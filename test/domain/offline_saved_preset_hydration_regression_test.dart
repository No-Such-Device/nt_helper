import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';

void main() {
  group('saved presets without cached parameter metadata', () {
    late AppDatabase database;
    late OfflineDistingMidiManager manager;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      manager = OfflineDistingMidiManager(database);
      // Matches the database condition of the saved TwoBeads preset: the
      // algorithm identities and slot values exist, but parameter rows do not.
      for (final (guid, name) in const [
        ('bead', 'Texture Synthesizer 2'),
        ('ThTx', 'No Such Texture'),
      ]) {
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: Value(guid),
                name: Value(name),
                numSpecifications: const Value(0),
              ),
            );
      }
      final id = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Saved two algorithm preset',
            lastModified: DateTime(2026),
            isTemplate: false,
          ),
          slots: [
            _slot(0, 'bead', 'Texture Synthesizer 2', 35),
            _slot(1, 'ThTx', 'No Such Texture', 39),
          ],
        ),
      );
      await manager.initializeFromDb(
        await database.presetsDao.getFullPresetDetails(id),
      );
    });

    tearDown(() async => database.close());

    test(
      'retains both algorithm identities and their saved parameter counts',
      () async {
        expect(await manager.requestNumAlgorithmsInPreset(), 2);
        expect((await manager.requestAlgorithmGuid(0))?.guid, 'bead');
        expect((await manager.requestAlgorithmGuid(1))?.guid, 'ThTx');
        expect((await manager.requestNumberOfParameters(0))?.numParameters, 35);
        expect((await manager.requestNumberOfParameters(1))?.numParameters, 39);
      },
    );

    test(
      'bulk reads expose the same saved values as individual reads',
      () async {
        expect((await manager.requestParameterValue(0, 3))?.value, 21);
        for (final (slotIndex, count) in [(0, 35), (1, 39)]) {
          final allValues = await manager.requestAllParameterValues(slotIndex);
          expect(allValues, isNotNull);
          expect(allValues!.values, hasLength(count));
          for (var parameter = 0; parameter < count; parameter++) {
            expect(allValues.values[parameter].parameterNumber, parameter);
            expect(
              allValues.values[parameter].value,
              (await manager.requestParameterValue(
                slotIndex,
                parameter,
              ))?.value,
            );
          }
        }
      },
    );
    test(
      'same algorithm slots keep separate saved extents and ignore negative positions',
      () async {
        final first = _slot(0, 'bead', 'Texture Synthesizer 2', 3);
        first.parameterValues[-1] = 999;
        await manager.initializeFromDb(
          FullPresetDetails(
            preset: PresetEntry(
              id: -1,
              name: 'Distinct instances',
              lastModified: DateTime(2026),
              isTemplate: false,
            ),
            slots: [first, _slot(1, 'bead', 'Texture Synthesizer 2', 9)],
          ),
        );
        expect((await manager.requestNumberOfParameters(0))?.numParameters, 3);
        expect((await manager.requestNumberOfParameters(1))?.numParameters, 9);
        expect((await manager.requestNumberOfParameters(0))?.numParameters, 3);
        expect(
          (await manager.requestAllParameterValues(0))?.values,
          hasLength(3),
        );
        expect(
          (await manager.requestAllParameterValues(1))?.values,
          hasLength(9),
        );
      },
    , tags: ['regression']);

    for (final (guid, cachedCount, savedCount) in const [
      ('attn', 21, 41),
      ('mix2', 25, 51),
      ('spfz', 26, 36),
    ]) {
      test('$guid retains known metadata and saved tail values', () async {
        await database
            .into(database.algorithms)
            .insert(
              AlgorithmsCompanion(
                guid: Value(guid),
                name: Value(guid),
                numSpecifications: const Value(0),
              ),
            );
        for (var number = 0; number < cachedCount; number++) {
          await database
              .into(database.parameters)
              .insert(
                ParametersCompanion(
                  algorithmGuid: Value(guid),
                  parameterNumber: Value(number),
                  name: Value('Known parameter $number'),
                  minValue: const Value(-100),
                  maxValue: const Value(100),
                  defaultValue: const Value(7),
                  rawUnitIndex: const Value(2),
                  powerOfTen: const Value(-1),
                ),
              );
        }
        final id = await database.presetsDao.saveFullPreset(
          FullPresetDetails(
            preset: PresetEntry(
              id: -1,
              name: 'Expanded $guid',
              lastModified: DateTime(2026),
              isTemplate: false,
            ),
            slots: [_slot(0, guid, guid, savedCount)],
          ),
        );
        await manager.initializeFromDb(
          await database.presetsDao.getFullPresetDetails(id),
        );
        expect(
          (await manager.requestNumberOfParameters(0))?.numParameters,
          savedCount,
        );
        final known = await manager.requestParameterInfo(0, cachedCount - 1);
        expect(known?.name, 'Known parameter ${cachedCount - 1}');
        expect(known?.min, -100);
        expect(known?.max, 100);
        expect(known?.defaultValue, 7);
        expect(known?.unit, 2);
        expect(known?.powerOfTen, -1);
        final allValues = await manager.requestAllParameterValues(0);
        expect(allValues?.values, hasLength(savedCount));
        expect(allValues!.values.last.parameterNumber, savedCount - 1);
        expect(allValues.values.last.value, (savedCount - 1) % 5);
        // A longer saved parameter list does not establish missing specs.
        expect(
          (await manager.requestAlgorithmGuid(0))?.specifications,
          isEmpty,
        );
      });
    }
  });
}

FullPresetSlot _slot(int index, String guid, String name, int count) =>
    FullPresetSlot(
      slot: PresetSlotEntry(
        id: -1,
        presetId: -1,
        slotIndex: index,
        algorithmGuid: guid,
        customName: null,
      ),
      algorithm: AlgorithmEntry(
        guid: guid,
        name: name,
        numSpecifications: 0,
        pluginFilePath: null,
      ),
      parameterValues: {
        for (var parameter = 0; parameter < count; parameter++)
          parameter: parameter == 3 ? 21 : parameter % 5,
      },
      parameterStringValues: const {},
      mappings: const {},
    );
