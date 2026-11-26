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

const _kPrefSelectedInputName = 'selectedInputMidiDevice';
const _kPrefSelectedInputId = 'selectedInputMidiDeviceId';
const _kPrefSelectedOutputName = 'selectedOutputMidiDevice';
const _kPrefSelectedOutputId = 'selectedOutputMidiDeviceId';
const _kPrefSelectedSysExId = 'selectedSysExId';

class _DesiredMidiEndpoint {
  const _DesiredMidiEndpoint({this.id, this.name});

  final String? id;
  final String? name;

  bool get isEmpty =>
      (id == null || id!.isEmpty) && (name == null || name!.trim().isEmpty);
}

class _DesiredDeviceSelection {
  const _DesiredDeviceSelection({this.input, this.output, this.sysExId = 0});

  final _DesiredMidiEndpoint? input;
  final _DesiredMidiEndpoint? output;
  final int sysExId;
}

class _DeviceListSnapshot {
  const _DeviceListSnapshot({
    required this.allDevices,
    required this.inputDevices,
    required this.outputDevices,
  });

  final List<MidiDevice> allDevices;
  final List<MidiDevice> inputDevices;
  final List<MidiDevice> outputDevices;
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
}

class _ConnectionDelegate {
  _ConnectionDelegate(this._cubit);

  final DistingCubit _cubit;
  int _syncGeneration = 0;
  int _connectionSessionToken = 0;
  int _deviceListGeneration = 0;
  int _selectionRevision = 0;
  _DesiredDeviceSelection? _desiredSelection;
  Future<void> _persistChain = Future<void>.value();
  int? _activeOpenToken;
  String? _openingInputId;
  String? _openingOutputId;
  bool _firmwareProbeBusy = false;
  bool _setupCheckInFlight = false;
  bool _setupCheckPending = false;
  bool _pendingSetupCheckCanRetrySamePair = false;
  (String, String)? _failedPairToSkipNextCheck;
  bool _activeDeviceDisconnected = false;
  MidiCommand? _subscribedMidiCommand;
  _SelectedMidiTarget? _activeTarget;
  _SelectedMidiTarget? _lastOnlineTarget;
  _SelectedMidiTarget? _pendingReconnectTarget;
  StreamSubscription<MidiConnectionState>? _inputDeviceStateSub;
  StreamSubscription<MidiConnectionState>? _outputDeviceStateSub;

  bool get _openingConnection =>
      _activeOpenToken != null && _activeOpenToken == _connectionSessionToken;

  bool get hasPendingReconnect => _pendingReconnectTarget != null;

