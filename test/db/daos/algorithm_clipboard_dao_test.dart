import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/constants.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  AlgorithmEntry algo(String guid, String name) => AlgorithmEntry(
    guid: guid,
    name: name,
    numSpecifications: 0,
    pluginFilePath: null,
  );

  FullPresetSlot slot(
    int slotIndex,
    String guid, {
    List<int> specificationValues = const [],
    Map<int, int> parameterValues = const {},
    Map<int, PackedMappingData> mappings = const {},
    String? customName,
  }) => FullPresetSlot(
    slot: PresetSlotEntry(
      id: -1,
      presetId: -1,
      slotIndex: slotIndex,
      algorithmGuid: guid,
      customName: customName,
    ),
    algorithm: algo(guid, guid),
    specificationValues: specificationValues,
    parameterValues: parameterValues,
    parameterStringValues: const {},
    mappings: mappings,
  );

  FullPresetDetails clipboard(List<FullPresetSlot> slots) => FullPresetDetails(
    preset: PresetEntry(
      id: -1,
      name: 'ignored-name',
      lastModified: DateTime(2024, 1, 1),
      isTemplate: false,
    ),
    slots: slots,
  );

  group('Algorithm clipboard DAO', () {
    test('getClipboardTemplate returns null when empty', () async {
      expect(await database.presetsDao.getClipboardTemplate(), isNull);
      expect(await database.presetsDao.clipboardSlotCount(), 0);
    });

    test(
      'saveClipboardTemplate pins reserved name/category and reindexes',
      () async {
        await database.metadataDao.upsertAlgorithms([
          algo('ALG1', 'Alg 1'),
          algo('ALG2', 'Alg 2'),
        ]);

        final mapping = PackedMappingData(
          source: 1,
          cvInput: 2,
          isUnipolar: false,
          isGate: false,
          volts: 1,
          delta: 10,
          midiChannel: 0,
          midiMappingType: MidiMappingType.cc,
          midiCC: 5,
          isMidiEnabled: true,
          isMidiSymmetric: false,
          isMidiRelative: false,
          midiMin: 0,
          midiMax: 127,
          i2cCC: 0,
          isI2cEnabled: false,
          isI2cSymmetric: false,
          i2cMin: 0,
          i2cMax: 16383,
          perfPageIndex: 0,
          version: 5,
        );

        final id = await database.presetsDao.saveClipboardTemplate(
          clipboard([
            slot(
              7,
              'ALG1',
              specificationValues: const [4],
              parameterValues: {1: 42},
              mappings: {1: mapping},
            ),
            slot(99, 'ALG2', customName: 'Renamed'),
          ]),
        );

        final loaded = await database.presetsDao.getClipboardTemplate();
        expect(loaded, isNotNull);
        expect(loaded!.preset.id, id);
        expect(loaded.preset.name, Constants.algorithmClipboardPresetName);
        expect(loaded.preset.category, Constants.algorithmClipboardCategory);
        expect(loaded.preset.isTemplate, isTrue);

        // Slots are reindexed to 0..n-1 regardless of source slotIndex.
        expect(loaded.slots.length, 2);
        expect(loaded.slots[0].slot.slotIndex, 0);
        expect(loaded.slots[1].slot.slotIndex, 1);
        expect(loaded.slots[0].slot.algorithmGuid, 'ALG1');
        expect(loaded.slots[0].specificationValues, const [4]);
        expect(loaded.slots[0].parameterValues[1], 42);
        expect(loaded.slots[0].mappings[1], isNotNull);
        expect(loaded.slots[1].slot.customName, 'Renamed');

        expect(await database.presetsDao.clipboardSlotCount(), 2);
      },
    );

    test('saveClipboardTemplate replaces prior clipboard contents', () async {
      await database.metadataDao.upsertAlgorithms([
        algo('ALG1', 'Alg 1'),
        algo('ALG2', 'Alg 2'),
      ]);

      await database.presetsDao.saveClipboardTemplate(
        clipboard([slot(0, 'ALG1')]),
      );
      expect(await database.presetsDao.clipboardSlotCount(), 1);

      // Re-save with different contents — must reuse the same row (single
      // clipboard), not create a second one.
      await database.presetsDao.saveClipboardTemplate(
        clipboard([slot(0, 'ALG2'), slot(1, 'ALG1')]),
      );

      final loaded = await database.presetsDao.getClipboardTemplate();
      expect(loaded, isNotNull);
      expect(loaded!.slots.length, 2);
      expect(loaded.slots[0].slot.algorithmGuid, 'ALG2');
      expect(loaded.slots[1].slot.algorithmGuid, 'ALG1');

      // Only one clipboard row exists.
      final allTemplates = await database.presetsDao.getTemplates();
      expect(allTemplates, isEmpty);
    }, tags: ['regression']);

    test('clipboard is hidden from getTemplates()', () async {
      await database.metadataDao.upsertAlgorithms([algo('ALG1', 'Alg 1')]);

      // Add a normal user template alongside the clipboard.
      await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'User Template',
            lastModified: DateTime.now(),
            isTemplate: true,
            category: 'Reverbs',
          ),
          slots: [slot(0, 'ALG1')],
        ),
        isTemplate: true,
      );
      await database.presetsDao.saveClipboardTemplate(
        clipboard([slot(0, 'ALG1')]),
      );

      final templates = await database.presetsDao.getTemplates();
      expect(templates.length, 1);
      expect(templates.single.preset.name, 'User Template');
    });

    test('clearClipboardTemplate removes the clipboard row', () async {
      await database.metadataDao.upsertAlgorithms([algo('ALG1', 'Alg 1')]);

      await database.presetsDao.saveClipboardTemplate(
        clipboard([slot(0, 'ALG1')]),
      );
      expect(await database.presetsDao.clipboardSlotCount(), 1);

      await database.presetsDao.clearClipboardTemplate();
      expect(await database.presetsDao.getClipboardTemplate(), isNull);
      expect(await database.presetsDao.clipboardSlotCount(), 0);

      // Clearing an already-empty clipboard is a no-op.
      await database.presetsDao.clearClipboardTemplate();
    });
  });
}
