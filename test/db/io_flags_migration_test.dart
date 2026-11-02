import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';

void main() {
  group('ioFlags Database Migration Tests', () {
    late AppDatabase database;

    setUp(() {
      // Create in-memory database for testing
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('Fresh v10 schema includes ioFlags column', () async {
      // Schema version was 11 when ParameterOutputModeUsage was added; it was
      // bumped to 12 for Presets.category + Presets.templateMetadata and 13
      // for per-slot algorithm specification values.
      expect(database.schemaVersion, 14);

      // Insert a test algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('test'),
              name: const Value('Test Algorithm'),
              numSpecifications: const Value(0),
            ),
          );

      // Insert a parameter with ioFlags
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('test'),
              parameterNumber: const Value(0),
              name: const Value('Test Parameter'),
              minValue: const Value(0),
              maxValue: const Value(100),
              defaultValue: const Value(50),
              unitId: const Value(null),
              powerOfTen: const Value(0),
              rawUnitIndex: const Value(null),
              ioFlags: const Value(5), // Test with flags value
            ),
          );

      // Query the parameter back
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify ioFlags was stored correctly
      expect(param.ioFlags, 5);
    });

    test('Parameters with null ioFlags are stored correctly', () async {
      // Insert a test algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('test'),
              name: const Value('Test Algorithm'),
              numSpecifications: const Value(0),
            ),
          );

      // Insert a parameter with null ioFlags
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('test'),
              parameterNumber: const Value(0),
              name: const Value('Test Parameter'),
              minValue: const Value(0),
              maxValue: const Value(100),
              defaultValue: const Value(50),
              unitId: const Value(null),
              powerOfTen: const Value(0),
              rawUnitIndex: const Value(null),
              ioFlags: const Value(null), // Explicit null
            ),
          );

      // Query the parameter back
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify ioFlags is null
      expect(param.ioFlags, null);
    });

    test('Parameters with ioFlags = 0 are distinct from null', () async {
      // Insert a test algorithm
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
              name: const Value('Test Parameter'),
              minValue: const Value(0),
              maxValue: const Value(100),
              defaultValue: const Value(50),
              unitId: const Value(null),
              powerOfTen: const Value(0),
              rawUnitIndex: const Value(null),
              ioFlags: const Value(0), // Explicit zero
            ),
          );

      // Query the parameter back
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();

      // Verify ioFlags is 0, not null
      expect(param.ioFlags, 0);
      expect(param.ioFlags != null, true);
    });

    test('ioFlags supports all valid flag values (0-15)', () async {
      // Insert a test algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('test'),
              name: const Value('Test Algorithm'),
              numSpecifications: const Value(0),
            ),
          );

      // Test all valid flag values
      for (int flagValue = 0; flagValue <= 15; flagValue++) {
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: Value(flagValue),
                name: Value('Parameter $flagValue'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                rawUnitIndex: const Value(null),
                ioFlags: Value(flagValue),
              ),
            );
      }

      // Query all parameters back
      final params =
          await (database.select(database.parameters)
                ..where((p) => p.algorithmGuid.equals('test'))
                ..orderBy([(p) => OrderingTerm.asc(p.parameterNumber)]))
              .get();

      // Verify all flag values
      expect(params.length, 16);
      for (int i = 0; i < 16; i++) {
        expect(params[i].ioFlags, i);
      }
    });

    test(
      'Post-migration ioFlags can be updated from null to valid values',
      () async {
        // Test with fresh v10 database (ioFlags already present)
        // Insert algorithm and parameter
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: const Value('test'),
                name: const Value('Test'),
                numSpecifications: const Value(0),
              ),
            );

        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(0),
                name: const Value('Param'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                rawUnitIndex: const Value(null),
                ioFlags: const Value(null), // Initial null
              ),
            );

        // Verify initial null state
        var param =
            await (database.select(database.parameters)..where(
                  (p) =>
                      p.algorithmGuid.equals('test') &
                      p.parameterNumber.equals(0),
                ))
                .getSingle();
        expect(param.ioFlags, isNull);

        // Update ioFlags to a valid value
        await database
            .update(database.parameters)
            .replace(
              ParameterEntry(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Param',
                minValue: 0,
                maxValue: 100,
                defaultValue: 50,
                unitId: null,
                powerOfTen: 0,
                rawUnitIndex: null,
                ioFlags: 7, // Updated value
              ),
            );

        // Verify update succeeded
        param =
            await (database.select(database.parameters)..where(
                  (p) =>
                      p.algorithmGuid.equals('test') &
                      p.parameterNumber.equals(0),
                ))
                .getSingle();
        expect(param.ioFlags, 7);
      },
    tags: ['regression']);

    // True migration tests: Verify data can be queried after fresh v10 database creation
    test(
      'Fresh v10 database can query all parameter fields including ioFlags',
      () async {
        // Create test algorithms and parameters on fresh v10 database
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: const Value('test_algo'),
                name: const Value('Test Algorithm'),
                numSpecifications: const Value(2),
              ),
            );

        // Insert parameters with various values to simulate what would exist after migration
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test_algo'),
                parameterNumber: const Value(0),
                name: const Value('Test Param 1'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                rawUnitIndex: const Value(null),
                ioFlags: const Value(null),
              ),
            );

        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test_algo'),
                parameterNumber: const Value(1),
                name: const Value('Test Param 2'),
                minValue: const Value(10),
                maxValue: const Value(200),
                defaultValue: const Value(100),
                unitId: const Value(null),
                powerOfTen: const Value(1),
                rawUnitIndex: const Value(2),
                ioFlags: const Value(null),
              ),
            );

        // Query the parameters
        final params = await (database.select(
          database.parameters,
        )..orderBy([(p) => OrderingTerm.asc(p.parameterNumber)])).get();

        // Verify all fields are present and correct
        expect(params.length, 2);

        // First parameter
        expect(params[0].algorithmGuid, 'test_algo');
        expect(params[0].parameterNumber, 0);
        expect(params[0].name, 'Test Param 1');
        expect(params[0].minValue, 0);
        expect(params[0].maxValue, 100);
        expect(params[0].defaultValue, 50);
        expect(params[0].powerOfTen, 0);
        expect(params[0].ioFlags, isNull);

        // Second parameter
        expect(params[1].algorithmGuid, 'test_algo');
        expect(params[1].parameterNumber, 1);
        expect(params[1].name, 'Test Param 2');
        expect(params[1].minValue, 10);
        expect(params[1].maxValue, 200);
        expect(params[1].defaultValue, 100);
        expect(params[1].powerOfTen, 1);
        expect(params[1].rawUnitIndex, 2);
        expect(params[1].ioFlags, isNull);
      },
    );

    test('Preserves complex data with all data types (v10 schema)', () async {
      // Insert algorithm with plugin path
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('algo1'),
              name: const Value('Algorithm One'),
              numSpecifications: const Value(5),
              pluginFilePath: const Value('/path/to/plugin.o'),
            ),
          );

      // Insert units
      await database
          .into(database.units)
          .insert(
            UnitsCompanion(id: const Value(1), unitString: const Value('%')),
          );

      await database
          .into(database.units)
          .insert(
            UnitsCompanion(id: const Value(2), unitString: const Value('Hz')),
          );

      // Insert parameter with all non-null values
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('algo1'),
              parameterNumber: const Value(0),
              name: const Value('Param Zero'),
              minValue: const Value(0),
              maxValue: const Value(100),
              defaultValue: const Value(50),
              unitId: const Value(1),
              powerOfTen: const Value(0),
              rawUnitIndex: const Value(0),
              ioFlags: const Value(null),
            ),
          );

      // Insert parameter with negative values
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('algo1'),
              parameterNumber: const Value(1),
              name: const Value('Param One'),
              minValue: const Value(-50),
              maxValue: const Value(50),
              defaultValue: const Value(0),
              unitId: const Value(2),
              powerOfTen: const Value(-1),
              rawUnitIndex: const Value(1),
              ioFlags: const Value(null),
            ),
          );

      // Insert parameter with all null values except required fields
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion(
              algorithmGuid: const Value('algo1'),
              parameterNumber: const Value(2),
              name: const Value('Param With Nulls'),
              minValue: const Value(null),
              maxValue: const Value(null),
              defaultValue: const Value(null),
              unitId: const Value(null),
              powerOfTen: const Value(null),
              rawUnitIndex: const Value(null),
              ioFlags: const Value(null),
            ),
          );

      // Verify algorithm data
      final algo = await (database.select(
        database.algorithms,
      )..where((a) => a.guid.equals('algo1'))).getSingle();
      expect(algo.numSpecifications, 5);
      expect(algo.pluginFilePath, '/path/to/plugin.o');

      // Verify units
      final units = await database.select(database.units).get();
      expect(units.length, 2);

      // Verify parameter 0
      final param0 =
          await (database.select(database.parameters)..where(
                (p) =>
                    p.algorithmGuid.equals('algo1') &
                    p.parameterNumber.equals(0),
              ))
              .getSingle();
      expect(param0.name, 'Param Zero');
      expect(param0.minValue, 0);
      expect(param0.maxValue, 100);
      expect(param0.defaultValue, 50);
      expect(param0.unitId, 1);
      expect(param0.powerOfTen, 0);
      expect(param0.rawUnitIndex, 0);
      expect(param0.ioFlags, isNull);

      // Verify parameter 1
      final param1 =
          await (database.select(database.parameters)..where(
                (p) =>
                    p.algorithmGuid.equals('algo1') &
                    p.parameterNumber.equals(1),
              ))
              .getSingle();
      expect(param1.minValue, -50);
      expect(param1.maxValue, 50);
      expect(param1.defaultValue, 0);
      expect(param1.powerOfTen, -1);
      expect(param1.ioFlags, isNull);

      // Verify parameter 2
      final param2 =
          await (database.select(database.parameters)..where(
                (p) =>
                    p.algorithmGuid.equals('algo1') &
                    p.parameterNumber.equals(2),
              ))
              .getSingle();
      expect(param2.name, 'Param With Nulls');
      expect(param2.minValue, isNull);
      expect(param2.maxValue, isNull);
      expect(param2.defaultValue, isNull);
      expect(param2.unitId, isNull);
      expect(param2.powerOfTen, isNull);
      expect(param2.rawUnitIndex, isNull);
      expect(param2.ioFlags, isNull);
    });

    test('Supports bulk parameter updates after v10 schema', () async {
      // Insert algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion(
              guid: const Value('bulk_algo'),
              name: const Value('Bulk Test'),
              numSpecifications: const Value(0),
            ),
          );

      // Insert multiple parameters
      for (int i = 0; i < 5; i++) {
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('bulk_algo'),
                parameterNumber: Value(i),
                name: Value('Param $i'),
                minValue: Value(i * 10),
                maxValue: Value(i * 20),
                defaultValue: Value(i * 15),
                unitId: const Value(null),
                powerOfTen: Value(i),
                rawUnitIndex: const Value(null),
                ioFlags: const Value(null),
              ),
            );
      }

      // Verify all parameters inserted
      var params = await (database.select(
        database.parameters,
      )..orderBy([(p) => OrderingTerm.asc(p.parameterNumber)])).get();
      expect(params.length, 5);
      for (int i = 0; i < 5; i++) {
        expect(params[i].ioFlags, isNull);
      }

      // Update one parameter to set ioFlags
      await database
          .update(database.parameters)
          .replace(
            ParameterEntry(
              algorithmGuid: 'bulk_algo',
              parameterNumber: 0,
              name: 'Param 0',
              minValue: 0,
              maxValue: 0,
              defaultValue: 0,
              unitId: null,
              powerOfTen: 0,
              rawUnitIndex: null,
              ioFlags: 5, // Can now set ioFlags
            ),
          );

      // Verify update worked
      final updatedParam =
          await (database.select(database.parameters)..where(
                (p) =>
                    p.algorithmGuid.equals('bulk_algo') &
                    p.parameterNumber.equals(0),
              ))
              .getSingle();
      expect(updatedParam.ioFlags, 5);

      // Verify other parameters still have null ioFlags
      final otherParam =
          await (database.select(database.parameters)..where(
                (p) =>
                    p.algorithmGuid.equals('bulk_algo') &
                    p.parameterNumber.equals(1),
              ))
              .getSingle();
      expect(otherParam.ioFlags, isNull);
    });
  });
}
