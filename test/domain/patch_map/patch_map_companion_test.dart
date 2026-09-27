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
  expect(path, '/helper/ThPh.lua');
  return File('test/fixtures/patch_map/patch_helper.lua').readAsBytes();
}

void main() {
  test('closing during SD download cannot open a stale device lease', () async {
    final device = PatchMapDevice();
    final source = Completer<Uint8List?>();
    final cubit = PatchMapEditorCubit(
      PatchMapClient(device, 0),
      (_) => source.future,
    );
    final loading = cubit.load();
    await cubit.close();
    source.complete(await download('/helper/ThPh.lua'));
    await loading;
    expect(device.frames, isEmpty);
  });
  test(
    'SD discovery is GUID-based and rejects unsafe filenames and mismatched scripts',
    () async {
      expect(SdCardCompanion.pathForGuid('ThPh'), '/helper/ThPh.lua');
      expect(SdCardCompanion.pathForGuid('Test'), '/helper/Test.lua');
      expect(() => SdCardCompanion.pathForGuid('../x'), throwsFormatException);
      const source =
          "return {api_version=1, guid='Test', render=function(s) return {ok=true} end}";
      final other = await SdCardCompanion.load((path) async {
        expect(path, '/helper/Test.lua');
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
