import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';

void main() {
  test('offline manager retains simulated algorithm decoration', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final manager = OfflineDistingMidiManager(database);
    addTearDown(manager.dispose);

    await database
        .into(database.algorithms)
        .insert(
          AlgorithmsCompanion(
            guid: const Value('test'),
            name: const Value('Test Algorithm'),
            numSpecifications: const Value(0),
          ),
        );
    final presetId = await database.presetsDao.saveFullPreset(
      FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Offline Test',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: const PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'test',
            ),
            algorithm: const AlgorithmEntry(
              guid: 'test',
              name: 'Test Algorithm',
              numSpecifications: 0,
            ),
            parameterValues: const {},
            parameterStringValues: const {},
            mappings: const {},
          ),
        ],
      ),
    );
    await manager.initializeFromDb(
      await database.presetsDao.getFullPresetDetails(presetId),
    );

    expect(manager, isA<AlgorithmVisualStyleWriter>());
    const style = AlgorithmVisualStyle(
      leftIndent: 2,
      lineAbove: true,
      bracket: AlgorithmVisualBracket.open,
    );

    await manager.requestSetAlgorithmVisualStyle(0, style);

    expect((await manager.requestAlgorithmGuid(0))?.visualStyle, style);
  });
}
