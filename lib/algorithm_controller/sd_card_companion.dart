import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:nt_helper/utils/temp_directory_utils.dart';
import 'dart:typed_data';
import 'lua_algorithm_controller_engine.dart';

/// SD Lua source with an optional endpoint-scoped scratch-file cache.
class SdCardCompanion {
  SdCardCompanion._(this.source, this.guid);
  static String pathForGuid(String guid) {
    if (!RegExp(r'^[A-Za-z0-9 _-]{4}$').hasMatch(guid)) {
      throw const FormatException('Unsupported companion GUID');
    }
    return '/programs/helper/$guid.lua';
  }

  // A transfer/source resource budget, independent of the preset's string limits.
  static const maximumSourceBytes = 64 * 1024;
  final String source;
  final String guid;

  static Future<SdCardCompanion> load(
    Future<Uint8List?> Function(String) download, {
    required String guid,
    String? cacheKey,
    bool refresh = false,
    Future<Directory> Function()? temporaryDirectory,
  }) async {
    final sdPath = pathForGuid(guid);
    File? cache;
    if (cacheKey != null) {
      try {
        final root =
            await (temporaryDirectory ??
                TempDirectoryUtils.getWritableTempDirectory)();
        final endpoint = sha256.convert(utf8.encode(cacheKey)).toString();
        cache = File(
          p.join(
            root.path,
            'nt_helper',
            'companions',
            'v1',
            endpoint,
            '$guid.lua',
          ),
        );
        if (!refresh && await cache.exists()) {
          try {
            return _decode(await cache.readAsBytes(), guid);
          } on FormatException {
            // Invalid/partial scratch files are replaced by a fresh SD download.
          }
        }
      } on FileSystemException {
        // Scratch storage is optional; SD loading still works if unavailable.
        cache = null;
      }
    }
    final data = await download(sdPath);
    final companion = _decode(data, guid);
    if (cache != null) {
      Directory? staging;
      try {
        await cache.parent.create(recursive: true);
        staging = await cache.parent.createTemp('.download-');
        final file = File(p.join(staging.path, '$guid.lua'));
        await file.writeAsBytes(data!, flush: true);
        await file.rename(cache.path);
      } on FileSystemException {
        // A cache write failure does not invalidate successfully downloaded Lua.
      } finally {
        if (staging != null) {
          try {
            await staging.delete(recursive: true);
          } on FileSystemException {
            /* Temporary cleanup is best effort. */
          }
        }
      }
    }
    return companion;
  }

  static SdCardCompanion _decode(Uint8List? data, String guid) {
    if (data == null || data.isEmpty) {
      throw FormatException(
        'Install $guid.lua in /programs/helper/ on the NT SD card.',
      );
    }
    if (data.length > maximumSourceBytes) {
      throw const FormatException(
        'Companion exceeds the 64 KiB source budget.',
      );
    }
    return SdCardCompanion._(utf8.decode(data), guid);
  }

  Future<Map<String, dynamic>> evaluate(
    Map<String, Object?> snapshot, {
    Map<String, Object?>? event,
    Map<String, Object?>? change,
  }) async {
    final reply = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(
        _evaluate,
        (reply.sendPort, source, snapshot, event, guid, change),
        onError: reply.sendPort,
        onExit: reply.sendPort,
        errorsAreFatal: true,
      );
      final response = await reply.first.timeout(const Duration(seconds: 2));
      if (response is! String) {
        throw const FormatException(
          'Companion evaluation failed. Reload the companion.',
        );
      }
      if (response.length > 65536) {
        throw const FormatException(
          'Companion result exceeds its 64 KiB budget.',
        );
      }
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid companion document.');
      }
      return decoded;
    } on TimeoutException {
      throw const FormatException(
        'Companion exceeded its execution deadline. Reload the companion.',
      );
    } finally {
      worker?.kill(priority: Isolate.immediate);
      reply.close();
    }
  }
}

void _evaluate(
  (
    SendPort,
    String,
    Map<String, Object?>,
    Map<String, Object?>?,
    String,
    Map<String, Object?>?,
  )
  request,
) {
  final value = const LuaAlgorithmControllerEngine().evaluateCompanion(
    source: request.$2,
    guid: request.$5,
    snapshot: request.$3,
    event: request.$4,
    change: request.$6,
  );
  Object? normalize(Object? input) {
    if (input is Map) {
      final result = <String, Object?>{};
      for (final entry in input.entries) {
        if (entry.key is! String) throw const FormatException('Invalid key');
        result[entry.key as String] = normalize(entry.value);
      }
      return result;
    }
    if (input is List) return input.map(normalize).toList();
    return input;
  }

  final encoded = jsonEncode(normalize(value));
  if (encoded.length > 65536) {
    throw const FormatException('Companion output exceeds budget');
  }
  request.$1.send(encoded);
}
