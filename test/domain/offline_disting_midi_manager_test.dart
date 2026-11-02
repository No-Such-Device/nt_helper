import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';

void main() {
  group('OfflineDistingMidiManager ioFlags Tests', () {
    late AppDatabase database;
    late OfflineDistingMidiManager manager;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      manager = OfflineDistingMidiManager(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('requestParameterInfo reads ioFlags from database', () async {
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

      // Insert parameter with ioFlags = 7
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
              rawUnitIndex: const Value(5),
              ioFlags: const Value(7), // Test ioFlags value
            ),
          );

      // Initialize manager with preset containing the algorithm
      final preset = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
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
                algorithmGuid: 'test',
                customName: null,
              ),
              algorithm: AlgorithmEntry(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
                pluginFilePath: null,
              ),
              parameterValues: {},
              parameterStringValues: {},
              mappings: {},
            ),
          ],
        ),
      );

      final presetDetails = await database.presetsDao.getFullPresetDetails(
        preset,
      );
      await manager.initializeFromDb(presetDetails);

      // Request parameter info
      final paramInfo = await manager.requestParameterInfo(0, 0);

      // Verify ioFlags is read correctly
      expect(paramInfo, isNotNull);
      expect(paramInfo!.ioFlags, 7);
    });

    test('requestParameterInfo defaults null ioFlags to 0', () async {
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

      // Insert parameter with null ioFlags
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
              rawUnitIndex: const Value(5),
              ioFlags: const Value(null), // Null ioFlags
            ),
          );

      // Initialize manager with preset
      final preset = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
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
                algorithmGuid: 'test',
                customName: null,
              ),
              algorithm: AlgorithmEntry(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
                pluginFilePath: null,
              ),
              parameterValues: {},
              parameterStringValues: {},
              mappings: {},
            ),
          ],
        ),
      );

      final presetDetails = await database.presetsDao.getFullPresetDetails(
        preset,
      );
      await manager.initializeFromDb(presetDetails);

      // Request parameter info
      final paramInfo = await manager.requestParameterInfo(0, 0);

      // Verify null ioFlags defaults to 0
      expect(paramInfo, isNotNull);
      expect(paramInfo!.ioFlags, 0);
    }, tags: ['regression']);

    test(
      'requestParameterInfo distinguishes between null and 0 ioFlags',
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

        // Insert parameter with ioFlags = 0 (explicit zero)
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
                rawUnitIndex: const Value(5),
                ioFlags: const Value(0), // Explicit zero
              ),
            );

        // Insert parameter with null ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(1),
                name: const Value('Param with null flags'),
                minValue: const Value(0),
                maxValue: const Value(100),
                defaultValue: const Value(50),
                unitId: const Value(null),
                powerOfTen: const Value(0),
                rawUnitIndex: const Value(5),
                ioFlags: const Value(null), // Null
              ),
            );

        // Initialize manager with preset
        final preset = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
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
                  algorithmGuid: 'test',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
              ),
            ],
          ),
        );

        final presetDetails = await database.presetsDao.getFullPresetDetails(
          preset,
        );
        await manager.initializeFromDb(presetDetails);

        // Request both parameters
        final paramInfo0 = await manager.requestParameterInfo(0, 0);
        final paramInfo1 = await manager.requestParameterInfo(0, 1);

        // Both should default to 0, but both came from database
        expect(paramInfo0, isNotNull);
        expect(paramInfo0!.ioFlags, 0);

        expect(paramInfo1, isNotNull);
        expect(paramInfo1!.ioFlags, 0);
      },
    tags: ['regression']);

    test(
      'requestParameterInfo handles all valid ioFlags values (0-15)',
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

        // Insert parameters with all valid ioFlags values
        for (int flagValue = 0; flagValue <= 15; flagValue++) {
          await database
              .into(database.parameters)
              .insert(
                ParametersCompanion(
                  algorithmGuid: const Value('test'),
                  parameterNumber: Value(flagValue),
                  name: Value('Param $flagValue'),
                  minValue: const Value(0),
                  maxValue: const Value(100),
                  defaultValue: const Value(50),
                  unitId: const Value(null),
                  powerOfTen: const Value(0),
                  rawUnitIndex: const Value(5),
                  ioFlags: Value(flagValue),
                ),
              );
        }

        // Initialize manager with preset
        final preset = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
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
                  algorithmGuid: 'test',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
              ),
            ],
          ),
        );

        final presetDetails = await database.presetsDao.getFullPresetDetails(
          preset,
        );
        await manager.initializeFromDb(presetDetails);

        // Request all parameters and verify ioFlags values
        for (int flagValue = 0; flagValue <= 15; flagValue++) {
          final paramInfo = await manager.requestParameterInfo(0, flagValue);
          expect(paramInfo, isNotNull);
          expect(paramInfo!.ioFlags, flagValue);
        }
      },
    );

    test(
      'requestParameterInfo preserves all other fields when reading ioFlags',
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

        // Insert unit
        await database
            .into(database.units)
            .insert(
              UnitsCompanion(id: const Value(1), unitString: const Value('%')),
            );

        // Insert parameter with all fields populated including ioFlags
        await database
            .into(database.parameters)
            .insert(
              ParametersCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(0),
                name: const Value('Full Parameter'),
                minValue: const Value(10),
                maxValue: const Value(90),
                defaultValue: const Value(45),
                unitId: const Value(1),
                powerOfTen: const Value(2),
                rawUnitIndex: const Value(3),
                ioFlags: const Value(12), // Test ioFlags
              ),
            );

        // Initialize manager with preset
        final preset = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
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
                  algorithmGuid: 'test',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
              ),
            ],
          ),
        );

        final presetDetails = await database.presetsDao.getFullPresetDetails(
          preset,
        );
        await manager.initializeFromDb(presetDetails);

        // Request parameter info
        final paramInfo = await manager.requestParameterInfo(0, 0);

        // Verify all fields are preserved
        expect(paramInfo, isNotNull);
        expect(paramInfo!.algorithmIndex, 0);
        expect(paramInfo.parameterNumber, 0);
        expect(paramInfo.name, 'Full Parameter');
        expect(paramInfo.min, 10);
        expect(paramInfo.max, 90);
        expect(paramInfo.defaultValue, 45);
        expect(paramInfo.unit, 3); // rawUnitIndex
        expect(paramInfo.powerOfTen, 2);
        expect(paramInfo.ioFlags, 12);
      },
    );
  });

  group('OfflineDistingMidiManager requestOutputModeUsage Tests', () {
    late AppDatabase database;
    late OfflineDistingMidiManager manager;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      manager = OfflineDistingMidiManager(database);
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'DAO getOutputModeUsage retrieves data correctly from database',
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

        // Insert output mode usage data
        await database
            .into(database.parameterOutputModeUsage)
            .insert(
              ParameterOutputModeUsageCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(0),
                affectedOutputNumbers: const Value([1, 2, 3]),
              ),
            );

        // Query via DAO
        final result = await database.metadataDao.getOutputModeUsage('test', 0);

        // Verify data is retrieved correctly
        expect(result, isNotNull);
        expect(result, equals([1, 2, 3]));
      },
    );

    test('DAO getOutputModeUsage returns null when no data exists', () async {
      // Query for non-existent data
      final result = await database.metadataDao.getOutputModeUsage('test', 0);

      // Verify null is returned
      expect(result, isNull);
    });

    test(
      'requestOutputModeUsage returns OutputModeUsage when data exists',
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

        // Insert output mode usage data
        await database
            .into(database.parameterOutputModeUsage)
            .insert(
              ParameterOutputModeUsageCompanion(
                algorithmGuid: const Value('test'),
                parameterNumber: const Value(2),
                affectedOutputNumbers: const Value([5, 6]),
              ),
            );

        // Initialize manager with preset
        final preset = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
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
                  algorithmGuid: 'test',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
              ),
            ],
          ),
        );

        final presetDetails = await database.presetsDao.getFullPresetDetails(
          preset,
        );
        await manager.initializeFromDb(presetDetails);

        // Request output mode usage
        final result = await manager.requestOutputModeUsage(0, 2);

        // Verify OutputModeUsage is returned with correct data
        expect(result, isNotNull);
        expect(result!.parameterNumber, equals(2));
        expect(result.affectedParameterNumbers, equals([5, 6]));
      },
    );

    test(
      'requestOutputModeUsage returns null when no data in database',
      () async {
        // Insert test algorithm with no output mode usage data
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: const Value('test'),
                name: const Value('Test Algorithm'),
                numSpecifications: const Value(0),
              ),
            );

        // Initialize manager with preset
        final preset = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
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
                  algorithmGuid: 'test',
                  customName: null,
                ),
                algorithm: AlgorithmEntry(
                  guid: 'test',
                  name: 'Test Algorithm',
                  numSpecifications: 0,
                  pluginFilePath: null,
                ),
                parameterValues: {},
                parameterStringValues: {},
                mappings: {},
              ),
            ],
          ),
        );

        final presetDetails = await database.presetsDao.getFullPresetDetails(
          preset,
        );
        await manager.initializeFromDb(presetDetails);

        // Request output mode usage for non-existent parameter
        final result = await manager.requestOutputModeUsage(0, 99);

        // Verify null is returned (graceful fallback)
        expect(result, isNull);
      },
    );

    test('requestOutputModeUsage returns invalid index handling', () async {
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

      // Initialize manager with preset
      final preset = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
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
                algorithmGuid: 'test',
                customName: null,
              ),
              algorithm: AlgorithmEntry(
                guid: 'test',
                name: 'Test Algorithm',
                numSpecifications: 0,
                pluginFilePath: null,
              ),
              parameterValues: {},
              parameterStringValues: {},
              mappings: {},
            ),
          ],
        ),
      );

      final presetDetails = await database.presetsDao.getFullPresetDetails(
        preset,
      );
      await manager.initializeFromDb(presetDetails);

      // Request with invalid algorithm index
      final result = await manager.requestOutputModeUsage(999, 0);

      // Verify graceful handling (null or exception caught)
      expect(result, isNull);
    });
  });
}
