import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';

void main() {
  test('v12 upgrade creates the per-slot specification values table', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute(
            'CREATE TABLE preset_slots ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT'
            ')',
          );
          rawDatabase.execute('INSERT INTO preset_slots (id) VALUES (1)');
          rawDatabase.execute('PRAGMA user_version = 12');
        },
      ),
    );
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info(preset_specification_values)')
        .get();
    final userVersion = await database
        .customSelect('PRAGMA user_version')
        .getSingle();

    expect(columns.map((row) => row.read<String>('name')), [
      'preset_slot_id',
      'specification_index',
      'value',
    ]);
    expect(userVersion.read<int>('user_version'), 14);

    expect(
      await database.select(database.presetSpecificationValues).get(),
      isEmpty,
    );
    await database
        .into(database.presetSpecificationValues)
        .insert(
          PresetSpecificationValuesCompanion.insert(
            presetSlotId: 1,
            specificationIndex: 0,
            value: 4,
          ),
        );
    final savedValue = await database
        .select(database.presetSpecificationValues)
        .getSingle();
    expect(savedValue.value, 4);
  }, tags: ['regression']);
}
