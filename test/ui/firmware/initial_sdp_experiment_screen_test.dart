import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/initial_sdp_transport.dart';
import 'package:nt_helper/ui/firmware/initial_sdp_experiment_screen.dart';

import '../../test_helpers/mock_midi_command.dart';

class _DistingCubit extends MockCubit<DistingState> implements DistingCubit {}

class _Transport implements InitialSdpTransport {
  final observations = StreamController<Map<String, dynamic>>(
    onCancel: () async {},
  );
  final calls = <String>[];
  Map<String, dynamic> prerequisites = {'isIPad': true, 'osEligible': true};
  Object? availabilityError;
  Object? observeError;
  final connection = Completer<void>();
  final reply = Completer<InitialSdpResponse>();

  @override
  Stream<Map<String, dynamic>> get events => observations.stream;
  @override
  Future<Map<String, dynamic>> availability() async {
    calls.add('availability');
    if (availabilityError != null) throw availabilityError!;
    return prerequisites;
  }

  @override
  Future<void> observe() async {
    calls.add('observe');
    if (observeError != null) throw observeError!;
  }

  @override
  Future<void> connect() {
    calls.add('connect');
    return connection.future;
  }

  @override
  Future<InitialSdpResponse> errorStatus() {
    calls.add('errorStatus');
    return reply.future;
  }

  @override
  Future<void> close() async {
    calls.add('close');
  }

  void detected() => observations.add({
    'stage': 'detected',
    'vendorId': 0x1fc9,
    'productId': 0x0135,
  });
}

class _Harness {
  final cubit = _DistingCubit();
  final midi = MockMidiCommand();
  final transport = _Transport();
  final input = MidiDevice(
    'selected-input',
    'Selected NT input',
    MidiDeviceType.serial,
    true,
  );
  final output = MidiDevice(
    'selected-output',
    'Selected NT output',
    MidiDeviceType.serial,
    true,
  );
  final packets = <List<int>>[];
  final destinations = <String?>[];
  final ownership = <String>[];
  late DistingMidiManager manager;
  late DistingState current;

