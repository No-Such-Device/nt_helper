part of 'disting_cubit.dart';

class _ParameterRefreshDelegate {
  _ParameterRefreshDelegate(this._cubit);

  final DistingCubit _cubit;

  // Simple program refresh queue with retry
  Timer? _programRefreshTimer;
  int? _programRefreshSlot;
  int _programRefreshRetries = 0;

  // Parameter refresh debounce timer (300ms)
  Timer? _parameterRefreshTimer;
  static const Duration _parameterRefreshDebounceDelay = Duration(
    milliseconds: 300,
  );

  // Map to hold an active polling task for each mapped parameter,
  // keyed by a composite key (e.g. "algorithmIndex_parameterNumber").
  final Map<String, _PollingTask> _pollingTasks = {};

  void dispose() {
    stopForConnectionChange();
  }

  void stopForConnectionChange() {
    _programRefreshTimer?.cancel();
    _programRefreshTimer = null;
    _programRefreshSlot = null;
    _programRefreshRetries = 0;
    _parameterRefreshTimer?.cancel();
    _parameterRefreshTimer = null;
    _pollingTasks.clear();
  }

  /// Schedules a debounced parameter refresh (requestAllParameterValues).
  /// If a refresh is already scheduled, the existing timer is cancelled and restarted.
  /// This ensures only one refresh request is sent after a batch of parameter edits.
  /// The actual refresh occurs 300ms after the last call to this method.
  void scheduleParameterRefresh(int algorithmIndex) {
    final syncState = _cubit.state;
    if (syncState is! DistingStateSynchronized) {
      return; // Only schedule refresh when synchronized
    }
    final expectedManager = syncState.disting;

    // Cancel any pending timer
    _parameterRefreshTimer?.cancel();

    // Schedule a new refresh after the debounce delay
    _parameterRefreshTimer = Timer(_parameterRefreshDebounceDelay, () async {
      _parameterRefreshTimer = null;
      if (_cubit.isClosed) return;
      final manager = _cubit.disting();
      if (manager != null && identical(manager, expectedManager)) {
        try {
          final allParameterValues = await manager.requestAllParameterValues(
            algorithmIndex,
          );
          if (_cubit.isClosed) return;

          if (allParameterValues != null) {
            // Get current state (might have changed since timer was scheduled)
            final currentState = _cubit.state;
            if (currentState is DistingStateSynchronized &&
                identical(currentState.disting, expectedManager) &&
                algorithmIndex < currentState.slots.length) {
              // Update the slot with the refreshed parameter values
              final currentSlot = currentState.slots[algorithmIndex];
              final updatedSlot = currentSlot.copyWith(
                values: allParameterValues.values,
              );

              // Create new slots list with the updated slot
              final updatedSlots = List<Slot>.from(currentState.slots);
              updatedSlots[algorithmIndex] = updatedSlot;

              // Emit the updated state
              _cubit._emitState(currentState.copyWith(slots: updatedSlots));
            }
          }
        } catch (_) {}
      }
    });
  }

  // Simple program refresh queue with retry logic
  void queueProgramRefresh(int algorithmIndex) {
    // Cancel existing timer if any
    _programRefreshTimer?.cancel();

    // Store the slot to refresh and reset retry counter
    _programRefreshSlot = algorithmIndex;
    _programRefreshRetries = 0;

    // Start new timer with 2 second delay to give hardware time to load the new program
    _programRefreshTimer = Timer(const Duration(seconds: 2), () {
      _executeProgramRefresh();
    });
  }

  Future<void> _executeProgramRefresh() async {
    final slotIndex = _programRefreshSlot;
    if (slotIndex == null) return;

    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized) {
      _programRefreshTimer = null;
      _programRefreshSlot = null;
      return;
    }

