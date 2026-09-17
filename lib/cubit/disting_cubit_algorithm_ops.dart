part of 'disting_cubit.dart';

const algorithmAddFailedMessage =
    'The algorithm did not appear. Something went wrong.';
const algorithmAddBypassFailedMessage =
    'Algorithm added, but bypass could not be enabled.';

class AlgorithmAddFailedException implements Exception {
  const AlgorithmAddFailedException();

  @override
  String toString() => algorithmAddFailedMessage;
}

class AlgorithmAddBypassFailedException implements Exception {
  const AlgorithmAddBypassFailedException();

  @override
  String toString() => algorithmAddBypassFailedMessage;
}

mixin _DistingCubitAlgorithmOps on _DistingCubitBase {
  static const _bypassParameterNumber = 0;
  static const _bypassEnabledValue = 1;
  static const _addAlgorithmInitialSettleDelay = Duration(seconds: 1);
  static const _addAlgorithmPollInterval = Duration(seconds: 1);
  static const _addAlgorithmRequestTimeout = Duration(seconds: 1);
  static const _addAlgorithmVerificationWindow = Duration(seconds: 10);
  static const _respecificationInitialSettleDelay = Duration(seconds: 1);
  static const _respecificationPollInterval = Duration(seconds: 1);
  static const _respecificationRequestTimeout = Duration(seconds: 1);
  static const _respecificationVerificationWindow = Duration(seconds: 10);
  static const _respecificationRequestMaxRetries = 1;
  CancelableOperation<void>? _moveVerificationOperation;
  Future<AlgorithmRespecificationStatus>? _respecificationOperation;
  _RespecificationLifetime? _activeRespecificationLifetime;

  void _cancelRespecificationForConnectionChange() {
    _activeRespecificationLifetime?.cancellation.cancel();
  }

  void _invalidateRespecificationForState(DistingState nextState) {
    final lifetime = _activeRespecificationLifetime;
    if (lifetime != null && !lifetime.matches(nextState)) {
      lifetime.cancellation.cancel();
    }
  }

  bool _isCurrentRespecificationLifetime(_RespecificationLifetime lifetime) =>
      identical(_activeRespecificationLifetime, lifetime) &&
      lifetime.matches(state);

  _RespecificationLifetime? _respecificationLifetimeForSlot(
    IDistingMidiManager disting,
    int slotIndex,
  ) {
    final lifetime = _activeRespecificationLifetime;
    if (lifetime == null ||
        !identical(lifetime.disting, disting) ||
        lifetime.slotIndex != slotIndex) {
      return null;
    }
    return lifetime;
  }

  DistingStateSynchronized _requireRespecificationState() {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) {
      throw const AlgorithmRespecificationException(
        'Respecify requires a connected, synchronized device.',
      );
    }
    if (currentState.offline || currentState.demo) {
      throw const AlgorithmRespecificationException(
        'Respecify is unavailable in offline and demo modes.',
      );
    }
    if (!currentState.firmwareVersion.isSupported(
      ownerProvidedRespecifyMinimumFirmwareVersion,
    )) {
      throw const AlgorithmRespecificationException(
        'Respecify requires confirmed firmware 1.19 beta or later.',
      );
    }
    if (currentState.disting is! AlgorithmRespecificationWriter) {
      throw const AlgorithmRespecificationException(
        'Respecify requires a live MIDI connection.',
      );
    }
    return currentState;
  }

  bool _isSigned16(int value) => value >= -0x8000 && value <= 0x7FFF;

  PreparedAlgorithmRespecification _prepareAlgorithmRespecification(
    DistingStateSynchronized currentState,
    int slotIndex,
  ) {
    if (slotIndex < 0 ||
        slotIndex >= currentState.slots.length ||
        slotIndex > 0x7F) {
      throw AlgorithmRespecificationException(
        'Slot ${slotIndex + 1} is unavailable for respecification.',
      );
    }

    final algorithm = currentState.slots[slotIndex].algorithm;
    if (algorithm.algorithmIndex != slotIndex || algorithm.guid.isEmpty) {
      throw const AlgorithmRespecificationException(
        'The selected slot identity is inconsistent.',
      );
    }
    if (!algorithm.hasAuthoritativeSpecifications) {
      throw const AlgorithmRespecificationException(
        'Current specification values are unavailable from the device.',
      );
    }

    final matchingMetadata = currentState.algorithms
        .where((candidate) => candidate.guid == algorithm.guid)
        .toList(growable: false);
    if (matchingMetadata.length != 1) {
      throw const AlgorithmRespecificationException(
        'Matching algorithm specification metadata is unavailable.',
      );
    }

    final metadata = matchingMetadata.single.specifications;
    final currentValues = algorithm.specifications;
    if (metadata.length != currentValues.length || metadata.length > 0x7F) {
      throw const AlgorithmRespecificationException(
        'Algorithm specification metadata does not match the current slot.',
      );
    }

    final prepared = <PreparedAlgorithmSpecification>[];
    for (var index = 0; index < metadata.length; index++) {
      final specification = metadata[index];
      final currentValue = currentValues[index];
      final hasValidSignedValues =
          _isSigned16(specification.min) &&
          _isSigned16(specification.max) &&
          _isSigned16(specification.defaultValue) &&
          _isSigned16(currentValue);
      final hasConsistentRange =
          specification.min <= specification.max &&
          specification.defaultValue >= specification.min &&
          specification.defaultValue <= specification.max &&
          currentValue >= specification.min &&
          currentValue <= specification.max;
      if (!hasValidSignedValues || !hasConsistentRange) {
        throw AlgorithmRespecificationException(
          'Specification ${index + 1} metadata is inconsistent.',
        );
      }
      prepared.add(
        PreparedAlgorithmSpecification(
          metadata: specification,
          currentValue: currentValue,
        ),
      );
    }

    return PreparedAlgorithmRespecification(
      slotIndex: slotIndex,
      algorithmGuid: algorithm.guid,
      algorithmName: algorithm.name,
      specifications: prepared,
    );
  }

  PreparedAlgorithmRespecification prepareAlgorithmRespecificationImpl(
    int slotIndex,
  ) {
    final currentState = _requireRespecificationState();
    return _prepareAlgorithmRespecification(currentState, slotIndex);
  }

  Future<AlgorithmRespecificationStatus> respecifyAlgorithmImpl(
    int slotIndex,
    List<Object?> proposedSpecifications,
  ) {
    if (_respecificationOperation != null) {
      return Future<AlgorithmRespecificationStatus>.error(
        const AlgorithmRespecificationException(
          'A respecification is already pending verification.',
        ),
      );
    }

    late final Future<AlgorithmRespecificationStatus> guardedOperation;
    guardedOperation = _runRespecification(slotIndex, proposedSpecifications)
        .whenComplete(() {
          if (identical(_respecificationOperation, guardedOperation)) {
            _respecificationOperation = null;
          }
        });
    _respecificationOperation = guardedOperation;
    return guardedOperation;
  }

  Future<AlgorithmRespecificationStatus> _runRespecification(
    int slotIndex,
    List<Object?> proposedSpecifications,
  ) async {
    final currentState = _requireRespecificationState();
    final preparation = _prepareAlgorithmRespecification(
      currentState,
      slotIndex,
    );
    if (proposedSpecifications.length != preparation.specifications.length) {
      throw const AlgorithmRespecificationException(
        'The proposed specification count does not match the current slot.',
      );
    }

    final values = <int>[];
    for (var index = 0; index < proposedSpecifications.length; index++) {
      final proposedValue = proposedSpecifications[index];
      if (proposedValue is! int) {
        throw AlgorithmRespecificationException(
          'Specification ${index + 1} must be an integer.',
        );
      }

      final metadata = preparation.specifications[index].metadata;
      if (!_isSigned16(proposedValue) ||
          proposedValue < metadata.min ||
          proposedValue > metadata.max) {
        throw AlgorithmRespecificationException(
          'Specification ${index + 1} must be between '
          '${metadata.min} and ${metadata.max}.',
        );
      }
      values.add(proposedValue);
    }

    final lifetime = _RespecificationLifetime(
      state: currentState,
      slotIndex: preparation.slotIndex,
      algorithmGuid: preparation.algorithmGuid,
    );
    _activeRespecificationLifetime = lifetime;
    final submittedValues = List<int>.unmodifiable(values);

    try {
      final sendCompleted = await _waitForRespecificationSend(
        currentState.disting.requestRespecifyAlgorithm(
          slotIndex,
          submittedValues,
        ),
        lifetime,
      );
      if (!sendCompleted || !_isCurrentRespecificationLifetime(lifetime)) {
        return AlgorithmRespecificationStatus.unverifiable;
      }

      final observation = await _observeRespecification(
        lifetime,
        submittedValues: submittedValues,
      );
      if (observation != AlgorithmRespecificationStatus.observedMatchingState) {
        return observation;
      }
      if (!_isCurrentRespecificationLifetime(lifetime)) {
        return AlgorithmRespecificationStatus.unverifiable;
      }

      final _SlotRefreshStatus refreshStatus;
      try {
        refreshStatus = await _refreshSlotWithResult(
          slotIndex,
          expectation: _SlotHydrationExpectation(
            lifetime: lifetime,
            specifications: submittedValues,
          ),
        );
      } catch (_) {
        return AlgorithmRespecificationStatus.refreshFailed;
      }

      switch (refreshStatus) {
        case _SlotRefreshStatus.skipped:
          return AlgorithmRespecificationStatus.refreshSkipped;
        case _SlotRefreshStatus.incomplete:
          return AlgorithmRespecificationStatus.refreshIncomplete;
        case _SlotRefreshStatus.installed:
          try {
            final refreshed = await _refreshRoutingForRespecification(lifetime);
            return refreshed
                ? AlgorithmRespecificationStatus.observedMatchingState
                : AlgorithmRespecificationStatus.refreshSkipped;
          } catch (_) {
            return AlgorithmRespecificationStatus.refreshFailed;
          }
      }
    } finally {
      lifetime.cancellation.cancel();
      _discardParameterRetriesForRespecification(lifetime);
      if (identical(_activeRespecificationLifetime, lifetime)) {
        _activeRespecificationLifetime = null;
      }
    }
  }

  Future<bool> _waitForRespecificationSend(
    Future<void> request,
    _RespecificationLifetime lifetime,
  ) async {
    if (!_isCurrentRespecificationLifetime(lifetime)) return false;

    final cancelled = Completer<bool>();
    final removeCancellationListener = lifetime.cancellation.addListener(() {
      if (!cancelled.isCompleted) cancelled.complete(false);
    });
    try {
      return await Future.any<bool>([
        request.then((_) => true),
        cancelled.future,
      ]);
    } finally {
      removeCancellationListener();
    }
  }

  Future<bool> _waitForRespecificationDelay(
    Duration delay,
    DistingRequestCancellation cancellation,
  ) {
    if (cancellation.isCancelled) return Future<bool>.value(false);

    final completer = Completer<bool>();
    late final Timer timer;
    void Function()? removeCancellationListener;

    void complete(bool elapsed) {
      if (completer.isCompleted) return;
      timer.cancel();
      removeCancellationListener?.call();
      completer.complete(elapsed);
    }

    timer = Timer(delay, () => complete(true));
    removeCancellationListener = cancellation.addListener(
      () => complete(false),
    );
    return completer.future;
  }

  Future<AlgorithmRespecificationStatus> _observeRespecification(
    _RespecificationLifetime lifetime, {
    required List<int> submittedValues,
  }) async {
    final cancellation = lifetime.cancellation;
    final deadlineTimer = Timer(
      _respecificationVerificationWindow,
      cancellation.cancel,
    );

    try {
      final settled = await _waitForRespecificationDelay(
        _respecificationInitialSettleDelay,
        cancellation,
      );
      if (!settled) return AlgorithmRespecificationStatus.unverifiable;

      while (!cancellation.isCancelled) {
        try {
          final readback = await lifetime.disting.requestAlgorithmGuid(
            lifetime.slotIndex,
            timeout: _respecificationRequestTimeout,
            maxRetries: _respecificationRequestMaxRetries,
            cancellation: cancellation,
            rejectAmbiguousResponse: true,
          );
          if (!_isCurrentRespecificationLifetime(lifetime)) {
            return AlgorithmRespecificationStatus.unverifiable;
          }

          final isFreshTargetState =
              readback != null &&
              readback.algorithmIndex == lifetime.slotIndex &&
              readback.guid == lifetime.algorithmGuid &&
              readback.hasAuthoritativeSpecifications;
          if (isFreshTargetState) {
            return const ListEquality<int>().equals(
                  readback.specifications,
                  submittedValues,
                )
                ? AlgorithmRespecificationStatus.observedMatchingState
                : AlgorithmRespecificationStatus.observedDifferingState;
          }
        } catch (_) {
          if (cancellation.isCancelled) {
            return AlgorithmRespecificationStatus.unverifiable;
          }
        }

        final pollDelayElapsed = await _waitForRespecificationDelay(
          _respecificationPollInterval,
          cancellation,
        );
        if (!pollDelayElapsed) {
          return AlgorithmRespecificationStatus.unverifiable;
        }
      }

      return AlgorithmRespecificationStatus.unverifiable;
    } finally {
      deadlineTimer.cancel();
    }
  }

  String _deriveOptimisticAlgorithmNameForAdd({
    required String algorithmGuid,
    required String baseName,
    required List<Slot> existingSlots,
  }) {
    final used = <int>{};

    for (final slot in existingSlots) {
      final a = slot.algorithm;
      if (a.guid != algorithmGuid) continue;

      if (a.name == baseName) {
        used.add(1);
        continue;
      }

      final match = RegExp(
        '^${RegExp.escape(baseName)}\\((\\d+)\\)\$',
      ).firstMatch(a.name);
      if (match == null) continue;
      final n = int.tryParse(match.group(1) ?? '');
      if (n != null && n >= 2) {
        used.add(n);
      }
    }

    if (!used.contains(1)) return baseName;

    var i = 2;
    while (used.contains(i)) {
      i++;
    }
    return '$baseName($i)';
  }

  Slot _createPlaceholderSlotForAdd({
    required int slotIndex,
    required AlgorithmInfo algorithm,
    required List<int> specificationValues,
    required List<Slot> existingSlots,
  }) {
    final displayName = _deriveOptimisticAlgorithmNameForAdd(
      algorithmGuid: algorithm.guid,
      baseName: algorithm.name,
      existingSlots: existingSlots,
    );

    return Slot(
      algorithm: Algorithm(
        algorithmIndex: slotIndex,
        guid: algorithm.guid,
        name: displayName,
        specifications: List<int>.unmodifiable(specificationValues),
      ),
      routing: RoutingInfo(
        algorithmIndex: slotIndex,
        routingInfo: List.filled(6, 0),
      ),
      pages: ParameterPages(algorithmIndex: slotIndex, pages: const []),
      parameters: const [],
      values: const [],
      enums: const [],
      mappings: const [],
      valueStrings: const [],
    );
  }

  Future<bool> _waitForAlgorithmSlotCountIncrease(
    IDistingMidiManager disting, {
    required int previousSlotCount,
  }) async {
    final deadlineReached = Completer<void>();
    var remainingSeconds = _addAlgorithmVerificationWindow.inSeconds;
    final countdown = Timer.periodic(_addAlgorithmPollInterval, (timer) {
      remainingSeconds--;
      if (remainingSeconds <= 0) {
        timer.cancel();
        deadlineReached.complete();
      }
    });

    try {
      await Future.any<void>([
        Future<void>.delayed(_addAlgorithmInitialSettleDelay),
        deadlineReached.future,
      ]);

      while (!deadlineReached.isCompleted) {
        try {
          final currentCount = await Future.any<int?>([
            disting.requestNumAlgorithmsInPreset(
              timeout: _addAlgorithmRequestTimeout,
              maxRetries: remainingSeconds > 0 ? remainingSeconds : 1,
            ),
            deadlineReached.future.then<int?>((_) => null),
          ]);
          if (deadlineReached.isCompleted) return false;
          if (currentCount != null && currentCount > previousSlotCount) {
            return true;
          }
        } catch (_) {
          if (deadlineReached.isCompleted) return false;
        }

        await Future.any<void>([
          Future<void>.delayed(_addAlgorithmPollInterval),
          deadlineReached.future,
        ]);
      }

      return false;
    } finally {
      countdown.cancel();
    }
  }

  bool _removeOptimisticAlgorithmPlaceholder({
    required DistingStateSynchronized previousState,
    required Slot expectedPlaceholder,
  }) {
    final st = state;
    if (st is! DistingStateSynchronized) return false;
    if (!identical(st.disting, previousState.disting)) return false;

    final previousSlotCount = previousState.slots.length;
    if (st.slots.length != previousSlotCount + 1) return false;

    if (st.slots[previousSlotCount] != expectedPlaceholder) return false;

    final retainedSlots = List<Slot>.from(st.slots)..removeLast();
    final hasOtherPresetChanges =
        st.presetName != previousState.presetName ||
        !const DeepCollectionEquality().equals(
          retainedSlots,
          previousState.slots,
        ) ||
        !const DeepCollectionEquality().equals(
          st.perfPageItems,
          previousState.perfPageItems,
        );
    emit(
      st.copyWith(
        slots: retainedSlots,
        loading: false,
        isDirty: previousState.isDirty || hasOtherPresetChanges,
      ),
    );
    _rebuildCcLookup();
    return true;
  }

  Future<void> onAlgorithmSelectedImpl(
    AlgorithmInfo algorithm,
    List<int> specifications, {
    bool addBypassed = false,
  }) async {
    switch (state) {
      case DistingStateInitial():
      case DistingStateSelectDevice():
      case DistingStateConnected():
        break;
      case DistingStateSynchronized syncstate:
        final disting = syncstate.disting;
        final specsToSend = List<int>.unmodifiable(specifications);

        // An algorithm can only be added to the next empty slot, so we can be
        // optimistic and only reconcile the newly-added slot.
        final newSlotIndex = syncstate.slots.length;

        // 1) Optimistic placeholder slot for instant UI feedback
        final placeholder = _createPlaceholderSlotForAdd(
          slotIndex: newSlotIndex,
          algorithm: algorithm,
          specificationValues: specsToSend,
          existingSlots: syncstate.slots,
        );
        emit(
          syncstate.copyWith(
            slots: [...syncstate.slots, placeholder],
            loading: false,
            isDirty: true,
          ),
        );

        // 2) Send the add algorithm request.
        try {
          await disting.requestAddAlgorithm(algorithm, specsToSend);
        } catch (_) {
          _removeOptimisticAlgorithmPlaceholder(
            previousState: syncstate,
            expectedPlaceholder: placeholder,
          );
          throw const AlgorithmAddFailedException();
        }

        var bypassFailed = false;
        if (addBypassed) {
          try {
            await _setNewAlgorithmBypassed(disting, newSlotIndex);
          } on AlgorithmAddBypassFailedException {
            bypassFailed = true;
          }
        }

        // 3) Give the module time to instantiate the algorithm, then verify
        // only that the preset slot count increased. Slot hydration is a
        // separate best-effort step and cannot turn a confirmed add into a
        // failure.
        final didAppear = await _waitForAlgorithmSlotCountIncrease(
          disting,
          previousSlotCount: syncstate.slots.length,
        );
        if (!didAppear) {
          _removeOptimisticAlgorithmPlaceholder(
            previousState: syncstate,
            expectedPlaceholder: placeholder,
          );
          throw const AlgorithmAddFailedException();
        }

        // 4) Hydrate the new slot once in the background. If its pages or
        // other details are malformed, keep the confirmed placeholder and let
        // a later manual refresh try again.
        unawaited(
          Future<void>.sync(() async {
            if (isClosed) return;
            final current = state;
            if (current is! DistingStateSynchronized) return;
            if (!identical(current.disting, disting)) return;
            if (current.slots.length <= newSlotIndex) return;
            if (current.slots[newSlotIndex] != placeholder) return;

            final Slot fetched;
            try {
              fetched = await fetchSlot(disting, newSlotIndex);
            } catch (_) {
              return;
            }

            if (isClosed) return;
            final verified = state;
            if (verified is! DistingStateSynchronized) return;
            if (!identical(verified.disting, disting)) return;
            if (verified.slots.length <= newSlotIndex) return;
            if (verified.slots[newSlotIndex] != placeholder) return;

            final hydrated =
                fetched.algorithm.guid == placeholder.algorithm.guid &&
                    !fetched.algorithm.hasAuthoritativeSpecifications
                ? fetched.copyWith(
                    algorithm: fetched.algorithm.copyWith(
                      specifications: placeholder.algorithm.specifications,
                      hasAuthoritativeSpecifications: false,
                    ),
                  )
                : fetched;
            final updatedSlots = updateSlot(
              newSlotIndex,
              verified.slots,
              (_) => hydrated,
            );
            emit(verified.copyWith(slots: updatedSlots, loading: false));
            _rebuildCcLookup();
          }),
        );
        if (bypassFailed) {
          throw const AlgorithmAddBypassFailedException();
        }
        break;
    }
  }

  Future<void> _setNewAlgorithmBypassed(
    IDistingMidiManager disting,
    int newSlotIndex,
  ) async {
    try {
      await disting.setParameterValue(
        newSlotIndex,
        _bypassParameterNumber,
        _bypassEnabledValue,
      );
    } catch (_) {
      throw const AlgorithmAddBypassFailedException();
    }
  }

  Future<void> onRemoveAlgorithmImpl(int algorithmIndex) async {
    switch (state) {
      case DistingStateInitial():
      case DistingStateSelectDevice():
      case DistingStateConnected():
        break;
      case DistingStateSynchronized syncstate:
        // Cancel any pending verification from a previous operation
        _moveVerificationOperation?.cancel();

        // 1. Optimistic Update - Remove the slot and fix indices
        List<Slot> optimisticSlots = List.from(syncstate.slots);
        optimisticSlots.removeAt(algorithmIndex);

        // Fix algorithm indices for all slots after the removed one
        for (int i = algorithmIndex; i < optimisticSlots.length; i++) {
          optimisticSlots[i] = _fixAlgorithmIndex(optimisticSlots[i], i);
        }

        // Emit optimistic state
        emit(
          syncstate.copyWith(
            slots: optimisticSlots,
            loading: false,
            isDirty: true,
          ),
        );

        _rebuildCcLookup();

        // 2. Manager Request
        final disting = requireDisting();
        // Don't await here, let it run in the background
        disting.requestRemoveAlgorithm(algorithmIndex).catchError((e, s) {
          // Refresh immediately on error
          _refreshStateFromManager(delay: Duration.zero);
        });

        // 3. Verification
        _moveVerificationOperation = CancelableOperation.fromFuture(
          Future.delayed(const Duration(seconds: 2), () async {
            // Check if state is still synchronized before proceeding
            if (isClosed || state is! DistingStateSynchronized) return;
            final verificationState = state as DistingStateSynchronized;

            // Only verify if the current state still matches the optimistic one we emitted
            final eq = const DeepCollectionEquality();
            if (!eq.equals(verificationState.slots, optimisticSlots)) {
              return;
            }

            try {
              // Check if the number of algorithms matches our optimistic state
              final actualNumAlgorithms =
                  await disting.requestNumAlgorithmsInPreset() ?? 0;
              if (isClosed) return;
              if (actualNumAlgorithms != optimisticSlots.length) {
                await _refreshStateFromManager(delay: Duration.zero);
                return;
              }

              // Verify GUIDs and Names for remaining slots
              bool mismatchDetected = false;
              for (int i = 0; i < optimisticSlots.length; i++) {
                final actualAlgorithm = await disting.requestAlgorithmGuid(i);
                if (isClosed) return;
                final optimisticAlgorithm = optimisticSlots[i].algorithm;

                if (actualAlgorithm == null ||
                    actualAlgorithm.guid != optimisticAlgorithm.guid ||
                    actualAlgorithm.name != optimisticAlgorithm.name) {
                  mismatchDetected = true;
                  break;
                }
              }

              if (mismatchDetected) {
                await _refreshStateFromManager(delay: Duration.zero);
              } else {}
            } catch (e, stackTrace) {
              debugPrintStack(stackTrace: stackTrace);
              if (!isClosed) {
                await _refreshStateFromManager(delay: Duration.zero);
              }
            }
          }),
          onCancel: () {},
        );
        break;
    }
  }

  Future<int> moveAlgorithmUpImpl(int algorithmIndex) async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return algorithmIndex;
    if (algorithmIndex == 0) return 0;

    // Cancel any pending verification from a previous move
    _moveVerificationOperation?.cancel();

    final syncstate = currentState;
    final slots = syncstate.slots;

    // 1. Optimistic Update
    // Identify the two slots involved in the swap
    final slotToMove = slots[algorithmIndex];
    final slotToSwapWith = slots[algorithmIndex - 1];

    // Create corrected versions with updated internal indices
    final correctedMovedSlot = _fixAlgorithmIndex(
      slotToMove,
      algorithmIndex - 1,
    );
    final correctedSwappedSlot = _fixAlgorithmIndex(
      slotToSwapWith,
      algorithmIndex,
    );

    // Build the new list with only the swapped slots corrected and reordered
    List<Slot> optimisticSlotsCorrected = List.from(slots); // Start with a copy
    optimisticSlotsCorrected[algorithmIndex - 1] =
        correctedMovedSlot; // Moved slot goes to the upper position
    optimisticSlotsCorrected[algorithmIndex] =
        correctedSwappedSlot; // Swapped slot goes to the lower position

    // Emit optimistic state
    emit(
      syncstate.copyWith(
        slots: optimisticSlotsCorrected,
        loading: false,
        isDirty: true,
      ),
    );

    _rebuildCcLookup();

    // 2. Manager Request
    final disting = requireDisting();
    // Don't await here, let it run in the background
    disting.requestMoveAlgorithmUp(algorithmIndex).catchError((e, s) {
      // Optionally trigger a full refresh on error?
      _refreshStateFromManager(delay: Duration.zero);
    });

    // 3. Verification
    _moveVerificationOperation = CancelableOperation.fromFuture(
      Future.delayed(const Duration(seconds: 2), () async {
        // Check if state is still synchronized before proceeding
        if (isClosed || state is! DistingStateSynchronized) return;
        final verificationState = state as DistingStateSynchronized;

        // Only verify if the current state *still* matches the optimistic one we emitted.
        // If it changed due to user interaction or another update, the verification is moot.
        // Use a deep equality check for the slots.
        final eq = const DeepCollectionEquality();
        if (!eq.equals(verificationState.slots, optimisticSlotsCorrected)) {
          return;
        }

        try {
          // --- Verification: Check GUIDs and Names ---
          bool mismatchDetected = false;
          for (int i = 0; i < optimisticSlotsCorrected.length; i++) {
            final actualAlgorithm = await disting.requestAlgorithmGuid(i);
            if (isClosed || !identical(state, verificationState)) return;
            final optimisticAlgorithm = optimisticSlotsCorrected[i].algorithm;

            // Compare GUID and Name
            if (actualAlgorithm == null ||
                actualAlgorithm.guid != optimisticAlgorithm.guid ||
                actualAlgorithm.name != optimisticAlgorithm.name) {
              mismatchDetected = true;
              break; // No need to check further
            }
          }
          // --- End Verification ---

          if (mismatchDetected) {
            // If mismatch, only fetch the actual slots, keep other metadata.
            final actualSlots = await fetchSlots(
              optimisticSlotsCorrected.length,
              disting,
            );
            if (isClosed || !identical(state, verificationState)) return;
            final preservedActualSlots =
                _preserveKnownSlotSpecificationsForRefresh(
                  previousState: verificationState,
                  refreshedDisting: disting,
                  refreshedPresetName: verificationState.presetName,
                  refreshedSlots: actualSlots,
                );

            emit(
              DistingState.synchronized(
                disting: verificationState.disting,
                // Keep manager and other state
                distingVersion: verificationState.distingVersion,
                firmwareVersion: verificationState.firmwareVersion,
                deviceIoProfile: verificationState.deviceIoProfile,
                presetName: verificationState.presetName,
                // Use existing preset name
                algorithms: verificationState.algorithms,
                slots: preservedActualSlots,
                // Use actual slots
                unitStrings: verificationState.unitStrings,
                inputDevice: verificationState.inputDevice,
                outputDevice: verificationState.outputDevice,
                screenshot: verificationState.screenshot,
                loading: false,
                demo: verificationState.demo,
                offline: verificationState.offline,
                isDirty: verificationState.isDirty,
              ),
            );
            _rebuildCcLookup();
          } else {}
        } catch (e, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);
          if (!isClosed) {
            _refreshStateFromManager(delay: Duration.zero);
          }
        }
      }),
      onCancel: () {},
    );

    // 4. Return optimistic index
    return algorithmIndex - 1;
  }

  Future<int> moveAlgorithmDownImpl(int algorithmIndex) async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return algorithmIndex;
    final syncstate = currentState;
    final slots = syncstate.slots;
    if (algorithmIndex >= slots.length - 1) return algorithmIndex;

    // Cancel any pending verification from a previous move
    _moveVerificationOperation?.cancel();

    // 1. Optimistic Update
    // Identify the two slots involved in the swap
    final slotToMove = slots[algorithmIndex];
    final slotToSwapWith = slots[algorithmIndex + 1];

    // Create corrected versions with updated internal indices
    final correctedMovedSlot = _fixAlgorithmIndex(
      slotToMove,
      algorithmIndex + 1,
    );
    final correctedSwappedSlot = _fixAlgorithmIndex(
      slotToSwapWith,
      algorithmIndex,
    );

    // Build the new list with only the swapped slots corrected and reordered
    List<Slot> optimisticSlotsCorrected = List.from(slots); // Start with a copy
    optimisticSlotsCorrected[algorithmIndex] =
        correctedSwappedSlot; // Swapped slot goes to the upper position
    optimisticSlotsCorrected[algorithmIndex + 1] =
        correctedMovedSlot; // Moved slot goes to the lower position

    // Emit optimistic state
    emit(
      syncstate.copyWith(
        slots: optimisticSlotsCorrected,
        loading: false,
        isDirty: true,
      ),
    );

    _rebuildCcLookup();

    // 2. Manager Request
    final disting = requireDisting();
    // Don't await here, let it run in the background
    disting.requestMoveAlgorithmDown(algorithmIndex).catchError((e, s) {
      _refreshStateFromManager(delay: Duration.zero);
    });

    // 3. Verification
    _moveVerificationOperation = CancelableOperation.fromFuture(
      Future.delayed(const Duration(seconds: 2), () async {
        if (isClosed || state is! DistingStateSynchronized) return;
        final verificationState = state as DistingStateSynchronized;

        final eq = const DeepCollectionEquality();
        if (!eq.equals(verificationState.slots, optimisticSlotsCorrected)) {
          return;
        }

        try {
          // --- Verification: Check GUIDs and Names ---
          bool mismatchDetected = false;
          for (int i = 0; i < optimisticSlotsCorrected.length; i++) {
            final actualAlgorithm = await disting.requestAlgorithmGuid(i);
            if (isClosed || !identical(state, verificationState)) return;
            final optimisticAlgorithm = optimisticSlotsCorrected[i].algorithm;

            // Compare GUID and Name
            if (actualAlgorithm == null ||
                actualAlgorithm.guid != optimisticAlgorithm.guid ||
                actualAlgorithm.name != optimisticAlgorithm.name) {
              mismatchDetected = true;
              break; // No need to check further
            }
          }
          // --- End Verification ---

          if (mismatchDetected) {
            // If mismatch, only fetch the actual slots, keep other metadata.
            final actualSlots = await fetchSlots(
              optimisticSlotsCorrected.length,
              disting,
            );
            if (isClosed || !identical(state, verificationState)) return;
            final preservedActualSlots =
                _preserveKnownSlotSpecificationsForRefresh(
                  previousState: verificationState,
                  refreshedDisting: disting,
                  refreshedPresetName: verificationState.presetName,
                  refreshedSlots: actualSlots,
                );

            emit(
              DistingState.synchronized(
                disting: verificationState.disting,
                // Keep manager and other state
                distingVersion: verificationState.distingVersion,
                firmwareVersion: verificationState.firmwareVersion,
                deviceIoProfile: verificationState.deviceIoProfile,
                presetName: verificationState.presetName,
                // Use existing preset name
                algorithms: verificationState.algorithms,
                slots: preservedActualSlots,
                // Use actual slots
                unitStrings: verificationState.unitStrings,
                inputDevice: verificationState.inputDevice,
                outputDevice: verificationState.outputDevice,
                screenshot: verificationState.screenshot,
                loading: false,
                demo: verificationState.demo,
                offline: verificationState.offline,
                isDirty: verificationState.isDirty,
              ),
            );
            _rebuildCcLookup();
          } else {}
        } catch (e, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);
          if (!isClosed) {
            _refreshStateFromManager(delay: Duration.zero);
          }
        }
      }),
      onCancel: () {},
    );

    // 4. Return optimistic index
    return algorithmIndex + 1;
  }
}
