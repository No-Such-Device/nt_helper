import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/ui/firmware/firmware_error_widget.dart';
import 'package:nt_helper/ui/firmware/firmware_flow_diagram.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

const String _kLastFirmwareDirectoryKey = 'last_firmware_directory';

typedef LocalFirmwareFilePicker = Future<String?> Function();

/// Injectable firmware I/O boundary.
///
/// Production callers omit this and retain the platform service defaults.
class FirmwareUpdateScreenDependencies {
  final FirmwareVersionService firmwareVersionService;
  final FlashToolManager flashToolManager;
  final FlashToolBridge flashToolBridge;
  final LocalFirmwareFilePicker? pickLocalFirmwareFile;
  final LocalFirmwareFileReader? readLocalFirmwareFile;

  const FirmwareUpdateScreenDependencies({
    required this.firmwareVersionService,
    required this.flashToolManager,
    required this.flashToolBridge,
    this.pickLocalFirmwareFile,
    this.readLocalFirmwareFile,
  });
}

/// Screen for managing firmware updates on desktop platforms
class FirmwareUpdateScreen extends StatelessWidget {
  final DistingCubit distingCubit;
  final String? currentVersionOverride;
  final MidiDevice? inputDevice;
  final MidiDevice? outputDevice;
  final int? sysExId;

  @visibleForTesting
  final FirmwareUpdateScreenDependencies? dependencies;

  const FirmwareUpdateScreen({
    super.key,
    required this.distingCubit,
    this.currentVersionOverride,
    this.inputDevice,
    this.outputDevice,
    this.sysExId,
    this.dependencies,
  });

