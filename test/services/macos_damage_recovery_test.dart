import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:nt_helper/services/macos_library_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/storage_fixture.dart';

void main() {
  if (!Platform.isMacOS) {
    
    return;
  }
  late Directory root;
  late Directory docs;
  late Directory appDir;
  setUp(() {
    root = Directory.systemTemp.createTempSync('nt-damage-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    appDir = Directory(p.join(root.path, 'Support', 'nt_helper'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<SelectedLibrary> prepare({
    StorageCheckpoint? checkpoint,
    bool selected = false,
  }) => MacosLibraryStorage(
    directory: appDir,
    documentsProvider: selected
        ? () async => throw StateError('No Documents access after selection')
        : () async => docs,
    checkpoint: checkpoint,
  ).prepare();

  Future<File> damaged({bool repairable = false, Directory? location}) async {
    final fixture = await StorageFixture.create(location ?? docs);
    await fixture.close();
    damageLibrary(fixture.file, repairable: repairable);
    return fixture.file;
  }

  void assertRetained(Map<String, List<int>> originals) {
    final files = appDir.listSync(recursive: true).whereType<File>().toList();
    for (final entry in originals.entries) {
      expect(File(entry.key).readAsBytesSync(), entry.value, reason: entry.key);
      expect(
        files.any(
          (f) =>
              f.path.contains('original-0') &&
              listEquals(f.readAsBytesSync(), entry.value),
        ),
        isTrue,
        reason: 'Untouched retained capture of ${entry.key}',
      );
    }
  }

  for (final repairable in [false, true]) {
    for (final row in ['R', 'D', 'A', 'selected']) {
      test(
        '$row real damage ${repairable ? 'repairs complete semantics' : 'fails repair and selects one fresh store'}',
        () async {
          final location = row == 'D'
              ? Directory(p.join(docs.path, 'nt_helper'))
              : row == 'A'
              ? appDir
              : docs;
          final fixture = await StorageFixture.create(location);
          final expected = await contents(fixture.app);
          await fixture.close();
          final source = row == 'selected'
              ? (await prepare()).file
              : fixture.file;
          damageLibrary(source, repairable: repairable);
          final original = storageBytes(source);
          final check = sqlite3.open(source.path, mode: OpenMode.readOnly);
          try {
            try {
              expect(DatabaseIntegrityService.inspect(check), isNotNull);
            } on SqliteException catch (error) {
              expect(
                DatabaseIntegrityService.isDatabaseCorruptionError(error),
                isTrue,
              );
            }
          } finally {
            check.close();
          }
          final selected = await prepare(selected: row == 'selected');
          expect(selected.file.path, isNot(source.path));
          expect(
            selected.recovery,
            repairable
                ? LibraryRecovery.repaired
                : LibraryRecovery.freshAfterDamage,
          );
          final db = await selected.open();
          if (repairable) {
            expect(await contents(db), expected);
            expect(
              await db
                  .customSelect('PRAGMA integrity_check')
                  .get()
                  .then((r) => r.single.data.values.single),
              'ok',
            );
          } else {
            expect(
              (await contents(db)).values.every((rows) => rows.isEmpty),
              isTrue,
            );
          }
          await db.customStatement(
            "INSERT INTO metadata_cache VALUES ('destination-only', 'later edit')",
          );
          await db.close();
          assertRetained(original);
          for (var retry = 0; retry < 2; retry++) {
            final again = await prepare(selected: true);
            expect(again.file.path, selected.file.path);
            expect(again.recovery, selected.recovery);
            final opened = await again.open();
            expect(
              (await opened
                      .customSelect(
                        "SELECT * FROM metadata_cache WHERE cache_key='destination-only'",
                      )
                      .get())
                  .length,
              1,
            );
            await opened.close();
          }
        },
      , tags: ['regression']);
    }
  }

  for (final repairable in [false, true]) {
    test(
      'damaged WAL library retains untouched main and recovery files (${repairable ? 'repaired' : 'fresh'})',
      () async {
        final source = await damaged(repairable: repairable);
        final writer = sqlite3.open(source.path, mode: OpenMode.readWrite);
        try {
          writer.execute(
            "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; INSERT INTO units VALUES (909, 'WAL-only damage sentinel')",
          );
          final originals = storageBytes(source);
          expect(originals['${source.path}-wal']!.length, greaterThan(32));
          final selected = await prepare();
          expect(
            selected.recovery,
            repairable
                ? LibraryRecovery.repaired
                : LibraryRecovery.freshAfterDamage,
          );
          final db = await selected.open();
          expect(
            (await db.customSelect('SELECT * FROM units WHERE id=909').get())
                .length,
            repairable ? 1 : 0,
          );
          await db.close();
          final captures = appDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.contains('original-0'))
              .toList();
          for (final entry in originals.entries) {
            expect(
              captures.any((f) => listEquals(f.readAsBytesSync(), entry.value)),
              isTrue,
              reason: entry.key,
            );
          }
        } finally {
          writer.close();
        }
      },
    , tags: ['regression']);
  }

  test(
    'repair uses supported AppDatabase upgrades without changing old schema originals',
    () async {
      final fixture = await StorageFixture.create(docs, oldSchema: true);
      await fixture.close();
      damageLibrary(fixture.file, repairable: true);
      final originals = storageBytes(fixture.file);
      final selected = await prepare();
      expect(selected.recovery, LibraryRecovery.repaired);
      final app = await selected.open();
      expect(
        (await app.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        14,
      );
      expect((await app.select(app.presets).getSingle()).id, 42);
      expect(await app.select(app.algorithmRepeatGrammars).get(), isEmpty);
      await app.close();
      assertRetained(originals);
    },
  , tags: ['regression']);

  test(
    'confirmed damage with duplicate unique keys cannot be reported repaired',
    () async {
      final file = await damaged(repairable: true);
      final raw = sqlite3.open(file.path, mode: OpenMode.readWrite);
      raw.execute(
        "PRAGMA journal_mode=PERSIST; INSERT INTO metadata_cache VALUES ('unique-one', 'first'), ('unique-two', 'second')",
      );
      final page =
          raw
                  .select(
                    "SELECT rootpage FROM sqlite_schema WHERE name='metadata_cache'",
                  )
                  .single['rootpage']
              as int;
      final size = raw.select('PRAGMA page_size').single.values.single as int;
      raw.close();
      final bytes = file.readAsBytesSync();
      final start = (page - 1) * size;
      final index = String.fromCharCodes(
        bytes.sublist(start, start + size),
      ).indexOf('unique-two');
      expect(index, greaterThanOrEqualTo(0));
      bytes.setRange(start + index, start + index + 10, 'unique-one'.codeUnits);
      file.writeAsBytesSync(bytes, flush: true);
      final originals = storageBytes(file);
      final selected = await prepare();
      expect(selected.recovery, LibraryRecovery.freshAfterDamage);
      final db = await selected.open();
      expect(await db.select(db.metadataCache).get(), isEmpty);
      await db.close();
      assertRetained(originals);
    },
  , tags: ['regression']);

  for (final scenario in [
    'competing',
    'unknown work',
    'unsupported',
    'partial schema',
    'busy',
    'preservation',
    'inspection',
    'native',
    'repair I/O',
    'repair denial',
  ]) {
    test('$scenario never authorizes fresh selection', () async {
      final source = await damaged(repairable: true);
      StorageCheckpoint? checkpoint;
      Database? writer;
      switch (scenario) {
        case 'competing':
          final other = await StorageFixture.create(appDir);
          await other.close();
        case 'unknown work':
          Directory(
            p.join(appDir.path, '.storage-v1', 'work-unknown'),
          ).createSync(recursive: true);
        case 'unsupported':
        case 'partial schema':
          final raw = sqlite3.open(source.path, mode: OpenMode.readWrite);
          raw.execute('PRAGMA journal_mode=PERSIST');
          raw.execute(
            scenario == 'unsupported'
                ? 'PRAGMA user_version=999'
                : 'DROP TABLE preset_mappings',
          );
          raw.close();
        case 'busy':
          writer = sqlite3.open(source.path, mode: OpenMode.readWrite);
          writer.execute('PRAGMA journal_mode=PERSIST; BEGIN IMMEDIATE');
        default:
          final boundary = switch (scenario) {
            'preservation' => 'before:retain-0',
            'inspection' || 'native' => 'before:inspect-0',
            _ => 'before:reindex',
          };
          checkpoint = (point) async {
            if (point == boundary) {
              if (scenario == 'native') {
                throw ArgumentError('SQLite unavailable');
              }
              throw SqliteException(
                extendedResultCode: scenario == 'repair denial' ? 14 : 10,
                message: 'simulated external inspection/repair failure',
              );
            }
          };
      }
      final originals = storageBytes(source);
      try {
        await expectLater(
          prepare(checkpoint: checkpoint),
          throwsA(isA<StorageFailure>()),
        );
        expect(
          File(
            p.join(appDir.path, '.storage-v1', 'selected.json'),
          ).existsSync(),
          isFalse,
        );
        for (final entry in originals.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
      } finally {
        writer?.close();
      }
      if (![
        'competing',
        'unknown work',
        'unsupported',
        'partial schema',
      ].contains(scenario)) {
        expect((await prepare()).recovery, LibraryRecovery.repaired);
      }
    }, tags: ['regression']);
  }

  test(
    'sole unknown partial file is uncertainty, not damage authority',
    () async {
      final file = File(p.join(docs.path, libraryFileName))
        ..writeAsStringSync('partial unknown copy');
      await expectLater(
        prepare(),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.kind,
            'kind',
            StorageFailureKind.uncertain,
          ),
        ),
      );
      expect(file.readAsStringSync(), 'partial unknown copy');
      expect(
        File(p.join(appDir.path, '.storage-v1', 'selected.json')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'damage arising only in uncertain transfer does not authorize reset',
    () async {
      final fixture = await StorageFixture.create(docs);
      await fixture.close();
      await expectLater(
        prepare(
          checkpoint: (point) async {
            if (point == 'before:transfer-0') {
              throw SqliteException(
                extendedResultCode: 11,
                message: 'transfer damage',
              );
            }
          },
        ),
        throwsA(
          isA<StorageFailure>().having(
            (e) => e.kind,
            'kind',
            StorageFailureKind.uncertain,
          ),
        ),
      );
      expect(
        File(p.join(appDir.path, '.storage-v1', 'selected.json')).existsSync(),
        isFalse,
      );
      expect((await prepare()).recovery, isNull);
    },
  , tags: ['regression']);
}
