import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

PackedMappingData _mapping({
  int source = 1,
  int delta = 10,
  int perfPageIndex = 0,
  int midiCC = 64,
}) {
  return PackedMappingData(
    source: source,
    cvInput: 2,
    isUnipolar: false,
    isGate: false,
    volts: 5,
    delta: delta,
    midiChannel: 1,
    midiMappingType: MidiMappingType.cc,
    midiCC: midiCC,
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
    perfPageIndex: perfPageIndex,
    version: 5,
  );
}

FullPresetSlot _slot({
  required int slotIndex,
  required String guid,
  String? customName,
  List<int>? specificationValues,
  Map<int, int>? values,
  Map<int, String>? strings,
  Map<int, PackedMappingData>? mappings,
}) {
  return FullPresetSlot(
    slot: PresetSlotEntry(
      id: -1,
      presetId: -1,
      slotIndex: slotIndex,
      algorithmGuid: guid,
      customName: customName,
    ),
    algorithm: AlgorithmEntry(
      guid: guid,
      name: 'Alg $guid',
      numSpecifications: specificationValues?.length ?? 0,
      pluginFilePath: null,
    ),
    specificationValues: specificationValues ?? const [],
    parameterValues: values ?? {},
    parameterStringValues: strings ?? {},
    mappings: mappings ?? {},
  );
}

Future<int> _savePreset(
  AppDatabase db,
  String name, {
  bool isTemplate = false,
  List<FullPresetSlot> slots = const [],
}) async {
  return db.presetsDao.saveFullPreset(
    FullPresetDetails(
      preset: PresetEntry(
        id: -1,
        name: name,
        lastModified: DateTime.now(),
        isTemplate: false,
      ),
      slots: slots,
    ),
    isTemplate: isTemplate,
  );
}

