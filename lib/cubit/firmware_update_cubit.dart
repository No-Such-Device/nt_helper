import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bloc/bloc.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';

typedef LocalFirmwareFileReader = Future<List<int>?> Function(String path);

Future<List<int>?> _readLocalFirmwareFileFromDisk(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

/// Cubit for managing the firmware update workflow
class FirmwareUpdateCubit extends Cubit<FirmwareUpdateState> {
  final FirmwareVersionService _firmwareVersionService;
  final FlashToolManager _flashToolManager;
  final FlashToolBridge _flashToolBridge;
  final bool _isDemo;
  final bool _isOffline;
  final String _initialCurrentVersion;
  final FirmwareVersion? _firmwareVersion;
  IDistingMidiManager? _midiManager;
  final Future<IDistingMidiManager> Function()? _createMidiManager;
  final void Function(IDistingMidiManager)? _disposeMidiManager;
  final Future<bool> Function()? _checkMidiDevices;
  final LocalFirmwareFileReader _readLocalFirmwareFile;
  final Duration _midiPollInterval;
  final int _midiPollAttempts;
  final bool _isWindows;
  // A supplied manager is borrowed until a deliberate firmware handoff.
  bool _ownsMidiManager = false;
  bool _closing = false;
  int _operationGeneration = 0;
  int _midiReacquisitionGeneration = 0;

  StreamSubscription<FlashProgress>? _flashSubscription;
  String? _currentFirmwarePath;
  String? _currentTargetVersion;

  FirmwareUpdateCubit({
    required FirmwareVersionService firmwareVersionService,
    required FlashToolManager flashToolManager,
    required FlashToolBridge flashToolBridge,
    required String currentVersion,
    required bool isDemo,
    required bool isOffline,
    FirmwareVersion? firmwareVersion,
    IDistingMidiManager? midiManager,
    Future<IDistingMidiManager> Function()? createMidiManager,
    void Function(IDistingMidiManager)? disposeMidiManager,
    Future<bool> Function()? checkMidiDevices,
    LocalFirmwareFileReader? readLocalFirmwareFile,
    Duration midiPollInterval = const Duration(seconds: 5),
    int midiPollAttempts = 12,
    bool? isWindowsOverride,
  }) : _firmwareVersionService = firmwareVersionService,
       _flashToolManager = flashToolManager,
       _flashToolBridge = flashToolBridge,
       _isDemo = isDemo,
       _isOffline = isOffline,
       _initialCurrentVersion = currentVersion,
       _firmwareVersion = firmwareVersion,
       _midiManager = midiManager,
       _createMidiManager = createMidiManager,
       _disposeMidiManager = disposeMidiManager,
       _checkMidiDevices = checkMidiDevices,
       _readLocalFirmwareFile =
           readLocalFirmwareFile ?? _readLocalFirmwareFileFromDisk,
       _midiPollInterval = midiPollInterval,
       _midiPollAttempts = midiPollAttempts,
       _isWindows = isWindowsOverride ?? Platform.isWindows,
       super(FirmwareUpdateState.initial(currentVersion: currentVersion));

  bool _isCurrent(int generation) =>
      !_closing && !isClosed && generation == _operationGeneration;

  bool get _canAutoEnterBootloader =>
      _firmwareVersion?.hasBootloaderSysEx == true &&
      (_midiManager != null || _createMidiManager != null);

  /// Whether firmware update is available (desktop only, not demo/offline)
  bool get isUpdateAvailable {
    if (_isDemo || _isOffline) return false;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return false;
    }
    return true;
  }

  /// Load available firmware versions from the server
  Future<void> loadAvailableVersions() async {
    if (_closing || isClosed || !isUpdateAvailable) return;
    final generation = _operationGeneration;

    final currentState = state;
    if (currentState is! FirmwareUpdateStateInitial) return;

    emit(currentState.copyWith(isLoadingVersions: true, fetchError: null));

    try {
      final versions = await _firmwareVersionService.fetchAvailableVersions();
      if (!_isCurrent(generation) || state is! FirmwareUpdateStateInitial) {
        return;
      }
      emit(
        currentState.copyWith(
          availableVersions: versions,
          isLoadingVersions: false,
        ),
      );
    } catch (e) {
      if (!_isCurrent(generation) || state is! FirmwareUpdateStateInitial) {
        return;
      }
      emit(
        currentState.copyWith(
          isLoadingVersions: false,
          fetchError: e.toString(),
        ),
      );
    }
  }

  /// Start the firmware update process for a specific version
  Future<void> startUpdate(FirmwareRelease version) async {
    if (_closing || isClosed) return;
    final generation = ++_operationGeneration;
    if (!isUpdateAvailable) {
      emit(
        FirmwareUpdateState.error(
          message: _isDemo
              ? 'Firmware updates not available in demo mode'
              : _isOffline
              ? 'Firmware updates not available in offline mode'
              : 'Firmware updates only available on desktop platforms',
        ),
      );
      return;
    }

    emit(FirmwareUpdateState.downloading(version: version, progress: 0));

    try {
      final firmwarePath = await _firmwareVersionService.downloadFirmware(
        version,
        onProgress: (progress) {
          if (_isCurrent(generation) &&
              state is FirmwareUpdateStateDownloading) {
            emit(
              FirmwareUpdateState.downloading(
                version: version,
                progress: progress,
              ),
            );
          }
        },
      );

      if (!_isCurrent(generation)) {
        await _deleteTempFile(firmwarePath);
        return;
      }
      _currentFirmwarePath = firmwarePath;
      _currentTargetVersion = version.version;

      emit(
        FirmwareUpdateState.waitingForBootloader(
          firmwarePath: firmwarePath,
          targetVersion: version.version,
          canAutoEnter: _canAutoEnterBootloader,
        ),
      );
    } on FirmwareDownloadException catch (e) {
      if (!_isCurrent(generation)) return;
      emit(
        FirmwareUpdateState.error(
          message: e.message,
          errorType: FirmwareErrorType.download,
        ),
      );
    } catch (e) {
      if (!_isCurrent(generation)) return;
      emit(
        FirmwareUpdateState.error(
          message: 'Download failed: $e',
          errorType: FirmwareErrorType.download,
        ),
      );
    }
  }

  /// Use a local firmware file instead of downloading
  Future<void> useLocalFile(String path) async {
    if (_closing || isClosed) return;
    final generation = ++_operationGeneration;
    if (!isUpdateAvailable) {
      emit(
        FirmwareUpdateState.error(message: 'Firmware updates not available'),
      );
      return;
    }

    // Validate the file exists and is a valid ZIP
    try {
      final bytes = await _readLocalFirmwareFile(path);
      if (!_isCurrent(generation)) return;
      if (bytes == null) {
        emit(
          const FirmwareUpdateState.error(
            message: 'Selected file does not exist',
          ),
        );
        return;
      }

      // Validate it's a valid ZIP with firmware binary
      final archive = ZipDecoder().decodeBytes(bytes);

      if (archive.isEmpty) {
        emit(
          const FirmwareUpdateState.error(
            message: 'Selected ZIP archive is empty',
          ),
        );
        return;
      }

      final hasFirmware = archive.any(
        (f) =>
            f.name.toLowerCase().contains('disting') &&
            f.name.toLowerCase().endsWith('.bin'),
      );
      if (!hasFirmware) {
        emit(
          const FirmwareUpdateState.error(
            message:
                'ZIP does not contain expected firmware file (disting_NT.bin)',
          ),
        );
        return;
      }

      _currentFirmwarePath = path;
      _currentTargetVersion = 'local';

      emit(
        FirmwareUpdateState.waitingForBootloader(
          firmwarePath: path,
          targetVersion: 'local',
          canAutoEnter: _canAutoEnterBootloader,
        ),
      );
    } catch (e) {
      if (!_isCurrent(generation)) return;
      emit(
        FirmwareUpdateState.error(
          message: 'Invalid firmware file: $e',
          errorType: FirmwareErrorType.download,
        ),
      );
    }
  }

  /// User confirmed they want to proceed with the firmware update.
  /// If auto-enter is available, enters bootloader automatically; otherwise
  /// starts flashing directly (user already in bootloader mode).
  Future<void> confirmAndFlash() async {
    if (_closing || isClosed) return;
    final currentState = state;
    if (currentState is! FirmwareUpdateStateWaitingForBootloader) return;

    if (currentState.canAutoEnter) {
      await _autoEnterBootloaderAndFlash(
        currentState.firmwarePath,
        currentState.targetVersion,
      );
    } else {
      await startFlashing();
    }
  }

  /// Start the flash process after user confirms bootloader mode
  Future<void> startFlashing() async {
    if (_closing || isClosed) return;
    final currentState = state;
    final String firmwarePath;
    final String targetVersion;

    if (currentState is FirmwareUpdateStateWaitingForBootloader) {
      firmwarePath = currentState.firmwarePath;
      targetVersion = currentState.targetVersion;
    } else if (currentState is FirmwareUpdateStateEnteringBootloader) {
      firmwarePath = currentState.firmwarePath;
      targetVersion = currentState.targetVersion;
    } else {
      return;
    }

    final generation = ++_operationGeneration;

    // On Linux, automatically install udev rules if missing
    if (Platform.isLinux) {
      final udevRulesFile = File('/etc/udev/rules.d/99-disting-nt.rules');
      final rulesExist = await udevRulesFile.exists();
      if (!_isCurrent(generation)) return;
      if (!rulesExist) {
        final installed = await _installUdevRulesInternal();
        if (!_isCurrent(generation)) return;
        if (!installed) {
          emit(
            FirmwareUpdateState.error(
              message:
                  'USB access rules are required for firmware updates. '
                  'Please authorize the installation when prompted.',
              errorType: FirmwareErrorType.udevMissing,
              firmwarePath: firmwarePath,
              targetVersion: targetVersion,
            ),
          );
          return;
        }
      }
    }

    // First ensure the flash tool is available
    try {
      await _flashToolManager.getToolPath();
    } catch (e) {
      if (!_isCurrent(generation)) return;
      _releaseOwnedMidiConnection();
      emit(
        FirmwareUpdateState.error(
          message: 'Failed to prepare flash tool: $e',
          errorType: FirmwareErrorType.general,
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
        ),
      );
      return;
    }

    if (!_isCurrent(generation)) return;
    await _flashSubscription?.cancel();
    _flashSubscription = null;
    if (!_isCurrent(generation)) return;

    // The desktop MIDI backends must release the selected ports before the
    // standalone flasher resets and re-enumerates the NT.
    _releaseMidiConnection();

    FlashStage? currentStage;

    emit(
      FirmwareUpdateState.flashing(
        targetVersion: targetVersion,
        progress: const FlashProgress(
          stage: FlashStage.sdpConnect,
          percent: 0,
          message: 'Connecting to bootloader...',
        ),
      ),
    );

    try {
      final stream = _flashToolBridge.flash(firmwarePath);

      _flashSubscription = stream.listen(
        (progress) {
          if (!_isCurrent(generation)) return;
          currentStage = progress.stage;
          if (progress.isError) {
            emit(
              FirmwareUpdateState.error(
                message: progress.message,
                errorType: progress.isSandboxError
                    ? FirmwareErrorType.sandboxRestriction
                    : _getErrorTypeForStage(currentStage),
                failedStage: currentStage,
                firmwarePath: firmwarePath,
                targetVersion: targetVersion,
              ),
            );
          } else if (progress.stage == FlashStage.complete &&
              progress.percent == 100) {
            unawaited(_cleanupTempFiles());
            _startMidiReacquisition(targetVersion);
          } else {
            emit(
              FirmwareUpdateState.flashing(
                targetVersion: targetVersion,
                progress: progress,
              ),
            );
          }
        },
        onError: (error) {
          if (!_isCurrent(generation)) return;
          emit(
            FirmwareUpdateState.error(
              message: 'Flash error: $error',
              errorType: _getErrorTypeForStage(currentStage),
              failedStage: currentStage,
              firmwarePath: firmwarePath,
              targetVersion: targetVersion,
            ),
          );
        },
        onDone: () {
          if (!_isCurrent(generation)) return;
          // Stream completed - check if we're still in flashing state
          // If so, something went wrong
          if (state is FirmwareUpdateStateFlashing) {
            emit(
              FirmwareUpdateState.error(
                message: 'Flash process ended unexpectedly',
                errorType: _getErrorTypeForStage(currentStage),
                failedStage: currentStage,
                firmwarePath: firmwarePath,
                targetVersion: targetVersion,
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!_isCurrent(generation)) return;
      emit(
        FirmwareUpdateState.error(
          message: 'Failed to start flash: $e',
          errorType: FirmwareErrorType.general,
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
        ),
      );
    }
  }

  static const _bootloaderWaitDuration = Duration(seconds: 5);
  static const _bootloaderWaitTickInterval = Duration(milliseconds: 100);

  /// Send the enter-bootloader SysEx and wait for device to switch modes.
  Future<void> _autoEnterBootloaderAndFlash(
    String firmwarePath,
    String targetVersion,
  ) async {
    final generation = ++_operationGeneration;
    emit(
      FirmwareUpdateState.enteringBootloader(
        firmwarePath: firmwarePath,
        targetVersion: targetVersion,
      ),
    );

    try {
      if (_midiManager == null && _createMidiManager != null) {
        final manager = await _createMidiManager();
        if (!_isCurrent(generation)) {
          _disposeManager(manager);
          return;
        }
        _midiManager = manager;
      }
      // A bootloader command deliberately consumes even a borrowed manager.
      _ownsMidiManager = true;
      final manager = _midiManager!;
      try {
        await manager.requestEnterBootloader();
      } finally {
        // A late command completion must not release a newer retry's manager.
        if (identical(_midiManager, manager)) _releaseOwnedMidiConnection();
      }
    } catch (e) {
      if (!_isCurrent(generation)) return;
      emit(
        FirmwareUpdateState.error(
          message: 'Failed to enter bootloader: $e',
          errorType: FirmwareErrorType.bootloaderConnection,
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
        ),
      );
      return;
    }
    if (!_isCurrent(generation)) return;

    // Wait for the device to switch to bootloader mode, updating progress.
    final totalTicks =
        _bootloaderWaitDuration.inMilliseconds ~/
        _bootloaderWaitTickInterval.inMilliseconds;
    for (var tick = 1; tick <= totalTicks; tick++) {
      await Future<void>.delayed(_bootloaderWaitTickInterval);
      if (!_isCurrent(generation) ||
          state is! FirmwareUpdateStateEnteringBootloader) {
        return;
      }
      emit(
        FirmwareUpdateState.enteringBootloader(
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
          progress: tick / totalTicks,
        ),
      );
    }

    if (_isCurrent(generation) &&
        state is FirmwareUpdateStateEnteringBootloader) {
      await startFlashing();
    }
  }

  void _releaseOwnedMidiConnection() {
    if (_ownsMidiManager) _releaseMidiConnection();
  }

  void _releaseMidiConnection() {
    final manager = _midiManager;
    if (manager == null) return;
    _midiManager = null;
    _ownsMidiManager = false;
    _disposeManager(manager);
  }

  void _disposeManager(IDistingMidiManager manager) {
    try {
      final dispose = _disposeMidiManager;
      if (dispose != null) {
        dispose(manager);
      } else {
        manager.dispose();
      }
    } catch (_) {
      // The NT may disappear while its handles are being closed. The release
      // remains complete from this cubit's perspective and must not be retried.
    }
  }

  void _startMidiReacquisition(String newVersion) {
    final checkMidiDevices = _checkMidiDevices;
    if (checkMidiDevices == null) {
      // Keep direct Cubit users backwards compatible. The firmware screen
      // always supplies a fresh platform-enumeration callback.
      emit(FirmwareUpdateState.success(newVersion: newVersion));
      return;
    }

    final generation = ++_midiReacquisitionGeneration;
    emit(
      FirmwareUpdateState.verifyingMidi(
        newVersion: newVersion,
        totalAttempts: _midiPollAttempts,
      ),
    );
    unawaited(
      _pollForMidiDevices(
        newVersion: newVersion,
        generation: generation,
        checkMidiDevices: checkMidiDevices,
      ),
    );
  }

  Future<void> _pollForMidiDevices({
    required String newVersion,
    required int generation,
    required Future<bool> Function() checkMidiDevices,
  }) async {
    for (var attempt = 1; attempt <= _midiPollAttempts; attempt++) {
      await Future<void>.delayed(_midiPollInterval);
      if (_closing || isClosed || generation != _midiReacquisitionGeneration) {
        return;
      }

      var found = false;
      try {
        found = await checkMidiDevices();
      } catch (_) {
        // Enumeration can fail transiently while the NT is rebooting. Keep
        // retrying through the full timeout.
      }

      if (_closing || isClosed || generation != _midiReacquisitionGeneration) {
        return;
      }
      if (found) {
        emit(FirmwareUpdateState.success(newVersion: newVersion));
        return;
      }

      if (attempt < _midiPollAttempts) {
        emit(
          FirmwareUpdateState.verifyingMidi(
            newVersion: newVersion,
            completedAttempts: attempt,
            totalAttempts: _midiPollAttempts,
          ),
        );
      }
    }

    emit(
      FirmwareUpdateState.midiRecoveryRequired(
        newVersion: newVersion,
        isWindows: _isWindows,
      ),
    );
  }

  /// Retry the complete five-second/one-minute MIDI detection cycle.
  Future<void> checkMidiAgain() async {
    if (_closing || isClosed) return;
    final currentState = state;
    final checkMidiDevices = _checkMidiDevices;
    if (currentState is! FirmwareUpdateStateMidiRecoveryRequired ||
        checkMidiDevices == null) {
      return;
    }

    final generation = ++_midiReacquisitionGeneration;
    emit(
      FirmwareUpdateState.verifyingMidi(
        newVersion: currentState.newVersion,
        totalAttempts: _midiPollAttempts,
      ),
    );
    await _pollForMidiDevices(
      newVersion: currentState.newVersion,
      generation: generation,
      checkMidiDevices: checkMidiDevices,
    );
  }

  /// Get the error type based on which stage failed
  FirmwareErrorType _getErrorTypeForStage(FlashStage? stage) {
    if (stage == null) return FirmwareErrorType.general;
    switch (stage) {
      case FlashStage.sdpConnect:
      case FlashStage.blCheck:
        return FirmwareErrorType.bootloaderConnection;
      case FlashStage.sdpUpload:
      case FlashStage.write:
        return FirmwareErrorType.flashWrite;
      case FlashStage.configure:
      case FlashStage.reset:
      case FlashStage.complete:
        return FirmwareErrorType.general;
    }
  }

  /// Cancel the current operation
  Future<void> cancel() async {
    if (_closing || isClosed) return;
    final generation = ++_operationGeneration;
    _midiReacquisitionGeneration++;
    final subscription = _flashSubscription;
    _flashSubscription = null;
    _releaseMidiConnection();
    final cleanup = _cleanupTempFiles();
    final cancellation = _flashToolBridge.cancel();
    await subscription?.cancel();
    await cancellation;
    await cleanup;
    if (!_isCurrent(generation)) return;

    final currentState = state;
    if (currentState is FirmwareUpdateStateInitial) {
      // Already in initial state, nothing to do
    } else {
      // Get the current version from any state that has it
      emit(FirmwareUpdateState.initial(currentVersion: _getCurrentVersion()));
      // Reload available versions
      await loadAvailableVersions();
    }
  }

  /// Clean up temporary files (called on success, cancel, or error dismiss)
  Future<void> cleanupAndReset() async {
    if (_closing || isClosed) return;
    final generation = ++_operationGeneration;
    _midiReacquisitionGeneration++;
    final subscription = _flashSubscription;
    _flashSubscription = null;
    _releaseOwnedMidiConnection();
    final cleanup = _cleanupTempFiles();
    await subscription?.cancel();
    await cleanup;
    if (!_isCurrent(generation)) return;
    emit(FirmwareUpdateState.initial(currentVersion: _getCurrentVersion()));
    // Reload available versions
    await loadAvailableVersions();
  }

  /// Return to bootloader instructions (from error state)
  /// Used when user needs to re-enter bootloader mode
  void returnToBootloaderInstructions() {
    if (_closing || isClosed) return;
    _operationGeneration++;
    _midiReacquisitionGeneration++;
    final currentState = state;
    String? firmwarePath;
    String? targetVersion;

    if (currentState is FirmwareUpdateStateError) {
      firmwarePath = currentState.firmwarePath;
      targetVersion = currentState.targetVersion;
    }

    // Fall back to stored values if not in error state
    firmwarePath ??= _currentFirmwarePath;
    targetVersion ??= _currentTargetVersion;

    if (firmwarePath != null && targetVersion != null) {
      emit(
        FirmwareUpdateState.waitingForBootloader(
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
          canAutoEnter: _canAutoEnterBootloader,
        ),
      );
    } else {
      // Can't return to bootloader without firmware path, reset instead
      emit(FirmwareUpdateState.initial(currentVersion: _getCurrentVersion()));
    }
  }

  /// Retry the flash process (from error state)
  /// Used when the flash failed during upload/write
  Future<void> retryFlash() async {
    if (_closing || isClosed) return;
    _operationGeneration++;
    _midiReacquisitionGeneration++;
    final currentState = state;
    String? firmwarePath;
    String? targetVersion;

    if (currentState is FirmwareUpdateStateError) {
      firmwarePath = currentState.firmwarePath;
      targetVersion = currentState.targetVersion;
    }

    // Fall back to stored values
    firmwarePath ??= _currentFirmwarePath;
    targetVersion ??= _currentTargetVersion;

    if (firmwarePath != null && targetVersion != null) {
      emit(
        FirmwareUpdateState.waitingForBootloader(
          firmwarePath: firmwarePath,
          targetVersion: targetVersion,
          canAutoEnter: _canAutoEnterBootloader,
        ),
      );
    } else {
      // Can't retry without firmware path, reset instead
      emit(FirmwareUpdateState.initial(currentVersion: _getCurrentVersion()));
    }
  }

  /// Install udev rules on Linux using pkexec for elevated privileges
  /// Called from error state when user wants to retry after failed auto-install
  Future<bool> installUdevRules() async {
    if (_closing || isClosed) return false;
    final generation = _operationGeneration;
    if (!Platform.isLinux) return false;

    final currentState = state;
    if (currentState is! FirmwareUpdateStateError ||
        currentState.errorType != FirmwareErrorType.udevMissing) {
      return false;
    }

    final installed = await _installUdevRulesInternal();
    if (!_isCurrent(generation)) return false;
    if (installed) {
      // Success - return to bootloader waiting state and retry
      final firmwarePath = currentState.firmwarePath ?? _currentFirmwarePath;
      final targetVersion = currentState.targetVersion ?? _currentTargetVersion;

      if (firmwarePath != null && targetVersion != null) {
        emit(
          FirmwareUpdateState.waitingForBootloader(
            firmwarePath: firmwarePath,
            targetVersion: targetVersion,
          ),
        );
        // Automatically retry flashing
        await startFlashing();
        return true;
      }
    }

    return false;
  }

  /// Internal helper to install udev rules using pkexec
  /// Returns true if successful, false if user cancelled or error occurred
  Future<bool> _installUdevRulesInternal() async {
    try {
      // Create temp file with udev rules content
      final tempDir = Directory.systemTemp;
      final tempRulesFile = File('${tempDir.path}/99-disting-nt.rules');

      const rulesContent = '''
# udev rules for Disting NT firmware update
# NXP ROM bootloader (SDP mode) - used during initial connection
SUBSYSTEM=="usb", ATTR{idVendor}=="1fc9", ATTR{idProduct}=="0135", MODE="0666"
# NXP flashloader (bootloader running) - used during firmware flash
SUBSYSTEM=="usb", ATTR{idVendor}=="15a2", ATTR{idProduct}=="0073", MODE="0666"
''';

      await tempRulesFile.writeAsString(rulesContent);

      // Use pkexec to install the rules with a shell script
      final result = await Process.run('pkexec', [
        'sh',
        '-c',
        'cp "${tempRulesFile.path}" /etc/udev/rules.d/99-disting-nt.rules && '
            'udevadm control --reload-rules && '
            'udevadm trigger',
      ]);

      // Clean up temp file
      try {
        await tempRulesFile.delete();
      } catch (_) {}

      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Get diagnostic information for error reporting
  Future<String> getDiagnostics() async {
    final currentState = state;
    final buffer = StringBuffer();

    // Platform info
    buffer.writeln(
      'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );

    // Version info
    buffer.writeln('Current Firmware: $_initialCurrentVersion');
    if (currentState is FirmwareUpdateStateError &&
        currentState.targetVersion != null) {
      buffer.writeln('Target Firmware: ${currentState.targetVersion}');
    } else if (_currentTargetVersion != null) {
      buffer.writeln('Target Firmware: $_currentTargetVersion');
    }

    // Error info
    if (currentState is FirmwareUpdateStateError) {
      if (currentState.failedStage != null) {
        buffer.writeln(
          'Error Stage: ${currentState.failedStage!.machineValue}',
        );
      }
      buffer.writeln('Error Message: ${currentState.message}');
    }

    // Recent log lines
    buffer.writeln('\nRecent Log:');
    final recentLogs = await _flashToolBridge.getRecentLogLines(20);
    for (final line in recentLogs) {
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  /// Clean up downloaded firmware files
  Future<void> _cleanupTempFiles() async {
    final path = _currentFirmwarePath;
    _currentFirmwarePath = null;
    _currentTargetVersion = null;
    if (path != null) await _deleteTempFile(path);
  }

  Future<void> _deleteTempFile(String path) async {
    // Retain user-selected files; only remove downloaded firmware packages.
    if (!path.contains('distingNT_')) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  /// Get the stored current version (persists across state changes)
  String _getCurrentVersion() => _initialCurrentVersion;

  @override
  Future<void> close() async {
    _closing = true;
    _operationGeneration++;
    _midiReacquisitionGeneration++;
    _releaseOwnedMidiConnection();
    await _flashSubscription?.cancel();
    _flashSubscription = null;
    await _cleanupTempFiles();
    return super.close();
  }
}
