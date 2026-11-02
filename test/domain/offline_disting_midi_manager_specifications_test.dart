import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/services/metadata_import_service.dart';

void main() {
  group('OfflineDistingMidiManager specification values', () {
    late AppDatabase database;
    late OfflineDistingMidiManager manager;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      manager = OfflineDistingMidiManager(database);

      for (final (guid, name) in const [
        ('algo-a', 'Algorithm A'),
        ('algo-b', 'Algorithm B'),
        ('algo-c', 'Algorithm C'),
      ]) {
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: Value(guid),
                name: Value(name),
                numSpecifications: const Value(1),
              ),
            );
        await database
            .into(database.specifications)
            .insert(
              SpecificationEntry(
                algorithmGuid: guid,
                specIndex: 0,
                name: 'Channels',
                minValue: 1,
                maxValue: 8,
                defaultValue: 1,
                type: 0,
              ),
            );
        final grammar = AlgorithmRepeatGrammar(
          baselineSpecifications: [1],
          sections: [
            RepeatSection(
              specificationIndex: 0,
              countBias: 0,
              sourceOrdinal: 0,
              runs: const [
                ShapeStreamRun(
                  stream: ShapeStream.parameters,
                  firstStart: 0,
                  itemCount: 1,
                ),
              ],
              substitutions: [
                OrdinalTextSubstitution(
                  stream: ShapeStream.parameters,
                  rowOffset: 0,
                  field: OrdinalField.parameterName,
                  parts: const [
                    OrdinalTextPlaceholder(
                      specificationIndex: 0,
                      displayBias: 1,
                    ),
                    LiteralTextPart(':Value'),
                  ],
                ),
              ],
              children: const [],
            ),
          ],
        );
        await database.metadataDao.replaceAlgorithmShapeAndGrammar(
          guid: guid,
          parameters: [
            ParameterEntry(
              algorithmGuid: guid,
              parameterNumber: 0,
              name: '1:Value',
              minValue: 0,
              maxValue: 100,
              defaultValue: 0,
            ),
          ],
          enums: const [],
          pages: const [],
          pageItems: const [],
          outputUsage: const [],
          grammar: grammar,
        );
      }
    });

    tearDown(() async {
      await database.close();
    });

    test('loads and returns defensive copies of saved values', () async {
      final sourceValues = <int>[4];
      await manager.initializeFromDb(
        _presetDetails([_slot(0, 'algo-a', 'Algorithm A', sourceValues)]),
      );

      sourceValues[0] = 1;
      final firstRead = await manager.requestAlgorithmGuid(0);
      expect(firstRead?.specifications, [4]);

      firstRead!.specifications[0] = 2;
      expect((await manager.requestAlgorithmGuid(0))?.specifications, [4]);
    });

    test(
      'preserves exact added values through current details and save',
      () async {
        await manager.initializeFromDb(null);
        await manager.requestSetPresetName('Four Channel Quantizer');
        final selectedValues = <int>[4];

        await manager.requestAddAlgorithm(
          _algorithmInfo('algo-a', 'Algorithm A'),
          selectedValues,
        );
        selectedValues[0] = 1;

        expect((await manager.requestAlgorithmGuid(0))?.specifications, [4]);
        expect(
          (await manager.requestCurrentPresetDetails())
              ?.slots
              .single
              .specificationValues,
          [4],
        );

        await manager.requestSavePreset();
        final savedPreset = await database.presetsDao.getPresetByName(
          'Four Channel Quantizer',
        );
        final savedDetails = await database.presetsDao.getFullPresetDetails(
          savedPreset!.id,
        );
        expect(savedDetails!.slots.single.specificationValues, [4]);
      },
    tags: ['regression']);

    test('failed local saves propagate and can be retried', () async {
      await manager.initializeFromDb(null);
      await manager.requestSetPresetName('Retry local save');
      await manager.requestAddAlgorithm(
        _algorithmInfo('algo-a', 'Algorithm A'),
        [2],
      );
      await database.customStatement('''
        CREATE TRIGGER reject_preset_save BEFORE INSERT ON presets
        BEGIN SELECT RAISE(ABORT, 'local save rejected'); END;
      ''');

      await expectLater(
        manager.requestSavePreset(),
        throwsA(
          predicate(
            (error) => error.toString().contains('local save rejected'),
          ),
        ),
      );
      expect(manager.loadedPresetId, isNull);
      expect(
        await database.presetsDao.getPresetByName('Retry local save'),
        isNull,
      );

      await database.customStatement('DROP TRIGGER reject_preset_save');
      await manager.requestSavePreset();
      final saved = await database.presetsDao.getPresetByName(
        'Retry local save',
      );
      expect(manager.loadedPresetId, saved!.id);
      final restored = await database.presetsDao.getFullPresetDetails(saved.id);
      expect(restored!.slots.single.specificationValues, [2]);
    }, tags: ['regression']);

    test('unbuildable local presets report a save failure', () async {
      await manager.initializeFromDb(null);
      await manager.requestAddAlgorithm(
        _algorithmInfo('algo-a', 'Algorithm A'),
        [2],
      );
      await (database.delete(
        database.algorithms,
      )..where((row) => row.guid.equals('algo-a'))).go();

      await expectLater(manager.requestSavePreset(), throwsStateError);
      expect(manager.loadedPresetId, isNull);
      expect(await database.presetsDao.getAllPresets(), isEmpty);
    });

    test('keeps values aligned through moves and removal', () async {
      await manager.initializeFromDb(
        _presetDetails([
          _slot(0, 'algo-a', 'Algorithm A', [1]),
          _slot(1, 'algo-b', 'Algorithm B', [2]),
          _slot(2, 'algo-c', 'Algorithm C', [3]),
        ]),
      );

      await manager.requestMoveAlgorithmDown(0);
      expect(await _slotIdentities(manager), [
        {
          'guid': 'algo-b',
          'specifications': [2],
        },
        {
          'guid': 'algo-a',
          'specifications': [1],
        },
        {
          'guid': 'algo-c',
          'specifications': [3],
        },
      ]);

      await manager.requestMoveAlgorithmUp(2);
      expect(await _slotIdentities(manager), [
        {
          'guid': 'algo-b',
          'specifications': [2],
        },
        {
          'guid': 'algo-c',
          'specifications': [3],
        },
        {
          'guid': 'algo-a',
          'specifications': [1],
        },
      ]);

      await manager.requestRemoveAlgorithm(1);
      expect(await _slotIdentities(manager), [
        {
          'guid': 'algo-b',
          'specifications': [2],
        },
        {
          'guid': 'algo-a',
          'specifications': [1],
        },
      ]);
    });

    test('new preset clears all saved specification values', () async {
      await manager.initializeFromDb(
        _presetDetails([
          _slot(0, 'algo-a', 'Algorithm A', [4]),
        ]),
      );

      await manager.requestNewPreset();

      expect(await manager.requestAlgorithmGuid(0), isNull);
      expect((await manager.requestCurrentPresetDetails())?.slots, isEmpty);
    });

    for (final corruptGrammar in [false, true]) {
      test('${corruptGrammar ? 'corrupt' : 'missing'} grammar rejects a new '
          'unsupported shape without changing the preset', () async {
        await manager.initializeFromDb(
          _presetDetails([
            _slot(0, 'algo-b', 'Algorithm B', [2]),
          ]),
        );
        if (corruptGrammar) {
          await (database.update(
            database.algorithmRepeatGrammars,
          )..where((row) => row.algorithmGuid.equals('algo-a'))).write(
            const AlgorithmRepeatGrammarsCompanion(grammarJson: Value('{')),
          );
        } else {
          await (database.delete(
            database.algorithmRepeatGrammars,
          )..where((row) => row.algorithmGuid.equals('algo-a'))).go();
        }
        await expectLater(
          manager.requestAddAlgorithm(_algorithmInfo('algo-a', 'Algorithm A'), [
            4,
          ]),
          throwsStateError,
        );
        expect(await _slotIdentities(manager), [
          {
            'guid': 'algo-b',
            'specifications': [2],
          },
        ]);
      });
    }

    test(
      'bundled Attenuverter expands every advertised channel count',
      () async {
        final bundled =
            jsonDecode(
                  await File(
                    'assets/metadata/full_metadata.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final tables = bundled['tables'] as Map<String, dynamic>;
        for (final entry in tables.entries) {
          if (entry.key == 'units') continue;
          tables[entry.key] = (entry.value as List).where((row) {
            final data = row as Map<String, dynamic>;
            return data['algorithmGuid'] == 'attn' || data['guid'] == 'attn';
          }).toList();
        }
        expect(
          await MetadataImportService(
            database,
          ).importFromJson(jsonEncode(bundled)),
          isTrue,
        );
        final catalog = await database.metadataDao.getFullAlgorithmDetails(
          'attn',
        );
        final algorithm = AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'attn',
          name: 'Attenuverter',
          specifications: [
            for (final spec in catalog!.specifications)
              Specification(
                name: spec.name,
                min: spec.minValue,
                max: spec.maxValue,
                defaultValue: spec.defaultValue,
                type: spec.type,
              ),
          ],
        );
        for (var channels = 1; channels <= 12; channels++) {
          await manager.requestAddAlgorithm(algorithm, [channels]);
          final slot = channels - 1;
          expect((await manager.requestAlgorithmGuid(slot))?.specifications, [
            channels,
          ]);
          expect(
            (await manager.requestNumberOfParameters(slot))?.numParameters,
            1 + 10 * channels,
          );
          expect(
            (await manager.requestParameterInfo(slot, 10 * channels))?.name,
            '$channels:Gain',
          );
          final pages = (await manager.requestParameterPages(slot))!.pages;
          expect(pages.map((page) => page.name), [
            for (var channel = 1; channel <= channels; channel++)
              'Channel $channel',
            'Algorithm',
          ]);
          for (var channel = 0; channel < channels; channel++) {
            expect(pages[channel].parameters, [
              for (var parameter = 1; parameter <= 10; parameter++)
                10 * channel + parameter,
            ]);
          }
          expect(pages.last.parameters, [0]);
        }
      },
    );
  });
}

