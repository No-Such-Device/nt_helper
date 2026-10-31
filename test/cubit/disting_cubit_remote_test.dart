import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/mock_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:nt_helper/models/remote_control_state.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/remote_wire_harness.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _NonLiveManager extends Mock implements IDistingMidiManager {}

DistingState synchronized(
  IDistingMidiManager manager, {
  String version = '1.19.0',
  bool demo = false,
  bool offline = false,
}) => DistingState.synchronized(
  disting: manager,
  distingVersion: version,
  firmwareVersion: FirmwareVersion(version),
  presetName: 'Remote wire test',
  algorithms: const [],
  slots: const [],
  unitStrings: const [],
  demo: demo,
  offline: offline,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  late RemoteWireHarness wire;
  late DistingCubit cubit;
  var closed = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 1000,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
    wire = RemoteWireHarness();
    final database = _Database();
    final metadata = _Metadata();
    when(() => database.metadataDao).thenReturn(metadata);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    cubit = DistingCubit(
      database,
      midiCommand: wire.midi,
      isWindowsOverride: true,
    );
    cubit.emit(synchronized(wire.manager));
    closed = false;
  });
  tearDown(() async {
    if (!closed) await cubit.close();
    await wire.close();
  });

  test(
    'opening, rebuilding and pressing alone never writes a pot; independent holds deduplicate',
    () async {
      final session = cubit.openRemoteSession();
      final initial = cubit.remoteControlState;
      expect(initial.available, isTrue);
      expect(initial.potValues, [2048, 2048, 2048]);
      cubit.emit(
        (cubit.state as DistingStateSynchronized).copyWith(loading: true),
      );
      expect(cubit.remoteControlState.sessionId, session);
      expect(wire.remotePackets, isEmpty);
      await cubit.sendRemoteAction(session, const RemotePush(3));
      await cubit.sendRemoteAction(session, const RemotePush(3));
      await cubit.sendRemoteAction(session, const RemotePush(4));
      expect(cubit.remoteControlState.heldControls, {3, 4});
      await cubit.sendRemoteAction(session, const RemoteEncoderTurn(0, 1));
      expect(cubit.remoteControlState.heldControls, {3, 4});
      await cubit.sendRemoteAction(session, const RemoteRelease(3));
      await cubit.sendRemoteAction(session, const RemoteRelease(3));
      expect(cubit.remoteControlState.heldControls, {4});
      await cubit.closeRemoteSession(session);
      await cubit.closeRemoteSession(session);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([1, 4]),
        remoteFrame([3, 0, 1]),
        remoteFrame([2, 3]),
        remoteFrame([2, 4]),
      ]);
      expect(initial.heldControls, isEmpty);
      expect(() => initial.potValues[0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'local pot inputs retain across host sessions, clamp and reset only on new connection',
    () async {
      var session = cubit.openRemoteSession();
      await cubit.adjustRemotePot(session, 0, 32);
      await cubit.adjustRemotePot(session, 1, -32);
      await cubit.adjustRemotePot(session, 2, 24);
      expect(cubit.remoteControlState.potValues, [2080, 2016, 2072]);
      expect(wire.remotePackets, [
        remoteFrame([4, 0, 0x20, 0x10]),
        remoteFrame([4, 1, 0x60, 0x0F]),
        remoteFrame([4, 2, 0x18, 0x10]),
      ]);
      await cubit.closeRemoteSession(session);
      session = cubit.openRemoteSession();
      cubit.emit(
        (cubit.state as DistingStateSynchronized).copyWith(
          presetName: 'Rebuilt',
        ),
      );
      expect(cubit.remoteControlState.potValues, [2080, 2016, 2072]);
      expect(wire.remotePackets, hasLength(3));
      await cubit.adjustRemotePot(session, 0, 32);
      await cubit.adjustRemotePot(session, 1, -10000);
      await cubit.adjustRemotePot(session, 2, 10000);
      await cubit.adjustRemotePot(session, 2, 1);
      expect(cubit.remoteControlState.potValues, [2112, 0, 4095]);
      expect(wire.remotePackets.last, remoteFrame([4, 2, 127, 31]));
      final previousConnection = cubit.remoteControlState.connectionId;
      cubit.emit(synchronized(wire.replaceManager()));
      expect(cubit.remoteControlState.connectionId, isNot(previousConnection));
      expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
      expect(cubit.remoteControlState.sessionId, isNull);
      await expectLater(
        cubit.adjustRemotePot(session, 0, 32),
        throwsStateError,
      );
      expect(wire.remotePackets, hasLength(6));
    },
  );

  test(
    'main authority rejects invalid indices and pot ranges without changing input or writing',
    () async {
      final session = cubit.openRemoteSession();
      for (final action in const [
        RemotePush(-1),
        RemotePush(9),
        RemoteRelease(9),
        RemoteEncoderTurn(2, 20),
        RemotePotTurn(3, 0),
        RemotePotTurn(0, -1),
        RemotePotTurn(0, 4096),
      ]) {
        await expectLater(
          cubit.sendRemoteAction(session, action),
          throwsRangeError,
        );
      }
      await expectLater(
        cubit.adjustRemotePot(session, -1, 32),
        throwsRangeError,
      );
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
      expect(wire.remoteAttempts, isEmpty);
    },
  );

  test(
    'authority serializes rapid mixed actions and split encoder movement',
    () async {
      final session = cubit.openRemoteSession();
      final expected = <List<int>>[];
      final requests = <Future<void>>[];
      for (var i = 0; i < 50; i++) {
        requests.add(cubit.sendRemoteAction(session, const RemotePush(3)));
        requests.add(
          cubit.sendRemoteAction(session, const RemoteEncoderTurn(0, 130)),
        );
        requests.add(cubit.adjustRemotePot(session, 0, 1));
        requests.add(cubit.sendRemoteAction(session, const RemoteRelease(3)));
        expected.addAll([
          remoteFrame([1, 3]),
          remoteFrame([3, 0, 63]),
          remoteFrame([3, 0, 63]),
          remoteFrame([3, 0, 4]),
          remoteFrame([4, 0, i + 1, 16]),
          remoteFrame([2, 3]),
        ]);
      }
      await Future.wait(requests);
      expect(wire.remotePackets, expected);
      expect(cubit.remoteControlState.pending, isFalse);
      expect(cubit.remoteControlState.potValues, [2098, 2048, 2048]);
    },
  );

  test(
    'closing cancels unsent host work without cancelling an unrelated request',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      await cubit.sendRemoteAction(session, const RemotePush(7));
      final version = wire.manager.requestVersionString();
      final turn = cubit.sendRemoteAction(
        session,
        const RemoteEncoderTurn(0, 5),
      );
      final cancelled = expectLater(
        turn,
        throwsA(isA<DistingRequestCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final cleanup = cubit.closeRemoteSession(session);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(cubit.remoteControlState.sessionId, isNull);
      wire.injectVersion();
      await cancelled;
      expect(await version, '1.19.0');
      await cleanup;
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([1, 7]),
        remoteFrame([2, 3]),
        remoteFrame([2, 7]),
      ]);
      await expectLater(
        cubit.sendRemoteAction(session, const RemotePush(0)),
        throwsStateError,
      );
    },
  );

  test(
    'a host replaced before queue execution cannot write, or overwrite the new host',
    () async {
      final old = cubit.openRemoteSession();
      final pending = cubit.sendRemoteAction(old, const RemotePush(0));
      final rejected = expectLater(pending, throwsStateError);
      final replacement = cubit.openRemoteSession();
      await rejected;
      await cubit.sendRemoteAction(replacement, const RemotePush(8));
      await expectLater(
        cubit.sendRemoteAction(old, const RemotePotTurn(0, 0)),
        throwsStateError,
      );
      expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
      expect(cubit.remoteControlState.heldControls, {8});
      expect(wire.remotePackets, [
        remoteFrame([1, 8]),
      ]);
    },
  );

  test('cleanup captures a push sent just before the host closes', () async {
    final session = cubit.openRemoteSession();
    late Future<void> cleanup;
    wire.onSend = (packet) {
      if (packet[6] == 0x78 && packet[7] == 1) {
        scheduleMicrotask(() => cleanup = cubit.closeRemoteSession(session));
      }
    };
    await cubit.sendRemoteAction(session, const RemotePush(6));
    await cleanup;
    expect(wire.remotePackets, [
      remoteFrame([1, 6]),
      remoteFrame([2, 6]),
    ]);
    expect(cubit.remoteControlState.heldControls, isEmpty);
  });

  test(
    'replacement cancels old queued turns and cleanup; nothing replays on the new manager',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      final version = wire.manager.requestVersionString();
      final turn = cubit.sendRemoteAction(
        session,
        const RemoteEncoderTurn(0, 5),
      );
      final cancelled = expectLater(
        turn,
        throwsA(isA<DistingRequestCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      final cleanup = cubit.closeRemoteSession(session);
      cubit.emit(synchronized(wire.replaceManager()));
      await cancelled;
      await cleanup;
      wire.injectVersion();
      expect(await version, '1.19.0');
      final replacement = cubit.openRemoteSession();
      await cubit.sendRemoteAction(replacement, const RemoteEncoderTurn(1, -5));
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([3, 1, 123]),
      ]);
      expect(cubit.remoteControlState.error, isNull);
    },
  );

  test(
    'disconnect cancels before manager disposal and leaves no reattach path',
    () async {
      final session = cubit.openRemoteSession();
      final version = wire.manager.requestVersionString();
      final versionDisposed = expectLater(version, throwsStateError);
      final push = cubit.sendRemoteAction(session, const RemotePush(0));
      final cancelled = expectLater(
        push,
        throwsA(isA<DistingRequestCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      cubit.disconnect();
      await versionDisposed;
      await cancelled;
      expect(cubit.remoteControlState.available, isFalse);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(() => cubit.openRemoteSession(), throwsStateError);
      expect(wire.remoteAttempts, isEmpty);
      cubit.emit(synchronized(wire.replaceManager()));
      expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
      expect(cubit.remoteControlState.available, isTrue);
    },
  );

  test(
    'conservative firmware and live-manager gates expose reasons and never write',
    () async {
      for (final version in [
        '1.19beta',
        '1.19.0beta',
        '1.19.0-beta.2',
        '1.19.0',
        '1.20.0',
        '2.0.0',
      ]) {
        cubit.emit(synchronized(wire.manager, version: version));
        expect(cubit.remoteControlState.available, isTrue, reason: version);
      }
      final old = cubit.openRemoteSession();
      final cases = <DistingState>[
        for (final version in [
          '',
          'unknown',
          'build 2026 firmware 1.19',
          '1.19garbage',
          '1.18.99',
          '1.18beta',
        ])
          synchronized(wire.manager, version: version),
        synchronized(wire.manager, demo: true),
        synchronized(wire.manager, offline: true),
        synchronized(_NonLiveManager()),
        synchronized(MockDistingMidiManager()),
        DistingState.connected(disting: wire.manager),
        const DistingState.initial(),
      ];
      for (final state in cases) {
        cubit.emit(state);
        expect(cubit.remoteControlState.available, isFalse);
        expect(cubit.remoteControlState.unavailableReason, isNotEmpty);
        expect(() => cubit.openRemoteSession(), throwsStateError);
        await expectLater(
          cubit.sendRemoteAction(old, const RemotePush(0)),
          throwsStateError,
        );
      }
      expect(wire.remoteAttempts, isEmpty);
    },
  );

  test(
    'capability loss cancels queued work, rejects old tokens and retains same-connection pots',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.adjustRemotePot(session, 0, 32);
      final version = wire.manager.requestVersionString();
      final turn = cubit.sendRemoteAction(
        session,
        const RemoteEncoderTurn(0, 5),
      );
      final cancelled = expectLater(
        turn,
        throwsA(isA<DistingRequestCancelledException>()),
      );
      await Future<void>.delayed(Duration.zero);
      cubit.emit(synchronized(wire.manager, version: '1.18.9'));
      await cancelled;
      expect(cubit.remoteControlState.sessionId, isNull);
      wire.injectVersion();
      await version;
      cubit.emit(synchronized(wire.manager));
      expect(cubit.remoteControlState.potValues, [2080, 2048, 2048]);
      await expectLater(
        cubit.sendRemoteAction(session, const RemotePush(0)),
        throwsStateError,
      );
      final reopened = cubit.openRemoteSession();
      await cubit.adjustRemotePot(reopened, 0, 32);
      expect(wire.remotePackets, [
        remoteFrame([4, 0, 32, 16]),
        remoteFrame([4, 0, 64, 16]),
      ]);
    },
  );

  test(
    'send and cleanup failures clear local holds and publish errors, not device-success claims',
    () async {
      final states = <RemoteControlState>[];
      final subscription = cubit.remoteControlStateStream.listen(states.add);
      addTearDown(subscription.cancel);
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      wire.failRemoteSend = true;
      await expectLater(
        cubit.sendRemoteAction(session, const RemoteEncoderTurn(0, 5)),
        throwsStateError,
      );
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(
        cubit.remoteControlState.error,
        contains('device state is unknown'),
      );
      expect(cubit.remoteControlState.sessionId, isNull);
      expect(cubit.remoteControlState.pendingReleaseControls, {3});
      await expectLater(cubit.closeRemoteSession(session), throwsStateError);
      expect(cubit.remoteControlState.pendingReleaseControls, {3});
      expect(cubit.remoteControlState.available, isFalse);
      expect(() => cubit.openRemoteSession(), throwsStateError);
      await expectLater(
        cubit.sendRemoteAction(session, const RemotePush(8)),
        throwsStateError,
      );
      expect(
        cubit.remoteControlState.error,
        contains('device release is unknown'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(wire.remoteAttempts, hasLength(4));
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
      ]);
      expect(states.any((state) => state.pending), isTrue);
      expect(states.where((state) => state.error != null), isNotEmpty);
      expect(cubit.remoteControlState.pending, isFalse);
    },
  );

  test(
    'a push that throws after delivery releases both prior and uncertain holds',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      final failure = StateError('Push delivery became uncertain');
      wire.onSend = (packet) {
        if (packet[6] == 0x78 && packet[7] == 1 && packet[8] == 6) {
          throw failure;
        }
      };
      await expectLater(
        cubit.sendRemoteAction(session, const RemotePush(6)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(failure.message),
          ),
        ),
      );
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([1, 6]),
        remoteFrame([2, 3]),
        remoteFrame([2, 6]),
      ]);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(cubit.remoteControlState.sessionId, isNull);
      expect(
        cubit.remoteControlState.error,
        contains('device state is unknown'),
      );
      await cubit.closeRemoteSession(session);
      expect(wire.remotePackets, hasLength(4));
    },
  );

  test(
    'failure cleanup tries every release and preserves the original send error',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      await cubit.sendRemoteAction(session, const RemotePush(4));
      final failure = StateError('Encoder transport failed');
      var failRelease = true;
      wire.onSend = (packet) {
        if (packet[6] != 0x78) return;
        if (packet[7] == 3) throw failure;
        if (packet[7] == 2 && packet[8] == 3 && failRelease) {
          throw StateError('Release transport failed');
        }
      };
      await expectLater(
        cubit.sendRemoteAction(session, const RemoteEncoderTurn(0, 5)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(failure.message),
          ),
        ),
      );
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([1, 4]),
        remoteFrame([3, 0, 5]),
        remoteFrame([2, 3]),
        remoteFrame([2, 4]),
      ]);
      expect(
        cubit.remoteControlState.error,
        contains('Encoder transport failed'),
      );
      expect(cubit.remoteControlState.pendingReleaseControls, {3});
      expect(
        cubit.remoteControlState.error,
        contains('device release is unknown'),
      );
      expect(cubit.remoteControlState.heldControls, isEmpty);
      failRelease = false;
      await cubit.closeRemoteSession(session);
      expect(wire.remotePackets.last, remoteFrame([2, 3]));
      expect(wire.remotePackets, hasLength(6));
      expect(cubit.remoteControlState.pendingReleaseControls, isEmpty);
      expect(cubit.remoteControlState.available, isTrue);
      final recovered = cubit.openRemoteSession();
      await cubit.closeRemoteSession(recovered);
    },
  );

  test(
    'failed replacement-host cleanup blocks its new host until release recovery',
    () async {
      final original = cubit.openRemoteSession();
      await cubit.sendRemoteAction(original, const RemotePush(3));
      wire.failRemoteSend = true;
      final cleanupFailed = cubit.remoteControlStateStream.firstWhere(
        (state) => state.pendingReleaseControls.isNotEmpty && !state.pending,
      );
      final replacement = cubit.openRemoteSession();
      await cleanupFailed;
      expect(cubit.remoteControlState.pendingReleaseControls, {3});
      expect(cubit.remoteControlState.available, isFalse);
      expect(() => cubit.openRemoteSession(), throwsStateError);
      await expectLater(
        cubit.sendRemoteAction(replacement, const RemoteEncoderTurn(0, 1)),
        throwsStateError,
      );
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
      ]);
      expect(wire.remoteAttempts, hasLength(2));
      wire.failRemoteSend = false;
      await cubit.closeRemoteSession(replacement);
      expect(wire.remotePackets.last, remoteFrame([2, 3]));
      expect(cubit.remoteControlState.pendingReleaseControls, isEmpty);
      expect(cubit.remoteControlState.available, isTrue);
    },
  );

  test('failed push cleanup never follows a replacement transport', () async {
    final session = cubit.openRemoteSession();
    final failure = StateError('Push failed while connection changed');
    wire.onSend = (packet) {
      if (packet[6] == 0x78 && packet[7] == 1 && packet[8] == 6) {
        cubit.emit(synchronized(wire.replaceManager()));
        throw failure;
      }
    };
    await expectLater(
      cubit.sendRemoteAction(session, const RemotePush(6)),
      throwsA(isA<DistingRequestCancelledException>()),
    );
    await cubit.closeRemoteSession(session);
    expect(wire.remotePackets, [
      remoteFrame([1, 6]),
    ]);
    final replacement = cubit.openRemoteSession();
    await cubit.sendRemoteAction(replacement, const RemoteEncoderTurn(1, 1));
    expect(wire.remotePackets.last, remoteFrame([3, 1, 1]));
    expect(wire.remotePackets, hasLength(2));
  });

  test(
    'disconnect with possibly delivered pushes reports unknown release without replay',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      cubit.disconnect();
      expect(cubit.remoteControlState.available, isFalse);
      expect(
        cubit.remoteControlState.error,
        contains('device release is unknown'),
      );
      expect(cubit.remoteControlState.heldControls, isEmpty);
      await cubit.closeRemoteSession(session);
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
      ]);
      cubit.emit(synchronized(wire.replaceManager()));
      final replacement = cubit.openRemoteSession();
      await cubit.sendRemoteAction(replacement, const RemoteEncoderTurn(1, 1));
      expect(wire.remotePackets.last, remoteFrame([3, 1, 1]));
      expect(wire.remotePackets, hasLength(2));
    },
  );

  test(
    'shutdown blocks new hosts while original-transport cleanup is pending',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(3));
      final version = wire.manager.requestVersionString();
      final closing = cubit.close();
      expect(cubit.remoteControlState.available, isFalse);
      expect(() => cubit.openRemoteSession(), throwsStateError);
      await expectLater(
        cubit.sendRemoteAction(session, const RemotePush(8)),
        throwsStateError,
      );
      wire.injectVersion();
      await version;
      await closing;
      closed = true;
      expect(wire.remotePackets, [
        remoteFrame([1, 3]),
        remoteFrame([2, 3]),
      ]);
    },
  );

  test(
    'Cubit shutdown releases sent holds on the original transport and closes remote state',
    () async {
      final session = cubit.openRemoteSession();
      await cubit.sendRemoteAction(session, const RemotePush(8));
      await cubit.close();
      closed = true;
      expect(wire.remotePackets, [
        remoteFrame([1, 8]),
        remoteFrame([2, 8]),
      ]);
      expect(cubit.remoteControlState.available, isFalse);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      expect(() => cubit.openRemoteSession(), throwsStateError);
    },
  );
}