  bool get isTransportDisconnected {
    final state = _cubit.state;
    if (state is DistingStateSynchronized && !state.offline && !state.demo) {
      return _pendingReconnectTarget != null ||
          (_openingConnection && _activeTarget == null);
    }
    return _pendingReconnectTarget != null;
  }

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
    _pendingSetupCheckCanRetrySamePair = false;
    _failedPairToSkipNextCheck = null;
  }

  void _disconnectMidiDevice(MidiDevice device) {
    try {
      _cubit._midiCommand.disconnectDevice(device);
    } catch (_) {}
  }

  bool _isDeviceOwnedByAnotherSession(
    String deviceId, {
    required int excludingOpenToken,
  }) {
    if (_cubit.isClosed) return false;
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

  int _normalizeSysExId(int? value) =>
      value != null && value >= 0 && value <= 127 ? value : 0;

  _DesiredMidiEndpoint? _desiredEndpointFrom({String? id, String? name}) {
    final hasId = id != null && id.trim().isNotEmpty;
    final hasName = name != null && name.trim().isNotEmpty;
    if (!hasId && !hasName) return null;
    return _DesiredMidiEndpoint(
      id: hasId ? id : null,
      name: hasName ? name : null,
    );
  }

  Future<_DesiredDeviceSelection> _readDesiredSelectionFromPrefs() async {
    final prefs = await _cubit._prefs;
    return _DesiredDeviceSelection(
      input: _desiredEndpointFrom(
        id: prefs.getString(_kPrefSelectedInputId),
        name: prefs.getString(_kPrefSelectedInputName),
      ),
      output: _desiredEndpointFrom(
        id: prefs.getString(_kPrefSelectedOutputId),
        name: prefs.getString(_kPrefSelectedOutputName),
      ),
      sysExId: _normalizeSysExId(prefs.getInt(_kPrefSelectedSysExId)),
    );
  }

  Future<void> _writeDesiredSelectionToPrefs(
    _DesiredDeviceSelection selection, {
    int? expectedRevision,
  }) async {
    final prefs = await _cubit._prefs;
    if (expectedRevision != null && _selectionRevision != expectedRevision) {
      return;
    }

    Future<void> writeStringOrRemove(String key, String? value) async {
      if (value == null || value.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    }

    await writeStringOrRemove(_kPrefSelectedInputName, selection.input?.name);
    if (expectedRevision != null && _selectionRevision != expectedRevision) {
      return;
    }
    await writeStringOrRemove(_kPrefSelectedInputId, selection.input?.id);
    if (expectedRevision != null && _selectionRevision != expectedRevision) {
      return;
    }
    await writeStringOrRemove(_kPrefSelectedOutputName, selection.output?.name);
    if (expectedRevision != null && _selectionRevision != expectedRevision) {
      return;
    }
    await writeStringOrRemove(_kPrefSelectedOutputId, selection.output?.id);
    if (expectedRevision != null && _selectionRevision != expectedRevision) {
      return;
    }
    await prefs.setInt(
      _kPrefSelectedSysExId,
      _normalizeSysExId(selection.sysExId),
    );
  }

  Future<void> _schedulePersistDesiredSelection(
    _DesiredDeviceSelection selection,
    int revision,
  ) {
    final writeFuture = _persistChain
        .then((_) async {
          if (_selectionRevision != revision) return;
          await _writeDesiredSelectionToPrefs(
            selection,
            expectedRevision: revision,
          );
        })
        .catchError((Object _) {});
    _persistChain = writeFuture;
    return writeFuture;
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

    if (expectedId.isNotEmpty) {
      final idMatches = directional
          .where((device) => device.id == expectedId)
          .toList();
      if (idMatches.length == 1) {
        return (device: idMatches.single, ambiguous: false);
      }
      if (idMatches.length > 1) {
        return (device: null, ambiguous: true);
      }
      if (devices.any((device) => device.id == expectedId)) {
        return (device: null, ambiguous: false);
      }
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

  MidiDevice? _resolveDesiredEndpoint(
    List<MidiDevice> allDevices,
    List<MidiDevice> directionalDevices,
    _DesiredMidiEndpoint? desired, {
    required bool input,
  }) {
    if (desired != null && !desired.isEmpty) {
      return _matchReturningEndpoint(
        allDevices,
        expectedId: desired.id ?? '',
        expectedName: desired.name ?? '',
        input: input,
      ).device;
    }
    // Without a saved preference for this direction, suggest only a sole
    // unambiguous endpoint. Selection does not open MIDI or start sync.
    return directionalDevices.length == 1 ? directionalDevices.single : null;
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
    _pendingSetupCheckCanRetrySamePair = false;
    _failedPairToSkipNextCheck = null;

    final normalizedSysExId = _normalizeSysExId(sysExId);
    final previousDesired =
        _desiredSelection ?? const _DesiredDeviceSelection();
    final nextDesiredInput = inputDevice != null
        ? _desiredEndpointFrom(id: inputDevice.id, name: inputDevice.name)
        : (currentState.selectedInputDevice != null
              ? null
              : previousDesired.input);
    final nextDesiredOutput = outputDevice != null
        ? _desiredEndpointFrom(id: outputDevice.id, name: outputDevice.name)
        : (currentState.selectedOutputDevice != null
              ? null
              : previousDesired.output);
    final nextDesired = _DesiredDeviceSelection(
      input: nextDesiredInput,
      output: nextDesiredOutput,
      sysExId: normalizedSysExId,
    );
    _desiredSelection = nextDesired;
    final revision = ++_selectionRevision;
    _schedulePersistDesiredSelection(nextDesired, revision);

    _cubit._emitState(
      currentState.copyWith(
        selectedInputDevice: inputDevice,
        selectedOutputDevice: outputDevice,
        selectedSysExId: normalizedSysExId,
      ),
    );
  }

  Future<void> initialize() async {
    StartupLogService.log(
      'DistingCubit.initialize: starting MIDI discovery. '
      'The app can start without a Disting NT connected; missing hardware '
      'should leave the app on device selection or offline mode.',
    );

    final listGeneration = ++_deviceListGeneration;
    final startRevision = _selectionRevision;

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

    final snapshot = await _fetchDeviceLists();
    final prefsSelection = await _readDesiredSelectionFromPrefs();
    if (_cubit.isClosed || listGeneration != _deviceListGeneration) {
      return;
    }
    if (_selectionRevision == startRevision) {
      _desiredSelection = prefsSelection;
    }
    final currentState = _cubit.state;
    if (currentState is! DistingStateInitial &&
        currentState is! DistingStateSelectDevice) {
      return;
    }

    final desired = _desiredSelection ?? prefsSelection;
    final selectedInputDevice = _resolveDesiredEndpoint(
      snapshot.allDevices,
      snapshot.inputDevices,
      desired.input,
      input: true,
    );
    final selectedOutputDevice = _resolveDesiredEndpoint(
      snapshot.allDevices,
      snapshot.outputDevices,
      desired.output,
      input: false,
    );
    final savedPairAvailable =
        selectedInputDevice != null && selectedOutputDevice != null;
    _cubit._emitState(
      DistingState.selectDevice(
        inputDevices: snapshot.inputDevices,
        outputDevices: snapshot.outputDevices,
        canWorkOffline: canWorkOffline,
        selectedInputDevice: selectedInputDevice,
        selectedOutputDevice: selectedOutputDevice,
        selectedSysExId: desired.sysExId,
      ),
    );
    StartupLogService.log(
      'DistingCubit.initialize: showing device selection; '
      'manual MIDI connection required; '
      'saved pair available=$savedPairAvailable',
    );
    startMidiSetupListener();
  }

  Future<void> switchToDeviceSelection() async {
    _cubit._offlineManager?.dispose();
    _cubit._offlineManager = null;
    disconnect();
    await loadDevices();
  }

  Future<void> loadDevices({int? sessionToken}) async {
    StartupLogService.log(
      'DistingCubit.loadDevices: refreshing MIDI device list',
    );
    final previousState = _cubit.state;
    final listGeneration = ++_deviceListGeneration;
    final startRevision = _selectionRevision;
    try {
      if (previousState is! DistingStateSelectDevice) {
        _cubit._emitState(const DistingState.initial());
      }

      // Fetch devices using the helper
      final snapshot = await _fetchDeviceLists();

      // Re-check offline capability here for manual refresh accuracy
      final bool canWorkOffline = await _cubit._metadataDao
          .hasCachedAlgorithms();

      if (_desiredSelection == null) {
        final prefsSelection = await _readDesiredSelectionFromPrefs();
        if (_selectionRevision == startRevision && _desiredSelection == null) {
          _desiredSelection = prefsSelection;
        }
      }

      if (_cubit.isClosed ||
          listGeneration != _deviceListGeneration ||
          (sessionToken != null && _connectionSessionToken != sessionToken)) {
        return;
      }

      final currentState = _cubit.state;
      if (previousState is DistingStateSelectDevice &&
          currentState is! DistingStateSelectDevice) {
        return;
      }
      if (previousState is! DistingStateSelectDevice &&
          currentState is! DistingStateInitial) {
        return;
      }
      final desired = _desiredSelection ?? const _DesiredDeviceSelection();
      final selectedInputDevice = _resolveDesiredEndpoint(
        snapshot.allDevices,
        snapshot.inputDevices,
        desired.input,
        input: true,
      );
      final selectedOutputDevice = _resolveDesiredEndpoint(
        snapshot.allDevices,
        snapshot.outputDevices,
        desired.output,
        input: false,
      );

      // Transition to the select device state, preserving desired choices
      // across explicit and MIDI-triggered refreshes even while absent.
      _cubit._emitState(
        DistingState.selectDevice(
          inputDevices: snapshot.inputDevices,
          outputDevices: snapshot.outputDevices,
          canWorkOffline: canWorkOffline,
          selectedInputDevice: selectedInputDevice,
          selectedOutputDevice: selectedOutputDevice,
          selectedSysExId: desired.sysExId,
        ),
      );
      StartupLogService.log(
        'DistingCubit.loadDevices: device selection updated; '
        'inputs=${snapshot.inputDevices.length}, '
        'outputs=${snapshot.outputDevices.length}, '
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
          listGeneration != _deviceListGeneration ||
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
        DistingState.selectDevice(
          inputDevices: const [],
          outputDevices: const [],
          canWorkOffline: false,
          selectedSysExId: _desiredSelection?.sysExId ?? 0,
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
      if (change == MidiSetupChange.deviceConnected) {
        return;
      }
      if (change == MidiSetupChange.deviceDisconnected &&
          _activeTarget == null) {
        return;
      }
      StartupLogService.log('DistingCubit: MIDI setup changed');
      _triggerSetupCheck(
        canRetrySamePair: change != MidiSetupChange.deviceAppeared,
      );
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

  void _triggerSetupCheck({bool canRetrySamePair = false}) {
    if (_cubit.isClosed) return;
    if (_setupCheckInFlight || _openingConnection) {
      _setupCheckPending = true;
      if (canRetrySamePair) {
        _pendingSetupCheckCanRetrySamePair = true;
      }
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

  bool _isSilentReconnectEligibleState(DistingState state) =>
      (state is DistingStateSynchronized && !state.offline && !state.demo) ||
      (state is DistingStateConnected && !state.offline);

  Future<void> _handleMidiSetupChange() async {
    if (_cubit.isClosed || _openingConnection) return;
    final state = _cubit.state;

    final pendingTarget = _pendingReconnectTarget;
    if (pendingTarget != null) {
      if (_isSilentReconnectEligibleState(state)) {
        await _checkPendingReconnect(pendingTarget);
        return;
      }
      _pendingReconnectTarget = null;
    }

    if (state is DistingStateInitial || state is DistingStateSelectDevice) {
      await loadDevices();
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

    // On Linux (flutter_midi_command_linux 1.4.0), disconnectDevice returns
    // void and invokes unawaited(linuxDevice.disconnect()) before ALSA route
    // teardown finishes. Never immediately auto-reopen a surviving Linux
    // endpoint against that unobservable close, and never reuse pre-teardown
    // snapshot objects.
    final hadSurvivingEndpoint = hasInput || hasOutput;

    _pendingReconnectTarget = target;
    _teardownOnlineConnection(
      inputDevice: inputDevice,
      outputDevice: outputDevice,
      manager: manager,
      preserveCheckpoints: state is DistingStateSynchronized,
    );
    final teardownToken = ++_connectionSessionToken;
    _setupCheckPending = false;

    List<MidiDevice> postTeardownDevices = const [];
    try {
      postTeardownDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {}
    if (_cubit.isClosed ||
        _openingConnection ||
        _connectionSessionToken != teardownToken ||
        !_isSilentReconnectEligibleState(_cubit.state)) {
      if (identical(_pendingReconnectTarget, target) &&
          !_isSilentReconnectEligibleState(_cubit.state)) {
        _pendingReconnectTarget = null;
      }
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

    if (_cubit._isLinux && hadSurvivingEndpoint) {
      final survivingStillPresent = postTeardownDevices.any(
        (device) => device.id == target.inputId || device.id == target.outputId,
      );
      _pendingReconnectTarget = target.copyWith(
        autoReconnect: !survivingStillPresent,
      );
      _ensureMidiSetupListener();
      return;
    }

    if (matchedInput.device != null && matchedOutput.device != null) {
      unawaited(
        _silentReconnectToDevices(
          matchedInput.device!,
          matchedOutput.device!,
          target,
        ),
      );
      return;
    }

    _pendingReconnectTarget = target;
    _ensureMidiSetupListener();
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
    if (!_isSilentReconnectEligibleState(_cubit.state)) {
      _failedPairToSkipNextCheck = null;
      return;
    }

    final skipPair = _failedPairToSkipNextCheck;
    _failedPairToSkipNextCheck = null;

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

    if (!target.autoReconnect) {
      final survivingStillPresent = rawDevices.any(
        (device) => device.id == target.inputId || device.id == target.outputId,
      );
      if (!survivingStillPresent &&
          matchedInput.device == null &&
          matchedOutput.device == null) {
        _pendingReconnectTarget = target.copyWith(autoReconnect: true);
      }
      _ensureMidiSetupListener();
      return;
    }

    if (matchedInput.device != null && matchedOutput.device != null) {
      if (skipPair != null &&
          matchedInput.device!.id == skipPair.$1 &&
          matchedOutput.device!.id == skipPair.$2) {
        _ensureMidiSetupListener();
        return;
      }
      unawaited(
        _silentReconnectToDevices(
          matchedInput.device!,
          matchedOutput.device!,
          target,
        ),
      );
      return;
    }

    _ensureMidiSetupListener();
  }

  Future<bool> tryReconnectPendingForUserRefresh() async {
    final target = _pendingReconnectTarget;
    if (target == null || _cubit.isClosed || _openingConnection) {
      return !isTransportDisconnected;
    }
    final checkToken = _connectionSessionToken;
    final List<MidiDevice> rawDevices;
    try {
      rawDevices = await _cubit._midiCommand.devices ?? <MidiDevice>[];
    } catch (_) {
      return false;
    }
    if (_cubit.isClosed ||
        _openingConnection ||
        _connectionSessionToken != checkToken ||
        !identical(_pendingReconnectTarget, target) ||
        !_isSilentReconnectEligibleState(_cubit.state)) {
      return false;
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
    if (matchedInput.device == null || matchedOutput.device == null) {
      return false;
    }
    await _silentReconnectToDevices(
      matchedInput.device!,
      matchedOutput.device!,
      target,
    );
    return !isTransportDisconnected;
  }

  void _teardownOnlineConnection({
    required MidiDevice? inputDevice,
    required MidiDevice? outputDevice,
    required IDistingMidiManager? manager,
    bool preserveCheckpoints = false,
  }) {
    _syncGeneration++;
    _clearActiveDeviceListeners();
    _activeTarget = null;
    _activeDeviceDisconnected = false;
    _cubit._remoteDelegate.clearConnection();
    _cubit._moduleSettingsDelegate.clearConnection();
    _cubit._memoryDelegate.clearConnection();
    _cubit._mappingDelegate.discardPendingForConnectionLoss();
    _cubit._cancelRespecificationForConnectionChange();
    if (!preserveCheckpoints) {
      _cubit._checkpointDelegate.clearCheckpoints();
    }
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

  Future<void> _silentReconnectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    _SelectedMidiTarget reconnectTarget,
  ) async {
    if (_openingConnection || _cubit.isClosed) return;
    final openToken = ++_connectionSessionToken;
    final startRevision = _selectionRevision;
    _activeOpenToken = openToken;
    _openingInputId = inputDevice.id;
    _openingOutputId = outputDevice.id;
    _pendingReconnectTarget = null;
    _setupCheckPending = false;
    _pendingSetupCheckCanRetrySamePair = false;
    _failedPairToSkipNextCheck = null;

    bool isCurrentSession() =>
        !_cubit.isClosed && _connectionSessionToken == openToken;
    bool isCurrentOpen() => isCurrentSession() && _activeOpenToken == openToken;

    final target = _SelectedMidiTarget(
      inputId: inputDevice.id,
      inputName: reconnectTarget.inputName,
      outputId: outputDevice.id,
      outputName: reconnectTarget.outputName,
      sysExId: reconnectTarget.sysExId,
    );

    var openedInput = false;
    var openedOutput = false;
    var openFailed = false;
    var needsInitialSync = false;
    DistingMidiManager? newDistingManager;

    try {
      await _cubit._midiCommand.connectToDevice(inputDevice);
      openedInput = true;
      if (!isCurrentOpen() || !_isSilentReconnectEligibleState(_cubit.state)) {
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
        await _cubit._midiCommand.connectToDevice(outputDevice);
        openedOutput = true;
        if (!isCurrentOpen() ||
            !_isSilentReconnectEligibleState(_cubit.state)) {
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

      final currentState = _cubit.state;
      newDistingManager = DistingMidiManager(
        midiCommand: _cubit._midiCommand,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: target.sysExId,
      );

      _activeTarget = target;
      _lastOnlineTarget = target;
      _cubit._lastOnlineInputDevice = inputDevice;
      _cubit._lastOnlineOutputDevice = outputDevice;
      _cubit._lastOnlineSysExId = target.sysExId;

      if (currentState is DistingStateSynchronized &&
          !currentState.offline &&
          !currentState.demo) {
        if (_selectionRevision == startRevision) {
          final nextDesired = _DesiredDeviceSelection(
            input: _desiredEndpointFrom(
              id: target.inputId,
              name: target.inputName,
            ),
            output: _desiredEndpointFrom(
              id: target.outputId,
              name: target.outputName,
            ),
            sysExId: target.sysExId,
          );
          _desiredSelection = nextDesired;
          final revision = ++_selectionRevision;
          _schedulePersistDesiredSelection(nextDesired, revision);
        }
        _cubit._emitState(
          currentState.copyWith(
            disting: newDistingManager,
            inputDevice: inputDevice,
            outputDevice: outputDevice,
          ),
        );
        _cubit._createParameterQueue();
        _watchActiveDevices(inputDevice, outputDevice, newDistingManager);
        _ensureMidiSetupListener();
        _cubit._ccNotificationDelegate.start();
        _cubit._monitoringDelegate.resumeCpuMonitoring();
      } else if (currentState is DistingStateConnected &&
          !currentState.offline) {
        if (_selectionRevision == startRevision) {
          final nextDesired = _DesiredDeviceSelection(
            input: _desiredEndpointFrom(
              id: target.inputId,
              name: target.inputName,
            ),
            output: _desiredEndpointFrom(
              id: target.outputId,
              name: target.outputName,
            ),
            sysExId: target.sysExId,
          );
          _desiredSelection = nextDesired;
          final revision = ++_selectionRevision;
          _schedulePersistDesiredSelection(nextDesired, revision);
        }
        needsInitialSync = true;
        _cubit._emitState(
          DistingState.connected(
            disting: newDistingManager,
            inputDevice: inputDevice,
            outputDevice: outputDevice,
            offline: false,
          ),
        );
        _cubit._createParameterQueue();
        _watchActiveDevices(inputDevice, outputDevice, newDistingManager);
        _ensureMidiSetupListener();
      } else {
        _activeTarget = null;
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
    } catch (_) {
      final stillCurrent = isCurrentOpen();
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
      if (_isSilentReconnectEligibleState(_cubit.state)) {
        openFailed = true;
        _pendingReconnectTarget = reconnectTarget;
        _ensureMidiSetupListener();
      }
      return;
    } finally {
      if (_activeOpenToken == openToken) {
        _activeOpenToken = null;
        _openingInputId = null;
        _openingOutputId = null;
        final canRetrySamePair = _pendingSetupCheckCanRetrySamePair;
        _pendingSetupCheckCanRetrySamePair = false;
        if (_setupCheckPending &&
            isCurrentSession() &&
            _cubit._midiSetupSubscription != null) {
          if (openFailed && !canRetrySamePair) {
            _failedPairToSkipNextCheck = (inputDevice.id, outputDevice.id);
          }
          _triggerSetupCheck();
        }
      }
    }

    if (!needsInitialSync ||
        !isCurrentSession() ||
        !identical(_cubit.disting(), newDistingManager)) {
      return;
    }

    final syncSucceeded = await performSyncAndEmit();
    if (syncSucceeded &&
        isCurrentSession() &&
        identical(_cubit.disting(), newDistingManager)) {
      _cubit._monitoringDelegate.resumeCpuMonitoring();
    }
  }

  Future<void> connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) => _connectToDevices(inputDevice, outputDevice, sysExId);

  Future<void> _connectToDevices(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) async {
    if (_openingConnection || _cubit.isClosed) return;
    final openToken = ++_connectionSessionToken;
    _activeOpenToken = openToken;
    _openingInputId = inputDevice.id;
    _openingOutputId = outputDevice.id;
    _pendingReconnectTarget = null;
    _setupCheckPending = false;
    _pendingSetupCheckCanRetrySamePair = false;
    _failedPairToSkipNextCheck = null;

    bool isCurrentSession() =>
        !_cubit.isClosed && _connectionSessionToken == openToken;
    bool isCurrentOpen() => isCurrentSession() && _activeOpenToken == openToken;

    final normalizedSysExId = _normalizeSysExId(sysExId);
    final target = _SelectedMidiTarget(
      inputId: inputDevice.id,
      inputName:
          identical(inputDevice, _cubit._lastOnlineInputDevice) &&
              _lastOnlineTarget?.inputId == inputDevice.id
          ? _lastOnlineTarget!.inputName
          : inputDevice.name,
      outputId: outputDevice.id,
      outputName:
          identical(outputDevice, _cubit._lastOnlineOutputDevice) &&
              _lastOnlineTarget?.outputId == outputDevice.id
          ? _lastOnlineTarget!.outputName
          : outputDevice.name,
      sysExId: normalizedSysExId,
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

      final nextDesired = _DesiredDeviceSelection(
        input: _desiredEndpointFrom(id: target.inputId, name: target.inputName),
        output: _desiredEndpointFrom(
          id: target.outputId,
          name: target.outputName,
        ),
        sysExId: target.sysExId,
      );
      _desiredSelection = nextDesired;
      final persistRevision = ++_selectionRevision;
      await _schedulePersistDesiredSelection(nextDesired, persistRevision);
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
        sysExId: target.sysExId,
      );

      _activeTarget = target;
      _lastOnlineTarget = target;
      _cubit._lastOnlineInputDevice = inputDevice;
      _cubit._lastOnlineOutputDevice = outputDevice;
      _cubit._lastOnlineSysExId = target.sysExId;

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
      _cubit._lastOnlineInputDevice = null;
      _cubit._lastOnlineOutputDevice = null;
      _cubit._lastOnlineSysExId = null;
      _lastOnlineTarget = null;
      await loadDevices(sessionToken: openToken);
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

  Future<_DeviceListSnapshot> _fetchDeviceLists() async {
    final devices = List<MidiDevice>.of(
      await _cubit._midiCommand.devices ?? const <MidiDevice>[],
    );
    devices.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    final inputDevices = devices
        .where((it) => it.inputPorts.isNotEmpty)
        .toList();
    final outputDevices = devices
        .where((it) => it.outputPorts.isNotEmpty)
        .toList();
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
    return _DeviceListSnapshot(
      allDevices: devices,
      inputDevices: inputDevices,
      outputDevices: outputDevices,
    );
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
