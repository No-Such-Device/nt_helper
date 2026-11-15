import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/ntx_8cv_connection_cubit.dart';
import 'package:nt_helper/cubit/ntx_8cv_settings_cubit.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_midi_connection.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/utils/responsive.dart';

/// The primary page for configuring a separately connected NTX-8CV.
class Ntx8cvScreen extends StatefulWidget {
  const Ntx8cvScreen({super.key, this.connectionCubit});

  /// Supplying a connection cubit is useful for embedding and automated tests.
  final Ntx8cvConnectionCubit? connectionCubit;

  @override
  State<Ntx8cvScreen> createState() => _Ntx8cvScreenState();
}

class _Ntx8cvScreenState extends State<Ntx8cvScreen> {
  late final Ntx8cvConnectionCubit _connectionCubit;
  late final Ntx8cvSettingsCubit _settingsCubit;
  late final bool _ownsConnectionCubit;
  final TextEditingController _deviceIdController = TextEditingController(
    text: '0',
  );

  @override
  void initState() {
    super.initState();
    _ownsConnectionCubit = widget.connectionCubit == null;
    _connectionCubit = widget.connectionCubit ?? Ntx8cvConnectionCubit();
    _settingsCubit = Ntx8cvSettingsCubit(connectionCubit: _connectionCubit);
    unawaited(_connectionCubit.initialize());
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    unawaited(_settingsCubit.close());
    if (_ownsConnectionCubit) {
      unawaited(_connectionCubit.close());
    }
    super.dispose();
  }

