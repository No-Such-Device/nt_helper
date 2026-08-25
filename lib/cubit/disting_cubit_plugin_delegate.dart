part of 'disting_cubit.dart';

class _PluginDelegate {
  _PluginDelegate(this._cubit);

  final DistingCubit _cubit;

  /// Scans for Lua script plugins in the /programs/lua directory.
  /// Returns a sorted list of .lua files found.
  Future<List<PluginInfo>> fetchLuaPlugins() async {
    final currentState = _cubit.state;

    if (currentState is! DistingStateSynchronized || currentState.offline) {
      return [];
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      return [];
    }

    return _scanPluginDirectory(PluginType.lua);
  }

  /// Scans for 3pot plugins in the /programs/3pot directory.
  /// Returns a sorted list of .3pot files found.
  Future<List<PluginInfo>> fetch3potPlugins() async {
    final currentState = _cubit.state;

    if (currentState is! DistingStateSynchronized || currentState.offline) {
      return [];
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      return [];
    }

    return _scanPluginDirectory(PluginType.threePot);
  }

  /// Scans for C++ plugins in the /programs/plug-ins directory.
  /// Returns a sorted list of .o files found.
  Future<List<PluginInfo>> fetchCppPlugins() async {
    final currentState = _cubit.state;

    if (currentState is! DistingStateSynchronized || currentState.offline) {
      return [];
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      return [];
    }

    return _scanPluginDirectory(PluginType.cpp);
  }

  /// Helper method to scan a specific directory for files with a given extension.
  Future<List<PluginInfo>> _scanPluginDirectory(PluginType pluginType) async {
    final plugins = <PluginInfo>[];
    final disting = _cubit.requireDisting();
    await disting.requestWake();

    try {
      final pluginInfos = await _scanDirectoryForPlugins(
        pluginType.directory,
        pluginType,
      );
      plugins.addAll(pluginInfos);
    } catch (e) {
      // Intentionally swallowed - scanning errors shouldn't crash the app
    }

    // Sort by name
    plugins.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return plugins;
  }