  _Harness({
    String version = '1.15.0',
    bool demo = false,
    bool offline = false,
    bool synchronized = true,
  }) {
    when(
      () => midi.onMidiPacketReceived,
    ).thenAnswer((_) => const Stream<MidiPacket>.empty());
    when(
      () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
    ).thenAnswer((invocation) {
      packets.add(
        List<int>.from(invocation.positionalArguments.single as Uint8List),
      );
      destinations.add(invocation.namedArguments[#deviceId] as String?);
      ownership.add('request');
    });
    manager = DistingMidiManager(
      midiCommand: midi,
      inputDevice: input,
      outputDevice: output,
      sysExId: 17,
    );
    current = synchronized
        ? DistingState.synchronized(
            disting: manager,
            distingVersion: version,
            firmwareVersion: FirmwareVersion(version),
            presetName: 'Test',
            algorithms: const [],
            slots: const [],
            unitStrings: const [],
            inputDevice: input,
            outputDevice: output,
            demo: demo,
            offline: offline,
          )
        : const DistingState.initial();
    when(() => cubit.state).thenAnswer((_) => current);
    when(
      () => cubit.stream,
    ).thenAnswer((_) => const Stream<DistingState>.empty());
    when(
      () => cubit.disposeFirmwareMidiManager(manager, input, output),
    ).thenAnswer((_) {
      ownership.add('release');
      manager.dispose();
      current = const DistingState.initial();
    });
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: InitialSdpExperimentScreen(
          distingCubit: cubit,
          dependencies: InitialSdpExperimentScreenDependencies(
            transport: transport,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FilledButton, 'Request bootloader and read status'),
    );
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    manager.dispose();
    unawaited(transport.observations.close());
  }
}

List<Rect> _geometry(WidgetTester tester) => [
  for (final key in ['sdp-progress-slot', 'sdp-status-slot', 'sdp-action-slot'])
    tester.getRect(find.byKey(ValueKey(key))),
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<Object?> announcements;
  setUp(() {
    announcements = [];
    binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        announcements.add(message);
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      null,
    );
  });
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  // Existing desktop handoff tests continue into flashing and never exercise
  // the experiment's real controller, native receipts, semantics or geometry.
  testWidgets(
    'ac-002/ac-003/ac-005: explicit selected identity and four independent accessible receipts keep geometry fixed',
    (tester) async {
      final h = _Harness();
      final semantics = tester.ensureSemantics();
      await h.pump(tester);
      final geometry = _geometry(tester);
      expect(h.packets, isEmpty);
      expect(h.transport.calls, isEmpty);
      expect(h.ownership, isEmpty);
      expect(find.bySemanticsLabel('Initial SDP experiment'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Initial SDP experiment')),
        matchesSemantics(isHeader: true, label: 'Initial SDP experiment'),
      );
      await h.start(tester);
      expect(h.packets, [
        [0xf0, 0, 0x21, 0x27, 0x6d, 17, 0x7f, 0x7f, 0xf7],
      ]);
      expect(h.destinations, [h.output.id]);
      expect(h.ownership, ['request', 'release']);
      await h.pump(
        tester,
      ); // A route rebuild after MIDI handoff keeps its baseline.
      expect(
        find.textContaining(
          'Selected NT input → Selected NT output; firmware 1.15.0',
        ),
        findsOneWidget,
      );
      verify(
        () => h.cubit.disposeFirmwareMidiManager(h.manager, h.input, h.output),
      ).called(1);
      verifyNever(
        () => h.cubit.createFirmwareMidiManager(h.input, h.output, 17),
      );
      expect(
        find.bySemanticsLabel('Bootloader request sent: confirmed'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Initial SDP experiment in progress'),
        findsOneWidget,
      );
      expect(_geometry(tester), geometry);
      // MIDI loss is deliberately not a USB observation, even after elapsed time.
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.bySemanticsLabel('Observed initial USB 1FC9:0135: not confirmed'),
        findsOneWidget,
      );
      h.transport.detected();
      await tester.pump();
      expect(h.transport.calls, ['availability', 'observe', 'connect']);
      expect(
        find.bySemanticsLabel('Observed initial USB 1FC9:0135: confirmed'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Driver connected: not confirmed'),
        findsOneWidget,
      );
      h.transport.connection.complete();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Driver connected: confirmed'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Decoded SDP response received: not confirmed'),
        findsOneWidget,
      );
      expect(_geometry(tester), geometry);
      h.transport.reply.complete(
        const InitialSdpResponse(hab: 0x56787856, status: 0xf0f0f0f0),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('Decoded SDP response received: confirmed'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Status 0xf0f0f0f0; HAB 0x56787856'),
        findsOneWidget,
      );
      expect(_geometry(tester), geometry);
      await tester.pump();
      expect(h.transport.calls, [
        'availability',
        'observe',
        'connect',
        'errorStatus',
        'close',
      ]);
      expect(h.transport.observations.hasListener, isFalse);
      expect(announcements.toString(), contains('Bootloader request sent'));
      expect(announcements.toString(), contains('Driver connected'));
      expect(
        announcements.toString(),
        contains('Decoded SDP error-status response received'),
      );
      final statusSemantics = tester.getSemantics(
        find.byKey(const ValueKey('sdp-live-status')),
      );
      expect(
        statusSemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
      );
      await h.dispose(tester);
      semantics.dispose();
    },
  );

  // Firmware message encoding tests do not prove UI eligibility or ownership.
  for (final scenario in [
    'unsupported',
    'unknown',
    'misleading version',
    'demo',
    'offline',
    'not live',
  ]) {
    testWidgets(
      'ac-002: $scenario rejects bootloader entry without consuming MIDI',
      (tester) async {
        final h = _Harness(
          version: scenario == 'unsupported'
              ? '1.14.0'
              : scenario == 'unknown'
              ? 'Unknown'
              : scenario == 'misleading version'
              ? 'Unknown 1.19'
              : '1.15.0',
          demo: scenario == 'demo',
          offline: scenario == 'offline',
          synchronized: scenario != 'not live',
        );
        await h.pump(tester);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.textContaining('Prerequisite:'), findsOneWidget);
        expect(h.packets, isEmpty);
        expect(h.ownership, isEmpty);
        expect(h.transport.calls, isEmpty);
        await h.dispose(tester);
      },
    );
  }

  // Existing firmware tests lack native failures and must not promote detection
  // or a native notification into a decoded command response.
  for (final scenario in [
    'unavailable',
    'disabled',
    'missing channel',
    'observation failure',
    'missing transition',
    'connection failure',
    'connection timeout',
    'disconnect',
    'malformed query',
    'failed query',
    'query timeout',
  ]) {
    testWidgets(
      'ac-003/ac-005: $scenario reports its stage, cleans resources and never reports communication',
      (tester) async {
        final h = _Harness();
        if (scenario == 'unavailable') {
          h.transport.prerequisites['available'] = false;
        }
        if (scenario == 'disabled') {
          h.transport.prerequisites['driverEnabled'] = false;
        }
        if (scenario == 'missing channel') {
          h.transport.availabilityError = MissingPluginException();
        }
        if (scenario == 'observation failure') {
          h.transport.observeError = PlatformException(
            code: 'availability',
            message: 'Observation registration failed',
          );
        }
        await h.pump(tester);
        final geometry = _geometry(tester);
        await h.start(tester);
        String stage;
        if (['unavailable', 'disabled', 'missing channel'].contains(scenario)) {
          stage = 'Driver availability';
          expect(h.packets, isEmpty);
          expect(h.ownership, isEmpty);
        } else if (scenario == 'observation failure') {
          stage = 'Detection';
        } else if (scenario == 'missing transition') {
          // Neither elapsed time, MIDI disappearance nor unsolicited native
          // connection/response notifications can replace the observed identity.
          h.transport.observations.add({'stage': 'connected'});
          h.transport.observations.add({
            'stage': 'response',
            'status': 0,
            'hab': 0,
          });
          await tester.pump(const Duration(seconds: 21));
          stage = 'Detection';
          expect(h.transport.calls, isNot(contains('connect')));
        } else {
          h.transport.detected();
          await tester.pump();
          if (scenario == 'connection failure') {
            h.transport.connection.completeError(
              PlatformException(
                code: 'connection',
                message: 'IOServiceOpen failed',
              ),
            );
            stage = 'Driver connection';
          } else if (scenario == 'connection timeout') {
            await tester.pump(const Duration(seconds: 11));
            stage = 'Driver connection';
          } else if (scenario == 'disconnect') {
            h.transport.observations.add({'stage': 'disconnected'});
            stage = 'Disconnect';
          } else {
            h.transport.connection.complete();
            await tester.pump();
            if (scenario == 'malformed query') {
              h.transport.reply.completeError(
                const FormatException('Malformed initial SDP status response'),
              );
            } else if (scenario == 'failed query') {
              h.transport.reply.completeError(
                PlatformException(
                  code: 'query',
                  message: 'Status transfer failed',
                ),
              );
            } else {
              await tester.pump(const Duration(seconds: 11));
            }
            stage = 'SDP query';
          }
        }
        await tester.pump();
        expect(find.textContaining('$stage failed:'), findsOneWidget);
        expect(announcements.toString(), contains('$stage failed:'));
        expect(
          find.textContaining('Decoded SDP error-status response received.'),
          findsNothing,
        );
        expect(_geometry(tester), geometry);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        await tester.pump();
        expect(h.transport.calls.where((c) => c == 'close').length, 1);
        expect(h.transport.observations.hasListener, isFalse);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        await h.dispose(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // Desktop tests do not protect cancellation while iPad connection is pending.
  testWidgets(
    'ac-005: closing pending connection cleans up and ignores late receipts with keyboard access intact',
    (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final actionFocus = Focus.of(
        tester.element(find.text('Request bootloader and read status')),
      );
      actionFocus.requestFocus();
      await tester.pump();
      expect(actionFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.ownership, ['request', 'release']);
      final closeFocus = Focus.of(
        tester.element(find.text('Close experiment')),
      );
      closeFocus.requestFocus();
      await tester.pump();
      expect(closeFocus.hasFocus, isTrue);
      h.transport.detected();
      await tester.pump();
      await h.dispose(tester);
      h.transport.connection.complete();
      await tester.pump();
      await tester.pump();
      expect(h.transport.calls, [
        'availability',
        'observe',
        'connect',
        'close',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  // Availability is asynchronous; prior desktop checks do not cover a changed
  // live selection before the experiment's explicit request.
  testWidgets(
    'ac-002: stale live selection is rejected at the action boundary',
    (tester) async {
      final h = _Harness();
      await h.pump(tester);
      h.current = const DistingState.initial();
      await h.start(tester);
      expect(find.textContaining('Prerequisite failed:'), findsOneWidget);
      expect(h.packets, isEmpty);
      expect(h.ownership, isEmpty);
      await h.dispose(tester);
    },
  );
}
