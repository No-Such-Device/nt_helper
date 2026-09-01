import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/core/routing/routing_service_locator.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';
import 'package:nt_helper/services/zoom_hotkey_service.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/contextual_help_tooltip_scope.dart';
import 'package:nt_helper/ui/template_manager/template_manager_screen.dart';
import 'package:nt_helper/utils/build_config.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';

class DistingApp extends StatefulWidget {
  static const templateManagerRoute = '/template-manager';

  const DistingApp({super.key});

  static Map<String, WidgetBuilder> buildRoutes() {
    return {
      '/': (context) => MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) {
              // Get the AppDatabase instance from the context
              final database = context.read<AppDatabase>();

              // Create DistingCubit and pass the database instance
              final cubit = DistingCubit(database); // Pass database here
              final videoPopupService = VideoPopupWindowService.instance;
              if (videoPopupService.isSupported) {
                unawaited(videoPopupService.registerMainCubit(cubit));
              }
              cubit.initialize(); // Load available devices for manual selection
              return cubit;
            },
          ),
        ],
        child: Material(child: DistingPage()),
      ),
      templateManagerRoute: (context) => const TemplateManagerScreen(),
    };
  }

  @override
  State<DistingApp> createState() => _DistingAppState();
}

class _DistingAppState extends State<DistingApp> {
  late final AppLifecycleListener _lifecycleListener;
  final KeyBindingService _keyBindingService = KeyBindingService();
  StreamSubscription<ZoomHotkeyAction>? _zoomHotkeySubscription;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _onExitRequested,
    );
    _zoomHotkeySubscription = ZoomHotkeyService.instance.stream.listen(
      _handleZoomHotkeyAction,
    );
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Delay slightly to ensure the window is shown and initial rendering attempted
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {}); // Trigger a rebuild to force repaint
          }
        });
      });
    }
  }

  void _handleZoomHotkeyAction(ZoomHotkeyAction action) {
    final settings = SettingsService();
    switch (action) {
      case ZoomHotkeyAction.zoomIn:
        settings.zoomInUi();
        break;
      case ZoomHotkeyAction.zoomOut:
        settings.zoomOutUi();
        break;
      case ZoomHotkeyAction.resetZoom:
        settings.resetUiScale();
        break;
    }
  }

  Future<AppExitResponse> _onExitRequested() async {
    try {
      final db = context.read<AppDatabase>();
      await db.close();
    } catch (_) {}
    try {
      await RoutingServiceLocator.reset();
    } catch (_) {}
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _zoomHotkeySubscription?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    return ValueListenableBuilder<Color>(
      valueListenable: settings.themeSeedColorNotifier,
      builder: (context, seedColor, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(
            seedColor: seedColor,
            brightness: Brightness.light,
          ),
          darkTheme: AppTheme.build(
            seedColor: seedColor,
            brightness: Brightness.dark,
          ),
          highContrastTheme: AppTheme.build(
            seedColor: seedColor,
            brightness: Brightness.light,
            contrastLevel: 1,
          ),
          highContrastDarkTheme: AppTheme.build(
            seedColor: seedColor,
            brightness: Brightness.dark,
            contrastLevel: 1,
          ),
          themeMode: ThemeMode.system,
          builder: (context, child) {
            return ValueListenableBuilder<double>(
              valueListenable: settings.uiScaleNotifier,
              builder: (context, scale, _) {
                final mediaQuery = MediaQuery.of(context);
                return ContextualHelpTooltipScope(
                  child: MediaQuery(
                    data: mediaQuery.copyWith(
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Shortcuts(
                      shortcuts: _keyBindingService.desktopZoomShortcuts,
                      child: Actions(
                        actions: _keyBindingService.buildZoomActions(
                          onZoomIn: settings.zoomInUi,
                          onZoomOut: settings.zoomOutUi,
                          onResetZoom: settings.resetUiScale,
                        ),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          initialRoute: '/',
          routes: DistingApp.buildRoutes(),
        );
      },
    );
  }
}

class DistingPage extends StatefulWidget {
  const DistingPage({super.key});

  @override
  State<DistingPage> createState() => _DistingPageState();
}

class _DistingPageState extends State<DistingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final distingCubit = context.read<DistingCubit>();
          McpServerService.initialize(distingCubit: distingCubit);
          final settings = SettingsService();
          if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
              settings.mcpEnabled) {
            if (!McpServerService.instance.isRunning) {
              final bindAddress = settings.mcpRemoteConnections
                  ? InternetAddress.anyIPv4
                  : InternetAddress.loopbackIPv4;
              await McpServerService.instance
                  .start(bindAddress: bindAddress)
                  .catchError((e) {});
            } else {}
          } else {}
        } catch (e) {
          // Intentionally empty
        }
      }
    });
  }

  Future<void> _handleSettingsDialog(BuildContext context) async {
    final settings = SettingsService();
    final mcpInstance = McpServerService.instance;

    settings.mcpEnabled;
    mcpInstance.isRunning;

    // Get the midi manager and algorithms for RTT stats if connected
    IDistingMidiManager? midiManager;
    List<AlgorithmInfo>? algorithms;
    Map<String, dynamic>? ccDiag;
    try {
      final cubit = context.read<DistingCubit>();
      final state = cubit.state;
      if (state is DistingStateSynchronized && !state.offline) {
        midiManager = cubit.requireDisting();
        algorithms = state.algorithms;
      }
      ccDiag = cubit.ccNotificationDiagnostics;
    } catch (_) {
      // Cubit not available
    }

    final result = await context.showSettingsDialog(
      midiManager: midiManager,
      algorithms: algorithms,
      ccNotificationDiagnostics: ccDiag,
    );

    if (result == true) {
      // Settings were saved
      final bool isMcpEnabledAfterDialog = settings.mcpEnabled;
      final bool isServerStillRunningBeforeAction = mcpInstance
          .isRunning; // Check state *before* explicitly starting/stopping

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final bindAddress = settings.mcpRemoteConnections
            ? InternetAddress.anyIPv4
            : InternetAddress.loopbackIPv4;
        if (isMcpEnabledAfterDialog) {
          if (!isServerStillRunningBeforeAction) {
            await mcpInstance
                .start(bindAddress: bindAddress)
                .catchError((e) {});
          } else {
            // Server already running — restart if bind address changed
            if (mcpInstance.boundAddress?.address != bindAddress.address) {
              await mcpInstance
                  .restart(bindAddress: bindAddress)
                  .catchError((e) {});
            }
          }
        } else {
          // MCP Setting is OFF
          if (isServerStillRunningBeforeAction) {
            await mcpInstance.stop().catchError((e) {});
          }
        }
      }
    } else {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocProvider(
        create: (context) => MidiListenerCubit(),
        child: BlocBuilder<DistingCubit, DistingState>(
          builder: (context, state) {
            if (state is DistingStateInitial) {
              return Center(
                child: Semantics(
                  hint: 'Scan for connected MIDI devices',
                  child: ElevatedButton(
                    onPressed: () {
                      context.read<DistingCubit>().loadDevices();
                    },
                    child: Text("Load Devices"),
                  ),
                ),
              );
            } else if (state is DistingStateSelectDevice) {
              return _DeviceSelectionView(
                inputDevices: state.inputDevices,
                outputDevices: state.outputDevices,
                selectedInputDevice: state.selectedInputDevice,
                selectedOutputDevice: state.selectedOutputDevice,
                selectedSysExId: state.selectedSysExId,
                onSelectionChanged: (inputDevice, outputDevice, sysExId) {
                  context.read<DistingCubit>().updateDeviceSelection(
                    inputDevice: inputDevice,
                    outputDevice: outputDevice,
                    sysExId: sysExId,
                  );
                },
                onDeviceSelected: (inputDevice, outputDevice, sysExId) {
                  context.read<DistingCubit>().connectToDevices(
                    inputDevice,
                    outputDevice,
                    sysExId,
                  );
                },
                onRefresh: () {
                  context.read<DistingCubit>().loadDevices();
                },
                onSettingsPressed: () async {
                  await _handleSettingsDialog(context);
                },
                onDemoPressed: () async {
                  context.read<DistingCubit>().onDemo();
                },
                onOfflinePressed: () async {
                  context.read<DistingCubit>().goOffline();
                },
                onFirmwarePressed:
                    !kPlayStoreBuild &&
                        (Platform.isMacOS ||
                            Platform.isWindows ||
                            Platform.isLinux)
                    ? (
                        String? probedVersion,
                        MidiDevice? inputDevice,
                        MidiDevice? outputDevice,
                        int? sysExId,
                      ) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FirmwareUpdateScreen(
                              distingCubit: context.read<DistingCubit>(),
                              currentVersionOverride: probedVersion,
                              inputDevice: inputDevice,
                              outputDevice: outputDevice,
                              sysExId: sysExId,
                            ),
                          ),
                        );
                      }
                    : null,
                canWorkOffline: state.canWorkOffline,
              );
            } else if (state is DistingStateConnected) {
              final isTimeout =
                  state.syncStatus?.contains('timed out') ?? false;
              return Center(
                child: SingleChildScrollView(
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isTimeout
                              ? "Synchronization Failed"
                              : "Synchronizing...",
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (state.syncStatus != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              state.syncStatus!,
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: isTimeout
                              ? Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : CircularProgressIndicator(
                                  value: state.syncProgress,
                                  semanticsLabel:
                                      state.syncStatus ??
                                      'Synchronizing with Disting NT',
                                ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            context.read<DistingCubit>().cancelSync();
                          },
                          child: Text(isTimeout ? "Back" : "Cancel"),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            } else if (state is DistingStateSynchronized) {
              return SynchronizedScreen(
                slots: state.slots,
                algorithms: state.algorithms,
                units: state.unitStrings,
                distingVersion: state.distingVersion,
                presetName: state.presetName,
                isDirty: state.isDirty,
                screenshot: state.screenshot,
                loading: state.loading,
                firmwareVersion: state.firmwareVersion,
              );
            } else {
              // Simple fallback - just restart the device selection
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  context.read<DistingCubit>().loadDevices();
                }
              });
              return const Center(child: CircularProgressIndicator());
            }
          },
        ),
      ),
    );
  }
}

