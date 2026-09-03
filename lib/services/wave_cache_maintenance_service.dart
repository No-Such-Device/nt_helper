import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';
import 'package:nt_helper/interfaces/preset_file_system.dart';
import 'package:path/path.dart' as p;

class WaveCacheCleanupPlan {
  const WaveCacheCleanupPlan({
    required this.sampleFragment,
    required this.matchedSamplePaths,
    required this.cachePaths,
    required this.directoriesWithoutCache,
    this.zeroByteWavPaths = const [],
    this.isZeroByteWavScan = false,
  });

  final String? sampleFragment;
  final List<String> matchedSamplePaths;
  final List<String> cachePaths;
  final List<String> directoriesWithoutCache;
  final List<String> zeroByteWavPaths;
  final bool isZeroByteWavScan;

  bool get isGlobal => sampleFragment == null;
  bool get hasDeletions => zeroByteWavPaths.isNotEmpty || cachePaths.isNotEmpty;
}

class WaveCacheCleanupResult {
  const WaveCacheCleanupResult({
    required this.plan,
    required this.deletedCachePaths,
    required this.failedCachePaths,
    required this.remountRequested,
    this.deletedZeroByteWavPaths = const [],
    this.failedZeroByteWavPaths = const {},
    this.remountError,
  });

  final WaveCacheCleanupPlan plan;
  final List<String> deletedCachePaths;
  final Map<String, String> failedCachePaths;
  final List<String> deletedZeroByteWavPaths;
  final Map<String, String> failedZeroByteWavPaths;
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

    final entries = await _listAllEntries();
    final files = entries.map((entry) => entry.path).toList();
    final fragmentLower = normalizedFragment.toLowerCase();
    final matchedSampleEntries = entries.where((entry) {
      final basename = p.posix.basename(entry.path).toLowerCase();
      return basename.endsWith('.wav') && basename.contains(fragmentLower);
    }).toList();
    final matchedSamples =
        matchedSampleEntries.map((entry) => entry.path).toList()..sort();
    final zeroByteWavPaths =
        matchedSampleEntries
            .where((entry) => entry.size == 0)
            .map((entry) => entry.path)
            .toList()
          ..sort();

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
      zeroByteWavPaths: zeroByteWavPaths,
    );
  }

  Future<WaveCacheCleanupPlan> findAll() async {
    final files = (await _listAllEntries()).map((entry) => entry.path);
    final cachePaths = files.where(_isWaveCache).toSet().toList()..sort();
    return WaveCacheCleanupPlan(
      sampleFragment: null,
      matchedSamplePaths: const [],
      cachePaths: cachePaths,
      directoriesWithoutCache: const [],
    );
  }

  Future<WaveCacheCleanupPlan> findZeroByteWavs() async {
    final entries = await _listAllEntries();
    final zeroByteWavPaths =
        entries
            .where(
              (entry) =>
                  entry.size == 0 &&
                  p.posix.basename(entry.path).toLowerCase().endsWith('.wav'),
            )
            .map((entry) => entry.path)
            .toList()
          ..sort();

    final cacheByDirectory = <String, String>{};
    for (final entry in entries) {
      if (_isWaveCache(entry.path)) {
        cacheByDirectory[p.posix.dirname(entry.path)] = entry.path;
      }
    }

    final cachePaths = <String>[];
    final directoriesWithoutCache = <String>[];
    for (final directory in zeroByteWavPaths.map(p.posix.dirname).toSet()) {
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
      sampleFragment: null,
      matchedSamplePaths: const [],
      cachePaths: cachePaths,
      directoriesWithoutCache: directoriesWithoutCache,
      zeroByteWavPaths: zeroByteWavPaths,
      isZeroByteWavScan: true,
    );
  }

  Future<WaveCacheCleanupResult> deleteAndRemount(
    WaveCacheCleanupPlan plan,
  ) async {
    final deleted = <String>[];
    final failed = <String, String>{};
    final deletedZeroByteWavs = <String>[];
    final failedZeroByteWavs = <String, String>{};

    await _deletePaths(
      plan.zeroByteWavPaths,
      deletedZeroByteWavs,
      failedZeroByteWavs,
    );
    await _deletePaths(plan.cachePaths, deleted, failed);

    var remountRequested = false;
    String? remountError;
    if (deletedZeroByteWavs.isNotEmpty || deleted.isNotEmpty) {
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
      deletedZeroByteWavPaths: deletedZeroByteWavs,
      failedZeroByteWavPaths: failedZeroByteWavs,
      remountRequested: remountRequested,
      remountError: remountError,
    );
  }

  Future<List<FileEntryInfo>> _listAllEntries() async {
    await _manager.requestWake();
    return _fileSystem.listEntries('/', recursive: true);
  }

  Future<void> _deletePaths(
    List<String> paths,
    List<String> deleted,
    Map<String, String> failed,
  ) async {
    for (final path in paths) {
      try {
        final status = await _manager.requestFileDelete(path);
        if (status?.success == true) {
          deleted.add(path);
        } else {
          failed[path] = status?.message ?? 'No response from the device';
        }
      } catch (error) {
        failed[path] = error.toString();
      }
    }
  }

  bool _isWaveCache(String filePath) {
    return p.posix.basename(filePath).toLowerCase() ==
        cacheFileName.toLowerCase();
  }
}
