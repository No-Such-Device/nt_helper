import 'dart:typed_data';

import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sd_card_file_activity.dart';
import 'package:nt_helper/interfaces/preset_file_system.dart';
import 'package:path/path.dart' as p;

class PresetFileSystemImpl implements PresetFileSystem {
  final IDistingMidiManager manager;
  PresetFileSystemImpl(this.manager);

  @override
  Future<List<String>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final entries = await listEntries(directoryPath, recursive: recursive);
    return [for (final e in entries) e.path];
  }

  @override
  Future<List<FileEntryInfo>> listEntries(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final listing = await manager.requestDirectoryListing(directoryPath);
    if (listing == null) return [];

    final result = <FileEntryInfo>[];
    for (final entry in listing.entries) {
      // Hardware appends '/' to directory names — strip it for path construction
      final entryName = entry.name.endsWith('/')
          ? entry.name.substring(0, entry.name.length - 1)
          : entry.name;
      final entryPath = p.posix.join(directoryPath, entryName);
      if (entry.isDirectory) {
        if (recursive) {
          result.addAll(await listEntries(entryPath, recursive: true));
        }
      } else {
        result.add(FileEntryInfo(path: entryPath, size: entry.size));
      }
    }
    return result;
  }

  @override
  Future<int?> getFileSize(String relativePath) async {
    final slash = relativePath.lastIndexOf('/');
    if (slash <= 0) return null;
    final parent = relativePath.substring(0, slash);
    final entries = await listEntries(parent);
    for (final e in entries) {
      if (e.path == relativePath) return e.size;
    }
    return null;
  }

  @override
  Future<Uint8List?> readFile(String relativePath) {
    SdCardFileActivity.forManager(manager).requireAvailable(relativePath);
    return manager.requestFileDownload(relativePath);
  }
}
