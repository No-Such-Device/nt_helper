import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/request_key.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/module_settings.dart';

import '../test_helpers/module_settings_fixtures.dart';

void main() {
  test(
    'exact editor-derived request bytes, signed16 extremes, no checksums',
    () {
      expect(ModuleSettingsCodec.packet(7, 0x63), [
        240,
        0,
        33,
        39,
        109,
        7,
        99,
        247,
      ]);
      for (final command in [0x64, 0x65]) {
        expect(
          ModuleSettingsCodec.packet(
            7,
            command,
            ModuleSettingsCodec.settingId(257),
          ),
          [240, 0, 33, 39, 109, 7, command, 0, 2, 1, 247],
        );
      }
      for (final n in [-32768, -1, 0, 32767]) {
        final info = settingInfo(5, min: -32768, max: 32767);
        expect(ModuleSettingsCodec.write(info, ModuleSettingValue(n)), [
          0,
          0,
          5,
          ...encode16(n),
        ]);
        expect(
          ModuleSettingsCodec.value(settingValuePayload(5, n), info).value,
          n,
        );
      }
      for (final action in [0, 1, 2]) {
        expect(ModuleSettingsCodec.packet(7, 0x67, [action]), [
          240,
          0,
          33,
          39,
          109,
          7,
          103,
          action,
          247,
        ]);
      }
    },
  );

  test(
    'hierarchy preserves opaque bytes, nested menu order and immutable data',
    () {
      final tree = ModuleSettingsCodec.groups(settingsGroupsPayload());
      expect(tree.opaqueHeader, [12, 34, 56]);
      expect(tree.settingIds, [5, 9]);
      expect(tree.groups[3]!.name, 'Engine');
      expect(() => tree.groups.clear(), throwsUnsupportedError);
      expect(() => tree.groups[3]!.children.clear(), throwsUnsupportedError);
    },
  );

  test('rejects truncated, unterminated, oversized, cyclic, duplicate, missing and future trees', () {
    final valid = settingsGroupsPayload();
    for (var end = 0; end < valid.length; end++) {
      expect(
        () => ModuleSettingsCodec.groups(Uint8List.sublistView(valid, 0, end)),
        throwsA(anything),
        reason: 'length $end',
      );
    }
    for (final bytes in <List<int>>[
      [1, 0, 0, 0, 1, 0, 0, 1, 1, 0],
      [1, 0, 0, 0, 1, 1, 0, 0],
      [1, 0, 0, 0, 1, 0, 0, 2, 0, 3, 0, 3],
      [1, 0, 0, 0, 1, 0, 0, 1, 1, 7],
      [...valid, 0],
      [1, 0, 128, ...valid.skip(3)],
      List.filled(1017, 0),
    ]) {
      expect(
        () => ModuleSettingsCodec.groups(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
    }
    expect(
      () => ModuleSettingsCodec.groups(Uint8List.fromList([2])),
      throwsUnsupportedError,
    );
  });

  test(
    'metadata bounds, toggles, defaults, flags and future types fail closed',
    () {
      final toggle = settingInfo(
        5,
        unit: 1,
        min: 0,
        max: 1,
        enums: ['No', 'Yes'],
      );
      expect(toggle.isToggle, isTrue);
      expect(toggle.writable, isTrue);
      expect(
        settingInfo(
          5,
          unit: 1,
          min: 0,
          max: 1,
          enums: ['Left', 'Right'],
        ).isToggle,
        isFalse,
      );
      for (final type in [5, 7, 127]) {
        expect(settingInfo(5, type: type).writable, isFalse);
      }
      for (final flags in [4, 8, 127]) {
        expect(
          () => ModuleSettingsCodec.write(
            settingInfo(5, flags: flags),
            const ModuleSettingValue(1),
          ),
          throwsArgumentError,
        );
      }
      expect(settingInfo(5, flags: 3).needsReboot, isTrue);
      expect(settingInfo(5, flags: 3).restartsEngine, isTrue);
      final valid = settingInfoPayload(5);
      for (var n = 0; n < valid.length; n++) {
        expect(
          () => ModuleSettingsCodec.info(Uint8List.sublistView(valid, 0, n)),
          throwsA(anything),
        );
      }
      for (final payload in [
        settingInfoPayload(5, min: 2, max: 1),
        settingInfoPayload(5, def: 101),
        settingInfoPayload(5, unit: 1, min: 0, max: 2, enums: ['Off', 'On']),
        settingInfoPayload(5, maxLength: -1),
      ]) {
        expect(() => ModuleSettingsCodec.info(payload), throwsFormatException);
      }
    },
  );

  test('names reject Unicode, NUL, overlength; paths and unknown types stay read only', () {
    final info = settingInfo(5, type: 4);
    expect(
      ModuleSettingsCodec.write(info, const ModuleSettingValue('NT name')),
      [0, 0, 5, ...'NT name'.codeUnits, 0],
    );
    for (final name in ['é', 'x\u0000', 'a' * 21]) {
      expect(
        () => ModuleSettingsCodec.write(info, ModuleSettingValue(name)),
        throwsArgumentError,
      );
    }
    expect(
      ModuleSettingsCodec.value(
        Uint8List.fromList([0, 0, 5, 65, 32, 0]),
        info,
      ).value,
      'A',
    );
    expect(
      () => ModuleSettingsCodec.value(Uint8List.fromList([0, 0, 5, 65]), info),
      throwsFormatException,
    );
    expect(
      () => ModuleSettingsCodec.write(
        settingInfo(5, type: 5),
        const ModuleSettingValue('/mts'),
      ),
      throwsArgumentError,
    );
  });

  test('Path reads preserve SD paths but neither flag-free nor readonly Path writes are supported', () {
    for (final flags in [0, 4]) {
      final info = settingInfo(56, type: 5, flags: flags);
      expect(
        ModuleSettingsCodec.value(
          Uint8List.fromList([0, 0, 56, ...'/recordings'.codeUnits, 0]),
          info,
        ).value,
        '/recordings',
      );
      expect(info.writable, isFalse);
      expect(
        () =>
            ModuleSettingsCodec.write(info, const ModuleSettingValue('/other')),
        throwsArgumentError,
      );
    }
    expect(settingInfo(56, type: 4).writable, isTrue);
    expect(settingInfo(56, type: 4, flags: 4).writable, isFalse);
  });

  test(
    'all 64 bits, bit63 and little-endian limb boundaries retain precision',
    () {
      final info = settingInfo(5, type: 6);
      for (final bits in [
        BigInt.zero,
        BigInt.one,
        BigInt.one << 63,
        (BigInt.one << 64) - BigInt.one,
      ]) {
        final payload = ModuleSettingsCodec.write(
          info,
          ModuleSettingValue(bits),
        );
        expect(payload.length, 13);
        expect(
          ModuleSettingsCodec.value(Uint8List.fromList(payload), info).value,
          bits,
        );
      }
      expect(
        ModuleSettingsCodec.write(info, ModuleSettingValue(BigInt.one << 63)),
        [0, 0, 5, ...List.filled(9, 0), 1],
      );
      expect(
        () => ModuleSettingsCodec.value(
          Uint8List.fromList([0, 0, 5, ...List.filled(9, 0), 2]),
          info,
        ),
        throwsFormatException,
      );
      expect(
        () => ModuleSettingsCodec.write(
          info,
          ModuleSettingValue(BigInt.one << 64),
        ),
        throwsArgumentError,
      );
    },
  );

  test('packet and numeric validation reject out-of-domain inputs', () {
    for (final id in [-1, 32768]) {
      expect(() => ModuleSettingsCodec.settingId(id), throwsRangeError);
    }
    for (final id in [-1, 128]) {
      expect(() => ModuleSettingsCodec.packet(id, 0x63), throwsArgumentError);
    }
    expect(
      () => ModuleSettingsCodec.packet(0, 0x66, List.filled(1017, 0)),
      throwsArgumentError,
    );
    expect(
      () => ModuleSettingsCodec.value(
        Uint8List.fromList([0, 0, 5, 4, 0, 0, 0]),
        settingInfo(5),
      ),
      throwsFormatException,
    );
    expect(
      () => ModuleSettingsCodec.write(
        settingInfo(5),
        const ModuleSettingValue(101),
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          ModuleSettingsCodec.value(settingValuePayload(9, 0), settingInfo(5)),
      throwsFormatException,
    );
  });

  test('request key correlates command/device/setting in strict and normal matching', () {
    final key = RequestKey(
      sysExId: 7,
      messageType: DistingNTRespMessageType.respSettingValue,
      settingId: 5,
    );
    final same = RequestKey(
      sysExId: 7,
      messageType: DistingNTRespMessageType.respSettingValue,
      settingId: 5,
    );
    expect(key, same);
    expect(key.hashCode, same.hashCode);
    for (final args in [
      (7, 0x65, 5, true),
      (7, 0x65, 9, false),
      (8, 0x65, 5, false),
      (7, 0x64, 5, false),
    ]) {
      final msg = decodeDistingNTSysEx(
        ModuleSettingsCodec.packet(
          args.$1,
          args.$2,
          settingValuePayload(args.$3, 0),
        ),
      )!;
      expect(key.matches(msg), args.$4);
      expect(key.matchesStrict(msg), args.$4);
    }
  });

  test(
    'recognized release/beta is only a candidate, never a capability proof',
    () {
      for (final v in [
        '1.20beta',
        '1.20.0beta',
        '1.20beta2',
        '1.20.0-beta.2',
        'v1.20.0',
        '2.0.0',
      ]) {
        expect(FirmwareVersion(v).isModuleSettingsCandidate, isTrue, reason: v);
      }
      for (final v in [
        '',
        '1.19.0',
        'date 2026.11.23',
        'junk1.20',
        '1.20broken',
      ]) {
        expect(
          FirmwareVersion(v).isModuleSettingsCandidate,
          isFalse,
          reason: v,
        );
      }
    },
  );
}
