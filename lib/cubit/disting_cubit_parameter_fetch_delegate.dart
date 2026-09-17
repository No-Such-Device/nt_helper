part of 'disting_cubit.dart';

class _ParameterFetchDelegate {
  _ParameterFetchDelegate(this._cubit);

  final DistingCubit _cubit;

  /// Concurrency limit for per-parameter calls.
  /// Tune this — 4-6 usually keeps the module happy without stalling.
  static const int kParallel = 4;

  // Background retry queue for failed parameter requests
  final List<_ParameterRetryRequest> _parameterRetryQueue = [];

  // Semaphore to ensure retry queue has lower priority than active commands
  int _activeCommandCount = 0;
  final _commandSemaphore = Completer<void>();

  bool get hasQueuedRetries => _parameterRetryQueue.isNotEmpty;

  // Background retry for failed parameter requests
  void _queueParameterRetry(_ParameterRetryRequest request) {
    _parameterRetryQueue.add(request);
  }

  // Acquire semaphore for active commands (blocks retry queue)
  void acquireCommandSemaphore() {
    _activeCommandCount++;
    if (_activeCommandCount == 1) {}
  }

  // Release semaphore for active commands (allows retry queue)
  void releaseCommandSemaphore() {
    _activeCommandCount--;
    if (_activeCommandCount == 0) {
      if (!_commandSemaphore.isCompleted) {
        _commandSemaphore.complete();
      }
    }
    if (_activeCommandCount < 0) {
      _activeCommandCount = 0;
    }
  }

