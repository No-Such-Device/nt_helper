import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/algorithm_controller/companion_table.dart';
import 'package:nt_helper/algorithm_controller/sd_card_companion.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor_cubit.dart';
import '../../support/patch_map_device.dart';

Future<Uint8List?> download(String path) async {
  expect(path, '/programs/helper/ThPh.lua');
  return File('test/fixtures/patch_map/patch_helper.lua').readAsBytes();
}

void main() {
  test(
    'notification cannot return a write and failure keeps the last view',
    () async {
      final device = PatchMapDevice();
      final source = File('test/fixtures/patch_map/patch_helper.lua')
          .readAsStringSync()
          .replaceAll(
            'return companion',
            "companion.on_change = function(s,c) return {type='set_title',title='Wrong'} end; return companion",
          );
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => Uint8List.fromList(utf8.encode(source)),
      );
      await cubit.load();
      final previous = cubit.state.document;
      device.changeProperty(0, 2);
      await cubit.refresh();
      expect(cubit.state.error, contains('Unsupported companion view'));
      expect(identical(cubit.state.document, previous), isTrue);
      expect(device.map.title, 'Patch Helper');
      expect(device.frames.last['request']![7], 9);
      await cubit.close();
    },
  );

  test(
    'NT properties notify Lua, unchanged polls are quiet, and live wire matches native fixture',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0, lease: 50),
        download,
      );
      await cubit.load();
      await cubit.refresh();
      expect(cubit.state.document!.focusSocket, 0);
      final same = cubit.state;
      final before = device.frames.length;
      await cubit.refresh();
      expect(identical(cubit.state, same), isTrue);
      expect(device.frames.length, before + 1);
      device.changeProperty(0, 20);
      await cubit.refresh();
      expect(cubit.state.document!.focusSocket, 19);
      device.changeProperty(1, 4);
      device.changeProperty(2, 7);
      await cubit.refresh();
      expect(cubit.state.map!.connections[19].colour, 4);
      expect(cubit.state.map!.connections[19].tag, 7);
      expect(cubit.state.document!.focusSocket, isNull);
      expect(cubit.state.error, isNull);
      // No user gesture means no outgoing write commands at all.
      expect(
        device.frames
            .where((f) => f.containsKey('request'))
            .map((f) => f['request']![7]),
        everyElement(isIn([1, 2, 6, 9])),
      );
      final wire = File('test/fixtures/patch_map/live-session.json');
      if (Platform.environment['UPDATE_PATCH_FIXTURE'] == '1') {
        wire.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(device.frames)}\n',
        );
      } else {
        expect(device.frames, jsonDecode(wire.readAsStringSync()));
      }
      await cubit.close();
    },
  );

  test(
    'NT change preserves drafts and blocks writes until explicit reload',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        download,
        hasUnsentEdits: () => true,
      );
      await cubit.load();
      final original = cubit.state.map;
      device.changeProperty(2, 3);
      await cubit.refresh();
      expect(identical(cubit.state.map, original), isTrue);
      expect(cubit.state.error, contains('unsent edits are retained'));
      final before = device.frames.length;
      await cubit.setTitle('stale draft');
      expect(device.frames.length, before);
      await cubit.load();
      expect(cubit.state.map!.connections[0].tag, 3);
      await cubit.close();
    },
  );

  test(
    'expired lease stops watch and cannot silently follow another preset',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), download);
      await cubit.load();
      final original = cubit.state.map;
      device.lease = 0;
      await cubit.refresh();
      expect(cubit.state.error, contains('session changed'));
      expect(identical(cubit.state.map, original), isTrue);
      final before = device.frames.length;
      await cubit.refresh();
      expect(device.frames.length, before);
      await cubit.close();
    },
  );

  test('notifications fall back to render for older companions', () async {
    const source =
        "return {api_version=1, guid='ThPh', render=function(s) return {seen=s.properties.tag} end}";
    final script = await SdCardCompanion.load(
      (_) async => Uint8List.fromList(utf8.encode(source)),
      guid: 'ThPh',
    );
    expect(
      await script.evaluate(
        {
          'properties': {'tag': 9},
        },
        change: {'type': 'nt_changed'},
      ),
      {'seen': 9},
    );
  });

  test('closing during SD download cannot open a stale device lease', () async {
    final device = PatchMapDevice();
    final source = Completer<Uint8List?>();
    final cubit = PatchMapEditorCubit(
      PatchMapClient(device, 0),
      (_) => source.future,
    );
    final loading = cubit.load();
    await cubit.close();
    source.complete(await download('/programs/helper/ThPh.lua'));
    await loading;
    expect(device.frames, isEmpty);
  });
  test(
    'SD discovery is GUID-based and rejects unsafe filenames and mismatched scripts',
    () async {
      expect(SdCardCompanion.pathForGuid('ThPh'), '/programs/helper/ThPh.lua');
      expect(SdCardCompanion.pathForGuid('Test'), '/programs/helper/Test.lua');
      expect(() => SdCardCompanion.pathForGuid('../x'), throwsFormatException);
      const source =
          "return {api_version=1, guid='Test', render=function(s) return {ok=true} end}";
      final other = await SdCardCompanion.load((path) async {
        expect(path, '/programs/helper/Test.lua');
        return Uint8List.fromList(utf8.encode(source));
      }, guid: 'Test');
      expect(await other.evaluate({}), {'ok': true});
      final mismatch = await SdCardCompanion.load(
        (_) async => Uint8List.fromList(utf8.encode(source)),
        guid: 'ThPh',
      );
      await expectLater(mismatch.evaluate({}), throwsFormatException);
    },
  );
  test(
    'SD companion projects the approved grids and sends acknowledged state actions',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0, lease: 42),
        download,
      );
      await cubit.load();
      expect(cubit.state.error, isNull);
      expect(cubit.state.document!.groups.map((g) => (g.count, g.columns)), [
        (12, 4),
        (8, 2),
      ]);
      await cubit.addExpander(0);
      await cubit.renameExpander(0, 'Pitch');
      await cubit.addExpander(1);
      await cubit.setConnection(
        PatchConnection(
          socket: 20,
          destination: 'Plaits V/oct',
          colour: 9,
          tag: 2,
          group: 'Voice',
        ),
      );
      await cubit.moveExpander(0, 1);
      expect(cubit.state.error, isNull);
      expect(cubit.state.map!.expanders.last.name, 'Pitch');
      expect(cubit.state.map!.connections[28].destination, 'Plaits V/oct');
      await cubit.load();
      expect(cubit.state.document!.groups.last.title, 'Pitch · NTX-8CV');
      expect(cubit.state.document!.groups.map((g) => (g.count, g.columns)), [
        (12, 4),
        (8, 2),
        (8, 1),
        (8, 1),
      ]);
      final wire = File('test/fixtures/patch_map/expanded-session.json');
      if (Platform.environment['UPDATE_PATCH_FIXTURE'] == '1') {
        wire.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(device.frames)}\n',
        );
      } else {
        expect(device.frames, jsonDecode(wire.readAsStringSync()));
      }
      await cubit.close();
    },
  );
  test(
    'failed writes retain last acknowledged state and require reload',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), download);
      await cubit.load();
      device.holdWrite = Completer<void>();
      device.loseReply = true;
      final pending = cubit.setTitle('Changed');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state.busy, isTrue);
      expect(cubit.state.map!.title, 'Patch Helper');
      device.holdWrite!.complete();
      await pending;
      expect(cubit.state.editable, isFalse);
      expect(cubit.state.map!.title, 'Patch Helper');
      device.holdWrite = null;
      device.loseReply = false;
      await cubit.load();
      expect(cubit.state.map!.title, 'Changed');
      await cubit.close();
    },
  );
  test(
    'missing, incompatible and infinite companions fail without a fallback editor',
    () async {
      final device = PatchMapDevice();
      final missing = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => null,
      );
      await missing.load();
      expect(missing.state.error, contains('Install ThPh.lua'));
      expect(device.frames, isEmpty);
      await missing.close();
      for (final source in ['return {api_version=99}', 'while true do end']) {
        final script = await SdCardCompanion.load(
          (_) async => Uint8List.fromList(utf8.encode(source)),
          guid: 'ThPh',
        );
        await expectLater(
          script.evaluate({'expanders': []}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Lua cannot access filesystem, network, module loading or process APIs',
    () async {
      const source = '''return {api_version=1, guid='ThPh', render=function(s)
      assert(io==nil and os==nil and package==nil and debug==nil and require==nil and load==nil and loadfile==nil and dofile==nil)
      return {ok=true} end}''';
      final script = await SdCardCompanion.load(
        (_) async => Uint8List.fromList(utf8.encode(source)),
        guid: 'ThPh',
      );
      expect(await script.evaluate({}), {'ok': true});
    },
  );
  test('malformed grids are rejected before rendering', () {
    expect(
      () => CompanionTable.parse({
        'type': 'socket_table',
        'version': 1,
        'labels': {},
        'groups': [
          {'start': 0, 'count': 12, 'columns': 5},
        ],
      }, PatchMap.empty()),
      throwsFormatException,
    );
  });
  test(
    'named repeated expanders survive JSON and preserve records on reorder',
    () {
      final map = PatchMap.empty()
          .addExpander(0)
          .addExpander(0)
          .renameExpander(1, 'Right');
      final moved = map
          .withConnection(PatchConnection(socket: 28, destination: 'Pitch'))
          .moveExpander(1, 0);
      expect(moved.connections[20].destination, 'Pitch');
      expect(PatchMap.fromJson(moved.toJson()).expanders.first.name, 'Right');
      expect(map.expanders.last.name, 'Right');
      expect(() => map.expanders.clear(), throwsUnsupportedError);
    },
  );
}
