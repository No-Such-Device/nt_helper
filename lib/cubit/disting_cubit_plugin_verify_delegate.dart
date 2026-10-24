part of 'disting_cubit.dart';

/// Installs a plugin and then confirms the result against the device, for
/// callers such as the MCP `install_plugin` tool that cannot watch the UI.
///
/// The upload itself is delegated unchanged to [_PluginDelegate.installPlugin];
/// this delegate adds the live-session guard, the SD listing check, an awaited
/// wait for the rescan, and the optional load.
class _PluginVerifyDelegate {
  _PluginVerifyDelegate(this._cubit);

  final DistingCubit _cubit;

  /// Uploads [fileData] as [fileName] (a `.o` or `.lua` file name) and reports
  /// what the device shows afterwards.
  ///
  /// Before anything is sent, throws [PluginInstallRefused] when:
  /// - a `.o` file is not a 32-bit little-endian ARM relocatable ELF that
  ///   defines `pluginEntry` and at least one readable factory GUID;
  /// - a `.lua` file is not valid UTF-8 or contains NUL bytes;
  /// - the app is not synchronized with live hardware whose firmware
  ///   supports SD writes;
  /// - for a `.o` file, the algorithm list is still loading in the
  ///   background after [libraryReadyTimeout], so the collision check would
  ///   see a partial list;
  /// - a GUID in the `.o` file already belongs to a built-in algorithm or to
  ///   a plug-in installed from a different file (see [_checkCollisions]).
  ///
  /// Upload failures from [_PluginDelegate.installPlugin] propagate unchanged.
  ///
  /// For `.o` files the algorithm list is re-read up to [maxRescanAttempts]
  /// times, [rescanPollInterval] apart, until every GUID found in the local
  /// file appears. When [load] is true each matching algorithm is then loaded
  /// with [_PluginDelegate.loadPlugin]. Lua scripts are not algorithms, so for
  /// them only the SD listing is checked.
  Future<PluginInstallReport> installPluginAndVerify(
    String fileName,
    Uint8List fileData, {
    bool load = false,
    int maxRescanAttempts = 5,
    Duration rescanPollInterval = const Duration(seconds: 1),
    Duration libraryReadyTimeout = const Duration(seconds: 10),
  }) async {
    final targetPath = PluginInstallationPath.target(fileName);
    final isObject = targetPath.toLowerCase().endsWith('.o');
    final expectedGuids = isObject
        ? _checkObject(fileData, fileName)
        : const <String>[];
    if (!isObject) _checkLua(fileData, fileName);
    _requireLiveSession();
    if (isObject) await _requireLoadedLibrary(libraryReadyTimeout);
    final state = _requireLiveSession();
    final unattributedGuids = _checkCollisions(
      expectedGuids,
      targetPath,
      state,
    );
    final presetReloaded =
        isObject &&
        _cubit._pluginDelegate._isPluginInUseByPreset(targetPath, state);

    final cleanup = await _cubit._pluginDelegate.installPlugin(
      fileName,
      fileData,
    );
    final filePresent = await _isListed(targetPath, fileData.length);

    var matches = <AlgorithmInfo>[];
    var attempts = 0;
    while (isObject && attempts < maxRescanAttempts) {
      if (attempts > 0) await Future.delayed(rescanPollInterval);
      attempts++;
      final algorithms = await _cubit._algorithmLibraryDelegate
          .refreshAlgorithmsNow();
      matches = algorithms
          .where((a) => expectedGuids.contains(a.guid))
          .toList();
      final found = matches.map((a) => a.guid).toSet();
      if (expectedGuids.every(found.contains)) break;
    }

    final loadResults = <PluginLoadResult>[];
    if (load) {
      for (final algorithm in matches) {
        final loaded = await _cubit._pluginDelegate.loadPlugin(algorithm.guid);
        loadResults.add(
          PluginLoadResult(
            guid: algorithm.guid,
            loaded: loaded?.isLoaded ?? false,
          ),
        );
      }
    }

    return PluginInstallReport(
      destinationPath: targetPath,
      bytesWritten: fileData.length,
      presetReloaded: presetReloaded,
      cleanup: cleanup,
      filePresent: filePresent,
      expectedGuids: expectedGuids,
      unattributedGuids: unattributedGuids,
      algorithms: [
        for (final a in matches)
          InstalledPluginAlgorithm(
            guid: a.guid,
            name: a.name,
            isLoaded: a.isLoaded,
          ),
      ],
      rescanAttempts: attempts,
      loadResults: loadResults,
    );
  }

