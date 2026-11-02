import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late DistingCubit cubit;
  late ToolRegistry registry;
  const name = 'Offline save destination';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    expect(
      await MetadataImportService(database).importFromJson(
        await File('assets/metadata/full_metadata.json').readAsString(),
      ),
      isTrue,
    );
    await AlgorithmMetadataService().initialize(database);
    cubit = DistingCubit(database, midiCommand: MockMidiCommand());
    await cubit.goOffline();
    registry = ToolRegistry(cubit);
    final created =
        jsonDecode(
              await registry.executeTool('new', {
                'name': name,
                'algorithms': [
                  {
                    'guid': 'attn',
                    'specifications': [2],
                  },
                ],
              }),
            )
            as Map<String, dynamic>;
    expect(created['success'], isTrue, reason: '$created');
    bool ready(DistingState state) =>
        state is DistingStateSynchronized &&
        state.slots.length == 1 &&
        state.slots.single.parameters.length == 21;
    if (!ready(cubit.state)) {
      await cubit.stream.firstWhere(ready).timeout(const Duration(seconds: 5));
    }
    await cubit.requireDisting().setParameterValue(0, 1, 1);
    await cubit.requireDisting().setParameterValue(0, 11, 1);
    final initialSave =
        jsonDecode(await registry.executeTool('save', {}))
            as Map<String, dynamic>;
    expect(initialSave['success'], isTrue, reason: '$initialSave');
    // Stage runtime edits without saving. The save facade must write them to
    // the database rather than merely returning a successful message.
    final manager = (cubit.state as DistingStateSynchronized).disting;
    await manager.setParameterValue(0, 1, 3);
    await manager.setParameterValue(0, 11, 4);
    await manager.setParameterValue(0, 8, 0);
    await manager.setParameterValue(0, 18, 0);
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  for (final chat in [false, true]) {
    final facade = chat ? 'built-in chat' : 'external MCP';
    Future<Map<String, dynamic>> save() async =>
        jsonDecode(
              chat
                  ? await ToolBridgeService(registry).executeTool('save', {})
                  : await registry.executeTool('save', {}),
            )
            as Map<String, dynamic>;

    test(
      '$facade save says Saved locally and persists values plus specs',
      () async {
        final preset = (await database.presetsDao.getPresetByName(name))!;
        final before = (await database.presetsDao.getFullPresetDetails(
          preset.id,
        ))!;
        expect(before.slots.single.parameterValues[1], 1);
        final response = await save();
        expect(response['success'], isTrue, reason: '$response');
        expect(response['message'], startsWith('Saved locally'));
        expect(
          (response['message'] as String).toLowerCase(),
          isNot(contains('device')),
        );
        expect(response['destination'], 'local_database');
        expect(response['device_write_confirmed'], isFalse);
        final persisted = (await database.presetsDao.getFullPresetDetails(
          preset.id,
        ))!;
        expect(persisted.slots.single.algorithm.guid, 'attn');
        expect(persisted.slots.single.specificationValues, [2]);
        expect(persisted.slots.single.parameterValues[1], 3);
        expect(persisted.slots.single.parameterValues[11], 4);
        expect(persisted.slots.single.parameterValues[8], 0);
        expect(persisted.slots.single.parameterValues[18], 0);
        final reopened = OfflineDistingMidiManager(database);
        await reopened.initializeFromDb(persisted);
        expect((await reopened.requestAlgorithmGuid(0))?.specifications, [2]);
        expect((await reopened.requestParameterValue(0, 1))?.value, 3);
        expect((await reopened.requestParameterValue(0, 11))?.value, 4);
      },
    );

    test(
      '$facade failed database save returns error and leaves stored data intact',
      () async {
        final preset = (await database.presetsDao.getPresetByName(name))!;
        await database.customStatement(
          'CREATE TRIGGER reject_offline_save '
          'BEFORE INSERT ON presets BEGIN SELECT RAISE(ABORT, \'test save rejected\'); END',
        );
        final response = await save();
        expect(response['success'], isFalse, reason: '$response');
        expect(response['error'], contains('test save rejected'));
        expect(response.containsKey('message'), isFalse);
        final unchanged = (await database.presetsDao.getFullPresetDetails(
          preset.id,
        ))!;
        expect(unchanged.slots.single.specificationValues, [2]);
        expect(unchanged.slots.single.parameterValues[1], 1);
        expect(unchanged.slots.single.parameterValues[11], 1);
      },
    , tags: ['regression']);
  }
}
