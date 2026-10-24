part of 'disting_cubit.dart';

class _AlgorithmLibraryDelegate {
  _AlgorithmLibraryDelegate(this._cubit);

  final DistingCubit _cubit;

  /// Background loads that may still publish a fuller `state.algorithms`.
  int _backgroundLoads = 0;
  Completer<void>? _backgroundLoadsSettled;

  /// Whether a background load is still filling in `state.algorithms`.
  /// Until it finishes, the list can be empty or missing plug-ins.
  bool get isLoadingInBackground => _backgroundLoads > 0;

  /// Waits until no background load is running, for at most [timeout].
  /// Returns true at once when none is running, and false if one is still
  /// running when [timeout] expires.
  Future<bool> waitForBackgroundLoads(Duration timeout) async {
    if (_backgroundLoads == 0) return true;
    final settled = (_backgroundLoadsSettled ??= Completer<void>()).future;
    try {
      await settled.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  /// Runs [load] as a background load, so [isLoadingInBackground] stays true
  /// until it finishes, whether or not it succeeds.
  Future<void> _trackBackgroundLoad(Future<void> Function() load) async {
    _backgroundLoads++;
    try {
      await load();
    } finally {
      _backgroundLoads--;
      if (_backgroundLoads == 0) {
        _backgroundLoadsSettled?.complete();
        _backgroundLoadsSettled = null;
      }
    }
  }

  // Helper to determine if an algorithm is a factory algorithm (lowercase GUID)
  // vs community plugin (any uppercase letters in GUID)
  bool _isFactoryAlgorithm(String guid) {
    return guid == guid.toLowerCase();
  }

  // Helper to fetch algorithm info with prioritization (factory first, then community)
  // Uses cache if available and valid (same numAlgorithms, cache fresh per settings)
  Future<List<AlgorithmInfo>> fetchAlgorithmsWithPriority(
    IDistingMidiManager manager, {
    bool enableBackgroundCommunityLoading = false,
  }) async {
    final numAlgorithms = await manager.requestNumberOfAlgorithms() ?? 0;

    // Try cache first - only if numAlgorithms matches and cache is fresh
    final cacheFreshnessDays = SettingsService().algorithmCacheDays;
    final cachedAlgorithms = await _cubit._metadataDao.getAlgorithmInfoCache(
      numAlgorithms,
      cacheFreshnessDays: cacheFreshnessDays,
    );
    if (cachedAlgorithms != null && cachedAlgorithms.length == numAlgorithms) {
      // Cache hit - use cached data
      return cachedAlgorithms;
    }

    // Cache miss - fetch from device
    List<AlgorithmInfo> algorithms;
    if (enableBackgroundCommunityLoading) {
      // Optimized approach: only fetch factory algorithms synchronously
      algorithms = await _fetchFactoryAlgorithmsAndStartBackgroundLoading(
        manager,
        numAlgorithms,
      );
    } else {
      // Original approach: fetch all algorithms synchronously with prioritization
      algorithms = await _fetchAllAlgorithmsSynchronously(
        manager,
        numAlgorithms,
      );
    }

    // Save to cache if we got a complete set
    if (algorithms.length == numAlgorithms) {
      await _cubit._metadataDao.saveAlgorithmInfoCache(
        algorithms,
        numAlgorithms,
      );
    }

    return algorithms;
  }

  // Optimized method: fetch factory algorithms quickly, queue slow ones for background
  Future<List<AlgorithmInfo>> _fetchFactoryAlgorithmsAndStartBackgroundLoading(
    IDistingMidiManager manager,
    int numAlgorithms,
  ) async {
    final List<AlgorithmInfo> factoryResults = [];
    final List<int> backgroundIndices = [];

    // Quick pass with short timeout to catch fast-responding factory algorithms
    for (int i = 0; i < numAlgorithms; i++) {
      try {
        // Use very short timeout - factory algorithms should respond quickly
        final algorithmInfo = await manager
            .requestAlgorithmInfo(i)
            .timeout(const Duration(milliseconds: 200), onTimeout: () => null);

        if (algorithmInfo != null && _isFactoryAlgorithm(algorithmInfo.guid)) {
          factoryResults.add(algorithmInfo);
        } else if (algorithmInfo != null) {
          // Got response but it's a community plugin - queue for background
          backgroundIndices.add(i);
        } else {
          // Timed out - likely a community plugin that's not loaded, queue for background
          backgroundIndices.add(i);
        }
      } catch (e) {
        // Error - queue for background retry
        backgroundIndices.add(i);
      }
    }

    // Start background loading for community plugins and timed-out algorithms
    if (backgroundIndices.isNotEmpty) {
      _loadCommunityPluginsInBackground(
        manager,
        backgroundIndices,
        List.from(factoryResults),
      );
    }

    return factoryResults;
  }

  // Original method: fetch all algorithms with full categorization pass
  Future<List<AlgorithmInfo>> _fetchAllAlgorithmsSynchronously(
    IDistingMidiManager manager,
    int numAlgorithms,
  ) async {
    final List<int> factoryIndices = [];
    final List<int> communityIndices = [];

    // First pass: categorize algorithms by requesting basic info
    for (int i = 0; i < numAlgorithms; i++) {
      try {
        final algorithmInfo = await manager.requestAlgorithmInfo(i);
        if (algorithmInfo != null) {
          if (_isFactoryAlgorithm(algorithmInfo.guid)) {
            factoryIndices.add(i);
          } else {
            communityIndices.add(i);
          }
        }
      } catch (e) {
        // If we can't determine, treat as community (lower priority)
        communityIndices.add(i);
      }
    }

    final List<AlgorithmInfo> results = [];

    // Fetch factory algorithms first (higher priority)
    for (int i in factoryIndices) {
      try {
        final algorithmInfo = await manager.requestAlgorithmInfo(i);
        if (algorithmInfo != null) {
          results.add(algorithmInfo);
        }
      } catch (e) {
        // Intentionally empty
      }
    }

    // Synchronous community algorithm loading
    for (int i in communityIndices) {
      try {
        final algorithmInfo = await manager.requestAlgorithmInfo(i);
        if (algorithmInfo != null) {
          results.add(algorithmInfo);
        }
      } catch (e) {
        // Intentionally empty
      }
    }

    return results;
  }

  // Background loading of ALL algorithms with prioritization and state merging
  Future<void> loadAllAlgorithmsInBackground(
    IDistingMidiManager manager,
    int numAlgorithms,
  ) => _trackBackgroundLoad(() => _loadAllAlgorithms(manager, numAlgorithms));

  Future<void> _loadAllAlgorithms(
    IDistingMidiManager manager,
    int numAlgorithms,
  ) async {
    // Try cache first
    final cacheFreshnessDays = SettingsService().algorithmCacheDays;
    final cachedAlgorithms = await _cubit._metadataDao.getAlgorithmInfoCache(
      numAlgorithms,
      cacheFreshnessDays: cacheFreshnessDays,
    );
    if (cachedAlgorithms != null && cachedAlgorithms.length == numAlgorithms) {
      // Cache hit - update state with cached data
      final currentState = _cubit.state;
      if (currentState is DistingStateSynchronized && !currentState.offline) {
        _cubit._emitState(currentState.copyWith(algorithms: cachedAlgorithms));
      }
      return;
    }

    // Cache miss - fetch from device
    final List<AlgorithmInfo> factoryResults = [];
    final List<AlgorithmInfo> communityResults = [];

    // Load all algorithms with prioritization (factory first, then community)
    for (int i = 0; i < numAlgorithms; i++) {
      try {
        final algorithmInfo = await manager.requestAlgorithmInfo(i);
        if (algorithmInfo != null) {
          if (_isFactoryAlgorithm(algorithmInfo.guid)) {
            factoryResults.add(algorithmInfo);

            // Update state immediately when we get factory algorithms
            final currentState = _cubit.state;
            if (currentState is DistingStateSynchronized &&
                !currentState.offline) {
              final currentAlgorithms = [
                ...factoryResults,
                ...communityResults,
              ];
              _cubit._emitState(
                currentState.copyWith(algorithms: currentAlgorithms),
              );
            }
          } else {
            communityResults.add(algorithmInfo);

            // Update state when we get community plugins too
            final currentState = _cubit.state;
            if (currentState is DistingStateSynchronized &&
                !currentState.offline) {
              final currentAlgorithms = [
                ...factoryResults,
                ...communityResults,
              ];
              _cubit._emitState(
                currentState.copyWith(algorithms: currentAlgorithms),
              );
            }
          }
        }
      } catch (e) {
        // Continue with next algorithm
      }
    }

    // Save complete algorithm list to cache
    final allResults = [...factoryResults, ...communityResults];
    if (allResults.length == numAlgorithms) {
      await _cubit._metadataDao.saveAlgorithmInfoCache(
        allResults,
        numAlgorithms,
      );
    }
  }

  // Background loading of community plugins with single retry and state merging
  Future<void> _loadCommunityPluginsInBackground(
    IDistingMidiManager manager,
    List<int> communityIndices,
    List<AlgorithmInfo> baseResults,
  ) => _trackBackgroundLoad(
    () => _loadCommunityPlugins(manager, communityIndices, baseResults),
  );

  Future<void> _loadCommunityPlugins(
    IDistingMidiManager manager,
    List<int> communityIndices,
    List<AlgorithmInfo> baseResults,
  ) async {
    final List<AlgorithmInfo> communityResults = [];

    for (int i in communityIndices) {
      try {
        // Single attempt to fetch community plugin
        final algorithmInfo = await manager.requestAlgorithmInfo(i);
        if (algorithmInfo != null) {
          communityResults.add(algorithmInfo);
        }
      } catch (e) {
        // Move on to next plugin - no retry
      }
    }

    // Merge results and update state if still synchronized
    if (communityResults.isNotEmpty) {
      final mergedResults = [...baseResults, ...communityResults];

      // Only update state if we're still in synchronized mode and not offline
      final currentState = _cubit.state;
      if (currentState is DistingStateSynchronized && !currentState.offline) {
        _cubit._emitState(currentState.copyWith(algorithms: mergedResults));
      }
    } else {}
  }

  // Helper method to determine if algorithm library should be refreshed
  bool shouldRefreshAlgorithms(DistingStateSynchronized currentState) {
    // For now, be conservative and only refresh algorithms if the list is empty
    // In the future, we could add more sophisticated logic like checking timestamps,
    // firmware version changes, or comparing algorithm counts
    return currentState.algorithms.isEmpty;
  }

  // Background refresh of algorithm library without blocking the UI
  void refreshAlgorithmsInBackground() {
    // Run asynchronously without awaiting
    unawaited(
      _trackBackgroundLoad(() async {
        try {
          final currentState = _cubit.state;
          if (currentState is! DistingStateSynchronized ||
              currentState.offline) {
            return; // State changed, abort
          }

          final distingManager = _cubit.requireDisting();

          // Fetch algorithm info in the background with prioritization
          try {
            final algorithms = await fetchAlgorithmsWithPriority(
              distingManager,
              enableBackgroundCommunityLoading: true,
            );

            // Only update if state is still synchronized and algorithms changed
            final newState = _cubit.state;
            if (newState is DistingStateSynchronized &&
                !newState.offline &&
                algorithms.length != newState.algorithms.length) {
              _cubit._emitState(newState.copyWith(algorithms: algorithms));
            }
          } catch (e, stackTrace) {
            debugPrintStack(stackTrace: stackTrace);
            // Don't update state on algorithm fetch failure during background refresh
          }
        } catch (e, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);
          // Don't emit error state for background refresh failures
        }
      }),
    );
  }

  // Public method to trigger algorithm list refresh from UI
  void refreshAlgorithms() {
    refreshAlgorithmsInBackground();
  }

  /// Sends rescan plugins command to hardware and refreshes algorithm list.
  /// Used by the Add Algorithm screen's manual rescan button.
  Future<void> rescanPlugins() async {
    final disting = _cubit.requireDisting();
    await disting.requestRescanPlugins();
    // Invalidate cache since plugins may have changed
    await _cubit._metadataDao.invalidateAlgorithmInfoCache();
    refreshAlgorithmsInBackground();
  }

  /// Awaited counterpart of [refreshAlgorithmsInBackground]: re-reads the
  /// whole algorithm list from the device, bypassing the cache, publishes it
  /// to state, and returns it.
  ///
  /// It sends no rescan command; callers that need one send it first.
  Future<List<AlgorithmInfo>> refreshAlgorithmsNow() async {
    final manager = _cubit.requireDisting();
    await _cubit._metadataDao.invalidateAlgorithmInfoCache();
    final algorithms = await fetchAlgorithmsWithPriority(manager);
    final state = _cubit.state;
    if (state is DistingStateSynchronized && !state.offline) {
      _cubit._emitState(state.copyWith(algorithms: algorithms));
    }
    return algorithms;
  }
}