  /// Returns the synchronized live state or throws [PluginInstallRefused].
  DistingStateSynchronized _requireLiveSession() {
    final state = _cubit.state;
    if (state is! DistingStateSynchronized) {
      throw const PluginInstallRefused(
        PluginInstallRefusal.notConnected,
        'No Disting NT is connected and synchronized.',
      );
    }
    if (state.demo) {
      throw const PluginInstallRefused(
        PluginInstallRefusal.demo,
        'Demo mode has no device to install to. Connect a Disting NT.',
      );
    }
    if (state.offline) {
      throw const PluginInstallRefused(
        PluginInstallRefusal.offline,
        'Offline mode has no device to install to. Connect a Disting NT.',
      );
    }
    if (!FirmwareVersion(state.distingVersion).hasSdCardSupport) {
      throw const PluginInstallRefused(
        PluginInstallRefusal.noSdCardSupport,
        'The connected firmware does not support SD card writes.',
      );
    }
    return state;
  }

  /// Waits up to [timeout] for any background algorithm-list load to finish,
  /// then throws [PluginInstallRefused] if one is still running. Until it
  /// finishes, `state.algorithms` can be empty or missing plug-ins, and a
  /// collision check against it could miss an existing GUID.
  Future<void> _requireLoadedLibrary(Duration timeout) async {
    final library = _cubit._algorithmLibraryDelegate;
    if (await library.waitForBackgroundLoads(timeout)) return;
    throw PluginInstallRefused(
      PluginInstallRefusal.algorithmLibraryLoading,
      'The algorithm list is still loading from the device after '
      '${timeout.inSeconds} s, so GUID collisions cannot be checked yet. '
      'Nothing was uploaded. Retry in a few seconds.',
    );
  }

  /// Whether [targetPath]'s directory lists the file with [size] bytes, or
  /// null when the listing cannot be read.
  Future<bool?> _isListed(String targetPath, int size) async {
    final slash = targetPath.lastIndexOf('/');
    final name = targetPath.substring(slash + 1);
    try {
      final listing = await _cubit.requireDisting().requestDirectoryListing(
        targetPath.substring(0, slash),
      );
      if (listing == null) return null;
      return listing.entries.any(
        (e) => !e.isDirectory && e.name == name && e.size == size,
      );
    } catch (_) {
      return null;
    }
  }

