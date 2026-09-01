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

class _ConnectionDelegate {
  _ConnectionDelegate(this._cubit);

  final DistingCubit _cubit;
  int _syncGeneration = 0;

  MidiDevice? _resolveSelection(
    List<MidiDevice> devices,
    MidiDevice? previousSelection,
  ) {
    if (previousSelection == null) return null;
    return devices
            .where((device) => device.id == previousSelection.id)
            .firstOrNull ??
        devices
            .where((device) => device.name == previousSelection.name)
            .firstOrNull;
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
        selectedInputDevice: savedPairAvailable ? savedInputDevice : null,
        selectedOutputDevice: savedPairAvailable ? savedOutputDevice : null,
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
      final selectedInputDevice = selectionState == null
          ? null
          : _resolveSelection(inputDevices, selectionState.selectedInputDevice);
      final selectedOutputDevice = selectionState == null
          ? null
          : _resolveSelection(
              outputDevices,
              selectionState.selectedOutputDevice,
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
  /// Automatically refreshes device list when changes are detected.
  void startMidiSetupListener() {
    // Cancel any existing subscription to avoid duplicates
    _cubit._midiSetupSubscription?.cancel();
    _cubit._midiSetupSubscription = null;

    // Subscribe to MIDI setup changes
    _cubit._midiSetupSubscription = _cubit._midiCommand.onMidiSetupChanged
        ?.listen((_) {
          StartupLogService.log('DistingCubit: MIDI setup changed');
          // Only refresh if we're still in the device selection state
          if (_cubit.state is DistingStateInitial ||
              _cubit.state is DistingStateSelectDevice) {
            loadDevices();
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

  void disconnect() {
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

    // Disconnect MIDI devices FIRST (closes ALSA ports and stops isolate)
    // Must happen before manager.dispose() to avoid read/write on closed ports
    if (inputDevice != null) {
      _cubit._midiCommand.disconnectDevice(inputDevice);
    }
    if (outputDevice != null && outputDevice.id != inputDevice?.id) {
      _cubit._midiCommand.disconnectDevice(outputDevice);
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

  static const _syncTimeout = Duration(seconds: 60);

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

  Future<bool> performSyncAndEmit() async {
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
        if (!_isCurrentSync(generation, currentState, distingManager)) {
          return;
        }
        if (currentState is DistingStateSynchronized) {
          slots = _cubit._preserveKnownSlotSpecificationsForRefresh(
            previousState: currentState,
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
  ) async {
    StartupLogService.log(
      'DistingCubit.connectToDevices: attempting connection to '
      'input="${inputDevice.name}" (${inputDevice.id}), '
      'output="${outputDevice.name}" (${outputDevice.id}), sysExId=$sysExId',
    );
    // Get the potentially existing manager AND devices from the CURRENT state
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
    final existingManager = _cubit.disting(); // Get manager separately

    // Stop listening for MIDI setup changes while connecting
    stopMidiSetupListener();

    try {
      // Stop CC notifications before disconnecting (avoids callbacks on disposed manager)
      _cubit._ccNotificationDelegate.stop();

      // Disconnect and dispose any existing managers first
      if (existingManager != null) {
        // Explicitly disconnect devices using devices read from the state
        if (existingInputDevice != null) {
          _cubit._midiCommand.disconnectDevice(existingInputDevice);
        }
        // Avoid disconnecting same device twice
        if (existingOutputDevice != null &&
            existingOutputDevice.id != existingInputDevice?.id) {
          _cubit._midiCommand.disconnectDevice(existingOutputDevice);
        }
        existingManager.dispose(); // Dispose the old manager
      }
      _cubit._offlineManager
          ?.dispose(); // Explicitly dispose offline if it exists
      _cubit._offlineManager = null;

      // Connect to the selected device
      StartupLogService.log(
        'DistingCubit.connectToDevices: opening input MIDI device "${inputDevice.name}"',
      );
      await _cubit._midiCommand.connectToDevice(inputDevice);
      if (inputDevice != outputDevice) {
        StartupLogService.log(
          'DistingCubit.connectToDevices: opening output MIDI device "${outputDevice.name}"',
        );
        await _cubit._midiCommand.connectToDevice(outputDevice);
      }
      final prefs = await _cubit._prefs;
      await prefs.setString('selectedInputMidiDevice', inputDevice.name);
      await prefs.setString('selectedOutputMidiDevice', outputDevice.name);
      await prefs.setInt('selectedSysExId', sysExId);

      // Create the NEW online manager
      final newDistingManager = DistingMidiManager(
        midiCommand: _cubit._midiCommand,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
      );

      // Emit Connected state WITH the new manager AND devices
      _cubit._emitState(
        DistingState.connected(
          disting: newDistingManager,
          inputDevice: inputDevice, // Store connected devices
          outputDevice: outputDevice,
          offline: false,
        ),
      );
      StartupLogService.log(
        'DistingCubit.connectToDevices: MIDI ports opened; querying Disting NT next',
      );

      // Create parameter queue for the new manager
      _cubit._createParameterQueue();

      // Store these details as the last successful ONLINE connection
      // BEFORE starting the full sync.
      _cubit._lastOnlineInputDevice = inputDevice;
      _cubit._lastOnlineOutputDevice = outputDevice;
      _cubit._lastOnlineSysExId =
          sysExId; // Use the parameter passed to this method

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

      final syncSucceeded =
          await performSyncAndEmit(); // Sync with the new connection
      if (syncSucceeded) {
        _cubit._monitoringDelegate.resumeCpuMonitoring();
      }
      StartupLogService.log(
        'DistingCubit.connectToDevices: connection flow completed; '
        'syncSucceeded=$syncSucceeded',
      );
    } catch (e, stackTrace) {
      StartupLogService.logError(
        'DistingCubit.connectToDevices: connection failed',
        e,
        stackTrace,
      );
      debugPrintStack(stackTrace: stackTrace);
      // Clear last connection details if connection/sync fails
      _cubit._lastOnlineInputDevice = null;
      _cubit._lastOnlineOutputDevice = null;
      _cubit._lastOnlineSysExId = null;
      // Attempt to clean up MIDI connection on error too
      try {
        _cubit._midiCommand.disconnectDevice(inputDevice);
        if (inputDevice != outputDevice) {
          _cubit._midiCommand.disconnectDevice(outputDevice);
        }
      } catch (disconnectError) {
        // Intentionally empty
      }
      await loadDevices();
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
