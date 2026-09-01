part of 'disting_cubit.dart';

class _SlotMaintenanceDelegate {
  _SlotMaintenanceDelegate(this._cubit);

  final DistingCubit _cubit;

  final Map<int, DateTime> _lastAnomalyRefreshAttempt = {};

  Slot fixAlgorithmIndex(Slot slot, int algorithmIndex) {
    // Run through all of the parts of the slot and replace the algorithm index
    // with the new one by manually constructing new objects.
    return Slot(
      algorithm: slot.algorithm.copyWith(algorithmIndex: algorithmIndex),
      routing: RoutingInfo(
        algorithmIndex: algorithmIndex,
        routingInfo: slot.routing.routingInfo,
      ),
      pages: ParameterPages(
        algorithmIndex: algorithmIndex,
        pages: slot.pages.pages,
      ),
      parameters: slot.parameters
          .map(
            (parameter) => ParameterInfo(
              algorithmIndex: algorithmIndex,
              parameterNumber: parameter.parameterNumber,
              min: parameter.min,
              max: parameter.max,
              defaultValue: parameter.defaultValue,
              unit: parameter.unit,
              name: parameter.name,
              powerOfTen: parameter.powerOfTen,
              ioFlags: parameter.ioFlags,
            ),
          )
          .toList(),
      values: slot.values
          .map(
            (value) => ParameterValue(
              algorithmIndex: algorithmIndex,
              parameterNumber: value.parameterNumber,
              value: value.value,
              isDisabled: value.isDisabled,
            ),
          )
          .toList(),
      enums: slot.enums
          .map(
            (enums) => ParameterEnumStrings(
              algorithmIndex: algorithmIndex,
              parameterNumber: enums.parameterNumber,
              values: enums.values,
            ),
          )
          .toList(),
      mappings: slot.mappings
          .map(
            (mapping) => Mapping(
              algorithmIndex: algorithmIndex,
              parameterNumber: mapping.parameterNumber,
              packedMappingData: mapping.packedMappingData,
            ),
          )
          .toList(),
      valueStrings: slot.valueStrings
          .map(
            (valueStrings) => ParameterValueString(
              algorithmIndex: algorithmIndex,
              parameterNumber: valueStrings.parameterNumber,
              value: valueStrings.value,
            ),
          )
          .toList(),
      outputModeMap: slot.outputModeMap,
    );
  }

  Future<void> refreshSlot(int algorithmIndex) async {
    final syncState = _cubit.state;
    if (syncState is! DistingStateSynchronized) {
      return;
    }

    try {
      final disting = syncState.disting;
      final Slot updatedSlot = await _cubit.fetchSlot(disting, algorithmIndex);
      final currentState = _cubit.state;
      if (!identical(currentState, syncState) ||
          currentState is! DistingStateSynchronized ||
          algorithmIndex >= currentState.slots.length) {
        return;
      }
      final newSlots = List<Slot>.from(currentState.slots);
      newSlots[algorithmIndex] = _cubit._preserveKnownSlotSpecifications(
        previousState: syncState,
        refreshedDisting: disting,
        refreshedPresetName: syncState.presetName,
        slotIndex: algorithmIndex,
        refreshedSlot: updatedSlot,
      );
      _cubit._emitState(currentState.copyWith(slots: newSlots));
      _cubit._rebuildCcLookup();
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> refreshSlotAfterAnomaly(int algorithmIndex) async {
    await Future.delayed(const Duration(seconds: 1));

    final syncState = _cubit.state;
    if (syncState is! DistingStateSynchronized) {
      return;
    }

    final now = DateTime.now();
    final lastAttempt = _lastAnomalyRefreshAttempt[algorithmIndex];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 10)) {
      return;
    }
    _lastAnomalyRefreshAttempt[algorithmIndex] = now;

    try {
      final disting = syncState.disting;
      final Slot updatedSlot = await _cubit.fetchSlot(disting, algorithmIndex);
      final currentState = _cubit.state;
      if (!identical(currentState, syncState) ||
          currentState is! DistingStateSynchronized ||
          algorithmIndex >= currentState.slots.length) {
        return;
      }
      final newSlots = List<Slot>.from(currentState.slots);
      newSlots[algorithmIndex] = _cubit._preserveKnownSlotSpecifications(
        previousState: syncState,
        refreshedDisting: disting,
        refreshedPresetName: syncState.presetName,
        slotIndex: algorithmIndex,
        refreshedSlot: updatedSlot,
      );
      _cubit._emitState(currentState.copyWith(slots: newSlots));
      _cubit._rebuildCcLookup();
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> resetOutputs(Slot slot, int outputIndex) async {
    final disting = _cubit.requireDisting();
    final state = _cubit.state;
    final profile = state is DistingStateSynchronized
        ? state.deviceIoProfile
        : DeviceIoProfile.distingLegacy;
    if (outputIndex < 0 ||
        (outputIndex != 0 && !profile.contains(outputIndex))) {
      return;
    }

    slot.parameters
        .where(
          (p) =>
              p.isOutput &&
              p.unit == 1 &&
              p.min == 0 &&
              profile.busesWithin(p.min, p.max).isNotEmpty &&
              outputIndex >= p.min &&
              outputIndex <= p.max,
        )
        .forEach(
          (p) => disting.setParameterValue(
            p.algorithmIndex,
            p.parameterNumber,
            outputIndex,
          ),
        );
    _cubit.refresh();
  }
}
