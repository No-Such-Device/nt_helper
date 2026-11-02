import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/algorithm_repeat_grammar.dart';
import 'package:nt_helper/services/metadata_import_service.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'atomic shape replacement preserves specifications and grammar',
    () async {
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
        sections: const [],
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
        ],
        enums: const [],
        pages: const [],
        pageItems: const [],
        outputUsage: const [],
        grammar: grammar,
      );

      final saved = await database.metadataDao.getAlgorithmRepeatGrammar(
        'quan',
      );
      expect(
        AlgorithmRepeatGrammar.fromCompactJson(jsonDecode(saved!.grammarJson)),
        grammar,
      );
      expect(
        await database.select(database.specifications).get(),
        hasLength(1),
      );

      await database.metadataDao.replaceAlgorithmShapeAndGrammar(
        guid: 'quan',
        parameters: const [],
        enums: const [],
        pages: const [],
        pageItems: const [],
        outputUsage: const [],
        grammar: null,
      );
      expect(
        await database.metadataDao.getAlgorithmRepeatGrammar('quan'),
        isNull,
      );
      expect(
        await database.select(database.specifications).get(),
        hasLength(1),
      );
    },
  );

  test('v1 and v2 imports remain grammar-free', () async {
    for (final version in [1, 2]) {
      final importDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(importDatabase.close);
      final imported = await MetadataImportService(
        importDatabase,
      ).importFromJson(jsonEncode(_bundle(version: version, grammar: null)));
      expect(imported, isTrue);
      expect(
        await importDatabase
            .select(importDatabase.algorithmRepeatGrammars)
            .get(),
        isEmpty,
      );
    }
  });

  test('v3 imports matching flat rows and compact grammar', () async {
    final grammar = AlgorithmRepeatGrammar(
      baselineSpecifications: [2],
      sections: const [],
    );

    final imported = await MetadataImportService(database).importFromJson(
      jsonEncode(_bundle(version: 3, grammar: grammar.toCompactJson())),
    );

    expect(imported, isTrue);
    expect(await database.select(database.parameters).get(), hasLength(1));
    final saved = await database.metadataDao.getAlgorithmRepeatGrammar('quan');
    expect(
      AlgorithmRepeatGrammar.fromCompactJson(jsonDecode(saved!.grammarJson)),
      grammar,
    );
  });

  test('malformed v3 grammar rolls back every table write', () async {
    final imported = await MetadataImportService(
      database,
    ).importFromJson(jsonEncode(_bundle(version: 3, grammar: [99, [], []])));

    expect(imported, isFalse);
    expect(await database.select(database.algorithms).get(), isEmpty);
    expect(await database.select(database.parameters).get(), isEmpty);
    expect(
      await database.select(database.algorithmRepeatGrammars).get(),
      isEmpty,
    );
  }, tags: ['regression']);

  test('clear paths remove output usage and grammar rows', () async {
    await database
        .into(database.algorithms)
        .insert(
          const AlgorithmEntry(
            guid: 'quan',
            name: 'Quantizer',
            numSpecifications: 0,
            pluginFilePath: null,
          ),
        );
    await database
        .into(database.parameters)
        .insert(
          const ParameterEntry(
            algorithmGuid: 'quan',
            parameterNumber: 0,
            name: 'Output mode',
            minValue: 0,
            maxValue: 1,
            defaultValue: 0,
            unitId: null,
            powerOfTen: 0,
            ioFlags: 8,
            rawUnitIndex: 0,
          ),
        );
    await database
        .into(database.parameterOutputModeUsage)
        .insert(
          const ParameterOutputModeUsageEntry(
            algorithmGuid: 'quan',
            parameterNumber: 0,
            affectedOutputNumbers: [0],
          ),
        );
    await database
        .into(database.algorithmRepeatGrammars)
        .insert(
          AlgorithmRepeatGrammarEntry(
            algorithmGuid: 'quan',
            grammarVersion: 1,
            grammarJson: jsonEncode([1, [], []]),
          ),
        );

    await database.metadataDao.clearAlgorithmMetadata('quan');

    expect(
      await database.select(database.parameterOutputModeUsage).get(),
      isEmpty,
    );
    expect(
      await database.select(database.algorithmRepeatGrammars).get(),
      isEmpty,
    );
  });
}

Map<String, Object?> _bundle({
  required int version,
  required Object? grammar,
}) => {
  'exportType': 'full_metadata',
  'exportVersion': version,
  'tables': {
    'units': <Object?>[],
    'algorithms': [
      {
        'guid': 'quan',
        'name': 'Quantizer',
        'numSpecifications': 1,
        'pluginFilePath': null,
      },
    ],
    'specifications': [
      {
        'algorithmGuid': 'quan',
        'specIndex': 0,
        'name': 'Channels',
        'minValue': 1,
        'maxValue': 12,
        'defaultValue': 1,
        'type': 0,
      },
    ],
    'parameters': [
      {
        'algorithmGuid': 'quan',
        'parameterNumber': 0,
        'name': 'Mode',
        'minValue': 0,
        'maxValue': 1,
        'defaultValue': 0,
        'unitId': null,
        'powerOfTen': 0,
        'rawUnitIndex': 0,
        'ioFlags': 0,
      },
    ],
    'parameterEnums': <Object?>[],
    'parameterPages': <Object?>[],
    'parameterPageItems': <Object?>[],
    'parameterOutputModeUsage': <Object?>[],
    'metadataCache': <Object?>[],
    if (grammar != null)
      'algorithmRepeatGrammars': [
        {'algorithmGuid': 'quan', 'grammarVersion': 1, 'grammar': grammar},
      ],
  },
};
