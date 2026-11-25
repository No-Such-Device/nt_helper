part of 'disting_cubit.dart';

/// Whether a MIDI snapshot contains the expected NT input and output.
///
/// Expected names are matched case-insensitively. The Disting-name fallback is
/// used only when that endpoint's pre-flash name was unavailable.
@visibleForTesting
bool firmwareMidiEndpointsAvailable(
  List<MidiDevice> devices,
  String? expectedInputName,
  String? expectedOutputName,
) {
  bool matches(MidiDevice device, String? expectedName, {required bool input}) {
    final hasDirection = input
        ? device.inputPorts.isNotEmpty
        : device.outputPorts.isNotEmpty;
    if (!hasDirection) return false;

    final normalizedExpected = expectedName?.trim().toLowerCase();
    final normalizedActual = device.name.trim().toLowerCase();
    if (normalizedExpected != null && normalizedExpected.isNotEmpty) {
      return normalizedActual == normalizedExpected;
    }
    return normalizedActual.contains('disting');
  }

  final hasInput = devices.any(
    (device) => matches(device, expectedInputName, input: true),
  );
  final hasOutput = devices.any(
    (device) => matches(device, expectedOutputName, input: false),
  );
  return hasInput && hasOutput;
}

/// Lifecycle health of the online live-MIDI connection owned by [DistingCubit].
enum ConnectionHealthState {
  disconnected,
  connecting,
  usable,
  lost,
  recovering,
  recoveryExhausted,
  closed,
}

/// Bounded timing and retry limits for online USB disconnect/reboot recovery.
final class OnlineRecoveryConfig {
  const OnlineRecoveryConfig({
    this.connectTimeout = const Duration(seconds: 3),
    this.probeTimeout = const Duration(seconds: 2),
    this.initialRetryDelay = const Duration(milliseconds: 500),
    this.maxRetryDelay = const Duration(seconds: 2),
    this.maxRecoveryAttempts = 5,
    this.maxRecoveryDuration = const Duration(seconds: 15),
  });

  final Duration connectTimeout;
  final Duration probeTimeout;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final int maxRecoveryAttempts;
  final Duration maxRecoveryDuration;
}

final class _OnlineConnectionTarget {
  _OnlineConnectionTarget({
    required this.inputId,
    required this.inputName,
    required this.outputId,
    required this.outputName,
    required this.sysExId,
    required this.lastInputDevice,
    required this.lastOutputDevice,
    required this.lineage,
  });

  String inputId;
  String inputName;
  String outputId;
  String outputName;
  final int sysExId;
  MidiDevice lastInputDevice;
  MidiDevice lastOutputDevice;
  final ResponseAttributionTracker lineage;
}

class _ConnectionDelegate {
  _ConnectionDelegate(this._cubit);

  final DistingCubit _cubit;
  int _syncGeneration = 0;
  int _sessionEpoch = 0;
  int _attemptEpoch = 0;
  bool _firmwareProbeBusy = false;
  ConnectionHealthState _healthState = ConnectionHealthState.disconnected;

  _OnlineConnectionTarget? _activeTarget;
  IDistingMidiManager? _activeManager;
  MidiDevice? _activeInputDevice;
  MidiDevice? _activeOutputDevice;

  StreamSubscription<MidiConnectionState>? _inputStateSubscription;
  StreamSubscription<MidiConnectionState>? _outputStateSubscription;

  Future<void>? _recoveryTask;
  int? _recoverySessionEpoch;
  Timer? _recoveryWaitTimer;
  Completer<void>? _recoveryWakeCompleter;

  bool _onlineSnapshotCheckInFlight = false;
  bool _onlineSnapshotCheckPending = false;

  // Quarantine lineages survive manager replacement, MidiCommand replacement,
  // and USB re-enumeration ID aliases for the same endpoint name + SysEx ID.
  // Bounded so long-running processes cannot grow without limit.
  static const int _maxTrackedLineages = 32;
  final Map<String, ResponseAttributionTracker> _lineageByEndpointId = {};
  final Map<String, ResponseAttributionTracker> _lineageByEndpointName = {};

  OnlineRecoveryConfig get _config => _cubit.recoveryConfig;
  ConnectionHealthState get healthState => _healthState;
  int get connectionEpoch => _attemptEpoch;

  int get firmwareSysExId {
    final manager = _cubit.disting();
    if (manager is DistingMidiManager) return manager.sysExId;
    final state = _cubit.state;
    return state is DistingStateSelectDevice ? state.selectedSysExId : 0;
  }

  void dispose() {
    _sessionEpoch++;
    _attemptEpoch++;
    _syncGeneration++;
    _healthState = ConnectionHealthState.closed;
    _cancelRecoveryWait();
    _stopDeviceStateSubscriptions();
    stopMidiSetupListener();
    _activeTarget = null;
    _activeManager = null;
    _activeInputDevice = null;
    _activeOutputDevice = null;
  }

  void onLeavingOnlineSession() {
    _sessionEpoch++;
    _attemptEpoch++;
    _syncGeneration++;
    if (_healthState != ConnectionHealthState.closed) {
      _healthState = ConnectionHealthState.disconnected;
    }
    _cancelRecoveryWait();
    _stopDeviceStateSubscriptions();
    _activeTarget = null;
    _activeManager = null;
    _activeInputDevice = null;
    _activeOutputDevice = null;
  }

  void onFirmwareHandoffStarted() {
    onLeavingOnlineSession();
  }

  ResponseAttributionTracker _resolveLineageForEndpoint(
    MidiDevice inputDevice,
    int sysExId,
  ) {
    final idKey = '${inputDevice.id}|$sysExId';
    final normalizedName = inputDevice.name.trim().toLowerCase();
    final nameKey = normalizedName.isEmpty ? null : '$normalizedName|$sysExId';

    final existing =
        _lineageByEndpointId[idKey] ??
        (nameKey != null ? _lineageByEndpointName[nameKey] : null);
    final tracker = existing ?? ResponseAttributionTracker();

    _rememberLineage(idKey, nameKey, tracker);
    return tracker;
  }

  void _rememberLineage(
    String idKey,
    String? nameKey,
    ResponseAttributionTracker tracker,
  ) {
    if (_lineageByEndpointId.length >= _maxTrackedLineages &&
        !_lineageByEndpointId.containsKey(idKey)) {
      _lineageByEndpointId.remove(_lineageByEndpointId.keys.first);
    }
    _lineageByEndpointId[idKey] = tracker;
    if (nameKey != null) {
      if (_lineageByEndpointName.length >= _maxTrackedLineages &&
          !_lineageByEndpointName.containsKey(nameKey)) {
        _lineageByEndpointName.remove(_lineageByEndpointName.keys.first);
      }
      _lineageByEndpointName[nameKey] = tracker;
    }
  }

  bool _isEndpointOwnedByCurrentSession(MidiCommand command, String deviceId) {
    if (_cubit.isClosed || !identical(_cubit._midiCommand, command)) {
      return false;
    }
    if (_healthState != ConnectionHealthState.usable &&
        _healthState != ConnectionHealthState.connecting &&
        _healthState != ConnectionHealthState.recovering) {
      return false;
    }
    return _activeInputDevice?.id == deviceId ||
        _activeOutputDevice?.id == deviceId;
  }

  void _stopDeviceStateSubscriptions() {
    _inputStateSubscription?.cancel();
    _inputStateSubscription = null;
    _outputStateSubscription?.cancel();
    _outputStateSubscription = null;
  }

  void _cancelRecoveryWait() {
    _recoveryWaitTimer?.cancel();
    _recoveryWaitTimer = null;
    final wake = _recoveryWakeCompleter;
    _recoveryWakeCompleter = null;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
  }

