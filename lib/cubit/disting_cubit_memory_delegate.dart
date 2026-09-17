part of 'disting_cubit.dart';

final class _MemoryConnectionScope {
  _MemoryConnectionScope(this.manager);

  final IDistingMidiManager manager;
  Future<void> queryTail = Future<void>.value();
}

/// Owns connection-local memory display state and fresh memory transactions.
///
/// Memory transactions are serialized as a whole, in addition to the MIDI
/// manager's per-message scheduler. This prevents display and fresh-only
/// consumers from overlapping indistinguishable 0x39 exchanges.
final class _MemoryDelegate {
  _MemoryDelegate(this._cubit);

  final DistingCubit _cubit;
  final StreamController<MemoryDisplayState> _stateController =
      StreamController<MemoryDisplayState>.broadcast(sync: true);

  MemoryDisplayState _state = const MemoryDisplayState.unavailable();
  _MemoryConnectionScope? _connection;
  Future<void>? _displayRefresh;
  _MemoryConnectionScope? _displayRefreshConnection;
  bool _disposed = false;

  MemoryDisplayState get state {
    _synchronizeConnection();
    return _state;
  }

  Stream<MemoryDisplayState> get stateStream => _stateController.stream;

  bool get isSupported {
    final currentState = _cubit.state;
    return currentState is DistingStateSynchronized &&
        !currentState.offline &&
        !currentState.demo &&
        currentState.firmwareVersion.hasMemoryUsage;
  }

  /// Requests a display refresh while preserving any previous successful
  /// sample. Failures become unavailable or unfresh display state.
  Future<void> refreshDisplay() {
    final connection = _connectionForQueryOrNull();
    if (connection == null) {
      _setState(const MemoryDisplayState.unavailable());
      return Future<void>.value();
    }

    final existingRefresh = _displayRefresh;
    if (existingRefresh != null &&
        identical(_displayRefreshConnection, connection)) {
      return existingRefresh;
    }

    final previousSample = _state.sample;
    _setState(MemoryDisplayState.refreshing(previousSample: previousSample));

    late final Future<void> refresh;
    refresh = _runDisplayRefresh(connection, previousSample).whenComplete(() {
      if (identical(_displayRefresh, refresh)) {
        _displayRefresh = null;
        _displayRefreshConnection = null;
      }
    });
    _displayRefresh = refresh;
    _displayRefreshConnection = connection;
    return refresh;
  }

  /// Requests a fresh sample from the active physical connection.
  ///
  /// This path never reads or returns the remembered display sample. It throws
  /// when the connection is unavailable, unsupported, superseded, or when a
  /// fresh catalogue/0x39 transaction cannot produce a result.
  Future<MemoryUsage> requestFresh() async {
    final connection = _connectionForQuery();
    return _serialize(connection, () => _executeFreshQuery(connection));
  }

  /// Clears remembered and in-flight display state before a connection ends.
  void clearConnection() {
    if (_connection == null &&
        _displayRefresh == null &&
        _state.status == MemoryDisplayStatus.unavailable) {
      return;
    }

    _connection = null;
    _displayRefresh = null;
    _displayRefreshConnection = null;
    _setState(const MemoryDisplayState.unavailable());
  }

  /// Keeps connection-local memory from surviving state transitions that
  /// replace or leave the active physical manager.
  void onDistingStateWillChange(DistingState nextState) {
    final activeConnection = _connection;
    if (activeConnection == null) return;

    final nextManager = _physicalManager(nextState);
    if (!identical(activeConnection.manager, nextManager)) {
      clearConnection();
      return;
    }

    if (nextState is DistingStateSynchronized &&
        !nextState.firmwareVersion.hasMemoryUsage) {
      _setState(const MemoryDisplayState.unavailable());
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    clearConnection();
    _disposed = true;
    await _stateController.close();
  }

  Future<void> _runDisplayRefresh(
    _MemoryConnectionScope connection,
    MemoryUsage? previousSample,
  ) async {
    try {
      final sample = await _serialize(
        connection,
        () => _executeFreshQuery(connection),
      );
      if (_isCurrent(connection)) {
        _setState(MemoryDisplayState.available(sample));
      }
    } catch (_) {
      if (!_isCurrent(connection)) return;
      _setState(
        previousSample == null
            ? const MemoryDisplayState.unavailable()
            : MemoryDisplayState.unfresh(previousSample),
      );
    }
  }

  Future<MemoryUsage> _executeFreshQuery(
    _MemoryConnectionScope connection,
  ) async {
    _requireCurrent(connection);

    try {
      final input = await MemoryQueryInput.requestFromCatalogue(
        connection.manager,
      );
      _requireCurrent(connection);
      if (input == null) {
        throw StateError(
          'No suitable built-in algorithm was found for a memory query.',
        );
      }

      final sample = await connection.manager.requestMemoryUsage(input);
      _requireCurrent(connection);
      if (sample == null) {
        throw StateError('The device did not return a memory sample.');
      }
      return sample;
    } catch (error, stackTrace) {
      // Prefer a superseded-connection failure over any late result or error
      // produced by a manager that no longer owns the active connection.
      _requireCurrent(connection);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> _serialize<T>(
    _MemoryConnectionScope connection,
    Future<T> Function() query,
  ) {
    final operation = connection.queryTail.then((_) => query());
    connection.queryTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  _MemoryConnectionScope _connectionForQuery() {
    if (_disposed) {
      throw StateError('Memory queries are unavailable after disposal.');
    }

    final connection = _synchronizeConnection();
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized ||
        currentState.offline ||
        currentState.demo ||
        connection == null) {
      throw StateError('No physical Disting NT connection is synchronized.');
    }
    if (!currentState.firmwareVersion.hasMemoryUsage) {
      _setState(const MemoryDisplayState.unavailable());
      throw UnsupportedError(
        'Memory queries require firmware version 1.19 or higher.',
      );
    }
    return connection;
  }

  _MemoryConnectionScope? _connectionForQueryOrNull() {
    try {
      return _connectionForQuery();
    } on StateError {
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  _MemoryConnectionScope? _synchronizeConnection() {
    if (_disposed) return null;

    final manager = _physicalManager(_cubit.state);
    if (manager == null) {
      clearConnection();
      return null;
    }

    final currentConnection = _connection;
    if (currentConnection != null &&
        identical(currentConnection.manager, manager)) {
      return currentConnection;
    }

    clearConnection();
    final nextConnection = _MemoryConnectionScope(manager);
    _connection = nextConnection;
    return nextConnection;
  }

  IDistingMidiManager? _physicalManager(DistingState state) {
    return switch (state) {
      DistingStateSynchronized(
        disting: final manager,
        offline: false,
        demo: false,
      ) =>
        manager,
      _ => null,
    };
  }

  bool _isCurrent(_MemoryConnectionScope connection) {
    if (_disposed || !identical(_connection, connection)) return false;
    return identical(_physicalManager(_cubit.state), connection.manager);
  }

  void _requireCurrent(_MemoryConnectionScope connection) {
    if (!_isCurrent(connection)) {
      throw StateError(
        'The memory query was superseded by a connection change.',
      );
    }

    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized ||
        !currentState.firmwareVersion.hasMemoryUsage) {
      throw StateError('The memory query is no longer available.');
    }
  }

  void _setState(MemoryDisplayState nextState) {
    if (_sameState(_state, nextState)) return;
    _state = nextState;
    if (!_stateController.isClosed) {
      _stateController.add(nextState);
    }
  }

  bool _sameState(MemoryDisplayState left, MemoryDisplayState right) {
    return left.status == right.status && identical(left.sample, right.sample);
  }
}
