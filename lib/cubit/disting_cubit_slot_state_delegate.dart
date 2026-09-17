part of 'disting_cubit.dart';

class _SlotStateDelegate {
  _SlotStateDelegate(this._cubit);

  final DistingCubit _cubit;

  // Output mode usage tracking
  // Maps slot index -> parameter number -> list of affected parameters
  final Map<int, Map<int, List<int>>> _outputModeUsageMap = {};

  // Track which output mode parameters we've already queried to avoid duplicates
  final Map<int, Set<int>> _queriedOutputModeParameters = {};

  Map<int, List<int>> outputModeMapForSlot(int slotIndex) {
    return _outputModeUsageMap[slotIndex] ?? const {};
  }

  void setOutputModeUsageMapForSlot(
    int slotIndex,
    Map<int, List<int>> outputModeMap,
  ) {
    _outputModeUsageMap[slotIndex] = outputModeMap;
    _queriedOutputModeParameters[slotIndex] = outputModeMap.keys.toSet();
  }

  Future<void> ensureOutputModeUsageFromDb({
    required int slotIndex,
    required String algorithmGuid,
  }) async {
    if (_outputModeUsageMap[slotIndex]?.isNotEmpty == true) {
      return;
    }

    try {
      final dbOutputModeUsage = await _cubit._metadataDao
          .getOutputModeUsageForAlgorithm(algorithmGuid);
      if (dbOutputModeUsage.isNotEmpty) {
        _outputModeUsageMap[slotIndex] = dbOutputModeUsage;
      }
    } catch (e) {
      // Silently ignore database errors - output mode is optional
    }
  }

  // State update methods for retry results
  Future<void> updateSlotParameterInfo(
    int slotIndex,
    int paramIndex,
    ParameterInfo info, {
    required bool Function() isCurrent,
  }) async {
    final currentState = _cubit.state;
    if (!isCurrent() ||
        currentState is! DistingStateSynchronized ||
        slotIndex >= currentState.slots.length) {
      return;
    }

    final slot = currentState.slots[slotIndex];
    if (paramIndex >= slot.parameters.length) {
      return;
    }

    final updatedParameters = List<ParameterInfo>.from(slot.parameters);
    updatedParameters[paramIndex] = info;

    final updatedSlot = slot.copyWith(parameters: updatedParameters);
    final updatedSlots = List<Slot>.from(currentState.slots);
    updatedSlots[slotIndex] = updatedSlot;

    _cubit._emitState(currentState.copyWith(slots: updatedSlots));

    // Rebuild CC lookup since parameter min/max may affect CC-to-param conversion
    _cubit._rebuildCcLookup();

    // Automatically query output mode usage if parameter has isOutputMode flag
    if (info.isOutputMode && info.parameterNumber >= 0 && isCurrent()) {
      await _queryOutputModeUsage(
        slotIndex,
        info.parameterNumber,
        isCurrent: isCurrent,
      );
    }
  }

  /// Query output mode usage for a parameter with isOutputMode flag.
  /// Uses debounce logic to avoid duplicate queries during sync operations.
  Future<void> _queryOutputModeUsage(
    int slotIndex,
    int parameterNumber, {
    required bool Function() isCurrent,
  }) async {
    final currentState = _cubit.state;
    if (!isCurrent() || currentState is! DistingStateSynchronized) {
      return;
    }

    // Check if we've already queried this parameter
    final queriedParams = _queriedOutputModeParameters[slotIndex] ?? {};
    if (queriedParams.contains(parameterNumber)) {
      return; // Already queried, skip
    }

    try {
      final disting = currentState.disting;
      final outputModeUsage = await disting.requestOutputModeUsage(
        slotIndex,
        parameterNumber,
      );

      if (outputModeUsage != null && isCurrent()) {
        // Store the output mode usage data
        final slotMap = _outputModeUsageMap[slotIndex] ?? {};
        slotMap[outputModeUsage.parameterNumber] =
            outputModeUsage.affectedParameterNumbers;
        _outputModeUsageMap[slotIndex] = slotMap;

        // Mark as queried
        queriedParams.add(parameterNumber);
        _queriedOutputModeParameters[slotIndex] = queriedParams;

        // Update the slot with the new outputModeMap and emit state change
        // This ensures the routing editor gets the modeParameterNumber for output ports
        final refreshedState = _cubit.state;
        if (isCurrent() &&
            refreshedState is DistingStateSynchronized &&
            slotIndex < refreshedState.slots.length) {
          final currentSlot = refreshedState.slots[slotIndex];
          final updatedSlot = currentSlot.copyWith(
            outputModeMap: _outputModeUsageMap[slotIndex] ?? {},
          );
          final updatedSlots = List<Slot>.from(refreshedState.slots);
          updatedSlots[slotIndex] = updatedSlot;
          _cubit._emitState(refreshedState.copyWith(slots: updatedSlots));
        }
      }
    } catch (e) {
      // Silently fail - output mode usage is optional data
    }
  }

  /// Get output mode usage data for a parameter.
  /// Returns list of affected parameter numbers, or null if not available.
  List<int>? getOutputModeUsage(int slotIndex, int parameterNumber) {
    return _outputModeUsageMap[slotIndex]?[parameterNumber];
  }

  /// Get all output mode usage data for a slot.
  Map<int, List<int>>? getSlotOutputModeUsage(int slotIndex) {
    return _outputModeUsageMap[slotIndex];
  }

