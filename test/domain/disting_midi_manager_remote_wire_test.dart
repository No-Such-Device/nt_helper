import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/sysex/requests/remote_command.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/remote_wire_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 10,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
  });

  test(
    'records all nine indexed pushes/releases, encoder signs and pot bytes',
    () async {
      final wire = RemoteWireHarness();
      addTearDown(wire.close);
      final cancellation = DistingRequestCancellation();
      final actions = <RemoteAction>[
        for (var i = 0; i < 9; i++) ...[RemotePush(i), RemoteRelease(i)],
        for (var i = 0; i < 2; i++)
          for (final delta in [1, -1, 5, -5, 63, -64])
            RemoteEncoderTurn(i, delta),
        for (var i = 0; i < 3; i++)
          for (final value in [0, 2048, 4095]) RemotePotTurn(i, value),
      ];
      await Future.wait([
        for (final action in actions)
          wire.manager.requestRemoteAction(action, cancellation: cancellation),
      ]);
      expect(wire.remotePackets, [
        for (var i = 0; i < 9; i++) ...[
          remoteFrame([0x01, i]),
          remoteFrame([0x02, i]),
        ],
        for (var i = 0; i < 2; i++)
          for (final byte in [0x01, 0x7F, 0x05, 0x7B, 0x3F, 0x40])
            remoteFrame([0x03, i, byte]),
        for (var i = 0; i < 3; i++) ...[
          remoteFrame([0x04, i, 0x00, 0x00]),
          remoteFrame([0x04, i, 0x00, 0x10]),
          remoteFrame([0x04, i, 0x7F, 0x1F]),
        ],
      ]);
    },
  );

  test(
    'sustained concurrent mixed input preserves order, totals and packet limits',
    () async {
      final wire = RemoteWireHarness();
      addTearDown(wire.close);
      final cancellation = DistingRequestCancellation();
      final requests = <Future<void>>[];
      final expected = <List<int>>[];
      for (var i = 0; i < 100; i++) {
        for (final action in [
          const RemotePush(3),
          const RemoteEncoderTurn(0, 125),
          RemotePotTurn(1, i * 32),
          const RemoteRelease(3),
          const RemoteEncoderTurn(1, -129),
        ]) {
          requests.add(
            wire.manager.requestRemoteAction(
              action,
              cancellation: cancellation,
            ),
          );
        }
        expected.addAll([
          remoteFrame([1, 3]),
          remoteFrame([3, 0, 63]),
          remoteFrame([3, 0, 62]),
          remoteFrame([4, 1, (i * 32) & 0x7F, (i * 32) >> 7]),
          remoteFrame([2, 3]),
          remoteFrame([3, 1, 64]),
          remoteFrame([3, 1, 64]),
          remoteFrame([3, 1, 127]),
        ]);
      }
      await Future.wait(requests);
      expect(wire.remotePackets, expected);
      for (final packet in wire.remotePackets) {
        expect(packet.length, lessThanOrEqualTo(1024));
        expect(
          packet.sublist(1, packet.length - 1),
          everyElement(inInclusiveRange(0, 127)),
        );
      }
      final turns = wire.remotePackets.where((p) => p[7] == 3);
      int signed(int byte) => byte < 64 ? byte : byte - 128;
      expect(
        turns
            .where((p) => p[8] == 0)
            .fold<int>(0, (sum, p) => sum + signed(p[9])),
        12500,
      );
      expect(
        turns
            .where((p) => p[8] == 1)
            .fold<int>(0, (sum, p) => sum + signed(p[9])),
        -12900,
      );
    },
  );

  test(
    'rejects invalid inputs before sending, including raw wire range and ID',
    () async {
      final wire = RemoteWireHarness();
      addTearDown(wire.close);
      for (final action in const [
        RemotePush(-1),
        RemotePush(9),
        RemoteRelease(-1),
        RemoteRelease(9),
        RemoteEncoderTurn(-1, 1),
        RemoteEncoderTurn(2, 1),
        RemotePotTurn(-1, 0),
        RemotePotTurn(3, 0),
        RemotePotTurn(0, -1),
        RemotePotTurn(0, 4096),
      ]) {
        expect(
          () => wire.manager.requestRemoteAction(
            action,
            cancellation: DistingRequestCancellation(),
          ),
          throwsRangeError,
        );
      }
      for (final delta in [-65, 64]) {
        expect(
          () => RemoteCommandMessage(
            sysExId: remoteWireSysExId,
            action: RemoteEncoderTurn(0, delta),
          ).encode(),
          throwsRangeError,
        );
      }
      for (final id in [-1, 128]) {
        expect(
          () => RemoteCommandMessage(
            sysExId: id,
            action: const RemotePush(0),
          ).encode(),
          throwsRangeError,
        );
      }
      await wire.manager.requestRemoteAction(
        const RemoteEncoderTurn(0, 0),
        cancellation: DistingRequestCancellation(),
      );
      expect(wire.attempts, isEmpty);
    },
  );

  test(
    'scoped cancellation removes only remote work behind an unrelated request',
    () async {
      final wire = RemoteWireHarness();
      addTearDown(wire.close);
      final version = wire.manager.requestVersionString();
      final cancellation = DistingRequestCancellation();
      final remote = wire.manager.requestRemoteAction(
        const RemoteEncoderTurn(0, 130),
        cancellation: cancellation,
      );
      final cancelled = expectLater(
        remote,
        throwsA(isA<DistingRequestCancelledException>()),
      );
      final wake = wire.manager.requestWake();
      cancellation.cancel();
      wire.injectVersion();
      expect(await version, '1.19.0');
      await cancelled;
      await wake;
      expect(wire.remoteAttempts, isEmpty);
      expect(wire.sentPackets.map((p) => p[6]), [0x22, 0x07]);
      await wire.manager.requestRemoteAction(
        const RemoteEncoderTurn(1, -1),
        cancellation: DistingRequestCancellation(),
      );
      expect(wire.remotePackets, [
        remoteFrame([3, 1, 127]),
      ]);
    },
  );

  test('an already-cancelled action produces no packet', () async {
    final wire = RemoteWireHarness();
    addTearDown(wire.close);
    final cancellation = DistingRequestCancellation()..cancel();
    await expectLater(
      wire.manager.requestRemoteAction(
        const RemotePush(0),
        cancellation: cancellation,
      ),
      throwsA(isA<DistingRequestCancelledException>()),
    );
    expect(wire.attempts, isEmpty);
  });

  test('missing replies never retransmit gestures', () {
    final wire = RemoteWireHarness();
    addTearDown(wire.close);
    fakeAsync((time) {
      var complete = false;
      wire.manager
          .requestRemoteAction(
            const RemoteEncoderTurn(0, 5),
            cancellation: DistingRequestCancellation(),
          )
          .then((_) => complete = true);
      time.flushMicrotasks();
      expect(complete, isTrue);
      time.elapse(const Duration(seconds: 30));
      expect(wire.remoteAttempts, [
        remoteFrame([3, 0, 5]),
      ]);
    });
  });

  test(
    'send failure is reported after one attempt without retry or blocking other commands',
    () async {
      final wire = RemoteWireHarness()..failRemoteSend = true;
      addTearDown(wire.close);
      await expectLater(
        wire.manager.requestRemoteAction(
          const RemotePush(3),
          cancellation: DistingRequestCancellation(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('after 1 attempts'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(wire.remoteAttempts, hasLength(1));
      expect(wire.remotePackets, isEmpty);
      await wire.manager.requestWake();
      expect(wire.sentPackets.single[6], 0x07);
    },
  );
}