    try {
      final disting = currentState.disting;
      final updatedSlot = await _cubit.fetchSlot(disting, slotIndex);

      // Check if state is still synchronized and slot still exists
      final newState = _cubit.state;
      if (!identical(newState, currentState) ||
          newState is! DistingStateSynchronized ||
          slotIndex >= newState.slots.length) {
        return;
      }

      // Update the slot in the state
      final preservedSlot = _cubit._preserveKnownSlotSpecifications(
        previousState: currentState,
        refreshedDisting: disting,
        refreshedPresetName: currentState.presetName,
        slotIndex: slotIndex,
        refreshedSlot: updatedSlot,
      );
      _cubit._emitState(
        newState.copyWith(
          slots: _cubit.updateSlot(
            slotIndex,
            newState.slots,
            (slot) => preservedSlot,
          ),
        ),
      );
      _cubit._rebuildCcLookup();

      // Clear the queue
      _programRefreshTimer = null;
      _programRefreshSlot = null;
      _programRefreshRetries = 0;
    } catch (e, stackTrace) {
      // Retry with exponential backoff if we haven't exceeded max retries
      if (_programRefreshRetries < 3) {
        _programRefreshRetries++;
        final delaySeconds = _programRefreshRetries; // 1s, 2s, 3s

        _programRefreshTimer = Timer(
          Duration(seconds: delaySeconds),
          _executeProgramRefresh,
        );
      } else {
        debugPrintStack(stackTrace: stackTrace);

        // Clear the queue
        _programRefreshTimer = null;
        _programRefreshSlot = null;
        _programRefreshRetries = 0;
      }
    }
  }

  // Starts polling for each mapped parameter.
  void startPollingMappedParameters() {
    stopPollingMappedParameters(); // Clear any previous tasks.
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) return;

    if (state.firmwareVersion.hasPerfPageItems &&
        state.perfPageItems.isNotEmpty) {
      for (final item in state.perfPageItems.where((i) => i.enabled)) {
        final key = '${item.slotIndex}_${item.parameterNumber}';
        if (!_pollingTasks.containsKey(key)) {
          _pollingTasks[key] = _PollingTask();
          _pollPerfPageItemParameter(item, key);
        }
      }
    } else {
      final mappedParams = DistingCubit.buildMappedParameterList(state);
      for (final param in mappedParams) {
        final key =
            '${param.parameter.algorithmIndex}_${param.parameter.parameterNumber}';
        _pollingTasks[key] = _PollingTask();
        _pollIndividualParameter(param, key);
      }
    }
  }

  // Stops all polling tasks.
  void stopPollingMappedParameters() {
    _pollingTasks.clear();
  }

  // Polls a single mapped parameter recursively.
  Future<void> _pollIndividualParameter(
    MappedParameter mapped,
    String key,
  ) async {
    // If the task has been cancelled or state is not synchronized, stop.
    final task = _pollingTasks[key];
    if (task == null ||
        !task.active ||
        _cubit.state is! DistingStateSynchronized) {
      return;
    }

    // Define intervals and threshold.
    const Duration fastInterval = Duration(milliseconds: 100);
    const Duration slowInterval = Duration(milliseconds: 1000);
    const int fastToSlowThreshold = 3;

    try {
      final disting = _cubit.requireDisting();
      // Request the current parameter value.
      final newValue = await disting.requestParameterValue(
        mapped.parameter.algorithmIndex,
        mapped.parameter.parameterNumber,
      );
      if (newValue == null) return;

      // Anomaly Check
      if (newValue.value < mapped.parameter.min ||
          newValue.value > mapped.parameter.max) {
        _cubit._refreshSlotAfterAnomaly(mapped.parameter.algorithmIndex);
        // Unlike in updateParameterValue, we don't return early here.
        // The polling loop will continue, and the refresh will eventually correct the state.
      }
      // End Anomaly Check

      final currentState = _cubit.state;
      if (currentState is DistingStateSynchronized &&
          identical(currentState.disting, disting)) {
        // Add boundary checks before accessing slots and values
        if (mapped.parameter.algorithmIndex >= currentState.slots.length) {
          _pollingTasks.remove(key); // Remove task to stop polling
          return;
        }
        final currentSlot = currentState.slots[mapped.parameter.algorithmIndex];
        // Check if parameter number is still valid
        if (mapped.parameter.parameterNumber >= currentSlot.values.length) {
          _pollingTasks.remove(key); // Remove task to stop polling
          return;
        }
        final currentValue =
            currentSlot.values[mapped.parameter.parameterNumber];
        if (newValue.value != currentValue.value ||
            newValue.isDisabled != currentValue.isDisabled) {
          // A change was detected (value or disabled state): update state and reset no-change count.
          final updatedSlots = _cubit.updateSlot(
            mapped.parameter.algorithmIndex,
            currentState.slots,
            (slot) => slot.copyWith(
              values: _cubit.replaceInList(
                slot.values,
                newValue,
                index: mapped.parameter.parameterNumber,
              ),
            ),
          );
          _cubit._emitState(currentState.copyWith(slots: updatedSlots));
          task.noChangeCount = 0;
          // Continue polling quickly.
          await Future.delayed(fastInterval);
        } else {
          // No change: increment counter and choose interval.
          task.noChangeCount++;
          final delay = (task.noChangeCount >= fastToSlowThreshold)
              ? slowInterval
              : fastInterval;
          await Future.delayed(delay);
        }
      }
    } catch (e) {
      // In case of an error, wait a bit before retrying.
      await Future.delayed(slowInterval);
    }

    // Continue polling this parameter if it's still active.
    if (_pollingTasks.containsKey(key)) {
      _pollIndividualParameter(mapped, key);
    }
  }

  Future<void> _pollPerfPageItemParameter(
    PerformancePageItem item,
    String key,
  ) async {
    final task = _pollingTasks[key];
    if (task == null ||
        !task.active ||
        _cubit.state is! DistingStateSynchronized) {
      return;
    }

    const Duration fastInterval = Duration(milliseconds: 100);
    const Duration slowInterval = Duration(milliseconds: 1000);
    const int fastToSlowThreshold = 3;

    try {
      final disting = _cubit.requireDisting();
      final newValue = await disting.requestParameterValue(
        item.slotIndex,
        item.parameterNumber,
      );
      if (newValue == null) return;

      final currentState = _cubit.state;
      if (currentState is DistingStateSynchronized &&
          identical(currentState.disting, disting)) {
        if (item.slotIndex >= currentState.slots.length) {
          _pollingTasks.remove(key);
          return;
        }
        final currentSlot = currentState.slots[item.slotIndex];
        if (item.parameterNumber >= currentSlot.values.length) {
          _pollingTasks.remove(key);
          return;
        }
        final currentValue = currentSlot.values[item.parameterNumber];
        if (newValue.value != currentValue.value ||
            newValue.isDisabled != currentValue.isDisabled) {
          final updatedSlots = _cubit.updateSlot(
            item.slotIndex,
            currentState.slots,
            (slot) => slot.copyWith(
              values: _cubit.replaceInList(
                slot.values,
                newValue,
                index: item.parameterNumber,
              ),
            ),
          );
          _cubit._emitState(currentState.copyWith(slots: updatedSlots));
          task.noChangeCount = 0;
          await Future.delayed(fastInterval);
        } else {
          task.noChangeCount++;
          final delay = (task.noChangeCount >= fastToSlowThreshold)
              ? slowInterval
              : fastInterval;
          await Future.delayed(delay);
        }
      }
    } catch (e) {
      await Future.delayed(slowInterval);
    }

    if (_pollingTasks.containsKey(key)) {
      _pollPerfPageItemParameter(item, key);
    }
  }
}
