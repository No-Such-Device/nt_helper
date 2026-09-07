import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _subDir = 'nt_helper';
const _markerFile = '.migrated';

/// Files to migrate from the old documents directory. Only the main SQLite
/// file is copied — WAL and SHM files are intentionally excluded because
/// copying them independently is non-atomic and can produce a corrupt
/// database. SQLite will create new WAL/SHM files as needed when it opens
/// the copied database.
const filesToMigrate = ['nt_helper_db.sqlite', 'gallery_cache.json'];

Completer<Directory>? _initCompleter;

/// Returns the dedicated nt_helper directory within the application documents
/// directory, creating it if needed. On first run, copies any existing files
/// (database, gallery cache) from the parent documents directory.
/// On Windows, unavailable Documents folders (including OneDrive redirects)
/// fall back to application support, including when an empty Documents app
/// directory exists but cannot create its migration marker. Once created, the
/// fallback stays in use across launches so restoring Documents cannot hide
/// newly saved data.
///
/// Uses a [Completer] to ensure the initialization logic runs only once, even
/// if called concurrently.
///
/// Directory providers and [isWindows] are injectable for testing.
Future<Directory> getAppDirectory({
  Future<Directory> Function()? docsProvider,
  Future<Directory> Function()? supportProvider,
  bool? isWindows,
}) async {
  if (_initCompleter != null) {
    return _initCompleter!.future;
  }

  final completer = Completer<Directory>();
  _initCompleter = completer;

  try {
    Directory? fallbackDir;
    if (isWindows ?? Platform.isWindows) {
      try {
        final supportDir =
            await (supportProvider ?? getApplicationSupportDirectory)();
        fallbackDir = Directory(p.join(supportDir.path, _subDir));
      } on FileSystemException {
        // A working Documents location can still be used without support.
      } on MissingPlatformDirectoryException {
        // A working Documents location can still be used without support.
      }
    }

    Directory? docsDir;
    Directory appDir;
    if (fallbackDir != null && fallbackDir.existsSync()) {
      appDir = fallbackDir;
    } else {
      try {
        docsDir = await (docsProvider ?? getApplicationDocumentsDirectory)();
        appDir = Directory(p.join(docsDir.path, _subDir));
        if (!appDir.existsSync()) {
          appDir.createSync(recursive: true);
        }
      } catch (error) {
        if (fallbackDir == null ||
            (error is! FileSystemException &&
                error is! MissingPlatformDirectoryException)) {
          rethrow;
        }
        docsDir = null;
        appDir = fallbackDir;
        appDir.createSync(recursive: true);
      }
    }

    final marker = File(p.join(appDir.path, _markerFile));
    if (!marker.existsSync()) {
      if (docsDir != null) {
        migrateExistingFiles(docsDir, appDir);
      }
      try {
        marker.createSync();
      } on FileSystemException {
        // Directory creation can succeed while file creation is blocked. Only
        // fall back from an empty Documents store: migration may already have
        // moved a database here, and opening an empty store would hide it.
        if (fallbackDir == null ||
            docsDir == null ||
            filesToMigrate.any(
              (name) => File(p.join(appDir.path, name)).existsSync(),
            )) {
          rethrow;
        }
        appDir = fallbackDir;
        appDir.createSync(recursive: true);
        File(p.join(appDir.path, _markerFile)).createSync();
      }
    }

    completer.complete(appDir);
  } catch (e, st) {
    completer.completeError(e, st);
    _initCompleter = null;
  }

  // Return the same future on failure as well, avoiding an unobserved second
  // error when the first caller has already caught the startup exception.
  return completer.future;
}

/// Resets the cached directory so [getAppDirectory] will re-initialize.
/// Only intended for use in tests.
void resetAppDirectoryForTest() {
  _initCompleter = null;
}

/// Copies migratable files from [oldDir] to [newDir], then deletes the
/// originals. Deletion failures are silently ignored so they never break
/// the app.
void migrateExistingFiles(Directory oldDir, Directory newDir) {
  for (final fileName in filesToMigrate) {
    final oldFile = File(p.join(oldDir.path, fileName));
    final newFile = File(p.join(newDir.path, fileName));
    if (oldFile.existsSync() && !newFile.existsSync()) {
      oldFile.copySync(newFile.path);
    }
  }

  // Clean up old files after successful migration.
  for (final fileName in filesToMigrate) {
    try {
      final oldFile = File(p.join(oldDir.path, fileName));
      if (oldFile.existsSync()) {
        oldFile.deleteSync();
      }
    } catch (_) {
      // Deletion is best-effort; failures must not break the app.
    }
  }

  // Also clean up leftover WAL/SHM files from the old location.
  for (final suffix in ['-wal', '-shm']) {
    try {
      final oldFile = File(p.join(oldDir.path, 'nt_helper_db.sqlite$suffix'));
      if (oldFile.existsSync()) {
        oldFile.deleteSync();
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
