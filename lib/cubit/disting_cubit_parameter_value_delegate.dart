part of 'disting_cubit.dart';

class _ParameterValueDelegate {
  _ParameterValueDelegate(this._cubit);

  final DistingCubit _cubit;

  Future<void> updateParameterValue({
    required int algorithmIndex,
    required int parameterNumber,
    required int value,
    required bool userIsChangingTheValue,
  }) async {
    // Acquire semaphore to block retry queue during user parameter updates
    _cubit._parameterFetchDelegate.acquireCommandSemaphore();

    try {
      switch (_cubit.state) {
        case DistingStateInitial():
        case DistingStateSelectDevice():
        case DistingStateConnected():
          break;
        case DistingStateSynchronized syncstate:
          _cubit.requireDisting();

          // Always queue the parameter update for sending to device
          final currentSlot = syncstate.slots[algorithmIndex];
          final needsStringUpdate =
              parameterNumber < currentSlot.parameters.length &&
              ParameterEditorRegistry.isStringTypeUnit(
                currentSlot.parameters[parameterNumber].unit,
              );

          _cubit._parameterQueue?.updateParameter(
            algorithmIndex: algorithmIndex,
            parameterNumber: parameterNumber,
            value: value,
            needsStringUpdate: needsStringUpdate,
            isRealTimeUpdate: userIsChangingTheValue,
          );
          _cubit._ccNotificationDelegate.markOutboundChange(
            algorithmIndex,
            parameterNumber,
          );

          if (userIsChangingTheValue) {
            // Optimistic update during slider movement - just update the UI
            // Preserve isDisabled state from current value
            final currentValue = currentSlot.values.elementAtOrNull(
              parameterNumber,
            );
            final newValue = ParameterValue(
              algorithmIndex: algorithmIndex,
              parameterNumber: parameterNumber,
              value: value,
              isDisabled: currentValue?.isDisabled ?? false,
            );

            _cubit._emitState(
              syncstate.copyWith(
                slots: _cubit.updateSlot(algorithmIndex, syncstate.slots, (
                  slot,
                ) {
                  return slot.copyWith(
                    values: _cubit.replaceInList(
                      slot.values,
                      newValue,
                      index: parameterNumber,
                    ),
                  );
                }),
                isDirty: true,
              ),
            );
          } else {
            // When user releases slider - do minimal additional processing
            final transportDisconnected =
                _cubit._connectionDelegate.isTransportDisconnected;

            // Special case for switching programs
            if (!transportDisconnected &&
                _cubit._isProgramParameter(
                  syncstate,
                  algorithmIndex,
                  parameterNumber,
                )) {
              _cubit._queueProgramRefresh(algorithmIndex);
            }

            // Anomaly Check - using the value we're setting
            if (!transportDisconnected &&
                parameterNumber < currentSlot.parameters.length) {
              final parameterInfo = currentSlot.parameters.elementAt(
                parameterNumber,
              );
              if (value < parameterInfo.min || value > parameterInfo.max) {
                _cubit._refreshSlotAfterAnomaly(algorithmIndex);
                return; // Return early as the slot will be refreshed
              }
            }

            // Update UI with the final value immediately (optimistic)
            // Preserve isDisabled state from current value
            final currentValue = currentSlot.values.elementAtOrNull(
              parameterNumber,
            );
            final newValue = ParameterValue(
              algorithmIndex: algorithmIndex,
              parameterNumber: parameterNumber,
              value: value,
              isDisabled: currentValue?.isDisabled ?? false,
            );

            _cubit._emitState(
              syncstate.copyWith(
                slots: _cubit.updateSlot(algorithmIndex, syncstate.slots, (
                  slot,
                ) {
                  return slot.copyWith(
                    values: _cubit.replaceInList(
                      slot.values,
                      newValue,
                      index: parameterNumber,
                    ),
                  );
                }),
                isDirty: true,
              ),
            );

            // The parameter queue will handle:
            // 1. Sending the parameter value to device
            // 2. Querying parameter string if needed
            // 3. Rate limiting and consolidation

            // Trigger a debounced refresh to re-sync state after the user lets go
            // Skip if we're already doing a full program refresh (which includes all values)
            if (!transportDisconnected &&
                !_cubit._isProgramParameter(
                  syncstate,
                  algorithmIndex,
                  parameterNumber,
                )) {
              _cubit.scheduleParameterRefresh(algorithmIndex);
            }
          }
      }
    } finally {
      // Always release semaphore to allow retry queue to proceed
      _cubit._parameterFetchDelegate.releaseCommandSemaphore();
    }
  }
}