class _DeviceSelectionView extends StatelessWidget {
  final List<MidiDevice> inputDevices;
  final List<MidiDevice> outputDevices;
  final MidiDevice? selectedInputDevice;
  final MidiDevice? selectedOutputDevice;
  final int selectedSysExId;
  final void Function(MidiDevice?, MidiDevice?, int) onSelectionChanged;
  final void Function(MidiDevice, MidiDevice, int) onDeviceSelected;
  final VoidCallback onRefresh;
  final VoidCallback onSettingsPressed;
  final VoidCallback onDemoPressed;
  final VoidCallback onOfflinePressed;
  final void Function(
    String? probedVersion,
    MidiDevice? inputDevice,
    MidiDevice? outputDevice,
    int? sysExId,
  )?
  onFirmwarePressed;
  final bool canWorkOffline;

  const _DeviceSelectionView({
    required this.inputDevices,
    required this.outputDevices,
    required this.selectedInputDevice,
    required this.selectedOutputDevice,
    required this.selectedSysExId,
    required this.onSelectionChanged,
    required this.onDeviceSelected,
    required this.onRefresh,
    required this.onSettingsPressed,
    required this.onDemoPressed,
    required this.onOfflinePressed,
    this.onFirmwarePressed,
    required this.canWorkOffline,
  });

