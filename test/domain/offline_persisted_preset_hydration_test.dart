import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';

void main() {
  test('hydrates legacy saved slots after reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('offline-preset-');
    final file = File('${directory.path}/presets.sqlite');
    var database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    const lfo = AlgorithmEntry(guid: 'lfo ', name: 'LFO', numSpecifications: 1);
    const plugin = AlgorithmEntry(
      guid: 'bead',
      name: 'Texture Synthesizer 2',
      numSpecifications: 0,
    );
    await database.metadataDao.upsertAlgorithms([lfo, plugin]);
    await database
        .into(database.parameters)
        .insert(
          ParametersCompanion.insert(
            algorithmGuid: lfo.guid,
            parameterNumber: 0,
            name: 'Rate',
            minValue: const Value(0),
            maxValue: const Value(100),
            defaultValue: const Value(50),
          ),
        );

    final presetId = await database.presetsDao.saveFullPreset(
      FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Saved offline preset',
          lastModified: DateTime(2026),
          isTemplate: false,
        ),
        // Deliberately supply reverse order: hydration must use slotIndex.
        slots: [
          FullPresetSlot(
            slot: const PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 1,
              algorithmGuid: 'bead',
              customName: 'Granular voice',
            ),
            algorithm: plugin,
            parameterValues: {0: 12, 34: 99},
            parameterStringValues: {34: 'Saved text'},
            mappings: {},
          ),
          FullPresetSlot(
            slot: const PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'lfo ',
              customName: 'Slow modulation',
            ),
            algorithm: lfo,
            parameterValues: {0: 23},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      ),
    );

    await database.close();
    database = AppDatabase.forTesting(NativeDatabase(file));
    final details = await database.presetsDao.getFullPresetDetails(presetId);
    expect(details, isNotNull);
    expect(details!.slots.map((slot) => slot.slot.algorithmGuid), [
      'lfo ',
      'bead',
    ]);
    expect(
      details.slots.every((slot) => slot.specificationValues.isEmpty),
      isTrue,
    );

    final manager = OfflineDistingMidiManager(database);
    addTearDown(manager.dispose);
    await manager.initializeFromDb(details);

    expect(await manager.requestNumAlgorithmsInPreset(), 2);
    final first = await manager.requestAlgorithmGuid(0);
    expect(first?.guid, 'lfo ');
    expect(first?.name, 'Slow modulation');
    expect((await manager.requestParameterInfo(0, 0))?.name, 'Rate');
    expect((await manager.requestParameterValue(0, 0))?.value, 23);

    // A catalogued plugin remains identifiable even without cached metadata.
    final second = await manager.requestAlgorithmGuid(1);
    expect(second?.guid, 'bead');
    expect(second?.name, 'Granular voice');
    expect((await manager.requestNumberOfParameters(1))?.numParameters, 35);
    expect((await manager.requestParameterValue(1, 34))?.value, 99);
    expect(
      (await manager.requestParameterValueString(1, 34))?.value,
      'Saved text',
    );
    expect(
      (await manager.requestCurrentPresetDetails())?.slots[1].parameterValues,
      {0: 12, 34: 99},
    );
  }, tags: ['regression']);
}
