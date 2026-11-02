import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/services/algorithm_json_exporter.dart';

void main() {
  group('ioFlags JSON Import/Export Tests', () {
    late AppDatabase database;
    late MetadataImportService importService;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      importService = MetadataImportService(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('Import handles missing ioFlags field (old v1 format)', () async {
      // Create JSON without ioFlags field (version 1 format)
      final jsonString = json.encode({
        'exportType': 'full_metadata',
        'exportVersion': 1,
        'tables': {
          'algorithms': [
            {
              'guid': 'test',
              'name': 'Test Algorithm',
              'numSpecifications': 0,
              'pluginFilePath': null,
            },
          ],
          'parameters': [
            {
              'algorithmGuid': 'test',
              'parameterNumber': 0,
              'name': 'Test Parameter',
              'minValue': 0,
              'maxValue': 100,
              'defaultValue': 50,
              'unitId': null,
              'powerOfTen': 0,
              'rawUnitIndex': null,
              // No ioFlags field
            },
          ],
        },
      });

      // Import the JSON
      final success = await importService.importFromJson(jsonString);
      expect(success, isTrue);

      // Query the parameter
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify ioFlags is null (missing field treated as null)
      expect(param.ioFlags, isNull);
    }, tags: ['regression']);

    test('Import handles explicit null ioFlags', () async {
      // Create JSON with explicit null ioFlags
      final jsonString = json.encode({
        'exportType': 'full_metadata',
        'exportVersion': 2,
        'tables': {
          'algorithms': [
            {
              'guid': 'test',
              'name': 'Test Algorithm',
              'numSpecifications': 0,
              'pluginFilePath': null,
            },
          ],
          'parameters': [
            {
              'algorithmGuid': 'test',
              'parameterNumber': 0,
              'name': 'Test Parameter',
              'minValue': 0,
              'maxValue': 100,
              'defaultValue': 50,
              'unitId': null,
              'powerOfTen': 0,
              'rawUnitIndex': null,
              'ioFlags': null, // Explicit null
            },
          ],
        },
      });

      // Import the JSON
      final success = await importService.importFromJson(jsonString);
      expect(success, isTrue);

      // Query the parameter
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify ioFlags is null
      expect(param.ioFlags, isNull);
    });

    test('Import reads ioFlags correctly for valid values (0-15)', () async {
      for (int flagValue = 0; flagValue <= 15; flagValue++) {
        // Create JSON with specific ioFlags value
        final jsonString = json.encode({
          'exportType': 'full_metadata',
          'exportVersion': 2,
          'tables': {
            'algorithms': [
              {
                'guid': 'test$flagValue',
                'name': 'Test Algorithm $flagValue',
                'numSpecifications': 0,
                'pluginFilePath': null,
              },
            ],
            'parameters': [
              {
                'algorithmGuid': 'test$flagValue',
                'parameterNumber': 0,
                'name': 'Test Parameter',
                'minValue': 0,
                'maxValue': 100,
                'defaultValue': 50,
                'unitId': null,
                'powerOfTen': 0,
                'rawUnitIndex': null,
                'ioFlags': flagValue,
              },
            ],
          },
        });

        // Import the JSON
        final success = await importService.importFromJson(jsonString);
        expect(success, isTrue);

        // Query the parameter
        final param = await (database.select(
          database.parameters,
        )..where((p) => p.algorithmGuid.equals('test$flagValue'))).getSingle();

        // Verify ioFlags value
        expect(param.ioFlags, flagValue);
      }
    });

    test(
      'Import validates ioFlags range (invalid values treated as null)',
      () async {
        final invalidValues = [-1, 16, 100, 255];

        for (int invalidValue in invalidValues) {
          // Create JSON with invalid ioFlags value
          final jsonString = json.encode({
            'exportType': 'full_metadata',
            'exportVersion': 2,
            'tables': {
              'algorithms': [
                {
                  'guid': 'test$invalidValue',
                  'name': 'Test Algorithm $invalidValue',
                  'numSpecifications': 0,
                  'pluginFilePath': null,
                },
              ],
              'parameters': [
                {
                  'algorithmGuid': 'test$invalidValue',
                  'parameterNumber': 0,
                  'name': 'Test Parameter',
                  'minValue': 0,
                  'maxValue': 100,
                  'defaultValue': 50,
                  'unitId': null,
                  'powerOfTen': 0,
                  'rawUnitIndex': null,
                  'ioFlags': invalidValue,
                },
              ],
            },
          });

          // Import the JSON
          final success = await importService.importFromJson(jsonString);
          expect(success, isTrue);

          // Query the parameter
          final param =
              await (database.select(database.parameters)
                    ..where((p) => p.algorithmGuid.equals('test$invalidValue')))
                  .getSingle();

          // Verify invalid value treated as null
          expect(param.ioFlags, isNull);
        }
      },
    );

    test('Import preserves all existing fields with ioFlags', () async {
      // Create JSON with all fields including ioFlags
      final jsonString = json.encode({
        'exportType': 'full_metadata',
        'exportVersion': 2,
        'tables': {
          'algorithms': [
            {
              'guid': 'test',
              'name': 'Test Algorithm',
              'numSpecifications': 5,
              'pluginFilePath': '/path/to/plugin.o',
            },
          ],
          'units': [
            {'id': 1, 'unitString': '%'},
          ],
          'parameters': [
            {
              'algorithmGuid': 'test',
              'parameterNumber': 0,
              'name': 'Test Parameter',
              'minValue': 10,
              'maxValue': 90,
              'defaultValue': 45,
              'unitId': 1,
              'powerOfTen': 2,
              'rawUnitIndex': 3,
              'ioFlags': 7,
            },
          ],
        },
      });

      // Import the JSON
      final success = await importService.importFromJson(jsonString);
      expect(success, isTrue);

      // Query the parameter
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify all fields preserved
      expect(param.algorithmGuid, 'test');
      expect(param.parameterNumber, 0);
      expect(param.name, 'Test Parameter');
      expect(param.minValue, 10);
      expect(param.maxValue, 90);
      expect(param.defaultValue, 45);
      expect(param.unitId, 1);
      expect(param.powerOfTen, 2);
      expect(param.rawUnitIndex, 3);
      expect(param.ioFlags, 7);
    });

    test('Import reads output mode usage affected outputs from JSON', () async {
      final jsonString = json.encode({
        'exportType': 'full_metadata',
        'exportVersion': 2,
        'tables': {
          'algorithms': [
            {
              'guid': 'test',
              'name': 'Test Algorithm',
              'numSpecifications': 0,
              'pluginFilePath': null,
            },
          ],
          'parameterOutputModeUsage': [
            {
              'algorithmGuid': 'test',
              'parameterNumber': 5,
              'affectedOutputNumbers': [4, 7],
            },
          ],
        },
      });

      final success = await importService.importFromJson(jsonString);
      expect(success, isTrue);

      final affectedOutputs = await database.metadataDao.getOutputModeUsage(
        'test',
        5,
      );
      expect(affectedOutputs, [4, 7]);
    });

    test(
      'Export includes ioFlags field for parameters with non-null values',
      () async {
        // Insert test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: const Value('test'),
                name: const Value('Test Algorithm'),
                numSpecifications: const Value(0),
              ),
            );

        // Insert parameters with various ioFlags values
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(0),
                name: const Value('Param with ioFlags'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                ioFlags: const Value(7), // Non-null ioFlags
                rawUnitIndex: const Value(null),
              ),
            );

        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(1),
                name: const Value('Param without ioFlags'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                ioFlags: const Value(null), // Null ioFlags
                rawUnitIndex: const Value(null),
              ),
            );

        // Export to JSON
        final exporter = AlgorithmJsonExporter(database);
        final tempDir = Directory.systemTemp.createTempSync(
          'io_flags_export_test',
        );
        final exportPath = '${tempDir.path}/export.json';

        await exporter.exportFullMetadata(exportPath);

        // Read and parse the exported JSON
        final exportFile = File(exportPath);
        final exportJson = json.decode(await exportFile.readAsString());

        // Verify export structure
        expect(exportJson['exportVersion'], 3);
        expect(exportJson['exportType'], 'full_metadata');

        // Find the parameters in the export
        final parameters = exportJson['tables']['parameters'] as List;
        expect(parameters.length, 2);

        // Verify first parameter has ioFlags
        final param0 = parameters.firstWhere(
          (p) => p['algorithmGuid'] == 'test' && p['parameterNumber'] == 0,
        );
        expect(param0['ioFlags'], 7);

        // Verify second parameter has null ioFlags
        final param1 = parameters.firstWhere(
          (p) => p['algorithmGuid'] == 'test' && p['parameterNumber'] == 1,
        );
        expect(param1['ioFlags'], isNull);

        // Cleanup
        tempDir.deleteSync(recursive: true);
      },
    );

    test('Export includes ioFlags = 0 (distinct from null)', () async {
      // Insert test algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('test'),
              name: const Value('Test Algorithm'),
              numSpecifications: const Value(0),
            ),
          );

      // Insert parameter with ioFlags = 0
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('test'),
              parameterNumber: const Value(0),
              name: const Value('Param with zero flags'),
              minValue: const Value(0),
              maxValue: const Value(100),
              defaultValue: const Value(50),
              unitId: const Value(null),
              powerOfTen: const Value(0),
              ioFlags: const Value(0), // Explicit zero
              rawUnitIndex: const Value(null),
            ),
          );

      // Export to JSON
      final exporter = AlgorithmJsonExporter(database);
      final tempDir = Directory.systemTemp.createTempSync(
        'io_flags_export_test',
      );
      final exportPath = '${tempDir.path}/export.json';

      await exporter.exportFullMetadata(exportPath);

      // Read and parse the exported JSON
      final exportFile = File(exportPath);
      final exportJson = json.decode(await exportFile.readAsString());

      // Find the parameter in the export
      final parameters = exportJson['tables']['parameters'] as List;
      final param = parameters.firstWhere(
        (p) => p['algorithmGuid'] == 'test' && p['parameterNumber'] == 0,
      );

      // Verify ioFlags is 0, not null
      expect(param['ioFlags'], 0);
      expect(param['ioFlags'] != null, isTrue);

      // Cleanup
      tempDir.deleteSync(recursive: true);
    }, tags: ['regression']);

    test('Export→Import round-trip preserves ioFlags values', () async {
      // Insert test data
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('test'),
              name: const Value('Test Algorithm'),
              numSpecifications: const Value(0),
            ),
          );

      // Insert parameters with various ioFlags values
      final testValues = [null, 0, 5, 15];
      for (int i = 0; i < testValues.length; i++) {
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: Value(i),
                name: Value('Param $i'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                ioFlags: Value(testValues[i]),
                rawUnitIndex: const Value(null),
              ),
            );
      }

      // Export to JSON
      final exporter = AlgorithmJsonExporter(database);
      final tempDir = Directory.systemTemp.createTempSync(
        'io_flags_export_test',
      );
      final exportPath = '${tempDir.path}/export.json';

      await exporter.exportFullMetadata(exportPath);

      // Read the exported JSON
      final exportFile = File(exportPath);
      final exportJsonString = await exportFile.readAsString();

      // Create a fresh database for import
      final importDb = AppDatabase.forTesting(NativeDatabase.memory());
      final importService = MetadataImportService(importDb);

      // Import the JSON
      final success = await importService.importFromJson(exportJsonString);
      expect(success, isTrue);

      // Verify all ioFlags values preserved
      for (int i = 0; i < testValues.length; i++) {
        final param =
            await (importDb.select(importDb.parameters)..where(
                  (p) =>
                      p.algorithmGuid.equals('test') &
                      p.parameterNumber.equals(i),
                ))
                .getSingle();

        expect(
          param.ioFlags,
          testValues[i],
          reason: 'Parameter $i ioFlags should be ${testValues[i]}',
        );
      }

      // Cleanup
      await importDb.close();
      tempDir.deleteSync(recursive: true);
    });

    test(
      'Export includes only factory algorithms with lowercase GUIDs',
      () async {
        await database.metadataDao.upsertAlgorithms([
          const AlgorithmEntry(
            guid: 'lfo ',
            name: 'LFO',
            numSpecifications: 1,
            pluginFilePath: null,
          ),
          const AlgorithmEntry(
            guid: 'env2',
            name: 'Envelope',
            numSpecifications: 0,
            pluginFilePath: null,
          ),
          const AlgorithmEntry(
            guid: 'PLUG',
            name: 'Community Plugin',
            numSpecifications: 0,
            pluginFilePath: '/plugins/PLUG.o',
          ),
          const AlgorithmEntry(
            guid: 'plug-in',
            name: 'Lowercase Non-Factory Plugin',
            numSpecifications: 0,
            pluginFilePath: '/plugins/plug-in.o',
          ),
        ]);

        await database.metadataDao.upsertParameters([
          const ParameterEntry(
            algorithmGuid: 'lfo ',
            parameterNumber: 0,
            name: 'Output',
            minValue: 0,
            maxValue: 64,
            defaultValue: 13,
            unitId: null,
            powerOfTen: 0,
            rawUnitIndex: 1,
            ioFlags: 2,
          ),
          const ParameterEntry(
            algorithmGuid: 'env2',
            parameterNumber: 0,
            name: 'Gate input',
            minValue: 0,
            maxValue: 64,
            defaultValue: 1,
            unitId: null,
            powerOfTen: 0,
            rawUnitIndex: 1,
            ioFlags: 1,
          ),
          const ParameterEntry(
            algorithmGuid: 'PLUG',
            parameterNumber: 0,
            name: 'Plugin input',
            minValue: 0,
            maxValue: 64,
            defaultValue: 1,
            unitId: null,
            powerOfTen: 0,
            rawUnitIndex: 1,
            ioFlags: 1,
          ),
          const ParameterEntry(
            algorithmGuid: 'plug-in',
            parameterNumber: 0,
            name: 'Plugin input',
            minValue: 0,
            maxValue: 64,
            defaultValue: 1,
            unitId: null,
            powerOfTen: 0,
            rawUnitIndex: 1,
            ioFlags: 1,
          ),
        ]);

        final exporter = AlgorithmJsonExporter(database);
        final tempDir = Directory.systemTemp.createTempSync(
          'factory_export_test',
        );
        final exportPath = '${tempDir.path}/export.json';

        await exporter.exportFullMetadata(exportPath);

        final exportJson = json.decode(await File(exportPath).readAsString());
        final algorithms = exportJson['tables']['algorithms'] as List;
        final exportedGuids = algorithms.map((a) => a['guid']).toSet();

        expect(exportedGuids, containsAll(['lfo ', 'env2']));
        expect(exportedGuids, isNot(contains('PLUG')));
        expect(exportedGuids, isNot(contains('plug-in')));

        tempDir.deleteSync(recursive: true);
      },
    );
  });
}
