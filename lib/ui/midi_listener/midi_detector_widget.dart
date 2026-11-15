import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'midi_listener_cubit.dart';

/// Detect MIDI devices, connect, and watch CC messages.
/// If an ancestor MidiListenerCubit is found, use it.
/// Otherwise, create and own a MidiListenerCubit locally.
class MidiDetectorWidget extends StatelessWidget {
  final Function({
    required MidiEventType type,
    required int channel,
    required int number, // CC or Note number
  })?
  onMidiEventFound;

  const MidiDetectorWidget({super.key, this.onMidiEventFound});

  @override
  Widget build(BuildContext context) {
    // Try to find an existing MidiListenerCubit in the current context
    // If none is found, an exception is thrown.
    // We can catch that to decide whether we create a local Cubit or not.
    try {
      context.read<MidiListenerCubit>();
      // If we get here, there's already a MidiListenerCubit in the ancestor tree
      return _MidiDetectorContents(
        onMidiEventFound: onMidiEventFound,
        useLocalCubit: false, // We'll use the existing one
      );
    } catch (_) {
      // No MidiListenerCubit exists above, so we create a local one
      return BlocProvider(
        create: (_) => MidiListenerCubit(),
        child: _MidiDetectorContents(
          onMidiEventFound: onMidiEventFound,
          useLocalCubit: true,
        ),
      );
    }
  }
}

/// The actual UI/stateful logic for the MIDI detector.
/// This widget **expects** a MidiListenerCubit to be in the widget tree.
/// If [useLocalCubit] is true, we created one ourselves in the parent;
/// otherwise, we rely on an ancestor-provided Cubit.
class _MidiDetectorContents extends StatefulWidget {
  final Function({
    required MidiEventType type,
    required int channel,
    required int number,
  })?
  onMidiEventFound;
  final bool useLocalCubit;

  const _MidiDetectorContents({
    required this.onMidiEventFound,
    required this.useLocalCubit,
  });

  @override
  State<_MidiDetectorContents> createState() => _MidiDetectorContentsState();
}

class _MidiDetectorContentsState extends State<_MidiDetectorContents> {
  late MidiListenerCubit _cubit;
  List<MidiDevice> _devices = [];
  MidiDevice? _selectedDevice;
  final TextEditingController _dropdownController = TextEditingController();

  String? _statusMessage;
  Timer? _fadeTimer;
  bool _wasConnected = false;
  DateTime? _lastHandledDetectionTime;

