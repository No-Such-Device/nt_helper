part of 'disting_cubit.dart';

mixin _DistingCubitSlotOps on _DistingCubitBase {
  final Map<int, CancelableOperation<void>> _renameSlotVerificationOperations =
      {};
  final Map<int, CancelableOperation<void>> _visualStyleVerificationOperations =
      {};

  void renameSlotImpl(int algorithmIndex, String newName) async {
    final currentState = state;
    if (currentState is DistingStateSynchronized) {
      if (algorithmIndex < 0 || algorithmIndex >= currentState.slots.length) {
        return;
      }

      final trimmed = newName.trim();
      if (trimmed.isEmpty) return;

      final slot = currentState.slots[algorithmIndex];
      final currentAlgorithm = slot.algorithm;
      if (trimmed == currentAlgorithm.name) return;

      // 1) Optimistic update for instant UI response
      final optimisticAlgorithm = Algorithm(
        algorithmIndex: currentAlgorithm.algorithmIndex,
        guid: currentAlgorithm.guid,
        name: trimmed,
        specifications: currentAlgorithm.specifications,
        visualStyle: currentAlgorithm.visualStyle,
      );
      final optimisticSlots = updateSlot(
        algorithmIndex,
        currentState.slots,
        (s) => s.copyWith(algorithm: optimisticAlgorithm),
      );
      emit(
        currentState.copyWith(
          slots: optimisticSlots,
          loading: false,
          isDirty: true,
        ),
      );

      // 2) Send request in background
      final disting = requireDisting();
      disting.requestSendSlotName(algorithmIndex, trimmed).catchError((e, s) {
        // If send fails, let the verification pass reconcile state.
      });

      // 3) Verification: read back just this slot's Algorithm and correct if needed.
      _renameSlotVerificationOperations[algorithmIndex]?.cancel();
      _renameSlotVerificationOperations[algorithmIndex] =
          CancelableOperation.fromFuture(
            Future.delayed(const Duration(milliseconds: 750), () async {
              if (isClosed || state is! DistingStateSynchronized) return;
              final verificationState = state as DistingStateSynchronized;

              // Only proceed if the slot still exists and still matches our optimistic edit.
              if (algorithmIndex < 0 ||
                  algorithmIndex >= verificationState.slots.length) {
                return;
              }

              final currentSlot = verificationState.slots[algorithmIndex];
              if (currentSlot.algorithm.guid != currentAlgorithm.guid) return;
              if (currentSlot.algorithm.name != trimmed) return;

              final actual = await disting.requestAlgorithmGuid(algorithmIndex);
              if (actual == null) return;
              if (isClosed || !identical(state, verificationState)) return;

              // If the device accepted it, the name should match. Otherwise, correct locally.
              if (actual.name != trimmed) {
                final correctedSlot = _preserveKnownSlotSpecifications(
                  previousState: verificationState,
                  refreshedDisting: disting,
                  refreshedPresetName: verificationState.presetName,
                  slotIndex: algorithmIndex,
                  refreshedSlot: currentSlot.copyWith(algorithm: actual),
                );
                final correctedSlots = updateSlot(
                  algorithmIndex,
                  verificationState.slots,
                  (s) => correctedSlot,
                );
                emit(
                  verificationState.copyWith(
                    slots: correctedSlots,
                    isDirty: true,
                  ),
                );
              }
            }),
            onCancel: () {},
          );
    }
  }

  Future<void> setAlgorithmVisualStyleImpl(
    int algorithmIndex,
    AlgorithmVisualStyle style,
  ) async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return;
    if (currentState.offline ||
        !currentState.firmwareVersion.hasAlgorithmVisualStyle) {
      throw UnsupportedError(
        'Algorithm visual styling requires connected firmware 1.18 or newer',
      );
    }
    if (algorithmIndex < 0 || algorithmIndex >= currentState.slots.length) {
      return;
    }

    final originalAlgorithm = currentState.slots[algorithmIndex].algorithm;
    if (originalAlgorithm.visualStyle == style) return;

    final disting = requireDisting();
    await disting.requestSetAlgorithmVisualStyle(algorithmIndex, style);

    final stateAfterWrite = state;
    if (stateAfterWrite is! DistingStateSynchronized ||
        !identical(stateAfterWrite.disting, disting) ||
        algorithmIndex >= stateAfterWrite.slots.length ||
        stateAfterWrite.slots[algorithmIndex].algorithm.guid !=
            originalAlgorithm.guid) {
      return;
    }

    final optimisticSlots = updateSlot(
      algorithmIndex,
      stateAfterWrite.slots,
      (slot) =>
          slot.copyWith(algorithm: slot.algorithm.copyWith(visualStyle: style)),
    );
    emit(stateAfterWrite.copyWith(slots: optimisticSlots, isDirty: true));

    _visualStyleVerificationOperations[algorithmIndex]?.cancel();
    _visualStyleVerificationOperations[algorithmIndex] =
        CancelableOperation.fromFuture(
          Future.delayed(const Duration(milliseconds: 250), () async {
            if (isClosed) return;
            final beforeRead = state;
            if (beforeRead is! DistingStateSynchronized ||
                !identical(beforeRead.disting, disting) ||
                algorithmIndex >= beforeRead.slots.length) {
              return;
            }
            final beforeReadAlgorithm =
                beforeRead.slots[algorithmIndex].algorithm;
            if (beforeReadAlgorithm.guid != originalAlgorithm.guid ||
                beforeReadAlgorithm.visualStyle != style) {
              return;
            }

            Algorithm? actual;
            try {
              actual = await disting.requestAlgorithmGuid(algorithmIndex);
            } catch (_) {
              return;
            }
            if (actual == null ||
                actual.guid != originalAlgorithm.guid ||
                actual.visualStyle == null ||
                actual.visualStyle == style) {
              return;
            }
            if (isClosed) return;

            final afterRead = state;
            if (afterRead is! DistingStateSynchronized ||
                !identical(afterRead.disting, disting) ||
                algorithmIndex >= afterRead.slots.length) {
              return;
            }
            final currentAlgorithm = afterRead.slots[algorithmIndex].algorithm;
            if (currentAlgorithm.guid != originalAlgorithm.guid ||
                currentAlgorithm.visualStyle != style) {
              return;
            }

            final correctedSlots = updateSlot(
              algorithmIndex,
              afterRead.slots,
              (slot) => slot.copyWith(
                algorithm: slot.algorithm.copyWith(
                  visualStyle: actual!.visualStyle,
                ),
              ),
            );
            emit(afterRead.copyWith(slots: correctedSlots, isDirty: true));
          }),
          onCancel: () {},
        );
  }
}
