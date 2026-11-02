import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/initial_sdp_experiment_cubit.dart';
import 'package:nt_helper/services/initial_sdp_transport.dart';

// Set only on RunnerInitialSdp. Profile/AOT allows the iPad's USB port to
// connect to the NT without a Mac debugger; Release stays excluded.
bool get initialSdpExperimentEnabled =>
    !kReleaseMode &&
    Platform.isIOS &&
    const bool.fromEnvironment('NT_INITIAL_SDP_EXPERIMENT');

class InitialSdpExperimentScreenDependencies {
  final InitialSdpTransport transport;
  const InitialSdpExperimentScreenDependencies({required this.transport});
}

class InitialSdpExperimentScreen extends StatefulWidget {
  final DistingCubit distingCubit;
  @visibleForTesting
  final InitialSdpExperimentScreenDependencies? dependencies;

  const InitialSdpExperimentScreen({
    super.key,
    required this.distingCubit,
    this.dependencies,
  });

  @override
  State<InitialSdpExperimentScreen> createState() =>
      _InitialSdpExperimentScreenState();
}

class _InitialSdpExperimentScreenState
    extends State<InitialSdpExperimentScreen> {
  // Retain the chosen connection and baseline even after handoff resets MIDI
  // state or an orientation/theme rebuild occurs.
  late final DistingState selected = widget.distingCubit.state;

  @override
  Widget build(BuildContext context) {
    final distingCubit = widget.distingCubit;
    final dependencies = widget.dependencies;
    if (!initialSdpExperimentEnabled && dependencies == null) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Available only in the iPad development experiment build.',
          ),
        ),
      );
    }
    final snapshot = selected;
    final live = snapshot is DistingStateSynchronized ? snapshot : null;
    final input = live?.inputDevice;
    final output = live?.outputDevice;
    final version = live?.firmwareVersion;
    final recognizedVersion =
        version != null &&
        RegExp(
          r'^v?\d+\.\d+(?:\.\d+)?(?:-?beta(?:\.?\d+)?)?$',
          caseSensitive: false,
        ).hasMatch(version.versionString.trim());
    final reason =
        live == null ||
            live.demo ||
            live.offline ||
            input == null ||
            output == null
        ? 'Prerequisite: select a synchronized live NT; demo and offline connections cannot enter bootloader.'
        : !recognizedVersion
        ? 'Prerequisite: firmware capability is unknown. No request allowed.'
        : !version.hasBootloaderSysEx
        ? 'Prerequisite: firmware 1.15 or later is required for bootloader entry.'
        : null;
    return BlocProvider(
      create: (_) => InitialSdpExperimentCubit(
        transport:
            dependencies?.transport ?? MethodChannelInitialSdpTransport(),
        midiManager: live?.disting,
        ineligibleReason: reason,
        selectedStillLive: () {
          final current = distingCubit.state;
          return current is DistingStateSynchronized &&
              !current.demo &&
              !current.offline &&
              identical(current.disting, live?.disting) &&
              current.inputDevice?.id == input?.id &&
              current.outputDevice?.id == output?.id &&
              current.firmwareVersion.versionString == version?.versionString;
        },
        releaseMidiManager: (manager) =>
            distingCubit.disposeFirmwareMidiManager(manager, input!, output!),
      ),
      child: _ExperimentView(
        eligible: reason == null,
        selection:
            '${input?.name ?? 'No input'} → ${output?.name ?? 'No output'}; firmware ${version?.versionString ?? 'unknown'}',
      ),
    );
  }
}

class _ExperimentView extends StatelessWidget {
  final bool eligible;
  final String selection;
  const _ExperimentView({required this.eligible, required this.selection});

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<InitialSdpExperimentCubit, InitialSdpExperimentState>(
    listener: (context, state) => SemanticsService.sendAnnouncement(
      View.of(context),
      state.message,
      Directionality.of(context),
    ),
    builder: (context, state) => Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('Initial SDP experiment'),
        ),
      ),
      body: FocusTraversalGroup(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'Development only · status exchange, no flashing',
                ),
              ),
              const SizedBox(height: 12),
              Text(selection),
              const SizedBox(height: 12),
              const Text(
                'Before starting, record NT firmware and normal operation. Use an M-series iPad on iPadOS 16+, enable the driver in Settings > Apps > Nt Helper > Drivers, and connect a USB data cable with independent NT power. This action interrupts MIDI. After the attempt, power-cycle the NT and compare firmware and normal operation; record any hotplug.',
              ),
              const SizedBox(height: 16),
              for (final row in [
                ('Bootloader request sent', state.requestSent),
                ('Observed initial USB 1FC9:0135', state.detected),
                ('Driver connected', state.connected),
                ('Decoded SDP response received', state.response != null),
              ])
                SizedBox(
                  height: 40,
                  child: Semantics(
                    label:
                        '${row.$1}: ${row.$2 ? 'confirmed' : 'not confirmed'}',
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          Icon(
                            row.$2
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(row.$1)),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('sdp-progress-slot'),
                height: 8,
                child: state.busy
                    ? const LinearProgressIndicator(
                        semanticsLabel: 'Initial SDP experiment in progress',
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('sdp-status-slot'),
                height: 144,
                child: Semantics(
                  key: const ValueKey('sdp-live-status'),
                  container: true,
                  liveRegion: true,
                  child: SingleChildScrollView(child: Text(state.message)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                key: const ValueKey('sdp-action-slot'),
                height: 52,
                child: FilledButton(
                  onPressed: eligible && !state.started
                      ? context.read<InitialSdpExperimentCubit>().start
                      : null,
                  child: const Text('Request bootloader and read status'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close experiment'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