  void _syncDeviceIdText(Ntx8cvConnectionState state) {
    if (_deviceIdController.text == state.deviceIdText) return;
    _deviceIdController.value = TextEditingValue(
      text: state.deviceIdText,
      selection: TextSelection.collapsed(offset: state.deviceIdText.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = Responsive.isMobile(context);
    final theme = Theme.of(context);

    return BlocListener<Ntx8cvConnectionCubit, Ntx8cvConnectionState>(
      bloc: _connectionCubit,
      listenWhen: (previous, current) =>
          previous.deviceIdText != current.deviceIdText,
      listener: (_, state) => _syncDeviceIdText(state),
      child: Scaffold(
        appBar: AppBar(title: const Text('NTX-8CV')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding: Responsive.getScreenPadding(context),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _Ntx8cvSyncIndicator(
                            connectionCubit: _connectionCubit,
                            settingsCubit: _settingsCubit,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text(
                                'NTX-8CV',
                                style: theme.textTheme.headlineMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Configure the NTX-8CV over its dedicated USB MIDI '
                        'connection.',
                      ),
                      const SizedBox(height: 24),
                      BlocBuilder<Ntx8cvConnectionCubit, Ntx8cvConnectionState>(
                        bloc: _connectionCubit,
                        buildWhen: _connectionPresentationChanged,
                        builder: (context, state) => _ConnectionSection(
                          isNarrow: isNarrow,
                          state: state,
                          deviceIdController: _deviceIdController,
                          onRefresh: _connectionCubit.refreshEndpoints,
                          onInputChanged: (device) {
                            unawaited(
                              _connectionCubit.selectInputDevice(device),
                            );
                          },
                          onOutputChanged: (device) {
                            unawaited(
                              _connectionCubit.selectOutputDevice(device),
                            );
                          },
                          onDeviceIdChanged: (value) {
                            unawaited(_connectionCubit.setDeviceIdText(value));
                          },
                          onConnect: _connectionCubit.connect,
                          onDisconnect: _connectionCubit.disconnect,
                        ),
                      ),
                      const SizedBox(height: 16),
                      BlocSelector<
                        Ntx8cvConnectionCubit,
                        Ntx8cvConnectionState,
                        bool
                      >(
                        bloc: _connectionCubit,
                        selector: (state) => state.isConnected,
                        builder: (context, isConnected) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BlocBuilder<
                              Ntx8cvSettingsCubit,
                              Ntx8cvSettingsState
                            >(
                              bloc: _settingsCubit,
                              buildWhen: _usbAudioPresentationChanged,
                              builder: (context, settingsState) =>
                                  Ntx8cvUsbAudioSection(
                                    isConnected: isConnected,
                                    state: settingsState,
                                    onUsbHostChanged:
                                        _settingsCubit.setUsbHostEnabled,
                                    onUsbAudioChannelChanged: _settingsCubit
                                        .setUsbAudioChannelEnabled,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            BlocBuilder<
                              Ntx8cvSettingsCubit,
                              Ntx8cvSettingsState
                            >(
                              bloc: _settingsCubit,
                              buildWhen: _expanderSettingsPresentationChanged,
                              builder: (context, settingsState) =>
                                  Ntx8cvSettingsSection(
                                    isConnected: isConnected,
                                    state: settingsState,
                                    onChannelGroupChanged:
                                        _settingsCubit.setChannelGroup,
                                    onRetryChannelGroupChange:
                                        _settingsCubit.retryChannelGroupChange,
                                    onEs5Changed: _settingsCubit.setEs5Enabled,
                                    onRetryEs5Change:
                                        _settingsCubit.retryEs5Change,
                                    onModeChanged:
                                        _settingsCubit.setExpansionMode,
                                    onRetryModeChange:
                                        _settingsCubit.retryModeChange,
                                    onExpanderAudioChannelChanged:
                                        _settingsCubit
                                            .setExpanderAudioChannelEnabled,
                                    onReboot: _settingsCubit.reboot,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _usbAudioPresentationChanged(
  Ntx8cvSettingsState previous,
  Ntx8cvSettingsState current,
) =>
    previous.usbHost != current.usbHost ||
    previous.usbAudioChannels != current.usbAudioChannels ||
    previous.isRefreshing != current.isRefreshing ||
    previous.isRebooting != current.isRebooting;

bool _expanderSettingsPresentationChanged(
  Ntx8cvSettingsState previous,
  Ntx8cvSettingsState current,
) =>
    previous.channelGroup != current.channelGroup ||
    previous.es5 != current.es5 ||
    previous.mode != current.mode ||
    previous.expanderAudioChannels != current.expanderAudioChannels ||
    previous.modeCapabilityEvidenced != current.modeCapabilityEvidenced ||
    previous.modeRebootRequired != current.modeRebootRequired ||
    previous.isRefreshing != current.isRefreshing ||
    previous.isRebooting != current.isRebooting ||
    previous.rebootMessage != current.rebootMessage;

bool _connectionPresentationChanged(
  Ntx8cvConnectionState previous,
  Ntx8cvConnectionState current,
) {
  return !_sameEndpointLists(previous.inputDevices, current.inputDevices) ||
      !_sameEndpointLists(previous.outputDevices, current.outputDevices) ||
      previous.selectedInputDevice?.id != current.selectedInputDevice?.id ||
      previous.selectedOutputDevice?.id != current.selectedOutputDevice?.id ||
      previous.deviceIdText != current.deviceIdText ||
      previous.deviceIdError != current.deviceIdError ||
      (!previous.isReacquiringAfterReboot &&
          !current.isReacquiringAfterReboot &&
          previous.status != current.status) ||
      previous.statusLabel != current.statusLabel ||
      previous.isBusy != current.isBusy ||
      previous.canConnect != current.canConnect ||
      previous.isConnected != current.isConnected ||
      (!current.isBusy && previous.statusMessage != current.statusMessage);
}

bool _sameEndpointLists(
  List<Ntx8cvMidiEndpoint> first,
  List<Ntx8cvMidiEndpoint> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    final a = first[index];
    final b = second[index];
    if (a.id != b.id ||
        a.name != b.name ||
        a.hasInput != b.hasInput ||
        a.hasOutput != b.hasOutput) {
      return false;
    }
  }
  return true;
}

class _Ntx8cvSyncIndicator extends StatefulWidget {
  const _Ntx8cvSyncIndicator({
    required this.connectionCubit,
    required this.settingsCubit,
  });

  final Ntx8cvConnectionCubit connectionCubit;
  final Ntx8cvSettingsCubit settingsCubit;

  @override
  State<_Ntx8cvSyncIndicator> createState() => _Ntx8cvSyncIndicatorState();
}

class _Ntx8cvSyncIndicatorState extends State<_Ntx8cvSyncIndicator> {
  static const _visibleAfterSync = Duration(seconds: 2);
  static const _fadeDuration = Duration(milliseconds: 600);

  late final StreamSubscription<Ntx8cvConnectionState> _connectionSubscription;
  late final StreamSubscription<Ntx8cvSettingsState> _settingsSubscription;
  late bool _isSynced;
  double _opacity = 1;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _isSynced = _calculateIsSynced();
    _connectionSubscription = widget.connectionCubit.stream.listen(
      (_) => _updateSyncState(),
    );
    _settingsSubscription = widget.settingsCubit.stream.listen(
      (_) => _updateSyncState(),
    );
    if (_isSynced) _scheduleFade();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    unawaited(_connectionSubscription.cancel());
    unawaited(_settingsSubscription.cancel());
    super.dispose();
  }

  bool _calculateIsSynced() {
    final connection = widget.connectionCubit.state;
    final settings = widget.settingsCubit.state;
    return connection.isConnected &&
        !connection.isBusy &&
        !connection.isLoadingEndpoints &&
        !settings.isBusy &&
        !settings.hasPendingChannelGroupChange &&
        !settings.hasPendingEs5Change &&
        !settings.hasPendingUsbSettingsChange &&
        !settings.hasPendingExpanderAudioChange &&
        !settings.hasPendingModeChange &&
        settings.confirmedChannelGroup != null &&
        settings.confirmedEs5Enabled != null &&
        settings.hasConfirmedUsbSettingsSnapshot &&
        settings.hasConfirmedExpanderAudioSnapshot &&
        settings.confirmedMode != null &&
        settings.modeCapabilityEvidenced &&
        settings.channelGroupMessage == null &&
        settings.es5Message == null &&
        !settings.hasUsbSettingsError &&
        !settings.hasExpanderAudioError &&
        settings.modeMessage == null &&
        settings.rebootMessage == null;
  }

  void _updateSyncState() {
    final nextIsSynced = _calculateIsSynced();
    if (nextIsSynced == _isSynced) return;

    _fadeTimer?.cancel();
    setState(() {
      _isSynced = nextIsSynced;
      _opacity = 1;
    });
    if (nextIsSynced) _scheduleFade();
  }

  void _scheduleFade() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(_visibleAfterSync, () {
      if (!mounted || !_isSynced) return;
      setState(() => _opacity = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = _isSynced
        ? 'NTX-8CV data synced'
        : 'NTX-8CV data not fully synced';
    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 10,
          height: 10,
          child: DecoratedBox(
            key: const Key('ntx8cv-sync-outline'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: 0.7),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AnimatedOpacity(
                key: const Key('ntx8cv-sync-indicator'),
                opacity: _opacity,
                duration: _fadeDuration,
                child: DecoratedBox(
                  key: const Key('ntx8cv-sync-fill'),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isSynced
                        ? context.appColors.info.color
                        : context.appColors.warning.color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Ntx8cvUsbAudioSection extends StatelessWidget {
  const Ntx8cvUsbAudioSection({
    super.key,
    required this.isConnected,
    required this.state,
    required this.onUsbHostChanged,
    required this.onUsbAudioChannelChanged,
  });

  final bool isConnected;
  final Ntx8cvSettingsState state;
  final Future<void> Function(bool) onUsbHostChanged;
  final Future<void> Function(int, bool) onUsbAudioChannelChanged;

  @override
  Widget build(BuildContext context) {
    final isGloballyUnavailable =
        !isConnected || state.isRebooting || state.isRefreshing;
    final displayedUsbHost = state.isWritingUsbHost
        ? state.attemptedUsbHostEnabled ?? state.confirmedUsbHostEnabled
        : state.confirmedUsbHostEnabled;
    final canChangeUsbHost =
        !isGloballyUnavailable &&
        state.confirmedUsbHostEnabled != null &&
        !state.isLoadingUsbHost;

    return Card(
      key: const Key('ntx8cv-usb-audio-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'USB Settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('ntx8cv-usb-host'),
              contentPadding: EdgeInsets.zero,
              title: const Text('USB host'),
              value: displayedUsbHost ?? false,
              onChanged: canChangeUsbHost
                  ? (enabled) {
                      unawaited(onUsbHostChanged(enabled));
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Enable audio channel',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
                  _Ntx8cvAudioChannelCheckbox(
                    index: index,
                    change: state.usbAudioChannels[index],
                    semanticContext: 'USB',
                    keyPrefix: 'ntx8cv-usb-audio-channel',
                    enabled:
                        !isGloballyUnavailable &&
                        state.confirmedUsbAudioChannelEnabled(index) != null &&
                        !state.isLoadingUsbAudioChannel(index),
                    onChanged: (enabled) {
                      unawaited(onUsbAudioChannelChanged(index, enabled));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _StableMessageSlot(
              message: _errorMessage(),
              isError: true,
              height: 20,
            ),
          ],
        ),
      ),
    );
  }

  String? _errorMessage() {
    if (!isConnected || state.isRefreshing) return null;
    if (state.usbHostMessage != null && !state.isWritingUsbHost) {
      return 'USB host setting not confirmed.';
    }
    for (var index = 0; index < kNtx8cvAudioChannelCount; index++) {
      if (state.usbAudioChannelMessage(index) != null &&
          !state.isWritingUsbAudioChannel(index)) {
        return 'USB audio channel ${index + 1} setting not confirmed.';
      }
    }
    if (!state.hasConfirmedUsbSettingsSnapshot) {
      return 'USB audio settings unavailable.';
    }
    return null;
  }
}

class _Ntx8cvAudioChannelCheckbox extends StatelessWidget {
  const _Ntx8cvAudioChannelCheckbox({
    required this.index,
    required this.change,
    required this.semanticContext,
    required this.keyPrefix,
    required this.enabled,
    required this.onChanged,
  });

  final int index;
  final Ntx8cvSettingChange change;
  final String semanticContext;
  final String keyPrefix;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final confirmed = _boolValue(change.confirmedValue);
    final selected = change.isWriting
        ? _boolValue(change.attemptedValue) ?? confirmed ?? false
        : confirmed ?? false;
    final label = '$semanticContext audio channel ${index + 1}';
    return Tooltip(
      message: label,
      child: MergeSemantics(
        child: Semantics(
          label: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  '${index + 1}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Checkbox(
                key: Key('$keyPrefix-${index + 1}'),
                value: selected,
                onChanged: enabled
                    ? (value) {
                        if (value != null) onChanged(value);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool? _boolValue(int? value) => switch (value) {
    0 => false,
    1 => true,
    _ => null,
  };
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({
    required this.isNarrow,
    required this.state,
    required this.deviceIdController,
    required this.onRefresh,
    required this.onInputChanged,
    required this.onOutputChanged,
    required this.onDeviceIdChanged,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isNarrow;
  final Ntx8cvConnectionState state;
  final TextEditingController deviceIdController;
  final Future<void> Function() onRefresh;
  final ValueChanged<Ntx8cvMidiEndpoint?> onInputChanged;
  final ValueChanged<Ntx8cvMidiEndpoint?> onOutputChanged;
  final ValueChanged<String> onDeviceIdChanged;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final controls = _ConnectionControls(
      state: state,
      deviceIdController: deviceIdController,
      onInputChanged: onInputChanged,
      onOutputChanged: onOutputChanged,
      onDeviceIdChanged: onDeviceIdChanged,
      onConnect: onConnect,
      onDisconnect: onDisconnect,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh NTX-8CV MIDI endpoints',
                  onPressed: state.isBusy
                      ? null
                      : () {
                          unawaited(onRefresh());
                        },
                ),
                const SizedBox(width: 4),
                _ConnectionStatusChip(state: state),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Select its MIDI input and output, then connect.'),
            const SizedBox(height: 16),
            if (isNarrow)
              _NarrowConnectionControls(controls: controls)
            else
              _WideConnectionControls(controls: controls),
            const SizedBox(height: 12),
            Row(
              key: const Key('ntx8cv-connection-actions'),
              children: [
                Expanded(child: _ConnectionMessageSlot(state: state)),
                const SizedBox(width: 12),
                controls.button(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(Ntx8cvConnectionStatus status) =>
      switch (status) {
        Ntx8cvConnectionStatus.disconnected => Icons.link_off,
        Ntx8cvConnectionStatus.connecting => Icons.sync,
        Ntx8cvConnectionStatus.connected => Icons.link,
        Ntx8cvConnectionStatus.failed => Icons.error_outline,
      };
}

class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({required this.state});

  final Ntx8cvConnectionState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('ntx8cv-connection-status'),
      liveRegion: true,
      label: 'NTX-8CV connection status: ${state.statusLabel}',
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const ExcludeSemantics(
            child: Opacity(
              opacity: 0,
              child: Chip(
                avatar: Icon(Icons.link_off),
                label: _HiddenLayoutText('Reconnecting'),
              ),
            ),
          ),
          Chip(
            avatar: Icon(
              state.isReacquiringAfterReboot
                  ? Icons.sync
                  : _ConnectionSection._statusIcon(state.status),
            ),
            label: Text(state.statusLabel),
          ),
        ],
      ),
    );
  }
}

class _ConnectionMessageSlot extends StatelessWidget {
  const _ConnectionMessageSlot({required this.state});

  final Ntx8cvConnectionState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state.isBusy || state.isLoadingEndpoints;
    return _StableMessageSlot(
      message: isActive ? null : state.statusMessage,
      isError: state.status == Ntx8cvConnectionStatus.failed,
      height: 20,
    );
  }
}

class _StableMessageSlot extends StatelessWidget {
  const _StableMessageSlot({
    required this.message,
    this.isError = false,
    this.height = 32,
    this.reserveRetrySpace = false,
    this.retryKey,
    this.onRetry,
  });

  final String? message;
  final bool isError;
  final double height;
  final bool reserveRetrySpace;
  final Key? retryKey;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: isError ? Theme.of(context).colorScheme.error : null);
    final messageText = message == null
        ? const SizedBox.shrink()
        : Tooltip(
            message: message,
            child: Semantics(
              liveRegion: true,
              label: message,
              excludeSemantics: true,
              child: Text(
                message!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: messageText),
          ),
          if (reserveRetrySpace || retryKey != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 116,
              child: retryKey == null
                  ? null
                  : OutlinedButton.icon(
                      key: retryKey,
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry send'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HiddenLayoutText extends StatelessWidget {
  const _HiddenLayoutText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => RichText(
    text: TextSpan(style: DefaultTextStyle.of(context).style, text: text),
  );
}

class _WideConnectionControls extends StatelessWidget {
  const _WideConnectionControls({required this.controls});

  final _ConnectionControls controls;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('ntx8cv-connection-controls-wide'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: controls.inputField()),
        const SizedBox(width: 12),
        Expanded(child: controls.outputField()),
        const SizedBox(width: 12),
        Expanded(child: controls.deviceIdField()),
      ],
    );
  }
}

class _NarrowConnectionControls extends StatelessWidget {
  const _NarrowConnectionControls({required this.controls});

  final _ConnectionControls controls;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ntx8cv-connection-controls-narrow'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls.inputField(),
        const SizedBox(height: 12),
        controls.outputField(),
        const SizedBox(height: 12),
        controls.deviceIdField(),
      ],
    );
  }
}

class _ConnectionControls {
  const _ConnectionControls({
    required this.state,
    required this.deviceIdController,
    required this.onInputChanged,
    required this.onOutputChanged,
    required this.onDeviceIdChanged,
    required this.onConnect,
    required this.onDisconnect,
  });

  final Ntx8cvConnectionState state;
  final TextEditingController deviceIdController;
  final ValueChanged<Ntx8cvMidiEndpoint?> onInputChanged;
  final ValueChanged<Ntx8cvMidiEndpoint?> onOutputChanged;
  final ValueChanged<String> onDeviceIdChanged;
  final Future<void> Function() onConnect;
  final Future<void> Function() onDisconnect;

  Widget inputField() => _MidiEndpointField(
    key: const Key('ntx8cv-midi-input'),
    label: 'MIDI input',
    devices: state.inputDevices,
    selectedDevice: state.selectedInputDevice,
    enabled: !state.isBusy,
    onChanged: onInputChanged,
  );

  Widget outputField() => _MidiEndpointField(
    key: const Key('ntx8cv-midi-output'),
    label: 'MIDI output',
    devices: state.outputDevices,
    selectedDevice: state.selectedOutputDevice,
    enabled: !state.isBusy,
    onChanged: onOutputChanged,
  );

  Widget deviceIdField() => TextFormField(
    key: const Key('ntx8cv-device-id'),
    controller: deviceIdController,
    enabled: !state.isBusy,
    keyboardType: TextInputType.number,
    onChanged: onDeviceIdChanged,
    decoration: InputDecoration(
      labelText: 'SysEx device ID',
      helperText: '0–126',
      errorText: state.deviceIdError,
      border: const OutlineInputBorder(),
    ),
  );

  Widget button() {
    if (state.isConnected) {
      return SizedBox(
        width: 140,
        child: FilledButton.icon(
          key: const Key('ntx8cv-connect-button'),
          onPressed: () {
            unawaited(onDisconnect());
          },
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
        ),
      );
    }
    return SizedBox(
      width: 140,
      child: FilledButton.icon(
        key: const Key('ntx8cv-connect-button'),
        onPressed: state.canConnect && !state.isReacquiringAfterReboot
            ? () {
                unawaited(onConnect());
              }
            : null,
        icon: Icon(state.isBusy ? Icons.sync : Icons.link),
        label: const Text('Connect'),
      ),
    );
  }
}

class _MidiEndpointField extends StatelessWidget {
  const _MidiEndpointField({
    super.key,
    required this.label,
    required this.devices,
    required this.selectedDevice,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final List<Ntx8cvMidiEndpoint> devices;
  final Ntx8cvMidiEndpoint? selectedDevice;
  final bool enabled;
  final ValueChanged<Ntx8cvMidiEndpoint?> onChanged;

  @override
  Widget build(BuildContext context) {
    Ntx8cvMidiEndpoint? selectedValue;
    for (final device in devices) {
      if (device.id == selectedDevice?.id) {
        selectedValue = device;
        break;
      }
    }
    return KeyedSubtree(
      key: ValueKey('$label:${selectedValue?.id}'),
      child: DropdownButtonFormField<Ntx8cvMidiEndpoint>(
        key: ValueKey('$label-dropdown'),
        initialValue: selectedValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        hint: const Text('No MIDI endpoint selected'),
        items: [
          for (final device in devices)
            DropdownMenuItem(value: device, child: Text(device.name)),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Displays device-confirmed settings and explicit recovery actions.
class Ntx8cvSettingsSection extends StatelessWidget {
  const Ntx8cvSettingsSection({
    super.key,
    required this.isConnected,
    required this.state,
    required this.onChannelGroupChanged,
    required this.onRetryChannelGroupChange,
    required this.onEs5Changed,
    required this.onRetryEs5Change,
    required this.onModeChanged,
    required this.onRetryModeChange,
    required this.onExpanderAudioChannelChanged,
    required this.onReboot,
  });

  final bool isConnected;
  final Ntx8cvSettingsState state;
  final Future<void> Function(Ntx8cvChannelGroup) onChannelGroupChanged;
  final Future<void> Function() onRetryChannelGroupChange;
  final Future<void> Function(bool) onEs5Changed;
  final Future<void> Function() onRetryEs5Change;
  final Future<void> Function(Ntx8cvExpansionMode) onModeChanged;
  final Future<void> Function() onRetryModeChange;
  final Future<void> Function(int, bool) onExpanderAudioChannelChanged;
  final Future<void> Function() onReboot;

  @override
  Widget build(BuildContext context) {
    final isGloballyUnavailable =
        !isConnected || state.isRebooting || state.isRefreshing;
    final displayedChannelGroup = state.isWritingChannelGroup
        ? state.attemptedChannelGroup ?? state.confirmedChannelGroup
        : state.confirmedChannelGroup;
    final displayedEs5Enabled = state.isWritingEs5
        ? state.attemptedEs5Enabled ?? state.confirmedEs5Enabled
        : state.confirmedEs5Enabled;
    final displayedMode = state.isWritingMode
        ? state.attemptedMode ?? state.confirmedMode
        : state.confirmedMode;
    final canChangeChannelGroup =
        !isGloballyUnavailable &&
        state.confirmedChannelGroup != null &&
        !state.isLoadingChannelGroup &&
        (!state.hasPendingChannelGroupChange || state.isWritingChannelGroup);
    final canChangeEs5 =
        !isGloballyUnavailable &&
        state.confirmedEs5Enabled != null &&
        !state.isLoadingEs5 &&
        (!state.hasPendingEs5Change || state.isWritingEs5);
    final canChangeMode =
        !isGloballyUnavailable &&
        state.confirmedMode != null &&
        state.modeCapabilityEvidenced &&
        !state.isLoadingMode &&
        (!state.hasPendingModeChange || state.isWritingMode);
    final canReboot = isConnected && !state.isBusy;
    final es5Message = _es5Message();
    final modeMessage = _modeMessage();
    final channelGroupMessage = _channelGroupMessage();
    final rebootMessage = state.rebootMessage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'disting NT Expander Settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 4),
            _StableMessageSlot(
              message: rebootMessage,
              isError: rebootMessage != null,
              height: 20,
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable ES-5'),
              value: displayedEs5Enabled ?? false,
              onChanged: canChangeEs5
                  ? (enabled) {
                      unawaited(onEs5Changed(enabled));
                    }
                  : null,
            ),
            _StableMessageSlot(
              message: es5Message,
              reserveRetrySpace: true,
              retryKey: state.hasPendingEs5Change && !state.isWritingEs5
                  ? const Key('ntx8cv-retry-es5-change')
                  : null,
              onRetry:
                  state.hasPendingEs5Change &&
                      !isGloballyUnavailable &&
                      !state.isLoadingEs5 &&
                      !state.isWritingEs5
                  ? () {
                      unawaited(onRetryEs5Change());
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Ntx8cvExpansionMode>(
              key: ValueKey('ntx8cv-expansion-mode-$displayedMode'),
              initialValue: displayedMode,
              decoration: const InputDecoration(
                labelText: 'NT expansion mode',
                border: OutlineInputBorder(),
              ),
              items: Ntx8cvExpansionMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: canChangeMode
                  ? (mode) {
                      if (mode != null) {
                        unawaited(onModeChanged(mode));
                      }
                    }
                  : null,
            ),
            _StableMessageSlot(
              message: modeMessage,
              reserveRetrySpace: true,
              retryKey: state.hasPendingModeChange && !state.isWritingMode
                  ? const Key('ntx8cv-retry-mode-change')
                  : null,
              onRetry:
                  state.hasPendingModeChange &&
                      !isGloballyUnavailable &&
                      state.modeCapabilityEvidenced &&
                      !state.isLoadingMode &&
                      !state.isWritingMode
                  ? () {
                      unawaited(onRetryModeChange());
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Ntx8cvChannelGroup>(
              key: ValueKey('ntx8cv-channel-group-$displayedChannelGroup'),
              initialValue: displayedChannelGroup,
              decoration: const InputDecoration(
                labelText: 'Channel Group',
                border: OutlineInputBorder(),
              ),
              items: Ntx8cvChannelGroup.values
                  .map(
                    (group) => DropdownMenuItem(
                      value: group,
                      child: Text(group.label),
                    ),
                  )
                  .toList(),
              onChanged: canChangeChannelGroup
                  ? (group) {
                      if (group != null) {
                        unawaited(onChannelGroupChanged(group));
                      }
                    }
                  : null,
            ),
            _StableMessageSlot(
              message: channelGroupMessage,
              reserveRetrySpace: true,
              retryKey:
                  state.hasPendingChannelGroupChange &&
                      !state.isWritingChannelGroup
                  ? const Key('ntx8cv-retry-channel-group-change')
                  : null,
              onRetry:
                  state.hasPendingChannelGroupChange &&
                      !isGloballyUnavailable &&
                      !state.isLoadingChannelGroup &&
                      !state.isWritingChannelGroup
                  ? () {
                      unawaited(onRetryChannelGroupChange());
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              'Enable audio channel',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
                  _Ntx8cvAudioChannelCheckbox(
                    index: index,
                    change: state.expanderAudioChannels[index],
                    semanticContext: 'NT expander',
                    keyPrefix: 'ntx8cv-expander-audio-channel',
                    enabled:
                        !isGloballyUnavailable &&
                        state.confirmedExpanderAudioChannelEnabled(index) !=
                            null &&
                        !state.isLoadingExpanderAudioChannel(index),
                    onChanged: (enabled) {
                      unawaited(onExpanderAudioChannelChanged(index, enabled));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _StableMessageSlot(
              message: _expanderAudioMessage(),
              isError: true,
              height: 20,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label:
                    'Reboot only the currently selected, identity-verified '
                    'NTX-8CV',
                child: SizedBox(
                  width: 184,
                  child: FilledButton.icon(
                    key: const Key('ntx8cv-reboot'),
                    onPressed: canReboot
                        ? () {
                            unawaited(onReboot());
                          }
                        : null,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reboot NTX-8CV'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _channelGroupMessage() {
    if (state.hasPendingChannelGroupChange) {
      return state.isWritingChannelGroup
          ? null
          : 'Channel Group change not confirmed.';
    }
    if (state.isRefreshing) return null;
    if (!isConnected) return null;
    if (state.isLoadingChannelGroup) return null;
    return state.confirmedChannelGroup == null
        ? 'Channel Group unavailable.'
        : null;
  }

  String? _es5Message() {
    if (state.hasPendingEs5Change) {
      return state.isWritingEs5 ? null : 'ES-5 change not confirmed.';
    }
    if (state.isRefreshing) return null;
    if (!isConnected) return null;
    if (state.isLoadingEs5) return null;
    return state.confirmedEs5Enabled == null ? 'ES-5 unavailable.' : null;
  }

  String? _modeMessage() {
    if (state.hasPendingModeChange) {
      return state.isWritingMode
          ? null
          : 'Expansion mode change not confirmed.';
    }
    if (state.isRefreshing) return null;
    if (!isConnected) return null;
    if (state.isLoadingMode) return null;
    if (!state.modeCapabilityEvidenced) {
      return 'Expansion mode unavailable.';
    }
    if (state.confirmedMode == null) return 'Expansion mode unavailable.';
    return state.modeRebootRequired ? 'Reboot to apply.' : null;
  }

  String? _expanderAudioMessage() {
    if (!isConnected || state.isRefreshing) return null;
    for (var index = 0; index < kNtx8cvAudioChannelCount; index++) {
      if (state.expanderAudioChannelMessage(index) != null &&
          !state.isWritingExpanderAudioChannel(index)) {
        return 'NT expander audio channel ${index + 1} setting not confirmed.';
      }
    }
    if (!state.hasConfirmedExpanderAudioSnapshot) {
      return 'NT expander audio settings unavailable.';
    }
    return null;
  }
}
