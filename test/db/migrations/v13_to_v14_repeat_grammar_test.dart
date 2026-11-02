import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';

void main() {
  test('v13 upgrade adds grammar table and preserves flat metadata', () async {
    final database = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute(
            'CREATE TABLE algorithms ('
            'guid TEXT NOT NULL PRIMARY KEY, '
            'name TEXT NOT NULL, '
            'num_specifications INTEGER NOT NULL, '
            'plugin_file_path TEXT NULL'
            ')',
          );
          rawDatabase.execute(
            "INSERT INTO algorithms VALUES ('quan', 'Quantizer', 1, NULL)",
          );
          rawDatabase.execute('PRAGMA user_version = 13');
        },
      ),
    );
    addTearDown(database.close);

    final algorithm = await database.select(database.algorithms).getSingle();
    final columns = await database
        .customSelect('PRAGMA table_info(algorithm_repeat_grammars)')
        .get();
    final userVersion = await database
        .customSelect('PRAGMA user_version')
        .getSingle();

    expect(algorithm.guid, 'quan');
    expect(columns.map((row) => row.read<String>('name')), [
      'algorithm_guid',
      'grammar_version',
      'grammar_json',
    ]);
    expect(userVersion.read<int>('user_version'), 14);
    expect(
      await database.select(database.algorithmRepeatGrammars).get(),
      isEmpty,
    );
  }, tags: ['regression']);
}