Future<void> _seedAlgorithm(AppDatabase db, String guid) async {
  await db.metadataDao.upsertAlgorithms([
    AlgorithmEntry(
      guid: guid,
      name: 'Alg $guid',
      numSpecifications: 0,
      pluginFilePath: null,
    ),
  ]);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('PresetsDao.applyTemplateSlots — argument validation', () {
    test('empty templateSlotIndices throws ArgumentError', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      final targetId = await _savePreset(db, 'Target');

      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [],
          insertionOffset: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('index out of range throws ArgumentError', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      final targetId = await _savePreset(db, 'Target');

      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [3],
          insertionOffset: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('negative insertionOffset throws ArgumentError', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      final targetId = await _savePreset(db, 'Target');

      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [0],
          insertionOffset: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('unknown templateId throws StateError', () async {
      final targetId = await _savePreset(db, 'Target');
      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: 9999,
          targetPresetId: targetId,
          templateSlotIndices: const [0],
          insertionOffset: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('unknown targetPresetId throws StateError', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: 9999,
          templateSlotIndices: const [0],
          insertionOffset: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PresetsDao.applyTemplateSlots — insert mode', () {
    test('applies 3 of 5 slots into empty target', () async {
      for (final g in const ['AAAA', 'BBBB', 'CCCC', 'DDDD', 'EEEE']) {
        await _seedAlgorithm(db, g);
      }
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(
            slotIndex: 0,
            guid: 'AAAA',
            values: {1: 11},
            strings: {2: 'a-string'},
            mappings: {3: _mapping(source: 11)},
          ),
          _slot(slotIndex: 1, guid: 'BBBB', values: {1: 22}),
          _slot(slotIndex: 2, guid: 'CCCC', values: {1: 33}),
          _slot(slotIndex: 3, guid: 'DDDD'),
          _slot(slotIndex: 4, guid: 'EEEE'),
        ],
      );
      final targetId = await _savePreset(db, 'Target');

      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0, 2, 4],
        insertionOffset: 0,
      );

      expect(result.targetPresetId, targetId);
      expect(result.skippedTemplateSlotIndices, isEmpty);
      expect(result.insertedSlotIndices, [0, 1, 2]);

      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded, isNotNull);
      expect(loaded!.slots, hasLength(3));
      expect(loaded.slots[0].algorithm.guid, 'AAAA');
      expect(loaded.slots[0].parameterValues[1], 11);
      expect(loaded.slots[0].parameterStringValues[2], 'a-string');
      expect(loaded.slots[0].mappings[3]?.source, 11);
      expect(loaded.slots[1].algorithm.guid, 'CCCC');
      expect(loaded.slots[1].parameterValues[1], 33);
      expect(loaded.slots[2].algorithm.guid, 'EEEE');
    });

    test('inserts into middle and shifts existing slots upward', () async {
      for (final g in const ['AAAA', 'BBBB', 'CCCC', 'DDDD']) {
        await _seedAlgorithm(db, g);
      }
      await _seedAlgorithm(db, 'TARG');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(slotIndex: 0, guid: 'AAAA'),
          _slot(slotIndex: 1, guid: 'BBBB'),
        ],
      );
      final targetId = await _savePreset(
        db,
        'Target',
        slots: [
          _slot(slotIndex: 0, guid: 'TARG', values: {1: 100}),
          _slot(slotIndex: 1, guid: 'TARG', values: {1: 200}),
          _slot(slotIndex: 2, guid: 'TARG', values: {1: 300}),
          _slot(slotIndex: 3, guid: 'TARG', values: {1: 400}),
        ],
      );

      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0, 1],
        insertionOffset: 2,
      );

      expect(result.insertedSlotIndices, [2, 3]);
      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded!.slots, hasLength(6));
      expect(loaded.slots[0].algorithm.guid, 'TARG');
      expect(loaded.slots[0].parameterValues[1], 100);
      expect(loaded.slots[1].algorithm.guid, 'TARG');
      expect(loaded.slots[1].parameterValues[1], 200);
      expect(loaded.slots[2].algorithm.guid, 'AAAA');
      expect(loaded.slots[3].algorithm.guid, 'BBBB');
      expect(loaded.slots[4].algorithm.guid, 'TARG');
      expect(loaded.slots[4].parameterValues[1], 300);
      expect(loaded.slots[5].algorithm.guid, 'TARG');
      expect(loaded.slots[5].parameterValues[1], 400);
    });

    test('insertionOffset past end clamps to append', () async {
      await _seedAlgorithm(db, 'AAAA');
      await _seedAlgorithm(db, 'TARG');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      final targetId = await _savePreset(
        db,
        'Target',
        slots: [
          _slot(slotIndex: 0, guid: 'TARG'),
          _slot(slotIndex: 1, guid: 'TARG'),
          _slot(slotIndex: 2, guid: 'TARG'),
          _slot(slotIndex: 3, guid: 'TARG'),
        ],
      );

      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0],
        insertionOffset: 999,
      );

      expect(result.insertedSlotIndices, [4]);
      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded!.slots, hasLength(5));
      expect(loaded.slots[4].algorithm.guid, 'AAAA');
    });

    test('duplicate indices produce multiple copies in order', () async {
      await _seedAlgorithm(db, 'AAAA');
      await _seedAlgorithm(db, 'BBBB');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(slotIndex: 0, guid: 'AAAA'),
          _slot(slotIndex: 1, guid: 'BBBB', customName: 'two', values: {7: 77}),
          _slot(slotIndex: 2, guid: 'AAAA'),
        ],
      );
      final targetId = await _savePreset(db, 'Target');

      await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [1, 1, 1],
        insertionOffset: 0,
      );

      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded!.slots, hasLength(3));
      for (final s in loaded.slots) {
        expect(s.algorithm.guid, 'BBBB');
        expect(s.slot.customName, 'two');
        expect(s.parameterValues[7], 77);
      }
    });

    test('bumps target preset lastModified timestamp', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [_slot(slotIndex: 0, guid: 'AAAA')],
      );
      final targetId = await _savePreset(db, 'Target');
      await (db.update(db.presets)..where((p) => p.id.equals(targetId))).write(
        PresetsCompanion(lastModified: Value(DateTime.utc(2000))),
      );
      final before = (await db.presetsDao.getPresetById(
        targetId,
      ))!.lastModified;

      await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0],
        insertionOffset: 0,
      );

      final after = (await db.presetsDao.getPresetById(targetId))!.lastModified;
      expect(after.isAfter(before), isTrue);
    });
  });

  group('PresetsDao.applyTemplateSlots — replace mode', () {
    test(
      'replaces slots at offset and removes mapping/routing of replaced',
      () async {
        await _seedAlgorithm(db, 'AAAA');
        await _seedAlgorithm(db, 'TARG');

        final templateId = await _savePreset(
          db,
          'Tmpl',
          isTemplate: true,
          slots: [
            _slot(slotIndex: 0, guid: 'AAAA', values: {1: 1}),
            _slot(slotIndex: 1, guid: 'AAAA', values: {1: 2}),
          ],
        );
        final targetId = await _savePreset(
          db,
          'Target',
          slots: [
            _slot(slotIndex: 0, guid: 'TARG', values: {9: 100}),
            _slot(slotIndex: 1, guid: 'TARG', values: {9: 200}),
            _slot(
              slotIndex: 2,
              guid: 'TARG',
              specificationValues: const [9],
              mappings: {3: _mapping(source: 99, delta: 7)},
            ),
            _slot(slotIndex: 3, guid: 'TARG'),
          ],
        );

        // Snapshot the slot ids that will be replaced so we can verify their
        // child rows are gone.
        final targetSlots =
            await (db.select(db.presetSlots)
                  ..where((s) => s.presetId.equals(targetId))
                  ..orderBy([(s) => OrderingTerm.asc(s.slotIndex)]))
                .get();
        final slotIdsBeforeReplace = {
          for (final s in targetSlots) s.slotIndex: s.id,
        };

        // Add a routing row for the slot at index 2 so we can confirm it
        // is deleted on replace (PresetRoutings does not cascade).
        await db
            .into(db.presetRoutings)
            .insert(
              PresetRoutingsCompanion.insert(
                presetSlotId: Value(slotIdsBeforeReplace[2]!),
                routingInfoJson: const [1, 2, 3],
              ),
            );

        final result = await db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [0, 1],
          insertionOffset: 2,
          overwrite: true,
        );

        expect(result.insertedSlotIndices, [2, 3]);
        final loaded = await db.presetsDao.getFullPresetDetails(targetId);
        expect(loaded!.slots, hasLength(4));
        expect(loaded.slots[0].algorithm.guid, 'TARG');
        expect(loaded.slots[1].algorithm.guid, 'TARG');
        expect(loaded.slots[2].algorithm.guid, 'AAAA');
        expect(loaded.slots[2].parameterValues[1], 1);
        expect(loaded.slots[3].algorithm.guid, 'AAAA');
        expect(loaded.slots[3].parameterValues[1], 2);

        // Verify the orphaned PresetMappings and PresetRoutings of the replaced
        // slots are gone — those slot ids no longer exist.
        final mappingsLeft = await (db.select(
          db.presetMappings,
        )..where((m) => m.presetSlotId.equals(slotIdsBeforeReplace[2]!))).get();
        expect(mappingsLeft, isEmpty);
        final routingsLeft = await (db.select(
          db.presetRoutings,
        )..where((r) => r.presetSlotId.equals(slotIdsBeforeReplace[2]!))).get();
        expect(routingsLeft, isEmpty);
        final specificationValuesLeft = await (db.select(
          db.presetSpecificationValues,
        )..where((v) => v.presetSlotId.equals(slotIdsBeforeReplace[2]!))).get();
        expect(specificationValuesLeft, isEmpty);
      },
    );

    test('replace into empty positions still inserts', () async {
      await _seedAlgorithm(db, 'AAAA');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(slotIndex: 0, guid: 'AAAA'),
          _slot(slotIndex: 1, guid: 'AAAA'),
        ],
      );
      final targetId = await _savePreset(db, 'Target');

      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0, 1],
        insertionOffset: 0,
        overwrite: true,
      );

      expect(result.insertedSlotIndices, [0, 1]);
      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded!.slots, hasLength(2));
    });
  });

  group('PresetsDao.applyTemplateSlots — space exception', () {
    test(
      'insert mode beyond 40 slots throws TemplateSpaceException with diagnostics',
      () async {
        await _seedAlgorithm(db, 'AAAA');
        await _seedAlgorithm(db, 'TARG');
        // Template with 36 slots
        final templateSlots = List<FullPresetSlot>.generate(
          36,
          (i) => _slot(slotIndex: i, guid: 'AAAA'),
        );
        final templateId = await _savePreset(
          db,
          'Tmpl',
          isTemplate: true,
          slots: templateSlots,
        );

        // Target with 5 existing slots
        final targetSlots = List<FullPresetSlot>.generate(
          5,
          (i) => _slot(slotIndex: i, guid: 'TARG'),
        );
        final targetId = await _savePreset(db, 'Target', slots: targetSlots);

        try {
          await db.presetsDao.applyTemplateSlots(
            templateId: templateId,
            targetPresetId: targetId,
            templateSlotIndices: List<int>.generate(36, (i) => i),
            insertionOffset: 5,
          );
          fail('expected TemplateSpaceException');
        } on TemplateSpaceException catch (e) {
          expect(e.current, 5);
          expect(e.applied, 36);
          expect(e.limit, 40);
        }

        final loaded = await db.presetsDao.getFullPresetDetails(targetId);
        expect(
          loaded!.slots,
          hasLength(5),
          reason: 'no slots should be added on failure',
        );
        // No new param/mapping/routing rows beyond original
        final allParamValues = await db.select(db.presetParameterValues).get();
        expect(allParamValues, isEmpty);
      },
    );

    test(
      'replace mode beyond 40 slots throws TemplateSpaceException',
      () async {
        await _seedAlgorithm(db, 'AAAA');
        await _seedAlgorithm(db, 'TARG');
        final templateId = await _savePreset(
          db,
          'Tmpl',
          isTemplate: true,
          slots: List<FullPresetSlot>.generate(
            10,
            (i) => _slot(slotIndex: i, guid: 'AAAA'),
          ),
        );
        final targetId = await _savePreset(
          db,
          'Target',
          slots: List<FullPresetSlot>.generate(
            5,
            (i) => _slot(slotIndex: i, guid: 'TARG'),
          ),
        );

        expect(
          () => db.presetsDao.applyTemplateSlots(
            templateId: templateId,
            targetPresetId: targetId,
            templateSlotIndices: List<int>.generate(10, (i) => i),
            insertionOffset: 35,
            overwrite: true,
          ),
          throwsA(isA<TemplateSpaceException>()),
        );
      },
    );
  });

  group('PresetsDao.applyTemplateSlots — missing algorithm metadata', () {
    test(
      'skips slots without local algorithm rows and populates warning',
      () async {
        await _seedAlgorithm(db, 'AAAA');
        await _seedAlgorithm(db, 'GHST');
        final templateId = await _savePreset(
          db,
          'Tmpl',
          isTemplate: true,
          slots: [
            _slot(slotIndex: 0, guid: 'AAAA'),
            _slot(slotIndex: 1, guid: 'GHST'),
            _slot(slotIndex: 2, guid: 'AAAA'),
          ],
        );
        // Now remove GHST from algorithms to simulate missing metadata locally.
        await (db.delete(
          db.algorithms,
        )..where((a) => a.guid.equals('GHST'))).go();

        final targetId = await _savePreset(db, 'Target');

        final result = await db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [0, 1, 2],
          insertionOffset: 0,
        );

        expect(result.skippedTemplateSlotIndices, [1]);
        expect(result.insertedSlotIndices, [0, 1]);
        expect(result.warning, isNotNull);
        expect(result.warning, contains('GHST'));

        final loaded = await db.presetsDao.getFullPresetDetails(targetId);
        expect(loaded!.slots, hasLength(2));
        expect(loaded.slots.every((s) => s.algorithm.guid == 'AAAA'), isTrue);
      },
    );

    test('space check uses non-skipped count', () async {
      await _seedAlgorithm(db, 'AAAA');
      await _seedAlgorithm(db, 'GHST');
      // Template has 30 slots — 20 of them are GHST (will skip).
      final templateSlots = <FullPresetSlot>[];
      for (var i = 0; i < 30; i++) {
        templateSlots.add(_slot(slotIndex: i, guid: i < 20 ? 'GHST' : 'AAAA'));
      }
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: templateSlots,
      );
      await (db.delete(
        db.algorithms,
      )..where((a) => a.guid.equals('GHST'))).go();

      // Target with 31 existing slots - 31 + 10 (non-skipped) = 41 > 40.
      final targetId = await _savePreset(
        db,
        'Target',
        slots: List<FullPresetSlot>.generate(
          31,
          (i) => _slot(slotIndex: i, guid: 'AAAA'),
        ),
      );

      expect(
        () => db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: List<int>.generate(30, (i) => i),
          insertionOffset: 25,
        ),
        throwsA(
          isA<TemplateSpaceException>().having((e) => e.applied, 'applied', 10),
        ),
      );

      // Now with 22 existing — 22 + 10 = 32, below the 40-slot limit.
      final targetId2 = await _savePreset(
        db,
        'Target 2',
        slots: List<FullPresetSlot>.generate(
          22,
          (i) => _slot(slotIndex: i, guid: 'AAAA'),
        ),
      );
      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId2,
        templateSlotIndices: List<int>.generate(30, (i) => i),
        insertionOffset: 22,
      );
      expect(result.skippedTemplateSlotIndices, hasLength(20));
      expect(result.insertedSlotIndices, hasLength(10));
    });
  });

  group('PresetsDao.applyTemplateSlots — self-application', () {
    test('applying template onto itself doubles the slot count', () async {
      await _seedAlgorithm(db, 'AAAA');
      await _seedAlgorithm(db, 'BBBB');
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(slotIndex: 0, guid: 'AAAA', values: {1: 10}),
          _slot(
            slotIndex: 1,
            guid: 'BBBB',
            customName: 'orig-bb',
            values: {1: 20},
            mappings: {3: _mapping(source: 7)},
          ),
        ],
      );

      final result = await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: templateId,
        templateSlotIndices: const [0, 1],
        insertionOffset: 2,
      );

      expect(result.insertedSlotIndices, [2, 3]);
      final loaded = await db.presetsDao.getFullPresetDetails(templateId);
      expect(loaded!.slots, hasLength(4));
      expect(loaded.slots[0].algorithm.guid, 'AAAA');
      expect(loaded.slots[1].algorithm.guid, 'BBBB');
      expect(loaded.slots[1].slot.customName, 'orig-bb');
      expect(loaded.slots[2].algorithm.guid, 'AAAA');
      expect(loaded.slots[2].parameterValues[1], 10);
      expect(loaded.slots[3].algorithm.guid, 'BBBB');
      expect(loaded.slots[3].slot.customName, 'orig-bb');
      expect(loaded.slots[3].mappings[3]?.source, 7);
    });
  });

  group('PresetsDao.applyTemplateSlots — slot fidelity', () {
    test(
      'copies specifications, parameter values, strings, mappings, and routing',
      () async {
        await _seedAlgorithm(db, 'AAAA');

        final templateId = await _savePreset(
          db,
          'Tmpl',
          isTemplate: true,
          slots: [
            _slot(
              slotIndex: 0,
              guid: 'AAAA',
              customName: 'verbatim-name',
              specificationValues: const [4],
              values: {0: 1, 1: 2, 2: 3},
              strings: {0: 'hello', 5: 'world'},
              mappings: {
                0: _mapping(source: 9, perfPageIndex: 3),
                1: _mapping(source: 12, midiCC: 7, perfPageIndex: 0),
              },
            ),
          ],
        );

        // Attach a PresetRouting row to the template slot manually.
        final tmplSlotId = (await (db.select(
          db.presetSlots,
        )..where((s) => s.presetId.equals(templateId))).getSingle()).id;
        await db
            .into(db.presetRoutings)
            .insert(
              PresetRoutingsCompanion.insert(
                presetSlotId: Value(tmplSlotId),
                routingInfoJson: const [4, 5, 6, 7, 8, 9],
              ),
            );

        final targetId = await _savePreset(db, 'Target');

        await db.presetsDao.applyTemplateSlots(
          templateId: templateId,
          targetPresetId: targetId,
          templateSlotIndices: const [0],
          insertionOffset: 0,
        );

        final loaded = await db.presetsDao.getFullPresetDetails(targetId);
        expect(loaded, isNotNull);
        final slot = loaded!.slots.single;
        expect(slot.slot.customName, 'verbatim-name');
        expect(slot.specificationValues, const [4]);
        expect(slot.parameterValues, {0: 1, 1: 2, 2: 3});
        expect(slot.parameterStringValues, {0: 'hello', 5: 'world'});
        expect(slot.mappings[0]?.source, 9);
        expect(slot.mappings[0]?.perfPageIndex, 3);
        expect(slot.mappings[1]?.source, 12);
        expect(slot.mappings[1]?.midiCC, 7);

        // Routing should also have been copied.
        final newSlot = await (db.select(
          db.presetSlots,
        )..where((s) => s.presetId.equals(targetId))).getSingle();
        final routings = await (db.select(
          db.presetRoutings,
        )..where((r) => r.presetSlotId.equals(newSlot.id))).get();
        expect(routings, hasLength(1));
        expect(routings.first.routingInfoJson, [4, 5, 6, 7, 8, 9]);
      },
    );

    test('templateSlotIndices respects template slotIndex ordering', () async {
      for (final g in const ['AAAA', 'BBBB', 'CCCC']) {
        await _seedAlgorithm(db, g);
      }
      // Save template with slots in non-ascending insertion order; their
      // logical slotIndex still drives the meaning of "index 0".
      final templateId = await _savePreset(
        db,
        'Tmpl',
        isTemplate: true,
        slots: [
          _slot(slotIndex: 2, guid: 'CCCC'),
          _slot(slotIndex: 0, guid: 'AAAA'),
          _slot(slotIndex: 1, guid: 'BBBB'),
        ],
      );
      final targetId = await _savePreset(db, 'Target');

      await db.presetsDao.applyTemplateSlots(
        templateId: templateId,
        targetPresetId: targetId,
        templateSlotIndices: const [0, 2],
        insertionOffset: 0,
      );

      final loaded = await db.presetsDao.getFullPresetDetails(targetId);
      expect(loaded!.slots, hasLength(2));
      expect(loaded.slots[0].algorithm.guid, 'AAAA');
      expect(loaded.slots[1].algorithm.guid, 'CCCC');
    });
  });
}
