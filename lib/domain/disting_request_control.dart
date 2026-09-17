/// Operation-owned cancellation for a queued or in-flight Disting request.
///
/// Cancelling one instance affects only requests explicitly given that instance;
/// it does not dispose the manager or interrupt unrelated scheduler work.
final class DistingRequestCancellation {
  final Set<void Function()> _listeners = {};
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void Function() addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }

    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    final listeners = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }
}

final class DistingRequestCancelledException implements Exception {
  const DistingRequestCancelledException();

  @override
  String toString() => 'The Disting request was cancelled.';
}
