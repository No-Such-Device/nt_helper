import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:nt_helper/services/macos_library_storage.dart';
import 'package:nt_helper/services/macos_storage_io.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;

import '../support/storage_fixture.dart';

void main() {
  if (!Platform.isMacOS) {
    test('macOS storage boundary', () {}, skip: 'Darwin storage primitives');
    return;
  }
  late Directory root;
  late Directory docs;
  late Directory support;
  late Directory appDir;
  final fixtures = <StorageFixture>[];

  setUp(() {
    resetAppDirectoryForTest();
    root = Directory.systemTemp.createTempSync('nt-storage-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Support'))..createSync();
    appDir = Directory(p.join(support.path, 'nt_helper'));
  });
  tearDown(() async {
    for (final fixture in fixtures) {
      await fixture.close();
    }
    fixtures.clear();
    resetAppDirectoryForTest();
    root.deleteSync(recursive: true);
  });

  Future<StorageFixture> fixture(
    Directory location, {
    bool oldSchema = false,
  }) async {
    final value = await StorageFixture.create(location, oldSchema: oldSchema);
    fixtures.add(value);
    return value;
  }

  Future<SelectedLibrary> prepare({
    StorageCheckpoint? checkpoint,
    Future<Directory> Function()? documents,
  }) => MacosLibraryStorage(
    directory: appDir,
    documentsProvider: documents ?? () async => docs,
    checkpoint: checkpoint,
  ).prepare();
  Future<void> assertComplete(
    SelectedLibrary selected,
    Map<String, List<String>> expected,
  ) async {
    final app = await selected.open();
    try {
      expect(await contents(app), expected);
    } finally {
      await app.close();
    }
  }

  test(
    'true absence initializes one usable selected database and reopens without Documents',
    () async {
      final selected = await prepare();
      final app = await selected.open();
      expect(await app.select(app.presets).get(), isEmpty);
      await app.customStatement(
        "INSERT INTO metadata_cache VALUES ('destination', 'new edits')",
      );
      await app.close();
      final reopened = await prepare(
        documents: () async =>
            throw StateError('Documents must not be consulted'),
      );
      expect(reopened.file.path, selected.file.path);
      final db = await reopened.open();
      expect(
        (await db.select(db.metadataCache).getSingle()).cacheKey,
        'destination',
      );
      await db.close();
    },
  );

  for (final operation in [
    'BEGIN; SELECT * FROM metadata_cache; COMMIT',
    'BEGIN; SELECT * FROM metadata_cache; ROLLBACK',
    "BEGIN; INSERT INTO metadata_cache VALUES ('rollback', 'edit'); ROLLBACK",
    'VACUUM',
  ]) {
    test(
      'selected library survives normal SQLite operation: $operation',
      () async {
        final selected = await prepare();
        final raw = selected.openRaw();
        try {
          raw.execute(operation);
        } finally {
          raw.close();
        }
        await prepare(
          documents: () async => throw StateError('no legacy access'),
        );
      },
    );
  }

  test(
    'valid saved database opens after file identity changes without consulting Documents',
    () async {
      final selected = await prepare();
      final saved = await selected.open();
      await saved.customStatement(
        "INSERT INTO metadata_cache VALUES ('saved-before-restart', 'keep this')",
      );
      await saved.close();
      final original = selected.file.renameSync(
        '${selected.file.path}.retained',
      );
      original.copySync(selected.file.path);
      expect(
        MacosStorageIo.identity(selected.file.path),
        isNot(selected.identity),
      );
      final reopened = await prepare(
        documents: () async => throw StateError('no legacy access'),
        checkpoint: (point) async {
          if (point.contains('inspect-selected')) {
            throw StateError(
              'A successful open must not enter failure inspection',
            );
          }
        },
      );
      expect(reopened.file.path, selected.file.path);
      final app = await reopened.open();
      await app.customStatement(
        "INSERT INTO metadata_cache VALUES ('changed-file', 'kept')",
      );
      await app.close();
      final again = await (await prepare()).open();
      expect(
        (await again.select(again.metadataCache).get()).map(
          (row) => row.cacheKey,
        ),
        containsAll(['saved-before-restart', 'changed-file']),
      );
      await again.close();
    },
  );

  test(
    'diagnostic inventory errors do not replace the original SQLite failure',
    () async {
      final selected = await prepare();
      final saved = selected.file.renameSync('${selected.file.path}.retained');
      Link('${selected.file.path}-wal').createSync(saved.path);
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>()
              .having(
                (e) => e.kind,
                'original failure kind',
                StorageFailureKind.access,
              )
              .having(
                (e) => e.cause.toString(),
                'original SQLite failure',
                contains('SqliteException'),
              )
              .having(
                (e) => e.diagnostics,
                'missing database',
                contains('Observed identity: missing'),
              )
              .having(
                (e) => e.diagnostics,
                'failed diagnostic',
                contains('Could not inspect:'),
              ),
        ),
      );
      expect(selected.file.existsSync(), isFalse);
      expect(saved.existsSync(), isTrue);
    },
  );

  test(
    'recovery successor reopens after an earlier valid file replacement',
    () async {
      await fixture(docs);
      final selected = await prepare();
      final app = await selected.open();
      final expected = await contents(app);
      await app.close();
      final saved = selected.file.renameSync('${selected.file.path}.retained');
      saved.copySync(selected.file.path);
      damageLibrary(selected.file, repairable: true);
      final repaired = await prepare(
        documents: () async => throw StateError('no legacy access'),
      );
      expect(repaired.recovery, LibraryRecovery.repaired);
      expect(repaired.file.path, isNot(selected.file.path));
      final reopened = await prepare(
        documents: () async => throw StateError('no legacy access'),
      );
      expect(reopened.file.path, repaired.file.path);
      await assertComplete(reopened, expected);
    },
  );

  for (final row in ['R', 'D', 'D marker', 'R+D', 'A', 'A+R+D']) {
    test(
      'automatic inventory $row opens complete records, keys, relationships, sequences and WAL exactly once',
      () async {
        final locations = <Directory>[];
        if (row.contains('R')) locations.add(docs);
        if (row.contains('D')) {
          locations.add(Directory(p.join(docs.path, 'nt_helper')));
        }
        if (row.contains('A')) locations.add(appDir);
        final values = <StorageFixture>[];
        for (final location in locations) {
          values.add(await fixture(location));
        }
        if (row.contains('marker')) {
          File(
            p.join(locations.first.path, '.migrated'),
          ).writeAsStringSync('old');
        }
        final expected = await contents(values.first.app);
        final originalBytes = {
          for (final value in values)
            value.file.path: File('${value.file.path}-wal').readAsBytesSync(),
        };
        final selected = await prepare();
        await assertComplete(selected, expected);
        for (final source in values) {
          expect(source.file.existsSync(), isTrue);
          final retained = appDir
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) => f.path.contains('original-') && f.path.endsWith('-wal'),
              );
          expect(
            retained.any(
              (f) =>
                  base64Encode(f.readAsBytesSync()) ==
                  base64Encode(originalBytes[source.file.path]!),
            ),
            isTrue,
          );
          source.raw.execute(
            'BEGIN IMMEDIATE; ROLLBACK',
          ); // Exclusion released.
        }
        final again = await prepare(
          documents: () async => throw StateError('no legacy dependency'),
        );
        await assertComplete(again, expected);
        expect(again.file.path, selected.file.path);
      },
    );
  }

  test(
    'supported v13 upgrades use AppDatabase schema ownership and preserve data',
    () async {
      final source = await fixture(docs, oldSchema: true);
      final selected = await prepare();
      final db = await selected.open();
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        14,
      );
      expect(await db.select(db.algorithmRepeatGrammars).get(), isEmpty);
      expect(
        (await db.select(db.presetSpecificationValues).getSingle()).value,
        3,
      );
      expect(
        (await db.select(db.metadataCache).get()).map((r) => r.cacheKey),
        contains('wal-only'),
      );
      expect(source.raw.select('PRAGMA user_version').first.values.single, 13);
      await db.close();
    },
  );

  test(
    'held source writer blocks then Retry includes last commit, never uncommitted data',
    () async {
      final source = await fixture(docs);
      source.raw.execute(
        "BEGIN IMMEDIATE; INSERT INTO metadata_cache VALUES ('uncommitted', 'not admitted')",
      );
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.kind,
            'kind',
            StorageFailureKind.busy,
          ),
        ),
      );
      source.raw.execute('ROLLBACK');
      source.addLateCommit();
      await assertComplete(await prepare(), await contents(source.app));
      final opened = await (await prepare()).open();
      expect(
        (await opened.select(opened.metadataCache).get()).any(
          (r) => r.cacheKey == 'uncommitted',
        ),
        isFalse,
      );
      await opened.close();
    },
  );

  test(
    'preselection interruption recaptures changed unique source and retains failed work',
    () async {
      final source = await fixture(docs);
      await expectLater(
        prepare(
          checkpoint: (point) async {
            if (point == 'before:selection') {
              throw const FileSystemException(
                'injected disk full',
                '',
                OSError('full', 28),
              );
            }
          },
        ),
        throwsA(isA<StorageFailure>()),
      );
      final retained = appDir
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toSet();
      source.addLateCommit();
      await assertComplete(await prepare(), await contents(source.app));
      expect(retained.every((path) => File(path).existsSync()), isTrue);
    },
  );

  test(
    'failed SQLite open reports missing or invalid selected files without creating a replacement',
    () async {
      await fixture(docs);
      final selected = await prepare();
      final saved = selected.file.renameSync('${selected.file.path}.retained');
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>()
              .having(
                (e) => e.diagnostics,
                'report',
                contains(selected.file.path),
              )
              .having(
                (e) => e.cause.toString(),
                'SQLite error',
                contains('SqliteException'),
              ),
        ),
      );
      expect(selected.file.existsSync(), isFalse);
      File(selected.file.path).writeAsStringSync('replacement');
      await expectLater(prepare(), throwsA(isA<StorageFailure>()));
      File(selected.file.path).renameSync('${selected.file.path}.unknown');
      saved.renameSync(selected.file.path);
      final db = await (await prepare()).open();
      expect((await db.select(db.presets).getSingle()).id, 42);
      await db.close();
      final journal = File('${selected.file.path}-journal');
      final retained = journal.renameSync('${journal.path}.retained');
      final reopened = await prepare();
      expect(reopened.file.path, selected.file.path);
      final writable = await reopened.open();
      await writable.customStatement(
        "INSERT INTO metadata_cache VALUES ('journal-recreated', 'new edit')",
      );
      await writable.close();
      expect(journal.existsSync(), isTrue);
      expect(retained.existsSync(), isTrue);
      expect(
        MacosStorageIo.identity(journal.path),
        isNot(selected.journalIdentity),
      );
      await prepare();
    },
  );

  test(
    'ordinary getAppDirectory, integrity and lazy AppDatabase share the selected identity',
    () async {
      final source = await fixture(docs);
      final expected = await contents(source.app);
      final dirs = await Future.wait(
        List.generate(
          5,
          (_) => getAppDirectory(
            docsProvider: () async => docs,
            supportProvider: () async => support,
            isMacOS: true,
          ),
        ),
      );
      expect(dirs.map((d) => d.path).toSet(), {appDir.path});
      expect(
        (await DatabaseIntegrityService.getDatabaseFile()).path,
        selectedLibrary!.file.path,
      );
      expect(
        (await DatabaseIntegrityService.checkIntegrity()).isCorrupt,
        isFalse,
      );
      final ordinary = AppDatabase();
      expect(await contents(ordinary), expected);
      await ordinary.close();
    },
  );

  for (final scenario in [
    'unequal',
    'subset',
    'empty A',
    'partial A',
    'orphan WAL',
    'missing WAL',
    'directory',
    'symlink',
    'malformed authority',
    'unsupported schema',
  ]) {
    test(
      'uncertain inventory $scenario blocks with retained artifacts',
      () async {
        await fixture(docs);
        switch (scenario) {
          case 'unequal':
          case 'subset':
            final other = await fixture(
              Directory(p.join(docs.path, 'nt_helper')),
            );
            other.raw.execute(
              scenario == 'subset'
                  ? "DELETE FROM metadata_cache WHERE cache_key='base'"
                  : "UPDATE presets SET name='Different'",
            );
          case 'empty A':
            appDir.createSync();
            File(p.join(appDir.path, libraryFileName)).createSync();
          case 'partial A':
            appDir.createSync();
            File(
              p.join(appDir.path, libraryFileName),
            ).writeAsStringSync('partial');
          case 'orphan WAL':
            appDir.createSync();
            File(
              p.join(appDir.path, '$libraryFileName-wal'),
            ).writeAsStringSync('unknown');
          case 'missing WAL':
            appDir.createSync();
            File(
              p.join(appDir.path, libraryFileName),
            ).writeAsStringSync('unknown');
            File(
              p.join(appDir.path, '$libraryFileName-shm'),
            ).writeAsStringSync('unknown');
          case 'directory':
            Directory(
              p.join(appDir.path, libraryFileName),
            ).createSync(recursive: true);
          case 'symlink':
            appDir.createSync();
            Link(
              p.join(appDir.path, libraryFileName),
            ).createSync(p.join(docs.path, libraryFileName));
          case 'malformed authority':
            Directory(
              p.join(appDir.path, '.storage-v1'),
            ).createSync(recursive: true);
            File(
              p.join(appDir.path, '.storage-v1', 'selected.json'),
            ).writeAsStringSync('{broken');
          case 'unsupported schema':
            final other = await fixture(appDir);
            other.raw.execute('PRAGMA user_version=999');
        }
        final originals = {
          for (final file
              in root
                  .listSync(recursive: true, followLinks: false)
                  .whereType<File>())
            file.path: file.readAsBytesSync(),
        };
        await expectLater(prepare(), throwsA(isA<StorageFailure>()));
        expect(
          File(
            p.join(appDir.path, '.storage-v1', 'selected.json'),
          ).existsSync(),
          scenario == 'malformed authority',
        );
        for (final path in originals.keys) {
          expect(File(path).existsSync(), isTrue);
          // SQLite may touch originals, but an untouched retained capture must
          // exist for every pre-opening main/WAL/journal byte stream.
          if (path.endsWith('-shm')) continue;
          final bytes = base64Encode(originals[path]!);
          expect(
            base64Encode(File(path).readAsBytesSync()) == bytes ||
                appDir
                    .listSync(recursive: true)
                    .whereType<File>()
                    .any((f) => base64Encode(f.readAsBytesSync()) == bytes),
            isTrue,
            reason: path,
          );
        }
      },
    );
  }

  test(
    'simulated native and access failures retain authority and Retry succeeds',
    () async {
      final source = await fixture(docs);
      final expected = await contents(source.app);
      for (final failure in [
        const FileSystemException(
          'simulated access denial',
          '',
          OSError('denied', 13),
        ),
        ArgumentError("simulated couldn't resolve native function libsqlite3"),
      ]) {
        await expectLater(
          prepare(
            checkpoint: (point) async {
              if (point == 'before:open') throw failure;
            },
          ),
          throwsA(
            isA<StorageFailure>().having(
              (e) => e.kind,
              'non-corruption kind',
              failure is FileSystemException
                  ? StorageFailureKind.access
                  : StorageFailureKind.native,
            ),
          ),
        );
        await assertComplete(
          await prepare(
            documents: () async => throw StateError('no legacy fallback'),
          ),
          expected,
        );
      }
    },
  );

  test(
    'disposable competitor access denial is not mistaken for absence',
    () async {
      await fixture(docs);
      final competitor = Directory(p.join(docs.path, 'nt_helper'))
        ..createSync();
      expect(
        (await Process.run('chmod', ['000', competitor.path])).exitCode,
        0,
      );
      try {
        await expectLater(
          prepare(),
          throwsA(
            isA<StorageFailure>().having(
              (e) => e.kind,
              'kind',
              StorageFailureKind.access,
            ),
          ),
        );
        expect(
          File(
            p.join(appDir.path, '.storage-v1', 'selected.json'),
          ).existsSync(),
          isFalse,
        );
      } finally {
        await Process.run('chmod', ['700', competitor.path]);
      }
      await prepare();
    },
  );

  test(
    'independent replacement after an owned interruption remains blocked',
    () async {
      final old = await fixture(docs);
      await expectLater(
        prepare(
          checkpoint: (point) async {
            if (point == 'after:work') throw StateError('interrupted');
          },
        ),
        throwsA(isA<StorageFailure>()),
      );
      // Preserve the old inode; create a genuinely independent source identity.
      await old.close();
      fixtures.remove(old);
      old.file.renameSync('${old.file.path}.retained');
      await fixture(docs);
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.message,
            'specific reason',
            contains('independent library'),
          ),
        ),
      );
    },
  );

  for (final point in ['after:reservation', 'before:exclude-0']) {
    test(
      'checkpointed WAL removal after $point automatically retries without losing retained work',
      () async {
        final source = await fixture(docs);
        final expected = await contents(source.app);
        final wal = File('${source.file.path}-wal');
        final checkpoint = source.raw
            .select('PRAGMA wal_checkpoint(FULL)')
            .single;
        expect(checkpoint['busy'], 0);
        expect(checkpoint['log'], greaterThan(0));
        expect(checkpoint['checkpointed'], checkpoint['log']);
        expect(wal.lengthSync(), greaterThan(32));
        final mainBefore = source.file.readAsBytesSync();
        final walBefore = wal.readAsBytesSync();
        await expectLater(
          prepare(
            checkpoint: (boundary) async {
              if (boundary == point) {
                throw StateError('pre-exclusion interruption');
              }
            },
          ),
          throwsA(isA<StorageFailure>()),
        );
        final retained = {
          for (final file in appDir.listSync(recursive: true).whereType<File>())
            file.path: file.readAsBytesSync(),
        };
        expect(wal.readAsBytesSync(), walBefore);
        await source.close();
        fixtures.remove(source);
        expect(wal.existsSync(), isFalse);
        expect(source.file.readAsBytesSync(), mainBefore);
        await assertComplete(await prepare(), expected);
        for (final entry in retained.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
      },
    );
  }

  test(
    'missing previously observed WAL cannot silently admit an incomplete main file',
    () async {
      final source = await fixture(docs);
      final mainBefore = source.file.readAsBytesSync();
      await expectLater(
        prepare(
          checkpoint: (point) async {
            if (point == 'before:exclude-0') {
              throw StateError('interrupted before source opening');
            }
          },
        ),
        throwsA(isA<StorageFailure>()),
      );
      await source.close();
      fixtures.remove(source);
      final checkpointed = source.file.readAsBytesSync();
      // Model lost indispensable recovery data without replacing the source inode.
      source.file.writeAsBytesSync(mainBefore);
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.message,
            'reason',
            contains('WAL recovery data is missing'),
          ),
        ),
      );
      source.file.writeAsBytesSync(checkpointed);
      final opened = await (await prepare()).open();
      expect(
        (await opened.select(opened.metadataCache).get()).map(
          (r) => r.cacheKey,
        ),
        contains('wal-only'),
      );
      await opened.close();
    },
  );

  test(
    'unexplained work is never replaced or treated as owned initialization',
    () async {
      final unknown = Directory(
        p.join(appDir.path, '.storage-v1', 'work-unknown'),
      )..createSync(recursive: true);
      final bytes = File(p.join(unknown.path, libraryFileName))
        ..writeAsStringSync('retained unknown work');
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.message,
            'reason',
            contains('Unexplained migration work'),
          ),
        ),
      );
      expect(bytes.readAsStringSync(), 'retained unknown work');
    },
  );

  test('copied authority cannot confer migration ownership', () async {
    await fixture(docs);
    final selected = await prepare();
    final record = File(p.join(appDir.path, '.storage-v1', 'selected.json'));
    final original = record.renameSync('${record.path}.retained');
    original.copySync(record.path);
    await expectLater(
      prepare(),
      throwsA(
        isA<StorageFailure>().having(
          (e) => e.toString(),
          'specific reason',
          contains('witness'),
        ),
      ),
    );
    record.renameSync('${record.path}.unknown');
    original.renameSync(record.path);
    expect((await prepare()).file.path, selected.file.path);
  });

  test(
    'in-process selection contention is busy, settles, and then uses one authority',
    () async {
      await fixture(docs);
      final held = Completer<void>();
      final release = Completer<void>();
      final first = prepare(
        checkpoint: (point) async {
          if (point == 'before:selection') {
            held.complete();
            await release.future;
          }
        },
      );
      await held.future;
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.kind,
            'kind',
            StorageFailureKind.busy,
          ),
        ),
      );
      release.complete();
      final selected = await first;
      expect((await prepare()).file.path, selected.file.path);
    },
  );

  test(
    'Darwin inode identity distinguishes replacement and rejects unsupported entities',
    () {
      final file = File(p.join(root.path, 'identity'))
        ..writeAsStringSync('same');
      final id = MacosStorageIo.identity(file.path);
      expect(id, startsWith('32768:'));
      expect(MacosStorageIo.identity(root.path), startsWith('16384:'));
      final reader = MacosStorageIo.openRead(file.path);
      try {
        expect(reader.read(), utf8.encode('same'));
      } finally {
        reader.close();
      }
      file.writeAsStringSync('a larger ordinary edit');
      expect(MacosStorageIo.identity(file.path), id);
      file.renameSync('${file.path}.retained');
      File(file.path).writeAsStringSync('same');
      expect(MacosStorageIo.identity(file.path), isNot(id));
      expect(MacosStorageIo.identity(p.join(root.path, 'absent')), isNull);
      final reserved = p.join(root.path, 'reserved');
      MacosStorageIo.reserveDirectory(reserved);
      final unknown = File(p.join(reserved, 'unknown'))
        ..writeAsStringSync('retain');
      expect(
        () => MacosStorageIo.reserveDirectory(reserved),
        throwsA(isA<FileSystemException>()),
      );
      expect(unknown.readAsStringSync(), 'retain');
    },
  );
}