  /// Recursively scans a directory for plugin files of a specific type.
  Future<List<PluginInfo>> _scanDirectoryForPlugins(
    String path,
    PluginType pluginType,
  ) async {
    final plugins = <PluginInfo>[];
    final disting = _cubit.requireDisting();

    try {
      final listing = await disting.requestDirectoryListing(path);
      if (listing != null) {
        for (final entry in listing.entries) {
          final newPath = path.endsWith('/')
              ? '$path${entry.name}'
              : '$path/${entry.name}';
          if (entry.isDirectory) {
            // Recursively scan subdirectories
            plugins.addAll(await _scanDirectoryForPlugins(newPath, pluginType));
          } else if (entry.name.toLowerCase().endsWith(
            pluginType.extension.toLowerCase(),
          )) {
            // Convert DOS date/time to DateTime if available
            DateTime? lastModified;
            try {
              if (entry.date != 0 && entry.time != 0) {
                final year = 1980 + (entry.date >> 9);
                final month = ((entry.date >> 5) & 0xF);
                final day = entry.date & 0x1F;
                final hour = entry.time >> 11;
                final minute = (entry.time >> 5) & 0x3F;
                final second = 2 * (entry.time & 0x1F);

                if (year > 1980 &&
                    month > 0 &&
                    month <= 12 &&
                    day > 0 &&
                    day <= 31) {
                  lastModified = DateTime(
                    year,
                    month,
                    day,
                    hour,
                    minute,
                    second,
                  );
                }
              }
            } catch (e) {
              // If date conversion fails, just use null
            }

            plugins.add(
              PluginInfo(
                name: entry.name,
                path: newPath,
                type: pluginType,
                sizeBytes: entry.size,
                lastModified: lastModified,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Intentionally swallowed - scanning errors shouldn't crash the app
    }

    return plugins;
  }

  /// Sends a delete command for a plugin file on the SD card.
  /// This is a fire-and-forget operation that assumes success.
  /// Only works when connected to a physical device (not offline/demo mode).
  Future<void> deletePlugin(PluginInfo plugin) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized || currentState.offline) {
      throw Exception("Cannot delete plugin: Not synchronized or offline.");
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      throw Exception("Firmware does not support SD card operations.");
    }

    final disting = _cubit.requireDisting();
    await disting.requestWake();

    // Send the delete command (fire-and-forget)
    await disting.requestFileDelete(plugin.path);
  }

  /// Uploads a plugin file to the appropriate directory on the SD card.
  /// Files are uploaded in 512-byte chunks to stay within SysEx message limits.
  /// Only works when connected to a physical device (not offline/demo mode).
  ///
  /// For gallery plugins, pass [galleryPluginId] and [galleryPluginVersion]
  /// to properly track the installation for update checking.
  Future<void> installPlugin(
    String fileName,
    Uint8List fileData, {
    Function(double)? onProgress,
    String? galleryPluginId,
    String? galleryPluginVersion,
  }) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized || currentState.offline) {
      throw Exception("Cannot install plugin: Not synchronized or offline.");
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      throw Exception("Firmware does not support SD card operations.");
    }

    // Determine the target directory based on file extension
    final extension = fileName.toLowerCase().split('.').last;
    String targetDirectory;
    switch (extension) {
      case 'lua':
        targetDirectory = '/programs/lua';
        break;
      case '3pot':
        targetDirectory = '/programs/three_pot';
        break;
      case 'o':
        targetDirectory = '/programs/plug-ins';
        break;
      default:
        throw Exception("Unsupported plugin file type: .$extension");
    }

    // Handle paths that already contain directory structure
    final String targetPath;
    if (fileName.contains('/')) {
      // Check if the fileName already starts with the expected directory structure
      final expectedPrefix = targetDirectory.substring(1); // Remove leading /
      if (fileName.startsWith(expectedPrefix)) {
        // The fileName already contains the full path structure, use it as-is
        targetPath = '/$fileName';
      } else {
        // The fileName contains directories but not the expected prefix
        targetPath = '$targetDirectory/$fileName';
      }
    } else {
      // Simple filename without directory structure
      targetPath = '$targetDirectory/$fileName';
    }

    // Ensure the parent directory of the final target path exists before uploading
    final disting = _cubit.requireDisting();
    await disting.requestWake();
    final parentPath = targetPath.substring(0, targetPath.lastIndexOf('/'));
    await _ensureDirectoryExists(parentPath, disting);

    // For C++ plugins (.o files), check if the plugin is currently in use
    // by any algorithm in the preset. If so, follow reference implementation
    // workflow: save preset, create blank preset to release plugin locks.
    String? savedPresetName;
    if (extension == 'o') {
      final isPluginInUse = _isPluginInUseByPreset(targetPath, currentState);
      if (isPluginInUse) {
        savedPresetName = currentState.presetName;
        await disting.requestNewPreset();
      }
    }

    // Upload in 512-byte chunks (matching JavaScript tool behavior)
    const chunkSize = 512;
    int uploadPos = 0;

    while (uploadPos < fileData.length) {
      final remainingBytes = fileData.length - uploadPos;
      final currentChunkSize = remainingBytes < chunkSize
          ? remainingBytes
          : chunkSize;
      final chunk = fileData.sublist(uploadPos, uploadPos + currentChunkSize);

      try {
        await _uploadChunk(targetPath, chunk, uploadPos);
        uploadPos += currentChunkSize;

        // Report progress
        final progress = uploadPos / fileData.length;
        onProgress?.call(progress);

        // Small delay between chunks to avoid overwhelming the device
        if (uploadPos < fileData.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (e) {
        throw Exception("Upload failed at position $uploadPos: $e");
      }
    }

    // For C++ plugins (.o files), complete the workflow:
    // - Always rescan plugins to make the new one available
    // - Invalidate algorithm info cache since plugin list changed
    // - If we did the preset dance (plugin was in use), reload the original preset
    if (extension == 'o') {
      try {
        // Brief delay to allow hardware to finish file operations
        await Future.delayed(const Duration(milliseconds: 200));
        await disting.requestRescanPlugins();
        // Invalidate algorithm info cache since plugins changed
        await _cubit._metadataDao.invalidateAlgorithmInfoCache();

        // Only reload preset if we did the preset dance (plugin was in use)
        if (savedPresetName != null) {
          final presetPath = '/presets/$savedPresetName.json';
          await disting.requestLoadPreset(presetPath, false);
        }
      } catch (e) {
        // Fire-and-forget: don't block on rescan/reload errors
      }
    }

    // Record the installation in the database (non-blocking - don't fail install on DB error)
    try {
      await _cubit.database.pluginInstallationsDao.recordPluginByPath(
        installationPath: targetPath,
        pluginName: fileName.split('/').last,
        pluginType: switch (extension) {
          'lua' => 'lua',
          '3pot' => 'threepot',
          'o' => 'cpp',
          _ => 'unknown',
        },
        totalBytes: fileData.length,
        pluginId: galleryPluginId,
        pluginVersion: galleryPluginVersion,
      );
    } catch (e) {
      // Intentionally swallowed - DB errors shouldn't fail installations
    }

    // Refresh state from manager to pick up any changes
    await _cubit._refreshStateFromManager();
  }

  /// Uploads a single chunk of file data.
  /// This mirrors the JavaScript tool's chunked upload implementation.
  Future<void> _uploadChunk(
    String targetPath,
    Uint8List chunkData,
    int position,
  ) async {
    final disting = _cubit.requireDisting();

    // Use chunked upload with position (first chunk creates the file)
    final createAlways = position == 0;
    final result = await disting.requestFileUploadChunk(
      targetPath,
      chunkData,
      position,
      createAlways: createAlways,
    );

    if (result == null || !result.success) {
      throw Exception(
        "Chunk upload failed: ${result?.message ?? 'Unknown error'}",
      );
    }
  }

  /// Checks if the plugin at the given path is currently in use by any
  /// algorithm in the preset.
  ///
  /// Returns true if any slot contains an algorithm whose source file
  /// matches the target path.
  bool _isPluginInUseByPreset(
    String targetPath,
    DistingStateSynchronized currentState,
  ) {
    // Find all algorithm GUIDs that correspond to plugins with this filename
    final matchingGuids = currentState.algorithms
        .where((algo) => algo.isPlugin && algo.filename == targetPath)
        .map((algo) => algo.guid)
        .toSet();

    if (matchingGuids.isEmpty) {
      // Plugin not in the available algorithms list (new plugin being installed)
      return false;
    }

    // Check if any slot uses one of these GUIDs
    return currentState.slots.any(
      (slot) => matchingGuids.contains(slot.algorithm.guid),
    );
  }

  /// Ensures the specified directory exists on the SD card, creating it if necessary.
  /// Handles parent directory creation as well.
  Future<void> _ensureDirectoryExists(
    String directoryPath,
    IDistingMidiManager disting,
  ) async {
    try {
      final listing = await disting.requestDirectoryListing(directoryPath);

      // A successful listing means the directory exists, even when it is empty.
      // The NT rejects attempts to create an existing empty directory.
      if (listing != null) {
        return;
      }
    } on SdCardOperationException catch (error) {
      if (error.operation != SdCardOperation.directoryListing) {
        rethrow;
      }
    }

    // Directory doesn't exist - need to create it
    // First ensure parent directory exists
    final parentPath = directoryPath.substring(
      0,
      directoryPath.lastIndexOf('/'),
    );
    if (parentPath.isNotEmpty) {
      await _ensureDirectoryExists(parentPath, disting);
    }

    // Now create this directory
    final result = await disting.requestDirectoryCreate(directoryPath);

    if (result == null || !result.success) {
      throw Exception(
        "Failed to create directory '$directoryPath': ${result?.message ?? 'Unknown error'}",
      );
    }
  }

  /// Backs up all plugins from the Disting NT to a local directory.
  /// Maintains the directory structure (/programs/lua, /programs/three_pot, /programs/plug-ins).
  Future<void> backupPlugins(
    String backupDirectory, {
    void Function(double progress, String currentFile)? onProgress,
  }) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized || currentState.offline) {
      throw Exception("Cannot backup plugins: Not synchronized or offline.");
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      throw Exception("Firmware does not support SD card operations.");
    }

    final disting = _cubit.requireDisting();
    await disting.requestWake();

    try {
      await disting.backupPlugins(backupDirectory, onProgress: onProgress);
    } catch (e) {
      rethrow;
    }
  }

  /// Install multiple files from a preset package in batch
  Future<void> installPackageFiles(
    List<PackageFile> files,
    Map<String, Uint8List> fileData, {
    Function(String fileName, int completed, int total)? onFileStart,
    Function(String fileName, double progress)? onFileProgress,
    Function(String fileName)? onFileComplete,
    Function(String fileName, String error)? onFileError,
  }) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized || currentState.offline) {
      throw Exception("Cannot install package: Not synchronized or offline.");
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      throw Exception("Firmware does not support SD card operations.");
    }