  @override
  Widget build(BuildContext context) {
    // Check platform - only available on desktop
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return Scaffold(
        appBar: AppBar(title: const Text('Firmware Update')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Text(
              'Firmware updates are only available on desktop platforms (macOS, Windows, Linux).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Get current state info
    final distingState = distingCubit.state;
    final syncState = distingState is DistingStateSynchronized
        ? distingState
        : null;
    final currentVersion =
        currentVersionOverride ??
        syncState?.firmwareVersion.versionString ??
        'Unknown';
    final isDemo = syncState?.demo ?? false;
    final isOffline = syncState?.offline ?? false;

    // Create services unless focused tests supplied controlled I/O boundaries.
    final firmwareVersionService =
        dependencies?.firmwareVersionService ?? FirmwareVersionService();
    final flashToolManager =
        dependencies?.flashToolManager ?? FlashToolManager();
    final flashToolBridge =
        dependencies?.flashToolBridge ??
        FlashToolBridge(toolManager: flashToolManager);

    final firmwareVersion = currentVersionOverride != null
        ? FirmwareVersion(currentVersionOverride!)
        : syncState?.firmwareVersion;

    final hasDeviceInfo =
        inputDevice != null && outputDevice != null && sysExId != null;
    final selectedInputDevice = inputDevice ?? syncState?.inputDevice;
    final selectedOutputDevice = outputDevice ?? syncState?.outputDevice;
    final hasSelectedDevices =
        selectedInputDevice != null && selectedOutputDevice != null;

    return BlocProvider.value(
      value: distingCubit,
      child: BlocProvider(
        create: (context) => FirmwareUpdateCubit(
          firmwareVersionService: firmwareVersionService,
          flashToolManager: flashToolManager,
          flashToolBridge: flashToolBridge,
          currentVersion: currentVersion,
          isDemo: isDemo,
          isOffline: isOffline,
          firmwareVersion: firmwareVersion,
          midiManager: syncState != null ? distingCubit.disting() : null,
          createMidiManager: hasDeviceInfo
              ? () => distingCubit.createFirmwareMidiManager(
                  inputDevice!,
                  outputDevice!,
                  sysExId!,
                )
              : null,
          disposeMidiManager: hasSelectedDevices
              ? (manager) => distingCubit.disposeFirmwareMidiManager(
                  manager,
                  selectedInputDevice,
                  selectedOutputDevice,
                )
              : null,
          checkMidiDevices: () => distingCubit.firmwareMidiDevicesAvailable(
            selectedInputDevice?.name,
            selectedOutputDevice?.name,
          ),
          readLocalFirmwareFile: dependencies?.readLocalFirmwareFile,
        )..loadAvailableVersions(),
        child: _FirmwareUpdateView(
          pickLocalFirmwareFile: dependencies?.pickLocalFirmwareFile,
        ),
      ),
    );
  }
}

class _FirmwareUpdateView extends StatelessWidget {
  final LocalFirmwareFilePicker? pickLocalFirmwareFile;

  const _FirmwareUpdateView({this.pickLocalFirmwareFile});

  @override
  Widget build(BuildContext context) {
    return FirmwareUpdateCompletionListener(
      child: FirmwareUpdateAnnouncementListener(
        child: _FirmwareUpdateScaffold(
          pickLocalFirmwareFile: pickLocalFirmwareFile,
        ),
      ),
    );
  }
}

/// Refreshes device selection and closes the firmware route after the NT's
/// input and output endpoints have both returned.
class FirmwareUpdateCompletionListener extends StatelessWidget {
  final Widget child;
  final FirmwareUpdateCubit? bloc;

  const FirmwareUpdateCompletionListener({
    super.key,
    required this.child,
    this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<FirmwareUpdateCubit, FirmwareUpdateState>(
      bloc: bloc,
      listenWhen: (previous, current) =>
          previous is! FirmwareUpdateStateSuccess &&
          current is FirmwareUpdateStateSuccess,
      listener: (context, state) async {
        await context.read<DistingCubit>().onFirmwareUpdateComplete();
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: child,
    );
  }
}

class FirmwareUpdateAnnouncementListener extends StatelessWidget {
  final Widget child;
  final FirmwareUpdateCubit? bloc;

  const FirmwareUpdateAnnouncementListener({
    super.key,
    required this.child,
    this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    return BlocListener<FirmwareUpdateCubit, FirmwareUpdateState>(
      bloc: bloc,
      listener: (context, state) {
        if (state is FirmwareUpdateStateDownloading) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Downloading firmware: ${(state.progress * 100).toInt()}%',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateFlashing) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Flashing firmware: ${state.progress.percent}%',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateSuccess) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Firmware update complete',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateError) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Firmware update error: ${state.message}',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateEnteringBootloader) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Entering bootloader mode',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateWaitingForBootloader) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Waiting for bootloader mode',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateVerifyingMidi) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Waiting for Disting NT to return to MIDI',
            TextDirection.ltr,
          );
        } else if (state is FirmwareUpdateStateMidiRecoveryRequired) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Firmware installation completed, but the Disting NT did not return to MIDI',
            TextDirection.ltr,
          );
        }
      },
      child: child,
    );
  }
}

class _FirmwareUpdateScaffold extends StatelessWidget {
  final LocalFirmwareFilePicker? pickLocalFirmwareFile;

  const _FirmwareUpdateScaffold({this.pickLocalFirmwareFile});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FirmwareUpdateCubit, FirmwareUpdateState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Firmware Update'),
            leading: _buildBackButton(context, state),
            actions: _buildAppBarActions(context, state),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: FirmwareUpdateStateContent(state: state),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget>? _buildAppBarActions(
    BuildContext context,
    FirmwareUpdateState state,
  ) {
    // Only show local file action on initial state
    if (state is FirmwareUpdateStateInitial) {
      return [
        TextButton.icon(
          onPressed: () => _selectLocalFile(context),
          icon: const Icon(Icons.folder_open),
          label: const Text('Local Zip File'),
        ),
        const SizedBox(width: 8),
      ];
    }
    return null;
  }

