import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_preset_codec.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(
          File('test/fixtures/patch_map/native-map.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test('matches the C++ preset fixture and canonical socket order', () {
    final json = fixture()['patch_helper'] as Map<String, dynamic>;
    final map = PatchMap.fromJson(json);
    expect(map.toJson(), json);
    expect(map.connections.first.socketLabel, 'In 1');
    expect(map.connections[11].socketLabel, 'In 12');
    expect(map.connections[12].socketLabel, 'Out 1');
    expect(map.connections.last.socketLabel, 'Out 8');
    expect(map.connections.last.connected, isFalse);
    final rows = json['connections'] as List;
    json['connections'] = rows.reversed.toList();
    expect(PatchMap.fromJson(json).toJson(), map.toJson());
  });

  test(
    'clearing destination preserves cable metadata and leaves source untouched',
    () {
      final map = PatchMap.fromJson(fixture()['patch_helper']);
      final cleared = map.withConnection(
        map.connections.first.withDestination(''),
      );
      expect(cleared.connections.first.connected, isFalse);
      expect(cleared.connections.first.colour, 4);
      expect(cleared.connections.first.tag, 12);
      expect(cleared.connections.first.group, 'Voice 1');
      expect(map.connections.first.connected, isTrue);
      expect(() => map.connections.clear(), throwsUnsupportedError);
    },
  );

  test('slot codec preserves unrelated fields and independent instances', () {
    final slot = <String, dynamic>{
      'guid': 'ThPh',
      'parameters': [1],
      'mapping': {'custom': true},
      ...fixture(),
    };
    final before = jsonEncode(slot);
    final map = PatchMapPresetCodec.readSlot(slot);
    final written = PatchMapPresetCodec.writeSlot(
      slot,
      map.withConnection(map.connections.first.withDestination('other')),
    );
    expect(written['parameters'], [1]);
    expect(written['mapping'], {'custom': true});
    expect(jsonEncode(slot), before);
    expect(
      PatchMapPresetCodec.readSlot({
        'guid': 'ThPh',
      }).connections.first.connected,
      isFalse,
    );
    expect(
      () => PatchMapPresetCodec.readSlot({'guid': 'gain'}),
      throwsFormatException,
    );
    final future = {
      'guid': 'ThPh',
      'patch_helper': {...map.toJson(), 'version': 2},
    };
    expect(
      () => PatchMapPresetCodec.writeSlot(future, map),
      throwsFormatException,
    );
  });

  test(
    'rejects malformed data, unknown versions, and unsupported text without truncation',
    () {
      void reject(void Function(Map<String, dynamic>) mutate) {
        final json = fixture()['patch_helper'] as Map<String, dynamic>;
        mutate(json);
        expect(() => PatchMap.fromJson(json), throwsFormatException);
      }

      reject((json) => json['version'] = 2);
      reject((json) => json['version'] = 1.0);
      reject((json) => json.remove('title'));
      reject((json) => json['extra'] = true);
      for (final text in ['x' * 64, 'bad\ntext', 'café', 'a\u0000b']) {
        reject((json) => json['title'] = text);
        reject((json) => json['connections'][0]['destination'] = text);
      }
      reject((json) => json['connections'][0]['group'] = 'x' * 33);
      reject((json) => json['connections'][1]['socket'] = 0);
      reject((json) => json['connections'].removeLast());
      for (final key in ['socket', 'colour', 'tag']) {
        for (final value in [-1, 999, 1.5, '1', null]) {
          reject((json) => json['connections'][0][key] = value);
        }
      }
    },
  );

  test('accepts exact text boundaries', () {
    final connection = PatchConnection(
      socket: 0,
      destination: 'x' * 63,
      group: 'y' * 32,
      tag: 12,
      colour: 11,
    );
    final map = PatchMap(
      title: 'z' * 63,
      connections: [connection, ...PatchMap.empty().connections.skip(1)],
    );
    expect(PatchMap.fromJson(map.toJson()).toJson(), map.toJson());
  });
}
