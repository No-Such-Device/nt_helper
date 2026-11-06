import 'dart:io';

import 'package:flutter/services.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OpenedStartupLibrary {
  const OpenedStartupLibrary(this.database, {this.location});
  final AppDatabase database;
  final String? location;
}

/// Resolve the location, then let Drift and SQLite open the library normally.
class StartupStorageOpener {
  StartupStorageOpener({
    bool? isMacOS,
    this.docsProvider,
    this.supportProvider,
    this.galleryCheckpoint,
    this.requestAccess = _requestAccess,
    this.releaseAccess = _releaseAccess,
  }) : isMacOS = isMacOS ?? Platform.isMacOS;

  final bool isMacOS;
  final Future<Directory> Function()? docsProvider;
  final Future<Directory> Function()? supportProvider;
  final Future<void> Function(String)? galleryCheckpoint;
  final Future<bool> Function(String) requestAccess;
  final Future<void> Function() releaseAccess;
  String? legacyAccessDirectory;
  String? location;

  static const _accessChannel = MethodChannel(
    'com.nt_helper.app/legacy_storage_access',
  );
  static Future<bool> _requestAccess(String path) async =>
      await _accessChannel.invokeMethod<bool>('select', path) ?? false;
  static Future<void> _releaseAccess() =>
      _accessChannel.invokeMethod<void>('release');

  Future<OpenedStartupLibrary> open({
    bool selectLegacyDirectory = false,
    File? importSource,
    bool startFresh = false,
  }) async {
    AppDatabase? database;
    Directory? documents;
    var accessRequested = false;
    final requestedDirectory = legacyAccessDirectory;
    legacyAccessDirectory = null;
    try {
      final folder = await getAppDirectory(
        isMacOS: isMacOS,
        docsProvider: docsProvider,
        supportProvider: supportProvider,
        galleryCheckpoint: galleryCheckpoint,
      );
      File file;
      if (isMacOS) {
        final storage = LibraryStorage(
          directory: folder,
          documentsProvider: () async {
            documents =
                await (docsProvider ?? getApplicationDocumentsDirectory)();
            if (selectLegacyDirectory && requestedDirectory != null) {
              accessRequested = true;
              if (!await requestAccess(requestedDirectory)) {
                legacyAccessDirectory = requestedDirectory;
                throw FileSystemException(
                  'Folder selection cancelled',
                  requestedDirectory,
                );
              }
            }
            return documents!;
          },
        );
        location = storage.file.path;
        file = await storage.prepare(
          importSource: importSource,
          startFresh: startFresh,
        );
      } else {
        file = File(p.join(folder.path, 'nt_helper_db.sqlite'));
        location = file.path;
      }
      database = AppDatabase.atFile(file);
      await database.select(database.algorithms).get();
      return OpenedStartupLibrary(database, location: file.path);
    } catch (error) {
      await database?.close();
      final cause = error is LibraryImportException ? error.cause : error;
      if (documents != null &&
          cause is FileSystemException &&
          [1, 13].contains(cause.osError?.errorCode) &&
          cause.path != null &&
          (p.equals(cause.path!, documents!.path) ||
              p.isWithin(documents!.path, cause.path!))) {
        legacyAccessDirectory = FileSystemEntity.isDirectorySync(cause.path!)
            ? p.normalize(cause.path!)
            : File(cause.path!).parent.path;
      }
      rethrow;
    } finally {
      if (accessRequested) await releaseAccess();
    }
  }
}
