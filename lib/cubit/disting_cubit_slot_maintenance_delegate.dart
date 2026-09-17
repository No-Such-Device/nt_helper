part of 'disting_cubit.dart';

enum _SlotRefreshStatus { installed, skipped, incomplete }

final class _SlotHydrationExpectation {
  _SlotHydrationExpectation({
    required this.disting,
    required this.algorithmGuid,
    required List<int> specifications,
  }) : specifications = List<int>.unmodifiable(specifications);

  final IDistingMidiManager disting;
  final String algorithmGuid;
  final List<int> specifications;
}

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

  Future<_SlotRefreshStatus> refreshSlot(
    int algorithmIndex, {
    _SlotHydrationExpectation? expectation,
  }) async {
    final syncState = _cubit.state;
    if (syncState is! DistingStateSynchronized ||
        algorithmIndex < 0 ||
        algorithmIndex >= syncState.slots.length) {
      return _SlotRefreshStatus.skipped;
    }

    final disting = syncState.disting;
    if (expectation != null &&
        (!identical(disting, expectation.disting) ||
            !_matchesExpectedAlgorithm(
              syncState.slots[algorithmIndex].algorithm,
              algorithmIndex,
              expectation.algorithmGuid,
            ))) {
      return _SlotRefreshStatus.skipped;
    }

    try {
      final Slot updatedSlot = await _cubit.fetchSlot(disting, algorithmIndex);
      final currentState = _cubit.state;
      if (!identical(currentState, syncState) ||
          currentState is! DistingStateSynchronized ||
          algorithmIndex >= currentState.slots.length) {
        return _SlotRefreshStatus.skipped;
      }

      if (expectation != null &&
          !_isCompleteExpectedHydration(
            updatedSlot,
            algorithmIndex: algorithmIndex,
            firmwareVersion: currentState.firmwareVersion,
            expectation: expectation,
          )) {
        return _SlotRefreshStatus.incomplete;
      }

      final installedSlot = expectation == null
          ? _cubit._preserveKnownSlotSpecifications(
              previousState: syncState,
              refreshedDisting: disting,
              refreshedPresetName: syncState.presetName,
              slotIndex: algorithmIndex,
              refreshedSlot: updatedSlot,
            )
          : updatedSlot;
      final newSlots = List<Slot>.from(currentState.slots);
      newSlots[algorithmIndex] = installedSlot;
      _cubit._slotStateDelegate.setOutputModeUsageMapForSlot(
        algorithmIndex,
        installedSlot.outputModeMap,
      );
      _cubit._emitState(currentState.copyWith(slots: newSlots));
      _cubit._rebuildCcLookup();
      return _SlotRefreshStatus.installed;
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  bool _matchesExpectedAlgorithm(
    Algorithm algorithm,
    int algorithmIndex,
    String algorithmGuid,
  ) =>
      algorithm.algorithmIndex == algorithmIndex &&
      algorithm.guid == algorithmGuid;

  bool _isCompleteExpectedHydration(
    Slot slot, {
    required int algorithmIndex,
    required FirmwareVersion firmwareVersion,
    required _SlotHydrationExpectation expectation,
  }) {
    final algorithm = slot.algorithm;
    if (!_matchesExpectedAlgorithm(
          algorithm,
          algorithmIndex,
          expectation.algorithmGuid,
        ) ||
        !algorithm.hasAuthoritativeSpecifications ||
        !const ListEquality<int>().equals(
          algorithm.specifications,
          expectation.specifications,
        ) ||
        slot.pages.algorithmIndex != algorithmIndex) {
      return false;
    }

    final parameterCount = slot.parameters.length;
    if (slot.values.length != parameterCount ||
        slot.enums.length != parameterCount ||
        slot.mappings.length != parameterCount ||
        slot.valueStrings.length != parameterCount) {
      return false;
    }

    final visibleParameters = slot.pages.pages
        .expand((page) => page.parameters)
        .toSet();
    if (visibleParameters.any(
      (parameterNumber) =>
          parameterNumber < 0 || parameterNumber >= parameterCount,
    )) {
      return false;
    }

    for (var index = 0; index < parameterCount; index++) {
      final parameter = slot.parameters[index];
      final value = slot.values[index];
      if (parameter.algorithmIndex != algorithmIndex ||
          parameter.parameterNumber != index ||
          value.algorithmIndex != algorithmIndex ||
          value.parameterNumber != index) {
        return false;
      }

      final isVisible = visibleParameters.contains(index);
      final enumIsRequired =
          isVisible &&
          parameter.unit == 1 &&
          !(firmwareVersion.isExactly('1.12.0') &&
              algorithm.guid == 'maco' &&
              index == 1);
      final enumStrings = slot.enums[index];
      if (enumIsRequired &&
          (enumStrings.algorithmIndex != algorithmIndex ||
              enumStrings.parameterNumber != index)) {
        return false;
      }

      final mappingIsRequired = isVisible && parameter.unit != -1;
      final mapping = slot.mappings[index];
      if (mappingIsRequired &&
          (mapping.algorithmIndex != algorithmIndex ||
              mapping.parameterNumber != index)) {
        return false;
      }

      final valueString = slot.valueStrings[index];
      final hasValueStringCoordinates =
          valueString.algorithmIndex == algorithmIndex &&
          valueString.parameterNumber == index;
      final isOptionalValueStringFiller =
          valueString.algorithmIndex == -1 && valueString.parameterNumber == -1;
      if (!hasValueStringCoordinates && !isOptionalValueStringFiller) {
        return false;
      }
    }

    for (final entry in slot.outputModeMap.entries) {
      if (entry.key < 0 ||
          entry.key >= parameterCount ||
          entry.value.any(
            (parameterNumber) =>
                parameterNumber < 0 || parameterNumber >= parameterCount,
          )) {
        return false;
      }
    }

    return true;
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
