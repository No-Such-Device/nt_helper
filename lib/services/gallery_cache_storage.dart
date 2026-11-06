import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/macos_storage_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class GalleryStorageUnavailable implements Exception {
  const GalleryStorageUnavailable(this.cause);
  final Object cause;
  @override
  String toString() =>
      'Gallery temporarily unavailable. Cache transfer is incomplete; originals and interrupted work are retained. Retry after the reported condition clears. $cause';
}

/// Independent of database selection: Retry can only publish the gallery cache.
/// A complete destination wins without another Documents read. Partial copies
/// stay under unique work names; publication never replaces destination data.
class GalleryCacheStorage extends ChangeNotifier {
  GalleryCacheStorage({
    required this.directory,
    required this.documentsProvider,
    this.checkpoint,
  });
  final Directory directory;
  final Future<Directory> Function() documentsProvider;
  final Future<void> Function(String)? checkpoint;
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
      await checkpoint?.call('gallery:inventory');
      if (MacosStorageIo.identity(file.path) == null) {
        final documents = await documentsProvider();
        final candidates = <List<int>>[];
        for (final directory in [
          documents,
          Directory(p.join(documents.path, 'nt_helper')),
        ]) {
          final source = File(p.join(directory.path, 'gallery_cache.json'));
          if (MacosStorageIo.identity(source.path) == null) continue;
          await checkpoint?.call('gallery:read');
          final bytes = await source.readAsBytes();
          _validate(bytes);
          if (candidates.isNotEmpty && !listEquals(candidates.first, bytes)) {
            throw const FormatException(
              'Legacy gallery caches differ; neither was replaced',
            );
          }
          candidates.add(bytes);
        }
        if (candidates.isNotEmpty) {
          await MacosStorageIo.publish(
            p.join(directory.path, '.gallery-transfer-${const Uuid().v4()}'),
            file.path,
            candidates.first,
            (point) async => checkpoint?.call('gallery:$point'),
          );
        }
      }
      // Existing destinations are authoritative, including later cache edits.
      // Ordinary cache decoding/network fallback remains GalleryService's job.
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

  void _validate(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    Gallery.fromJson(data['gallery'] as Map<String, dynamic>);
  }
}
