import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/request_key.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMidi extends Mock implements MidiCommand {}

Uint8List _sysEx(
  DistingNTRespMessageType type,
  List<int> payload, {
  int sysExId = 0,
}) => Uint8List.fromList([
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  sysExId,
  type.value,
  ...payload,
  0xF7,
]);

Uint8List _algorithmInfoFrame(int libraryIndex, String guid, String name) =>
    _sysEx(DistingNTRespMessageType.respAlgorithmInfo, [
      ...encode16(libraryIndex),
      ...guid.codeUnits,
      0, // 0 specifications
      ...name.codeUnits,
      0,
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'inter_message_delay_ms': 0,
      'request_timeout_ms': 50,
    });
    await SettingsService().init();
  });

  group('Terminal disposal and closed/unavailable receive stream', () {
    final packet = Uint8List.fromList([0xF0, 0x7D, 1, 0xF7]);

    test('disposed scheduler rejects new work immediately with zero sends', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends = 0;
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sends++);

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
        );
        scheduler.dispose();
        // Idempotent second dispose
        scheduler.dispose();

        Object? error;
        scheduler
            .sendRequest<void>(
              packet,
              RequestKey(sysExId: 0),
              responseExpectation: ResponseExpectation.none,
            )
            .then<void>(
              (_) => fail('Expected terminal rejection'),
              onError: (Object e) => error = e,
            );
        time.flushMicrotasks();

        expect(sends, 0);
        expect(
          error,
          isA<DistingSchedulerClosedException>()
              .having(
                (e) => e.reason,
                'reason',
                SchedulerTerminationReason.disposed,
              )
              .having((e) => e.phase, 'phase', RequestFailurePhase.beforeSend)
              .having((e) => e.definitelyUnsent, 'definitelyUnsent', isTrue),
        );
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test('dispose settles inflight with inFlight phase and queued with beforeSend once', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends = 0;
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sends++);

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
        );

        final errors = <int, Object>{};
        var completions = 0;

        scheduler
            .sendRequest<int>(
              _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respNumAlgorithms,
              ),
            )
            .then<void>(
              (_) => completions++,
              onError: (Object e) {
                completions++;
                errors[0] = e;
              },
            );
        scheduler
            .sendRequest<String>(
              _sysEx(DistingNTRespMessageType.respPresetName, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respPresetName,
              ),
            )
            .then<void>(
              (_) => completions++,
              onError: (Object e) {
                completions++;
                errors[1] = e;
              },
            );
        scheduler
            .sendRequest<void>(
              packet,
              RequestKey(sysExId: 0),
              responseExpectation: ResponseExpectation.none,
              replayPolicy: RequestReplayPolicy.never,
            )
            .then<void>(
              (_) => completions++,
              onError: (Object e) {
                completions++;
                errors[2] = e;
              },
            );

        time.flushMicrotasks();
        expect(sends, 1);

        scheduler.dispose();
        time.flushMicrotasks();

        expect(completions, 3);
        expect(sends, 1);
        expect(
          errors[0],
          isA<DistingSchedulerClosedException>()
              .having((e) => e.phase, 'phase', RequestFailurePhase.inFlight)
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue),
        );
        expect(
          errors[1],
          isA<DistingSchedulerClosedException>()
              .having((e) => e.phase, 'phase', RequestFailurePhase.beforeSend)
              .having((e) => e.definitelyUnsent, 'definitelyUnsent', isTrue),
        );
        expect(
          errors[2],
          isA<DistingSchedulerClosedException>()
              .having((e) => e.phase, 'phase', RequestFailurePhase.beforeSend)
              .having((e) => e.definitelyUnsent, 'definitelyUnsent', isTrue),
        );
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test('closed receive stream terminates scheduler, settles work, rejects new sends, and notifies once', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends = 0;
        var lossNotifications = 0;
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sends++);

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
          onConnectionLost: () => lossNotifications++,
        );

        Object? inflightError;
        Object? queuedError;
        scheduler
            .sendRequest<int>(
              _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respNumAlgorithms,
              ),
            )
            .then<void>((_) {}, onError: (Object e) => inflightError = e);
        scheduler
            .sendRequest<void>(
              packet,
              RequestKey(sysExId: 0),
              responseExpectation: ResponseExpectation.none,
              replayPolicy: RequestReplayPolicy.never,
            )
            .then<void>((_) {}, onError: (Object e) => queuedError = e);

        time.flushMicrotasks();
        expect(sends, 1);

        incoming.close();
        time.flushMicrotasks();

        expect(lossNotifications, 1);
        expect(scheduler.isUsable, isFalse);
        expect(scheduler.getDiagnostics()['subscriptionActive'], isFalse);
        expect(
          inflightError,
          isA<DistingSchedulerClosedException>()
              .having(
                (e) => e.reason,
                'reason',
                SchedulerTerminationReason.receiveStreamClosed,
              )
              .having((e) => e.phase, 'phase', RequestFailurePhase.inFlight),
        );
        expect(
          queuedError,
          isA<DistingSchedulerClosedException>()
              .having(
                (e) => e.reason,
                'reason',
                SchedulerTerminationReason.receiveStreamClosed,
              )
              .having((e) => e.phase, 'phase', RequestFailurePhase.beforeSend),
        );

        Object? afterCloseError;
        scheduler
            .sendRequest<void>(
              packet,
              RequestKey(sysExId: 0),
              responseExpectation: ResponseExpectation.none,
            )
            .then<void>((_) {}, onError: (Object e) => afterCloseError = e);
        time.flushMicrotasks();

        expect(sends, 1);
        expect(
          afterCloseError,
          isA<DistingSchedulerClosedException>()
              .having(
                (e) => e.reason,
                'reason',
                SchedulerTerminationReason.receiveStreamClosed,
              )
              .having((e) => e.phase, 'phase', RequestFailurePhase.beforeSend),
        );
        scheduler.dispose();
        time.flushMicrotasks();
      });
    });

    test(
      'null receive stream immediately rejects sends without transmitting',
      () {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          var sends = 0;
          when(() => midi.onMidiPacketReceived).thenReturn(null);
          when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
              .thenAnswer((_) => sends++);

          final scheduler = DistingMessageScheduler(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );
          expect(scheduler.isUsable, isFalse);

          Object? error;
          scheduler
              .sendRequest<void>(
                packet,
                RequestKey(sysExId: 0),
                responseExpectation: ResponseExpectation.none,
              )
              .then<void>((_) {}, onError: (Object e) => error = e);
          time.flushMicrotasks();

          expect(sends, 0);
          expect(
            error,
            isA<DistingSchedulerClosedException>().having(
              (e) => e.reason,
              'reason',
              SchedulerTerminationReason.receiveStreamUnavailable,
            ),
          );
          scheduler.dispose();
        });
      },
    );

    test(
      'suspended forceDeviceReconnect cannot revive listener after dispose',
      () {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          when(() => midi.connectToDevice(device)).thenAnswer((_) async {});
          when(() => midi.disconnectDevice(device)).thenAnswer((_) {});

          final scheduler = DistingMessageScheduler(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );

          var finished = false;
          scheduler.forceDeviceReconnect().then((_) => finished = true);
          time.elapse(const Duration(milliseconds: 300));
          scheduler.dispose();
          time.flushMicrotasks();
          expect(incoming.hasListener, isFalse);

          time.elapse(const Duration(seconds: 2));
          time.flushMicrotasks();

          expect(finished, isTrue);
          expect(incoming.hasListener, isFalse);
          verifyNever(() => midi.connectToDevice(device));
          incoming.close();
          time.flushMicrotasks();
        });
      },
    );

    test('forceDeviceReconnect awaits async connect error and broken-flag fails terminally without looping', () {
      for (final retryDelay in [
        Duration.zero,
        const Duration(milliseconds: 50),
      ]) {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          var sends = 0;
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          when(() => midi.disconnectDevice(device)).thenAnswer((_) {});
          when(() => midi.connectToDevice(device))
              .thenAnswer((_) => Future<void>.error(StateError('USB gone')));
          when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
              .thenAnswer((_) => sends++);

          final scheduler = DistingMessageScheduler(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
            defaultMaxRetries: 5,
            defaultRetryDelay: retryDelay,
          );

          var reconnectDone = false;
          scheduler.forceDeviceReconnect().then((_) => reconnectDone = true);
          time.elapse(const Duration(seconds: 1));
          time.flushMicrotasks();
          expect(reconnectDone, isTrue);
          expect(incoming.hasListener, isFalse);

          // Re-attach subscription to specifically exercise the broken-flag
          // branch inside _sendCurrentRequest without stack overflow or loop.
          scheduler.tryReconnectSubscription();
          expect(incoming.hasListener, isTrue);

          Object? error;
          scheduler
              .sendRequest<int>(
                _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
                RequestKey(
                  sysExId: 0,
                  messageType: DistingNTRespMessageType.respNumAlgorithms,
                ),
                maxRetries: 5,
                retryDelay: retryDelay,
              )
              .then<void>((_) {}, onError: (Object e) => error = e);

          time.elapse(const Duration(seconds: 5));
          time.flushMicrotasks();

          expect(sends, 0);
          expect(
            error,
            isA<DistingSchedulerClosedException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  SchedulerTerminationReason.connectionLost,
                )
                .having(
                  (e) => e.phase,
                  'phase',
                  RequestFailurePhase.beforeSend,
                ),
          );
          scheduler.dispose();
          incoming.close();
          time.flushMicrotasks();
        });
      }
    });
  });

  group('Inter-message pacing and attempt budget enforcement', () {
    final packet = Uint8List.fromList([0xF0, 0x7D, 1, 0xF7]);

    test('enforces messageInterval across idle sequential admissions and single timer', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        final sendTimes = <Duration>[];
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sendTimes.add(time.elapsed));

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
          messageInterval: const Duration(seconds: 1),
        );

        // First request transmits immediately at t=0.
        scheduler.sendRequest<void>(
          packet,
          RequestKey(sysExId: 0),
          responseExpectation: ResponseExpectation.none,
        );
        // Second arrives while idle at t=0 -> must wait full 1s cooldown.
        scheduler.sendRequest<void>(
          packet,
          RequestKey(sysExId: 0),
          responseExpectation: ResponseExpectation.none,
        );
        time.flushMicrotasks();
        expect(sendTimes, [Duration.zero]);

        // Third arrives at t=400ms during pending cooldown -> must NOT cancel timer.
        time.elapse(const Duration(milliseconds: 400));
        scheduler.sendRequest<void>(
          packet,
          RequestKey(sysExId: 0),
          responseExpectation: ResponseExpectation.none,
        );
        time.flushMicrotasks();
        expect(sendTimes, [Duration.zero]);

        // At t=1000ms, second sends; at t=2000ms, third sends.
        time.elapse(const Duration(milliseconds: 600));
        expect(sendTimes, [Duration.zero, const Duration(seconds: 1)]);
        time.elapse(const Duration(seconds: 1));
        expect(sendTimes, [
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ]);

        // Fourth arrives at t=3500ms (cooldown elapsed) -> sends immediately.
        time.elapse(const Duration(milliseconds: 1500));
        scheduler.sendRequest<void>(
          packet,
          RequestKey(sysExId: 0),
          responseExpectation: ResponseExpectation.none,
        );
        time.flushMicrotasks();
        expect(sendTimes, [
          Duration.zero,
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(milliseconds: 3500),
        ]);

        scheduler.dispose();
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test('maxRetries preserves total-attempt semantics (0->1, 1->1, 2->2) across timeout and split errors', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends = 0;
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sends++);

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
          messageInterval: Duration.zero,
        );

        // maxRetries: 0 -> 1 attempt
        scheduler.sendRequest<int>(
          _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
          RequestKey(
            sysExId: 0,
            messageType: DistingNTRespMessageType.respNumAlgorithms,
          ),
          responseExpectation: ResponseExpectation.optional,
          maxRetries: 0,
          timeout: const Duration(milliseconds: 20),
        );
        time.elapse(const Duration(milliseconds: 100));
        expect(sends, 1);

        // maxRetries: 2 -> 1 split error recovery + timeout = 2 total sends (not 3)
        sends = 0;
        Object? err;
        scheduler
            .sendRequest<int>(
              _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respNumAlgorithms,
              ),
              maxRetries: 2,
              timeout: const Duration(milliseconds: 20),
            )
            .then<void>((_) {}, onError: (Object e) => err = e);
        time.flushMicrotasks();
        incoming.add(
          MidiPacket(Uint8List.fromList([0xF0, 0, 0x21]), 0, device),
        );
        time.flushMicrotasks();
        incoming.addError(StateError('split error'));
        time.elapse(const Duration(milliseconds: 100));
        expect(sends, 2);
        expect(err, isA<TimeoutException>());

        scheduler.dispose();
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test(
      'strict settings query never exceeds 1 attempt on split stream error',
      () {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          var sends = 0;
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
              .thenAnswer((_) => sends++);

          final manager = DistingMidiManager(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );

          Object? error;
          manager
              .discoverModuleSettings(DistingRequestCancellation())
              .then<void>((_) {}, onError: (Object e) => error = e);
          time.flushMicrotasks();

          // Inject partial 0x63 response then stream error.
          final partial = ModuleSettingsCodec.packet(0, 0x63, [
            1,
            2,
          ]).sublist(0, 8);
          incoming.add(MidiPacket(Uint8List.fromList(partial), 0, device));
          time.flushMicrotasks();
          incoming.addError(StateError('USB hiccup'));
          time.elapse(const Duration(seconds: 5));
          time.flushMicrotasks();

          expect(sends, 1);
          expect(error, isA<StateError>());
          manager.dispose();
          incoming.close();
          time.flushMicrotasks();
        });
      },
    );

    test('delayed respAlgorithmInfo for index 5 never completes active request for index 6', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        final manager = DistingMidiManager(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
        );

        // Request A (libraryIndex 5) times out.
        Object? errA;
        manager
            .requestAlgorithmInfo(5)
            .then<void>((_) {}, onError: (Object e) => errA = e);
        time.elapse(const Duration(seconds: 2));
        time.flushMicrotasks();
        expect(errA, isA<TimeoutException>());

        // Request B (libraryIndex 6) is now active.
        AlgorithmInfo? resultB;
        manager.requestAlgorithmInfo(6).then((v) => resultB = v);
        time.flushMicrotasks();

        // Late reply for index 5 arrives -> MUST NOT complete index 6!
        incoming.add(
          MidiPacket(_algorithmInfoFrame(5, 'alg5', 'Algo 5'), 0, device),
        );
        time.flushMicrotasks();
        expect(resultB, isNull);

        // Actual reply for index 6 arrives -> completes B!
        incoming.add(
          MidiPacket(_algorithmInfoFrame(6, 'alg6', 'Algo 6'), 0, device),
        );
        time.flushMicrotasks();
        expect(resultB, isNotNull);
        expect(resultB!.algorithmIndex, 6);
        expect(resultB!.guid, 'alg6');

        manager.dispose();
        incoming.close();
        time.flushMicrotasks();
      });
    });
  });

  group('Mutation never-replay policy', () {
    test(
      'executeLua and installLua with silent optional output send exactly once',
      () {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          var sends = 0;
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
              .thenAnswer((_) => sends++);

          final manager = DistingMidiManager(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );

          var execDone = false;
          manager.executeLua('x = (x or 0) + 1').then((v) {
            expect(v, isNull);
            execDone = true;
          });
          time.elapse(const Duration(minutes: 1));
          time.flushMicrotasks();
          expect(execDone, isTrue);
          expect(sends, 1);

          sends = 0;
          var installDone = false;
          manager.installLua(0, 'return {}').then((v) {
            expect(v, isNull);
            installDone = true;
          });
          time.elapse(const Duration(minutes: 1));
          time.flushMicrotasks();
          expect(installDone, isTrue);
          expect(sends, 1);

          manager.dispose();
          incoming.close();
          time.flushMicrotasks();
        });
      },
    );

    test('ambiguous send throw never replays any live mutator', () {
      final sampleAlgo = AlgorithmInfo(
        algorithmIndex: 0,
        guid: 'clck',
        name: 'Clock',
        specifications: const [],
      );
      final mutations = <String, Future<Object?> Function(DistingMidiManager)>{
        'requestNewPreset': (m) => m.requestNewPreset(),
        'requestSavePreset': (m) => m.requestSavePreset(),
        'requestLoadPreset': (m) =>
            m.requestLoadPreset('/presets/a.json', false),
        'requestSetPresetName': (m) => m.requestSetPresetName('Test'),
        'requestAddAlgorithm': (m) =>
            m.requestAddAlgorithm(sampleAlgo, const []),
        'requestRemoveAlgorithm': (m) => m.requestRemoveAlgorithm(0),
        'requestRespecifyAlgorithm': (m) =>
            m.requestRespecifyAlgorithm(0, const [1]),
        'requestMoveAlgorithmUp': (m) => m.requestMoveAlgorithmUp(1),
        'requestMoveAlgorithmDown': (m) => m.requestMoveAlgorithmDown(0),
        'requestLoadPlugin': (m) => m.requestLoadPlugin('PLUG'),
        'requestSetFocus': (m) => m.requestSetFocus(0, 1),
        'setParameterValue': (m) => m.setParameterValue(0, 1, 42),
        'setParameterString': (m) => m.setParameterString(0, 1, 'hi'),
        'requestSendSlotName': (m) => m.requestSendSlotName(0, 'S0'),
        'requestSetDisplayMode': (m) =>
            m.requestSetDisplayMode(DisplayMode.algorithmUI),
        'requestSetRealTimeClock': (m) => m.requestSetRealTimeClock(1700000000),
        'setRealTimeClock': (m) => m.setRealTimeClock(1700000000),
        'requestWake': (m) => m.requestWake(),
        'requestReboot': (m) => m.requestReboot(),
        'requestEnterBootloader': (m) => m.requestEnterBootloader(),
        'setPerformancePageMapping': (m) =>
            m.setPerformancePageMapping(0, 1, 2),
        'requestSetAlgorithmVisualStyle': (m) =>
            m.requestSetAlgorithmVisualStyle(0, const AlgorithmVisualStyle()),
        'setPerfPageItem': (m) => m.setPerfPageItem(
          const PerformancePageItem(
            itemIndex: 0,
            enabled: true,
            slotIndex: 0,
            parameterNumber: 0,
            min: 0,
            max: 100,
            upperLabel: 'A',
            lowerLabel: 'B',
          ),
        ),
        'requestSclFile': (m) => m.requestSclFile('/scl/a.scl'),
        'requestKbmFile': (m) => m.requestKbmFile('/scl/a.kbm'),
        'executeLua': (m) => m.executeLua('return 1'),
        'installLua': (m) => m.installLua(0, 'return 1'),
      };

      for (final entry in mutations.entries) {
        fakeAsync((time) {
          final midi = _FakeMidi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'dev',
            'Disting NT',
            MidiDeviceType.serial,
            true,
          );
          var sends = 0;
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
              .thenAnswer((_) {
                sends++;
                throw StateError('may have been transmitted');
              });

          final manager = DistingMidiManager(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );

          Object? error;
          entry
              .value(manager)
              .then<void>((_) {}, onError: (Object e) => error = e);
          time.elapse(const Duration(seconds: 5));
          time.flushMicrotasks();

          expect(sends, 1, reason: '${entry.key} must never replay');
          expect(
            error,
            isA<StateError>(),
            reason: '${entry.key} must surface error',
          );
          manager.dispose();
          incoming.close();
          time.flushMicrotasks();
        });
      }

      // Also verify requestSetMapping (3 fire-and-forget packets -> 1 attempt each)
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends = 0;
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {
              sends++;
              throw StateError('may have sent');
            });

        final manager = DistingMidiManager(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
        );

        Object? error;
        manager
            .requestSetMapping(0, 0, PackedMappingData.filler())
            .then<void>((_) {}, onError: (Object e) => error = e);
        time.elapse(const Duration(seconds: 5));
        time.flushMicrotasks();

        expect(sends, 3);
        expect(error, isA<StateError>());
        manager.dispose();
        incoming.close();
        time.flushMicrotasks();
      });
    });
  });

  group('Session-loss quarantine lineage and bounded memory', () {
    test('session-loss debt persists across MidiCommand and endpoint ID replacement, never expires by time, isolates unaffected classes, and drains on late reply', () {
      fakeAsync((time) {
        final lineage = ResponseAttributionTracker();

        // Session 1 on MidiCommand A + endpoint id-1
        final midi1 = _FakeMidi();
        final incoming1 = StreamController<MidiPacket>.broadcast();
        final device1 = MidiDevice(
          'id-1',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi1.onMidiPacketReceived)
            .thenAnswer((_) => incoming1.stream);
        when(() => midi1.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        final sched1 = DistingMessageScheduler(
          midiCommand: midi1,
          inputDevice: device1,
          outputDevice: device1,
          sysExId: 0,
          attributionTracker: lineage,
        );

        // Start a best-effort preset-name read and lose the session while in-flight.
        Object? lostError;
        sched1
            .sendRequest<String>(
              _sysEx(DistingNTRespMessageType.respPresetName, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respPresetName,
              ),
            )
            .then<void>((_) {}, onError: (Object e) => lostError = e);
        time.flushMicrotasks();

        sched1.markConnectionLost();
        time.flushMicrotasks();
        expect(
          lostError,
          isA<DistingSchedulerClosedException>().having(
            (e) => e.phase,
            'phase',
            RequestFailurePhase.inFlight,
          ),
        );
        expect(lineage.totalDebtCount, 1);

        // Advance time by 10 minutes — elapsed time MUST NOT clear debt.
        time.elapse(const Duration(minutes: 10));
        expect(lineage.totalDebtCount, 1);

        // Session 2 on NEW MidiCommand B + CHANGED endpoint id-2 sharing lineage.
        final midi2 = _FakeMidi();
        final incoming2 = StreamController<MidiPacket>.broadcast();
        final device2 = MidiDevice(
          'id-2',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        var sends2 = 0;
        when(() => midi2.onMidiPacketReceived)
            .thenAnswer((_) => incoming2.stream);
        when(() => midi2.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) => sends2++);

        final sched2 = DistingMessageScheduler(
          midiCommand: midi2,
          inputDevice: device2,
          outputDevice: device2,
          sysExId: 0,
          attributionTracker: lineage,
        );

        final observed = <DistingNTParsedMessage>[];
        sched2.addMessageObserver(observed.add);

        // Affected class (respPresetName) fails closed BEFORE sending.
        Object? blockedError;
        sched2
            .sendRequest<String>(
              _sysEx(DistingNTRespMessageType.respPresetName, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respPresetName,
              ),
            )
            .then<void>((_) {}, onError: (Object e) => blockedError = e);
        time.flushMicrotasks();
        expect(blockedError, isA<AmbiguousResponseAttributionException>());
        expect(sends2, 0);

        // Independent unaffected class (respNumAlgorithms) succeeds immediately!
        int? numAlgos;
        sched2
            .sendRequest<int>(
              _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respNumAlgorithms,
              ),
            )
            .then((v) => numAlgos = v);
        time.flushMicrotasks();
        expect(sends2, 1);
        incoming2.add(
          MidiPacket(
            _sysEx(DistingNTRespMessageType.respNumAlgorithms, [0, 0, 12]),
            0,
            device2,
          ),
        );
        time.flushMicrotasks();
        expect(numAlgos, 12);
        expect(observed, hasLength(1));

        // Late old preset-name reply arrives on Session 2 -> drains debt
        // WITHOUT notifying passive observers!
        incoming2.add(
          MidiPacket(
            _sysEx(DistingNTRespMessageType.respPresetName, [
              ...'OLD'.codeUnits,
              0,
            ]),
            0,
            device2,
          ),
        );
        time.flushMicrotasks();
        expect(lineage.totalDebtCount, 0);
        expect(observed, hasLength(1));

        // Now fresh preset-name read succeeds (after the 50ms pacing cooldown)!
        String? freshName;
        sched2
            .sendRequest<String>(
              _sysEx(DistingNTRespMessageType.respPresetName, const []),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respPresetName,
              ),
            )
            .then((v) => freshName = v);
        time.elapse(const Duration(milliseconds: 50));
        incoming2.add(
          MidiPacket(
            _sysEx(DistingNTRespMessageType.respPresetName, [
              ...'NEW'.codeUnits,
              0,
            ]),
            0,
            device2,
          ),
        );
        time.flushMicrotasks();
        expect(freshName, 'NEW');

        sched1.dispose();
        sched2.dispose();
        incoming1.close();
        incoming2.close();
        time.flushMicrotasks();
      });
    });

    test('expired handler list is capped deterministically even without unmatched messages', () {
      fakeAsync((time) {
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        final scheduler = DistingMessageScheduler(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 0,
          messageInterval: Duration.zero,
        );

        for (var i = 0; i < 30; i++) {
          scheduler.sendRequest<int>(
            _sysEx(DistingNTRespMessageType.respNumAlgorithms, const []),
            RequestKey(
              sysExId: 0,
              messageType: DistingNTRespMessageType.respNumAlgorithms,
            ),
            responseExpectation: ResponseExpectation.optional,
            maxRetries: 1,
            timeout: const Duration(milliseconds: 10),
          );
          time.elapse(const Duration(milliseconds: 15));
        }

        expect(
          scheduler.getDiagnostics()['expiredHandlerCount'],
          lessThanOrEqualTo(20),
        );
        scheduler.dispose();
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test('overflowing distinct debt keys collapses to bounded uncertain domain without dropping safety evidence', () {
      fakeAsync((time) {
        final lineage = ResponseAttributionTracker();
        final midi = _FakeMidi();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'dev',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        // Exceed the 512 distinct-key cap via session-loss debts on distinct library indices.
        for (var i = 0; i < 520; i++) {
          final sched = DistingMessageScheduler(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
            attributionTracker: lineage,
          );
          sched
              .sendRequest<AlgorithmInfo>(
                _sysEx(DistingNTRespMessageType.respAlgorithmInfo, encode16(i)),
                RequestKey(
                  sysExId: 0,
                  messageType: DistingNTRespMessageType.respAlgorithmInfo,
                  libraryIndex: i,
                ),
              )
              .ignore();
          time.flushMicrotasks();
          sched.markConnectionLost();
          sched.dispose();
        }

        expect(lineage.hasUncertainDomains, isTrue);
        // Any respAlgorithmInfo on sysExId 0 is conservatively quarantined;
        // unaffected message types remain open.
        expect(
          lineage.hasSessionLossDebt(
            RequestKey(
              sysExId: 0,
              messageType: DistingNTRespMessageType.respAlgorithmInfo,
              libraryIndex: 999,
            ),
          ),
          isTrue,
        );
        expect(
          lineage.hasSessionLossDebt(
            RequestKey(
              sysExId: 0,
              messageType: DistingNTRespMessageType.respPresetName,
            ),
          ),
          isFalse,
        );
        incoming.close();
        time.flushMicrotasks();
      });
    });

    test('late old reply during retry backoff never completes replacement strict read or passive observer', () {
      fakeAsync((time) {
        final lineage = ResponseAttributionTracker();
        final midi1 = _FakeMidi();
        final incoming1 = StreamController<MidiPacket>.broadcast();
        final device1 = MidiDevice(
          'id-1',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi1.onMidiPacketReceived)
            .thenAnswer((_) => incoming1.stream);
        when(() => midi1.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        // Session 1: ordinary 0x40 read times out cleanly (records normal best-effort 0x40 debt).
        final sched1 = DistingMessageScheduler(
          midiCommand: midi1,
          inputDevice: device1,
          outputDevice: device1,
          sysExId: 0,
          attributionTracker: lineage,
        );
        sched1
            .sendRequest<Algorithm>(
              _sysEx(DistingNTRespMessageType.respAlgorithm, [2]),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respAlgorithm,
                algorithmIndex: 2,
              ),
              maxRetries: 1,
              timeout: const Duration(milliseconds: 20),
            )
            .ignore();
        time.elapse(const Duration(milliseconds: 25));
        sched1.dispose();

        // Session 2 on replacement MidiCommand starts strict 0x40 read with retryDelay.
        final midi2 = _FakeMidi();
        final incoming2 = StreamController<MidiPacket>.broadcast();
        final device2 = MidiDevice(
          'id-2',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        );
        when(() => midi2.onMidiPacketReceived)
            .thenAnswer((_) => incoming2.stream);
        when(() => midi2.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((_) {});

        final sched2 = DistingMessageScheduler(
          midiCommand: midi2,
          inputDevice: device2,
          outputDevice: device2,
          sysExId: 0,
          attributionTracker: lineage,
        );
        final observed = <DistingNTParsedMessage>[];
        sched2.addMessageObserver(observed.add);

        Object? strictErr;
        sched2
            .sendRequest<Algorithm>(
              _sysEx(DistingNTRespMessageType.respAlgorithm, [2]),
              RequestKey(
                sysExId: 0,
                messageType: DistingNTRespMessageType.respAlgorithm,
                algorithmIndex: 2,
              ),
              maxRetries: 2,
              timeout: const Duration(milliseconds: 20),
              retryDelay: const Duration(milliseconds: 100),
              attributionPolicy:
                  ResponseAttributionPolicy.rejectAmbiguousResponse,
            )
            .then<void>((_) {}, onError: (Object e) => strictErr = e);

        // Attempt 1 times out at 20ms -> now waiting inside 100ms retry backoff!
        time.elapse(const Duration(milliseconds: 40));
        expect(strictErr, isNull);

        // Late old 0x40 reply arrives during retry backoff -> MUST reject strict read
        // and MUST NOT reach passive observers!
        incoming2.add(
          MidiPacket(
            _sysEx(DistingNTRespMessageType.respAlgorithm, [
              2,
              ...'TEST'.codeUnits,
              ...'Slot'.codeUnits,
              0,
            ]),
            0,
            device2,
          ),
        );
        time.flushMicrotasks();
        expect(strictErr, isA<AmbiguousResponseAttributionException>());
        expect(observed, isEmpty);

        sched2.dispose();
        incoming1.close();
        incoming2.close();
        time.flushMicrotasks();
      });
    });
  });
}
