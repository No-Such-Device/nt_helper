import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Real complete AppDatabase, deliberately retained open to keep committed WAL
/// bytes out of the main file until assertions and migration have finished.
class StorageFixture {
  StorageFixture._(this.file, this.raw, this.app);
  final File file;
  final Database raw;
  final AppDatabase app;

  static Future<StorageFixture> create(
    Directory directory, {
    bool oldSchema = false,
  }) async {
    directory.createSync(recursive: true);
    final file = File(p.join(directory.path, LibraryStorage.legacyFileName));
    final raw = sqlite3.open(file.path);
    final app = AppDatabase.forTesting(NativeDatabase.opened(raw));
    await app.select(app.algorithms).get();
    raw.execute('''
BEGIN;
INSERT INTO algorithms VALUES ('test', 'Complete algorithm', 1, '/plugins/test.o');
INSERT INTO algorithm_repeat_grammars VALUES ('test', 1, '{"repeat":2}');
INSERT INTO specifications VALUES ('test', 0, 'Count', 1, 8, 2, 0);
INSERT INTO units VALUES (7, 'Hz');
INSERT INTO parameters VALUES ('test', 0, 'Frequency', -20, 200, 10, 7, 2, 3, 5);
INSERT INTO parameter_enums VALUES ('test', 0, 0, 'First');
INSERT INTO parameter_pages VALUES ('test', 0, 'Main');
INSERT INTO parameter_page_items VALUES ('test', 0, 0);
INSERT INTO parameter_output_mode_usage VALUES ('test', 0, '[1,2]');
INSERT INTO presets (id,name,last_modified,is_template,category,template_metadata) VALUES (42, 'Library preset', 123456, 1, 'Test', '{"author":"Fixture"}');
INSERT INTO preset_slots VALUES (23, 42, 0, 'test', 'Custom slot');
INSERT INTO preset_specification_values VALUES (23, 0, 3);
INSERT INTO preset_parameter_values VALUES (19, 23, 0, 123);
INSERT INTO preset_parameter_string_values VALUES (23, 0, '123 Hz');
INSERT INTO preset_mappings VALUES (23, 0, X'01020304', 2);
INSERT INTO preset_routings VALUES (23, '[1,2,13,0]');
INSERT INTO metadata_cache VALUES ('base', 'non-preset metadata');
INSERT INTO plugin_installations (id,plugin_id,plugin_name,plugin_version,plugin_type,plugin_author,installed_at,installation_path,installation_status,marketplace_metadata,repository_url,file_count,total_bytes,available_version,update_available,last_checked)
VALUES (13, 'plugin', 'Plugin', '1.2', 'cpp', 'Author', 234567, '/plugins', 'completed', '{"extra":true}', 'https://example.test/plugin', 2, 3456, '1.3', 1, 345678);
INSERT INTO units VALUES (777, 'Deleted allocation'); DELETE FROM units WHERE id=777;
INSERT INTO presets (id,name) VALUES (888, 'Deleted allocation'); DELETE FROM presets WHERE id=888;
INSERT INTO preset_slots VALUES (999, 42, 1, 'test', NULL); DELETE FROM preset_slots WHERE id=999;
INSERT INTO preset_parameter_values VALUES (555, 23, 1, 0); DELETE FROM preset_parameter_values WHERE id=555;
INSERT INTO plugin_installations (id,plugin_id,plugin_name,plugin_version,plugin_type,plugin_author,installation_path) VALUES (666,'gone','gone','0','lua','gone','/gone'); DELETE FROM plugin_installations WHERE id=666;
COMMIT;
''');
    if (oldSchema) {
      raw.execute(
        'DROP TABLE algorithm_repeat_grammars; PRAGMA user_version=13',
      );
    }
    raw.execute(
      'PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA wal_checkpoint(TRUNCATE)',
    );
    raw.execute(
      "INSERT INTO metadata_cache VALUES ('wal-only', 'committed WAL sentinel')",
    );
    final fixture = StorageFixture._(file, raw, app);
    fixture.assertWalOnly();
    return fixture;
  }

  void assertWalOnly() {
    if (raw
            .select("SELECT * FROM metadata_cache WHERE cache_key='wal-only'")
            .length !=
        1) {
      throw StateError('WAL sentinel was not committed');
    }
    final copy = File(
      '${file.path}.main-only-${DateTime.now().microsecondsSinceEpoch}',
    );
    file.copySync(copy.path);
    final main = sqlite3.open(copy.path, mode: OpenMode.readOnly);
    try {
      if (main
          .select("SELECT * FROM metadata_cache WHERE cache_key='wal-only'")
          .isNotEmpty) {
        throw StateError('Fixture sentinel is not WAL-only');
      }
    } finally {
      main.close();
      copy.deleteSync();
    }
    if (File('${file.path}-wal').lengthSync() <= 32) {
      throw StateError('Missing WAL evidence');
    }
  }

  void addLateCommit() => raw.execute(
    "INSERT INTO metadata_cache VALUES ('late', 'committed after crash')",
  );
  Future<void> close() => app.close();
}

Future<Map<String, List<String>>> contents(AppDatabase app) async {
  final result = <String, List<String>>{};
  for (final table in app.allTables) {
    final rows = await app
        .customSelect('SELECT * FROM "${table.actualTableName}"')
        .get();
    result[table.actualTableName] =
        rows
            .map(
              (r) => jsonEncode(
                r.data.map(
                  (key, value) => MapEntry(
                    key,
                    value is Uint8List ? base64Encode(value) : value,
                  ),
                ),
              ),
            )
            .toList()
          ..sort();
  }
  result['sqlite_sequence'] =
      (await app
              .customSelect('SELECT * FROM sqlite_sequence ORDER BY name')
              .get())
          .map((r) => jsonEncode(r.data))
          .toList();
  return result;
}