  @override
  void initState() {
    super.initState();
    // Access the Cubit from the context
    _cubit = context.read<MidiListenerCubit>();
    _cubit.startDetecting();

    final s = _cubit.state;
    if (s is Initial) {
      _cubit.discoverDevices().then((devices) {
        if (mounted) {
          setState(() => _devices = devices ?? []);
        }
      });
    } else if (s is Data) {
      _devices = s.devices;
      _selectedDevice = s.selectedDevice;
      if (_selectedDevice != null) {
        _dropdownController.text = _selectedDevice!.name;
      }

      // Restore status message for connected device
      _wasConnected = s.isConnected;
      if (s.isConnected && s.selectedDevice != null) {
        _statusMessage = 'Connected to ${s.selectedDevice!.name}.';
      }
      _lastHandledDetectionTime = s.lastDetectedTime;
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _dropdownController.dispose();

    if (widget.useLocalCubit) {
      _cubit.close();
    } else {
      _cubit.stopDetecting();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card.outlined(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('MIDI Detector', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildDeviceDropdown(),
            const SizedBox(height: 16),
            BlocConsumer<MidiListenerCubit, MidiListenerState>(
              listener: (context, state) {
                switch (state) {
                  case Initial():
                    _showStatusMessage('No device connected.');
                  case Data(
                    :final devices,
                    :final isConnected,
                    :final selectedDevice,
                    :final lastDetectedType,
                    :final lastDetectedChannel,
                    :final lastDetectedCc,
                    :final lastDetectedNote,
                    :final lastDetectedTime,
                  ):
                    // Sync device list from cubit state
                    if (devices != _devices) {
                      setState(() => _devices = devices);
                    }

                    // Handle disconnection when device disappeared
                    if (selectedDevice == null && _selectedDevice != null) {
                      setState(() {
                        _selectedDevice = null;
                        _dropdownController.clear();
                      });
                    }

                    // Only show connection status on transitions
                    if (isConnected && !_wasConnected) {
                      _showStatusMessage(
                        'Connected to ${selectedDevice?.name}.',
                      );
                    } else if (!isConnected && _wasConnected) {
                      _showStatusMessage('No device connected.');
                    }
                    _wasConnected = isConnected;
                    final isNewDetection =
                        lastDetectedType != null &&
                        lastDetectedChannel != null &&
                        lastDetectedTime != null &&
                        lastDetectedTime != _lastHandledDetectionTime;
                    if (isNewDetection) {
                      _lastHandledDetectionTime = lastDetectedTime;
                      final (String, int?)
                      eventInfo = switch (lastDetectedType) {
                        MidiEventType.cc => ('CC', lastDetectedCc),
                        MidiEventType.noteOn => ('Note On', lastDetectedNote),
                        MidiEventType.noteOff => ('Note Off', lastDetectedNote),
                        MidiEventType.cc14BitLowFirst => (
                          '14-bit CC',
                          lastDetectedCc,
                        ),
                        MidiEventType.cc14BitHighFirst => (
                          '14-bit CC',
                          lastDetectedCc,
                        ),
                        MidiEventType.pitchBend => (
                          'Pitch bend',
                          lastDetectedCc,
                        ),
                        MidiEventType.channelPressure => (
                          'Channel pressure',
                          lastDetectedCc,
                        ),
                        MidiEventType.nrpn => ('NRPN', lastDetectedCc),
                      };

                      final eventNumber = eventInfo.$2;
                      if (eventNumber != null) {
                        final eventTypeStr = eventInfo.$1;
                        final message = switch (lastDetectedType) {
                          MidiEventType.cc14BitLowFirst ||
                          MidiEventType.cc14BitHighFirst =>
                            '14-bit CC $eventNumber Ch ${lastDetectedChannel + 1}',
                          MidiEventType.pitchBend =>
                            'Pitch bend Ch ${lastDetectedChannel + 1}',
                          MidiEventType.channelPressure =>
                            'Channel pressure Ch ${lastDetectedChannel + 1}',
                          MidiEventType.nrpn =>
                            'NRPN $eventNumber Ch ${lastDetectedChannel + 1}',
                          _ =>
                            'Detected $eventTypeStr $eventNumber on channel ${lastDetectedChannel + 1}',
                        };
                        _showStatusMessage(message);
                        widget.onMidiEventFound?.call(
                          type: lastDetectedType,
                          channel: lastDetectedChannel,
                          number: eventNumber,
                        );
                      }
                    }
                }
              },
              builder: (context, state) {
                return _buildAnimatedStatus(theme);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceDropdown() {
    final sorted = List<MidiDevice>.of(_devices)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final entries = sorted.map((device) {
      return DropdownMenuEntry<MidiDevice>(value: device, label: device.name);
    }).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownMenu<MidiDevice>(
          width: 200,
          requestFocusOnTap: false,
          controller: _dropdownController,
          label: const Text('MIDI Device'),
          dropdownMenuEntries: entries,
          onSelected: _onDeviceSelected,
        ),
        const SizedBox(width: 8),
        BlocBuilder<MidiListenerCubit, MidiListenerState>(
          builder: (context, state) {
            final isConnected = state is Data && state.isConnected;
            return ElevatedButton.icon(
              onPressed: isConnected ? _onDisconnectPressed : null,
              icon: const Icon(Icons.close),
              label: const Text('Disconnect'),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAnimatedStatus(ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: SizedBox(
        height: 24,
        child: _statusMessage != null
            ? Text(
                _statusMessage!,
                key: ValueKey(_statusMessage),
                style: theme.textTheme.bodyMedium,
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  void _onDeviceSelected(MidiDevice? device) {
    if (device == null) return;
    setState(() => _selectedDevice = device);
    _cubit.connectToDevice(device);
  }

  void _onDisconnectPressed() {
    setState(() => _selectedDevice = null);
    _dropdownController.clear();
    _cubit.disconnectDevice();
  }

  void _showStatusMessage(String newMessage) {
    setState(() {
      _statusMessage = newMessage;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      newMessage,
      TextDirection.ltr,
    );
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _statusMessage = null;
      });
    });
  }
}
