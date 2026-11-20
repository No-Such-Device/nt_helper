part of 'disting_cubit.dart';

class _MappingDelegate {
  _MappingDelegate(this._cubit) {
    _stateSubscription = _cubit.stream.listen(_handleStateChange);
  }

  final DistingCubit _cubit;
  static const _saveDebounce = Duration(seconds: 1);
  static const _verificationDelay = Duration(milliseconds: 100);
  static const _maxForegroundFailures = 4;
  static const _maxRetryDelay = Duration(seconds: 2);

  final Map<_MappingSaveKey, _PendingMappingSave> _pendingSaves = {};
  late final StreamSubscription<DistingState> _stateSubscription;
  bool _disposed = false;

  Future<void> saveMapping(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  ) {
    return _queueMappingSave(
      algorithmIndex,
      parameterNumber,
      data,
      immediate: false,
    );
  }

  Future<void> saveMappingImmediately(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  ) {
    return _queueMappingSave(
      algorithmIndex,
      parameterNumber,
      data,
      immediate: true,
    );
  }

  Future<void> _queueMappingSave(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data, {
    required bool immediate,
  }) {
    if (_disposed) {
      return Future.error(StateError('Mapping save coordinator is closed'));
    }

    final key = (
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
    );
    final entry = _pendingSaves.putIfAbsent(
      key,
      () => _PendingMappingSave(data),
    );
    final completer = Completer<void>();

    entry
      ..data = data
      ..failureCount = 0
      ..waitingForSynchronization = false
      ..waiters.add(completer);
    entry.revision++;

    if (!entry.writing) {
      _scheduleSave(key, entry, immediate ? Duration.zero : _saveDebounce);
    }

    return completer.future;
  }

  void _scheduleSave(
    _MappingSaveKey key,
    _PendingMappingSave entry,
    Duration delay,
  ) {
    entry.timer?.cancel();
    entry.timer = Timer(delay, () {
      entry.timer = null;
      unawaited(_drainSave(key));
    });
  }

  Future<void> _drainSave(_MappingSaveKey key) async {
    final entry = _pendingSaves[key];
    if (_disposed || entry == null || entry.writing) return;

    final state = _cubit.state;
    if (state is! DistingStateSynchronized) {
      entry.waitingForSynchronization = true;
      return;
    }

    entry
      ..waitingForSynchronization = false
      ..writing = true;

    while (!_disposed) {
      final revision = entry.revision;
      final requestedData = entry.data;

      try {
        final verified = await _writeAndVerify(key, requestedData);
        if (_disposed) return;

        if (verified == null) {
          entry.writing = false;
          if (_cubit.state is DistingStateSynchronized) {
            _scheduleSave(key, entry, Duration.zero);
          } else {
            entry.waitingForSynchronization = true;
          }
          return;
        }

        if (entry.revision != revision) {
          continue;
        }

        _applyVerifiedMapping(key, verified.data, verified.disting);
        entry.writing = false;
        _pendingSaves.remove(key);
        _completeWaiters(entry);
        return;
      } on UnsupportedError catch (error, stackTrace) {
        entry.writing = false;
        _pendingSaves.remove(key);
        _completeWaitersWithError(entry, error, stackTrace);
        return;
      } catch (error, stackTrace) {
        if (_disposed) return;
        if (entry.revision != revision) {
          continue;
        }

        entry.writing = false;
        entry.failureCount++;

        if (entry.failureCount >= _maxForegroundFailures) {
          _completeWaitersWithError(entry, error, stackTrace);
        }

        _scheduleSave(key, entry, _retryDelay(entry.failureCount));
        return;
      }
    }
  }

  Future<({PackedMappingData data, IDistingMidiManager disting})?>
  _writeAndVerify(_MappingSaveKey key, PackedMappingData requestedData) async {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) return null;

    if (_isExpressiveMidiType(requestedData.midiMappingType) &&
        !state.firmwareVersion.hasExpressiveMidiMapping) {
      throw UnsupportedError(
        'Pitch bend and channel pressure mappings require firmware 1.17 or newer',
      );
    }

    final normalizedData = _normalizeMappingForFirmware(requestedData, state);
    final disting = state.disting;

    await disting.requestSetMapping(
      key.algorithmIndex,
      key.parameterNumber,
      normalizedData,
    );
    await Future<void>.delayed(_verificationDelay);

    final actual = await disting.requestMappings(
      key.algorithmIndex,
      key.parameterNumber,
    );
    final after = _cubit.state;
    if (after is! DistingStateSynchronized ||
        !identical(after.disting, disting)) {
      return null;
    }
    if (actual == null ||
        !_editableMappingSettingsMatch(
          actual.packedMappingData,
          normalizedData,
        )) {
      throw StateError(
        'Mapping readback did not match the requested CV, MIDI, and i2c settings',
      );
    }

