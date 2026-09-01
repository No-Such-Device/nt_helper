import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Offline LFO routing', () {
    late AppDatabase database;
    late DistingCubit cubit;
    late OfflineDistingMidiManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      database = AppDatabase.forTesting(NativeDatabase.memory());

      final metadataJson = await File(
        'assets/metadata/full_metadata.json',
      ).readAsString();
      final imported = await MetadataImportService(
        database,
      ).importFromJson(metadataJson);
      expect(imported, isTrue);

      final lfo = await database.metadataDao.getAlgorithmByGuid('lfo ');
      expect(lfo, isNotNull);

      final presetId = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Offline LFO',
            lastModified: DateTime.now(),
            isTemplate: false,
          ),
          slots: [
            FullPresetSlot(
              slot: PresetSlotEntry(
                id: -1,
                presetId: -1,
                slotIndex: 0,
                algorithmGuid: 'lfo ',
                customName: null,
              ),
              algorithm: lfo!,
              parameterValues: const {},
              parameterStringValues: const {},
              mappings: const {},
            ),
          ],
        ),
      );

      final preset = await database.presetsDao.getFullPresetDetails(presetId);
      manager = OfflineDistingMidiManager(database);
      await manager.initializeFromDb(preset);
      cubit = DistingCubit(database, midiCommand: MockMidiCommand());
    });

    tearDown(() async {
      await cubit.close();
      await database.close();
    });

    test('uses bundled io metadata for LFO ports in offline mode', () async {
      final slot = await cubit.fetchSlot(manager, 0);
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
      );

      expect(
        routing.inputPorts.map((port) => port.name),
        containsAll(['Clock input', 'Reset input']),
      );
      expect(
        routing.outputPorts.map((port) => port.name),
        containsAll(['1:Output', '2:Output']),
      );
      expect(
        routing.inputPorts.map((port) => port.name),
        isNot(contains('1:Output')),
      );
      expect(
        [
          ...routing.inputPorts,
          ...routing.outputPorts,
        ].map((port) => port.name),
        isNot(contains('1:Output mode')),
      );

      final lfoOutput = routing.outputPorts.singleWhere(
        (port) => port.name == '1:Output',
      );
      expect(lfoOutput.modeParameterNumber, 5);

      final secondLfoOutput = routing.outputPorts.singleWhere(
        (port) => port.name == '2:Output',
      );
      expect(secondLfoOutput.modeParameterNumber, 22);
    });
  });
}
