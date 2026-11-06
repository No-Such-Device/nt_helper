import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory docs;
  late Directory support;
  late Directory app;
  setUp(() {
    resetAppDirectoryForTest();
    root = Directory.systemTemp.createTempSync('nt-open-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Support'))..createSync();
    app = Directory(p.join(support.path, 'nt_helper'))..createSync();
  });
  tearDown(() {
    resetAppDirectoryForTest();
    root.deleteSync(recursive: true);
  });
  StartupStorageOpener opener() => StartupStorageOpener(
    isMacOS: true,
    docsProvider: () async => docs,
    supportProvider: () async => support,
  );

  test(
    'corrupt canonical database reports SQLite error without deletion or stale legacy fallback',
    () async {
      final file = File(p.join(app.path, 'library.sqlite'))
        ..writeAsStringSync('corrupt database');
      final legacy = File(p.join(docs.path, LibraryStorage.legacyFileName))
        ..writeAsStringSync('stale legacy');
      final storage = opener();
      await expectLater(
        storage.open(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'SQLite cause',
            contains('SqliteException(26)'),
          ),
        ),
      );
      expect(storage.location, file.path);
      expect(file.readAsStringSync(), 'corrupt database');
      expect(legacy.readAsStringSync(), 'stale legacy');
    },
  );

  test(
    'newer canonical schema is rejected without changing schema or rows',
    () async {
      final file = File(p.join(app.path, 'library.sqlite'));
      final appDb = AppDatabase.atFile(file);
      await appDb.customStatement(
        "INSERT INTO metadata_cache VALUES ('future', 'keep')",
      );
      await appDb.customStatement('PRAGMA user_version=999');
      await appDb.close();
      await expectLater(
        opener().open(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'schema rejection',
            contains('schema 999 is newer'),
          ),
        ),
      );
      final raw = sqlite3.open(file.path);
      try {
        expect(raw.select('PRAGMA user_version').single.values.single, 999);
        expect(
          raw
              .select('SELECT cache_value FROM metadata_cache')
              .single
              .values
              .single,
          'keep',
        );
      } finally {
        raw.close();
      }
    },
  );

  test('busy canonical database is retryable without resetting data', () async {
    final ready = await opener().open();
    await ready.database.customStatement(
      "INSERT INTO metadata_cache VALUES ('busy', 'keep')",
    );
    final file = ready.location!;
    await ready.database.close();
    final raw = sqlite3.open(file);
    raw.execute('BEGIN EXCLUSIVE');
    try {
      await expectLater(
        opener().open(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'SQLite busy cause',
            contains('SqliteException(5)'),
          ),
        ),
      );
    } finally {
      raw.execute('ROLLBACK');
      raw.close();
    }
    final retried = await opener().open();
    try {
      expect(
        (await retried.database
                .select(retried.database.metadataCache)
                .getSingle())
            .cacheValue,
        'keep',
      );
    } finally {
      await retried.database.close();
    }
  });

  test(
    'legacy folder access cancellation retains files and granted access is released before admission',
    () async {
      final old = File(p.join(docs.path, LibraryStorage.legacyFileName));
      final db = AppDatabase.atFile(old);
      await db.customStatement(
        "INSERT INTO metadata_cache VALUES ('legacy', 'keep')",
      );
      await db.close();
      var cancel = true;
      var releases = 0;
      final storage = StartupStorageOpener(
        isMacOS: true,
        docsProvider: () async => docs,
        supportProvider: () async => support,
        requestAccess: (path) async {
          expect(path, docs.path);
          if (cancel) return false;
          expect((await Process.run('chmod', ['700', docs.path])).exitCode, 0);
          return true;
        },
        releaseAccess: () async {
          releases++;
        },
      );
      await Process.run('chmod', ['000', docs.path]);
      try {
        await expectLater(
          storage.open(),
          throwsA(isA<LibraryImportException>()),
        );
        expect(storage.legacyAccessDirectory, docs.path);
        await expectLater(
          storage.open(selectLegacyDirectory: true),
          throwsA(
            isA<LibraryImportException>().having(
              (e) => e.toString(),
              'cancelled',
              contains('cancelled'),
            ),
          ),
        );
        expect(releases, 1);
        cancel = false;
        final granted = await storage.open(selectLegacyDirectory: true);
        try {
          expect(releases, 2);
          expect(
            (await granted.database
                    .select(granted.database.metadataCache)
                    .getSingle())
                .cacheKey,
            'legacy',
          );
          expect(old.existsSync(), isTrue);
        } finally {
          await granted.database.close();
        }
      } finally {
        await Process.run('chmod', ['700', docs.path]);
      }
    },
    skip: !Platform.isMacOS,
  );
}
