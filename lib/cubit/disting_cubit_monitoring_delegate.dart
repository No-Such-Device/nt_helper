part of 'disting_cubit.dart';

class _MonitoringDelegate {
  _MonitoringDelegate(this._cubit) {
    _cpuUsageController = StreamController<CpuUsage?>.broadcast(
      onListen: _startCpuUsagePolling,
      onCancel: _checkStopCpuUsagePolling,
    );
  }

  final DistingCubit _cubit;

  // CPU Usage Streaming
  late final StreamController<CpuUsage?> _cpuUsageController;
  Timer? _cpuUsageTimer;
  static const Duration _cpuUsagePollingInterval = Duration(seconds: 10);
  static const Duration _cpuUsageBackoffInterval = Duration(seconds: 60);
  Duration _activeCpuUsagePollingInterval = _cpuUsagePollingInterval;
  int _consecutiveCpuUsageFailures = 0;
  bool _cpuUsagePollInFlight = false;

  // Video Streaming
  UsbVideoManager? _videoManager;
  StreamSubscription<VideoStreamState>? _videoStateSubscription;

  Stream<CpuUsage?> get cpuUsageStream => _cpuUsageController.stream;
  VideoStreamState? get currentVideoState => _videoManager?.currentState;
  UsbVideoManager? get videoManager => _videoManager;

  Future<void> dispose() async {
    _cpuUsageTimer?.cancel();
    _cpuUsageController.close();

    _videoStateSubscription?.cancel();
    await _videoManager?.dispose();
  }

  /// Gets the current CPU usage information from the Disting device.
  /// Returns null if the device is not connected or if the request fails.
  /// Only works when connected to a physical device (not in offline or demo mode).
  Future<CpuUsage?> getCpuUsage() async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized) {
      return null;
    }

    if (currentState.offline || currentState.demo) {
      return null;
    }

    try {
      final disting = _cubit.requireDisting();
      await disting.requestWake();
      final cpuUsage = await disting.requestCpuUsage();
      return cpuUsage;
    } catch (_) {
      return null;
    }
  }

  /// Starts the USB video stream from the Disting NT device
  Future<void> startVideoStream() async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized) {
      return;
    }

    // Initialize video manager if not already created
    _videoManager ??= UsbVideoManager(
      takeScreenshot: () async {
        final state = _cubit.state;
        if (state is! DistingStateSynchronized || state.offline || state.demo) {
          throw StateError('Screenshots require a synchronized live device.');
        }
        return _cubit.getHardwareScreenshot();
      },
    );
    await _videoManager!.initialize();

    // Subscribe to video state changes and update cubit state
    _videoStateSubscription?.cancel();
    _videoStateSubscription = _videoManager!.stateStream.listen((videoState) {
      if (_cubit.state is DistingStateSynchronized) {
        final syncState = _cubit.state as DistingStateSynchronized;
        _cubit._emitState(syncState.copyWith(videoStream: videoState));
      }
    });

    // Try to auto-connect to Disting NT or any available USB camera
    await _videoManager!.autoConnect();
  }

  /// Stops the USB video stream
  Future<void> stopVideoStream() async {
    _videoStateSubscription?.cancel();
    _videoStateSubscription = null;
    await _videoManager?.disconnect();

    final currentState = _cubit.state;
    if (currentState is DistingStateSynchronized) {
      _cubit._emitState(currentState.copyWith(videoStream: null));
    }
  }

  // CPU Usage Streaming
  void _startCpuUsagePolling() {
    // Cancel any existing timer
    _cpuUsageTimer?.cancel();
    _activeCpuUsagePollingInterval = _cpuUsagePollingInterval;

    // Start polling immediately, then every 10 seconds
    _pollCpuUsageOnce();
    _scheduleCpuUsagePolling(_cpuUsagePollingInterval);
  }

  void _checkStopCpuUsagePolling() {
    // Use a small delay to check if there are still listeners
    // This prevents stopping polling when one listener cancels but others remain
    Timer(const Duration(milliseconds: 100), () {
      if (!_cpuUsageController.hasListener) {
        _cpuUsageTimer?.cancel();
        _cpuUsageTimer = null;
      }
    });
  }

  Future<void> _pollCpuUsageOnce() async {
    if (_cpuUsagePollInFlight) return;

    _cpuUsagePollInFlight = true;
    try {
      final cpuUsage = await getCpuUsage();
      if (cpuUsage == null) {
        _consecutiveCpuUsageFailures++;
      } else {
        _consecutiveCpuUsageFailures = 0;
      }
      if (!_cpuUsageController.isClosed) {
        _cpuUsageController.add(cpuUsage);
      }
      if (_consecutiveCpuUsageFailures >= 3) {
        _scheduleCpuUsagePolling(_cpuUsageBackoffInterval);
      } else if (cpuUsage != null) {
        _scheduleCpuUsagePolling(_cpuUsagePollingInterval);
      }
    } catch (_) {
      _consecutiveCpuUsageFailures++;
      if (!_cpuUsageController.isClosed) {
        _cpuUsageController.add(null);
      }
      if (_consecutiveCpuUsageFailures >= 3) {
        _scheduleCpuUsagePolling(_cpuUsageBackoffInterval);
      }
    } finally {
      _cpuUsagePollInFlight = false;
    }
  }

  void _scheduleCpuUsagePolling(Duration interval) {
    if (!_cpuUsageController.hasListener) return;
    if (_cpuUsageTimer != null && _activeCpuUsagePollingInterval == interval) {
      return;
    }

    _cpuUsageTimer?.cancel();
    _activeCpuUsagePollingInterval = interval;
    _cpuUsageTimer = Timer.periodic(interval, (_) {
      _pollCpuUsageOnce();
    });
  }

  /// Temporarily pause CPU usage polling (useful during sync operations)
  void pauseCpuMonitoring() {
    _cpuUsageTimer?.cancel();
    _cpuUsageTimer = null;
  }

  /// Resume CPU usage polling if there are listeners
  void resumeCpuMonitoring() {
    if (_cpuUsageController.hasListener && _cpuUsageTimer == null) {
      _startCpuUsagePolling();
    }
  }
}
