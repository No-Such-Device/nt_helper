import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// A connection-scoped lease, not dialog state: closing/reopening a browser (or
/// replacing its manager on the same MIDI endpoint) cannot expose a partial file.
abstract interface class SdCardFileActivityOwner {
  SdCardFileActivity get fileActivity;
}

class SdCardFileBusyException extends StateError {
  SdCardFileBusyException()
    : super('File is being changed; wait for the operation to finish.');
}

class SdCardFileActivity extends ValueNotifier<Set<String>> {
  SdCardFileActivity() : super(const {});
  static final _fallback = Expando<SdCardFileActivity>();
  static final _endpoints = Expando<Map<String, SdCardFileActivity>>();
  static SdCardFileActivity forManager(Object manager) =>
      manager is SdCardFileActivityOwner
      ? manager.fileActivity
      : (_fallback[manager] ??= SdCardFileActivity());
  static SdCardFileActivity forEndpoint(
    Object midi,
    String deviceId,
    int sysExId,
  ) => (_endpoints[midi] ??= {})['$deviceId:$sysExId'] ??= SdCardFileActivity();

  String _path(String path) =>
      p.posix.normalize(path.startsWith('/') ? path : '/$path').toLowerCase();
  bool _overlaps(String a, String b) =>
      a == '/' ||
      b == '/' ||
      a == b ||
      a.startsWith('$b/') ||
      b.startsWith('$a/');
  bool isBusy(String path) => value.any((busy) => _overlaps(_path(path), busy));
  void requireAvailable(String path, {bool preset = false}) {
    final candidates = {path};
    if (preset) {
      if (!path.toLowerCase().endsWith('.json')) candidates.add('$path.json');
      if (!path.contains('/')) {
        candidates.addAll({
          '/presets/$path',
          '/presets/${path.toLowerCase().endsWith('.json') ? path : '$path.json'}',
        });
      }
    }
    if (candidates.any(isBusy)) throw SdCardFileBusyException();
  }

  Future<T> hold<T>(Set<String> paths, Future<T> Function() operation) async {
    final normalized = paths.map(_path).toSet();
    for (final path in normalized) {
      requireAvailable(path);
    }
    value = {...value, ...normalized};
    try {
      return await operation();
    } finally {
      value = {...value}..removeAll(normalized);
    }
  }
}