  // Wait for semaphore to be available (no active commands)
  Future<void> _waitForCommandSemaphore() async {
    while (_activeCommandCount > 0) {
      final completer = Completer<void>();
      if (_activeCommandCount == 0) break;

      // Wait for active commands to complete or timeout after reasonable period
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 5)),
        // Timeout to prevent deadlock
      ]);

      // Brief yield to check again
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // Process the retry queue in the background with low priority
  Future<void> processParameterRetryQueue(IDistingMidiManager disting) async {
    if (_parameterRetryQueue.isEmpty) return;

    final retryList = List.from(_parameterRetryQueue);
    _parameterRetryQueue.clear();

    // Add initial delay to let any pending operations complete
    await Future.delayed(const Duration(seconds: 2));

    for (int i = 0; i < retryList.length; i++) {
      final request = retryList[i];

      // Wait for semaphore - only proceed when no active commands
      await _waitForCommandSemaphore();

      try {
        // Longer delay between retries to maintain low priority
        await Future.delayed(const Duration(milliseconds: 500));

        // Periodically yield to event loop for longer pauses to allow user operations
        if (i > 0 && i % 3 == 0) {
          await Future.delayed(const Duration(seconds: 1));
        }

        // Wait again before the actual retry request to ensure no commands started
        await _waitForCommandSemaphore();

        // Additional micro-yield to event loop before each request
        await Future.delayed(Duration.zero);

        switch (request.type) {
          case _ParameterRetryType.info:
            final info = await disting.requestParameterInfo(
              request.slotIndex,
              request.paramIndex,
            );
            if (info != null) {
              await _cubit._slotStateDelegate.updateSlotParameterInfo(
                request.slotIndex,
                request.paramIndex,
                info,
              );
            }
            break;
          case _ParameterRetryType.enumStrings:
            final enums = await disting.requestParameterEnumStrings(
              request.slotIndex,
              request.paramIndex,
            );
            if (enums != null) {
              await _cubit._slotStateDelegate.updateSlotParameterEnums(
                request.slotIndex,
                request.paramIndex,
                enums,
              );
            }
            break;
          case _ParameterRetryType.mappings:
            final mappings = await disting.requestMappings(
              request.slotIndex,
              request.paramIndex,
            );
            if (mappings != null) {
              await _cubit._slotStateDelegate.updateSlotParameterMappings(
                request.slotIndex,
                request.paramIndex,
                mappings,
              );
            }
            break;
          case _ParameterRetryType.valueStrings:
            final valueStrings = await disting.requestParameterValueString(
              request.slotIndex,
              request.paramIndex,
            );
            if (valueStrings != null) {
              await _cubit._slotStateDelegate.updateSlotParameterValueStrings(
                request.slotIndex,
                request.paramIndex,
                valueStrings,
              );
            }
            break;
        }
      } catch (e) {
        // Add extra delay after failures to avoid overwhelming the device
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int completed, int total)? onSlotProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    _diag('fetchSlots start total=$numAlgorithmsInPreset parallelSlots=false');

    int completedCount = 0;
    final slots = <Slot>[];
    for (
      var algorithmIndex = 0;
      algorithmIndex < numAlgorithmsInPreset;
      algorithmIndex++
    ) {
      final slotStopwatch = Stopwatch()..start();
      _diag('fetchSlots slot=$algorithmIndex queued');
      try {
        final slot = await fetchSlot(disting, algorithmIndex);
        completedCount++;
        _diag(
          'fetchSlots slot=$algorithmIndex done completed=$completedCount/'
          '$numAlgorithmsInPreset elapsed=${slotStopwatch.elapsedMilliseconds}ms',
        );
        onSlotProgress?.call(completedCount, numAlgorithmsInPreset);
        slots.add(slot);
      } catch (e) {
        completedCount++;
        _diag(
          'fetchSlots slot=$algorithmIndex failed '
          'elapsed=${slotStopwatch.elapsedMilliseconds}ms error=$e',
        );
        onSlotProgress?.call(completedCount, numAlgorithmsInPreset);
        slots.add(_errorSlot(algorithmIndex));
      }
    }

    _diag(
      'fetchSlots done total=$numAlgorithmsInPreset '
      'elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    return slots;
  }

  Future<Slot> fetchSlot(
    IDistingMidiManager disting,
    int algorithmIndex,
  ) async {
    final slotStopwatch = Stopwatch()..start();
    _diag('fetchSlot[$algorithmIndex] start');

    /* ------------------------------------------------------------------ *
   * 1-2.  Pages  |  #Parameters  |  Algorithm GUID  |  All Values      *
   * ------------------------------------------------------------------ */
    // Fetch essential info first (these usually don't timeout)
    final essentialStopwatch = Stopwatch()..start();
    _diag('fetchSlot[$algorithmIndex] essentials start');
    final essentialResults = await Future.wait([
      disting.requestNumberOfParameters(algorithmIndex),
      disting.requestAlgorithmGuid(algorithmIndex),
    ]);

    final numParametersResult = essentialResults[0] as NumParameters?;
    final numParams = numParametersResult?.numParameters ?? 0;
    final parameterCountFromDevice =
        numParametersResult?.algorithmIndex == algorithmIndex;
    final guid = essentialResults[1] as Algorithm?;
    final pageResult = await _fetchParameterPagesWithMetadataFallback(
      disting,
      algorithmIndex,
      guid,
    );
    final pages = pageResult.pages;
    _diag(
      'fetchSlot[$algorithmIndex] essentials done '
      'pages=${pages.pages.length} numParams=$numParams '
      'guid=${guid?.guid ?? 'null'} '
      'elapsed=${essentialStopwatch.elapsedMilliseconds}ms',
    );

    final currentState = _cubit.state;
    final firmware = currentState is DistingStateSynchronized
        ? currentState.firmwareVersion
        : _cubit._lastKnownFirmwareVersion;

    // Try to get parameter values with retry and longer timeout
    List<ParameterValue> allValues;
    var allValuesFailed = false;
    var parameterValuesFromDevice = false;
    try {
      final valuesStopwatch = Stopwatch()..start();
      _diag('fetchSlot[$algorithmIndex] allValues start');
      final paramValuesResult = await disting.requestAllParameterValues(
        algorithmIndex,
      );
      parameterValuesFromDevice =
          paramValuesResult?.algorithmIndex == algorithmIndex;
      allValues =
          paramValuesResult?.values ??
          List<ParameterValue>.generate(
            numParams,
            (_) => ParameterValue.filler(),
          );
      _diag(
        'fetchSlot[$algorithmIndex] allValues done count=${allValues.length} '
        'elapsed=${valuesStopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      _diag('fetchSlot[$algorithmIndex] allValues failed error=$e retrying');
      try {
        // Retry with a longer timeout - give it more time to respond
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // Brief pause before retry
        final retryValuesStopwatch = Stopwatch()..start();
        final retryResult = await disting.requestAllParameterValues(
          algorithmIndex,
        );
        parameterValuesFromDevice =
            retryResult?.algorithmIndex == algorithmIndex;
        allValues =
            retryResult?.values ??
            List<ParameterValue>.generate(
              numParams,
              (_) => ParameterValue.filler(),
            );
        _diag(
          'fetchSlot[$algorithmIndex] allValues retry done '
          'count=${allValues.length} '
          'elapsed=${retryValuesStopwatch.elapsedMilliseconds}ms',
        );
      } catch (retryError) {
        _diag(
          'fetchSlot[$algorithmIndex] allValues retry failed '
          'error=$retryError using fillers',
        );
        allValuesFailed = true;
        allValues = List<ParameterValue>.generate(
          numParams,
          (_) => ParameterValue.filler(),
        );
      }
    }

    if (pageResult.usedMetadataFallback && allValuesFailed) {
      final metadataSlot = await _metadataBackedSlot(
        algorithmIndex,
        guid,
        pages,
        numParams,
        allValues,
      );
      if (metadataSlot != null) {
        _diag(
          'fetchSlot[$algorithmIndex] metadata slot used '
          'elapsed=${slotStopwatch.elapsedMilliseconds}ms',
        );
        return metadataSlot;
      }
    }

    /* Visible-parameter set (built from pages) */
    final visible = pages.pages.expand((p) => p.parameters).toSet();

    /* ------------------------------------------------------------------ *
   * 3. Parameter-info phase (throttled)                                *
   * ------------------------------------------------------------------ */
    final parameters = List<ParameterInfo>.filled(
      numParams,
      ParameterInfo.filler(),
    );
    final infoStopwatch = Stopwatch()..start();
    _diag('fetchSlot[$algorithmIndex] parameterInfo start count=$numParams');
    await _forEachLimited(Iterable<int>.generate(numParams), (param) async {
      try {
        final info = await disting.requestParameterInfo(algorithmIndex, param);
        parameters[param] = info ?? ParameterInfo.filler();
        if (info == null) {
          _queueParameterRetry(
            _ParameterRetryRequest(
              slotIndex: algorithmIndex,
              paramIndex: param,
              type: _ParameterRetryType.info,
            ),
          );
        }
      } catch (e) {
        parameters[param] = ParameterInfo.filler();
        _queueParameterRetry(
          _ParameterRetryRequest(
            slotIndex: algorithmIndex,
            paramIndex: param,
            type: _ParameterRetryType.info,
          ),
        );
      }
    });
    _diag(
      'fetchSlot[$algorithmIndex] parameterInfo done '
      'elapsed=${infoStopwatch.elapsedMilliseconds}ms',
    );

    /* Pre-calculate which params are enumerated / mappable / string */
    bool isEnum(int i) => parameters[i].unit == 1;
    bool isString(int i) =>
        ParameterEditorRegistry.isStringTypeUnit(parameters[i].unit);
    bool isMappable(int i) => parameters[i].unit != -1;

    /* ------------------------------------------------------------------ *
   * 4. Enums, Mappings, Value-Strings  (all throttled in parallel)     *
   * ------------------------------------------------------------------ */
    final enums = List<ParameterEnumStrings>.filled(
      numParams,
      ParameterEnumStrings.filler(),
    );
    final mappings = List<Mapping>.filled(numParams, Mapping.filler());
    final valueStrings = List<ParameterValueString>.filled(
      numParams,
      ParameterValueString.filler(),
    );

    // Skip enum strings for known buggy algorithm/parameter combinations
    // Macro Oscillator (maco) param 1 (Model) causes firmware to send truncated
    // SysEx that can corrupt the MIDI stream
    bool shouldSkipEnumStrings(int param) {
      return firmware?.isExactly('1.12.0') == true &&
          guid?.guid == 'maco' &&
          param == 1;
    }

    final enumCount = Iterable<int>.generate(numParams)
        .where(
          (i) => visible.contains(i) && isEnum(i) && !shouldSkipEnumStrings(i),
        )
        .length;
    final mappingCount = Iterable<int>.generate(
      numParams,
    ).where((i) => visible.contains(i) && isMappable(i)).length;
    final valueStringCount = Iterable<int>.generate(
      numParams,
    ).where((i) => visible.contains(i) && isString(i)).length;
    final optionalStopwatch = Stopwatch()..start();
    _diag(
      'fetchSlot[$algorithmIndex] optionalDetails start '
      'enums=$enumCount mappings=$mappingCount valueStrings=$valueStringCount',
    );
    await Future.wait([
      // Enums
      _forEachLimited(
        Iterable<int>.generate(numParams).where(
          (i) => visible.contains(i) && isEnum(i) && !shouldSkipEnumStrings(i),
        ),
        (param) async {
          try {
            final enumResult = await disting.requestParameterEnumStrings(
              algorithmIndex,
              param,
            );
            enums[param] = enumResult ?? ParameterEnumStrings.filler();
            if (enumResult == null) {
              _queueParameterRetry(
                _ParameterRetryRequest(
                  slotIndex: algorithmIndex,
                  paramIndex: param,
                  type: _ParameterRetryType.enumStrings,
                ),
              );
            }
          } catch (e) {
            enums[param] = ParameterEnumStrings.filler();
            _queueParameterRetry(
              _ParameterRetryRequest(
                slotIndex: algorithmIndex,
                paramIndex: param,
                type: _ParameterRetryType.enumStrings,
              ),
            );
          }
        },
      ),
      // Mappings
      _forEachLimited(
        Iterable<int>.generate(
          numParams,
        ).where((i) => visible.contains(i) && isMappable(i)),
        (param) async {
          try {
            final mappingResult = await disting.requestMappings(
              algorithmIndex,
              param,
            );
            mappings[param] = mappingResult ?? Mapping.filler();
            if (mappingResult == null) {
              _queueParameterRetry(
                _ParameterRetryRequest(
                  slotIndex: algorithmIndex,
                  paramIndex: param,
                  type: _ParameterRetryType.mappings,
                ),
              );
            }
          } catch (e) {
            mappings[param] = Mapping.filler();
            _queueParameterRetry(
              _ParameterRetryRequest(
                slotIndex: algorithmIndex,
                paramIndex: param,
                type: _ParameterRetryType.mappings,
              ),
            );
          }
        },
      ),
      // Value strings - fire-and-forget, no retries
      // String-type parameters may not respond (depends on unit type and firmware).
      // We accept null gracefully rather than retrying, matching reference implementation.
      _forEachLimited(
        Iterable<int>.generate(
          numParams,
        ).where((i) => visible.contains(i) && isString(i)),
        (param) async {
          try {
            final valueStringResult = await disting.requestParameterValueString(
              algorithmIndex,
              param,
            );
            valueStrings[param] =
                valueStringResult ?? ParameterValueString.filler();
            // No retry - some string-type params don't respond
          } catch (e) {
            valueStrings[param] = ParameterValueString.filler();
            // No retry on exception either
          }
        },
      ),
    ]);
    _diag(
      'fetchSlot[$algorithmIndex] optionalDetails done '
      'elapsed=${optionalStopwatch.elapsedMilliseconds}ms',
    );

    /* ------------------------------------------------------------------ *
   * 5. Assemble the Slot                                               *
   * ------------------------------------------------------------------ */

    final outputModeParamNumbers = <int>{};
    for (final param in parameters) {
      if (param.isOutputMode && param.parameterNumber >= 0) {
        outputModeParamNumbers.add(param.parameterNumber);
      }
    }

    final hasAddReplaceEnum = enums.any(
      (paramEnums) =>
          paramEnums.values.contains('Add') &&
          paramEnums.values.contains('Replace'),
    );

    if (outputModeParamNumbers.isEmpty && hasAddReplaceEnum) {
      throw StateError(
        'Output mode parameters missing ioFlags; fallback is not permitted.',
      );
    }

    final outputModeMap = <int, List<int>>{};
    if (outputModeParamNumbers.isNotEmpty) {
      final outputUsageStopwatch = Stopwatch()..start();
      _diag(
        'fetchSlot[$algorithmIndex] outputModeUsage start '
        'count=${outputModeParamNumbers.length}',
      );
      await _forEachLimited(outputModeParamNumbers, (paramNumber) async {
        try {
          final outputModeUsage = await disting.requestOutputModeUsage(
            algorithmIndex,
            paramNumber,
          );
          if (outputModeUsage != null) {
            outputModeMap[outputModeUsage.parameterNumber] =
                outputModeUsage.affectedParameterNumbers;
          }
        } catch (e) {
          // Output mode usage is optional; ignore failures.
        }
      });
      _diag(
        'fetchSlot[$algorithmIndex] outputModeUsage done '
        'elapsed=${outputUsageStopwatch.elapsedMilliseconds}ms',
      );
    }

    if (outputModeMap.isNotEmpty) {
      _cubit._slotStateDelegate.setOutputModeUsageMapForSlot(
        algorithmIndex,
        outputModeMap,
      );
    }

    if (outputModeMap.isNotEmpty) {
      final outputValuesStopwatch = Stopwatch()..start();
      _diag(
        'fetchSlot[$algorithmIndex] outputModeValues start '
        'count=${outputModeMap.length}',
      );
      await _forEachLimited(outputModeMap.keys, (paramNumber) async {
        if (paramNumber < 0 || paramNumber >= allValues.length) {
          return;
        }
        try {
          final value = await disting.requestParameterValue(
            algorithmIndex,
            paramNumber,
          );
          if (value != null) {
            allValues[paramNumber] = value;
          }
        } catch (e) {
          // Output mode values are optional; ignore failures.
        }
      });
      _diag(
        'fetchSlot[$algorithmIndex] outputModeValues done '
        'elapsed=${outputValuesStopwatch.elapsedMilliseconds}ms',
      );
    }

    // A fresh slot fetch defines the current parameter shape. Do not carry
    // output-mode relationships from the previous shape when the device
    // returns none for the refreshed slot.
    final resolvedOutputModeMap = outputModeMap;

    final slot = Slot(
      algorithm:
          guid ??
          Algorithm(
            algorithmIndex: algorithmIndex,
            guid: 'ERROR',
            name: 'Error fetching Algorithm',
          ),
      pages: pages,
      parameters: parameters,
      values: allValues,
      enums: enums,
      mappings: mappings,
      valueStrings: valueStrings,
      routing: RoutingInfo.filler(), // unchanged – still skipped
      parameterCountFromDevice: parameterCountFromDevice,
      parameterPagesFromDevice: !pageResult.usedMetadataFallback,
      parameterValuesFromDevice: parameterValuesFromDevice,
      outputModeMap: resolvedOutputModeMap,
    );
    _diag(
      'fetchSlot[$algorithmIndex] done '
      'elapsed=${slotStopwatch.elapsedMilliseconds}ms',
    );
    return slot;
  }

  Future<_ParameterPagesFetchResult> _fetchParameterPagesWithMetadataFallback(
    IDistingMidiManager disting,
    int algorithmIndex,
    Algorithm? algorithm,
  ) async {
    try {
      final pages = await disting.requestParameterPages(algorithmIndex);
      if (pages != null) {
        return _ParameterPagesFetchResult(pages, usedMetadataFallback: false);
      }
      _diag('fetchSlot[$algorithmIndex] pages returned null; using metadata');
    } catch (e) {
      _diag('fetchSlot[$algorithmIndex] pages failed error=$e using metadata');
    }

    final fallback = await _metadataPagesForAlgorithm(
      algorithmIndex,
      algorithm,
    );
    if (fallback != null) {
      _diag(
        'fetchSlot[$algorithmIndex] metadata pages used '
        'guid=${algorithm?.guid ?? 'null'} pages=${fallback.pages.length}',
      );
      return _ParameterPagesFetchResult(fallback, usedMetadataFallback: true);
    }

    return _ParameterPagesFetchResult(
      ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
      usedMetadataFallback: true,
    );
  }

  Future<ParameterPages?> _metadataPagesForAlgorithm(
    int algorithmIndex,
    Algorithm? algorithm,
  ) async {
    final guid = algorithm?.guid;
    if (guid == null || guid.isEmpty) return null;

    final details = await _cubit._metadataDao.getFullAlgorithmDetails(guid);
    if (details == null || details.parameterPages.isEmpty) return null;

    return ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: details.parameterPages.map((pageWithItems) {
        return ParameterPage(
          name: pageWithItems.page.name,
          parameters: pageWithItems.parameterNumbers,
        );
      }).toList(),
    );
  }

  Future<Slot?> _metadataBackedSlot(
    int algorithmIndex,
    Algorithm? algorithm,
    ParameterPages pages,
    int numParams,
    List<ParameterValue> values,
  ) async {
    final details = await _fullMetadataForAlgorithm(algorithm);
    if (details == null) return null;

    final parameters = List<ParameterInfo>.filled(
      numParams,
      ParameterInfo.filler(),
    );
    for (final item in details.parameters) {
      final entry = item.parameter;
      if (entry.parameterNumber < 0 || entry.parameterNumber >= numParams) {
        continue;
      }
      parameters[entry.parameterNumber] = ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: entry.parameterNumber,
        min: entry.minValue ?? 0,
        max: entry.maxValue ?? 0,
        defaultValue: entry.defaultValue ?? 0,
        unit: entry.rawUnitIndex ?? 0,
        name: entry.name,
        powerOfTen: entry.powerOfTen ?? 0,
        ioFlags: entry.ioFlags ?? 0,
      );
    }

    final enums = List<ParameterEnumStrings>.filled(
      numParams,
      ParameterEnumStrings.filler(),
    );
    for (final MapEntry(key: parameterNumber, value: enumValues)
        in details.enums.entries) {
      if (parameterNumber < 0 || parameterNumber >= numParams) continue;
      enums[parameterNumber] = ParameterEnumStrings(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        values: enumValues,
      );
    }

    return Slot(
      algorithm:
          algorithm ??
          Algorithm(
            algorithmIndex: algorithmIndex,
            guid: details.algorithm.guid,
            name: details.algorithm.name,
          ),
      pages: pages,
      parameters: parameters,
      values: values,
      enums: enums,
      mappings: List<Mapping>.filled(numParams, Mapping.filler()),
      valueStrings: List<ParameterValueString>.filled(
        numParams,
        ParameterValueString.filler(),
      ),
      routing: RoutingInfo.filler(),
      outputModeMap: const {},
    );
  }

  Future<FullAlgorithmDetails?> _fullMetadataForAlgorithm(
    Algorithm? algorithm,
  ) async {
    final guid = algorithm?.guid;
    if (guid == null || guid.isEmpty) return null;

    return _cubit._metadataDao.getFullAlgorithmDetails(guid);
  }

  /* ---------------------------------------------------------------------- *
 * Helper – run tasks with a concurrency cap                              *
 * ---------------------------------------------------------------------- */

  /// Runs [worker] for every element in [items], but never more than
  /// [parallel] tasks are in-flight at once.
  ///
  /// Uses a "batch" strategy: kick off up to [parallel] futures,
  /// `await Future.wait`, then move on to the next batch.  Simpler and
  /// avoids the need for isCompleted / whenComplete gymnastics.
  Future<void> _forEachLimited<T>(
    Iterable<T> items,
    Future<void> Function(T) worker, {
    int parallel = kParallel,
  }) async {
    final iterator = items.iterator;

    while (true) {
      // Collect up to [parallel] tasks for this batch.
      final batch = <Future<void>>[];
      for (var i = 0; i < parallel && iterator.moveNext(); i++) {
        batch.add(worker(iterator.current));
      }

      if (batch.isEmpty) break; // no more work
      await Future.wait(batch); // wait for the batch to finish
    }
  }

  Slot _errorSlot(int algorithmIndex) {
    return Slot(
      algorithm: Algorithm(
        algorithmIndex: algorithmIndex,
        guid: 'ERROR',
        name: 'Error fetching Algorithm',
      ),
      pages: ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
      parameters: const [],
      values: const [],
      enums: const [],
      mappings: const [],
      valueStrings: const [],
      routing: RoutingInfo.filler(),
      outputModeMap: const {},
    );
  }

  void _diag(String message) {
    debugPrint('[NT_DIAG fetch ${DateTime.now().toIso8601String()}] $message');
  }
}

class _ParameterPagesFetchResult {
  final ParameterPages pages;
  final bool usedMetadataFallback;

  const _ParameterPagesFetchResult(
    this.pages, {
    required this.usedMetadataFallback,
  });
}
