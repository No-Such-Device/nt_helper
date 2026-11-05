import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/ipad_firmware_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('dev.nosuch.nt_helper/firmware_session_v2');
  const eventName = 'dev.nosuch.nt_helper/firmware_session_v2_events';
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var nextId = 0;
  Map<String, Object> availability = {};
  late MethodChannelIpadFirmwareSession transport;

  Future<void> emit(Map<String, Object> event) async {
    await messenger.handlePlatformMessage(
      eventName,
      codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    calls.clear();
    nextId = 0;
    availability = {
      'api': MethodChannelIpadFirmwareSession.api,
      'maxLoader': MethodChannelIpadFirmwareSession.maxLoader,
      'maxApplication': MethodChannelIpadFirmwareSession.maxApplication,
      'isIPad': true,
      'osEligible': true,
    };
    transport = MethodChannelIpadFirmwareSession();
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventName),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return switch (call.method) {
        'availability' => availability,
        'prepare' => {'sessionId': 'session-${++nextId}'},
        _ => null,
      };
    });
  });
  tearDown(() async {
    await transport.close();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(const MethodChannel(eventName), null);
  });

  // Status-only channel tests cannot exercise the separate V2 typed contract.
  test(
    'V2 accepts only bounded bytes and attributes programming results',
    () async {
      final id = await transport.prepare();
      final seen = <IpadFirmwareEvent>[];
      final subscription = transport.events.listen(seen.add);
      final result = transport.start(
        sessionId: id,
        loader: Uint8List.fromList([1, 2]),
        application: Uint8List.fromList([3, 4, 5]),
      );
      await emit({
        'sessionId': id,
        'phase': 'writingApplication',
        'transferred': 2,
        'total': 3,
      });
      await emit({'sessionId': id, 'phase': 'programmed'});
      expect((await result).outcome, IpadProgrammingOutcome.programmed);
      final start = calls.singleWhere((call) => call.method == 'start');
      expect((start.arguments as Map).keys, [
        'sessionId',
        'loader',
        'application',
      ]);
      expect((start.arguments as Map)['loader'], Uint8List.fromList([1, 2]));
      expect(seen.map((event) => event.phase), [
        IpadProgrammingPhase.writingApplication,
        IpadProgrammingPhase.programmed,
      ]);
      expect(seen.every((event) => event.sessionId == id), isTrue);
      await subscription.cancel();
      expect(calls.map((call) => call.method), [
        'availability',
        'prepare',
        'start',
      ]);
    },
  );

  test(
    'incompatible API and unsupported iPad fail before preparing USB',
    () async {
      for (final change in [
        {'api': 1},
        {'maxLoader': 0},
        {'isIPad': false},
        {'osEligible': false},
      ]) {
        final original = Map<String, Object>.from(availability);
        availability.addAll(change);
        await expectLater(transport.prepare(), throwsA(anything));
        expect(calls.where((call) => call.method == 'prepare'), isEmpty);
        availability = original;
      }
    },
  );

  test(
    'empty oversized stale and concurrent starts never submit bytes',
    () async {
      final id = await transport.prepare();
      await expectLater(transport.prepare(), throwsStateError);
      for (final loader in [
        Uint8List(0),
        Uint8List(MethodChannelIpadFirmwareSession.maxLoader + 1),
      ]) {
        await expectLater(
          transport.start(
            sessionId: id,
            loader: loader,
            application: Uint8List(1),
          ),
          throwsRangeError,
        );
      }
      await expectLater(
        transport.start(
          sessionId: 'stale',
          loader: Uint8List(1),
          application: Uint8List(1),
        ),
        throwsStateError,
      );
      await expectLater(
        transport.start(
          sessionId: id,
          loader: Uint8List(1),
          application: Uint8List(
            MethodChannelIpadFirmwareSession.maxApplication + 1,
          ),
        ),
        throwsRangeError,
      );
      expect(calls.where((call) => call.method == 'start'), isEmpty);
      final first = transport.start(
        sessionId: id,
        loader: Uint8List(1),
        application: Uint8List(1),
      );
      await expectLater(
        transport.start(
          sessionId: id,
          loader: Uint8List(1),
          application: Uint8List(1),
        ),
        throwsStateError,
      );
      await transport.cancel(id);
      expect((await first).outcome, IpadProgrammingOutcome.canceled);
      expect(calls.where((call) => call.method == 'start').length, 1);
    },
  );

  test(
    'late terminal events cannot complete or cancel a newer session',
    () async {
      final old = await transport.prepare();
      await transport.cancel(old);
      final id = await transport.prepare();
      var completed = false;
      final result = transport
          .start(sessionId: id, loader: Uint8List(1), application: Uint8List(1))
          .then((value) {
            completed = true;
            return value;
          });
      await emit({'sessionId': old, 'phase': 'programmed'});
      expect(completed, isFalse);
      await expectLater(transport.cancel(old), throwsStateError);
      await emit({
        'sessionId': id,
        'phase': 'failed',
        'message': 'Reset ACK missing',
      });
      expect((await result).outcome, IpadProgrammingOutcome.failed);
      expect(calls.where((call) => call.method == 'start').length, 1);
    },
  );

  test(
    'closing during preparation releases the eventual native reservation',
    () async {
      final entered = Completer<void>();
      final reservation = Completer<Map<String, String>>();
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'availability') return availability;
        if (call.method == 'prepare') {
          entered.complete();
          return reservation.future;
        }
        return null;
      });
      final preparing = transport.prepare();
      await entered.future;
      final rejected = expectLater(preparing, throwsStateError);
      await transport.close();
      reservation.complete({'sessionId': 'closed-reservation'});
      await rejected;
      expect(calls.last.method, 'close');
      expect(calls.last.arguments, {'sessionId': 'closed-reservation'});
    },
  );

  test(
    'malformed native progress fails closed and tears down the session',
    () async {
      for (final invalid in [
        {'phase': 'unknown'},
        {'phase': 'writingApplication', 'transferred': 4, 'total': 3},
        {'phase': 'programmed', 'message': 42},
      ]) {
        final id = await transport.prepare();
        final result = transport.start(
          sessionId: id,
          loader: Uint8List(1),
          application: Uint8List(1),
        );
        await emit({'sessionId': id, ...invalid});
        expect((await result).outcome, IpadProgrammingOutcome.failed);
        expect(calls.where((call) => call.method == 'cancel').last.arguments, {
          'sessionId': id,
        });
      }
    },
  );
}
