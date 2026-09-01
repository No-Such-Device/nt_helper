part of 'disting_cubit.dart';

class _OfflineDemoDelegate {
  final DistingCubit _cubit;

  _OfflineDemoDelegate(this._cubit);

  Future<void> onDemo() async {
    // Stop listening for MIDI setup changes when entering demo mode
    _cubit._stopMidiSetupListener();

    // Stop CC notifications before replacing manager
    _cubit._ccNotificationDelegate.stop();

    // --- Create Mock Manager and Fetch State ---
    final mockManager = MockDistingMidiManager();
    final distingVersion =
        await mockManager.requestVersionString() ?? "Demo Error";
    final firmwareVersion = FirmwareVersion(distingVersion);
    _cubit._lastKnownFirmwareVersion = firmwareVersion;
    // Set the parameter unit scheme based on firmware version
    ParameterEditorRegistry.setFirmwareVersion(firmwareVersion);
    final presetName =
        await mockManager.requestPresetName() ?? "Demo Preset Error";
    final algorithms = await _cubit._fetchMockAlgorithms(mockManager);
    final unitStrings = await mockManager.requestUnitStrings() ?? [];
    final numSlots = await mockManager.requestNumAlgorithmsInPreset() ?? 0;
    final slots = await _cubit.fetchSlots(numSlots, mockManager);

    _cubit._emitState(
      DistingState.synchronized(
        disting: mockManager,
        distingVersion: distingVersion,
        firmwareVersion: firmwareVersion,
        deviceIoProfile: DeviceIoProfile.distingForFirmware(firmwareVersion),
        presetName: presetName,
        algorithms: algorithms,
        slots: slots,
        unitStrings: unitStrings,
        demo: true,
      ),
    );

    // Create parameter queue for demo manager
    _cubit._createParameterQueue();
  }

  Future<void> goOffline() async {
    final currentState = _cubit.state;
    if (currentState is DistingStateSynchronized && currentState.offline) {
      return; // Already offline
    }

    // Stop listening for MIDI setup changes when going offline
    _cubit._stopMidiSetupListener();

    // Stop CC notifications before disconnecting (avoids callbacks on disposed manager)
    _cubit._ccNotificationDelegate.stop();

    // Get devices and manager from CURRENT state before changing it
    MidiDevice? currentInputDevice;
    MidiDevice? currentOutputDevice;
    IDistingMidiManager? currentManager = _cubit.disting();
    DeviceIoProfile? currentDeviceIoProfile;

    if (currentState is DistingStateConnected) {
      currentInputDevice = currentState.inputDevice;
      currentOutputDevice = currentState.outputDevice;
    } else if (currentState is DistingStateSynchronized) {
      currentInputDevice = currentState.inputDevice;
      currentOutputDevice = currentState.outputDevice;
      currentDeviceIoProfile = currentState.deviceIoProfile;
    }

    _cubit._emitState(
      DistingState.connected(disting: MockDistingMidiManager(), loading: true),
    );

    try {
      // Disconnect existing MIDI connection IF devices were present
      if (currentManager != null) {
        if (currentInputDevice != null) {
          _cubit._midiCommand.disconnectDevice(currentInputDevice);
        }
        if (currentOutputDevice != null &&
            currentOutputDevice.id != currentInputDevice?.id) {
          _cubit._midiCommand.disconnectDevice(currentOutputDevice);
        }
        currentManager.dispose();
      }
      _cubit._offlineManager?.dispose();

      // Create and initialize the offline manager
      _cubit._offlineManager = OfflineDistingMidiManager(_cubit.database);
      await _cubit._offlineManager!.initializeFromDb(null);
      final version =
          await _cubit._offlineManager!.requestVersionString() ?? "Offline";
      final firmwareVersion =
          _cubit._lastKnownFirmwareVersion ?? FirmwareVersion("1.15");
      _cubit._lastKnownFirmwareVersion = firmwareVersion;
      final units = await _cubit._offlineManager!.requestUnitStrings() ?? [];
      final availableAlgorithmsInfo = await _cubit._fetchOfflineAlgorithms();
      final presetName =
          await _cubit._offlineManager!.requestPresetName() ?? "Offline Preset";
      final numAlgorithmsInPreset =
          await _cubit._offlineManager!.requestNumAlgorithmsInPreset() ?? 0;
      final List<Slot> initialSlots = await _cubit.fetchSlots(
        numAlgorithmsInPreset,
        _cubit._offlineManager!,
      );

      _cubit._emitState(
        DistingState.synchronized(
          disting: _cubit._offlineManager!,
          distingVersion: version,
          firmwareVersion: firmwareVersion,
          deviceIoProfile:
              currentDeviceIoProfile ??
              DeviceIoProfile.distingForFirmware(firmwareVersion),
          presetName: presetName,
          algorithms: availableAlgorithmsInfo,
          slots: initialSlots,
          unitStrings: units,
          inputDevice: null,
          outputDevice: null,
          offline: true,
          loading: false,
        ),
      );

      _cubit._createParameterQueue();
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      await _cubit.loadDevices();
    }
  }

