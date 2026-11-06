import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:path/path.dart' as p;

import '../support/storage_fixture.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory app;
  final fixtures = <StorageFixture>[];
  setUp(() {
    root = Directory.systemTemp.createTempSync('nt-library-import-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    app = Directory(p.join(root.path, 'Support'))..createSync();
  });
  tearDown(() async {
    for (final fixture in fixtures) {
      await fixture.close();
    }
    fixtures.clear();
    root.deleteSync(recursive: true);
  });
  LibraryStorage storage({Future<Directory> Function()? documents}) =>
      LibraryStorage(
        directory: app,
        documentsProvider: documents ?? () async => docs,
      );
  Future<StorageFixture> fixture(
    Directory location, {
    bool oldSchema = false,
  }) async {
    final value = await StorageFixture.create(location, oldSchema: oldSchema);
    fixtures.add(value);
    return value;
  }

  Future<AppDatabase> open(File file) async {
    final database = AppDatabase.forTesting(NativeDatabase(file));
    await database.select(database.algorithms).get();
    addTearDown(database.close);
    return database;
  }

  void selected(
    String attempt, {
    String name = 'selected.json',
    String? relative,
  }) {
    final control = Directory(p.join(app.path, '.storage-v1'))
      ..createSync(recursive: true);
    File(p.join(control.path, name)).writeAsStringSync(
      jsonEncode({
        'body': jsonEncode({
          'attempt': attempt,
          'file':
              relative ??
              p.join('work-$attempt', LibraryStorage.legacyFileName),
        }),
      }),
    );
  }

  const first = '11111111-1111-1111-1111-111111111111';
  const second = '22222222-2222-2222-2222-222222222222';

  test(
    'fresh install creates one usable canonical library and coalesces concurrent import',
    () async {
      final importer = storage();
      final pending = importer.prepare();
      final other = storage().prepare();
      expect(identical(pending, other), isTrue);
      final file = await pending;
      expect(file.path, p.join(app.path, 'library.sqlite'));
      final db = await open(file);
      expect(await db.select(db.presets).get(), isEmpty);
    },
  );

  test(
    'canonical library bypasses denied Documents and malformed historical metadata',
    () async {
      final file = await storage().prepare();
      final db = await open(file);
      await db.customStatement(
        "INSERT INTO metadata_cache VALUES ('canonical', 'keep')",
      );
      final control = Directory(p.join(app.path, '.storage-v1'))..createSync();
      File(p.join(control.path, 'selected.json')).writeAsStringSync('broken');
      final result = await storage(
        documents: () async => throw StateError('no Documents read'),
      ).prepare();
      expect(result.path, file.path);
      expect(
        (await db.select(db.metadataCache).getSingle()).cacheKey,
        'canonical',
      );
    },
  );

  for (final location in [
    'documents',
    'nested documents',
    'support',
    'orphan work',
  ]) {
    test(
      '$location import preserves all rows, sequences and committed WAL-only data',
      () async {
        final directory = switch (location) {
          'documents' => docs,
          'nested documents' => Directory(p.join(docs.path, 'nt_helper')),
          'support' => app,
          _ => Directory(p.join(app.path, '.storage-v1', 'work-$first')),
        };
        final source = await fixture(directory);
        final expected = await contents(source.app);
        final destination = await storage().prepare();
        expect(await contents(await open(destination)), expected);
        expect(source.file.existsSync(), isTrue);
        source.addLateCommit(); // Import does not retain a source write lock.
      },
    );
  }

  test(
    'selected successor imports without identities, receipts or hard-link witnesses',
    () async {
      final older = await fixture(
        Directory(p.join(app.path, '.storage-v1', 'work-$first')),
      );
      final latest = await fixture(
        Directory(p.join(app.path, '.storage-v1', 'work-$second')),
      );
      latest.raw.execute("UPDATE presets SET name='Latest selected library'");
      selected(first);
      selected(second, name: 'selected-$first.json');
      final file = await storage(
        documents: () async => throw StateError('no legacy read'),
      ).prepare();
      expect(await contents(await open(file)), await contents(latest.app));
      expect(older.file.existsSync(), isTrue);
    },
  );

  test('supported old schema is upgraded only on the imported copy', () async {
    final source = await fixture(docs, oldSchema: true);
    final result = await open(await storage().prepare());
    expect(await result.select(result.algorithmRepeatGrammars).get(), isEmpty);
    expect(
      (await result.select(result.presets).getSingle()).name,
      'Library preset',
    );
    expect(source.raw.select('PRAGMA user_version').single.values.single, 13);
  });

  test(
    'missing selected main with surviving journal never resurrects stale Documents data',
    () async {
      await fixture(docs);
      selected(first);
      final work = Directory(p.join(app.path, '.storage-v1', 'work-$first'))
        ..createSync();
      final journal = File(
        p.join(work.path, '${LibraryStorage.legacyFileName}-journal'),
      )..writeAsStringSync('retained journal');
      await expectLater(
        storage().prepare(),
        throwsA(
          isA<LibraryImportException>().having(
            (e) => e.toString(),
            'missing selected main',
            contains('missing'),
          ),
        ),
      );
      expect(storage().file.existsSync(), isFalse);
      final fresh = await storage().prepare(startFresh: true);
      final empty = await open(fresh);
      expect(await empty.select(empty.presets).get(), isEmpty);
      expect(journal.readAsStringSync(), 'retained journal');
      expect(
        File(p.join(docs.path, LibraryStorage.legacyFileName)).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'multiple candidates require a choice and explicit import preserves both sources',
    () async {
      final source = await fixture(docs);
      final other = await fixture(app);
      other.raw.execute("UPDATE presets SET name='Other'");
      await expectLater(
        storage().prepare(),
        throwsA(
          isA<LibraryImportException>().having(
            (e) => e.paths.length,
            'candidate count',
            2,
          ),
        ),
      );
      expect(storage().file.existsSync(), isFalse);
      final result = await storage().prepare(importSource: source.file);
      expect(await contents(await open(result)), await contents(source.app));
      expect(
        (await other.app.select(other.app.presets).getSingle()).name,
        'Other',
      );
    },
  );

  for (final relative in [
    '../outside.sqlite',
    'work-$second/${LibraryStorage.legacyFileName}',
  ]) {
    test(
      'historical hint $relative cannot escape its selected work directory',
      () async {
        selected(first, relative: relative);
        await expectLater(
          storage().prepare(),
          throwsA(isA<LibraryImportException>()),
        );
        expect(storage().file.existsSync(), isFalse);
      },
    );
  }

  test(
    'malformed selection and orphan sidecars require explicit recovery',
    () async {
      final control = Directory(p.join(app.path, '.storage-v1'))..createSync();
      final record = File(p.join(control.path, 'selected.json'))
        ..writeAsStringSync('{');
      await expectLater(
        storage().prepare(),
        throwsA(isA<LibraryImportException>()),
      );
      record.deleteSync();
      File(
        p.join(app.path, '${LibraryStorage.legacyFileName}-wal'),
      ).writeAsStringSync('orphan');
      await expectLater(
        storage().prepare(),
        throwsA(isA<LibraryImportException>()),
      );
      expect(storage().file.existsSync(), isFalse);
    },
  );

  test(
    'failed SQLite import preserves the source and retry discards abandoned temporary work',
    () async {
      final source = File(p.join(docs.path, LibraryStorage.legacyFileName))
        ..writeAsStringSync('not a database');
      await expectLater(
        storage().prepare(),
        throwsA(
          isA<LibraryImportException>().having(
            (e) => e.cause,
            'SQLite cause',
            isA<SqliteException>(),
          ),
        ),
      );
      expect(source.readAsStringSync(), 'not a database');
      expect(storage().file.existsSync(), isFalse);
      source.deleteSync();
      final valid = await fixture(docs);
      final work = Directory(p.join(app.path, '.library-import'))..createSync();
      File(
        p.join(work.path, 'library.sqlite'),
      ).writeAsStringSync('partial abandoned backup');
      final result = await storage().prepare();
      expect(await contents(await open(result)), await contents(valid.app));
      expect(work.existsSync(), isFalse);
    },
  );

  test(
    'Documents access failure propagates rather than initializing an empty library',
    () async {
      const failure = FileSystemException(
        'Documents denied',
        '/Documents',
        OSError('denied', 13),
      );
      await expectLater(
        storage(documents: () async => throw failure).prepare(),
        throwsA(
          isA<LibraryImportException>().having(
            (e) => e.cause,
            'original failure',
            same(failure),
          ),
        ),
      );
      expect(storage().file.existsSync(), isFalse);
    },
  );
}
