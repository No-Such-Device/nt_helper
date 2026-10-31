import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    // Create an in-memory database for testing
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  group('PresetsDao - specification value persistence', () {
    test('saves and loads user-selected slot specifications', () async {
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'quan',
          name: 'Quantizer',
          numSpecifications: 1,
          pluginFilePath: null,
        ),
      ]);

      final presetId = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Four Channel Quantizer',
            lastModified: DateTime.now(),
            isTemplate: true,
          ),
          slots: [
            FullPresetSlot(
              slot: PresetSlotEntry(
                id: -1,
                presetId: -1,
                slotIndex: 0,
                algorithmGuid: 'quan',
                customName: 'Quantizer',
              ),
              algorithm: AlgorithmEntry(
                guid: 'quan',
                name: 'Quantizer',
                numSpecifications: 1,
                pluginFilePath: null,
              ),
              specificationValues: const [4],
              parameterValues: const {},
              parameterStringValues: const {},
              mappings: const {},
            ),
          ],
        ),
        isTemplate: true,
      );

      final loaded = await database.presetsDao.getFullPresetDetails(presetId);

      expect(loaded!.slots.single.specificationValues, const [4]);
    });

    test('delete rollback does not strip specification values', () async {
      await database.metadataDao.upsertAlgorithms([
        const AlgorithmEntry(
          guid: 'quan',
          name: 'Quantizer',
          numSpecifications: 1,
          pluginFilePath: null,
        ),
      ]);
      final presetId = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Protected Quantizer',
            lastModified: DateTime.now(),
            isTemplate: true,
          ),
          slots: [
            FullPresetSlot(
              slot: const PresetSlotEntry(
                id: -1,
                presetId: -1,
                slotIndex: 0,
                algorithmGuid: 'quan',
              ),
              algorithm: const AlgorithmEntry(
                guid: 'quan',
                name: 'Quantizer',
                numSpecifications: 1,
                pluginFilePath: null,
              ),
              specificationValues: const [4],
              parameterValues: const {},
              parameterStringValues: const {},
              mappings: const {},
            ),
          ],
        ),
        isTemplate: true,
      );
      await database.customStatement(
        'CREATE TRIGGER prevent_protected_preset_delete '
        'BEFORE DELETE ON presets '
        'WHEN OLD.id = $presetId '
        "BEGIN SELECT RAISE(ABORT, 'protected'); END",
      );

      await expectLater(
        database.presetsDao.deletePreset(presetId),
        throwsA(anything),
      );

      final loaded = await database.presetsDao.getFullPresetDetails(presetId);
      expect(loaded!.slots.single.specificationValues, const [4]);
    });
  });

  group('PresetsDao - perfPageIndex persistence', () {
    test('saves and loads mapping with perfPageIndex > 0', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a mapping with perfPageIndex = 5
      final testMapping = PackedMappingData(
        source: 1,
        cvInput: 2,
        isUnipolar: false,
        isGate: false,
        volts: 5,
        delta: 100,
        midiChannel: 1,
        midiMappingType: MidiMappingType.cc,
        midiCC: 64,
        isMidiEnabled: true,
        isMidiSymmetric: false,
        isMidiRelative: false,
        midiMin: 0,
        midiMax: 127,
        i2cCC: 32,
        isI2cEnabled: false,
        isI2cSymmetric: false,
        i2cMin: 0,
        i2cMax: 16383,
        perfPageIndex: 5, // Test non-zero performance page
        version: 5,
      );

      // 3. Create a preset with a slot containing the mapping
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1, // -1 indicates new preset for auto-increment
          name: 'Test Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {
              10: testMapping, // Parameter 10 has the mapping
            },
          ),
        ],
      );

      // 4. Save the preset
      final presetId = await database.presetsDao.saveFullPreset(presetDetails);

      // 5. Load the preset back
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      // 6. Verify perfPageIndex was persisted correctly
      expect(loadedPreset, isNotNull);
      expect(loadedPreset!.slots.length, equals(1));

      final loadedMapping = loadedPreset.slots[0].mappings[10];
      expect(loadedMapping, isNotNull);
      expect(
        loadedMapping!.perfPageIndex,
        equals(5),
        reason: 'perfPageIndex should be persisted to database',
      );
    });

    test(
      'saves and loads preset routing rows with full preset details',
      () async {
        await database.metadataDao.upsertAlgorithms([
          AlgorithmEntry(
            guid: 'ROUT',
            name: 'Routing Algorithm',
            numSpecifications: 0,
            pluginFilePath: null,
          ),
        ]);

        final presetId = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
            preset: PresetEntry(
              id: -1,
              name: 'Routing Preset',
              lastModified: DateTime.now(),
              isTemplate: true,
            ),
            slots: [
              FullPresetSlot(
                slot: PresetSlotEntry(
                  id: -1,
                  presetId: -1,
                  slotIndex: 0,
                  algorithmGuid: 'ROUT',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'ROUT',
                  name: 'Routing Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
                routing: PresetRoutingEntry(
                  presetSlotId: -1,
                  routingInfoJson: const [1, 2, 3, 4, 5, 6],
                ),
              ),
            ],
          ),
          isTemplate: true,
        );

        final loadedPreset = await database.presetsDao.getFullPresetDetails(
          presetId,
        );

        expect(loadedPreset, isNotNull);
        expect(loadedPreset!.slots.single.routing, isNotNull);
        expect(loadedPreset.slots.single.routing!.routingInfoJson, [
          1,
          2,
          3,
          4,
          5,
          6,
        ]);

        final savedRoutingRows = await database
            .select(database.presetRoutings)
            .get();
        expect(savedRoutingRows, hasLength(1));
        expect(
          savedRoutingRows.single.presetSlotId,
          loadedPreset.slots.single.slot.id,
        );
      },
    );

    test('saves mapping with perfPageIndex = 0 (not assigned)', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TST2',
          name: 'Test Algorithm 2',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a mapping with perfPageIndex = 0 (not assigned)
      final testMapping = PackedMappingData(
        source: 1,
        cvInput: 2,
        isUnipolar: false,
        isGate: false,
        volts: 5,
        delta: 100,
        midiChannel: 1,
        midiMappingType: MidiMappingType.cc,
        midiCC: 64,
        isMidiEnabled: true,
        isMidiSymmetric: false,
        isMidiRelative: false,
        midiMin: 0,
        midiMax: 127,
        i2cCC: 32,
        isI2cEnabled: false,
        isI2cSymmetric: false,
        i2cMin: 0,
        i2cMax: 16383,
        perfPageIndex: 0, // Not assigned
        version: 5,
      );

      // 3. Create and save preset
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Test Preset 2',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TST2',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TST2',
              name: 'Test Algorithm 2',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {5: testMapping},
          ),
        ],
      );

      final presetId = await database.presetsDao.saveFullPreset(presetDetails);

      // 4. Load and verify
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );
      final loadedMapping = loadedPreset!.slots[0].mappings[5];

      expect(
        loadedMapping!.perfPageIndex,
        equals(0),
        reason: 'perfPageIndex = 0 should be persisted correctly',
      );
    });
  });

  group('PresetsDao - Template functionality', () {
    test('saves preset with isTemplate=true', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TMPL',
          name: 'Template Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a template preset
      final templateDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'My Template',
          lastModified: DateTime.now(),
          isTemplate: false, // Will be overridden by saveFullPreset parameter
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TMPL',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TMPL',
              name: 'Template Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save with isTemplate=true
      final presetId = await database.presetsDao.saveFullPreset(
        templateDetails,
        isTemplate: true,
      );

      // 4. Load and verify
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      expect(loadedPreset, isNotNull);
      expect(loadedPreset!.preset.isTemplate, isTrue);
    });

    test('getTemplates returns only templates', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create one template preset
      final templateDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Template Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Create one regular preset
      final regularDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Regular Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 4. Save both
      await database.presetsDao.saveFullPreset(
        templateDetails,
        isTemplate: true,
      );
      await database.presetsDao.saveFullPreset(
        regularDetails,
        isTemplate: false,
      );

      // 5. Query templates
      final templates = await database.presetsDao.getTemplates();

      // 6. Verify only template is returned
      expect(templates.length, equals(1));
      expect(templates[0].preset.name, equals('Template Preset'));
      expect(templates[0].preset.isTemplate, isTrue);
    });

    test('getNonTemplates returns only non-templates', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create one template preset
      final templateDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Template Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Create one regular preset
      final regularDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Regular Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 4. Save both
      await database.presetsDao.saveFullPreset(
        templateDetails,
        isTemplate: true,
      );
      await database.presetsDao.saveFullPreset(
        regularDetails,
        isTemplate: false,
      );

      // 5. Query non-templates
      final nonTemplates = await database.presetsDao.getNonTemplates();

      // 6. Verify only regular preset is returned
      expect(nonTemplates.length, equals(1));
      expect(nonTemplates[0].preset.name, equals('Regular Preset'));
      expect(nonTemplates[0].preset.isTemplate, isFalse);
    });

    test('migration sets existing presets to isTemplate=false', () async {
      // This test verifies that the default value works correctly
      // In a real migration scenario, existing presets would have isTemplate=false

      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create preset without explicitly setting isTemplate
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Migrated Preset',
          lastModified: DateTime.now(),
          isTemplate: false, // Default value
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save without specifying isTemplate (defaults to false)
      final presetId = await database.presetsDao.saveFullPreset(presetDetails);

      // 4. Load and verify it defaults to false
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      expect(loadedPreset, isNotNull);
      expect(loadedPreset!.preset.isTemplate, isFalse);
    });

    test('toggleTemplateStatus marks preset as template', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a regular preset
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Regular Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save as regular preset
      final presetId = await database.presetsDao.saveFullPreset(
        presetDetails,
        isTemplate: false,
      );

      // 4. Toggle to template
      await database.presetsDao.toggleTemplateStatus(presetId, true);

      // 5. Load and verify
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      expect(loadedPreset, isNotNull);
      expect(loadedPreset!.preset.isTemplate, isTrue);
    });

    test('toggleTemplateStatus unmarks preset as template', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a template preset
      final templateDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Template Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save as template
      final presetId = await database.presetsDao.saveFullPreset(
        templateDetails,
        isTemplate: true,
      );

      // 4. Toggle to regular preset
      await database.presetsDao.toggleTemplateStatus(presetId, false);

      // 5. Load and verify
      final loadedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      expect(loadedPreset, isNotNull);
      expect(loadedPreset!.preset.isTemplate, isFalse);
    });

    test('toggleTemplateStatus updates lastModified timestamp', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create preset
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Test Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save preset
      final presetId = await database.presetsDao.saveFullPreset(presetDetails);

      // Seed an old timestamp so the assertion cannot pass on an unchanged row.
      await (database.update(database.presets)
            ..where((p) => p.id.equals(presetId)))
          .write(PresetsCompanion(lastModified: Value(DateTime.utc(2000))));

      // 4. Get initial timestamp
      final initialPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );
      final initialTimestamp = initialPreset!.preset.lastModified;

      // 6. Toggle template status
      await database.presetsDao.toggleTemplateStatus(presetId, true);

      // 7. Load and verify timestamp updated
      final updatedPreset = await database.presetsDao.getFullPresetDetails(
        presetId,
      );

      expect(updatedPreset, isNotNull);
      expect(
        updatedPreset!.preset.lastModified.isAfter(initialTimestamp),
        isTrue,
        reason: 'lastModified must advance from the seeded timestamp',
      );
    });

    test('getTemplates returns templates sorted alphabetically', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create templates with names that need sorting
      final template1 = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Zebra Template',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      final template2 = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Apple Template',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      final template3 = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Mango Template',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      // 3. Save in non-alphabetical order
      await database.presetsDao.saveFullPreset(template1, isTemplate: true);
      await database.presetsDao.saveFullPreset(template2, isTemplate: true);
      await database.presetsDao.saveFullPreset(template3, isTemplate: true);

      // 4. Query templates
      final templates = await database.presetsDao.getTemplates();

      // 5. Verify they are sorted alphabetically
      expect(templates.length, equals(3));
      expect(templates[0].preset.name, equals('Apple Template'));
      expect(templates[1].preset.name, equals('Mango Template'));
      expect(templates[2].preset.name, equals('Zebra Template'));
    });

    test('watchTemplateCount returns correct count', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Get initial count (should be 0)
      final stream = database.presetsDao.watchTemplateCount();
      expect(await stream.first, equals(0));

      // 3. Create and save a template
      final template1 = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Template 1',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      await database.presetsDao.saveFullPreset(template1, isTemplate: true);

      // 4. Verify count is now 1
      expect(await stream.first, equals(1));

      // 5. Add another template
      final template2 = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Template 2',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      await database.presetsDao.saveFullPreset(template2, isTemplate: true);

      // 6. Verify count is now 2
      expect(await stream.first, equals(2));

      // 7. Add a non-template preset
      final regular = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Regular Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      await database.presetsDao.saveFullPreset(regular, isTemplate: false);

      // 8. Verify count is still 2 (non-template not counted)
      expect(await stream.first, equals(2));
    });

    test('watchTemplateCount updates when template status changes', () async {
      // 1. Create test algorithm
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(
          guid: 'TEST',
          name: 'Test Algorithm',
          numSpecifications: 0,
          pluginFilePath: null,
        ),
      ]);

      // 2. Create a regular preset
      final presetDetails = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Test Preset',
          lastModified: DateTime.now(),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'TEST',
              customName: null,
            ),
            algorithm: AlgorithmEntry(
              guid: 'TEST',
              name: 'Test Algorithm',
              numSpecifications: 0,
              pluginFilePath: null,
            ),
            parameterValues: {},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      final presetId = await database.presetsDao.saveFullPreset(
        presetDetails,
        isTemplate: false,
      );

      // 3. Get stream
      final stream = database.presetsDao.watchTemplateCount();

      // 4. Initial count should be 0
      expect(await stream.first, equals(0));

      // 5. Toggle to template
      await database.presetsDao.toggleTemplateStatus(presetId, true);

      // 6. Count should update to 1
      expect(await stream.first, equals(1));

      // 7. Toggle back to regular
      await database.presetsDao.toggleTemplateStatus(presetId, false);

      // 8. Count should update back to 0
      expect(await stream.first, equals(0));
    });
  });
}
