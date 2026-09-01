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
  CancelableOperation<void>? _moveVerificationOperation;

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
                fetched.algorithm.guid == placeholder.algorithm.guid
                ? fetched.copyWith(
                    algorithm: fetched.algorithm.copyWith(
                      specifications: placeholder.algorithm.specifications,
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
