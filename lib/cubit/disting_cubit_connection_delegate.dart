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

class _SelectedMidiTarget {
  const _SelectedMidiTarget({
    required this.inputId,
    required this.inputName,
    required this.outputId,
    required this.outputName,
    required this.sysExId,
  });

  final String inputId;
  final String inputName;
  final String outputId;
  final String outputName;
  final int sysExId;

  String get displayLabel {
    final trimmedInput = inputName.trim();
    final trimmedOutput = outputName.trim();
    if (trimmedInput.isNotEmpty &&
        trimmedInput.toLowerCase() == trimmedOutput.toLowerCase()) {
      return trimmedInput;
    }
    if (trimmedInput.isNotEmpty && trimmedOutput.isNotEmpty) {
      return '$trimmedInput / $trimmedOutput';
    }
    return trimmedInput.isNotEmpty ? trimmedInput : trimmedOutput;
  }
}

class _ConnectionDelegate {
  _ConnectionDelegate(this._cubit);

  final DistingCubit _cubit;
  int _syncGeneration = 0;
  bool _firmwareProbeBusy = false;
  bool _openingConnection = false;
  bool _setupCheckInFlight = false;
  bool _setupCheckPending = false;
  bool _activeDeviceDisconnected = false;
  MidiCommand? _subscribedMidiCommand;
  _SelectedMidiTarget? _activeTarget;
  _SelectedMidiTarget? _lastOnlineTarget;
  _SelectedMidiTarget? _pendingReconnectTarget;
  StreamSubscription<MidiConnectionState>? _inputDeviceStateSub;
  StreamSubscription<MidiConnectionState>? _outputDeviceStateSub;

  int get firmwareSysExId {
    final manager = _cubit.disting();
    if (manager is DistingMidiManager) return manager.sysExId;
    final state = _cubit.state;
    return state is DistingStateSelectDevice ? state.selectedSysExId : 0;
  }

  void dispose() {
    clearConnectionTracking();
    stopMidiSetupListener();
  }

  void clearConnectionTracking() {
    _syncGeneration++;
    _clearActiveDeviceListeners();
    _activeTarget = null;
    _pendingReconnectTarget = null;
    _activeDeviceDisconnected = false;
    _setupCheckPending = false;
  }

  void _clearActiveDeviceListeners() {
    _inputDeviceStateSub?.cancel();
    _inputDeviceStateSub = null;
    _outputDeviceStateSub?.cancel();
    _outputDeviceStateSub = null;
  }

