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
  test('invalid long edits never enter automatic synchronization', () async {
    final device = PatchMapDevice();
    final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), download);
    addTearDown(cubit.close);
    await cubit.load();
    expect(
      () => cubit.queueConnection(0, 'destination', 'D' * 33),
      throwsFormatException,
    );
    expect(
      () => cubit.queueConnection(0, 'group', 'G' * 33),
      throwsFormatException,
    );
    expect(cubit.state.pending, isFalse);
    cubit.queueConnection(0, 'destination', 'D' * 32);
    cubit.queueConnection(0, 'group', 'G' * 32);
    await cubit.synchronize();
    expect(cubit.state.pending, isFalse);
    expect(device.map.connections.first.destination, 'D' * 32);
    expect(device.map.connections.first.group, 'G' * 32);
  });

  test(
    'SD Lua owns dialog labels and choices; invalid or stale choices cannot write',
    () async {
      final device = PatchMapDevice();
      var source = utf8.decode((await download('/programs/helper/ThPh.lua'))!);
      source = source.replaceAll(
        "title = 'Add expander'",
        "title = 'Choose hardware'",
      );
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => Uint8List.fromList(utf8.encode(source)),
        companionCheckInterval: Duration.zero,
      );
      await cubit.load();
      final action = cubit.state.document!.actions.single;
      expect(action.title, 'Choose hardware');
      expect(action.choices.values, PatchMap.expanderTypes);
      await cubit.chooseAction('set_title', 0);
      await cubit.chooseAction('add_expander', 42);
      expect(device.map.expanders, isEmpty);
      // A background source update can withdraw a choice while its dialog is open.
      source = source.replaceAll("{ label = model, value = i - 1 }", "nil");
      await cubit.refresh();
      expect(cubit.state.error, isNotNull);
      await cubit.chooseAction(action.id, 0);
      expect(device.map.expanders, isEmpty);
      await cubit.close();
    },
  );

  test(
    'choice schema rejects unsupported actions, duplicate and invalid model values',
    () {
      Map<String, Object?> definition(List<Object?> choices) => {
        'id': 'add_expander',
        'label': 'Add expander',
        'dialog': {
          'type': 'choice_dialog',
          'title': 'Models',
          'cancel': 'Cancel',
          'choices': choices,
        },
      };
      for (final choices in [
        <Object?>[],
        [
          {'value': -1, 'label': 'Bad'},
        ],
        [
          {'value': 4, 'label': 'Bad'},
        ],
        [
          {'value': 0, 'label': 'One'},
          {'value': 0, 'label': 'Two'},
        ],
      ]) {
        expect(
          () => CompanionChoiceAction.parse(definition(choices)),
          throwsFormatException,
        );
      }
      expect(
        () => CompanionChoiceAction.parse({'id': 'set_title'}),
        throwsFormatException,
      );
    },
  );

  test('missing Lua recovers automatically when the file appears', () async {
    final device = PatchMapDevice();
    var available = false;
    var reads = 0;
    final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), (path) async {
      reads++;
      return available ? download(path) : null;
    }, retryDelay: Duration.zero);
    await cubit.load();
    expect(cubit.state.error, contains('/programs/helper/'));
    expect(device.frames, isEmpty);
    available = true;
    await cubit.synchronize();
    expect(cubit.state.editable, isTrue);
    expect(reads, 2);
    await cubit.close();
  });

  test(
    'background checks pick up changed SD Lua without reloading the map',
    () async {
      final device = PatchMapDevice();
      var source = utf8.decode((await download('/programs/helper/ThPh.lua'))!);
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => Uint8List.fromList(utf8.encode(source)),
        companionCheckInterval: Duration.zero,
      );
      await cubit.load();
      final map = cubit.state.map;
      source = source.replaceAll(
        "destination = 'Destination'",
        "destination = 'Connected to'",
      );
      await cubit.synchronize();
      expect(cubit.state.document!.labels['destination'], 'Connected to');
      expect(identical(cubit.state.map, map), isTrue);
      expect(device.frames.last['request']![7], 9);
      await cubit.close();
    },
  );

  test(
    'SD Lua scratch cache reuses files, refreshes, separates devices and recovers',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'companion-cache-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      var downloads = 0;
      Uint8List? data = Uint8List.fromList(utf8.encode('first Lua'));
      Future<Uint8List?> fetch(String path) async {
        expect(path, '/programs/helper/ThPh.lua');
        downloads++;
        return data;
      }

      Future<SdCardCompanion> load({
        bool refresh = false,
        String device = 'NT one',
      }) => SdCardCompanion.load(
        fetch,
        guid: 'ThPh',
        cacheKey: device,
        refresh: refresh,
        temporaryDirectory: () async => root,
      );
      expect((await load()).source, 'first Lua');
      data = Uint8List.fromList(utf8.encode('updated Lua'));
      expect((await load()).source, 'first Lua');
      expect(downloads, 1);
      expect((await load(refresh: true)).source, 'updated Lua');
      expect(downloads, 2);
      expect((await load(device: 'NT two')).source, 'updated Lua');
      expect(downloads, 3);
      data = null;
      await expectLater(load(refresh: true), throwsFormatException);
      expect((await load()).source, 'updated Lua');
      final files = await root
          .list(recursive: true)
          .where((f) => f is File && f.path.endsWith('.lua'))
          .cast<File>()
          .toList();
      expect(files, hasLength(2));
      for (final file in files) {
        await file.writeAsBytes([0xff]);
      }
      data = Uint8List.fromList(utf8.encode('repaired Lua'));
      expect((await load()).source, 'repaired Lua');
      expect(downloads, 5);
      for (final file in files) {
        await file.delete();
      }
      expect((await load()).source, 'repaired Lua');
      expect(downloads, 6);
    },
  );

  test('cache failures do not block the established SD transfer', () async {
    final source = await SdCardCompanion.load(
      download,
      guid: 'ThPh',
      cacheKey: 'NT',
      temporaryDirectory: () async =>
          throw const FileSystemException('unavailable'),
    );
    expect(source.source, contains('return companion'));
  });

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

  test('automatic field edits merge with concurrent NT changes', () async {
    final device = PatchMapDevice();
    final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), download);
    await cubit.load();
    cubit.queueConnection(0, 'destination', 'Rings');
    cubit.queueConnection(0, 'colour', 4);
    expect(cubit.state.map!.connections[0].colour, 4);
    expect(cubit.state.pending, isTrue);
    device.changeProperty(2, 3);
    await cubit.synchronize();
    expect(device.map.connections[0].destination, 'Rings');
    expect(device.map.connections[0].colour, 4);
    expect(device.map.connections[0].tag, 3);
    expect(cubit.state.pending, isFalse);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  test('latest edit survives a lost acknowledgement and converges', () async {
    final device = PatchMapDevice();
    final cubit = PatchMapEditorCubit(
      PatchMapClient(device, 0),
      download,
      retryDelay: Duration.zero,
    );
    await cubit.load();
    device.holdWrite = Completer<void>();
    device.loseReply = true;
    cubit.queueConnection(0, 'destination', 'First');
    final writing = cubit.synchronize();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cubit.queueConnection(0, 'destination', 'Latest');
    device.holdWrite!.complete();
    await writing;
    expect(cubit.state.map!.connections[0].destination, 'Latest');
    expect(cubit.state.pending, isTrue);
    device.loseReply = false;
    device.holdWrite = null;
    await cubit.synchronize();
    expect(device.map.connections[0].destination, 'Latest');
    expect(device.revision, 2);
    expect(cubit.state.pending, isFalse);
    await cubit.close();
  });

  test(
    'already applied edit is acknowledged by reread without a duplicate write',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        download,
        retryDelay: Duration.zero,
      );
      await cubit.load();
      device.loseReply = true;
      cubit.queueConnection(0, 'colour', 8);
      await cubit.synchronize();
      expect(cubit.state.pending, isTrue);
      device.loseReply = false;
      await cubit.synchronize();
      expect(device.revision, 1);
      expect(cubit.state.pending, isFalse);
      expect(cubit.state.error, isNull);
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
    'lost write acknowledgement recovers by reading without replaying writes',
    () async {
      final device = PatchMapDevice();
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        download,
        retryDelay: Duration.zero,
      );
      await cubit.load();
      device.holdWrite = Completer<void>();
      device.loseReply = true;
      final pending = cubit.setConnection(
        PatchConnection(socket: 0, destination: 'Changed'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.state.busy, isTrue);
      expect(cubit.state.map!.connections[0].destination, '');
      device.holdWrite!.complete();
      await pending;
      expect(cubit.state.editable, isFalse);
      expect(cubit.state.map!.connections[0].destination, '');
      device.holdWrite = null;
      device.loseReply = false;
      await cubit.synchronize();
      expect(cubit.state.map!.connections[0].destination, 'Changed');
      expect(device.revision, 1);
      expect(device.frames.where((f) => f['request']?[7] == 3), isEmpty);
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
