import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/services/initial_sdp_transport.dart';

class InitialSdpExperimentState {
  final String message;
  final bool started;
  final bool busy;
  final bool requestSent;
  final bool detected;
  final bool connected;
  final InitialSdpResponse? response;

  const InitialSdpExperimentState({
    required this.message,
    this.started = false,
    this.busy = false,
    this.requestSent = false,
    this.detected = false,
    this.connected = false,
    this.response,
  });
}

/// One explicit, status-only attempt. No firmware assets or flashing dependency.
class InitialSdpExperimentCubit extends Cubit<InitialSdpExperimentState> {
  final InitialSdpTransport transport;
  final IDistingMidiManager? midiManager;
  final void Function(IDistingMidiManager) releaseMidiManager;
  final bool Function() selectedStillLive;
  final String? ineligibleReason;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _detectionDeadline;
  bool _terminal = false;
  bool _querying = false;
  bool _observing = false;
  bool _nativeUsed = false;
  Future<void>? _cleanup;
  final _cancelPending = <void Function()>{};

  // Unlike Future.timeout, these deadlines are cancelled when the screen closes
  // or a disconnect terminates an in-flight native operation.
  Future<T> _wait<T>(Future<T> operation) {
    final result = Completer<T>();
    late final Timer timer;
    void cancel() {
      timer.cancel();
      if (!result.isCompleted) {
        result.completeError(StateError('Experiment ended'));
      }
    }

    timer = Timer(const Duration(seconds: 10), () {
      _cancelPending.remove(cancel);
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('No operation receipt within 10 seconds'),
        );
      }
    });
    _cancelPending.add(cancel);
    operation.then<void>(
      (value) {
        timer.cancel();
        _cancelPending.remove(cancel);
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        _cancelPending.remove(cancel);
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }

  InitialSdpExperimentCubit({
    required this.transport,
    required this.midiManager,
    required this.releaseMidiManager,
    required this.selectedStillLive,
    this.ineligibleReason,
  }) : super(
         InitialSdpExperimentState(
           message: ineligibleReason ?? 'Ready. No bootloader request sent.',
         ),
       );

  void _update(
    String message, {
    bool? sent,
    bool? detected,
    bool? connected,
    InitialSdpResponse? response,
    bool busy = true,
  }) {
    if (isClosed || _terminal) return;
    emit(
      InitialSdpExperimentState(
        message: message,
        started: true,
        busy: busy,
        requestSent: sent ?? state.requestSent,
        detected: detected ?? state.detected,
        connected: connected ?? state.connected,
        response: response ?? state.response,
      ),
    );
  }

  Future<void> start() async {
    if (state.started || isClosed) return;
    if (ineligibleReason != null ||
        midiManager == null ||
        !selectedStillLive()) {
      _fail(
        'Prerequisite',
        ineligibleReason ??
            'Selected live MIDI connection changed. Reconnect and reopen the experiment.',
      );
      return;
    }
    var stage = 'Driver availability';
    _update('Checking development driver prerequisites.');
    try {
      _nativeUsed = true;
      final availability = await _wait(transport.availability());
      if (isClosed || _terminal) return;
      if (availability['osEligible'] != true ||
          availability['isIPad'] != true ||
          availability['available'] == false ||
          availability['driverEnabled'] == false) {
        _fail(
          stage,
          'Driver unavailable or disabled. Use an M-series iPad on iPadOS 16+ and enable the development driver in Settings > General > Drivers.',
        );
        return;
      }
      // Recheck after asynchronous prerequisites, before touching MIDI ownership.
      if (!selectedStillLive()) {
        _fail(
          'Prerequisite',
          'Selected live MIDI connection changed. Reconnect and reopen the experiment.',
        );
        return;
      }
      stage = 'MIDI request';
      try {
        await _wait(midiManager!.requestEnterBootloader());
      } finally {
        // Only the explicit action consumes the selected manager. Opening and
        // prerequisite failures leave normal MIDI ownership untouched.
        releaseMidiManager(midiManager!);
      }
      if (isClosed || _terminal) return;
      _update(
        'Bootloader request sent. Waiting for observed 1FC9:0135.',
        sent: true,
      );
      stage = 'Detection';
      _observing = true;
      _subscription = transport.events.listen(
        _onEvent,
        onError: (Object error) {
          _fail('Driver observation', _describe(error));
        },
        onDone: () {
          if (!_terminal && !isClosed) {
            _fail(
              'Driver observation',
              'Observation stream closed before a decoded response.',
            );
          }
        },
      );
      _detectionDeadline = Timer(const Duration(seconds: 20), () {
        _fail(
          'Detection',
          'No 1FC9:0135 transition observed. Check driver enablement, development profiles, data cable and independent NT power; disclose any hotplug when retrying.',
        );
      });
      await _wait(transport.observe());
    } catch (error) {
      _fail(stage, _describe(error));
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (_terminal || isClosed || !_observing) return;
    switch (event['stage']) {
      case 'detected':
        if (event['vendorId'] != 0x1fc9 || event['productId'] != 0x0135) {
          _fail(
            'Detection',
            'Unexpected USB identity; initial 1FC9:0135 was not confirmed.',
          );
        } else if (!_querying) {
          unawaited(_connectAndQuery());
        }
      case 'disconnected':
        _fail(
          'Disconnect',
          event['message'] as String? ??
              'Initial bootloader driver disconnected.',
        );
      case 'failure':
        _fail(
          event['failedStage'] as String? ?? 'Driver',
          event['message'] as String? ?? 'Native operation failed.',
        );
      // Waiting, connected and response notifications are not command receipts.
      // Only completed connect/errorStatus calls can advance those stages.
    }
  }

  Future<void> _connectAndQuery() async {
    _querying = true;
    _detectionDeadline?.cancel();
    _update(
      'Observed initial bootloader 1FC9:0135. Connecting driver.',
      detected: true,
    );
    var stage = 'Driver connection';
    try {
      await _wait(transport.connect());
      if (isClosed || _terminal) return;
      _update(
        'Driver connected. Waiting for decoded SDP error-status response.',
        connected: true,
      );
      stage = 'SDP query';
      final response = await _wait(transport.errorStatus());
      if (isClosed || _terminal) return;
      if (response.hab < 0 ||
          response.hab > 0xffffffff ||
          response.status < 0 ||
          response.status > 0xffffffff) {
        throw const FormatException('Malformed SDP status words');
      }
      _update(
        'Decoded SDP error-status response received. Status 0x${response.status.toRadixString(16).padLeft(8, '0')}; HAB 0x${response.hab.toRadixString(16).padLeft(8, '0')}. No firmware programming performed.',
        response: response,
        busy: false,
      );
      _terminal = true;
      await _cleanUp();
    } catch (error) {
      _fail(stage, _describe(error));
    }
  }

  String _describe(Object error) => error is PlatformException
      ? error.message ?? error.code
      : error is MissingPluginException
      ? 'Development driver channel unavailable. Install the RunnerInitialSdp development build.'
      : error.toString();

  void _fail(String stage, String detail) {
    if (isClosed || _terminal) return;
    _update('$stage failed: $detail', busy: false);
    _terminal = true;
    unawaited(_cleanUp());
  }

  Future<void> _cleanUp() => _cleanup ??= () async {
    _observing = false;
    _detectionDeadline?.cancel();
    for (final cancel in _cancelPending.toList()) {
      cancel();
    }
    _cancelPending.clear();
    await _subscription?.cancel();
    if (_nativeUsed) {
      try {
        await transport.close();
      } catch (_) {
        // An unavailable channel has no native resources to release.
      }
    }
  }();

  @override
  Future<void> close() async {
    _terminal = true;
    await _cleanUp();
    return super.close();
  }
}
