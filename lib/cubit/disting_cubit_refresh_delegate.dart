part of 'disting_cubit.dart';

class _RefreshDelegate {
  final DistingCubit _cubit;

  _RefreshDelegate(this._cubit);

  Future<void> cancelSync() async {
    _cubit.disconnect();
    await _cubit.loadDevices();
  }

  /// Refreshes the state from the current manager (online or offline).
  /// By default, performs a fast refresh of preset data only.
  /// Set [fullRefresh] to true to also re-download the algorithm library (online only).
  Future<void> refresh({bool fullRefresh = false}) async {
    final currentState = _cubit.state;
    if (currentState is DistingStateSynchronized) {
      if (fullRefresh && !currentState.offline) {
        await _cubit._performSyncAndEmit();
        _cubit._memoryDelegate.refreshAfterDeviceMutation();
        return;
      }

      await _cubit._refreshStateFromManager();

      if (!currentState.offline &&
          _cubit._algorithmLibraryDelegate.shouldRefreshAlgorithms(
            currentState,
          )) {
        _cubit._algorithmLibraryDelegate.refreshAlgorithmsInBackground();
      }
    }
  }
}
