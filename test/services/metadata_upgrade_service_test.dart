import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/metadata_upgrade_service.dart';

void main() {
  group('MetadataUpgradeService', () {
    late AppDatabase database;
    late MetadataUpgradeService service;

    setUp(() {
      // Create in-memory database for testing
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = MetadataUpgradeService();
    });

    tearDown(() async {
      await database.close();
    });

    group('needsIoFlagsUpgrade', () {
      test('returns true when all parameters have null ioFlags', () async {
        // Create test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );

        // Create test parameters with null ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param 1',
                ioFlags: const Value(null),
              ),
            );
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 1,
                name: 'Test Param 2',
                ioFlags: const Value(null),
              ),
            );

        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        expect(needsUpgrade, isTrue);
      });

      test('returns false when some parameters have ioFlags', () async {
        // Create test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );

        // Create test parameters - one with ioFlags, one without
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param 1',
                ioFlags: const Value(5), // Has ioFlags
              ),
            );
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 1,
                name: 'Test Param 2',
                ioFlags: const Value(null),
              ),
            );

        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        expect(needsUpgrade, isFalse);
      });

      test('returns false when all parameters have ioFlags', () async {
        // Create test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );

        // Create test parameters with ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param 1',
                ioFlags: const Value(5),
              ),
            );
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 1,
                name: 'Test Param 2',
                ioFlags: const Value(8),
              ),
            );

        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        expect(needsUpgrade, isFalse);
      });

      test('returns true when database is empty', () async {
        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        // Empty database has zero parameters with non-null ioFlags
        expect(needsUpgrade, isTrue);
      });

      test('handles database errors gracefully', () async {
        // Create algorithm and parameter to set up state
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param',
                ioFlags: const Value(null),
              ),
            );

        // Close the database to cause an error on next query
        await database.close();

        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        // Should return false when query fails (safe default)
        expect(needsUpgrade, isFalse);
      });
    });

    group('upgradeIoFlags', () {
      test('throws exception when bundled metadata is missing', () async {
        // This test will fail to load the asset in test environment
        // The service should throw an exception with context
        expect(
          () => service.upgradeIoFlags(database),
          throwsA(isA<Exception>()),
        );
      });

      
    });

    group('performUpgradeIfNeeded', () {
      test('returns 0 when upgrade not needed', () async {
        // Create test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );

        // Create parameter with existing ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param',
                ioFlags: const Value(5),
              ),
            );

        final updateCount = await service.performUpgradeIfNeeded(database);
        expect(updateCount, equals(0));
      });

      test(
        'attempts upgrade when needed but throws without bundled metadata',
        () async {
          // Create test algorithm
          await database
              .into(database.algorithms)
              .insert(
                AlgorithmsCompanion.insert(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                ),
              );

          // Create parameter with null ioFlags
          await database
              .into(database.parameters)
              .insert(
                ParametersCompanion.insert(
                  algorithmGuid: 'test',
                  parameterNumber: 0,
                  name: 'Test Param',
                  ioFlags: const Value(null),
                ),
              );

          // Should throw because bundled metadata is not available in test
          expect(
            () => service.performUpgradeIfNeeded(database),
            throwsA(isA<Exception>()),
          );
        },
      );
    });

    group('idempotent behavior', () {
      test('running upgrade multiple times is safe', () async {
        // Create test algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
              ),
            );

        // Create parameter with existing ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'test',
                parameterNumber: 0,
                name: 'Test Param',
                ioFlags: const Value(5),
              ),
            );

        // Run upgrade twice - should not cause issues
        final count1 = await service.performUpgradeIfNeeded(database);
        final count2 = await service.performUpgradeIfNeeded(database);

        expect(count1, equals(0));
        expect(count2, equals(0));

        // Verify ioFlags unchanged
        final param = await (database.select(
          database.parameters,
        )..where((p) => p.algorithmGuid.equals('test'))).getSingle();
        expect(param.ioFlags, equals(5));
      });
    });

    group('data preservation', () {
      
    });
  });
}