  /// Checks that [bytes] can be loaded by the NT as a C++ plug-in and
  /// returns its factory GUIDs, or throws [PluginInstallRefused].
  ///
  /// The NT links plug-ins itself, so it needs an unlinked (ET_REL) 32-bit
  /// little-endian ARM object that defines `pluginEntry`. A readable GUID is
  /// required too: without one nt_helper cannot confirm the rescan or check
  /// for collisions.
  List<String> _checkObject(Uint8List bytes, String fileName) {
    final PluginObjectInfo info;
    try {
      info = ElfGuidExtractor.inspectPluginObject(bytes, fileName);
    } on GuidExtractionException catch (e) {
      throw PluginInstallRefused(PluginInstallRefusal.invalidElf, e.message);
    }
    if (!info.isArm32LittleEndian) {
      throw PluginInstallRefused(
        PluginInstallRefusal.wrongArchitecture,
        '$fileName is ${info.is32Bit ? '32' : '64'}-bit '
        '${info.isLittleEndian ? 'little' : 'big'}-endian '
        '${info.machine.name}; the Disting NT needs 32-bit little-endian '
        'EM_ARM. Build with the ARM toolchain from distingNT_API.',
      );
    }
    if (info.fileType != ElfFileType.relocatable) {
      throw PluginInstallRefused(
        PluginInstallRefusal.notRelocatable,
        '$fileName is ${info.fileType.name}; the Disting NT loads relocatable '
        'objects (ET_REL). Compile with -c and do not link.',
      );
    }
    if (!info.hasPluginEntry) {
      throw PluginInstallRefused(
        PluginInstallRefusal.missingPluginEntry,
        '$fileName does not define ${ElfGuidExtractor.pluginEntrySymbol}. '
        'Declare the plug-in with NT_DECLARE_PLUGIN from distingNT_API.',
      );
    }
    if (info.guids.isEmpty) {
      throw PluginInstallRefused(
        PluginInstallRefusal.noGuid,
        '$fileName has no factory GUID nt_helper can read. Factories must be '
        'named factory (static or not) or Factory inside a class or '
        'namespace, and start with a 4-character printable GUID.',
      );
    }
    return info.guids.map((g) => g.guid).toList();
  }

  /// Throws [PluginInstallRefused] unless [bytes] is UTF-8 without NUL bytes.
  void _checkLua(Uint8List bytes, String fileName) {
    final nul = bytes.indexOf(0);
    if (nul != -1) {
      throw PluginInstallRefused(
        PluginInstallRefusal.invalidLua,
        '$fileName contains a NUL byte at offset $nul; Lua scripts must be '
        'plain text.',
      );
    }
    try {
      utf8.decode(bytes);
    } on FormatException catch (e) {
      throw PluginInstallRefused(
        PluginInstallRefusal.invalidLua,
        '$fileName is not valid UTF-8 (${e.message} at offset ${e.offset}).',
      );
    }
  }

  /// Refuses a GUID that the synchronized algorithm list already attributes
  /// to a built-in algorithm or to a plug-in in a different file. Reinstalling
  /// the same file is allowed.
  ///
  /// A plug-in whose file the device did not report cannot be attributed, so
  /// its GUIDs are returned rather than refused: refusing would block every
  /// reinstall on such firmware, and the post-rescan check still reports what
  /// the device lists.
  List<String> _checkCollisions(
    List<String> guids,
    String targetPath,
    DistingStateSynchronized state,
  ) {
    final unattributed = <String>[];
    for (final guid in guids) {
      for (final existing in state.algorithms.where((a) => a.guid == guid)) {
        final file = existing.filename;
        if (existing.isPlugin && file == null) {
          unattributed.add(guid);
          continue;
        }
        if (existing.isPlugin && _samePluginFile(file!, targetPath)) continue;
        throw PluginInstallRefused(
          PluginInstallRefusal.guidCollision,
          existing.isPlugin
              ? 'GUID $guid is already used by ${existing.name} from $file. '
                    'Give this plug-in a unique GUID, or delete the other file.'
              : 'GUID $guid is already used by the built-in algorithm '
                    '${existing.name}. Give this plug-in a unique GUID.',
          {
            'guid': guid,
            'existing_name': existing.name,
            'existing_kind': existing.isPlugin ? 'plugin' : 'built_in',
            'existing_path': file,
          },
        );
      }
    }
    return unattributed.toSet().toList();
  }

  /// Whether [reported] (as the device names a plug-in file) and [target]
  /// (an absolute `/programs/plug-ins/...` path) are the same file. FAT is
  /// case-insensitive and the reported path may lack the leading slash.
  bool _samePluginFile(String reported, String target) {
    String key(String p) {
      final trimmed = p.toLowerCase().replaceFirst(RegExp('^/+'), '');
      const root = 'programs/plug-ins/';
      return trimmed.startsWith(root)
          ? trimmed.substring(root.length)
          : trimmed;
    }

    return key(reported) == key(target);
  }
}
