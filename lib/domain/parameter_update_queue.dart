// parameter_update_queue.dart - Latest-Value-Wins Parameter Updates
// -----------------------------------------------------------------------------
// Consolidates rapid parameter updates to prevent queue buildup:
// • Latest value wins: Replace pending updates for same parameter
// • Combined operations: Parameter set + string query as one unit
// • Rate limited: Proper intervals between device communications
// • Background processing: UI stays responsive with optimistic updates
// -----------------------------------------------------------------------------

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';

// -----------------------------------------------------------------------------
// Parameter update request
// -----------------------------------------------------------------------------

class ParameterUpdate {
  const ParameterUpdate({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.value,
    required this.needsStringUpdate,
  });

  final int algorithmIndex;
  final int parameterNumber;
  final int value;
  final bool needsStringUpdate;

  String get key => '$algorithmIndex:$parameterNumber';

  @override
  String toString() =>
      'ParameterUpdate(algo: $algorithmIndex, param: $parameterNumber, value: $value, needsString: $needsStringUpdate)';
}

// -----------------------------------------------------------------------------
// Parameter Update Queue - Latest Value Wins
// -----------------------------------------------------------------------------

class ParameterUpdateQueue {
  ParameterUpdateQueue({
    required this._midiManager,
    this.processingInterval = const Duration(milliseconds: 5),
    this.operationInterval = const Duration(milliseconds: 25),
    this.onParameterStringUpdated,
  });

  final IDistingMidiManager _midiManager;
  final Duration processingInterval;
  final Duration operationInterval;
  final void Function(int algorithmIndex, int parameterNumber, String value)?
  onParameterStringUpdated;

  // Latest value wins - keyed by "algorithmIndex:parameterNumber"
  final Map<String, ParameterUpdate> _pendingUpdates = {};

  // Processing state
  bool _isProcessing = false;
  Timer? _processTimer;
  bool _disposed = false;

  // Throttling for immediate string updates
  final Map<String, DateTime> _lastStringUpdateTime = {};
  static const Duration _stringUpdateThrottle = Duration(milliseconds: 100);

  // Statistics for debugging
  int _totalUpdatesReceived = 0;
  int _totalUpdatesSent = 0;
  int _updatesConsolidated = 0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Queue a parameter update. If an update for this parameter is already
  /// pending, it will be replaced with the new value (latest wins).
  void updateParameter({
    required int algorithmIndex,
    required int parameterNumber,
    required int value,
    required bool needsStringUpdate,
    bool isRealTimeUpdate = false,
  }) {
    if (_disposed) return;

    final update = ParameterUpdate(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      value: value,
      needsStringUpdate: needsStringUpdate,
    );

    _totalUpdatesReceived++;

    // Latest value wins - replace any existing update for this parameter
    final wasAlreadyPending = _pendingUpdates.containsKey(update.key);
    _pendingUpdates[update.key] = update;

    if (wasAlreadyPending) {
      _updatesConsolidated++;
    }

    // For real-time updates during slider movement, request string update immediately
    if (isRealTimeUpdate && needsStringUpdate) {
      _requestStringUpdateImmediately(algorithmIndex, parameterNumber);
    }

    _scheduleProcessing();
  }

  /// Get current queue statistics for debugging
  Map<String, int> getStatistics() => {
    'received': _totalUpdatesReceived,
    'sent': _totalUpdatesSent,
    'consolidated': _updatesConsolidated,
    'pending': _pendingUpdates.length,
  };

  /// Wait for all pending updates to be sent to hardware.
  Future<void> flush() async {
    while (_pendingUpdates.isNotEmpty || _isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Clear all pending updates
  void clear() {
    _pendingUpdates.clear();
    _lastStringUpdateTime.clear();
    _processTimer?.cancel();
    _processTimer = null;
  }

  void dispose() {
    _disposed = true;
    _processTimer?.cancel();
    _pendingUpdates.clear();
    _lastStringUpdateTime.clear();
  }

  // ---------------------------------------------------------------------------
  // Internal processing
  // ---------------------------------------------------------------------------

  void _scheduleProcessing() {
    if (_isProcessing || _disposed) return;

    // Cancel any existing timer and schedule processing
    _processTimer?.cancel();
    _processTimer = Timer(processingInterval, _processNext);
  }

  /// Request parameter string update immediately for real-time feedback
  void _requestStringUpdateImmediately(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    final key = '$algorithmIndex:$parameterNumber';
    final now = DateTime.now();

    // Throttle immediate string updates to avoid overwhelming MIDI
    final lastUpdate = _lastStringUpdateTime[key];
    if (lastUpdate != null &&
        now.difference(lastUpdate) < _stringUpdateThrottle) {
      return;
    }

    _lastStringUpdateTime[key] = now;

    try {
      final parameterString = await _midiManager.requestParameterValueString(
        algorithmIndex,
        parameterNumber,
      );
      if (parameterString != null) {
        onParameterStringUpdated?.call(
          algorithmIndex,
          parameterNumber,
          parameterString.value,
        );
      }
    } catch (e) {
      // Don't propagate errors for immediate updates
    }
  }

  Future<void> _processNext() async {
    if (_pendingUpdates.isEmpty || _isProcessing || _disposed) return;

    _isProcessing = true;

    try {
      // Take the first pending update (FIFO for fairness across parameters)
      final entry = _pendingUpdates.entries.first;
      _pendingUpdates.remove(entry.key);
      final update = entry.value;

      // Send parameter value (fire-and-forget)
      await _midiManager.setParameterValue(
        update.algorithmIndex,
        update.parameterNumber,
        update.value,
      );

      // Query parameter string if needed (expects response)
      if (update.needsStringUpdate) {
        try {
          final parameterString = await _midiManager
              .requestParameterValueString(
                update.algorithmIndex,
                update.parameterNumber,
              );
          if (parameterString != null) {
            // Notify the cubit about the updated parameter string
            onParameterStringUpdated?.call(
              update.algorithmIndex,
              update.parameterNumber,
              parameterString.value,
            );
          } else {}
        } catch (e) {
          // Continue processing even if string update fails
        }
      }

      _totalUpdatesSent++;
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isProcessing = false;

      // Schedule next update if more pending
      if (_pendingUpdates.isNotEmpty && !_disposed) {
        _processTimer = Timer(operationInterval, _processNext);
      }
    }
  }
}