AlgorithmInfo _algorithmInfo(String guid, String name) => AlgorithmInfo(
  algorithmIndex: 0,
  name: name,
  guid: guid,
  specifications: [
    Specification(name: 'Channels', min: 1, max: 8, defaultValue: 1, type: 0),
  ],
);

FullPresetDetails _presetDetails(List<FullPresetSlot> slots) =>
    FullPresetDetails(
      preset: PresetEntry(
        id: -1,
        name: 'Test Preset',
        lastModified: DateTime(2026),
        isTemplate: false,
      ),
      slots: slots,
    );

FullPresetSlot _slot(
  int index,
  String guid,
  String name,
  List<int> specificationValues,
) => FullPresetSlot(
  slot: PresetSlotEntry(
    id: index + 1,
    presetId: -1,
    slotIndex: index,
    algorithmGuid: guid,
    customName: null,
  ),
  algorithm: AlgorithmEntry(
    guid: guid,
    name: name,
    numSpecifications: 1,
    pluginFilePath: null,
  ),
  specificationValues: specificationValues,
  parameterValues: const {},
  parameterStringValues: const {},
  mappings: const {},
);

Future<List<Map<String, Object>>> _slotIdentities(
  OfflineDistingMidiManager manager,
) async {
  final result = <Map<String, Object>>[];
  for (var index = 0; ; index++) {
    final algorithm = await manager.requestAlgorithmGuid(index);
    if (algorithm == null) break;
    result.add({
      'guid': algorithm.guid,
      'specifications': algorithm.specifications,
    });
  }
  return result;
}
