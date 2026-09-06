import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/services/database_integrity_service.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _UnavailableDirectory extends Mock implements Directory {}

final class _UnavailableDocuments extends IOOverrides {
  _UnavailableDocuments(this.appPath) {
    when(() => directory.existsSync()).thenReturn(false);
    when(() => directory.createSync(recursive: true)).thenThrow(
      PathNotFoundException(
        appPath,
        const OSError('Path not found', 2),
        'Creation failed',
      ),
    );
  }

  final String appPath;
  final directory = _UnavailableDirectory();

  @override
  Directory createDirectory(String path) =>
      path == appPath ? directory : super.createDirectory(path);
}

void main() {
  late Directory tempRoot;

  setUp(() {
    resetAppDirectoryForTest();
    tempRoot = Directory.systemTemp.createTempSync('app_directory_test_');
  });

  tearDown(() {
    resetAppDirectoryForTest();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('getAppDirectory', () {
    test(
      'Windows starts when redirected Documents cannot be created',
      () async {
        final docs = Directory(p.join(tempRoot.path, 'OneDrive', 'Dokumente'));
        final support = Directory(p.join(tempRoot.path, 'LocalAppData'));

        await IOOverrides.runWithIOOverrides(() async {
          final result = await getAppDirectory(
            docsProvider: () async => docs,
            supportProvider: () async => support,
            isWindows: true,
          );

          expect(result.path, p.join(support.path, 'nt_helper'));
          expect(result.existsSync(), isTrue);
          expect(File(p.join(result.path, '.migrated')).existsSync(), isTrue);
          final database = await DatabaseIntegrityService.getDatabaseFile();
          expect(database.parent.path, result.path);
          final integrity = await DatabaseIntegrityService.checkIntegrity();
          expect(integrity.fileExists, isFalse);
          expect(integrity.isCorrupt, isFalse);

          File(
            p.join(result.path, 'gallery_cache.json'),
          ).writeAsStringSync('saved');
          resetAppDirectoryForTest();
          final reopened = await getAppDirectory(
            docsProvider: () async =>
                throw StateError('must not revisit Documents'),
            supportProvider: () async => support,
            isWindows: true,
          );
          expect(reopened.path, result.path);
          expect(
            File(
              p.join(reopened.path, 'gallery_cache.json'),
            ).readAsStringSync(),
            'saved',
          );
        }, _UnavailableDocuments(p.join(docs.path, 'nt_helper')));
      },
    );

    test('Windows keeps fallback data after Documents recovers', () async {
      final support = Directory(p.join(tempRoot.path, 'LocalAppData'));
      final fallback = Directory(p.join(support.path, 'nt_helper'))
        ..createSync(recursive: true);
      File(
        p.join(fallback.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('fallback-db');
      final documentsApp = Directory(p.join(tempRoot.path, 'nt_helper'))
        ..createSync();
      File(
        p.join(documentsApp.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('documents-db');

      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        supportProvider: () async => support,
        isWindows: true,
      );

      expect(result.path, fallback.path);
      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite')).readAsStringSync(),
        'fallback-db',
      );
      expect(
        File(
          p.join(documentsApp.path, 'nt_helper_db.sqlite'),
        ).readAsStringSync(),
        'documents-db',
      );
    });

    test('Windows preserves a working Documents database', () async {
      final support = Directory(p.join(tempRoot.path, 'LocalAppData'));
      final documentsApp = Directory(p.join(tempRoot.path, 'nt_helper'))
        ..createSync();
      File(
        p.join(documentsApp.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('existing-db');

      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        supportProvider: () async => support,
        isWindows: true,
      );

      expect(result.path, documentsApp.path);
      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite')).readAsStringSync(),
        'existing-db',
      );
      expect(
        Directory(p.join(support.path, 'nt_helper')).existsSync(),
        isFalse,
      );
    });

    test('Windows creates ordinary missing Documents parents', () async {
      final docs = Directory(p.join(tempRoot.path, 'OneDrive', 'Dokumente'));
      final support = Directory(p.join(tempRoot.path, 'LocalAppData'));
      final result = await getAppDirectory(
        docsProvider: () async => docs,
        supportProvider: () async => support,
        isWindows: true,
      );

      expect(result.path, p.join(docs.path, 'nt_helper'));
      expect(result.existsSync(), isTrue);
      expect(support.existsSync(), isFalse);
    });

    test('Windows falls back when Documents lookup is unavailable', () async {
      final result = await getAppDirectory(
        docsProvider: () async =>
            throw MissingPlatformDirectoryException('Documents missing'),
        supportProvider: () async => tempRoot,
        isWindows: true,
      );
      expect(result.path, p.join(tempRoot.path, 'nt_helper'));
      expect(result.existsSync(), isTrue);
    });

    test(
      'Windows can use Documents when support lookup is unavailable',
      () async {
        final result = await getAppDirectory(
          docsProvider: () async => tempRoot,
          supportProvider: () async =>
              throw MissingPlatformDirectoryException('Support missing'),
          isWindows: true,
        );
        expect(result.path, p.join(tempRoot.path, 'nt_helper'));
      },
    );

    test(
      'non-Windows directory failures propagate and initialization can retry',
      () async {
        await IOOverrides.runWithIOOverrides(() async {
          await expectLater(
            getAppDirectory(
              docsProvider: () async => tempRoot,
              supportProvider: () async =>
                  throw StateError('must not request support'),
              isWindows: false,
            ),
            throwsA(isA<PathNotFoundException>()),
          );
        }, _UnavailableDocuments(p.join(tempRoot.path, 'nt_helper')));

        final result = await getAppDirectory(
          docsProvider: () async => tempRoot,
          isWindows: false,
        );
        expect(result.existsSync(), isTrue);
      },
    );

    test('concurrent failed callers receive the error and can retry', () async {
      final pending = Completer<Directory>();
      final error = FileSystemException('directory unavailable');
      final first = getAppDirectory(
        docsProvider: () => pending.future,
        isWindows: false,
      );
      final second = getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );
      final firstCheck = expectLater(first, throwsA(same(error)));
      final secondCheck = expectLater(second, throwsA(same(error)));
      pending.completeError(error);
      await Future.wait([firstCheck, secondCheck]);
      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );
      expect(result.existsSync(), isTrue);
    });

    test(
      'Windows does not hide migration failures by opening an empty fallback',
      () async {
        final support = Directory(p.join(tempRoot.path, 'LocalAppData'));
        final oldDatabase = File(p.join(tempRoot.path, 'nt_helper_db.sqlite'))
          ..writeAsStringSync('original');
        Directory(
          p.join(tempRoot.path, 'nt_helper', 'nt_helper_db.sqlite'),
        ).createSync(recursive: true);

        await expectLater(
          getAppDirectory(
            docsProvider: () async => tempRoot,
            supportProvider: () async => support,
            isWindows: true,
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(oldDatabase.readAsStringSync(), 'original');
        expect(
          Directory(p.join(support.path, 'nt_helper')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'Windows propagates failure when fallback cannot be created',
      () async {
        File(
          p.join(tempRoot.path, 'blocked'),
        ).writeAsStringSync('not a directory');
        await expectLater(
          getAppDirectory(
            docsProvider: () async =>
                throw MissingPlatformDirectoryException('Documents missing'),
            supportProvider: () async =>
                Directory(p.join(tempRoot.path, 'blocked')),
            isWindows: true,
          ),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test('creates nt_helper subdirectory', () async {
      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(result.existsSync(), isTrue);
      expect(p.basename(result.path), 'nt_helper');
    });

    test('creates .migrated marker file after first run', () async {
      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      final marker = File(p.join(result.path, '.migrated'));
      expect(marker.existsSync(), isTrue);
    });

    test('returns same directory on subsequent calls', () async {
      final first = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );
      final second = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(first.path, second.path);
    });

    test('concurrent calls return the same directory', () async {
      final futures = List.generate(
        5,
        (_) => getAppDirectory(
          docsProvider: () async => tempRoot,
          isWindows: false,
        ),
      );

      final results = await Future.wait(futures);
      for (final dir in results) {
        expect(dir.path, results.first.path);
      }
    });
  });

  group('migration', () {
    test('copies sqlite and gallery_cache from old location', () async {
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('db-content');
      File(
        p.join(tempRoot.path, 'gallery_cache.json'),
      ).writeAsStringSync('cache-content');

      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite')).readAsStringSync(),
        'db-content',
      );
      expect(
        File(p.join(result.path, 'gallery_cache.json')).readAsStringSync(),
        'cache-content',
      );
    });

    test('does not copy WAL or SHM files', () async {
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('db');
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite-wal'),
      ).writeAsStringSync('wal');
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite-shm'),
      ).writeAsStringSync('shm');

      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite-wal')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite-shm')).existsSync(),
        isFalse,
      );
    });

    test('deletes old files after successful migration', () async {
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('db');
      File(
        p.join(tempRoot.path, 'gallery_cache.json'),
      ).writeAsStringSync('cache');

      await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(
        File(p.join(tempRoot.path, 'nt_helper_db.sqlite')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tempRoot.path, 'gallery_cache.json')).existsSync(),
        isFalse,
      );
    });

    test('cleans up old WAL and SHM files', () async {
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('db');
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite-wal'),
      ).writeAsStringSync('wal');
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite-shm'),
      ).writeAsStringSync('shm');

      await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      expect(
        File(p.join(tempRoot.path, 'nt_helper_db.sqlite-wal')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tempRoot.path, 'nt_helper_db.sqlite-shm')).existsSync(),
        isFalse,
      );
    });

    test('skips migration when .migrated marker exists', () async {
      final appDir = Directory(p.join(tempRoot.path, 'nt_helper'));
      appDir.createSync();
      File(p.join(appDir.path, '.migrated')).createSync();

      // Place a file in the old location that would be migrated
      File(
        p.join(tempRoot.path, 'nt_helper_db.sqlite'),
      ).writeAsStringSync('should-not-be-copied');

      final result = await getAppDirectory(
        docsProvider: () async => tempRoot,
        isWindows: false,
      );

      // File should NOT have been copied since marker exists
      expect(
        File(p.join(result.path, 'nt_helper_db.sqlite')).existsSync(),
        isFalse,
      );
    });

    test(
      'runs migration when directory exists but marker is missing',
      () async {
        final appDir = Directory(p.join(tempRoot.path, 'nt_helper'));
        appDir.createSync();

        // No .migrated marker, so migration should run
        File(
          p.join(tempRoot.path, 'nt_helper_db.sqlite'),
        ).writeAsStringSync('should-be-copied');

        final result = await getAppDirectory(
          docsProvider: () async => tempRoot,
          isWindows: false,
        );

        expect(
          File(p.join(result.path, 'nt_helper_db.sqlite')).readAsStringSync(),
          'should-be-copied',
        );
      },
    );
  });
}
