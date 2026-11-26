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
    this.autoReconnect = true,
  });

  final String inputId;
  final String inputName;
  final String outputId;
  final String outputName;
  final int sysExId;
  final bool autoReconnect;

  _SelectedMidiTarget copyWith({bool? autoReconnect}) => _SelectedMidiTarget(
    inputId: inputId,
    inputName: inputName,
    outputId: outputId,
    outputName: outputName,
    sysExId: sysExId,
    autoReconnect: autoReconnect ?? this.autoReconnect,
  );

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
  int _connectionSessionToken = 0;
  int? _activeOpenToken;
  String? _openingInputId;
  String? _openingOutputId;
  int _disconnectingCount = 0;
  bool _firmwareProbeBusy = false;
  bool _setupCheckInFlight = false;
  bool _setupCheckPending = false;
  bool _activeDeviceDisconnected = false;
  MidiCommand? _subscribedMidiCommand;
  _SelectedMidiTarget? _activeTarget;
  _SelectedMidiTarget? _lastOnlineTarget;
  _SelectedMidiTarget? _pendingReconnectTarget;
  StreamSubscription<MidiConnectionState>? _inputDeviceStateSub;
  StreamSubscription<MidiConnectionState>? _outputDeviceStateSub;

  bool get _openingConnection =>
      _activeOpenToken != null && _activeOpenToken == _connectionSessionToken;

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
    _connectionSessionToken++;
    _syncGeneration++;
    _clearActiveDeviceListeners();
    _activeTarget = null;
    _pendingReconnectTarget = null;
    _activeDeviceDisconnected = false;
    _setupCheckPending = false;
  }

  void _disconnectMidiDevice(MidiDevice device) {
    _disconnectingCount++;
    try {
      _cubit._midiCommand.disconnectDevice(device);
    } catch (_) {
    } finally {
      _disconnectingCount--;
    }
  }

  bool _isDeviceOwnedByAnotherSession(
    String deviceId, {
    required int excludingOpenToken,
  }) {
    if (_activeOpenToken != null &&
        _activeOpenToken != excludingOpenToken &&
        (_openingInputId == deviceId || _openingOutputId == deviceId)) {
      return true;
    }
    final activeTarget = _activeTarget;
    if (activeTarget != null &&
        (activeTarget.inputId == deviceId ||
            activeTarget.outputId == deviceId)) {
      return true;
    }
    final state = _cubit.state;
    if (state is DistingStateConnected && !state.offline) {
      if (state.inputDevice?.id == deviceId ||
          state.outputDevice?.id == deviceId) {
        return true;
      }
    } else if (state is DistingStateSynchronized &&
        !state.offline &&
        !state.demo) {
      if (state.inputDevice?.id == deviceId ||
          state.outputDevice?.id == deviceId) {
        return true;
      }
    }
    return false;
  }

  void _cleanupDiscardedOpen({
    required int openToken,
    required MidiDevice inputDevice,
    required MidiDevice outputDevice,
    required bool openedInput,
    required bool openedOutput,
    required DistingMidiManager? manager,
  }) {
    try {
      manager?.dispose();
    } catch (_) {}
    if (openedInput &&
        !_isDeviceOwnedByAnotherSession(
          inputDevice.id,
          excludingOpenToken: openToken,
        )) {
      _disconnectMidiDevice(inputDevice);
    }
    if (openedOutput &&
        outputDevice.id != inputDevice.id &&
        !_isDeviceOwnedByAnotherSession(
          outputDevice.id,
          excludingOpenToken: openToken,
        )) {
      _disconnectMidiDevice(outputDevice);
    }
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
    _connectionSessionToken++;
    _pendingReconnectTarget = null;
    _setupCheckPending = false;
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

  Future<void> loadDevices({int? sessionToken}) async {
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

      if (_cubit.isClosed ||
          (sessionToken != null && _connectionSessionToken != sessionToken)) {
        return;
      }

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
      if (_cubit.isClosed ||
          (sessionToken != null && _connectionSessionToken != sessionToken)) {
        return;
      }
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
    _cubit._midiSetupSubscription = command.onMidiSetupChanged?.listen((
      change,
    ) {
      if (_disconnectingCount > 0 &&
          change == MidiSetupChange.deviceDisconnected) {
        return;
      }
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

    final sessionToken = _connectionSessionToken;
    final List<MidiDevice> rawDevices;
    try {
      rawDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {
      return;
    }
    if (_cubit.isClosed ||
        _openingConnection ||
        _connectionSessionToken != sessionToken ||
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

    // If either selected endpoint is still present in the snapshot, teardown
    // invokes void disconnectDevice on a live endpoint whose native closure is
    // asynchronous and unobservable in flutter_midi_command 1.4.x (e.g. Linux
    // LinuxMidiDevice.disconnect awaits rx cancellation before ALSA close).
    // Never immediately auto-reopen or reuse the pre-teardown snapshot object.
    final hadSurvivingEndpoint = hasInput || hasOutput;

    _teardownOnlineConnection(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      manager: manager,
    );
    final teardownToken = ++_connectionSessionToken;
    _setupCheckPending = false;

    List<MidiDevice> postTeardownDevices = const [];
    try {
      postTeardownDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {}
    if (_cubit.isClosed ||
        _openingConnection ||
        _connectionSessionToken != teardownToken) {
      return;
    }

    final matchedInput = _matchReturningEndpoint(
      postTeardownDevices,
      expectedId: target.inputId,
      expectedName: target.inputName,
      input: true,
    );
    final matchedOutput = _matchReturningEndpoint(
      postTeardownDevices,
      expectedId: target.outputId,
      expectedName: target.outputName,
      input: false,
    );
    if (hadSurvivingEndpoint) {
      if (matchedInput.device != null && matchedOutput.device != null) {
        _pendingReconnectTarget = null;
        await _emitReconnectSelectDevice(
          postTeardownDevices,
          target,
          status:
              'MIDI connection lost. Select Connect to reconnect to ${target.displayLabel}.',
          sessionToken: teardownToken,
        );
        return;
      }
      final manualTarget = target.copyWith(autoReconnect: false);
      _pendingReconnectTarget = manualTarget;
      await _emitReconnectSelectDevice(
        postTeardownDevices,
        manualTarget,
        expectedPendingTarget: manualTarget,
        ambiguous: matchedInput.ambiguous || matchedOutput.ambiguous,
        sessionToken: teardownToken,
      );
      return;
    }

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
    await _emitReconnectSelectDevice(
      postTeardownDevices,
      target,
      expectedPendingTarget: target,
      ambiguous: matchedInput.ambiguous || matchedOutput.ambiguous,
      sessionToken: teardownToken,
    );
  }

  Future<void> _checkPendingReconnect(_SelectedMidiTarget target) async {
    if (_cubit.isClosed || _openingConnection) return;
    final checkToken = _connectionSessionToken;
    final List<MidiDevice> rawDevices;
    try {
      rawDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {
      _ensureMidiSetupListener();
      return;
    }
    if (_cubit.isClosed ||
        _openingConnection ||
        _connectionSessionToken != checkToken ||
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
      if (target.autoReconnect) {
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
      _pendingReconnectTarget = null;
      await _emitReconnectSelectDevice(
        rawDevices,
        target,
        status:
            '${target.displayLabel} is available. Select Connect to reconnect.',
        sessionToken: checkToken,
      );
      return;
    }

    await _emitReconnectSelectDevice(
      rawDevices,
      target,
      expectedPendingTarget: target,
      ambiguous: matchedInput.ambiguous || matchedOutput.ambiguous,
      sessionToken: checkToken,
    );
  }

  Future<void> _emitReconnectSelectDevice(
    List<MidiDevice> rawDevices,
    _SelectedMidiTarget target, {
    _SelectedMidiTarget? expectedPendingTarget,
    bool ambiguous = false,
    String? status,
    required int sessionToken,
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

    if (_cubit.isClosed || _connectionSessionToken != sessionToken) {
      return;
    }
    if (expectedPendingTarget != null &&
        !identical(_pendingReconnectTarget, expectedPendingTarget)) {
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
    final resolvedStatus =
        status ??
        (ambiguous
            ? 'MIDI connection lost. Multiple "${target.displayLabel}" devices found — select ports and connect.'
            : 'MIDI connection lost. Waiting for ${target.displayLabel} to reconnect.');

    _cubit._emitState(
      DistingState.selectDevice(
        inputDevices: inputDevices,
        outputDevices: outputDevices,
        canWorkOffline: canWorkOffline,
        selectedInputDevice: matchedInput,
        selectedOutputDevice: matchedOutput,
        selectedSysExId: target.sysExId,
        connectionStatus: resolvedStatus,
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
      _disconnectMidiDevice(inputDevice);
    }
    if (outputDevice != null && outputDevice.id != inputDevice?.id) {
      _disconnectMidiDevice(outputDevice);
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
    _connectionSessionToken++;
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
    final openToken = ++_connectionSessionToken;
    _activeOpenToken = openToken;
    _openingInputId = inputDevice.id;
    _openingOutputId = outputDevice.id;
    _pendingReconnectTarget = null;

    bool isCurrentSession() =>
        !_cubit.isClosed && _connectionSessionToken == openToken;
    bool isCurrentOpen() => isCurrentSession() && _activeOpenToken == openToken;

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
      if (!isCurrentOpen()) {
        _cleanupDiscardedOpen(
          openToken: openToken,
          inputDevice: inputDevice,
          outputDevice: outputDevice,
          openedInput: openedInput,
          openedOutput: openedOutput,
          manager: newDistingManager,
        );
        return;
      }

      if (inputDevice.id != outputDevice.id) {
        StartupLogService.log(
          'DistingCubit.connectToDevices: opening output MIDI device "${target.outputName}"',
        );
        await _cubit._midiCommand.connectToDevice(outputDevice);
        openedOutput = true;
        if (!isCurrentOpen()) {
          _cleanupDiscardedOpen(
            openToken: openToken,
            inputDevice: inputDevice,
            outputDevice: outputDevice,
            openedInput: openedInput,
            openedOutput: openedOutput,
            manager: newDistingManager,
          );
          return;
        }
      }

      final prefs = await _cubit._prefs;
      if (!isCurrentOpen()) {
        _cleanupDiscardedOpen(
          openToken: openToken,
          inputDevice: inputDevice,
          outputDevice: outputDevice,
          openedInput: openedInput,
          openedOutput: openedOutput,
          manager: newDistingManager,
        );
        return;
      }
      await prefs.setString('selectedInputMidiDevice', target.inputName);
      await prefs.setString('selectedOutputMidiDevice', target.outputName);
      await prefs.setInt('selectedSysExId', sysExId);
      if (!isCurrentOpen()) {
        _cleanupDiscardedOpen(
          openToken: openToken,
          inputDevice: inputDevice,
          outputDevice: outputDevice,
          openedInput: openedInput,
          openedOutput: openedOutput,
          manager: newDistingManager,
        );
        return;
      }

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
      final stillCurrent = isCurrentOpen();
      StartupLogService.logError(
        'DistingCubit.connectToDevices: connection failed',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      _cleanupDiscardedOpen(
        openToken: openToken,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        openedInput: openedInput,
        openedOutput: openedOutput,
        manager: newDistingManager,
      );
      if (!stillCurrent) return;

      _clearActiveDeviceListeners();
      _activeTarget = null;
      _activeDeviceDisconnected = false;
      _setupCheckPending = false;

      if (reconnectTarget != null) {
        _pendingReconnectTarget = reconnectTarget;
        List<MidiDevice> rawDevices = const [];
        try {
          rawDevices = await _cubit._midiCommand.devices ?? const [];
        } catch (_) {}
        if (!isCurrentOpen()) return;
        await _emitReconnectSelectDevice(
          rawDevices,
          reconnectTarget,
          expectedPendingTarget: reconnectTarget,
          sessionToken: openToken,
        );
      } else {
        _cubit._lastOnlineInputDevice = null;
        _cubit._lastOnlineOutputDevice = null;
        _cubit._lastOnlineSysExId = null;
        _lastOnlineTarget = null;
        await loadDevices(sessionToken: openToken);
      }
      return;
    } finally {
      if (_activeOpenToken == openToken) {
        _activeOpenToken = null;
        _openingInputId = null;
        _openingOutputId = null;
        if (_setupCheckPending &&
            isCurrentSession() &&
            _cubit._midiSetupSubscription != null) {
          _triggerSetupCheck();
        }
      }
    }

    if (!isCurrentSession() ||
        !identical(_cubit.disting(), newDistingManager)) {
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

    if (!isCurrentSession() ||
        !identical(_cubit.disting(), newDistingManager)) {
      return;
    }

    final syncSucceeded = await performSyncAndEmit();
    if (syncSucceeded &&
        isCurrentSession() &&
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
