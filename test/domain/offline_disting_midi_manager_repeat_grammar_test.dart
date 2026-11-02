import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';

void main() {
  late AppDatabase database;
  late OfflineDistingMidiManager manager;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    manager = OfflineDistingMidiManager(database);
    await _seedQuantizer(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'two Quantizer slots resolve different shapes from the same rows',
    () async {
      await manager.initializeFromDb(
        _preset([
          _slot(0, 'quan', [1]),
          _slot(1, 'quan', [4]),
        ]),
      );

      expect((await manager.requestNumberOfParameters(0))!.numParameters, 3);
      expect((await manager.requestNumberOfParameters(1))!.numParameters, 9);
      expect((await manager.requestParameterInfo(1, 8))!.name, '4:CV output');
      expect((await manager.requestParameterEnumStrings(1, 7))!.values, [
        'Input 4',
      ]);

      final pages = (await manager.requestParameterPages(1))!.pages;
      expect(pages.map((page) => page.name), [
        'Algorithm',
        'Channel 1',
        'Channel 2',
        'Channel 3',
        'Channel 4',
      ]);
      expect(pages.last.parameters, [7, 8]);
      expect(
        (await manager.requestOutputModeUsage(1, 8))!.affectedParameterNumbers,
        [7],
      );
    },
  );

  test(
    'offline add reconstitutes the selected shape after database reload',
    () async {
      await manager.initializeFromDb(null);
      final algorithm = await manager.requestAlgorithmInfo(0);

      expect(algorithm?.guid, 'quan');
      await manager.requestSetPresetName('Four Channel Quantizer');
      await manager.requestAddAlgorithm(algorithm!, const [4]);

      expect((await manager.requestNumberOfParameters(0))!.numParameters, 9);
      expect((await manager.requestParameterInfo(0, 8))!.name, '4:CV output');
      expect((await manager.requestParameterPages(0))!.pages, hasLength(5));

      await manager.requestSavePreset();
      final savedPreset = await database.presetsDao.getPresetByName(
        'Four Channel Quantizer',
      );
      final savedDetails = await database.presetsDao.getFullPresetDetails(
        savedPreset!.id,
      );
      expect(savedDetails!.slots.single.specificationValues, const [4]);

      final reloadedManager = OfflineDistingMidiManager(database);
      await reloadedManager.initializeFromDb(savedDetails);

      expect(
        (await reloadedManager.requestNumberOfParameters(0))!.numParameters,
        9,
      );
      expect(
        (await reloadedManager.requestParameterInfo(0, 8))!.name,
        '4:CV output',
      );
      expect(
        (await reloadedManager.requestParameterPages(0))!.pages,
        hasLength(5),
      );
    },
  , tags: ['regression']);

  test(
    'malformed grammar falls back to the complete canonical shape',
    () async {
      await (database.update(
        database.algorithmRepeatGrammars,
      )..where((row) => row.algorithmGuid.equals('quan'))).write(
        const AlgorithmRepeatGrammarsCompanion(grammarJson: Value('{')),
      );
      await manager.initializeFromDb(
        _preset([
          _slot(0, 'quan', [4]),
        ]),
      );

      expect((await manager.requestNumberOfParameters(0))!.numParameters, 5);
      expect((await manager.requestParameterInfo(0, 4))!.name, '2:CV output');
      expect((await manager.requestParameterPages(0))!.pages, hasLength(3));
    },
  , tags: ['regression']);

  test('out-of-range vector falls back atomically', () async {
    await manager.initializeFromDb(
      _preset([
        _slot(0, 'quan', [99]),
      ]),
    );

    expect((await manager.requestNumberOfParameters(0))!.numParameters, 5);
    expect(await manager.requestParameterInfo(0, 5), isNull);
  });

  test('algorithm without a grammar keeps one flat topology', () async {
    await database
        .into(database.algorithms)
        .insert(
          const AlgorithmEntry(
            guid: 'delm',
            name: 'Delay (Mono)',
            numSpecifications: 1,
            pluginFilePath: null,
          ),
        );
    await database
        .into(database.specifications)
        .insert(
          const SpecificationEntry(
            algorithmGuid: 'delm',
            specIndex: 0,
            name: 'Max delay time',
            minValue: 1,
            maxValue: 30,
            defaultValue: 30,
            type: 0,
          ),
        );
    await database
        .into(database.parameters)
        .insert(
          const ParameterEntry(
            algorithmGuid: 'delm',
            parameterNumber: 0,
            name: 'Delay',
            minValue: 0,
            maxValue: 100,
            defaultValue: 50,
            unitId: null,
            powerOfTen: 0,
            ioFlags: 0,
            rawUnitIndex: 0,
          ),
        );
    await manager.initializeFromDb(
      _preset([
        _slot(0, 'delm', [1], name: 'Delay (Mono)'),
        _slot(1, 'delm', [30], name: 'Delay (Mono)'),
      ]),
    );

    expect((await manager.requestNumberOfParameters(0))!.numParameters, 1);
    expect((await manager.requestNumberOfParameters(1))!.numParameters, 1);
    expect(
      (await manager.requestParameterInfo(0, 0))!.name,
      (await manager.requestParameterInfo(1, 0))!.name,
    );
  });
}