  Widget? _buildBackButton(BuildContext context, FirmwareUpdateState state) {
    // Do not interrupt bootloader entry, flashing, or the automatic return
    // check. Recovery help remains dismissible after the check times out.
    if (state is FirmwareUpdateStateEnteringBootloader ||
        state is FirmwareUpdateStateFlashing ||
        state is FirmwareUpdateStateVerifyingMidi) {
      return IconButton(
        icon: const Icon(
          Icons.arrow_back,
          semanticLabel: 'Cannot exit during firmware update',
        ),
        onPressed: null,
        tooltip: 'Cannot exit during firmware update',
      );
    }
    return null; // Use default back button
  }

  Future<void> _selectLocalFile(BuildContext context) async {
    final cubit = context.read<FirmwareUpdateCubit>();
    final injectedPicker = pickLocalFirmwareFile;
    if (injectedPicker != null) {
      final filePath = await injectedPicker();
      if (filePath != null) {
        await cubit.useLocalFile(filePath);
      }
      return;
    }

    // Get last used directory
    final prefs = await SharedPreferences.getInstance();
    final lastDirectory = prefs.getString(_kLastFirmwareDirectoryKey);

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Select Firmware Package',
      initialDirectory: lastDirectory,
    );

    final filePath = file?.path;
    if (filePath != null) {
      // Save the directory for next time
      final directory = path.dirname(filePath);
      await prefs.setString(_kLastFirmwareDirectoryKey, directory);

      await cubit.useLocalFile(filePath);
    }
  }
}

/// Shared firmware state body, exposed for focused widget and accessibility
/// testing without constructing platform flash services.
class FirmwareUpdateStateContent extends StatelessWidget {
  final FirmwareUpdateState state;

  const FirmwareUpdateStateContent({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return state.map(
      initial: (s) => _InitialStateView(state: s),
      downloading: (s) => _DownloadingStateView(state: s),
      waitingForBootloader: (s) => _BootloaderInstructionsView(state: s),
      enteringBootloader: (s) => _EnteringBootloaderView(state: s),
      flashing: (s) => _FlashingStateView(state: s),
      verifyingMidi: (s) => _VerifyingMidiView(state: s),
      midiRecoveryRequired: (s) => _MidiRecoveryView(state: s),
      success: (_) => const SizedBox.shrink(),
      error: (s) => _ErrorView(state: s),
    );
  }
}

/// Initial state - shows current and available versions
class _InitialStateView extends StatelessWidget {
  final FirmwareUpdateStateInitial state;

  const _InitialStateView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current version - pinned at top
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.memory, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Firmware',
                        style: theme.textTheme.labelMedium,
                      ),
                      Text(
                        state.currentVersion.startsWith('v')
                            ? state.currentVersion
                            : 'v${state.currentVersion}',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Available versions section header
        Text('Available Firmware', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        // Scrollable content
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Content based on state
                  _buildVersionsContent(context, theme, cubit, state),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVersionsContent(
    BuildContext context,
    ThemeData theme,
    FirmwareUpdateCubit cubit,
    FirmwareUpdateStateInitial state,
  ) {
    // Loading state
    if (state.isLoadingVersions) {
      return Column(
        children: [
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            'Checking for updates...',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    // Error state – show a quiet empty state with retry
    if (state.fetchError != null) {
      return Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Could not load available firmware versions.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => cubit.loadAvailableVersions(),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    // Available versions
    if (state.availableVersions != null) {
      if (state.availableVersions!.isEmpty) {
        return Text(
          'No firmware versions found.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildVersionCards(context, state.availableVersions!),
      );
    }

    // No data yet
    return const SizedBox.shrink();
  }

  List<Widget> _buildVersionCards(
    BuildContext context,
    List<FirmwareRelease> versions,
  ) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);

    return [
      Table(
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(),
          2: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (int i = 0; i < versions.length && i < 5; i++)
            _buildVersionRow(context, theme, cubit, versions[i], i == 0),
        ],
      ),
    ];
  }

  TableRow _buildVersionRow(
    BuildContext context,
    ThemeData theme,
    FirmwareUpdateCubit cubit,
    FirmwareRelease version,
    bool isLatest,
  ) {
    return TableRow(
      children: [
        // Column 1: Version number
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'v${version.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(
                height: 14,
                child: isLatest
                    ? Text(
                        'Latest',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        // Column 2: Changelog
        Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 12),
          child: version.changelog.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: version.changelog
                      .take(3)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                )
              : const SizedBox.shrink(),
        ),
        // Column 3: Install button
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton(
            onPressed: () => cubit.startUpdate(version),
            child: const Text('Install'),
          ),
        ),
      ],
    );
  }
}

/// Downloading state - shows download progress
class _DownloadingStateView extends StatelessWidget {
  final FirmwareUpdateStateDownloading state;

