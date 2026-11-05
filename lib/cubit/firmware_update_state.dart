import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';

part 'firmware_update_state.freezed.dart';

/// Type of error that occurred during firmware update
enum FirmwareErrorType {
  /// Errors during download/load phase
  download,

  /// Errors connecting to bootloader (SDP_CONNECT, BL_CHECK)
  bootloaderConnection,

  /// Errors during firmware upload/write (SDP_UPLOAD, WRITE)
  flashWrite,

  /// Linux udev rules missing - need to install for USB access
  udevMissing,

  /// macOS sandbox restriction - can't execute flash tool
  /// This occurs when the bundled binary is missing or improperly signed
  sandboxRestriction,

  /// General/unknown error
  general,
}

@freezed
sealed class FirmwareUpdateState with _$FirmwareUpdateState {
  /// Initial state - showing available firmware versions
  const factory FirmwareUpdateState.initial({
    /// Currently installed firmware version string
    required String currentVersion,

    /// Available firmware releases (null if not yet fetched)
    @Default(null) List<FirmwareRelease>? availableVersions,

    /// Whether we're loading available versions
    @Default(false) bool isLoadingVersions,

    /// Error message if fetching versions failed
    @Default(null) String? fetchError,
  }) = FirmwareUpdateStateInitial;

  /// Downloading firmware package
  const factory FirmwareUpdateState.downloading({
    required FirmwareRelease version,
    required double progress,
  }) = FirmwareUpdateStateDownloading;

  /// Waiting for user to confirm before entering bootloader mode
  const factory FirmwareUpdateState.waitingForBootloader({
    required String firmwarePath,
    required String targetVersion,

    /// Whether the device supports automatic bootloader entry via SysEx
    @Default(false) bool canAutoEnter,
  }) = FirmwareUpdateStateWaitingForBootloader;

  /// Auto-entering bootloader mode via SysEx (firmware 1.15+)
  const factory FirmwareUpdateState.enteringBootloader({
    required String firmwarePath,
    required String targetVersion,

    /// Progress 0.0 to 1.0 of the bootloader switch wait period
    @Default(0) double progress,
  }) = FirmwareUpdateStateEnteringBootloader;

  /// Flashing firmware to device
  const factory FirmwareUpdateState.flashing({
    required String targetVersion,
    required FlashProgress progress,
  }) = FirmwareUpdateStateFlashing;

  /// Firmware was installed and the app is waiting for the NT MIDI ports.
  const factory FirmwareUpdateState.verifyingMidi({
    required String newVersion,
    @Default(0) int completedAttempts,
    @Default(12) int totalAttempts,
    @Default(false) bool requiresVersion,
  }) = FirmwareUpdateStateVerifyingMidi;

  /// Firmware was installed, but the NT MIDI ports did not return in time.
  const factory FirmwareUpdateState.midiRecoveryRequired({
    required String newVersion,
    required bool isWindows,
    String? verificationMessage,
  }) = FirmwareUpdateStateMidiRecoveryRequired;

  /// Firmware update completed successfully
  const factory FirmwareUpdateState.success({required String newVersion}) =
      FirmwareUpdateStateSuccess;

  /// Error occurred during update
  const factory FirmwareUpdateState.error({
    required String message,

    /// Type of error that occurred
    @Default(FirmwareErrorType.general) FirmwareErrorType errorType,

    /// The stage at which the error occurred (if during flash process)
    @Default(null) FlashStage? failedStage,

    /// Path to the firmware file (for retry operations)
    @Default(null) String? firmwarePath,

    /// Target version being installed (for display)
    @Default(null) String? targetVersion,
  }) = FirmwareUpdateStateError;
}
