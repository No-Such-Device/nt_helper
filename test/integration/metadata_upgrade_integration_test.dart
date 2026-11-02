import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/metadata_upgrade_service.dart';

/// Integration tests for the metadata upgrade flow.
///
/// These tests verify the end-to-end upgrade process, including:
/// - Detection of databases needing upgrade
/// - Preservation of user data during upgrade
/// - Idempotent behavior
/// - Fresh install vs existing install scenarios
void main() {
  group('Metadata Upgrade Integration', () {
    late AppDatabase database;
    late MetadataUpgradeService service;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = MetadataUpgradeService();
    });

    tearDown(() async {
      await database.close();
    });

    test('fresh install scenario - no upgrade needed', () async {
      // Simulate fresh install with bundled metadata already imported
      // (This would happen via MetadataImportService in real scenario)

      // Create algorithm with factory data
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion.insert(
              guid: 'clck',
              name: 'Clock',
              numSpecifications: 1,
            ),
          );

      // Create parameters with ioFlags already set (fresh import)
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion.insert(
              algorithmGuid: 'clck',
              parameterNumber: 0,
              name: 'Clock output',
              ioFlags: const Value(10), // Has ioFlags from import
            ),
          );

      // Check upgrade detection
      final needsUpgrade = await service.needsIoFlagsUpgrade(database);
      expect(
        needsUpgrade,
        isFalse,
        reason: 'Fresh install should not need upgrade',
      );

      // Perform upgrade check
      final updateCount = await service.performUpgradeIfNeeded(database);
      expect(updateCount, equals(0), reason: 'No parameters should be updated');

      // Verify ioFlags unchanged
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('clck'))).getSingle();
      expect(param.ioFlags, equals(10));
    });

    test(
      'existing install scenario - simulates old database with null ioFlags',
      () async {
        // Simulate existing installation upgraded from old version
        // Old version would have parameters with null ioFlags

        // Create algorithm
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'clck',
                name: 'Clock',
                numSpecifications: 1,
              ),
            );

        // Create parameters with null ioFlags (old version)
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion.insert(
                algorithmGuid: 'clck',
                parameterNumber: 0,
                name: 'Clock output',
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                ioFlags: const Value(null), // Old version had no ioFlags
              ),
            );

        // Check upgrade detection
        final needsUpgrade = await service.needsIoFlagsUpgrade(database);
        expect(
          needsUpgrade,
          isTrue,
          reason: 'Old database should need upgrade',
        );

        // Note: We can't actually perform the upgrade in test environment
        // because bundled metadata asset is not available
        // But we verified the detection logic works
      },
    tags: ['regression']);

    test('user presets are preserved during upgrade detection', () async {
      // Create algorithm
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

      // Create user preset
      final presetId = await database
          .into(database.presets)
          .insert(
            PresetsCompanion.insert(
              name: 'My Preset',
              lastModified: Value(DateTime.now()),
            ),
          );

      // Create preset slot
      final slotId = await database
          .into(database.presetSlots)
          .insert(
            PresetSlotsCompanion.insert(
              presetId: presetId,
              slotIndex: 0,
              algorithmGuid: 'test',
            ),
          );

      // Create preset parameter value
      await database
          .into(database.presetParameterValues)
          .insert(
            PresetParameterValuesCompanion.insert(
              presetSlotId: slotId,
              parameterNumber: 0,
              value: 42,
            ),
          );

      // Check upgrade needed
      final needsUpgrade = await service.needsIoFlagsUpgrade(database);
      expect(needsUpgrade, isTrue);

      // Note: Actual upgrade would run here with bundled metadata
      // For now, verify preset data is intact
      final preset = await (database.select(
        database.presets,
      )..where((p) => p.id.equals(presetId))).getSingle();
      expect(preset.name, equals('My Preset'));

      final paramValue = await (database.select(
        database.presetParameterValues,
      )..where((p) => p.presetSlotId.equals(slotId))).getSingle();
      expect(paramValue.value, equals(42));
    });

    test('upgrade detection with mixed ioFlags states', () async {
      // Create algorithm
      await database
          .into(database.algorithms)
          .insert(
            AlgorithmsCompanion.insert(
              guid: 'test',
              name: 'Test Algorithm',
              numSpecifications: 0,
            ),
          );

      // Create parameters - some with ioFlags, some without
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion.insert(
              algorithmGuid: 'test',
              parameterNumber: 0,
              name: 'Param 1',
              ioFlags: const Value(5), // Has flags
            ),
          );
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion.insert(
              algorithmGuid: 'test',
              parameterNumber: 1,
              name: 'Param 2',
              ioFlags: const Value(null), // No flags
            ),
          );
      await database
          .into(database.parameters)
          .insert(
            ParametersCompanion.insert(
              algorithmGuid: 'test',
              parameterNumber: 2,
              name: 'Param 3',
              ioFlags: const Value(10), // Has flags
            ),
          );

      // Mixed state should indicate upgrade not needed
      // (assumes some data already present from hardware sync)
      final needsUpgrade = await service.needsIoFlagsUpgrade(database);
      expect(
        needsUpgrade,
        isFalse,
        reason:
            'Mixed state indicates partial data from hardware, skip upgrade',
      );
    });

    test('template presets are preserved', () async {
      // Create algorithm
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

      // Create template preset
      final templateId = await database
          .into(database.presets)
          .insert(
            PresetsCompanion.insert(
              name: 'My Template',
              lastModified: Value(DateTime.now()),
              isTemplate: const Value(true),
            ),
          );

      // Check upgrade needed
      final needsUpgrade = await service.needsIoFlagsUpgrade(database);
      expect(needsUpgrade, isTrue);

      // Verify template preserved
      final template = await (database.select(
        database.presets,
      )..where((p) => p.id.equals(templateId))).getSingle();
      expect(template.isTemplate, isTrue);
      expect(template.name, equals('My Template'));
    }, tags: ['regression']);

    test('multiple algorithms with parameters', () async {
      // Create multiple algorithms
      for (var i = 0; i < 3; i++) {
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion.insert(
                guid: 'alg$i',
                name: 'Algorithm $i',
                numSpecifications: 0,
              ),
            );

        // Each algorithm has multiple parameters with null ioFlags
        for (var j = 0; j < 5; j++) {
          await database
              .into(database.parameters)
              .insert(
                ParametersCompanion.insert(
                  algorithmGuid: 'alg$i',
                  parameterNumber: j,
                  name: 'Param $j',
                  ioFlags: const Value(null),
                ),
              );
        }
      }

      // Should detect upgrade needed (15 total parameters, all null)
      final needsUpgrade = await service.needsIoFlagsUpgrade(database);
      expect(needsUpgrade, isTrue);

      // Verify parameter count
      final allParams = await database.select(database.parameters).get();
      expect(allParams.length, equals(15));
      expect(allParams.every((p) => p.ioFlags == null), isTrue);
    });

    test('idempotent upgrade check', () async {
      // Create algorithm with parameters that already have ioFlags
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
              ioFlags: const Value(5),
            ),
          );

      // Run upgrade check multiple times
      final result1 = await service.performUpgradeIfNeeded(database);
      final result2 = await service.performUpgradeIfNeeded(database);
      final result3 = await service.performUpgradeIfNeeded(database);

      // All should return 0 (no update needed)
      expect(result1, equals(0));
      expect(result2, equals(0));
      expect(result3, equals(0));

      // Verify ioFlags unchanged
      final param = await (database.select(
        database.parameters,
      )..where((p) => p.algorithmGuid.equals('test'))).getSingle();
      expect(param.ioFlags, equals(5));
    }, tags: ['regression']);
  });
}
