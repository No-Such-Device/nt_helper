part of 'disting_cubit.dart';

/// A lightweight snapshot of a slot's parameter values.
class _SlotSnapshot {
  final String algorithmGuid;
  final Map<int, int> parameterValues;

  _SlotSnapshot({required this.algorithmGuid, required this.parameterValues});
}

/// A point-in-time snapshot of the preset state that can be restored.
class PresetCheckpoint {
  final String presetName;
  final String? label;
  final DateTime createdAt;
  final List<_SlotSnapshot> _slots;

  PresetCheckpoint._({
    required this.presetName,
    required this.label,
    required this.createdAt,
    required this._slots,
  });

  int get slotCount => _slots.length;
}

class _CheckpointDelegate {
  _CheckpointDelegate(this._cubit);

  final DistingCubit _cubit;

  static const int _maxCheckpoints = 10;
  final List<PresetCheckpoint> _checkpoints = [];

  List<PresetCheckpoint> get checkpoints => List.unmodifiable(_checkpoints);

  /// Create a checkpoint from the current synchronized state.
  /// Returns the checkpoint, or null if state is not synchronized.
  PresetCheckpoint? createCheckpoint({String? label}) {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) return null;

    final slots = <_SlotSnapshot>[];
    for (final slot in state.slots) {
      final paramValues = <int, int>{};
      for (final v in slot.values) {
        paramValues[v.parameterNumber] = v.value;
      }
      slots.add(
        _SlotSnapshot(
          algorithmGuid: slot.algorithm.guid,
          parameterValues: paramValues,
        ),
      );
    }

    final checkpoint = PresetCheckpoint._(
      presetName: state.presetName,
      label: label,
      createdAt: DateTime.now(),
      slots: slots,
    );

    _checkpoints.add(checkpoint);

    // Evict oldest if over limit
    while (_checkpoints.length > _maxCheckpoints) {
      _checkpoints.removeAt(0);
    }

    return checkpoint;
  }

  /// Validate that a checkpoint's algorithm lineup matches current state.
  /// Returns null if valid, or an error message if not.
  String? _validateCheckpoint(
    PresetCheckpoint checkpoint,
    DistingStateSynchronized state,
  ) {
    if (checkpoint._slots.length != state.slots.length) {
      return 'Checkpoint has ${checkpoint._slots.length} slots but '
          'current preset has ${state.slots.length}';
    }
    for (int i = 0; i < checkpoint._slots.length; i++) {
      if (checkpoint._slots[i].algorithmGuid != state.slots[i].algorithm.guid) {
        return 'Slot $i algorithm changed: '
            '${checkpoint._slots[i].algorithmGuid} → '
            '${state.slots[i].algorithm.guid}';
      }
    }
    return null;
  }

  /// Restore a checkpoint by writing all differing parameter values back.
  /// Returns the number of parameters restored, or -1 on failure.
  /// [onProgress] is called with (completed, total) counts.
  Future<int> restoreCheckpoint(
    PresetCheckpoint checkpoint, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) return -1;

    final error = _validateCheckpoint(checkpoint, state);
    if (error != null) return -1;

    // Collect all parameter diffs
    final writes = <({int slotIndex, int paramNum, int value})>[];
    for (int i = 0; i < checkpoint._slots.length; i++) {
      final snapshot = checkpoint._slots[i];
      final currentSlot = state.slots[i];

      for (final entry in snapshot.parameterValues.entries) {
        // Skip parameters that no longer exist in the current slot
        if (entry.key >= currentSlot.parameters.length) continue;

        // Skip values outside the current parameter's valid range to avoid
        // triggering anomaly-driven slot refreshes during restore
        final paramInfo = currentSlot.parameters[entry.key];
        if (entry.value < paramInfo.min || entry.value > paramInfo.max) {
          continue;
        }

        final currentValue = currentSlot.values
            .where((v) => v.parameterNumber == entry.key)
            .firstOrNull
            ?.value;
        if (currentValue != entry.value) {
          writes.add((slotIndex: i, paramNum: entry.key, value: entry.value));
        }
      }
    }

    if (writes.isEmpty) return 0;

    // Write all diffs
    var completed = 0;
    onProgress?.call(0, writes.length);

    for (final write in writes) {
      await _cubit.updateParameterValue(
        algorithmIndex: write.slotIndex,
        parameterNumber: write.paramNum,
        value: write.value,
        userIsChangingTheValue: false,
      );
      completed++;
      onProgress?.call(completed, writes.length);
    }

    return completed;
  }

  /// Remove a specific checkpoint.
  void removeCheckpoint(PresetCheckpoint checkpoint) {
    _checkpoints.remove(checkpoint);
  }

  /// Clear all checkpoints.
  void clearCheckpoints() {
    _checkpoints.clear();
  }
}