  void _watchActiveDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    IDistingMidiManager manager,
  ) {
    _clearActiveDeviceListeners();
    _activeDeviceDisconnected = false;

    void onConnectionState(MidiConnectionState state) {
      if (state != MidiConnectionState.disconnected) return;
      if (_cubit.isClosed || _openingConnection) return;
      if (!identical(_cubit.disting(), manager)) return;
      _activeDeviceDisconnected = true;
      _triggerSetupCheck();
    }

    _inputDeviceStateSub = inputDevice.onConnectionStateChanged.listen(
      onConnectionState,
    );
    if (outputDevice.id != inputDevice.id) {
      _outputDeviceStateSub = outputDevice.onConnectionStateChanged.listen(
        onConnectionState,
      );
    }
  }

  ({MidiDevice? device, bool ambiguous}) _matchReturningEndpoint(
    List<MidiDevice> devices, {
    required String expectedId,
    required String expectedName,
    required bool input,
  }) {
    final directional = devices.where(
      (device) =>
          input ? device.inputPorts.isNotEmpty : device.outputPorts.isNotEmpty,
    );

    final idMatches = directional
        .where((device) => device.id == expectedId)
        .toList();
    if (idMatches.length == 1) {
      return (device: idMatches.single, ambiguous: false);
    }
    if (devices.any((device) => device.id == expectedId)) {
      return (device: null, ambiguous: false);
    }

    final normalizedExpected = expectedName.trim().toLowerCase();
    if (normalizedExpected.isEmpty) {
      return (device: null, ambiguous: false);
    }
    final nameMatches = directional
        .where(
          (device) => device.name.trim().toLowerCase() == normalizedExpected,
        )
        .toList();
    if (nameMatches.length == 1) {
      return (device: nameMatches.single, ambiguous: false);
    }
    return (device: null, ambiguous: nameMatches.length > 1);
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
    _pendingReconnectTarget = null;
    _cubit._emitState(
      currentState.copyWith(
        selectedInputDevice: inputDevice,
        selectedOutputDevice: outputDevice,
        selectedSysExId: sysExId,
        connectionStatus: null,
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
    if (_pendingReconnectTarget != null) {
      await _checkPendingReconnect(_pendingReconnectTarget!);
      return;
    }
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
      _ensureMidiSetupListener();
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
          _ensureMidiSetupListener();
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
      _ensureMidiSetupListener();
    }
  }

  /// Starts listening for MIDI setup changes (device connections/disconnections).
  void startMidiSetupListener() {
    // Cancel any existing subscription to avoid duplicates
    _cubit._midiSetupSubscription?.cancel();
    _cubit._midiSetupSubscription = null;
    _subscribedMidiCommand = null;

    if (_cubit.isClosed) return;

    // Subscribe to MIDI setup changes
    final command = _cubit._midiCommand;
    _cubit._midiSetupSubscription = command.onMidiSetupChanged?.listen((_) {
      StartupLogService.log('DistingCubit: MIDI setup changed');
      _triggerSetupCheck();
    });
    if (_cubit._midiSetupSubscription != null) {
      _subscribedMidiCommand = command;
    }
    StartupLogService.log(
      'DistingCubit: MIDI setup listener '
      '${_cubit._midiSetupSubscription == null ? 'not available' : 'started'}',
    );
  }

  void _ensureMidiSetupListener() {
    if (_cubit.isClosed) return;
    if (_cubit._midiSetupSubscription != null &&
        identical(_subscribedMidiCommand, _cubit._midiCommand)) {
      return;
    }
    startMidiSetupListener();
  }

  /// Stops listening for MIDI setup changes.
  void stopMidiSetupListener() {
    _cubit._midiSetupSubscription?.cancel();
    _cubit._midiSetupSubscription = null;
    _subscribedMidiCommand = null;
  }

  void _triggerSetupCheck() {
    if (_cubit.isClosed) return;
    if (_setupCheckInFlight || _openingConnection) {
      _setupCheckPending = true;
      return;
    }
    unawaited(_drainSetupChecks());
  }

  Future<void> _drainSetupChecks() async {
    if (_setupCheckInFlight) return;
    _setupCheckInFlight = true;
    try {
      do {
        _setupCheckPending = false;
        if (_cubit.isClosed || _openingConnection) return;
        await _handleMidiSetupChange();
      } while (_setupCheckPending && !_cubit.isClosed && !_openingConnection);
    } finally {
      _setupCheckInFlight = false;
    }
  }

  Future<void> _handleMidiSetupChange() async {
    if (_cubit.isClosed || _openingConnection) return;
    final state = _cubit.state;

    if (state is DistingStateInitial || state is DistingStateSelectDevice) {
      final pendingTarget = _pendingReconnectTarget;
      if (pendingTarget != null) {
        await _checkPendingReconnect(pendingTarget);
      } else {
        await loadDevices();
      }
      return;
    }

    MidiDevice? inputDevice;
    MidiDevice? outputDevice;
    IDistingMidiManager? manager;
    if (state is DistingStateConnected && !state.offline) {
      inputDevice = state.inputDevice;
      outputDevice = state.outputDevice;
      manager = state.disting;
    } else if (state is DistingStateSynchronized &&
        !state.offline &&
        !state.demo) {
      inputDevice = state.inputDevice;
      outputDevice = state.outputDevice;
      manager = state.disting;
    } else {
      return;
    }

    if (inputDevice == null || outputDevice == null) return;

    final target =
        _activeTarget ??
        _SelectedMidiTarget(
          inputId: inputDevice.id,
          inputName: inputDevice.name,
          outputId: outputDevice.id,
          outputName: outputDevice.name,
          sysExId: manager is DistingMidiManager
              ? manager.sysExId
              : (_cubit._lastOnlineSysExId ?? 0),
        );

    final List<MidiDevice> rawDevices;
    try {
      rawDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {
      return;
    }
    if (_cubit.isClosed ||
        _openingConnection ||
        !identical(_cubit.disting(), manager)) {
      return;
    }

    final hasInput = rawDevices.any(
      (device) => device.id == inputDevice!.id && device.inputPorts.isNotEmpty,
    );
    final hasOutput = rawDevices.any(
      (device) =>
          device.id == outputDevice!.id && device.outputPorts.isNotEmpty,
    );
    final lost = _activeDeviceDisconnected || !hasInput || !hasOutput;
    if (!lost) return;

    _teardownOnlineConnection(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      manager: manager,
    );

    final matchedInput = _matchReturningEndpoint(
      rawDevices,
      expectedId: target.inputId,
      expectedName: target.inputName,
      input: true,
    );
    final matchedOutput = _matchReturningEndpoint(
      rawDevices,
      expectedId: target.outputId,
      expectedName: target.outputName,
      input: false,
    );
    if (matchedInput.device != null && matchedOutput.device != null) {
      unawaited(
        _connectToDevices(
          matchedInput.device!,
          matchedOutput.device!,
          target.sysExId,
          reconnectTarget: target,
        ),
      );
      return;
    }

    _pendingReconnectTarget = target;
    await _emitWaitingSelectDevice(
      rawDevices,
      target,
      ambiguous: matchedInput.ambiguous || matchedOutput.ambiguous,
    );
  }

  Future<void> _checkPendingReconnect(_SelectedMidiTarget target) async {
    if (_cubit.isClosed || _openingConnection) return;
    final List<MidiDevice> rawDevices;
    try {
      rawDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {
      _ensureMidiSetupListener();
      return;
    }
    if (_cubit.isClosed ||
        _openingConnection ||
        !identical(_pendingReconnectTarget, target)) {
      return;
    }
    final state = _cubit.state;
    if (state is! DistingStateInitial && state is! DistingStateSelectDevice) {
      return;
    }

    final matchedInput = _matchReturningEndpoint(
      rawDevices,
      expectedId: target.inputId,
      expectedName: target.inputName,
      input: true,
    );
    final matchedOutput = _matchReturningEndpoint(
      rawDevices,
      expectedId: target.outputId,
      expectedName: target.outputName,
      input: false,
    );
    if (matchedInput.device != null && matchedOutput.device != null) {
      unawaited(
        _connectToDevices(
          matchedInput.device!,
          matchedOutput.device!,
          target.sysExId,
          reconnectTarget: target,
        ),
      );
      return;
    }

    await _emitWaitingSelectDevice(
      rawDevices,
      target,
      ambiguous: matchedInput.ambiguous || matchedOutput.ambiguous,
    );
  }

  Future<void> _emitWaitingSelectDevice(
    List<MidiDevice> rawDevices,
    _SelectedMidiTarget target, {
    bool ambiguous = false,
  }) async {
    final sorted = List<MidiDevice>.of(rawDevices)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final inputDevices = sorted
        .where((device) => device.inputPorts.isNotEmpty)
        .toList();
    final outputDevices = sorted
        .where((device) => device.outputPorts.isNotEmpty)
        .toList();

    bool canWorkOffline = false;
    try {
      canWorkOffline = await _cubit._metadataDao.hasCachedAlgorithms();
    } catch (_) {}

    if (_cubit.isClosed || !identical(_pendingReconnectTarget, target)) {
      return;
    }
    final matchedInput = _matchReturningEndpoint(
      sorted,
      expectedId: target.inputId,
      expectedName: target.inputName,
      input: true,
    ).device;
    final matchedOutput = _matchReturningEndpoint(
      sorted,
      expectedId: target.outputId,
      expectedName: target.outputName,
      input: false,
    ).device;
    final status = ambiguous
        ? 'MIDI connection lost. Multiple "${target.displayLabel}" devices found — select ports and connect.'
        : 'MIDI connection lost. Waiting for ${target.displayLabel} to reconnect.';

    _cubit._emitState(
      DistingState.selectDevice(
        inputDevices: inputDevices,
        outputDevices: outputDevices,
        canWorkOffline: canWorkOffline,
        selectedInputDevice: matchedInput,
        selectedOutputDevice: matchedOutput,
        selectedSysExId: target.sysExId,
        connectionStatus: status,
      ),
    );
    _ensureMidiSetupListener();
  }

  void _teardownOnlineConnection({
    required MidiDevice? inputDevice,
    required MidiDevice? outputDevice,
    required IDistingMidiManager? manager,
  }) {
    _syncGeneration++;
    _clearActiveDeviceListeners();
    _activeTarget = null;
    _activeDeviceDisconnected = false;
    _cubit._remoteDelegate.clearConnection();
    _cubit._memoryDelegate.clearConnection();
    _cubit._cancelRespecificationForConnectionChange();
    _cubit._checkpointDelegate.clearCheckpoints();
    _cubit._ccNotificationDelegate.stop();
    _cubit._monitoringDelegate.pauseCpuMonitoring();
    _cubit._parameterRefreshDelegate.dispose();
    _cubit._parameterQueue?.dispose();
    _cubit._parameterQueue = null;

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
    try {
      manager?.dispose();
    } catch (_) {}
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
    _pendingReconnectTarget = null;

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

    // Do not dispose MidiCommand here: in flutter_midi_command 1.4.x its
    // dispose() calls platform teardown(), which permanently closes RX/setup
    // streams on Linux/Windows and unregisters Android's device callback.
    _teardownOnlineConnection(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      manager: manager,
    );
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
  }) async {
    StartupLogService.log(
      'DistingCubit.performSyncAndEmit: starting Disting NT sync',
    );
    final currentState = _cubit.state;
    final generation = ++_syncGeneration;
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
        } catch (e, stackTrace) {
          debugPrintStack(stackTrace: stackTrace);
        }
        if (!_isCurrentSync(generation, currentState, distingManager)) {
          return;
        }

        _emitSyncProgress(
          'Reading firmware version...',
          progress: 0.15,
          syncGeneration: generation,
        );

        final versionResponse =
            await distingManager.requestVersionString() ?? "";
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
        final presetName =
            await distingManager.requestPresetName() ?? "Default";

        _emitSyncProgress(
          'Loading unit strings...',
          progress: 0.30,
          syncGeneration: generation,
        );
        var unitStrings = await distingManager.requestUnitStrings() ?? [];

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
        if (!_isCurrentSync(generation, currentState, distingManager)) {
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

        if (!_isCurrentSync(generation, currentState, distingManager)) {
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
    } catch (e, stackTrace) {
      if (!_invalidateSync(generation)) return false;
      StartupLogService.logError(
        'DistingCubit.performSyncAndEmit: sync failed while querying Disting NT',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      // Release the failed connection before refreshing device selection so no
      // manager or native stream subscription leaks.
      _teardownOnlineConnection(
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        manager: distingManager,
      );
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

  Future<void> connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) => _connectToDevices(inputDevice, outputDevice, sysExId);

  Future<void> _connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId, {
    _SelectedMidiTarget? reconnectTarget,
  }) async {
    if (_openingConnection || _cubit.isClosed) return;
    _openingConnection = true;
    _pendingReconnectTarget = null;

    final target = _SelectedMidiTarget(
      inputId: inputDevice.id,
      inputName:
          reconnectTarget?.inputName ??
          (_lastOnlineTarget?.inputId == inputDevice.id
              ? _lastOnlineTarget!.inputName
              : inputDevice.name),
      outputId: outputDevice.id,
      outputName:
          reconnectTarget?.outputName ??
          (_lastOnlineTarget?.outputId == outputDevice.id
              ? _lastOnlineTarget!.outputName
              : outputDevice.name),
      sysExId: sysExId,
    );

    StartupLogService.log(
      'DistingCubit.connectToDevices: attempting connection to '
      'input="${target.inputName}" (${inputDevice.id}), '
      'output="${target.outputName}" (${outputDevice.id}), sysExId=$sysExId',
    );

    final currentState = _cubit.state;
    MidiDevice? existingInputDevice;
    MidiDevice? existingOutputDevice;
    if (currentState is DistingStateConnected) {
      existingInputDevice = currentState.inputDevice;
      existingOutputDevice = currentState.outputDevice;
    } else if (currentState is DistingStateSynchronized) {
      existingInputDevice = currentState.inputDevice;
      existingOutputDevice = currentState.outputDevice;
    }
    final existingManager = _cubit.disting();

    var openedInput = false;
    var openedOutput = false;
    DistingMidiManager? newDistingManager;

    try {
      _teardownOnlineConnection(
        inputDevice: existingInputDevice,
        outputDevice: existingOutputDevice,
        manager: existingManager,
      );
      _cubit._offlineManager?.dispose();
      _cubit._offlineManager = null;

      StartupLogService.log(
        'DistingCubit.connectToDevices: opening input MIDI device "${target.inputName}"',
      );
      await _cubit._midiCommand.connectToDevice(inputDevice);
      openedInput = true;
      if (_cubit.isClosed) {
        try {
          _cubit._midiCommand.disconnectDevice(inputDevice);
        } catch (_) {}
        return;
      }

      if (inputDevice.id != outputDevice.id) {
        StartupLogService.log(
          'DistingCubit.connectToDevices: opening output MIDI device "${target.outputName}"',
        );
        await _cubit._midiCommand.connectToDevice(outputDevice);
        openedOutput = true;
        if (_cubit.isClosed) {
          try {
            _cubit._midiCommand.disconnectDevice(inputDevice);
          } catch (_) {}
          try {
            _cubit._midiCommand.disconnectDevice(outputDevice);
          } catch (_) {}
          return;
        }
      }

      final prefs = await _cubit._prefs;
      if (_cubit.isClosed) {
        try {
          _cubit._midiCommand.disconnectDevice(inputDevice);
        } catch (_) {}
        if (openedOutput) {
          try {
            _cubit._midiCommand.disconnectDevice(outputDevice);
          } catch (_) {}
        }
        return;
      }
      await prefs.setString('selectedInputMidiDevice', target.inputName);
      await prefs.setString('selectedOutputMidiDevice', target.outputName);
      await prefs.setInt('selectedSysExId', sysExId);

      newDistingManager = DistingMidiManager(
        midiCommand: _cubit._midiCommand,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
      );

      _activeTarget = target;
      _lastOnlineTarget = target;
      _cubit._lastOnlineInputDevice = inputDevice;
      _cubit._lastOnlineOutputDevice = outputDevice;
      _cubit._lastOnlineSysExId = sysExId;

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

      _cubit._createParameterQueue();
      _watchActiveDevices(inputDevice, outputDevice, newDistingManager);
      _ensureMidiSetupListener();
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.connectToDevices: connection failed',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      _openingConnection = false;
      _setupCheckPending = false;
      _clearActiveDeviceListeners();
      _activeTarget = null;
      _activeDeviceDisconnected = false;
      try {
        newDistingManager?.dispose();
      } catch (_) {}
      if (openedInput) {
        try {
          _cubit._midiCommand.disconnectDevice(inputDevice);
        } catch (_) {}
      }
      if (openedOutput) {
        try {
          _cubit._midiCommand.disconnectDevice(outputDevice);
        } catch (_) {}
      }
      if (_cubit.isClosed) return;

      if (reconnectTarget != null) {
        _pendingReconnectTarget = reconnectTarget;
        List<MidiDevice> rawDevices = const [];
        try {
          rawDevices = await _cubit._midiCommand.devices ?? const [];
        } catch (_) {}
        await _emitWaitingSelectDevice(rawDevices, reconnectTarget);
      } else {
        _cubit._lastOnlineInputDevice = null;
        _cubit._lastOnlineOutputDevice = null;
        _cubit._lastOnlineSysExId = null;
        _lastOnlineTarget = null;
        await loadDevices();
      }
      return;
    } finally {
      _openingConnection = false;
    }

    if (_setupCheckPending && !_cubit.isClosed) {
      _triggerSetupCheck();
    }

    if (_cubit.isClosed || !identical(_cubit.disting(), newDistingManager)) {
      return;
    }

    // Synchronize device clock with local time
    // The device has no timezone info — it stamps FAT files directly from
    // the value we send, so we must send local time, not UTC.
    try {
      final now = DateTime.now();
      final localAsUtc = DateTime.utc(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        now.second,
      );
      final localEpoch = localAsUtc.millisecondsSinceEpoch ~/ 1000;
      await newDistingManager.requestSetRealTimeClock(localEpoch);
      StartupLogService.log(
        'DistingCubit.connectToDevices: device clock synchronized',
      );
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.connectToDevices: device clock sync failed; continuing',
        e,
        stackTrace,
      );
      // Continue with connection even if clock sync fails
    }

    if (_cubit.isClosed || !identical(_cubit.disting(), newDistingManager)) {
      return;
    }

    final syncSucceeded = await performSyncAndEmit();
    if (syncSucceeded &&
        !_cubit.isClosed &&
        identical(_cubit.disting(), newDistingManager)) {
      _cubit._monitoringDelegate.resumeCpuMonitoring();
    }
    StartupLogService.log(
      'DistingCubit.connectToDevices: connection flow completed; '
      'syncSucceeded=$syncSucceeded',
    );
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
