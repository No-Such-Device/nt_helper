part of 'disting_cubit.dart';

mixin _DistingCubitPresetOps on _DistingCubitBase {
  CancelableOperation<void>? _renamePresetVerificationOperation;

  Future<void> newPresetImpl() async {
    final currentState = state;
    if (currentState is DistingStateSynchronized) {
      final disting = requireDisting();
      await disting.requestNewPreset();
      _forgetSlotSpecificationsAfterPresetReplacement(disting);
      await _refreshStateFromManager();
    }
  }

  Future<void> loadPresetImpl(String name, bool append) async {
    final currentState = state;
    if (currentState is DistingStateSynchronized) {
      // Prevent online load preset when offline
      if (currentState.offline) {
        return;
      }
      final disting = requireDisting();

      emit(currentState.copyWith(loading: true));

      await disting.requestLoadPreset(name, append);

      if (!append) {
        _forgetSlotSpecificationsAfterPresetReplacement(disting);
      }

      await _refreshStateFromManager();
    }
  }

  void _forgetSlotSpecificationsAfterPresetReplacement(
    IDistingMidiManager disting,
  ) {
    final currentState = state;
    if (currentState is! DistingStateSynchronized ||
        !identical(currentState.disting, disting)) {
      return;
    }
    emit(
      currentState.copyWith(
        slots: [
          for (final slot in currentState.slots)
            slot.copyWith(
              algorithm: slot.algorithm.copyWith(specifications: const []),
            ),
        ],
      ),
    );
  }

  Future<void> renamePresetImpl(String newName) async {
    final currentState = state;
    if (currentState is! DistingStateSynchronized) return;

    final trimmed = newName.trim();
    // 1. Basic validation: no empty names, and no-op if name is unchanged
    if (trimmed.isEmpty || trimmed == currentState.presetName) return;

    // 2. Hardware limit: max 31 chars (plus null terminator).
    // We truncate to ensure the hardware doesn't reject or behave unpredictably.
    final finalName = trimmed.length > 31 ? trimmed.substring(0, 31) : trimmed;

    // 3. Final check: if truncation resulted in the same name, skip the write.
    if (finalName == currentState.presetName) return;

    // Optimistic update
    emit(currentState.copyWith(presetName: finalName, isDirty: true));

    final disting = currentState.disting;
    try {
      await disting.requestSetPresetName(finalName);
      await disting.requestSavePreset();
    } catch (_) {
      // Reconcile the optimistic state with device truth after a failed write.
      _renamePresetVerificationOperation?.cancel();
      _renamePresetVerificationOperation = CancelableOperation.fromFuture(
        Future.delayed(const Duration(milliseconds: 250), () async {
          final syncState = state;
          if (syncState is! DistingStateSynchronized) return;
          final actual = await disting.requestPresetName();
          final latestState = state;
          if (actual != null &&
              latestState is DistingStateSynchronized &&
              latestState.presetName != actual) {
            emit(latestState.copyWith(presetName: actual));
          }
        }),
        onCancel: () {},
      );
      rethrow;
    }

    // Verification loop to ensure the name actually took
    _renamePresetVerificationOperation?.cancel();
    _renamePresetVerificationOperation = CancelableOperation.fromFuture(
      Future.delayed(const Duration(milliseconds: 500), () async {
        final syncState = state;
        if (syncState is! DistingStateSynchronized) return;
        final actual = await disting.requestPresetName();
        final latestState = state;
        if (actual != null &&
            latestState is DistingStateSynchronized &&
            latestState.presetName != actual) {
          emit(latestState.copyWith(presetName: actual));
        }
      }),
      onCancel: () {},
    );
  }
}