    final filesToInstall = files.where((f) => f.shouldInstall).toList();

    for (int i = 0; i < filesToInstall.length; i++) {
      final file = filesToInstall[i];
      final data = fileData[file.relativePath];

      if (data == null) {
        onFileError?.call(file.filename, 'File data not found');
        continue;
      }

      try {
        onFileStart?.call(file.filename, i + 1, filesToInstall.length);

        // Install the file directly to its target path
        await installFileToPath(
          file.targetPath,
          data,
          onProgress: (progress) =>
              onFileProgress?.call(file.filename, progress),
        );

        onFileComplete?.call(file.filename);
      } catch (e) {
        final errorMsg = "Failed to install ${file.filename}: $e";
        onFileError?.call(file.filename, errorMsg);
      }
    }
  }

  /// Install a single file to a specific path on the SD card
  Future<void> installFileToPath(
    String targetPath,
    Uint8List fileData, {
    Function(double)? onProgress,
  }) async {
    // Ensure absolute path for SD card operations
    final absolutePath = targetPath.startsWith('/')
        ? targetPath
        : '/$targetPath';

    final disting = _cubit.requireDisting();
    await disting.requestWake();

    // Ensure parent directory exists
    final parentPath = absolutePath.substring(0, absolutePath.lastIndexOf('/'));
    if (parentPath.isNotEmpty) {
      await _ensureDirectoryExists(parentPath, disting);
    }

    // Upload in 512-byte chunks (matching existing implementation)
    const chunkSize = 512;
    int uploadPos = 0;

    while (uploadPos < fileData.length) {
      final remainingBytes = fileData.length - uploadPos;
      final currentChunkSize = remainingBytes < chunkSize
          ? remainingBytes
          : chunkSize;
      final chunk = fileData.sublist(uploadPos, uploadPos + currentChunkSize);

      try {
        await _uploadChunk(absolutePath, chunk, uploadPos);
        uploadPos += currentChunkSize;

        // Report progress
        final progress = uploadPos / fileData.length;
        onProgress?.call(progress);

        // Small delay between chunks
        if (uploadPos < fileData.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (e) {
        throw Exception("Upload failed at position $uploadPos: $e");
      }
    }
  }

  /// Install a sample file to a specific path on the SD card, if it doesn't already exist.
  ///
  /// Returns `true` if the file was installed, `false` if it was skipped (already exists).
  /// Throws an exception on failure.
  ///
  /// This method:
  /// 1. Checks if the file already exists at the target path
  /// 2. If exists, returns false (skipped)
  /// 3. If not exists, creates parent directories and uploads the file
  Future<bool> installSampleFile(
    String targetPath,
    Uint8List fileData, {
    Function(double)? onProgress,
  }) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized || currentState.offline) {
      throw Exception("Cannot install sample: Not synchronized or offline.");
    }

    if (!FirmwareVersion(currentState.distingVersion).hasSdCardSupport) {
      throw Exception("Firmware does not support SD card operations.");
    }

    final disting = _cubit.requireDisting();
    await disting.requestWake();

    // Check if file already exists
    final fileExists = await _sampleFileExists(targetPath, disting);
    if (fileExists) {
      return false; // Skip - file already exists
    }

    // Ensure parent directory exists
    final parentPath = targetPath.substring(0, targetPath.lastIndexOf('/'));
    if (parentPath.isNotEmpty) {
      await _ensureDirectoryExists(parentPath, disting);
    }

    // Upload the file
    await installFileToPath(targetPath, fileData, onProgress: onProgress);

    return true; // Installed
  }

  /// Check if a sample file exists at the given path on the SD card
  ///
  /// Returns a tuple-like result:
  /// - `true` if the file exists (should skip)
  /// - `false` if the file doesn't exist (should upload)
  /// - throws if a directory exists at the file path (conflict)
  Future<bool> _sampleFileExists(
    String filePath,
    IDistingMidiManager disting,
  ) async {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash == -1) return false;

    final directory = filePath.substring(0, lastSlash);
    final filename = filePath.substring(lastSlash + 1);

    try {
      final listing = await disting.requestDirectoryListing(directory);
      if (listing == null || listing.entries.isEmpty) {
        return false;
      }

      // Check for exact filename match
      for (final entry in listing.entries) {
        if (entry.name == filename) {
          if (entry.isDirectory) {
            // A directory exists where we want to put a file - conflict
            throw Exception(
              'Cannot install sample: a directory exists at path $filePath',
            );
          }
          return true; // File exists
        }
      }
      return false; // File doesn't exist
    } catch (e) {
      // Re-throw our own exceptions (directory conflict)
      if (e.toString().contains('Cannot install sample')) {
        rethrow;
      }
      // If we can't check, assume file doesn't exist and try to upload
      return false;
    }
  }

  /// Load a plugin using the dedicated 0x38 Load Plugin SysEx command
  /// and refresh the specific algorithm info with updated specifications
  Future<AlgorithmInfo?> loadPlugin(String guid) async {
    final currentState = _cubit.state;
    if (currentState is! DistingStateSynchronized) {
      return null;
    }

    final disting = _cubit.requireDisting();

    // Find the algorithm by GUID
    final algorithmIndex = currentState.algorithms.indexWhere(
      (algo) => algo.guid == guid,
    );

    if (algorithmIndex == -1) {
      return null;
    }

    final algorithm = currentState.algorithms[algorithmIndex];

    // Check if it's already loaded
    if (algorithm.isLoaded) {
      return algorithm;
    }

    try {
      // 1. Send load plugin command
      await disting.requestLoadPlugin(guid);

      // Loading completes asynchronously on the hardware, so wait for the
      // updated specifications instead of requiring a second button press.
      AlgorithmInfo? updatedInfo;
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future.delayed(const Duration(seconds: 1));
        updatedInfo = await disting.requestAlgorithmInfo(
          algorithm.algorithmIndex,
        );
        if (updatedInfo?.guid == guid && updatedInfo?.isLoaded == true) break;
      }

      if (updatedInfo != null &&
          updatedInfo.guid == guid &&
          updatedInfo.isLoaded) {
        // 3. Update only this algorithm in the state
        final updatedAlgorithms = List<AlgorithmInfo>.from(
          currentState.algorithms,
        );
        updatedAlgorithms[algorithmIndex] = updatedInfo;

        _cubit._emitState(currentState.copyWith(algorithms: updatedAlgorithms));
        return updatedInfo;
      } else {
        // Loading failed - either couldn't get info or plugin didn't load
        return null;
      }
    } catch (e) {
      // Intentionally swallowed - plugin loading errors shouldn't crash the app
      return null;
    }
  }
}