Future<void> _seedQuantizer(AppDatabase database) async {
  await database
      .into(database.algorithms)
      .insert(
        const AlgorithmEntry(
          guid: 'quan',
          name: 'Quantizer',
          numSpecifications: 1,
          pluginFilePath: null,
        ),
      );
  await database
      .into(database.specifications)
      .insert(
        const SpecificationEntry(
          algorithmGuid: 'quan',
          specIndex: 0,
          name: 'Channels',
          minValue: 1,
          maxValue: 12,
          defaultValue: 1,
          type: 0,
        ),
      );
  final grammar = AlgorithmRepeatGrammar(
    baselineSpecifications: [2],
    sections: [
      RepeatSection(
        specificationIndex: 0,
        countBias: 0,
        sourceOrdinal: 0,
        runs: const [
          ShapeStreamRun(
            stream: ShapeStream.parameters,
            firstStart: 1,
            itemCount: 2,
          ),
          ShapeStreamRun(
            stream: ShapeStream.pages,
            firstStart: 1,
            itemCount: 1,
          ),
          ShapeStreamRun(
            stream: ShapeStream.memberships,
            firstStart: 1,
            itemCount: 2,
          ),
          ShapeStreamRun(
            stream: ShapeStream.outputUsage,
            firstStart: 0,
            itemCount: 1,
          ),
        ],
        substitutions: [
          for (final (offset, suffix) in const [
            (0, 'CV input'),
            (1, 'CV output'),
          ])
            OrdinalTextSubstitution(
              stream: ShapeStream.parameters,
              rowOffset: offset,
              field: OrdinalField.parameterName,
              parts: [
                const OrdinalTextPlaceholder(
                  specificationIndex: 0,
                  displayBias: 1,
                ),
                LiteralTextPart(':$suffix'),
              ],
            ),
          OrdinalTextSubstitution(
            stream: ShapeStream.parameters,
            rowOffset: 0,
            field: OrdinalField.parameterEnumString,
            elementIndex: 0,
            parts: const [
              LiteralTextPart('Input '),
              OrdinalTextPlaceholder(specificationIndex: 0, displayBias: 1),
            ],
          ),
          OrdinalTextSubstitution(
            stream: ShapeStream.pages,
            rowOffset: 0,
            field: OrdinalField.pageName,
            parts: const [
              LiteralTextPart('Channel '),
              OrdinalTextPlaceholder(specificationIndex: 0, displayBias: 1),
            ],
          ),
        ],
        children: const [],
      ),
    ],
  );
  await database.metadataDao.replaceAlgorithmShapeAndGrammar(
    guid: 'quan',
    parameters: const [
      ParameterEntry(
        algorithmGuid: 'quan',
        parameterNumber: 0,
        name: 'Mode',
        minValue: 0,
        maxValue: 1,
        defaultValue: 0,
        unitId: null,
        powerOfTen: 0,
        ioFlags: 0,
        rawUnitIndex: 0,
      ),
      ParameterEntry(
        algorithmGuid: 'quan',
        parameterNumber: 1,
        name: '1:CV input',
        minValue: 0,
        maxValue: 64,
        defaultValue: 1,
        unitId: null,
        powerOfTen: 0,
        ioFlags: 1,
        rawUnitIndex: 0,
      ),
      ParameterEntry(
        algorithmGuid: 'quan',
        parameterNumber: 2,
        name: '1:CV output',
        minValue: 0,
        maxValue: 64,
        defaultValue: 1,
        unitId: null,
        powerOfTen: 0,
        ioFlags: 10,
        rawUnitIndex: 0,
      ),
      ParameterEntry(
        algorithmGuid: 'quan',
        parameterNumber: 3,
        name: '2:CV input',
        minValue: 0,
        maxValue: 64,
        defaultValue: 1,
        unitId: null,
        powerOfTen: 0,
        ioFlags: 1,
        rawUnitIndex: 0,
      ),
      ParameterEntry(
        algorithmGuid: 'quan',
        parameterNumber: 4,
        name: '2:CV output',
        minValue: 0,
        maxValue: 64,
        defaultValue: 1,
        unitId: null,
        powerOfTen: 0,
        ioFlags: 10,
        rawUnitIndex: 0,
      ),
    ],
    enums: const [
      ParameterEnumEntry(
        algorithmGuid: 'quan',
        parameterNumber: 1,
        enumIndex: 0,
        enumString: 'Input 1',
      ),
      ParameterEnumEntry(
        algorithmGuid: 'quan',
        parameterNumber: 3,
        enumIndex: 0,
        enumString: 'Input 2',
      ),
    ],
    pages: const [
      ParameterPageEntry(
        algorithmGuid: 'quan',
        pageIndex: 0,
        name: 'Algorithm',
      ),
      ParameterPageEntry(
        algorithmGuid: 'quan',
        pageIndex: 1,
        name: 'Channel 1',
      ),
      ParameterPageEntry(
        algorithmGuid: 'quan',
        pageIndex: 2,
        name: 'Channel 2',
      ),
    ],
    pageItems: const [
      ParameterPageItemEntry(
        algorithmGuid: 'quan',
        pageIndex: 0,
        parameterNumber: 0,
      ),
      ParameterPageItemEntry(
        algorithmGuid: 'quan',
        pageIndex: 1,
        parameterNumber: 1,
      ),
      ParameterPageItemEntry(
        algorithmGuid: 'quan',
        pageIndex: 1,
        parameterNumber: 2,
      ),
      ParameterPageItemEntry(
        algorithmGuid: 'quan',
        pageIndex: 2,
        parameterNumber: 3,
      ),
      ParameterPageItemEntry(
        algorithmGuid: 'quan',
        pageIndex: 2,
        parameterNumber: 4,
      ),
    ],
    outputUsage: const [
      ParameterOutputModeUsageEntry(
        algorithmGuid: 'quan',
        parameterNumber: 2,
        affectedOutputNumbers: [1],
      ),
      ParameterOutputModeUsageEntry(
        algorithmGuid: 'quan',
        parameterNumber: 4,
        affectedOutputNumbers: [3],
      ),
    ],
    grammar: grammar,
  );
}

FullPresetDetails _preset(List<FullPresetSlot> slots) => FullPresetDetails(
  preset: PresetEntry(
    id: -1,
    name: 'Test',
    lastModified: DateTime(2026),
    isTemplate: false,
  ),
  slots: slots,
);

FullPresetSlot _slot(
  int index,
  String guid,
  List<int> specifications, {
  String name = 'Quantizer',
}) => FullPresetSlot(
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
  specificationValues: specifications,
  parameterValues: const {},
  parameterStringValues: const {},
  mappings: const {},
);
