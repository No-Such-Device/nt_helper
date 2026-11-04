import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';

bool get ipadFirmwareV2Enabled =>
    !kReleaseMode &&
    Platform.isIOS &&
    const bool.fromEnvironment('NT_IPAD_FIRMWARE_V2');

/// Programming completion is not post-reboot application-version verification.
enum IpadProgrammingOutcome { programmed, canceled, failed }

enum IpadProgrammingPhase {
  waitingRom,
  uploadingLoader,
  jumping,
  waitingLoader,
  configuringNor,
  erasing,
  creatingFcb,
  writingApplication,
  resetting,
  programmed,
  canceled,
  failed,
}

extension IpadProgrammingPhaseLabel on IpadProgrammingPhase {
  String get label => switch (this) {
    IpadProgrammingPhase.waitingRom => 'Waiting for ROM bootloader',
    IpadProgrammingPhase.uploadingLoader => 'Uploading RAM loader',
    IpadProgrammingPhase.jumping => 'Starting RAM loader',
    IpadProgrammingPhase.waitingLoader =>
      'Waiting for flashloader USB connection',
    IpadProgrammingPhase.configuringNor => 'Configuring NOR flash',
    IpadProgrammingPhase.erasing => 'Erasing application region',
    IpadProgrammingPhase.creatingFcb => 'Creating flash configuration block',
    IpadProgrammingPhase.writingApplication => 'Writing application firmware',
    IpadProgrammingPhase.resetting => 'Resetting device',
    IpadProgrammingPhase.programmed =>
      'Programming complete; version not verified',
    IpadProgrammingPhase.canceled => 'Programming canceled',
    IpadProgrammingPhase.failed => 'Programming failed',
  };
}

class IpadFirmwareAvailability {
  final bool isIPad;
  final bool osEligible;
  const IpadFirmwareAvailability({
    required this.isIPad,
    required this.osEligible,
  });
}

class IpadFirmwareEvent {
  final String sessionId;
  final IpadProgrammingPhase phase;
  final int? transferred;
  final int? total;
  final String? message;
  const IpadFirmwareEvent({
    required this.sessionId,
    required this.phase,
    this.transferred,
    this.total,
    this.message,
  });
}

class IpadProgrammingResult {
  final String sessionId;
  final IpadProgrammingOutcome outcome;
  final String? message;
  const IpadProgrammingResult(this.sessionId, this.outcome, this.message);
}

abstract interface class IpadFirmwareSession {
  Future<IpadFirmwareAvailability> availability();

  /// Snapshot absence of bootloaders before the workflow releases MIDI.
  Future<String> prepare();
  Stream<IpadFirmwareEvent> get events;
  Future<IpadProgrammingResult> start({
    required String sessionId,
    required Uint8List loader,
    required Uint8List application,
  });
  Future<void> cancel(String sessionId);
  Future<void> close();
}

/// Registered exclusively by RunnerFirmwareV2, never the status-only target.
/// No native selectors, identities, addresses or commands cross this API.
class MethodChannelIpadFirmwareSession implements IpadFirmwareSession {
  static const api = 0x4e540002;
  static const maxLoader = 0x1e400;
  static const maxApplication = 0x7ff000;
  static const _methods = MethodChannel(
    'dev.nosuch.nt_helper/firmware_session_v2',
  );
  static const _nativeEvents = EventChannel(
    'dev.nosuch.nt_helper/firmware_session_v2_events',
  );
  final _events = StreamController<IpadFirmwareEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  String? _session;
  bool _preparing = false;
  int _generation = 0;
  Completer<IpadProgrammingResult>? _completion;

  @override
  Stream<IpadFirmwareEvent> get events => _events.stream;

  @override
  Future<IpadFirmwareAvailability> availability() async {
    final value = await _methods.invokeMapMethod<String, dynamic>(
      'availability',
    );
    if (value == null ||
        value['api'] != api ||
        value['maxLoader'] != maxLoader ||
        value['maxApplication'] != maxApplication ||
        value['isIPad'] is! bool ||
        value['osEligible'] is! bool) {
      throw const FormatException('Incompatible iPad firmware-session API');
    }
    return IpadFirmwareAvailability(
      isIPad: value['isIPad'] as bool,
      osEligible: value['osEligible'] as bool,
    );
  }