  MidiDevice? _deviceWithId(List<MidiDevice> devices, String? id) => id == null
      ? null
      : devices.where((device) => device.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentInputDevice = _deviceWithId(
      inputDevices,
      selectedInputDevice?.id,
    );
    final currentOutputDevice = _deviceWithId(
      outputDevices,
      selectedOutputDevice?.id,
    );
    final canConnect =
        currentInputDevice != null && currentOutputDevice != null;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Select MIDI input and output ports, then connect.',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.settings,
                        semanticLabel: 'Settings',
                      ),
                      tooltip: 'Settings',
                      onPressed: onSettingsPressed,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    DropdownMenu<String>(
                      key: const ValueKey('input-midi-device-dropdown'),
                      width: 250,
                      initialSelection: currentInputDevice?.id,
                      enabled: true,
                      label: const Text('Input MIDI Device'),
                      dropdownMenuEntries: inputDevices.map((device) {
                        return DropdownMenuEntry<String>(
                          value: device.id,
                          label: device.name,
                        );
                      }).toList(),
                      onSelected: (id) {
                        onSelectionChanged(
                          _deviceWithId(inputDevices, id),
                          currentOutputDevice,
                          selectedSysExId,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        semanticLabel: 'Refresh devices',
                      ),
                      tooltip: 'Refresh devices',
                      onPressed: onRefresh,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownMenu<String>(
                  key: const ValueKey('output-midi-device-dropdown'),
                  width: 250,
                  initialSelection: currentOutputDevice?.id,
                  enabled: true,
                  label: const Text('Output MIDI Device'),
                  dropdownMenuEntries: outputDevices.map((device) {
                    return DropdownMenuEntry<String>(
                      value: device.id,
                      label: device.name,
                    );
                  }).toList(),
                  onSelected: (id) {
                    onSelectionChanged(
                      currentInputDevice,
                      _deviceWithId(outputDevices, id),
                      selectedSysExId,
                    );
                  },
                ),
                const SizedBox(height: 16),
                DropdownMenu<int>(
                  width: 250,
                  initialSelection: selectedSysExId,
                  label: const Text("Device ID"),
                  dropdownMenuEntries: List.generate(128, (index) {
                    return DropdownMenuEntry<int>(
                      value: index,
                      label: index.toString(),
                    );
                  }),
                  onSelected: (id) {
                    if (id == null) return;
                    onSelectionChanged(
                      currentInputDevice,
                      currentOutputDevice,
                      id,
                    );
                  },
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Connect'),
                      onPressed: canConnect
                          ? () => onDeviceSelected(
                              currentInputDevice,
                              currentOutputDevice,
                              selectedSysExId,
                            )
                          : null,
                    ),
                    if (onFirmwarePressed != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.system_update),
                        label: const Text('Firmware'),
                        onPressed: canConnect
                            ? () => onFirmwarePressed?.call(
                                null,
                                currentInputDevice,
                                currentOutputDevice,
                                selectedSysExId,
                              )
                            : null,
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_off),
                      label: const Text('Offline'),
                      onPressed: canWorkOffline ? onOfflinePressed : null,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    "No Disting? Try the demo:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  hint:
                      'Try the app with simulated algorithms, no hardware needed',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: onDemoPressed,
                    label: const Text('Demo Mode'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