  Future<void> updateSlotParameterEnums(
    int slotIndex,
    int paramIndex,
    ParameterEnumStrings enums, {
    required bool Function() isCurrent,
  }) async {
    final currentState = _cubit.state;
    if (!isCurrent() ||
        currentState is! DistingStateSynchronized ||
        slotIndex >= currentState.slots.length) {
      return;
    }

    final slot = currentState.slots[slotIndex];
    if (paramIndex >= slot.enums.length) {
      return;
    }

    final updatedEnums = List<ParameterEnumStrings>.from(slot.enums);
    updatedEnums[paramIndex] = enums;

    final updatedSlot = slot.copyWith(enums: updatedEnums);
    final updatedSlots = List<Slot>.from(currentState.slots);
    updatedSlots[slotIndex] = updatedSlot;

    _cubit._emitState(currentState.copyWith(slots: updatedSlots));
  }

  Future<void> updateSlotParameterMappings(
    int slotIndex,
    int paramIndex,
    Mapping mappings, {
    required bool Function() isCurrent,
  }) async {
    final currentState = _cubit.state;
    if (!isCurrent() ||
        currentState is! DistingStateSynchronized ||
        slotIndex >= currentState.slots.length) {
      return;
    }

    final slot = currentState.slots[slotIndex];
    if (paramIndex >= slot.mappings.length) {
      return;
    }

    final updatedMappings = List<Mapping>.from(slot.mappings);
    updatedMappings[paramIndex] = mappings;

    final updatedSlot = slot.copyWith(mappings: updatedMappings);
    final updatedSlots = List<Slot>.from(currentState.slots);
    updatedSlots[slotIndex] = updatedSlot;

    _cubit._emitState(currentState.copyWith(slots: updatedSlots));

    // Rebuild CC lookup since mapping data (MIDI CC assignments) may have changed
    _cubit._rebuildCcLookup();
  }

  Future<void> updateSlotParameterValueStrings(
    int slotIndex,
    int paramIndex,
    ParameterValueString valueStrings, {
    required bool Function() isCurrent,
  }) async {
    final currentState = _cubit.state;
    if (!isCurrent() ||
        currentState is! DistingStateSynchronized ||
        slotIndex >= currentState.slots.length) {
      return;
    }

    final slot = currentState.slots[slotIndex];
    if (paramIndex >= slot.valueStrings.length) {
      return;
    }

    final updatedValueStrings = List<ParameterValueString>.from(
      slot.valueStrings,
    );
    updatedValueStrings[paramIndex] = valueStrings;

    final updatedSlot = slot.copyWith(valueStrings: updatedValueStrings);
    final updatedSlots = List<Slot>.from(currentState.slots);
    updatedSlots[slotIndex] = updatedSlot;

    _cubit._emitState(currentState.copyWith(slots: updatedSlots));
  }

  Future<bool> refreshRouting({_RespecificationLifetime? lifetime}) async {
    final startingState = _cubit.state;
    if (startingState is! DistingStateSynchronized) return false;
    if (lifetime != null &&
        !_cubit._isCurrentRespecificationLifetime(lifetime)) {
      return false;
    }

    final disting = startingState.disting;
    final slotIdentities = startingState.slots
        .map(
          (slot) =>
              (index: slot.algorithm.algorithmIndex, guid: slot.algorithm.guid),
        )
        .toList(growable: false);
    final routingRequest = Future.wait(
      startingState.slots.map(
        (slot) =>
            disting.requestRoutingInformation(slot.algorithm.algorithmIndex),
      ),
    );
    final List<RoutingInfo?>? routings;
    if (lifetime == null) {
      routings = await routingRequest;
    } else {
      routings = await _awaitRoutingOrCancellation(routingRequest, lifetime);
    }
    if (routings == null) return false;
    final completedRoutings = routings;

    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized ||
        !identical(currentState.disting, disting) ||
        !identical(currentState.inputDevice, startingState.inputDevice) ||
        !identical(currentState.outputDevice, startingState.outputDevice) ||
        currentState.slots.length != slotIdentities.length ||
        (lifetime != null &&
            !_cubit._isCurrentRespecificationLifetime(lifetime))) {
      return false;
    }
    for (var index = 0; index < slotIdentities.length; index++) {
      final currentAlgorithm = currentState.slots[index].algorithm;
      final expected = slotIdentities[index];
      if (currentAlgorithm.algorithmIndex != expected.index ||
          currentAlgorithm.guid != expected.guid) {
        return false;
      }
    }

    final updatedSlots = List<Slot>.generate(currentState.slots.length, (
      index,
    ) {
      final slot = currentState.slots[index];
      return slot.copyWith(routing: completedRoutings[index] ?? slot.routing);
    });
    _cubit._emitState(currentState.copyWith(slots: updatedSlots));
    return true;
  }

  Future<List<RoutingInfo?>?> _awaitRoutingOrCancellation(
    Future<List<RoutingInfo?>> routingRequest,
    _RespecificationLifetime lifetime,
  ) async {
    final cancelled = Completer<List<RoutingInfo?>?>();
    final removeCancellationListener = lifetime.cancellation.addListener(() {
      if (!cancelled.isCompleted) cancelled.complete();
    });
    try {
      return await Future.any<List<RoutingInfo?>?>([
        routingRequest.then<List<RoutingInfo?>?>((routings) => routings),
        cancelled.future,
      ]);
    } finally {
      removeCancellationListener();
    }
  }
}
