import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';
import 'package:path/path.dart' as p;

class WaveCacheCleanupPlan {
  const WaveCacheCleanupPlan({
    required this.sampleFragment,
    required this.matchedSamplePaths,
    required this.cachePaths,
    required this.directoriesWithoutCache,
  });

  final String? sampleFragment;
  final List<String> matchedSamplePaths;
  final List<String> cachePaths;
  final List<String> directoriesWithoutCache;

  bool get isGlobal => sampleFragment == null;
}

class WaveCacheCleanupResult {
  const WaveCacheCleanupResult({
    required this.plan,
    required this.deletedCachePaths,
    required this.failedCachePaths,
    required this.remountRequested,
    this.remountError,
  });

  final WaveCacheCleanupPlan plan;
  final List<String> deletedCachePaths;
  final Map<String, String> failedCachePaths;
  final bool remountRequested;
  final String? remountError;
}

/// Finds and removes the Disting NT's generated per-directory WAV caches.
class WaveCacheMaintenanceService {
  WaveCacheMaintenanceService(this._manager)
    : _fileSystem = PresetFileSystemImpl(_manager);

  static const cacheFileName = 'distingNT.wavcache';

  final IDistingMidiManager _manager;
  final PresetFileSystemImpl _fileSystem;

  Future<WaveCacheCleanupPlan> findForSampleFragment(String fragment) async {
    final normalizedFragment = fragment.trim();
    if (normalizedFragment.isEmpty) {
      throw ArgumentError.value(fragment, 'fragment', 'must not be empty');
    }

    final files = await _listAllFiles();
    final fragmentLower = normalizedFragment.toLowerCase();
    final matchedSamples = files.where((filePath) {
      final basename = p.posix.basename(filePath).toLowerCase();
      return basename.endsWith('.wav') && basename.contains(fragmentLower);
    }).toList()..sort();

    final cacheByDirectory = <String, String>{};
    for (final filePath in files) {
      if (_isWaveCache(filePath)) {
        cacheByDirectory[p.posix.dirname(filePath)] = filePath;
      }
    }

    final matchingDirectories = matchedSamples.map(p.posix.dirname).toSet();
    final cachePaths = <String>[];
    final directoriesWithoutCache = <String>[];
    for (final directory in matchingDirectories) {
      final cachePath = cacheByDirectory[directory];
      if (cachePath == null) {
        directoriesWithoutCache.add(directory);
      } else {
        cachePaths.add(cachePath);
      }
    }

    cachePaths.sort();
    directoriesWithoutCache.sort();
    return WaveCacheCleanupPlan(
      sampleFragment: normalizedFragment,
      matchedSamplePaths: matchedSamples,
      cachePaths: cachePaths,
      directoriesWithoutCache: directoriesWithoutCache,
    );
  }

  Future<WaveCacheCleanupPlan> findAll() async {
    final files = await _listAllFiles();
    final cachePaths = files.where(_isWaveCache).toSet().toList()..sort();
    return WaveCacheCleanupPlan(
      sampleFragment: null,
      matchedSamplePaths: const [],
      cachePaths: cachePaths,
      directoriesWithoutCache: const [],
    );
  }

  Future<WaveCacheCleanupResult> deleteAndRemount(
    WaveCacheCleanupPlan plan,
  ) async {
    final deleted = <String>[];
    final failed = <String, String>{};

    for (final cachePath in plan.cachePaths) {
      try {
        final status = await _manager.requestFileDelete(cachePath);
        if (status?.success == true) {
          deleted.add(cachePath);
        } else {
          failed[cachePath] = status?.message ?? 'No response from the device';
        }
      } catch (error) {
        failed[cachePath] = error.toString();
      }
    }

    var remountRequested = false;
    String? remountError;
    if (deleted.isNotEmpty) {
      try {
        // A full SD remount makes the NT rescan samples and rebuild these
        // caches; hardware validation confirmed that no device reboot is
        // required.
        await _manager.requestRemountSd();
        remountRequested = true;
      } catch (error) {
        remountError = error.toString();
      }
    }

    return WaveCacheCleanupResult(
      plan: plan,
      deletedCachePaths: deleted,
      failedCachePaths: failed,
      remountRequested: remountRequested,
      remountError: remountError,
    );
  }

  Future<List<String>> _listAllFiles() async {
    await _manager.requestWake();
    return _fileSystem.listFiles('/', recursive: true);
  }

  bool _isWaveCache(String filePath) {
    return p.posix.basename(filePath).toLowerCase() ==
        cacheFileName.toLowerCase();
  }
}