  const _DownloadingStateView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.download, size: 64),
        const SizedBox(height: 24),
        Text('Downloading Firmware', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('v${state.version.version}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 32),
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 8),
        Text('${(state.progress * 100).toInt()}%'),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: () => cubit.cancel(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Bootloader instructions - guides user to enter bootloader mode
class _BootloaderInstructionsView extends StatelessWidget {
  final FirmwareUpdateStateWaitingForBootloader state;

  const _BootloaderInstructionsView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.info_outline, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            state.canAutoEnter ? 'Ready to Update' : 'Enter Bootloader Mode',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            state.canAutoEnter
                ? 'Your Disting NT will be rebooted into bootloader mode '
                      'automatically and the firmware will be flashed.'
                : 'Follow these steps on your Disting NT:',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          if (!state.canAutoEnter) ...[
            // Manual bootloader steps
            _buildStep(
              context,
              number: 1,
              title: 'Enter Bootloader Mode',
              description: 'Menu > Misc > Enter bootloader mode, then confirm',
            ),
            const SizedBox(height: 16),
            _buildStep(
              context,
              number: 2,
              title: 'Screen Shows Message',
              description: 'The display shows "Entering serial downloader"',
            ),
            const SizedBox(height: 16),
            _buildStep(
              context,
              number: 3,
              title: 'Ready to Flash',
              description: 'Click the button below when ready',
            ),
            const SizedBox(height: 32),
          ],

          if (state.canAutoEnter) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'The module will be unavailable during the update. '
                        'Do not disconnect USB or power until the update is '
                        'complete.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],

          FilledButton.icon(
            onPressed: () => cubit.confirmAndFlash(),
            icon: const Icon(Icons.flash_on),
            label: Text(
              state.canAutoEnter
                  ? 'Update Firmware'
                  : "I'm in bootloader mode - Flash Now",
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: () => cubit.cancel(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required int number,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: Text('$number'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entering bootloader state - auto-entering via SysEx
class _EnteringBootloaderView extends StatelessWidget {
  final FirmwareUpdateStateEnteringBootloader state;

  const _EnteringBootloaderView({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondsLeft = ((1.0 - state.progress) * 5).ceil().clamp(0, 5);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.restart_alt, size: 64),
        const SizedBox(height: 24),
        Text('Entering Bootloader Mode', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          state.progress == 0
              ? 'Sending command to device...'
              : 'Waiting for device to switch ($secondsLeft s)',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(value: state.progress),
      ],
    );
  }
}

/// Flashing state - shows progress with animated diagram
class _FlashingStateView extends StatelessWidget {
  final FirmwareUpdateStateFlashing state;

  const _FlashingStateView({required this.state});

  /// Maps per-stage percent (0-100) into an overall percent (0-100)
  /// so the progress bar always moves forward.
  int _overallPercent(FlashProgress progress) {
    // Stage weight ranges (start%, end%) within overall progress.
    // Actual tool order: sdpConnect → blCheck → sdpUpload → configure → write → reset → complete
    const stageRanges = {
      FlashStage.sdpConnect: (0, 5),
      FlashStage.blCheck: (5, 10),
      FlashStage.sdpUpload: (10, 40),
      FlashStage.configure: (40, 50),
      FlashStage.write: (50, 95),
      FlashStage.reset: (95, 100),
      FlashStage.complete: (100, 100),
    };
    final (start, end) = stageRanges[progress.stage] ?? (0, 100);
    return (start + (end - start) * progress.percent / 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);
    final overall = _overallPercent(state.progress);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Animated flow diagram
        SizedBox(
          height: 150,
          child: FirmwareFlowDiagram(progress: state.progress),
        ),
        const SizedBox(height: 32),

        // Stage label
        Text(
          _getStageLabel(state.progress.stage.name),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: state.progress.message.isNotEmpty
              ? Text(
                  state.progress.message,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              : null,
        ),
        const SizedBox(height: 24),

        // Progress bar
        LinearProgressIndicator(value: overall / 100),
        const SizedBox(height: 8),
        Text('$overall%'),

        const SizedBox(height: 32),

        // Cancel button with confirmation
        OutlinedButton(
          onPressed: () => _confirmCancel(context, cubit),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _getStageLabel(String stage) {
    switch (stage) {
      case 'sdpConnect':
        return 'Connecting to bootloader...';
      case 'blCheck':
        return 'Checking bootloader...';
      case 'sdpUpload':
        return 'Uploading firmware...';
      case 'write':
        return 'Writing firmware...';
      case 'configure':
        return 'Configuring device...';
      case 'reset':
        return 'Resetting device...';
      case 'complete':
        return 'Completing...';
      default:
        return stage;
    }
  }

  Future<void> _confirmCancel(
    BuildContext context,
    FirmwareUpdateCubit cubit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Firmware Update?'),
        content: const Text(
          'Canceling during a firmware update may leave your device in an '
          'unusable state. Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue Update'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel Update'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      cubit.cancel();
    }
  }
}

class _VerifyingMidiView extends StatelessWidget {
  final FirmwareUpdateStateVerifyingMidi state;

  const _VerifyingMidiView({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(),
        ),
        const SizedBox(height: 24),
        Text('Waiting for Disting NT', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Firmware installation completed successfully. Waiting for the NT '
          'MIDI input and output to return.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Check ${state.completedAttempts + 1} of ${state.totalAttempts}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MidiRecoveryView extends StatelessWidget {
  static const restartMidiServiceCommand = 'Restart-Service MidiSrv';

  final FirmwareUpdateStateMidiRecoveryRequired state;

  const _MidiRecoveryView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.usb_off,
            size: 72,
            color: theme.colorScheme.error,
            semanticLabel: 'Disting NT MIDI connection not found',
          ),
          const SizedBox(height: 20),
          Text(
            'Firmware Installed',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'The firmware update completed successfully, but the Disting NT '
            'did not return to MIDI within one minute.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (state.isWindows)
            _buildWindowsRecovery(context, theme)
          else
            const Text(
              'Check the NT\'s USB connection and power, then power-cycle the '
              'NT. If it still does not appear, restart the computer.',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => cubit.checkMidiAgain(),
            icon: const Icon(Icons.refresh),
            label: const Text('Check Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowsRecovery(BuildContext context, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Windows MIDI service recovery',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'The Windows MIDI service may be stuck. Open PowerShell as '
              'Administrator and run:',
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'PowerShell command: $restartMidiServiceCommand',
              child: SelectableText(
                restartMidiServiceCommand,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: restartMidiServiceCommand),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PowerShell command copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy Command'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Then choose Check Again. Restart Windows if the NT still does '
              'not return.',
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state - shows error message with contextual actions
class _ErrorView extends StatelessWidget {
  final FirmwareUpdateStateError state;

  const _ErrorView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FirmwareUpdateCubit>();

    return FirmwareErrorWidget(
      state: state,
      onReturnToBootloader: () => cubit.returnToBootloaderInstructions(),
      onRetryFlash: () => cubit.retryFlash(),
      onTryAgain: () => cubit.cleanupAndReset(),
      onInstallUdevRules: () => cubit.installUdevRules(),
      onGetDiagnostics: () => cubit.getDiagnostics(),
    );
  }
}