  @override
  Future<String> prepare() async {
    if (_session != null || _preparing) {
      throw StateError('A firmware session already owns USB');
    }
    _preparing = true;
    final epoch = _generation;
    try {
      final available = await availability();
      if (epoch != _generation) throw StateError('Firmware preparation closed');
      if (!available.isIPad || !available.osEligible) {
        throw UnsupportedError('A supported development iPad is required');
      }
      _subscription = _nativeEvents.receiveBroadcastStream().listen(
        _receive,
        onError: (Object error) => _finish(
          IpadProgrammingOutcome.failed,
          'Native firmware event stream failed: $error',
        ),
        onDone: () => _finish(
          IpadProgrammingOutcome.failed,
          'Native firmware event stream closed',
        ),
      );
      final value = await _methods.invokeMapMethod<String, dynamic>('prepare');
      final id = value?['sessionId'];
      if (id is! String || id.isEmpty) {
        throw const FormatException('Missing firmware session identity');
      }
      if (epoch != _generation) {
        await _methods.invokeMethod<void>('close', {'sessionId': id});
        throw StateError('Firmware preparation closed');
      }
      _session = id;
      return id;
    } catch (_) {
      await _subscription?.cancel();
      _subscription = null;
      rethrow;
    } finally {
      _preparing = false;
    }
  }

  @override
  Future<IpadProgrammingResult> start({
    required String sessionId,
    required Uint8List loader,
    required Uint8List application,
  }) async {
    if (_session != sessionId || _completion != null) {
      throw StateError('Stale or concurrent firmware session');
    }
    if (loader.isEmpty ||
        loader.length > maxLoader ||
        application.isEmpty ||
        application.length > maxApplication) {
      throw RangeError('Firmware bytes exceed supported RAM/flash bounds');
    }
    final completion = Completer<IpadProgrammingResult>();
    _completion = completion;
    try {
      await _methods.invokeMethod<void>('start', {
        'sessionId': sessionId,
        'loader': Uint8List.fromList(loader),
        'application': Uint8List.fromList(application),
      });
    } catch (_) {
      if (_session == sessionId) await close();
      rethrow;
    }
    return completion.future;
  }

  void _receive(dynamic raw) {
    if (raw is! Map || raw['sessionId'] != _session || _session == null) {
      return; // Queued events from an older session cannot advance this one.
    }
    try {
      final name = raw['phase'];
      final phase = IpadProgrammingPhase.values.firstWhere(
        (value) => value.name == name,
      );
      final transferred = raw['transferred'];
      final total = raw['total'];
      if ((transferred != null || total != null) &&
          (transferred is! int ||
              total is! int ||
              total <= 0 ||
              transferred < 0 ||
              transferred > total ||
              total > maxApplication)) {
        throw const FormatException('Invalid programming byte counts');
      }
      final message = raw['message'];
      if (message != null && message is! String) {
        throw const FormatException('Invalid programming message');
      }
      _events.add(
        IpadFirmwareEvent(
          sessionId: _session!,
          phase: phase,
          transferred: transferred as int?,
          total: total as int?,
          message: message as String?,
        ),
      );
      switch (phase) {
        case IpadProgrammingPhase.programmed:
          _finish(IpadProgrammingOutcome.programmed, message);
        case IpadProgrammingPhase.canceled:
          _finish(IpadProgrammingOutcome.canceled, message);
        case IpadProgrammingPhase.failed:
          _finish(IpadProgrammingOutcome.failed, message);
        default:
          break;
      }
    } catch (_) {
      unawaited(cancel(_session!).catchError((Object _) {}));
      _finish(IpadProgrammingOutcome.failed, 'Malformed native firmware event');
    }
  }

  void _finish(IpadProgrammingOutcome outcome, String? message) {
    final id = _session;
    if (id == null) return;
    _session = null;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete(IpadProgrammingResult(id, outcome, message));
    }
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  Future<void> cancel(String sessionId) async {
    if (_session != sessionId) throw StateError('Stale firmware session');
    try {
      await _methods.invokeMethod<void>('cancel', {'sessionId': sessionId});
    } finally {
      if (_session == sessionId) {
        _finish(IpadProgrammingOutcome.canceled, 'Programming canceled');
      }
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    final id = _session;
    if (id != null) await cancel(id);
  }
}
