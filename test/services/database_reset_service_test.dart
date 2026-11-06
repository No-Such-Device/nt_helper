import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/database_reset_service.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('nt-reset-');
    SharedPreferences.setMockInitialValues({'keep-until-reset': true});
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'reset clears related rows with foreign keys enabled, keeps the file and never reimports legacy rows',
    () async {
      final legacy = await StorageFixture.create(
        Directory(p.join(root.path, 'Documents')),
      );
      addTearDown(legacy.close);
      final storage = LibraryStorage(
        directory: Directory(p.join(root.path, 'Support')),
        documentsProvider: () async => legacy.file.parent,
      );
      final file = await storage.prepare();
      final app = AppDatabase.forTesting(NativeDatabase(file));
      await app.select(app.algorithms).get();
      await app.customStatement('PRAGMA foreign_keys=ON');
      expect(
        (await app.select(app.presets).getSingle()).name,
        'Library preset',
      );
      await DatabaseResetService.resetAll(app);
      for (final table in app.allTables) {
        expect(
          await app.select(table).get(),
          isEmpty,
          reason: table.actualTableName,
        );
      }
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await app.close();
      expect(file.existsSync(), isTrue);
      expect(legacy.file.existsSync(), isTrue);
      final reopenedFile = await LibraryStorage(
        directory: storage.directory,
        documentsProvider: () async => throw StateError('must not reimport'),
      ).prepare();
      final reopened = AppDatabase.atFile(reopenedFile);
      try {
        expect(await reopened.select(reopened.presets).get(), isEmpty);
        expect(
          (await reopened.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          reopened.schemaVersion,
        );
      } finally {
        await reopened.close();
      }
    },
    tags: ['regression'],
  );

  test(
    'failed reset rolls back earlier table deletes and leaves preferences intact',
    () async {
      final source = await StorageFixture.create(root);
      try {
        final expected = await contents(source.app);
        source.raw.execute(
          "CREATE TRIGGER block_reset BEFORE DELETE ON metadata_cache BEGIN SELECT RAISE(ABORT, 'reset blocked'); END",
        );
        await expectLater(
          DatabaseResetService.resetAll(source.app),
          throwsA(isA<SqliteException>()),
        );
        expect(await contents(source.app), expected);
        expect(
          (await SharedPreferences.getInstance()).getBool('keep-until-reset'),
          isTrue,
        );
        expect(source.file.existsSync(), isTrue);
      } finally {
        await source.close();
      }
    },
    tags: ['regression'],
  );
}