    return (data: normalizedData, disting: disting);
  }

  bool _editableMappingSettingsMatch(
    PackedMappingData actual,
    PackedMappingData expected,
  ) {
    // Performance-page assignments are sent and read through a separate
    // protocol. Compare exactly the three payloads requestSetMapping writes.
    return listEquals(
          actual.encodeCVPackedData(),
          expected.encodeCVPackedData(),
        ) &&
        listEquals(
          actual.encodeMIDIPackedData(),
          expected.encodeMIDIPackedData(),
        ) &&
        listEquals(
          actual.encodeI2CPackedData(),
          expected.encodeI2CPackedData(),
        );
  }

  Duration _retryDelay(int failureCount) {
    final exponent = (failureCount - 1).clamp(0, 4);
    final delay = _verificationDelay * (1 << exponent);
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  void _applyVerifiedMapping(
    _MappingSaveKey key,
    PackedMappingData data,
    IDistingMidiManager disting,
  ) {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized ||
        !identical(state.disting, disting)) {
      return;
    }

    var slots = state.slots;
    if (key.algorithmIndex >= 0 && key.algorithmIndex < slots.length) {
      final slot = slots[key.algorithmIndex];
      final mappings = [...slot.mappings];
      if (key.parameterNumber >= 0 && key.parameterNumber < mappings.length) {
        final existing = mappings[key.parameterNumber];
        mappings[key.parameterNumber] = Mapping(
          algorithmIndex: key.algorithmIndex,
          parameterNumber: key.parameterNumber,
          packedMappingData: data.copyWith(
            // requestSetMapping only writes CV, MIDI, and i2c data.
            perfPageIndex: existing.packedMappingData.perfPageIndex,
          ),
        );
      }
      slots = _cubit.updateSlot(key.algorithmIndex, slots, (slot) {
        return slot.copyWith(mappings: mappings);
      });
    }

    _cubit._emitState(state.copyWith(slots: slots, isDirty: true));
    _cubit._rebuildCcLookup();
  }

  void _completeWaiters(_PendingMappingSave entry) {
    for (final waiter in entry.waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    entry.waiters.clear();
  }

  void _completeWaitersWithError(
    _PendingMappingSave entry,
    Object error,
    StackTrace stackTrace,
  ) {
    for (final waiter in entry.waiters) {
      if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
    }
    entry.waiters.clear();
  }

  void _handleStateChange(DistingState state) {
    if (_disposed || state is! DistingStateSynchronized) return;

    for (final MapEntry(key: key, value: entry)
        in _pendingSaves.entries.toList()) {
      if (entry.waitingForSynchronization &&
          !entry.writing &&
          entry.timer == null) {
        entry.waitingForSynchronization = false;
        _scheduleSave(key, entry, Duration.zero);
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();

    final error = StateError('Mapping save coordinator was closed');
    final stackTrace = StackTrace.current;
    for (final entry in _pendingSaves.values) {
      entry.timer?.cancel();
      _completeWaitersWithError(entry, error, stackTrace);
    }
    _pendingSaves.clear();
  }

  PackedMappingData _normalizeMappingForFirmware(
    PackedMappingData data,
    DistingStateSynchronized state,
  ) {
    final isExpressive = _isExpressiveMidiType(data.midiMappingType);
    final supportsExpressiveMidiMapping =
        state.firmwareVersion.hasExpressiveMidiMapping;
    final supportsV8 =
        state.offline ||
        state.demo ||
        state.firmwareVersion.hasBypassAwareMappings;
    data.validateForFirmware(
      supportsV8 ? FirmwareVersion('1.20') : state.firmwareVersion,
    );
    final baseVersion = data.version < 1
        ? supportsExpressiveMidiMapping
              ? 7
              : 6
        : data.version;
    final version = isExpressive && supportsExpressiveMidiMapping
        ? (baseVersion == 8 && supportsV8 ? 8 : 7)
        : baseVersion
              .clamp(
                1,
                supportsV8
                    ? 8
                    : supportsExpressiveMidiMapping
                    ? 7
                    : 6,
              )
              .toInt();

    if (!isExpressive) {
      return data.copyWith(version: version);
    }

    return data.copyWith(midiCC: 0, isMidiRelative: false, version: version);
  }

  bool _isExpressiveMidiType(MidiMappingType type) {
    return type == MidiMappingType.pitchBend ||
        type == MidiMappingType.channelPressure;
  }

  /// Reorders multiple performance parameters by setting new perfPageIndex values.
  ///
  /// Takes a list of (slotIndex, parameterNumber, perfPageIndex) records
  /// and calls setPerformancePageMapping sequentially for each.
  Future<void> reorderPerformanceParameters(
    List<({int slotIndex, int parameterNumber, int perfPageIndex})> assignments,
  ) async {
    for (final assignment in assignments) {
      await setPerformancePageMapping(
        assignment.slotIndex,
        assignment.parameterNumber,
        assignment.perfPageIndex,
      );
    }
  }

  /// Sets the performance page assignment for a parameter.
  ///
  /// - [slotIndex]: Slot index (0-39)
  /// - [parameterNumber]: Parameter number within the algorithm
  /// - [perfPageIndex]: Performance page index (0-30, where 0 = not assigned)
  ///
  /// Uses optimistic update pattern:
  /// 1. Update local state immediately for instant UI feedback
  /// 2. Send update to hardware
  /// 3. Verify by reading back specific parameter mapping
  /// 4. If mismatch, hardware value wins and UI updates again
  Future<void> setPerformancePageMapping(
    int slotIndex,
    int parameterNumber,
    int perfPageIndex,
  ) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized) {
      return;
    }

    if (slotIndex >= currentState.slots.length) {
      return;
    }

    final disting = _cubit.requireDisting();

    // 1. Optimistic Update - Update local state immediately
    final slot = currentState.slots[slotIndex];

    if (parameterNumber >= slot.mappings.length) {
      return;
    }

    final originalMapping = slot.mappings[parameterNumber];
    final optimisticMapping = Mapping(
      algorithmIndex: slotIndex,
      parameterNumber: parameterNumber,
      packedMappingData: originalMapping.packedMappingData.copyWith(
        perfPageIndex: perfPageIndex,
      ),
    );

    // Emit optimistic state immediately for instant UI feedback
    _cubit._emitState(
      currentState.copyWith(
        slots: _cubit.updateSlot(slotIndex, currentState.slots, (slot) {
          return slot.copyWith(
            mappings: _cubit.replaceInList(
              slot.mappings,
              optimisticMapping,
              index: parameterNumber,
            ),
          );
        }),
        isDirty: true,
      ),
    );

    // 2. Send update to hardware (non-blocking)
    disting
        .setPerformancePageMapping(slotIndex, parameterNumber, perfPageIndex)
        .catchError((e, s) {
          debugPrintStack(stackTrace: s);
        });

    // 3. Verify by reading back the specific parameter mapping with retry
    const maxRetries = 4; // Try up to 4 times
    const baseDelay = Duration(milliseconds: 100);
    bool verified = false;

    for (int attempt = 0; attempt < maxRetries && !verified; attempt++) {
      try {
        // Exponential backoff: 100ms, 200ms, 400ms, 800ms
        final delay = baseDelay * (1 << attempt);
        await Future.delayed(delay);

        final actualMapping = await disting.requestMappings(
          slotIndex,
          parameterNumber,
        );

        if (actualMapping == null) {
          continue; // Retry
        }

        // 4. If hardware value differs from optimistic value, hardware wins
        if (actualMapping.packedMappingData.perfPageIndex !=
            optimisticMapping.packedMappingData.perfPageIndex) {
          // Check if this is the last attempt
          if (attempt == maxRetries - 1) {
            // Last attempt - accept hardware value as final

            // Update UI with actual hardware value
            final verificationState = _cubit.state;
            if (verificationState is DistingStateSynchronized) {
              _cubit._emitState(
                verificationState.copyWith(
                  slots: _cubit.updateSlot(slotIndex, verificationState.slots, (
                    slot,
                  ) {
                    return slot.copyWith(
                      mappings: _cubit.replaceInList(
                        slot.mappings,
                        actualMapping,
                        index: parameterNumber,
                      ),
                    );
                  }),
                ),
              );
            }
            verified = true;
          } else {
            // Not the last attempt - retry to see if hardware catches up
            continue;
          }
        } else {
          // Hardware matches optimistic value - success!
          verified = true;
        }
      } catch (e, stackTrace) {
        debugPrintStack(stackTrace: stackTrace);

        if (attempt == maxRetries - 1) {
          // Last attempt failed - log error
        }
      }
    }

    if (!verified) {
      // Revert to original mapping since we couldn't verify the change
      final revertState = _cubit.state;
      if (revertState is DistingStateSynchronized) {
        _cubit._emitState(
          revertState.copyWith(
            slots: _cubit.updateSlot(slotIndex, revertState.slots, (slot) {
              return slot.copyWith(
                mappings: _cubit.replaceInList(
                  slot.mappings,
                  originalMapping,
                  index: parameterNumber,
                ),
              );
            }),
          ),
        );
      }
    }
  }
}

typedef _MappingSaveKey = ({int algorithmIndex, int parameterNumber});

class _PendingMappingSave {
  _PendingMappingSave(this.data);

  PackedMappingData data;
  int revision = 0;
  int failureCount = 0;
  bool writing = false;
  bool waitingForSynchronization = false;
  Timer? timer;
  final List<Completer<void>> waiters = [];
}
