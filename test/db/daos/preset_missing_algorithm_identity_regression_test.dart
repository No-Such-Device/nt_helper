import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';

void main() {
  for (final (label, guids) in <(String, List<String>)>[
    ('missing first', ['Xabc', 'lfo ', 'note']),
    ('missing middle', ['lfo ', 'Xabc', 'note']),
    ('missing last', ['lfo ', 'note', 'Xabc']),
    ('all missing', ['Xabc', 'Xdef']),
    ('factory only', ['lfo ', 'note']),
  ]) {
    test(
      '$label preserves every slot and child through save and reload',
      () async {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        try {
          await database.metadataDao.upsertAlgorithms([
            const AlgorithmEntry(
              guid: 'lfo ',
              name: 'LFO',
              numSpecifications: 1,
              pluginFilePath: null,
            ),
            const AlgorithmEntry(
              guid: 'note',
              name: 'Notes',
              numSpecifications: 1,
              pluginFilePath: null,
            ),
          ]);
          final original = FullPresetDetails(
            preset: PresetEntry(
              id: -1,
              name: label,
              lastModified: DateTime(2026),
              isTemplate: false,
            ),
            slots: [
              for (final (index, guid) in guids.indexed) _slot(index, guid),
            ],
          );
          final id = await database.presetsDao.saveFullPreset(original);
          final first = (await database.presetsDao.getFullPresetDetails(id))!;
          _expectPreserved(first, guids);
          final manager = OfflineDistingMidiManager(database);
          await manager.initializeFromDb(first);
          for (final (index, guid) in guids.indexed) {
            expect((await manager.requestAlgorithmGuid(index))?.guid, guid);
          }
          final offlineDetails = (await manager.requestCurrentPresetDetails())!;
          _expectPreserved(offlineDetails, guids);
          await database.presetsDao.saveFullPreset(offlineDetails);
          final second = (await database.presetsDao.getFullPresetDetails(id))!;
          _expectPreserved(second, guids);
          final catalog = await database.metadataDao.getAllAlgorithms();
          expect(
            catalog.map((entry) => entry.guid).toSet(),
            {'lfo ', 'note'},
            reason:
                'unknown slot identity must not create fake catalog metadata',
          );
        } finally {
          await database.close();
        }
      },
    tags: ['regression']);
  }
}

void _expectPreserved(FullPresetDetails details, List<String> guids) {
  expect(details.slots.map((slot) => slot.slot.algorithmGuid), guids);
  for (final (index, slot) in details.slots.indexed) {
    expect(slot.slot.slotIndex, index);
    expect(slot.algorithm.guid, guids[index]);
    expect(slot.slot.customName, 'Slot $index');
    expect(slot.specificationValues, [index + 2]);
    expect(slot.parameterValues, {0: index + 5, 3: index + 21});
    expect(slot.parameterStringValues, {3: 'saved $index'});
    expect(slot.mappings.keys, [3]);
    expect(slot.mappings[3]?.midiCC, 71);
    expect(slot.mappings[3]?.perfPageIndex, 2);
    expect(slot.routing?.routingInfoJson, [1, 13, index]);
  }
}

FullPresetSlot _slot(int index, String guid) => FullPresetSlot(
  slot: PresetSlotEntry(
    id: -1,
    presetId: -1,
    slotIndex: index,
    algorithmGuid: guid,
    customName: 'Slot $index',
  ),
  algorithm: AlgorithmEntry(
    guid: guid,
    name: guid,
    numSpecifications: 1,
    pluginFilePath: null,
  ),
  specificationValues: [index + 2],
  parameterValues: {0: index + 5, 3: index + 21},
  parameterStringValues: {3: 'saved $index'},
  mappings: {
    3: PackedMappingData.filler().copyWith(
      version: 7,
      midiCC: 71,
      midiChannel: 1,
      isMidiEnabled: true,
      perfPageIndex: 2,
    ),
  },
  routing: PresetRoutingEntry(
    presetSlotId: -1,
    routingInfoJson: [1, 13, index],
  ),
);
