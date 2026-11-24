part of 'disting_cubit.dart';

class _StateHelpersDelegate {
  _StateHelpersDelegate(this._cubit);

  final DistingCubit _cubit;

  void ensureCvRoutingOrderChangeSafe({int? fromSlot, int? toSlot}) {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) return;
    final taps =
        _cubit.ntx8cvRouting?.protectedBuses(state.deviceIoProfile) ?? <int>{};
    final writers = <int, Set<int>>{};
    final readers = <int, Set<int>>{};
    final replaceWriters = <int, Set<int>>{};
    for (var i = 0; i < state.slots.length && taps.isNotEmpty; i++) {
      final slotRouting = routing.AlgorithmRouting.fromSlot(
        state.slots[i],
        deviceIoProfile: state.deviceIoProfile,
      );
      final disabled = {
        for (final value in state.slots[i].values)
          if (value.isDisabled) value.parameterNumber,
      };
      for (final port in [
        ...slotRouting.inputPorts,
        ...slotRouting.outputPorts,
      ]) {
        final bus = port.busValue;
        if (!port.isActive ||
            disabled.contains(port.parameterNumber) ||
            bus == null ||
            !taps.contains(bus)) {
          continue;
        }
        if (port.isBusWriter) {
          writers.putIfAbsent(bus, () => {}).add(i);
          if (port.outputMode == routing_port.OutputMode.replace) {
            replaceWriters.putIfAbsent(bus, () => {}).add(i);
          }
        } else if (port.isBusReader) {
          readers.putIfAbsent(bus, () => {}).add(i);
        }
      }
    }
    final hasMove = fromSlot != null && toSlot != null;
    final newPositions = List.generate(state.slots.length, (i) => i);
    if (hasMove) {
      if (fromSlot < 0 ||
          toSlot < 0 ||
          fromSlot >= state.slots.length ||
          toSlot >= state.slots.length) {
        throw StateError('Invalid routing move.');
      }
      final order = List.generate(state.slots.length, (i) => i);
      order.insert(toSlot, order.removeAt(fromSlot));
      for (var i = 0; i < order.length; i++) {
        newPositions[order[i]] = i;
      }
    }
    for (final bus in taps) {
      final busWriters = writers[bus] ?? <int>{};
      final replaces = replaceWriters[bus] ?? <int>{};
      final writerOrderChanged = busWriters.any(
        (writer) => busWriters.any(
          (other) =>
              writer < other &&
              (replaces.contains(writer) || replaces.contains(other)) &&
              (!hasMove || newPositions[writer] > newPositions[other]),
        ),
      );
      final readOrderChanged = (readers[bus] ?? <int>{}).any(
        (reader) => busWriters.any(
          (writer) =>
              writer != reader &&
              (!hasMove ||
                  (writer < reader) !=
                      (newPositions[writer] < newPositions[reader])),
        ),
      );
      if (writerOrderChanged || readOrderChanged) {
        throw StateError(
          'Reordering NTX-8CV bus writers or readers could change the expander output.',
        );
      }
    }
    // Raw user-directed moves keep their legacy path without configured CV.
    // The Module-input exception requires complete evidence when CV is known.
    if (!state.slots.any(
      (slot) => slot.mappings.any((m) => m.packedMappingData.cvInput > 0),
    )) {
      return;
    }
    final reason = cvRoutingOptimizationBlockReason(
      state.slots,
      profile: state.deviceIoProfile,
    );
    if (reason != null) throw StateError(reason);
  }

  Slot preserveKnownSlotSpecifications({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required int slotIndex,
    required Slot refreshedSlot,
  }) {
    if (!identical(previousState.disting, refreshedDisting) ||
        previousState.presetName != refreshedPresetName ||
        slotIndex < 0 ||
        slotIndex >= previousState.slots.length) {
      return refreshedSlot;
    }

    final previousSlot = previousState.slots[slotIndex];
    final previousSpecifications = previousSlot.algorithm.specifications;
    if (previousSlot.algorithm.algorithmIndex != slotIndex ||
        refreshedSlot.algorithm.algorithmIndex != slotIndex ||
        previousSlot.algorithm.guid != refreshedSlot.algorithm.guid ||
        previousSpecifications.isEmpty ||
        refreshedSlot.algorithm.hasAuthoritativeSpecifications ||
        refreshedSlot.algorithm.specifications.isNotEmpty) {
      return refreshedSlot;
    }

    if (const ListEquality<int>().equals(
      previousSpecifications,
      refreshedSlot.algorithm.specifications,
    )) {
      return refreshedSlot;
    }

    return refreshedSlot.copyWith(
      algorithm: refreshedSlot.algorithm.copyWith(
        specifications: List<int>.unmodifiable(previousSpecifications),
        hasAuthoritativeSpecifications: false,
      ),
    );
  }

  List<Slot> preserveKnownSlotSpecificationsForRefresh({
    required DistingStateSynchronized previousState,
    required IDistingMidiManager refreshedDisting,
    required String refreshedPresetName,
    required List<Slot> refreshedSlots,
  }) => [
    for (final (slotIndex, refreshedSlot) in refreshedSlots.indexed)
      preserveKnownSlotSpecifications(
        previousState: previousState,
        refreshedDisting: refreshedDisting,
        refreshedPresetName: refreshedPresetName,
        slotIndex: slotIndex,
        refreshedSlot: refreshedSlot,
      ),
  ];

  void restoreSlotSpecificationValues(
    Iterable<FullPresetSlot> sourceSlots, {
    required int startingSlotIndex,
    required IDistingMidiManager expectedDisting,
    required String expectedPresetName,
  }) {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized ||
        !identical(currentState.disting, expectedDisting) ||
        currentState.presetName != expectedPresetName) {
      return;
    }

    final updatedSlots = List<Slot>.from(currentState.slots);
    var changed = false;
    for (final (offset, sourceSlot) in sourceSlots.indexed) {
      if (sourceSlot.specificationValues.isEmpty) continue;
      final targetSlotIndex = startingSlotIndex + offset;
      if (targetSlotIndex < 0 || targetSlotIndex >= updatedSlots.length) {
        continue;
      }

      final targetSlot = updatedSlots[targetSlotIndex];
      if (targetSlot.algorithm.guid != sourceSlot.algorithm.guid ||
          targetSlot.algorithm.hasAuthoritativeSpecifications) {
        continue;
      }
      if (const ListEquality<int>().equals(
        targetSlot.algorithm.specifications,
        sourceSlot.specificationValues,
      )) {
        continue;
      }

      updatedSlots[targetSlotIndex] = targetSlot.copyWith(
        algorithm: targetSlot.algorithm.copyWith(
          specifications: List<int>.unmodifiable(
            sourceSlot.specificationValues,
          ),
          hasAuthoritativeSpecifications: false,
        ),
      );
      changed = true;
    }

    if (changed) {
      _cubit._emitState(currentState.copyWith(slots: updatedSlots));
    }
  }

  // Helper to fetch algorithm metadata for offline mode
  Future<List<AlgorithmInfo>> fetchOfflineAlgorithms() async {
    try {
      final allBasicAlgoEntries = await _cubit._metadataDao.getAllAlgorithms();
      final List<AlgorithmInfo> availableAlgorithmsInfo = [];

      final detailedFutures = allBasicAlgoEntries.map((basicEntry) async {
        return await _cubit._metadataDao.getFullAlgorithmDetails(
          basicEntry.guid,
        );
      }).toList();

      final detailedResults = await Future.wait(detailedFutures);

      for (final details in detailedResults.whereType<FullAlgorithmDetails>()) {
        availableAlgorithmsInfo.add(
          AlgorithmInfo(
            guid: details.algorithm.guid,
            name: details.algorithm.name,
            algorithmIndex: -1,
            specifications: details.specifications
                .map(
                  (specEntry) => Specification(
                    name: specEntry.name,
                    min: specEntry.minValue,
                    max: specEntry.maxValue,
                    defaultValue: specEntry.defaultValue,
                    type: specEntry.type,
                  ),
                )
                .toList(),
          ),
        );
      }
      availableAlgorithmsInfo.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return availableAlgorithmsInfo;
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      return []; // Return empty on error
    }
  }

  List<RoutingInformation> buildRoutingInformation() {
    switch (_cubit.state) {
      case DistingStateSynchronized syncstate:
        return syncstate.slots
            .where((slot) => slot.routing.algorithmIndex != -1)
            .map(
              (slot) => RoutingInformation(
                algorithmIndex: slot.routing.algorithmIndex,
                routingInfo: slot.routing.routingInfo,
                algorithmName: (slot.algorithm.name.isNotEmpty)
                    ? slot.algorithm.name
                    : syncstate.algorithms
                          .firstWhere(
                            (element) => element.guid == slot.algorithm.guid,
                          )
                          .name,
              ),
            )
            .toList();
      default:
        return [];
    }
  }

  bool isProgramParameter(
    DistingStateSynchronized state,
    int algorithmIndex,
    int parameterNumber,
  ) =>
      (state.slots[algorithmIndex].parameters[parameterNumber].name ==
          "Program") &&
      (("spin" == state.slots[algorithmIndex].algorithm.guid) ||
          ("lua " == state.slots[algorithmIndex].algorithm.guid));
}
