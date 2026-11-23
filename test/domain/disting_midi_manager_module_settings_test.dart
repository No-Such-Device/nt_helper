import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/module_settings_fixtures.dart';
import '../test_helpers/remote_wire_harness.dart';

void inject(
  RemoteWireHarness wire,
  int command,
  List<int> payload, {
  int id = remoteWireSysExId,
}) => wire.incoming.add(
  MidiPacket(ModuleSettingsCodec.packet(id, command, payload), 0, wire.device),
);

void respond(
  RemoteWireHarness wire, {
  bool Function(int command)? include,
  bool mismatch = false,
}) {
  var value = 0;
  wire.onSend = (p) {
    final command = p[6];
    if (include != null && !include(command)) return;
    final id = p.length >= 11 ? decode16(p, 7) : 0;
    switch (command) {
      case 0x63:
        inject(wire, command, settingsGroupsPayload());
      case 0x64:
        inject(wire, command, settingInfoPayload(id));
      case 0x65:
        inject(wire, command, settingValuePayload(id, value));
      case 0x66:
        if (!mismatch) value = decode16(p, 10);
    }
  };
}

Future<void> load(
  RemoteWireHarness wire,
  DistingRequestCancellation cancellation,
) async {
  final tree = await wire.manager.discoverModuleSettings(cancellation);
  for (final id in tree.settingIds) {
    await wire.manager.requestModuleSettingInfo(id, cancellation);
    await wire.manager.requestModuleSettingValue(id, cancellation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 50,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
  });

  test('real scheduler writes once with no ACK and waits 20ms before fresh readback', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      respond(wire);
      final cancellation = DistingRequestCancellation();
      var loaded = false;
      load(wire, cancellation).then((_) => loaded = true);
      time.flushMicrotasks();
      expect(loaded, isTrue);
      expect(wire.sentPackets.map((p) => p[6]), [0x63, 0x64, 0x65, 0x64, 0x65]);
      ModuleSettingValue? result;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(-50), cancellation)
          .then((v) => result = v);
      time.flushMicrotasks();
      expect(wire.sentPackets.skip(5).map((p) => p[6]), [0x65, 0x66]);
      time.elapse(const Duration(milliseconds: 19));
      expect(result, isNull);
      time.elapse(const Duration(milliseconds: 1));
      time.flushMicrotasks();
      expect(result!.value, -50);
      expect(wire.sentPackets.skip(5).map((p) => p[6]), [0x65, 0x66, 0x65]);
      expect(wire.sentPackets[6], [
        240,
        0,
        33,
        39,
        109,
        remoteWireSysExId,
        0x66,
        0,
        0,
        5,
        ...encode16(-50),
        247,
      ]);
      wire.manager.sendModuleSettingsAction(0, cancellation).ignore();
      wire.manager.sendModuleSettingsAction(2, cancellation).ignore();
      time.flushMicrotasks();
      expect(wire.sentPackets.skip(8).map((p) => p.sublist(6)), [
        [0x67, 0, 247],
        [0x67, 2, 247],
      ]);
      Object? error;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(2), cancellation)
          .catchError((Object e) {
            error = e;
            throw e;
          })
          .ignore();
      time.flushMicrotasks();
      expect(error, isA<StateError>());
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });

  test('never writes without discovery and complete snapshot or to read-only metadata', () async {
    final wire = RemoteWireHarness();
    addTearDown(wire.close);
    final cancellation = DistingRequestCancellation();
    await expectLater(
      wire.manager.writeModuleSetting(
        5,
        const ModuleSettingValue(2),
        cancellation,
      ),
      throwsStateError,
    );
    await expectLater(
      wire.manager.sendModuleSettingsAction(0, cancellation),
      throwsStateError,
    );
    expect(wire.sentPackets, isEmpty);
    respond(wire);
    await wire.manager.discoverModuleSettings(cancellation);
    await wire.manager.requestModuleSettingInfo(5, cancellation);
    await expectLater(
      wire.manager.writeModuleSetting(
        5,
        const ModuleSettingValue(2),
        cancellation,
      ),
      throwsStateError,
    );
    await load(wire, cancellation);
    wire.onSend = (p) {
      if (p[6] == 0x64) inject(wire, 0x64, settingInfoPayload(5, flags: 4));
    };
    await wire.manager.requestModuleSettingInfo(5, cancellation);
    final count = wire.sentPackets.length;
    await expectLater(
      wire.manager.writeModuleSetting(
        5,
        const ModuleSettingValue(2),
        cancellation,
      ),
      throwsArgumentError,
    );
    expect(wire.sentPackets.length, count);
    await expectLater(
      wire.manager.sendModuleSettingsAction(1, cancellation),
      throwsUnsupportedError,
    );
  });

  test(
    'wrong device/command/setting cannot satisfy the current value request',
    () async {
      final wire = RemoteWireHarness();
      addTearDown(wire.close);
      respond(wire);
      final cancellation = DistingRequestCancellation();
      await load(wire, cancellation);
      wire.onSend = (p) {
        if (p[6] != 0x65) return;
        inject(wire, 0x65, settingValuePayload(5, 10), id: 3);
        inject(wire, 0x64, settingInfoPayload(5));
        inject(wire, 0x65, settingValuePayload(9, 20));
        inject(wire, 0x65, settingValuePayload(5, 30));
      };
      expect(
        (await wire.manager.requestModuleSettingValue(5, cancellation)).value,
        30,
      );
    },
  );

  test('discovery without reply makes one bounded read-only attempt; late debt is fail closed', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      final errors = <Object>[];
      final cancellation = DistingRequestCancellation();
      wire.manager.discoverModuleSettings(cancellation).catchError((Object e) {
        errors.add(e);
        throw e;
      }).ignore();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect(wire.sentPackets.map((p) => p[6]), [0x63]);
      expect(errors, hasLength(1));
      wire.manager.discoverModuleSettings(cancellation).catchError((Object e) {
        errors.add(e);
        throw e;
      }).ignore();
      time.flushMicrotasks();
      expect(errors.last, isA<AmbiguousResponseAttributionException>());
      expect(wire.sentPackets, hasLength(1));
      inject(wire, 0x63, settingsGroupsPayload());
      time.flushMicrotasks();
      respond(wire);
      var done = false;
      wire.manager
          .discoverModuleSettings(cancellation)
          .then((_) => done = true);
      time.flushMicrotasks();
      expect(done, isTrue);
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });

  test(
    'timed-out same-ID read prevents mutation until its late reply drains',
    () {
      fakeAsync((time) {
        final wire = RemoteWireHarness();
        final cancellation = DistingRequestCancellation();
        respond(wire);
        var loaded = false;
        load(wire, cancellation).then((_) => loaded = true);
        time.flushMicrotasks();
        expect(loaded, isTrue);
        respond(wire, include: (c) => c != 0x65);
        wire.manager.requestModuleSettingValue(5, cancellation).ignore();
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 1));
        Object? error;
        wire.manager
            .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
            .catchError((Object e) {
              error = e;
              throw e;
            })
            .ignore();
        time.flushMicrotasks();
        expect(
          error,
          isA<ModuleSettingWriteException>()
              .having(
                (e) => e.phase,
                'phase',
                ModuleSettingWritePhase.beforeSend,
              )
              .having(
                (e) => e.cause,
                'cause',
                isA<AmbiguousResponseAttributionException>(),
              ),
        );
        expect(wire.sentPackets.where((p) => p[6] == 0x66), isEmpty);
        inject(wire, 0x65, settingValuePayload(5, 0));
        time.flushMicrotasks();
        respond(wire);
        var value = -1;
        wire.manager
            .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
            .then((v) => value = v.value as int);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 20));
        time.flushMicrotasks();
        expect(value, 4);
        unawaited(wire.close());
        time.flushMicrotasks();
      });
    },
  );

  test('ambiguous mutation send failure and cancelled transactions never replay a write', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      final cancellation = DistingRequestCancellation();
      respond(wire);
      load(wire, cancellation).ignore();
      time.flushMicrotasks();
      final responder = wire.onSend;
      wire.onSend = (p) {
        if (p[6] == 0x66) throw StateError('May have been delivered');
        responder!(p);
      };
      Object? error;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
          .catchError((Object e) {
            error = e;
            throw e;
          })
          .ignore();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect(error, isNotNull);
      expect(wire.attempts.where((p) => p[6] == 0x66), hasLength(1));
      cancellation.cancel();
      wire.manager
          .writeModuleSetting(9, const ModuleSettingValue(8), cancellation)
          .ignore();
      time.flushMicrotasks();
      expect(wire.attempts.where((p) => p[6] == 0x66), hasLength(1));
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });
  test('cancellation during the 20ms settle interval prevents readback and any mutation replay', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      respond(wire);
      final cancellation = DistingRequestCancellation();
      load(wire, cancellation).ignore();
      time.flushMicrotasks();
      Object? error;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
          .then<void>(
            (_) => fail('Cancelled write must not complete normally'),
            onError: (Object e) {
              error = e;
            },
          );
      time.flushMicrotasks();
      expect(wire.sentPackets.where((p) => p[6] == 0x66), hasLength(1));
      final reads = wire.sentPackets.where((p) => p[6] == 0x65).length;
      cancellation.cancel();
      time.elapse(const Duration(milliseconds: 20));
      expect(
        error,
        isA<ModuleSettingWriteException>()
            .having((e) => e.phase, 'phase', ModuleSettingWritePhase.readback)
            .having(
              (e) => e.cause,
              'cause',
              isA<DistingRequestCancelledException>(),
            ),
      );
      expect(wire.sentPackets.where((p) => p[6] == 0x65), hasLength(reads));
      expect(wire.sentPackets.where((p) => p[6] == 0x66), hasLength(1));
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });

  test('settings reads tolerate 140ms replies with a 50ms general timeout and never await a write ACK', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      var value = 0;
      wire.onSend = (p) {
        final id = p.length >= 11 ? decode16(p, 7) : 0;
        switch (p[6]) {
          case 0x63:
            inject(wire, 0x63, settingsGroupsPayload());
          case 0x64:
            inject(wire, 0x64, settingInfoPayload(id));
          case 0x65:
            final captured = value;
            Timer(
              const Duration(milliseconds: 140),
              () => inject(wire, 0x65, settingValuePayload(id, captured)),
            );
          case 0x66:
            value = decode16(p, 10);
        }
      };
      final cancellation = DistingRequestCancellation();
      var loaded = false;
      load(wire, cancellation).then((_) => loaded = true);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 50));
      expect(loaded, isFalse);
      time.elapse(const Duration(milliseconds: 250));
      expect(loaded, isTrue);
      ModuleSettingValue? observed;
      Object? error;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
          .then<void>(
            (v) => observed = v,
            onError: (Object e) {
              error = e;
            },
          );
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 50));
      expect(error, isNull);
      time.elapse(const Duration(milliseconds: 250));
      expect(observed!.value, 4);
      expect(error, isNull);
      expect(wire.sentPackets.where((p) => p[6] == 0x66), hasLength(1));
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });

  test('late readback debt blocks only its ID; independent writes and fresh recovery never replay mutation', () {
    fakeAsync((time) {
      final wire = RemoteWireHarness();
      respond(wire);
      final cancellation = DistingRequestCancellation();
      load(wire, cancellation).ignore();
      time.flushMicrotasks();
      final values = {5: 0, 9: 0};
      var sent5 = false;
      var delayed = false;
      wire.onSend = (p) {
        final id = p.length >= 11 ? decode16(p, 7) : 0;
        if (p[6] == 0x66) {
          values[id] = decode16(p, 10);
          if (id == 5) sent5 = true;
        }
        if (p[6] == 0x65) {
          final captured = values[id]!;
          if (id == 5 && sent5 && !delayed) {
            delayed = true;
            Timer(
              const Duration(milliseconds: 1100),
              () => inject(wire, 0x65, settingValuePayload(id, captured)),
            );
          } else {
            inject(wire, 0x65, settingValuePayload(id, captured));
          }
        }
      };
      Object? error;
      wire.manager
          .writeModuleSetting(5, const ModuleSettingValue(4), cancellation)
          .catchError((Object e) {
            error = e;
            throw e;
          })
          .ignore();
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 1020));
      expect(
        error,
        isA<ModuleSettingWriteException>()
            .having((e) => e.phase, 'phase', ModuleSettingWritePhase.readback)
            .having((e) => e.mutationMayHaveOccurred, 'may have sent', isTrue),
      );
      int? independent;
      wire.manager
          .writeModuleSetting(9, const ModuleSettingValue(8), cancellation)
          .then((v) => independent = v.value as int);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 20));
      expect(independent, 8);
      Object? ambiguous;
      wire.manager.requestModuleSettingValue(5, cancellation).catchError((
        Object e,
      ) {
        ambiguous = e;
        throw e;
      }).ignore();
      time.flushMicrotasks();
      expect(ambiguous, isA<AmbiguousResponseAttributionException>());
      values[5] = 9;
      time.elapse(const Duration(milliseconds: 100));
      int? fresh;
      wire.manager
          .requestModuleSettingValue(5, cancellation)
          .then((v) => fresh = v.value as int);
      time.flushMicrotasks();
      expect(fresh, 9);
      expect(
        wire.sentPackets.where((p) => p[6] == 0x66 && decode16(p, 7) == 5),
        hasLength(1),
      );
      expect(
        wire.sentPackets.where((p) => p[6] == 0x66 && decode16(p, 7) == 9),
        hasLength(1),
      );
      unawaited(wire.close());
      time.flushMicrotasks();
    });
  });
}
