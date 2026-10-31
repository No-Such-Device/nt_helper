import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor_cubit.dart';
import '../../support/patch_map_device.dart';

Future<Uint8List?> download(String _) async =>
    File('test/fixtures/patch_map/patch_helper.lua').readAsBytesSync();

void main() {
  test(
    'Lua controls reusable record-section labels, columns and placement',
    () async {
      final device = PatchMapDevice();
      device.map = device.map.addAux(44);
      final source = utf8
          .decode((await download(''))!)
          .replaceAll(
            "id = 'aux', source = 'aux'",
            "id = 'notes', source = 'aux'",
          )
          .replaceAll("title = 'AUX buses'", "title = 'Internal signals'")
          .replaceAll("row_label = 'AUX'", "row_label = 'Signal'")
          .replaceAll('after_socket = 19', 'after_socket = 11')
          .replaceAll("label = 'Description'", "label = 'Purpose'");
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => Uint8List.fromList(utf8.encode(source)),
      );
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.error, isNull);
      final section = cubit.state.document!.recordSections.single;
      expect(section.id, 'notes');
      expect(section.title, 'Internal signals');
      expect(section.afterSocket, 11);
      expect(section.columns.map((column) => column.type), [
        'label',
        'text',
        'text',
        'remove',
      ]);
      expect(section.fields.first.label, 'Purpose');
      expect(section.label(device.map.aux.single.toJson()), 'Signal 44');
    },
  );

  test(
    'all AUX identities coexist with legacy banks and survive unrelated edits',
    () {
      var map = PatchMap.empty();
      for (var i = 0; i < PatchMap.maxExpanders; i++) {
        map = map.addExpander(i % 4);
      }
      for (var bus = 44; bus > 0; bus--) {
        map = map.addAux(bus);
      }
      map = map.withAux(PatchAux(bus: 44, description: 'Return', group: 'FX'));
      map = map
          .withConnection(PatchConnection(socket: 123, destination: 'Last'))
          .renameExpander(0, 'First')
          .moveExpander(0, 12);
      expect(map.aux.map((row) => row.bus), List.generate(44, (i) => i + 1));
      final saved = map.toJson();
      expect(saved['version'], 3);
      expect(PatchMap.fromJson(saved).toJson(), saved);
      expect(map.aux.last.description, 'Return');
      for (final bus in [0, 45]) {
        expect(() => PatchAux(bus: bus), throwsFormatException);
      }
      expect(() => map.addAux(44), throwsStateError);
      expect(
        () => PatchAux(bus: 1, description: 'x' * 33),
        throwsFormatException,
      );
      expect(
        () => PatchMap.fromJson({
          ...saved,
          'aux': [map.aux.first.toJson(), map.aux.first.toJson()],
        }),
        throwsFormatException,
      );
      expect(map.removeAux(44).addAux(44).aux.last.description, isEmpty);
    },
  );

  test('new client negotiates old plugins without AUX actions', () async {
    final device = PatchMapDevice()..supportsAux = false;
    final client = PatchMapClient(device, 0);
    final cubit = PatchMapEditorCubit(client, download);
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.error, isNull);
    expect(client.supportsAux, isFalse);
    expect(cubit.state.document!.recordSections, isEmpty);
    expect(device.frames.take(2).map((f) => f['request']![21]), [3, 2]);
    await expectLater(client.addAux(1), throwsA(isA<PatchMapSyncException>()));
    expect(device.map.aux, isEmpty);
  });

  test(
    'AUX edits merge, follow native selection and cannot be remapped by Lua',
    () async {
      final device = PatchMapDevice();
      device.map = device.map.addAux(44);
      final cubit = PatchMapEditorCubit(PatchMapClient(device, 0), download);
      addTearDown(cubit.close);
      await cubit.load();
      cubit.queueAux(44, 'description', 'Return');
      device.map = device.map.withAux(
        PatchAux(bus: 44, group: 'Native change'),
      );
      device.revision++;
      await cubit.synchronize();
      expect(device.map.aux.single.description, 'Return');
      expect(device.map.aux.single.group, 'Native change');
      expect(cubit.state.pending, isFalse);
      device.selectedAux = 44;
      await cubit.refresh();
      expect(cubit.state.document!.focusRecord, ('aux', 44));
      expect(cubit.state.document!.focusSocket, isNull);
      final source = utf8
          .decode((await download(''))!)
          .replaceAll(
            'return { type = event.type, bus = event.bus }',
            'return { type = event.type, bus = 1 }',
          );
      final hostile = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        (_) async => Uint8List.fromList(utf8.encode(source)),
      );
      addTearDown(hostile.close);
      await hostile.load();
      await hostile.chooseAction('add_aux', 3);
      expect(hostile.state.error, contains('changed the action'));
      expect(device.map.aux.map((row) => row.bus), [44]);
    },
  );

  test(
    'AUX edit recovers lost acknowledgement and retains the latest desired value',
    () async {
      final device = PatchMapDevice();
      device.map = device.map.addAux(3);
      final cubit = PatchMapEditorCubit(
        PatchMapClient(device, 0),
        download,
        retryDelay: Duration.zero,
      );
      addTearDown(cubit.close);
      await cubit.load();
      device.holdWrite = Completer<void>();
      device.loseReply = true;
      cubit.queueAux(3, 'description', 'First');
      final writing = cubit.synchronize();
      await device.writeStarted.future;
      cubit.queueAux(3, 'description', 'Latest');
      device.holdWrite!.complete();
      await writing;
      expect(cubit.state.map!.aux.single.description, 'Latest');
      device.loseReply = false;
      device.holdWrite = null;
      await cubit.synchronize();
      expect(device.map.aux.single.description, 'Latest');
      expect(cubit.state.pending, isFalse);
      expect(device.revision, 2);
    },
  );

  test('AUX lifecycle has identical C++ and Dart wire transcript', () async {
    final device = PatchMapDevice();
    final client = PatchMapClient(device, 0, lease: 42);
    await client.load();
    await client.addAux(44);
    await client.addAux(3);
    await client.setAux(
      PatchAux(bus: 44, description: 'Stereo return L', group: 'FX'),
    );
    expect((await client.refresh()).aux.map((row) => row.bus), [3, 44]);
    await client.removeAux(44);
    await client.addAux(44);
    final recalled = await client.load();
    expect(recalled.aux.last.description, isEmpty);
    expect(recalled.aux.last.group, isEmpty);
    final wire = File('test/fixtures/patch_map/aux-session.json');
    if (Platform.environment['UPDATE_PATCH_FIXTURE'] == '1') {
      wire.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(device.frames)}\n',
      );
    } else {
      expect(device.frames, jsonDecode(wire.readAsStringSync()));
    }
  });
}
