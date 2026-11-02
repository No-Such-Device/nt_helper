import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/gallery_cache_storage.dart';
import 'package:nt_helper/services/macos_storage_io.dart';
import 'package:path/path.dart' as p;

import '../support/gallery_cache_fixture.dart';

void main() {
  if (!Platform.isMacOS) return;
  late Directory root;
  late Directory docs;
  late Directory app;
  setUp(() {
    root = Directory.systemTemp.createTempSync('nt-gallery-cache-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    app = Directory(p.join(root.path, 'Support'))..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  for (final nested in [false, true]) {
    test(
      'gallery ${nested ? 'D' : 'R'} transfer retains originals and complete destination',
      () async {
        final sourceDirectory = nested
            ? (Directory(p.join(docs.path, 'nt_helper'))..createSync())
            : docs;
        final source = File(p.join(sourceDirectory.path, 'gallery_cache.json'))
          ..writeAsStringSync(cache('Original'));
        final bytes = source.readAsBytesSync();
        final storage = GalleryCacheStorage(
          directory: app,
          documentsProvider: () async => docs,
        );
        await storage.prepare();
        expect(storage.file.readAsBytesSync(), bytes);
        expect(source.readAsBytesSync(), bytes);
        expect(storage.ready, isTrue);
        storage.dispose();
      },
    );
  }

  test(
    'Retry adopts newer destination without reading denied legacy or replacing interrupted work',
    () async {
      File(
        p.join(docs.path, 'gallery_cache.json'),
      ).writeAsStringSync(cache('Old'));
      var fail = true;
      var denyLegacy = false;
      final storage = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async {
          if (denyLegacy) {
            throw const FileSystemException('simulated Documents denial');
          }
          return docs;
        },
        checkpoint: (point) async {
          if (fail && point == 'gallery:during:write') {
            throw const FileSystemException('simulated interruption');
          }
        },
      );
      await expectLater(
        storage.prepare(),
        throwsA(isA<GalleryStorageUnavailable>()),
      );
      final retained = {
        for (final file in app.listSync().whereType<File>())
          file.path: file.readAsBytesSync(),
      };
      expect(retained, isNotEmpty);
      final newer = cache('New destination-only cache');
      storage.file.writeAsStringSync(newer);
      fail = false;
      denyLegacy = true;
      await storage.prepare();
      expect(storage.file.readAsStringSync(), newer);
      for (final entry in retained.entries) {
        expect(File(entry.key).readAsBytesSync(), entry.value);
      }
      expect(
        jsonDecode(
          storage.file.readAsStringSync(),
        )['gallery']['plugins'][0]['name'],
        'New destination-only cache',
      );
      storage.dispose();
    },
  tags: ['regression']);

  test(
    'another writer at publication is retained; Retry adopts it without overwrite',
    () async {
      File(
        p.join(docs.path, 'gallery_cache.json'),
      ).writeAsStringSync(cache('Old'));
      final newer = cache('Concurrent destination');
      late GalleryCacheStorage storage;
      storage = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async => docs,
        checkpoint: (point) async {
          if (point == 'gallery:before:publish') {
            storage.file.writeAsStringSync(newer);
          }
        },
      );
      await expectLater(
        storage.prepare(),
        throwsA(isA<GalleryStorageUnavailable>()),
      );
      await storage.prepare();
      expect(storage.file.readAsStringSync(), newer);
      storage.dispose();
    },
  tags: ['regression']);

  test(
    'new service after interrupted transfer progresses without deleting partial work',
    () async {
      final source = File(p.join(docs.path, 'gallery_cache.json'))
        ..writeAsStringSync(cache('Original'));
      final interrupted = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async => docs,
        checkpoint: (point) async {
          if (point == 'gallery:during:write') {
            throw const FileSystemException(
              'simulated interrupted process boundary',
            );
          }
        },
      );
      await expectLater(
        interrupted.prepare(),
        throwsA(isA<GalleryStorageUnavailable>()),
      );
      final work = app.listSync().whereType<File>().single;
      final bytes = work.readAsBytesSync();
      interrupted.dispose();
      final restarted = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async => docs,
      );
      await restarted.prepare();
      expect(restarted.file.readAsBytesSync(), source.readAsBytesSync());
      expect(work.readAsBytesSync(), bytes);
      restarted.dispose();
    },
  tags: ['regression']);

  test(
    'no legacy cache is ordinary empty cache availability, not failed transfer',
    () async {
      final storage = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async => docs,
      );
      final first = storage.prepare();
      expect(identical(storage.prepare(), first), isTrue);
      await first;
      expect(storage.ready, isTrue);
      expect(storage.failure, isNull);
      expect(storage.file.existsSync(), isFalse);
      storage.dispose();
    },
  );

  test(
    'uncertain legacy caches and symlink destinations stay retained and unavailable',
    () async {
      final original = File(p.join(docs.path, 'gallery_cache.json'))
        ..writeAsStringSync(cache('R'));
      final nested = Directory(p.join(docs.path, 'nt_helper'))..createSync();
      final different = File(p.join(nested.path, 'gallery_cache.json'))
        ..writeAsStringSync(cache('D'));
      final storage = GalleryCacheStorage(
        directory: app,
        documentsProvider: () async => docs,
      );
      await expectLater(
        storage.prepare(),
        throwsA(isA<GalleryStorageUnavailable>()),
      );
      expect(storage.file.existsSync(), isFalse);
      expect(original.readAsStringSync(), isNot(different.readAsStringSync()));
      Link(storage.file.path).createSync(original.path);
      await expectLater(
        storage.prepare(),
        throwsA(isA<GalleryStorageUnavailable>()),
      );
      expect(
        () => MacosStorageIo.identity(storage.file.path),
        throwsA(isA<FileSystemException>()),
      );
      storage.dispose();
    },
  tags: ['regression']);
}
