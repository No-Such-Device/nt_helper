import 'package:nt_helper/models/plugin_cleanup_outcome.dart';

/// Why a verified plugin install was refused before anything was uploaded.
enum PluginInstallRefusal {
  /// No synchronized device session exists.
  notConnected('not_connected'),

  /// The app is synchronized from the offline cache, not a live device.
  offline('offline_mode'),

  /// The app is running against demo data, not a live device.
  demo('demo_mode'),

  /// The connected firmware cannot write to the SD card.
  noSdCardSupport('sd_card_unsupported'),

  /// The `.o` file is not a readable ELF object.
  invalidElf('invalid_elf'),

  /// The `.o` file is not 32-bit little-endian ARM (EM_ARM).
  wrongArchitecture('wrong_architecture'),

  /// The `.o` file is linked (ET_EXEC/ET_DYN) rather than relocatable.
  notRelocatable('not_relocatable'),

  /// The `.o` file does not define the `pluginEntry` symbol.
  missingPluginEntry('missing_plugin_entry'),

  /// The `.o` file declares no factory GUID nt_helper can read.
  noGuid('no_guid'),

  /// A GUID in the `.o` file already belongs to a different plug-in file or
  /// to a built-in algorithm.
  guidCollision('guid_collision'),

  /// The `.lua` file is not valid UTF-8 or contains NUL bytes.
  invalidLua('invalid_lua'),

  /// The algorithm list was still loading in the background when the wait
  /// for it ran out, so GUID collisions could not be checked.
  algorithmLibraryLoading('algorithm_library_loading');

  const PluginInstallRefusal(this.code);

  /// Stable snake_case error code reported to MCP clients.
  final String code;
}

/// Thrown by `DistingCubit.installPluginAndVerify` when the file or the
/// current session cannot accept a plugin upload. Nothing is sent to the
/// device.
class PluginInstallRefused implements Exception {
  const PluginInstallRefused(this.reason, this.message, [this.details]);

  /// Machine-readable reason.
  final PluginInstallRefusal reason;

  /// Human-readable explanation, suitable for showing to a client.
  final String message;

  /// Extra snake_case fields for the client, such as the conflicting GUID
  /// and existing plug-in for [PluginInstallRefusal.guidCollision].
  final Map<String, Object?>? details;

  @override
  String toString() => message;
}

/// One algorithm the device reported after the post-install rescan.
class InstalledPluginAlgorithm {
  const InstalledPluginAlgorithm({
    required this.guid,
    required this.name,
    required this.isLoaded,
  });

  /// Four-character algorithm GUID.
  final String guid;

  /// Algorithm name as reported by the device.
  final String name;

  /// Whether the plugin code is loaded into memory.
  final bool isLoaded;
}

/// Outcome of calling `loadPlugin` for one installed algorithm.
class PluginLoadResult {
  const PluginLoadResult({required this.guid, required this.loaded});

  /// GUID that was loaded.
  final String guid;

  /// Whether the device reported the algorithm as loaded afterwards.
  final bool loaded;
}

/// Everything `DistingCubit.installPluginAndVerify` learned about an upload.
class PluginInstallReport {
  const PluginInstallReport({
    required this.destinationPath,
    required this.bytesWritten,
    required this.presetReloaded,
    required this.cleanup,
    required this.filePresent,
    required this.expectedGuids,
    this.unattributedGuids = const [],
    required this.algorithms,
    required this.rescanAttempts,
    required this.loadResults,
  });

  /// Absolute SD card path the file was written to.
  final String destinationPath;

  /// Number of bytes uploaded.
  final int bytesWritten;

  /// True when the plugin was in use, so the preset was cleared for the
  /// upload and reloaded afterwards from its last saved copy on the SD card.
  final bool presetReloaded;

  /// Outcome of removing a same-GUID duplicate from the plug-ins root.
  final PluginCleanupOutcome cleanup;

  /// Whether the destination directory listing shows the file with the
  /// uploaded size. Null when the listing could not be read.
  final bool? filePresent;

  /// GUIDs read from the local `.o` file. Empty for Lua scripts.
  final List<String> expectedGuids;

  /// Expected GUIDs that an installed plug-in already used before the upload
  /// but whose file the device did not report, so a collision could not be
  /// ruled out.
  final List<String> unattributedGuids;

  /// Algorithms the device reported for this plugin's GUIDs after the
  /// rescan. Empty for Lua scripts.
  final List<InstalledPluginAlgorithm> algorithms;

  /// Number of algorithm-list reads made while waiting for the rescan.
  /// Zero for Lua scripts, which are not rescanned.
  final int rescanAttempts;

  /// One entry per algorithm when loading was requested, else empty.
  final List<PluginLoadResult> loadResults;

  /// Expected GUIDs that never appeared in the algorithm list.
  List<String> get missingGuids {
    final found = algorithms.map((a) => a.guid).toSet();
    return expectedGuids.where((guid) => !found.contains(guid)).toList();
  }
}