  Future<void> goOnline() async {
    final currentState = _cubit.state;
    if (!(currentState is DistingStateSynchronized && currentState.offline)) {
      // Disconnect existing MIDI connection before loading devices
      _cubit.disconnect();
      await _cubit.loadDevices();
      return;
    }

    // Dispose offline manager first
    _cubit._offlineManager?.dispose();
    _cubit._offlineManager = null;

    // Check if we have details from the last online session
    if (_cubit._lastOnlineInputDevice != null &&
        _cubit._lastOnlineOutputDevice != null &&
        _cubit._lastOnlineSysExId != null) {
      try {
        await _cubit.connectToDevices(
          _cubit._lastOnlineInputDevice!,
          _cubit._lastOnlineOutputDevice!,
          _cubit._lastOnlineSysExId!,
        );
        return;
      } catch (_) {
        _cubit._lastOnlineInputDevice = null;
        _cubit._lastOnlineOutputDevice = null;
        _cubit._lastOnlineSysExId = null;
      }
    }

    _cubit.disconnect();
    await _cubit.loadDevices();
  }

  Future<void> loadPresetOffline(FullPresetDetails presetDetails) async {
    final currentState = _cubit.state;
    if (!(currentState is DistingStateSynchronized && currentState.offline)) {
      return;
    }
    if (_cubit._offlineManager == null) {
      return;
    }

    _cubit._emitState(currentState.copyWith(loading: true));

    try {
      await _cubit._offlineManager!.initializeFromDb(presetDetails);

      final presetName =
          await _cubit._offlineManager!.requestPresetName() ?? "Error";
      final numAlgorithmsInPreset =
          await _cubit._offlineManager!.requestNumAlgorithmsInPreset() ?? 0;
      final slots = await _cubit.fetchSlots(
        numAlgorithmsInPreset,
        _cubit._offlineManager!,
      );

      final availableAlgorithmsInfo = await _cubit._fetchOfflineAlgorithms();
      final units = await _cubit._offlineManager!.requestUnitStrings() ?? [];
      final version =
          await _cubit._offlineManager!.requestVersionString() ?? "Offline";

      final firmwareVersion =
          _cubit._lastKnownFirmwareVersion ?? FirmwareVersion("1.15");
      _cubit._emitState(
        DistingState.synchronized(
          disting: _cubit._offlineManager!,
          distingVersion: version,
          firmwareVersion: firmwareVersion,
          deviceIoProfile: currentState.deviceIoProfile,
          presetName: presetName,
          algorithms: availableAlgorithmsInfo,
          slots: slots,
          unitStrings: units,
          offline: true,
          loading: false,
          screenshot: currentState.screenshot,
          demo: currentState.demo,
        ),
      );
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      _cubit._emitState(currentState.copyWith(loading: false));
    }
  }
}
