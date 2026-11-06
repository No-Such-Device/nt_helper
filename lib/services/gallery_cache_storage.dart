import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class GalleryStorageUnavailable implements Exception {
  const GalleryStorageUnavailable(this.cause);
  final Object cause;
  @override
  String toString() =>
      'Gallery temporarily unavailable. Cache transfer is incomplete; originals and interrupted work are retained. Retry after the reported condition clears. $cause';
}

/// Gallery transfer is independent of database startup. Existing cache wins.
class GalleryCacheStorage extends ChangeNotifier {
  GalleryCacheStorage({
    required this.directory,
    required this.documentsProvider,
    this.checkpoint,
  });
  final Directory directory;
  final Future<Directory> Function() documentsProvider;
  final Future<void> Function(String)? checkpoint;
  static final _transfers = <String, Future<void>>{};
  File get file => File(p.join(directory.path, 'gallery_cache.json'));
  Future<void>? _pending;
  bool ready = false;
  GalleryStorageUnavailable? failure;
  bool get busy => _pending != null;

  Future<void> prepare() {
    if (_pending != null) return _pending!;
    if (ready) return Future.value();
    final settled = Completer<void>();
    _pending = settled.future;
    failure = null;
    notifyListeners();
    unawaited(_prepare(settled));
    return settled.future;
  }

  Future<void> _prepare(Completer<void> settled) async {
    try {
      final key = p.normalize(p.absolute(file.path));
      await (_transfers[key] ??= _transfer().whenComplete(() {
        _transfers.remove(key);
      }));
      ready = true;
    } catch (error) {
      failure = GalleryStorageUnavailable(error);
    } finally {
      _pending = null;
      notifyListeners();
      if (failure case final error?) {
        settled.completeError(error);
      } else {
        settled.complete();
      }
    }
  }

  Future<void> _transfer() async {
    await checkpoint?.call('gallery:inventory');
    if (_hasCache(file)) return;
    await directory.create(recursive: true);
    final lock = await File(
      p.join(directory.path, '.gallery-import.lock'),
    ).open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      if (_hasCache(file)) return;
      final documents = await documentsProvider();
      List<int>? candidate;
      for (final location in [
        documents,
        Directory(p.join(documents.path, 'nt_helper')),
      ]) {
        final source = File(p.join(location.path, 'gallery_cache.json'));
        if (!_hasCache(source)) continue;
        await checkpoint?.call('gallery:read');
        final bytes = await source.readAsBytes();
        final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        Gallery.fromJson(data['gallery'] as Map<String, dynamic>);
        if (candidate != null && !listEquals(candidate, bytes)) {
          throw const FormatException(
            'Legacy gallery caches differ; neither was replaced',
          );
        }
        candidate = bytes;
      }
      if (candidate == null) return;
      final temporary = File(
        p.join(directory.path, '.gallery-transfer-${const Uuid().v4()}'),
      );
      final output = await temporary.open(mode: FileMode.writeOnly);
      try {
        final half = candidate.length ~/ 2;
        await output.writeFrom(candidate, 0, half);
        await checkpoint?.call('gallery:during:write');
        await output.writeFrom(candidate, half);
        await output.flush();
      } finally {
        await output.close();
      }
      await checkpoint?.call('gallery:before:publish');
      if (_hasCache(file)) {
        throw FileSystemException(
          'Gallery cache appeared during transfer; Retry to use it',
          file.path,
        );
      }
      await temporary.rename(file.path);
      await checkpoint?.call('gallery:after:publish');
    } finally {
      await lock.close();
    }
  }

  static bool _hasCache(File file) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.file) return true;
    if (type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Expected a regular gallery cache file',
        file.path,
      );
    }
    var parent = file.parent;
    while (!parent.existsSync() && parent.parent.path != parent.path) {
      parent = parent.parent;
    }
    parent.listSync(); // Do not mistake denied access for an absent cache.
    return false;
  }
}