  void _wakeRecovery() {
    _recoveryWaitTimer?.cancel();
    _recoveryWaitTimer = null;
    final wake = _recoveryWakeCompleter;
    _recoveryWakeCompleter = null;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
  }

  MidiDevice? _resolveSelection(
    List<MidiDevice> devices,
    MidiDevice? previousSelection,
  ) {
    if (previousSelection != null) {
      final retained =
          devices
              .where((device) => device.id == previousSelection.id)
              .firstOrNull ??
          devices
              .where((device) => device.name == previousSelection.name)
              .firstOrNull;
      if (retained != null) return retained;
    }
    // Suggest only an unambiguous endpoint, irrespective of module name.
    // Selection does not open MIDI or initiate synchronization.
    return devices.length == 1 ? devices.single : null;
  }

  void updateDeviceSelection({
    required MidiDevice? inputDevice,
    required MidiDevice? outputDevice,
    required int sysExId,
  }) {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSelectDevice) return;
    _cubit._emitState(
      currentState.copyWith(
        selectedInputDevice: inputDevice,
        selectedOutputDevice: outputDevice,
        selectedSysExId: sysExId,
      ),
    );
  }

  Future<void> initialize() async {
    StartupLogService.log(
      'DistingCubit.initialize: starting MIDI discovery. '
      'The app can start without a Disting NT connected; missing hardware '
      'should leave the app on device selection or offline mode.',
    );

    // Check for offline capability first
    bool canWorkOffline = false; // Default to false
    try {
      canWorkOffline = await _cubit._metadataDao.hasCachedAlgorithms();
      StartupLogService.log(
        'DistingCubit.initialize: cached offline algorithms available=$canWorkOffline',
      );
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.initialize: failed to check offline cache',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      // Proceed with canWorkOffline as false
    }

    final devices = await _fetchDeviceLists();
    final prefs = await _cubit._prefs;
    final savedInputName = prefs.getString('selectedInputMidiDevice');
    final savedOutputName = prefs.getString('selectedOutputMidiDevice');
    final savedSysExId = prefs.getInt('selectedSysExId');
    final savedInputDevice = savedInputName == null
        ? null
        : devices['input']
              ?.where((device) => device.name == savedInputName)
              .firstOrNull;
    final savedOutputDevice = savedOutputName == null
        ? null
        : devices['output']
              ?.where((device) => device.name == savedOutputName)
              .firstOrNull;
    final savedPairAvailable =
        savedInputDevice != null &&
        savedOutputDevice != null &&
        savedSysExId != null;
    _cubit._emitState(
      DistingState.selectDevice(
        inputDevices: devices['input'] ?? [],
        outputDevices: devices['output'] ?? [],
        canWorkOffline: canWorkOffline,
        selectedInputDevice: _resolveSelection(
          devices['input'] ?? [],
          savedInputDevice,
        ),
        selectedOutputDevice: _resolveSelection(
          devices['output'] ?? [],
          savedOutputDevice,
        ),
        selectedSysExId: savedPairAvailable ? savedSysExId : 0,
      ),
    );
    StartupLogService.log(
      'DistingCubit.initialize: showing device selection; '
      'manual MIDI connection required; '
      'saved pair available=$savedPairAvailable',
    );
    startMidiSetupListener();
  }

  Future<void> loadDevices() async {
    StartupLogService.log(
      'DistingCubit.loadDevices: refreshing MIDI device list',
    );
    final previousState = _cubit.state;
    try {
      if (previousState is! DistingStateSelectDevice) {
        _cubit._emitState(const DistingState.initial());
      }

      // Fetch devices using the helper
      final devices = await _fetchDeviceLists(); // Call helper

      // Re-check offline capability here for manual refresh accuracy
      final bool canWorkOffline = await _cubit._metadataDao
          .hasCachedAlgorithms();

      final inputDevices = devices['input'] ?? [];
      final outputDevices = devices['output'] ?? [];
      final currentState = _cubit.state;
      if (previousState is DistingStateSelectDevice &&
          currentState is! DistingStateSelectDevice) {
        return;
      }
      if (previousState is! DistingStateSelectDevice &&
          currentState is! DistingStateInitial) {
        return;
      }
      final selectionState = currentState is DistingStateSelectDevice
          ? currentState
          : previousState is DistingStateSelectDevice
          ? previousState
          : null;
      final selectedInputDevice = _resolveSelection(
        inputDevices,
        selectionState?.selectedInputDevice,
      );
      final selectedOutputDevice = _resolveSelection(
        outputDevices,
        selectionState?.selectedOutputDevice,
      );

      // Transition to the select device state, retaining each still-valid
      // manual choice across explicit and MIDI-triggered refreshes.
      _cubit._emitState(
        DistingState.selectDevice(
          inputDevices: inputDevices,
          outputDevices: outputDevices,
          canWorkOffline: canWorkOffline,
          selectedInputDevice: selectedInputDevice,
          selectedOutputDevice: selectedOutputDevice,
          selectedSysExId: selectionState?.selectedSysExId ?? 0,
        ),
      );
      StartupLogService.log(
        'DistingCubit.loadDevices: device selection updated; '
        'inputs=${devices['input']?.length ?? 0}, '
        'outputs=${devices['output']?.length ?? 0}, '
        'canWorkOffline=$canWorkOffline',
      );

      // Start listening for MIDI device connection changes
      startMidiSetupListener();
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.loadDevices: failed to refresh MIDI device list',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      final currentState = _cubit.state;
      if (previousState is DistingStateSelectDevice) {
        if (currentState is DistingStateSelectDevice) {
          startMidiSetupListener();
        }
        return;
      }
      if (currentState is! DistingStateInitial) {
        return;
      }
      _cubit._emitState(
        const DistingState.selectDevice(
          inputDevices: [],
          outputDevices: [],
          canWorkOffline: false,
        ),
      );

      // Still start listening even on error
      startMidiSetupListener();
    }
  }

  /// Starts listening for MIDI setup changes (device connections/disconnections).
  /// Refreshes device list while selecting a device, and monitors selected
  /// endpoints for loss/return while an online session is active.
  void startMidiSetupListener() {
    // Cancel any existing subscription to avoid duplicates
    _cubit._midiSetupSubscription?.cancel();
    _cubit._midiSetupSubscription = null;

    if (_cubit.isClosed) return;

    // Subscribe to MIDI setup changes
    _cubit._midiSetupSubscription = _cubit._midiCommand.onMidiSetupChanged
        ?.listen((_) {
          if (_cubit.isClosed) return;
          StartupLogService.log('DistingCubit: MIDI setup changed');
          final currentState = _cubit.state;
          if (currentState is DistingStateInitial ||
              currentState is DistingStateSelectDevice) {
            loadDevices();
          } else if (_activeTarget != null) {
            _onOnlineSetupChanged(_sessionEpoch, _attemptEpoch);
          }
        });
    StartupLogService.log(
      'DistingCubit: MIDI setup listener '
      '${_cubit._midiSetupSubscription == null ? 'not available' : 'started'}',
    );
  }

  /// Stops listening for MIDI setup changes.
  void stopMidiSetupListener() {
    _cubit._midiSetupSubscription?.cancel();
    _cubit._midiSetupSubscription = null;
  }

  void _startOnlineMonitoring({
    required int sessionEpoch,
    required int attemptEpoch,
    required MidiDevice inputDevice,
    required MidiDevice outputDevice,
  }) {
    if (_cubit.isClosed ||
        sessionEpoch != _sessionEpoch ||
        attemptEpoch != _attemptEpoch) {
      return;
    }

    startMidiSetupListener();
    _stopDeviceStateSubscriptions();

    void onEndpointState(MidiConnectionState state) {
      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }
      if (state == MidiConnectionState.disconnected) {
        _handleSessionLoss(
          sessionEpoch,
          attemptEpoch,
          reason: SchedulerTerminationReason.connectionLost,
        );
      }
    }

    _inputStateSubscription = inputDevice.onConnectionStateChanged.listen(
      onEndpointState,
    );
    if (outputDevice.id != inputDevice.id) {
      _outputStateSubscription = outputDevice.onConnectionStateChanged.listen(
        onEndpointState,
      );
    }
  }

  void _onOnlineSetupChanged(int sessionEpoch, int attemptEpoch) {
    if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;
    if (_healthState == ConnectionHealthState.recoveryExhausted ||
        _healthState == ConnectionHealthState.closed ||
        _healthState == ConnectionHealthState.disconnected) {
      return;
    }

    if (_healthState == ConnectionHealthState.lost ||
        _healthState == ConnectionHealthState.recovering) {
      _wakeRecovery();
      return;
    }

    if (_onlineSnapshotCheckInFlight) {
      _onlineSnapshotCheckPending = true;
      return;
    }

    _onlineSnapshotCheckInFlight = true;
    unawaited(
      _inspectOnlineEndpointsSnapshot(sessionEpoch, attemptEpoch).whenComplete(
        () {
          _onlineSnapshotCheckInFlight = false;
          if (_onlineSnapshotCheckPending) {
            _onlineSnapshotCheckPending = false;
            if (!_cubit.isClosed && _sessionEpoch == sessionEpoch) {
              _onOnlineSetupChanged(_sessionEpoch, _attemptEpoch);
            }
          }
        },
      ),
    );
  }

  Future<void> _inspectOnlineEndpointsSnapshot(
    int sessionEpoch,
    int attemptEpoch,
  ) async {
    if (_cubit.isClosed ||
        sessionEpoch != _sessionEpoch ||
        attemptEpoch != _attemptEpoch) {
      return;
    }
    final activeInput = _activeInputDevice;
    final activeOutput = _activeOutputDevice;
    if (activeInput == null || activeOutput == null) return;

    List<MidiDevice>? devices;
    try {
      devices = await _cubit._midiCommand.devices.timeout(_config.probeTimeout);
    } catch (_) {
      return;
    }
    if (_cubit.isClosed ||
        sessionEpoch != _sessionEpoch ||
        attemptEpoch != _attemptEpoch) {
      return;
    }
    if (devices == null) return;

    final hasInput = devices.any(
      (device) =>
          device.id == activeInput.id &&
          device.inputPorts.isNotEmpty &&
          device.connectionState != MidiConnectionState.disconnected,
    );
    final hasOutput = devices.any(
      (device) =>
          device.id == activeOutput.id &&
          device.outputPorts.isNotEmpty &&
          device.connectionState != MidiConnectionState.disconnected,
    );

    if (!hasInput || !hasOutput) {
      _handleSessionLoss(
        sessionEpoch,
        attemptEpoch,
        reason: SchedulerTerminationReason.connectionLost,
      );
    }
  }

  Future<IDistingMidiManager> createFirmwareMidiManager(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    _cubit._midiSetupSubscription?.pause();
    final connected = <MidiDevice>[];
    final command = _cubit._midiCommand;
    Future<void> connect(MidiDevice device) async {
      var expired = false;
      void release() {
        try {
          command.disconnectDevice(device);
        } catch (_) {}
      }

      final connection = command.connectToDevice(device);
      unawaited(
        connection.then((_) {
          if (expired) release();
        }, onError: (Object _) {}),
      );
      await connection.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          expired = true;
          release();
          throw TimeoutException('Firmware MIDI connection timed out');
        },
      );
      connected.add(device);
    }

    try {
      await connect(inputDevice);
      if (inputDevice.id != outputDevice.id) {
        await connect(outputDevice);
      }
      return DistingMidiManager(
        midiCommand: _cubit._midiCommand,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
      );
    } catch (_) {
      for (final device in connected) {
        try {
          _cubit._midiCommand.disconnectDevice(device);
        } catch (_) {}
      }
      _cubit._midiSetupSubscription?.resume();
      rethrow;
    }
  }

  void disconnect() {
    _sessionEpoch++;
    _attemptEpoch++;
    _syncGeneration++;
    _cancelRecoveryWait();
    _stopDeviceStateSubscriptions();
    stopMidiSetupListener();
    if (_healthState != ConnectionHealthState.closed) {
      _healthState = ConnectionHealthState.disconnected;
    }
    _activeTarget = null;
    _activeManager = null;
    _activeInputDevice = null;
    _activeOutputDevice = null;

    _cubit._remoteDelegate.clearConnection();
    _cubit._memoryDelegate.clearConnection();
    _cubit._monitoringDelegate.pauseCpuMonitoring();
    _cubit._parameterRefreshDelegate.stopForConnectionChange();
    _cubit._parameterFetchDelegate.clearPendingRetries();
    _cubit._disposeParameterQueue();

    MidiDevice? inputDevice;
    MidiDevice? outputDevice;
    IDistingMidiManager? manager;

    switch (_cubit.state) {
      case DistingStateInitial():
      case DistingStateSelectDevice():
        break;
      case DistingStateConnected connectedState:
        inputDevice = connectedState.inputDevice;
        outputDevice = connectedState.outputDevice;
        manager = connectedState.disting;
        break;
      case DistingStateSynchronized syncstate:
        inputDevice = syncstate.inputDevice;
        outputDevice = syncstate.outputDevice;
        manager = syncstate.disting;
        break;
    }

    // Stop CC notification processing before disconnecting
    _cubit._ccNotificationDelegate.stop();

    // Synchronously gate new admission and timers before native port teardown,
    // while keeping native disconnectDevice before manager.dispose().
    if (manager is DistingMidiManager) {
      manager.markConnectionLost(reason: SchedulerTerminationReason.disposed);
    }

    // Disconnect MIDI devices FIRST (closes ALSA ports and stops isolate)
    // Must happen before manager.dispose() to avoid read/write on closed ports
    if (inputDevice != null) {
      try {
        _cubit._midiCommand.disconnectDevice(inputDevice);
      } catch (_) {}
    }
    if (outputDevice != null && outputDevice.id != inputDevice?.id) {
      try {
        _cubit._midiCommand.disconnectDevice(outputDevice);
      } catch (_) {}
    }

    // Now dispose the manager (safe since devices are already disconnected)
    manager?.dispose();

    // The Windows plugin owns a process-wide NativeCallable for WinMM input.
    // Tearing MidiCommand down closes it, and later discovery reuses the closed
    // callback address, leaving the device list empty until process restart.
    if (!_cubit._isWindows) {
      _cubit._midiCommand.dispose();
      _cubit._midiCommand = _cubit._midiCommandFactory();
    }
  }

  static const _syncTimeout = Duration(minutes: 3);

  void _emitSyncProgress(
    String status, {
    double? progress,
    int? syncGeneration,
  }) {
    if (syncGeneration != null && syncGeneration != _syncGeneration) return;
    final currentState = _cubit.state;
    if (currentState is DistingStateConnected) {
      _cubit._emitState(
        currentState.copyWith(syncStatus: status, syncProgress: progress),
      );
    }
  }

  Future<bool> performSyncAndEmit({
    DistingStateSynchronized? preserveSlotSpecificationsFrom,
    int? expectedAttemptEpoch,
  }) async {
    StartupLogService.log(
      'DistingCubit.performSyncAndEmit: starting Disting NT sync',
    );
    final currentState = _cubit.state;
    final generation = ++_syncGeneration;
    final attemptEpoch = expectedAttemptEpoch ?? _attemptEpoch;
    var syncCommitted = false;
    MidiDevice? inputDevice; // Variables to hold devices from state
    MidiDevice? outputDevice;

    if (currentState is DistingStateConnected) {
      inputDevice = currentState.inputDevice;
      outputDevice = currentState.outputDevice;
    } else if (currentState is DistingStateSynchronized &&
        !currentState.offline) {
      inputDevice = currentState.inputDevice;
      outputDevice = currentState.outputDevice;
    } else {
      StartupLogService.log(
        'DistingCubit.performSyncAndEmit: skipped because no online Disting NT connection is active',
      );
      return false;
    }

    // Append retains construction metadata for unchanged existing slots, while
    // the sync itself runs in Connected state so old slot updates cannot race it.
    final specificationSource =
        preserveSlotSpecificationsFrom ??
        (currentState is DistingStateSynchronized ? currentState : null);

    // Now state is confirmed, get manager
    final IDistingMidiManager distingManager = _cubit.requireDisting();

    bool isStillCurrent() =>
        !_cubit.isClosed &&
        attemptEpoch == _attemptEpoch &&
        _isCurrentSync(generation, currentState, distingManager);

    try {
      await Future(() async {
        // --- Fetch ALL data from device REGARDLESS ---

        _emitSyncProgress(
          'Querying device...',
          progress: 0.0,
          syncGeneration: generation,
        );

        // Load algorithm library (try cache first for fast startup)
        List<AlgorithmInfo> algorithms = [];
        int numInPreset = 0;
        int numAlgorithms = 0;
        SlotCountInfo? slotCountInfo;
        try {
          numAlgorithms = await distingManager.requestNumberOfAlgorithms() ?? 0;
          slotCountInfo = await distingManager.requestSlotCountInfo();
          numInPreset = slotCountInfo?.slotCount ?? 0;

          // Try to load cached algorithms synchronously for fast startup
          if (numAlgorithms > 0) {
            final cacheFreshnessDays = SettingsService().algorithmCacheDays;
            final cachedAlgorithms = await _cubit._metadataDao
                .getAlgorithmInfoCache(
                  numAlgorithms,
                  cacheFreshnessDays: cacheFreshnessDays,
                );
            if (cachedAlgorithms != null &&
                cachedAlgorithms.length == numAlgorithms) {
              // Cache hit - use cached data immediately
              algorithms = cachedAlgorithms;
            }
          }
        } on DistingSchedulerClosedException {
          rethrow;
        } catch (e, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);
        }

        if (!isStillCurrent()) return;

        _emitSyncProgress(
          'Reading firmware version...',
          progress: 0.15,
          syncGeneration: generation,
        );

        String versionResponse;
        try {
          versionResponse = await distingManager.requestVersionString() ?? "";
        } on AmbiguousResponseAttributionException {
          versionResponse =
              _cubit._lastKnownFirmwareVersion?.versionString ?? "";
        }
        if (!isStillCurrent()) return;

        final versionParts = versionResponse.split('\n');
        final distingVersion = versionParts[0];
        final firmwareDate = versionParts.length > 1 ? versionParts[1] : null;
        final firmwareVersion = FirmwareVersion(
          distingVersion,
          date: firmwareDate,
        );
        final deviceIoProfile = DeviceIoProfile.resolve(
          slotCountInfo: slotCountInfo,
          firmwareVersion: firmwareVersion,
        );
        _cubit._lastKnownFirmwareVersion = firmwareVersion;
        // Set the parameter unit scheme based on firmware version
        ParameterEditorRegistry.setFirmwareVersion(firmwareVersion);

        _emitSyncProgress(
          'Reading preset...',
          progress: 0.25,
          syncGeneration: generation,
        );
        String presetName;
        try {
          presetName = await distingManager.requestPresetName() ?? "Default";
        } on AmbiguousResponseAttributionException {
          presetName = "Default";
        }
        if (!isStillCurrent()) return;

        _emitSyncProgress(
          'Loading unit strings...',
          progress: 0.30,
          syncGeneration: generation,
        );
        List<String> unitStrings;
        try {
          unitStrings = await distingManager.requestUnitStrings() ?? [];
        } on AmbiguousResponseAttributionException {
          unitStrings = [];
        }
        if (!isStillCurrent()) return;

        _emitSyncProgress(
          'Loading slots...',
          progress: 0.35,
          syncGeneration: generation,
        );
        List<Slot> slots = await _cubit.fetchSlots(
          numInPreset,
          distingManager,
          onSlotProgress: (completed, total) {
            _emitSyncProgress(
              'Loading slot $completed of $total...',
              progress: 0.35 + (completed / total) * 0.55,
              syncGeneration: generation,
            );
          },
        );
        if (!isStillCurrent()) return;
        // A cached library may have observed an unloaded plug-in with zero
        // specifications. Active slot readback can prove that cache incomplete.
        // Use the existing background library refresh rather than guessing the
        // meaning of the slot's construction values (e.g. Channels).
        if (algorithms.isNotEmpty) {
          final cachedByGuid = {for (final info in algorithms) info.guid: info};
          final incomplete = slots.any(
            (slot) =>
                slot.algorithm.specifications.isNotEmpty &&
                cachedByGuid[slot.algorithm.guid]?.specifications.length !=
                    slot.algorithm.specifications.length,
          );
          if (incomplete) {
            await _cubit._metadataDao.invalidateAlgorithmInfoCache();
            algorithms = [];
          }
        }
        if (!isStillCurrent()) {
          return;
        }
        if (specificationSource != null) {
          slots = _cubit._preserveKnownSlotSpecificationsForRefresh(
            previousState: specificationSource,
            refreshedDisting: distingManager,
            refreshedPresetName: presetName,
            refreshedSlots: slots,
          );
        }

        // Fetch performance page items if firmware supports them (v1.16+)
        List<PerformancePageItem> perfPageItems = [];
        if (firmwareVersion.hasPerfPageItems) {
          _emitSyncProgress(
            'Loading performance pages...',
            progress: 0.90,
            syncGeneration: generation,
          );
          perfPageItems = await _cubit._perfPageDelegate.fetchAllPerfPageItems(
            distingManager,
          );
        }

        if (!isStillCurrent()) {
          return;
        }

        _emitSyncProgress(
          'Finalizing...',
          progress: 0.95,
          syncGeneration: generation,
        );

        // --- Emit final synchronized state --- (Ensure offline is false)
        _cubit._emitState(
          DistingState.synchronized(
            disting: distingManager,
            distingVersion: distingVersion,
            firmwareVersion: firmwareVersion,
            deviceIoProfile: deviceIoProfile,
            presetName: presetName,
            algorithms: algorithms,
            slots: slots,
            unitStrings: unitStrings,
            inputDevice: inputDevice,
            outputDevice: outputDevice,
            loading: false,
            offline: false,
            perfPageItems: perfPageItems,
          ),
        );
        syncCommitted = true;
        StartupLogService.log(
          'DistingCubit.performSyncAndEmit: Disting NT sync complete; '
          'firmware="$distingVersion", preset="$presetName", slots=${slots.length}',
        );

        // Start CC notification processing for push updates
        _cubit._ccNotificationDelegate.start();

        // If cache miss, start background loading for algorithms
        // (now that we're in synchronized state, background loading can update state)
        if (algorithms.isEmpty && numAlgorithms > 0) {
          _cubit._algorithmLibraryDelegate.loadAllAlgorithmsInBackground(
            distingManager,
            numAlgorithms,
          );
        }

        // Start background retry processing for any failed parameter requests
        if (_cubit._parameterFetchDelegate.hasQueuedRetries) {
          _cubit._parameterFetchDelegate
              .processParameterRetryQueue(distingManager)
              .catchError((e) {});
        }

        // Check for firmware updates in background (non-blocking, desktop only)
        // This runs asynchronously and updates state if update is available
        if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
          _cubit.checkForFirmwareUpdate();
        }
      }).timeout(_syncTimeout);
      return syncCommitted;
    } on TimeoutException catch (e, stackTrace) {
      if (_cubit.isClosed || attemptEpoch != _attemptEpoch) return false;
      if (!_invalidateSync(generation)) return false;
      StartupLogService.logError(
        'DistingCubit.performSyncAndEmit: sync timed out while querying Disting NT',
        e,
        stackTrace,
      );
      _emitSyncProgress(
        'Synchronization timed out. The device may not be responding.\n'
        'Please check your MIDI connections and try again.',
      );
      return false;
    } on DistingSchedulerClosedException {
      if (_cubit.isClosed || attemptEpoch != _attemptEpoch) return false;
      _invalidateSync(generation);
      return false;
    } catch (e, stackTrace) {
      if (_cubit.isClosed || attemptEpoch != _attemptEpoch) return false;
      if (!_invalidateSync(generation)) return false;
      StartupLogService.logError(
        'DistingCubit.performSyncAndEmit: sync failed while querying Disting NT',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      // Do NOT store connection details if sync fails
      await loadDevices();
      return false;
    }
  }

  bool _invalidateSync(int generation) {
    if (generation != _syncGeneration) return false;
    _syncGeneration++;
    return true;
  }

  bool _isCurrentSync(
    int generation,
    DistingState startingState,
    IDistingMidiManager disting,
  ) {
    if (generation != _syncGeneration) return false;
    final currentState = _cubit.state;
    return switch (startingState) {
      DistingStateSynchronized() =>
        identical(currentState, startingState) &&
            currentState is DistingStateSynchronized &&
            identical(currentState.disting, disting),
      DistingStateConnected() =>
        currentState is DistingStateConnected &&
            identical(currentState.disting, disting),
      _ => false,
    };
  }

  Future<void> _openDevicePairBounded(
    MidiCommand command,
    MidiDevice inputDevice,
    MidiDevice outputDevice, {
    required int sessionEpoch,
    required int attemptEpoch,
    required Duration timeout,
  }) async {
    final opened = <MidiDevice>[];

    void releaseIfUnowned(MidiDevice device) {
      if (_isEndpointOwnedByCurrentSession(command, device.id)) {
        return;
      }
      try {
        command.disconnectDevice(device);
      } catch (_) {}
    }

    Future<void> openOne(MidiDevice device) async {
      var timedOutOrStale = false;
      final future = command.connectToDevice(device);
      unawaited(
        future.then((_) {
          if (timedOutOrStale ||
              _cubit.isClosed ||
              sessionEpoch != _sessionEpoch ||
              attemptEpoch != _attemptEpoch) {
            releaseIfUnowned(device);
          }
        }, onError: (Object _) {}),
      );

      await future.timeout(
        timeout,
        onTimeout: () {
          timedOutOrStale = true;
          releaseIfUnowned(device);
          throw TimeoutException(
            'Timed out opening MIDI device "${device.name}" (${device.id})',
            timeout,
          );
        },
      );

      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        timedOutOrStale = true;
        releaseIfUnowned(device);
        throw StateError('Connection attempt superseded');
      }
      opened.add(device);
    }

    try {
      await openOne(inputDevice);
      if (outputDevice.id != inputDevice.id) {
        await openOne(outputDevice);
      }
    } catch (_) {
      for (final device in opened) {
        releaseIfUnowned(device);
      }
      rethrow;
    }
  }

  Future<void> _writeRealTimeClock(
    DistingMidiManager manager, {
    required int sessionEpoch,
    required int attemptEpoch,
  }) async {
    if (_cubit.isClosed ||
        sessionEpoch != _sessionEpoch ||
        attemptEpoch != _attemptEpoch) {
      return;
    }
    // The device has no timezone info — it stamps FAT files directly from
    // the value we send, so we must send local time, not UTC.
    try {
      final now = clock.now();
      final localAsUtc = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
      final localEpoch = localAsUtc.millisecondsSinceEpoch ~/ 1000;
      await manager.requestSetRealTimeClock(localEpoch);
      StartupLogService.log(
        'DistingCubit.connectToDevices: device clock synchronized',
      );
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.connectToDevices: device clock sync failed; continuing',
        e,
        stackTrace,
      );
    }
  }

  Future<void> connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    if (_cubit.isClosed) return;
    final sessionEpoch = ++_sessionEpoch;
    final attemptEpoch = ++_attemptEpoch;
    _syncGeneration++;
    _cancelRecoveryWait();
    _stopDeviceStateSubscriptions();
    _healthState = ConnectionHealthState.connecting;
    _activeTarget = null;

    _cubit._remoteDelegate.clearConnection();
    _cubit._memoryDelegate.clearConnection();
    _cubit._monitoringDelegate.pauseCpuMonitoring();
    _cubit._parameterRefreshDelegate.stopForConnectionChange();
    _cubit._parameterFetchDelegate.clearPendingRetries();
    _cubit._disposeParameterQueue();

    StartupLogService.log(
      'DistingCubit.connectToDevices: attempting connection to '
      'input="${inputDevice.name}" (${inputDevice.id}), '
      'output="${outputDevice.name}" (${outputDevice.id}), sysExId=$sysExId',
    );
    // Get the potentially existing manager AND devices from the CURRENT state
    final currentState = _cubit.state;
    MidiDevice? existingInputDevice = _activeInputDevice;
    MidiDevice? existingOutputDevice = _activeOutputDevice;
    if (currentState is DistingStateConnected) {
      existingInputDevice ??= currentState.inputDevice;
      existingOutputDevice ??= currentState.outputDevice;
    } else if (currentState is DistingStateSynchronized) {
      existingInputDevice ??= currentState.inputDevice;
      existingOutputDevice ??= currentState.outputDevice;
    }
    final existingManager = _activeManager ?? _cubit.disting();
    _activeManager = null;
    _activeInputDevice = null;
    _activeOutputDevice = null;

    // Stop listening for MIDI setup changes while opening ports
    stopMidiSetupListener();

    final command = _cubit._midiCommand;
    try {
      // Stop CC notifications before disconnecting (avoids callbacks on disposed manager)
      _cubit._ccNotificationDelegate.stop();

      // Disconnect and dispose any existing managers first
      if (existingManager != null) {
        if (existingManager is DistingMidiManager) {
          existingManager.markConnectionLost(
            reason: SchedulerTerminationReason.disposed,
          );
        }
        if (existingInputDevice != null) {
          try {
            command.disconnectDevice(existingInputDevice);
          } catch (_) {}
        }
        if (existingOutputDevice != null &&
            existingOutputDevice.id != existingInputDevice?.id) {
          try {
            command.disconnectDevice(existingOutputDevice);
          } catch (_) {}
        }
        existingManager.dispose();
      }
      _cubit._offlineManager?.dispose();
      _cubit._offlineManager = null;

      // Connect to the selected devices with bounded awaits and epoch fencing.
      StartupLogService.log(
        'DistingCubit.connectToDevices: opening MIDI endpoints '
        '"${inputDevice.name}" / "${outputDevice.name}"',
      );
      await _openDevicePairBounded(
        command,
        inputDevice,
        outputDevice,
        sessionEpoch: sessionEpoch,
        attemptEpoch: attemptEpoch,
        timeout: _config.connectTimeout,
      );

      final prefs = await _cubit._prefs;
      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }
      await prefs.setString('selectedInputMidiDevice', inputDevice.name);
      await prefs.setString('selectedOutputMidiDevice', outputDevice.name);
      await prefs.setInt('selectedSysExId', sysExId);

      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }

      // Resolve or carry forward quarantine lineage for this endpoint + SysEx ID.
      final lineage = _resolveLineageForEndpoint(inputDevice, sysExId);
      final target = _OnlineConnectionTarget(
        inputId: inputDevice.id,
        inputName: inputDevice.name,
        outputId: outputDevice.id,
        outputName: outputDevice.name,
        sysExId: sysExId,
        lastInputDevice: inputDevice,
        lastOutputDevice: outputDevice,
        lineage: lineage,
      );

      // Create the NEW online manager bound to this epoch & lineage
      late final DistingMidiManager newDistingManager;
      newDistingManager = DistingMidiManager(
        midiCommand: command,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
        attributionTracker: lineage,
        onConnectionLost: () {
          _handleSessionLoss(
            sessionEpoch,
            attemptEpoch,
            reason: SchedulerTerminationReason.receiveStreamClosed,
          );
        },
      );

      _activeTarget = target;
      _activeManager = newDistingManager;
      _activeInputDevice = inputDevice;
      _activeOutputDevice = outputDevice;

      // Emit Connected state WITH the new manager AND devices
      _cubit._emitState(
        DistingState.connected(
          disting: newDistingManager,
          inputDevice: inputDevice,
          outputDevice: outputDevice,
          offline: false,
        ),
      );
      StartupLogService.log(
        'DistingCubit.connectToDevices: MIDI ports opened; querying Disting NT next',
      );

      // Create manager-bound parameter queue
      _cubit._createParameterQueue();

      // Store these details as the last successful ONLINE connection
      _cubit._lastOnlineInputDevice = inputDevice;
      _cubit._lastOnlineOutputDevice = outputDevice;
      _cubit._lastOnlineSysExId = sysExId;

      // Monitor selected endpoints while online so USB disconnect/reboot is detected.
      _startOnlineMonitoring(
        sessionEpoch: sessionEpoch,
        attemptEpoch: attemptEpoch,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
      );

      if (!newDistingManager.isTransportUsable) {
        _handleSessionLoss(
          sessionEpoch,
          attemptEpoch,
          reason: SchedulerTerminationReason.receiveStreamUnavailable,
        );
        return;
      }

      await _writeRealTimeClock(
        newDistingManager,
        sessionEpoch: sessionEpoch,
        attemptEpoch: attemptEpoch,
      );

      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }

      final syncSucceeded = await performSyncAndEmit(
        expectedAttemptEpoch: attemptEpoch,
      );
      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }
      if (syncSucceeded) {
        _healthState = ConnectionHealthState.usable;
        _cubit._monitoringDelegate.resumeCpuMonitoring();
      }
      StartupLogService.log(
        'DistingCubit.connectToDevices: connection flow completed; '
        'syncSucceeded=$syncSucceeded',
      );
    } catch (e, stackTrace) {
      if (_cubit.isClosed ||
          sessionEpoch != _sessionEpoch ||
          attemptEpoch != _attemptEpoch) {
        return;
      }
      StartupLogService.logError(
        'DistingCubit.connectToDevices: connection failed',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      _healthState = ConnectionHealthState.disconnected;
      _activeTarget = null;
      _activeManager = null;
      _activeInputDevice = null;
      _activeOutputDevice = null;
      _cubit._lastOnlineInputDevice = null;
      _cubit._lastOnlineOutputDevice = null;
      _cubit._lastOnlineSysExId = null;
      if (!_isEndpointOwnedByCurrentSession(command, inputDevice.id)) {
        try {
          command.disconnectDevice(inputDevice);
        } catch (_) {}
      }
      if (outputDevice.id != inputDevice.id &&
          !_isEndpointOwnedByCurrentSession(command, outputDevice.id)) {
        try {
          command.disconnectDevice(outputDevice);
        } catch (_) {}
      }
      await loadDevices();
    }
  }

  void _handleSessionLoss(
    int sessionEpoch,
    int attemptEpoch, {
    required SchedulerTerminationReason reason,
  }) {
    if (_cubit.isClosed ||
        sessionEpoch != _sessionEpoch ||
        attemptEpoch != _attemptEpoch) {
      return;
    }
    final target = _activeTarget;
    if (target == null) return;

    // Advance attempt epoch to fence all in-flight syncs/callbacks from the
    // lost session while preserving sessionEpoch for the single recovery owner.
    _attemptEpoch++;
    _syncGeneration++;
    _stopDeviceStateSubscriptions();

    // Stop all background/queued producers immediately so no old intents or
    // pending parameter writes can leak across the loss boundary.
    _cubit._remoteDelegate.clearConnection();
    _cubit._memoryDelegate.clearConnection();
    _cubit._ccNotificationDelegate.stop();
    _cubit._monitoringDelegate.pauseCpuMonitoring();
    _cubit._parameterRefreshDelegate.stopForConnectionChange();
    _cubit._parameterFetchDelegate.clearPendingRetries();
    _cubit._disposeParameterQueue();

    final oldManager = _activeManager;
    final oldInput = _activeInputDevice;
    final oldOutput = _activeOutputDevice;
    _activeManager = null;
    _activeInputDevice = null;
    _activeOutputDevice = null;

    // Gate scheduler synchronously before native disconnect so zero packets
    // transmit after loss and all in-flight/queued futures settle phase-aware.
    if (oldManager is DistingMidiManager) {
      oldManager.markConnectionLost(reason: reason);
    }

    if (oldInput != null) {
      try {
        _cubit._midiCommand.disconnectDevice(oldInput);
      } catch (_) {}
    }
    if (oldOutput != null && oldOutput.id != oldInput?.id) {
      try {
        _cubit._midiCommand.disconnectDevice(oldOutput);
      } catch (_) {}
    }

    try {
      oldManager?.dispose();
    } catch (_) {}

    // Keep Windows MidiCommand client lifetime intact (WinMM NativeCallable).
    // Recreate client on non-Windows platforms for fresh CoreMIDI/ALSA state.
    if (!_cubit._isWindows) {
      stopMidiSetupListener();
      try {
        _cubit._midiCommand.dispose();
      } catch (_) {}
      _cubit._midiCommand = _cubit._midiCommandFactory();
    }
    startMidiSetupListener();

    _healthState = ConnectionHealthState.lost;
    _cubit._emitState(
      DistingState.connected(
        disting: oldManager ?? MockDistingMidiManager(),
        inputDevice: target.lastInputDevice,
        outputDevice: target.lastOutputDevice,
        offline: false,
        loading: true,
        syncStatus: 'MIDI connection lost. Waiting for device to reconnect...',
      ),
    );

    _ensureRecoveryOwner(sessionEpoch, target);
  }

  Future<void> retryReconnect() async {
    if (_cubit.isClosed) return;
    final target = _activeTarget;
    if (target == null) return;
    if (_healthState == ConnectionHealthState.usable) return;

    final sessionEpoch = _sessionEpoch;
    _attemptEpoch++;
    _healthState = ConnectionHealthState.lost;
    startMidiSetupListener();
    await _ensureRecoveryOwner(sessionEpoch, target);
  }

  Future<void> _ensureRecoveryOwner(
    int sessionEpoch,
    _OnlineConnectionTarget target,
  ) {
    final existing = _recoveryTask;
    if (existing != null && _recoverySessionEpoch == sessionEpoch) {
      _wakeRecovery();
      return existing;
    }

    _recoverySessionEpoch = sessionEpoch;
    late final Future<void> task;
    task = _runRecoveryLoop(sessionEpoch, target).whenComplete(() {
      if (identical(_recoveryTask, task)) {
        _recoveryTask = null;
        _recoverySessionEpoch = null;
      }
    });
    _recoveryTask = task;
    return task;
  }

  ({MidiDevice input, MidiDevice output})? _resolveTargetEndpoints(
    List<MidiDevice> devices,
    _OnlineConnectionTarget target,
  ) {
    MidiDevice? resolveDirection({
      required String expectedId,
      required String expectedName,
      required bool input,
    }) {
      final directional = devices.where(
        (device) => input
            ? device.inputPorts.isNotEmpty
            : device.outputPorts.isNotEmpty,
      );
      if (devices.any((device) => device.id == expectedId)) {
        final byId = directional.where((device) => device.id == expectedId);
        return byId.length == 1 ? byId.single : null;
      }
      final normalizedExpected = expectedName.trim().toLowerCase();
      if (normalizedExpected.isEmpty) return null;
      final byName = directional
          .where(
            (device) => device.name.trim().toLowerCase() == normalizedExpected,
          )
          .toList(growable: false);
      return byName.length == 1 ? byName.single : null;
    }

    final input = resolveDirection(
      expectedId: target.inputId,
      expectedName: target.inputName,
      input: true,
    );
    final output = resolveDirection(
      expectedId: target.outputId,
      expectedName: target.outputName,
      input: false,
    );
    if (input == null || output == null) return null;
    return (input: input, output: output);
  }

  Future<void> _waitForRecoveryRetry(Duration delay) async {
    _cancelRecoveryWait();
    if (_cubit.isClosed) return;
    final completer = Completer<void>();
    _recoveryWakeCompleter = completer;
    _recoveryWaitTimer = Timer(delay, () {
      _recoveryWaitTimer = null;
      if (identical(_recoveryWakeCompleter, completer)) {
        _recoveryWakeCompleter = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future;
  }

  void _enterRecoveryExhausted(
    int sessionEpoch,
    _OnlineConnectionTarget target,
  ) {
    if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;
    _cancelRecoveryWait();
    _stopDeviceStateSubscriptions();
    _healthState = ConnectionHealthState.recoveryExhausted;
    final currentState = _cubit.state;
    final manager = currentState is DistingStateConnected
        ? currentState.disting
        : (_activeManager ?? MockDistingMidiManager());
    _cubit._emitState(
      DistingState.connected(
        disting: manager,
        inputDevice: target.lastInputDevice,
        outputDevice: target.lastOutputDevice,
        offline: false,
        loading: false,
        syncStatus: 'Connection recovery timed out. Check your MIDI connection and try again.',
      ),
    );
  }

  Future<void> _runRecoveryLoop(
    int sessionEpoch,
    _OnlineConnectionTarget target,
  ) async {
    final deadline = clock.now().add(_config.maxRecoveryDuration);
    var attempts = 0;
    var backoff = _config.initialRetryDelay;

    while (!_cubit.isClosed && sessionEpoch == _sessionEpoch) {
      final remaining = deadline.difference(clock.now());
      if (attempts >= _config.maxRecoveryAttempts ||
          remaining <= Duration.zero) {
        _enterRecoveryExhausted(sessionEpoch, target);
        return;
      }

      List<MidiDevice>? devices;
      try {
        devices = await _cubit._midiCommand.devices.timeout(
          _config.probeTimeout,
        );
      } catch (_) {
        devices = null;
      }
      if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;

      final pair = devices == null
          ? null
          : _resolveTargetEndpoints(devices, target);
      if (pair == null) {
        final waitRemaining = deadline.difference(clock.now());
        if (waitRemaining <= Duration.zero) {
          _enterRecoveryExhausted(sessionEpoch, target);
          return;
        }
        final delay = backoff < waitRemaining ? backoff : waitRemaining;
        await _waitForRecoveryRetry(delay);
        final doubled = backoff * 2;
        backoff = doubled > _config.maxRetryDelay
            ? _config.maxRetryDelay
            : doubled;
        continue;
      }

      attempts++;
      final attemptEpoch = ++_attemptEpoch;
      _healthState = ConnectionHealthState.recovering;

      // Update endpoint alias tracking while preserving the SAME quarantine
      // lineage across changed OS endpoint IDs and MidiCommand replacements.
      target.inputId = pair.input.id;
      target.outputId = pair.output.id;
      target.lastInputDevice = pair.input;
      target.lastOutputDevice = pair.output;
      final normalizedName = target.inputName.trim().toLowerCase();
      _rememberLineage(
        '${pair.input.id}|${target.sysExId}',
        normalizedName.isEmpty ? null : '$normalizedName|${target.sysExId}',
        target.lineage,
      );

      final command = _cubit._midiCommand;
      DistingMidiManager? candidateManager;
      var opened = false;
      try {
        await _openDevicePairBounded(
          command,
          pair.input,
          pair.output,
          sessionEpoch: sessionEpoch,
          attemptEpoch: attemptEpoch,
          timeout: _config.connectTimeout,
        );
        opened = true;

        if (_cubit.isClosed || sessionEpoch != _sessionEpoch) {
          return;
        }
        if (attemptEpoch != _attemptEpoch) {
          continue;
        }

        candidateManager = DistingMidiManager(
          midiCommand: command,
          inputDevice: pair.input,
          outputDevice: pair.output,
          sysExId: target.sysExId,
          attributionTracker: target.lineage,
          onConnectionLost: () {
            _handleSessionLoss(
              sessionEpoch,
              attemptEpoch,
              reason: SchedulerTerminationReason.receiveStreamClosed,
            );
          },
        );

        _activeManager = candidateManager;
        _activeInputDevice = pair.input;
        _activeOutputDevice = pair.output;
        _startOnlineMonitoring(
          sessionEpoch: sessionEpoch,
          attemptEpoch: attemptEpoch,
          inputDevice: pair.input,
          outputDevice: pair.output,
        );

        // Validate fresh usable read path before publishing Ready/Synchronized.
        final readable = await candidateManager.probeSessionReadable(
          timeout: _config.probeTimeout,
        );
        if (_cubit.isClosed || sessionEpoch != _sessionEpoch) {
          candidateManager.markConnectionLost(
            reason: SchedulerTerminationReason.disposed,
          );
          if (!_isEndpointOwnedByCurrentSession(command, pair.input.id)) {
            try {
              command.disconnectDevice(pair.input);
            } catch (_) {}
          }
          if (pair.output.id != pair.input.id &&
              !_isEndpointOwnedByCurrentSession(command, pair.output.id)) {
            try {
              command.disconnectDevice(pair.output);
            } catch (_) {}
          }
          candidateManager.dispose();
          return;
        }
        if (attemptEpoch != _attemptEpoch) {
          // A rapid reset superseded this attempt; loop immediately.
          continue;
        }
        if (!readable || !candidateManager.isTransportUsable) {
          throw StateError('Replacement MIDI session failed read validation');
        }

        _cubit._emitState(
          DistingState.connected(
            disting: candidateManager,
            inputDevice: pair.input,
            outputDevice: pair.output,
            offline: false,
          ),
        );
        _cubit._createParameterQueue();
        _cubit._lastOnlineInputDevice = pair.input;
        _cubit._lastOnlineOutputDevice = pair.output;
        _cubit._lastOnlineSysExId = target.sysExId;

        await _writeRealTimeClock(
          candidateManager,
          sessionEpoch: sessionEpoch,
          attemptEpoch: attemptEpoch,
        );
        if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;
        if (attemptEpoch != _attemptEpoch) continue;

        final syncSucceeded = await performSyncAndEmit(
          expectedAttemptEpoch: attemptEpoch,
        );
        if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;
        if (attemptEpoch != _attemptEpoch) continue;

        if (syncSucceeded) {
          _healthState = ConnectionHealthState.usable;
          _cubit._monitoringDelegate.resumeCpuMonitoring();
          return;
        }

        throw StateError('Post-reconnect synchronization did not complete');
      } catch (_) {
        if (_cubit.isClosed || sessionEpoch != _sessionEpoch) return;
        if (attemptEpoch != _attemptEpoch) {
          // Superseded by another rapid loss; continue with same recovery owner.
          continue;
        }
        _stopDeviceStateSubscriptions();
        if (identical(_activeManager, candidateManager)) {
          _activeManager = null;
          _activeInputDevice = null;
          _activeOutputDevice = null;
        }
        candidateManager?.markConnectionLost(
          reason: SchedulerTerminationReason.connectionLost,
        );
        if (opened) {
          if (!_isEndpointOwnedByCurrentSession(command, pair.input.id)) {
            try {
              command.disconnectDevice(pair.input);
            } catch (_) {}
          }
          if (pair.output.id != pair.input.id &&
              !_isEndpointOwnedByCurrentSession(command, pair.output.id)) {
            try {
              command.disconnectDevice(pair.output);
            } catch (_) {}
          }
        }
        candidateManager?.dispose();

        if (attempts >= _config.maxRecoveryAttempts) {
          _enterRecoveryExhausted(sessionEpoch, target);
          return;
        }
        final waitRemaining = deadline.difference(clock.now());
        if (waitRemaining <= Duration.zero) {
          _enterRecoveryExhausted(sessionEpoch, target);
          return;
        }
        final delay = backoff < waitRemaining ? backoff : waitRemaining;
        await _waitForRecoveryRetry(delay);
        final doubled = backoff * 2;
        backoff = doubled > _config.maxRetryDelay
            ? _config.maxRetryDelay
            : doubled;
      }
    }
  }

  Future<Map<String, List<MidiDevice>>> _fetchDeviceLists() async {
    final devices = await _cubit._midiCommand.devices;
    devices?.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    final inputDevices =
        devices?.where((it) => it.inputPorts.isNotEmpty).toList() ?? [];
    final outputDevices =
        devices?.where((it) => it.outputPorts.isNotEmpty).toList() ?? [];
    StartupLogService.log(
      'DistingCubit._fetchDeviceLists: visible MIDI devices: '
      '${_describeDevices(devices)}; inputs=${inputDevices.length}, '
      'outputs=${outputDevices.length}',
    );
    if (inputDevices.isEmpty || outputDevices.isEmpty) {
      StartupLogService.log(
        'DistingCubit._fetchDeviceLists: no usable MIDI '
        '${inputDevices.isEmpty ? 'inputs' : ''}'
        '${inputDevices.isEmpty && outputDevices.isEmpty ? ' or ' : ''}'
        '${outputDevices.isEmpty ? 'outputs' : ''} found. '
        'If the Disting NT is expected, check USB cable, power, OS MIDI '
        'permissions/drivers, and whether the device appears in the system MIDI utility.',
      );
    }
    return {'input': inputDevices, 'output': outputDevices};
  }

  Future<String?> probeFirmwareVersion(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId, {
    bool reportTimeout = false,
  }) async {
    if (_firmwareProbeBusy) return null;
    _firmwareProbeBusy = true;
    var abandoned = false;
    try {
      final connection = _cubit.createFirmwareMidiManager(
        inputDevice,
        outputDevice,
        sysExId,
      );
      unawaited(
        connection.then(
          (manager) {
            if (abandoned) {
              _cubit.disposeFirmwareMidiManager(
                manager,
                inputDevice,
                outputDevice,
              );
              _firmwareProbeBusy = false;
            }
          },
          onError: (Object _) {
            if (abandoned) _firmwareProbeBusy = false;
          },
        ),
      );
      final manager = await connection.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          abandoned = true;
          throw TimeoutException('Firmware MIDI connection timed out');
        },
      );
      try {
        return await manager.requestVersionString().timeout(
          const Duration(seconds: 3),
        );
      } finally {
        _cubit.disposeFirmwareMidiManager(manager, inputDevice, outputDevice);
      }
    } on TimeoutException {
      if (reportTimeout) rethrow;
      return null;
    } catch (_) {
      return null;
    } finally {
      if (!abandoned) _firmwareProbeBusy = false;
    }
  }

  Future<String?> probeFreshFirmwareVersion(
    String? inputName,
    String? outputName,
    int sysExId, {
    String? inputDeviceId,
    String? outputDeviceId,
  }) async {
    if (inputName == null || outputName == null) return null;
    // Packet metadata can rename cached MidiDevice objects after connection.
    // Saved discovery names are applicable only to that same selected pair,
    // never to a manually selected different module.
    var canonicalInput = inputName;
    var canonicalOutput = outputName;
    final knownInput =
        inputDeviceId != null &&
        inputDeviceId == _cubit._lastOnlineInputDevice?.id;
    final knownOutput =
        outputDeviceId != null &&
        outputDeviceId == _cubit._lastOnlineOutputDevice?.id;
    if (knownInput || knownOutput) {
      final prefs = await _cubit._prefs;
      if (knownInput) {
        canonicalInput =
            prefs.getString('selectedInputMidiDevice') ?? inputName;
      }
      if (knownOutput) {
        canonicalOutput =
            prefs.getString('selectedOutputMidiDevice') ?? outputName;
      }
    }
    final devices =
        await _cubit._midiCommand.devices.timeout(const Duration(seconds: 2)) ??
        [];
    List<MidiDevice> resolve(String name, String? id, {required bool input}) {
      final directional = devices.where(
        (device) => input
            ? device.inputPorts.isNotEmpty
            : device.outputPorts.isNotEmpty,
      );
      if (id != null && devices.any((device) => device.id == id)) {
        return directional.where((device) => device.id == id).toList();
      }
      return directional
          .where(
            (device) =>
                device.name.trim().toLowerCase() == name.trim().toLowerCase(),
          )
          .toList();
    }

    final inputs = resolve(canonicalInput, inputDeviceId, input: true);
    final outputs = resolve(canonicalOutput, outputDeviceId, input: false);
    if (inputs.length != 1 || outputs.length != 1) return null;
    return _cubit.probeFirmwareVersion(
      inputs.single,
      outputs.single,
      sysExId,
      reportTimeout: true,
    );
  }

  /// Takes a fresh platform MIDI snapshot and checks the expected directions.
  Future<bool> firmwareMidiDevicesAvailable(
    String? expectedInputName,
    String? expectedOutputName,
  ) async {
    final devices = await _cubit._midiCommand.devices ?? [];
    final available = firmwareMidiEndpointsAvailable(
      devices,
      expectedInputName,
      expectedOutputName,
    );
    StartupLogService.log(
      'DistingCubit.firmwareMidiDevicesAvailable: '
      'expectedInput="$expectedInputName", '
      'expectedOutput="$expectedOutputName", available=$available; '
      'snapshot=${_describeDevices(devices)}',
    );
    return available;
  }

  String _describeDevices(List<MidiDevice>? devices) {
    if (devices == null) return 'unavailable';
    if (devices.isEmpty) return 'none';
    return devices
        .map(
          (device) =>
              '"${device.name}" id=${device.id} '
              'inputs=${device.inputPorts.length} outputs=${device.outputPorts.length}',
        )
        .join('; ');
  }
}
