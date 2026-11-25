import 'dart:async';

/// Debounces parameter writes to prevent excessive MIDI writes during rapid changes
///
/// Used for slider controls where users may drag rapidly, creating many intermediate
/// values. The debouncer ensures only the final value (after user stops dragging)
/// gets written to hardware.
///
/// Example usage:
/// ```dart
/// final _debouncer = ParameterWriteDebouncer();
///
/// void _updateParameter(int paramNumber, int value) {
///   _debouncer.schedule('param_$paramNumber', () {
///     cubit.updateParameterValue(slotIndex, paramNumber, value);
///   }, Duration(milliseconds: 50));
/// }
///
/// @override
/// void dispose() {
///   _debouncer.dispose();
///   super.dispose();
/// }
/// ```
class ParameterWriteDebouncer {
  final Map<String, Timer> _timers = {};
  final Map<String, void Function()> _callbacks = {};
  final Map<String, void Function()> _cancellations = {};

  /// Schedules a callback to run after the specified delay
  ///
  /// If a callback with the same key is already scheduled, it will be cancelled
  /// and replaced with the new one. This ensures only the final value in a rapid
  /// sequence of changes gets processed.
  ///
  /// [key] Unique identifier for this debounced operation (e.g., 'pitch_5')
  /// [callback] Function to execute after delay
  /// [delay] How long to wait before executing (typically 50ms)
  void schedule(
    String key,
    void Function() callback,
    Duration delay, {
    void Function()? onCancel,
  }) {
    cancel(key);
    _callbacks[key] = callback;
    if (onCancel != null) _cancellations[key] = onCancel;
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      _callbacks.remove(key);
      _cancellations.remove(key);
      callback();
    });
  }

  void cancel(String key) {
    _timers.remove(key)?.cancel();
    _callbacks.remove(key);
    _cancellations.remove(key)?.call();
  }

  /// Settle accepted input before exposing another editor for the same values.
  void flush() {
    for (final key in _callbacks.keys.toList()) {
      final callback = _callbacks.remove(key);
      _timers.remove(key)?.cancel();
      _cancellations.remove(key);
      callback?.call();
    }
  }

  /// Cancel, never send, work belonging to a disposed editor.
  void dispose() {
    for (final key in _timers.keys.toList()) {
      cancel(key);
    }
  }

  /// Returns the number of currently pending timers (useful for debugging)
  int get pendingCount => _timers.length;
}
