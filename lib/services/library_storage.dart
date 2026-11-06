import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:nt_helper/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class LibraryImportException implements Exception {
  const LibraryImportException(
    this.message, {
    this.paths = const [],
    this.cause,
  });
  final String message;
  final List<String> paths;
  final Object? cause;

  @override
  String toString() =>
      [message, ...paths, if (cause != null) '$cause'].join('\n');
}

/// A one-time bridge from historical locations, not a database authority layer.
class LibraryStorage {
  LibraryStorage({required this.directory, required this.documentsProvider});
  final Directory directory;
  final Future<Directory> Function() documentsProvider;
  static const legacyFileName = 'nt_helper_db.sqlite';
  static final _pending = <String, Future<File>>{};
  File get file => File(p.join(directory.path, 'library.sqlite'));

  Future<File> prepare({File? importSource, bool startFresh = false}) {
    if (importSource != null && startFresh) {
      return Future.error(
        ArgumentError('Choose a library or start fresh, not both'),
      );
    }
    if (file.existsSync()) return Future.value(file);
    final key = p.normalize(p.absolute(file.path));
    return _pending[key] ??= _prepare(importSource, startFresh).whenComplete(
      () {
        _pending.remove(key);
      },
    );
  }

  Future<File> _prepare(File? source, bool startFresh) async {
    await directory.create(recursive: true);
    final lock = await File(
      p.join(directory.path, '.library-import.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      // Another process may have finished importing while we acquired the lock.
      if (await file.exists()) return file;
      try {
        source ??= startFresh ? null : await _findSource();
        final work = Directory(p.join(directory.path, '.library-import'));
        if (await work.exists()) await work.delete(recursive: true);
        await work.create();
        try {
          final temporary = File(p.join(work.path, 'library.sqlite'));
          if (source != null) {
            final reader = sqlite3.open(source.path, mode: OpenMode.readWrite);
            try {
              final target = sqlite3.open(temporary.path);
              try {
                await reader.backup(target).drain<void>();
              } finally {
                target.close();
              }
            } finally {
              reader.close();
            }
          }
          final app = AppDatabase.withExecutor(NativeDatabase(temporary));
          try {
            await app.select(app.algorithms).get();
          } finally {
            await app.close();
          }
          // All SQLite handles are closed; no live sidecars are copied.
          await temporary.rename(file.path);
          return file;
        } finally {
          if (await work.exists()) await work.delete(recursive: true);
        }
      } catch (error) {
        if (error is LibraryImportException) rethrow;
        throw LibraryImportException(
          'Could not import the saved library. Existing files have been kept.',
          paths: [if (source != null) source.path, file.path],
          cause: error,
        );
      }
    } finally {
      await lock.close(); // Also releases the migration-only lock.
    }
  }

  Future<File?> _findSource() async {
    final control = Directory(p.join(directory.path, '.storage-v1'));
    var selection = File(p.join(control.path, 'selected.json'));
    if (_type(selection.path) != FileSystemEntityType.notFound) {
      final seen = <String>{};
      File? selected;
      try {
        while (_type(selection.path) != FileSystemEntityType.notFound) {
          final envelope = jsonDecode(await selection.readAsString()) as Map;
          final record = jsonDecode(envelope['body'] as String) as Map;
          final attempt = record['attempt'] as String;
          final relative = record['file'] as String;
          if (!RegExp(
                r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
              ).hasMatch(attempt) ||
              !seen.add(attempt) ||
              relative != p.join('work-$attempt', legacyFileName) ||
              _type(p.join(control.path, 'work-$attempt')) ==
                  FileSystemEntityType.link) {
            throw const FormatException('Invalid historical library path');
          }
          selected = File(p.join(control.path, relative));
          selection = File(p.join(control.path, 'selected-$attempt.json'));
        }
        if (selected == null ||
            _type(selected.path) != FileSystemEntityType.file) {
          throw const FormatException('The saved main database is missing');
        }
        return selected;
      } catch (error) {
        throw LibraryImportException(
          'The previously selected library could not be found or read. Choose an intact library or start fresh.',
          paths: [if (selected != null) selected.path, selection.path],
          cause: error,
        );
      }
    }

    final documents = await documentsProvider();
    final paths = [
      p.join(directory.path, legacyFileName),
      p.join(documents.path, 'nt_helper', legacyFileName),
      p.join(documents.path, legacyFileName),
    ];
    var historical = false;
    if (_type(control.path) != FileSystemEntityType.notFound) {
      for (final entry in control.listSync(followLinks: false)) {
        if (p.basename(entry.path).startsWith('work-')) {
          historical = true;
          if (entry is Directory) paths.add(p.join(entry.path, legacyFileName));
        }
      }
    }
    final candidates = <String>{};
    for (final path in paths) {
      final type = _type(path);
      if (type == FileSystemEntityType.file) {
        candidates.add(path);
      } else if (type != FileSystemEntityType.notFound) {
        throw LibraryImportException(
          'Not a regular library file',
          paths: [path],
        );
      }
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (_type('$path$suffix') != FileSystemEntityType.notFound) {
          historical = true;
        }
      }
    }
    if (candidates.length == 1) return File(candidates.single);
    if (candidates.isNotEmpty || historical) {
      throw LibraryImportException(
        candidates.isEmpty
            ? 'Historical library files remain, but the main database is missing. Choose a library or start fresh.'
            : 'More than one saved library was found. Choose which library to import.',
        paths: candidates.toList(),
      );
    }
    return null;
  }

  // Unlike existsSync alone, a missing result must not hide denied inventory.
  static FileSystemEntityType _type(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      var parent = Directory(p.dirname(path));
      while (FileSystemEntity.typeSync(parent.path) ==
          FileSystemEntityType.notFound) {
        final next = parent.parent;
        if (next.path == parent.path) break;
        parent = next;
      }
      parent.listSync();
    }
    return type;
  }
}
