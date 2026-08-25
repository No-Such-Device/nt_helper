import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show ParameterInfo;
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/sample_directory_listing_cache.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:path/path.dart' as path;

/// Enhanced file parameter editor widget that provides context-aware file browsing
class FileParameterEditor extends StatefulWidget {
  final Slot slot;
  final ParameterInfo parameterInfo;
  final int parameterNumber;
  final int currentValue;
  final Function(int) onValueChanged;
  final ParameterEditorRule rule;

  const FileParameterEditor({
    super.key,
    required this.slot,
    required this.parameterInfo,
    required this.parameterNumber,
    required this.currentValue,
    required this.onValueChanged,
    required this.rule,
  });

  @override
  State<FileParameterEditor> createState() => _FileParameterEditorState();
}

enum _DevelopmentState {
  inactive,
  monitoring,
  changed, // File changed, waiting for changes to settle
  uploading,
  reloading,
  error,
}

class _FileParameterEditorState extends State<FileParameterEditor> {
  late TextEditingController _textController;
  late final FocusNode _textInputFocusNode;
  String? _currentDisplayValue;
  bool _isEditingText = false;
  bool _isLoadingFiles = false;
  List<DirectoryEntry> _availableFiles = [];
  String? _currentDirectory;
  String? _selectedFolderName;
  String? _selectedFileName;
  int? _loadedSampleDirectoryCacheRevision;
  String? _sampleCatalogueError;
  bool _sampleCatalogueTraversalFailed = false;

  bool get _usesNtSampleFolderEnumeration =>
      widget.rule.ntSampleFolderEnumeration;

  String? get _zeroValueSentinelLabel => widget.rule.zeroValueSentinelLabel;

  bool get _hasZeroValueSentinel => _zeroValueSentinelLabel != null;

  bool get _loadsFromSelectedFolder =>
      widget.rule.mode == FileSelectionMode.fileOnly &&
      (widget.parameterInfo.name.toLowerCase().contains('sample') ||
          widget.parameterInfo.name.contains('File'));

  // Development mode state for Lua Script
  Timer? _fileWatchTimer;
  Timer? _debounceTimer;
  String? _developmentFilePath;
  DateTime? _lastModified;
  bool _isDragOver = false;
  _DevelopmentState _devState = _DevelopmentState.inactive;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textInputFocusNode = FocusNode(
      debugLabel: 'FileParameterEditor.textInput',
    );
    _currentDirectory = widget.rule.baseDirectory;
    _updateDisplayValue();
    if (widget.rule.mode != FileSelectionMode.textInput) {
      _loadDirectoryContents();
    } else {
      // For text input, initialize the controller with current value string
      final valueString = widget.slot.valueStrings.elementAtOrNull(
        widget.parameterNumber,
      );
      if (valueString != null && valueString.value.isNotEmpty) {
        _textController.text = valueString.value;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textInputFocusNode.dispose();
    _fileWatchTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Check if this is Lua Script Program parameter
  bool get _isLuaScriptProgram =>
      widget.slot.algorithm.guid == 'lua ' &&
      widget.parameterInfo.name == 'Program';

  @override
  void didUpdateWidget(FileParameterEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentValue != widget.currentValue) {
      _updateSelectedNameForValue(widget.currentValue);

      // For text input, update the display value
      if (widget.rule.mode == FileSelectionMode.textInput) {
        _updateDisplayValue();
      }
    }

    // Check if this is a Sample or MIDI Player file parameter and if the folder value changed
    if (_loadsFromSelectedFolder) {
      _checkForFolderChanges(oldWidget);
    }

    if (_usesNtSampleFolderEnumeration) {
      final oldHardwareName = _parameterValueString(
        oldWidget.slot,
        oldWidget.parameterNumber,
      );
      final newHardwareName = _parameterValueString(
        widget.slot,
        widget.parameterNumber,
      );
      if (newHardwareName != null && oldHardwareName != newHardwareName) {
        setState(() {
          _setSelectedName(newHardwareName);
          _updateDisplayValue();
        });
      }
    }

    // Check if value string changed for text parameters
    if (widget.rule.mode == FileSelectionMode.textInput) {
      final oldValueString =
          oldWidget.slot.valueStrings
              .elementAtOrNull(oldWidget.parameterNumber)
              ?.value ??
          '';
      final newValueString =
          widget.slot.valueStrings
              .elementAtOrNull(widget.parameterNumber)
              ?.value ??
          '';
      if (oldValueString != newValueString && !_isEditingText) {
        // Hardware confirmed the value - update our display
        setState(() {
          _currentDisplayValue = newValueString;
          _textController.text = newValueString;
        });
      }
    }
  }

  /// Finds the folder parameter that corresponds to the same trigger as this sample parameter.
  /// For per-trigger parameters, uses the naming pattern "N:ParameterName" (e.g., "1:Folder", "1:Sample")
  int _findCorrespondingFolderParameter() {
    final currentParamName = widget.parameterInfo.name;

    // Extract trigger number from current parameter name (e.g., "2:Sample" -> "2")
    final triggerMatch = RegExp(r'^(\d+):').firstMatch(currentParamName);
    if (triggerMatch != null) {
      final triggerNumber = triggerMatch.group(1)!;
      final expectedFolderParamName = '$triggerNumber:Folder';

      // Find the folder parameter for the same trigger
      final triggerFolderIndex = widget.slot.parameters.indexWhere(
        (p) => p.name == expectedFolderParamName,
      );

      // If found, return it; otherwise fall through to generic fallback
      if (triggerFolderIndex != -1) {
        return triggerFolderIndex;
      }
    }

    // Match qualified pairs such as "Lion sample" and "Lion folder".
    final sampleMatch = RegExp(r'^(.*)[Ss]ample$').firstMatch(currentParamName);
    if (sampleMatch != null) {
      final expectedFolderParamName = '${sampleMatch.group(1)!}folder'
          .toLowerCase();
      final qualifiedFolderIndex = widget.slot.parameters.indexWhere(
        (parameter) => parameter.name.toLowerCase() == expectedFolderParamName,
      );
      if (qualifiedFolderIndex != -1) {
        return qualifiedFolderIndex;
      }
    }

    // Shared folders apply to following sample parameters until another folder
    // parameter appears, as in a folder followed by several role samples.
    final currentParameterIndex = widget.slot.parameters.indexWhere(
      (parameter) =>
          parameter.parameterNumber == widget.parameterInfo.parameterNumber,
    );
    for (var index = currentParameterIndex - 1; index >= 0; index--) {
      final parameter = widget.slot.parameters[index];
      if (parameter.unit == ParameterUnits.modernHasStrings &&
          RegExp(r'[Ff]older$').hasMatch(parameter.name)) {
        return index;
      }
    }

    // Fallback for non-per-trigger parameters or when trigger-specific not found
    return widget.slot.parameters.indexWhere(
      (parameter) => parameter.name.toLowerCase().contains('folder'),
    );
  }

  void _checkForFolderChanges(FileParameterEditor oldWidget) {
    try {
      // Find the specific folder parameter for the same trigger as this sample parameter
      final folderParamIndex = _findCorrespondingFolderParameter();

      if (folderParamIndex == -1) return;

      final oldFolderValue = oldWidget.slot.values.length > folderParamIndex
          ? oldWidget.slot.values[folderParamIndex].value
          : -1;
      final newFolderValue = widget.slot.values.length > folderParamIndex
          ? widget.slot.values[folderParamIndex].value
          : -1;

      // If folder changed, reload directory contents
      if (oldFolderValue != newFolderValue) {
        _loadDirectoryContents();
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  void _updateDisplayValue() {
    _currentDisplayValue = _getDisplayValueForCurrentValue();

    if (widget.rule.mode == FileSelectionMode.textInput) {
      _textController.text = _currentDisplayValue ?? '';
    }
  }

  String? _parameterValueString(Slot slot, int parameterNumber) {
    final value = slot.valueStrings.elementAtOrNull(parameterNumber)?.value;
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  void _setSelectedName(String name) {
    switch (widget.rule.mode) {
      case FileSelectionMode.folderOnly:
        _selectedFolderName = _cleanDisplayName(name, isFolder: true);
        break;
      case FileSelectionMode.fileOnly:
      case FileSelectionMode.directFile:
      case FileSelectionMode.folderThenFile:
        _selectedFileName = _cleanDisplayName(name, isFolder: false);
        break;
      case FileSelectionMode.textInput:
        break;
    }
  }

  String? _getDisplayValueForCurrentValue() {
    final currentVal = widget.currentValue;
    if (_hasZeroValueSentinel && currentVal <= 0) {
      return _zeroValueSentinelLabel;
    }
    // Use min value to determine display offset: if min=0, show currentVal+1; if min=1, show currentVal
    final displayVal = widget.parameterInfo.min == 0
        ? currentVal + 1
        : currentVal;
    final hardwareName = _usesNtSampleFolderEnumeration
        ? _parameterValueString(widget.slot, widget.parameterNumber)
        : null;
    // Return actual resolved names if available, otherwise show loading or fallback
    switch (widget.rule.mode) {
      case FileSelectionMode.folderOnly:
        return _selectedFolderName ??
            hardwareName ??
            (_isLoadingFiles ? 'Loading...' : 'Folder $displayVal');
      case FileSelectionMode.fileOnly:
        return _selectedFileName ??
            hardwareName ??
            (_isLoadingFiles ? 'Loading...' : 'File $displayVal');
      case FileSelectionMode.directFile:
        return _selectedFileName ??
            (_isLoadingFiles ? 'Loading...' : 'Program $displayVal');
      case FileSelectionMode.folderThenFile:
        return _selectedFileName ??
            (_isLoadingFiles ? 'Loading...' : 'Item $displayVal');
      case FileSelectionMode.textInput:
        // For text input, we need to get the actual string value from the slot
        final valueString = widget.slot.valueStrings.elementAtOrNull(
          widget.parameterNumber,
        );
        if (valueString != null && valueString.value.isNotEmpty) {
          return valueString.value;
        }
        // Return empty string if no value is set
        return '';
    }
  }

  Future<void> _resolveCurrentValueToName() async {
    if (_currentDirectory == null || _availableFiles.isEmpty) return;

    final index = _entryIndexForParameterValue(widget.currentValue);

    if (index >= 0 && index < _availableFiles.length) {
      final entry = _availableFiles[index];
      final hardwareName = _parameterValueString(
        widget.slot,
        widget.parameterNumber,
      );
      if (_usesNtSampleFolderEnumeration &&
          widget.rule.mode == FileSelectionMode.folderOnly &&
          hardwareName != null &&
          !_folderNamesMatch(entry.name, hardwareName)) {
        setState(() {
          _sampleCatalogueError =
              'Folder catalogue order does not match the NT at value '
              '${widget.currentValue}. Refresh to retry.';
          _availableFiles = [];
          _setSelectedName(hardwareName);
          _updateDisplayValue();
        });
        return;
      }
      setState(() {
        _setSelectedName(entry.name);
        _updateDisplayValue();
      });
    }
  }

  bool _folderNamesMatch(String listedName, String hardwareName) {
    String normalize(String value) =>
        value.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    return normalize(listedName) == normalize(hardwareName);
  }

  void _incrementValue() {
    final incrementedValue = _hasZeroValueSentinel
        ? (widget.currentValue < 1 ? 1 : widget.currentValue + 1)
        : widget.currentValue + 1;
    final newValue = incrementedValue.clamp(
      widget.parameterInfo.min,
      widget.parameterInfo.max,
    );
    // Optimistic update - immediately update UI
    _updateSelectedNameForValue(newValue);
    // Then notify parent to update hardware
    widget.onValueChanged(newValue);
  }

  void _decrementValue() {
    final decrementedValue = _hasZeroValueSentinel
        ? (widget.currentValue <= 1 ? 0 : widget.currentValue - 1)
        : widget.currentValue - 1;
    final newValue = decrementedValue.clamp(
      widget.parameterInfo.min,
      widget.parameterInfo.max,
    );
    // Optimistic update - immediately update UI
    _updateSelectedNameForValue(newValue);
    // Then notify parent to update hardware
    widget.onValueChanged(newValue);
  }

  String _cleanDisplayName(String name, {required bool isFolder}) {
    String cleanName = name;

    // Remove trailing slash from folder names
    if (isFolder && cleanName.endsWith('/')) {
      cleanName = cleanName.substring(0, cleanName.length - 1);
    }

    // For recursive mode, show subdirectory structure
    if (widget.rule.recursive && cleanName.contains('/')) {
      // Keep the subdirectory path but clean up the display
      final parts = cleanName.split('/');
      if (parts.length > 1) {
        // Show as "subdir/filename" or "subdir1/subdir2/filename"
        cleanName = parts.join('/');
      }
    }

    // Remove file extensions for certain file types
    if (!isFolder && widget.rule.allowedExtensions != null) {
      for (final ext in widget.rule.allowedExtensions!) {
        if (cleanName.toLowerCase().endsWith(ext.toLowerCase())) {
          cleanName = cleanName.substring(0, cleanName.length - ext.length);
          break;
        }
      }
    }

    return cleanName;
  }

  void _updateSelectedNameForValue(int value) {
    if (_availableFiles.isEmpty) return;

    final index = _entryIndexForParameterValue(value);

    if (index >= 0 && index < _availableFiles.length) {
      final entry = _availableFiles[index];
      setState(() {
        switch (widget.rule.mode) {
          case FileSelectionMode.folderOnly:
            _selectedFolderName = _cleanDisplayName(entry.name, isFolder: true);
            break;
          case FileSelectionMode.fileOnly:
          case FileSelectionMode.directFile:
          case FileSelectionMode.folderThenFile:
            _selectedFileName = _cleanDisplayName(entry.name, isFolder: false);
            break;
          case FileSelectionMode.textInput:
            break; // Not applicable
        }
        _updateDisplayValue();
      });
    }
  }

  Future<void> _loadDirectoryContents() async {
    final cubit = context.read<DistingCubit>();
    final disting = cubit.disting();
    if (disting == null) return;

    setState(() {
      _isLoadingFiles = true;
      _sampleCatalogueError = null;
      _sampleCatalogueTraversalFailed = false;
    });
    final sampleCacheRevision = _usesNtSampleFolderEnumeration
        ? SampleDirectoryListingCache.shared.revisionFor(disting)
        : null;

    try {
      String? directoryToLoad = _currentDirectory;

      // Sample parameters load files from the paired folder parameter.
      if (_loadsFromSelectedFolder) {
        directoryToLoad = await _getSelectedFolderPath(disting);
      }

      if (directoryToLoad == null) {
        if (mounted) setState(() => _isLoadingFiles = false);
        return;
      }

      List<DirectoryEntry> allFiles = [];

      if (_usesNtSampleFolderEnumeration &&
          widget.rule.mode == FileSelectionMode.folderOnly) {
        allFiles = await _loadNtSampleFolderEntries(disting, directoryToLoad);
      } else if (widget.rule.recursive) {
        // Recursive search for files
        allFiles = await _loadDirectoryRecursive(disting, directoryToLoad, '');
      } else {
        // Single directory listing
        final listing = await _requestDirectoryListing(
          disting,
          directoryToLoad,
        );

        if (listing != null) {
          allFiles = listing.entries;
        }
      }

      if (mounted) {
        setState(() {
          final availableFiles = allFiles.where((entry) {
            // Filter out hidden files and system directories
            if (entry.name.startsWith('.')) return false;

            // Filter based on mode and allowed extensions
            switch (widget.rule.mode) {
              case FileSelectionMode.folderOnly:
                return entry.isDirectory &&
                    !widget.rule.excludeDirs.contains(
                      entry.name.replaceAll('/', ''),
                    );
              case FileSelectionMode.fileOnly:
              case FileSelectionMode.directFile:
                if (entry.isDirectory) return false;
                if (widget.rule.allowedExtensions?.isEmpty ?? true) {
                  return true;
                }
                return widget.rule.allowedExtensions!.any(
                  (ext) => entry.name.toLowerCase().endsWith(ext.toLowerCase()),
                );
              case FileSelectionMode.folderThenFile:
                // Show both folders and valid files
                if (entry.isDirectory) {
                  return !widget.rule.excludeDirs.contains(
                    entry.name.replaceAll('/', ''),
                  );
                }
                if (widget.rule.allowedExtensions?.isEmpty ?? true) {
                  return true;
                }
                return widget.rule.allowedExtensions!.any(
                  (ext) => entry.name.toLowerCase().endsWith(ext.toLowerCase()),
                );
              case FileSelectionMode.textInput:
                return false; // Not used for text input
            }
          }).toList();
          if (!(_usesNtSampleFolderEnumeration &&
              widget.rule.mode == FileSelectionMode.folderOnly)) {
            availableFiles.sort((a, b) {
              // For recursive mode, sort by full path
              // For non-recursive, sort directories first, then files
              if (!widget.rule.recursive && a.isDirectory != b.isDirectory) {
                return a.isDirectory ? -1 : 1;
              }
              // Then sort alphabetically
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          }
          if (_hasZeroValueSentinel) {
            availableFiles.insert(0, _zeroValueSentinelEntry());
          }
          if (_usesNtSampleFolderEnumeration &&
              widget.rule.mode == FileSelectionMode.folderOnly) {
            if (_sampleCatalogueTraversalFailed) {
              _sampleCatalogueError =
                  'Folder catalogue incomplete: an NT directory listing '
                  'failed. Refresh to retry.';
              availableFiles.clear();
            } else if (widget.rule.ntSampleFolderCountFromRange) {
              final expected = _folderValueCount(widget.parameterInfo);
              if (availableFiles.length != expected) {
                _sampleCatalogueError =
                    'Folder catalogue incomplete: found '
                    '${availableFiles.length} of $expected. Refresh to retry.';
                availableFiles.clear();
              }
            }
          }
          _availableFiles = availableFiles;
          _isLoadingFiles = false;
          _loadedSampleDirectoryCacheRevision = sampleCacheRevision;
        });

        // After loading, resolve the current value to actual name
        await _resolveCurrentValueToName();
      } else if (allFiles.isEmpty && mounted) {
        setState(() {
          _availableFiles = [];
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFiles = false;
        });
      }
    }
  }

  Future<String?> _getSelectedFolderPath(IDistingMidiManager disting) async {
    try {
      // Find the specific folder parameter for the same trigger as this sample parameter
      final folderParamIndex = _findCorrespondingFolderParameter();

      if (folderParamIndex == -1) {
        return _currentDirectory;
      }

      final folderValue = widget.slot.values[folderParamIndex].value;

      if (_currentDirectory == null) {
        return _currentDirectory;
      }

      final folders = _usesNtSampleFolderEnumeration
          ? await _loadNtSampleFolderEntries(disting, _currentDirectory!)
          : await _loadFlatFolderEntries(disting, _currentDirectory!);

      // Convert folder parameter value to array index using min value
      final folderParam = widget.slot.parameters[folderParamIndex];
      if (_usesNtSampleFolderEnumeration) {
        if (_sampleCatalogueTraversalFailed) {
          _sampleCatalogueError =
              'Folder catalogue incomplete: an NT directory listing failed. '
              'Refresh to retry.';
          return null;
        }
        if (widget.rule.ntSampleFolderCountFromRange) {
          final expected = _folderValueCount(folderParam);
          if (folders.length != expected) {
            _sampleCatalogueError =
                'Folder catalogue incomplete: found ${folders.length} of '
                '$expected. Refresh to retry.';
            return null;
          }
        }
      }
      final folderIndex = folderValue - folderParam.min;

      if (folderIndex >= 0 && folderIndex < folders.length) {
        final selectedFolder = folders[folderIndex].name.replaceAll(
          RegExp(r'/+$'),
          '',
        );
        return '$_currentDirectory/$selectedFolder';
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  int _folderValueCount(ParameterInfo parameter) =>
      parameter.max - parameter.min + 1;

  Future<void> _showFileSelectionDialog() async {
    await _reloadInvalidatedSampleDirectoryCache();
    if (!mounted) return;

    if (_availableFiles.isEmpty && !_isLoadingFiles) {
      // Try to load files first
      await _loadDirectoryContents();
      if (_availableFiles.isEmpty && !_usesNtSampleFolderEnumeration) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No ${widget.rule.mode == FileSelectionMode.folderOnly ? "folders" : "files"} found in ${_currentDirectory ?? "directory"}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    if (_isLoadingFiles) {
      return; // Don't show dialog while loading
    }

    if (_sampleCatalogueError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_sampleCatalogueError!)));
    }

    while (mounted) {
      final result = await showDialog<Object?>(
        context: context,
        builder: (context) => _FileSelectionDialog(
          availableFiles: _availableFiles,
          currentDirectory: _currentDirectory,
          currentValue: widget.currentValue,
          parameterInfo: widget.parameterInfo,
          rule: widget.rule,
          canRefresh: _usesNtSampleFolderEnumeration,
          emptyMessage: _sampleCatalogueError,
          cleanDisplayName: _cleanDisplayName,
          getFileIcon: _getFileIcon,
          formatFileSize: _formatFileSize,
        ),
      );
      if (!mounted) return;

      if (result == _FileSelectionDialogAction.refresh) {
        await _refreshSampleDirectoryCache();
        continue;
      }

      if (result is DirectoryEntry) {
        // Find the index of the selected entry and set the parameter value.
        final selectedIndex = _availableFiles.indexOf(result);
        if (selectedIndex != -1) {
          final newValue = _parameterValueForEntryIndex(selectedIndex);
          _updateSelectedNameForValue(newValue);
          widget.onValueChanged(newValue);
        }
      }
      return;
    }
  }

  Future<void> _reloadInvalidatedSampleDirectoryCache() async {
    if (!_usesNtSampleFolderEnumeration || _isLoadingFiles) return;

    final disting = context.read<DistingCubit>().disting();
    if (disting == null) return;
    final currentRevision = SampleDirectoryListingCache.shared.revisionFor(
      disting,
    );
    if (_loadedSampleDirectoryCacheRevision == currentRevision) return;

    await _loadDirectoryContents();
  }

  Future<void> _refreshSampleDirectoryCache() async {
    final cubit = context.read<DistingCubit>();
    final disting = cubit.disting();
    final rootPath = widget.rule.baseDirectory ?? _currentDirectory;
    if (disting == null || rootPath == null) return;

    await cubit.refreshSlot(widget.slot.algorithm.algorithmIndex);
    SampleDirectoryListingCache.shared.invalidateTree(disting, rootPath);
    await _loadDirectoryContents();
    if (!mounted) return;

    SemanticsService.sendAnnouncement(
      WidgetsBinding.instance.platformDispatcher.views.first,
      'Sample folder listing refreshed',
      TextDirection.ltr,
    );
  }

  Future<DirectoryListing?> _requestDirectoryListing(
    IDistingMidiManager disting,
    String path,
  ) {
    if (_usesNtSampleFolderEnumeration) {
      return SampleDirectoryListingCache.shared.request(disting, path);
    }
    return disting.requestDirectoryListing(path);
  }

  Future<List<DirectoryEntry>> _loadDirectoryRecursive(
    IDistingMidiManager disting,
    String basePath,
    String relativePath,
  ) async {
    final currentPath = relativePath.isEmpty
        ? basePath
        : '$basePath/$relativePath';
    final listing = await _requestDirectoryListing(disting, currentPath);

    if (listing == null) return [];

    List<DirectoryEntry> results = [];
    List<DirectoryEntry> directories = [];

    // Separate files and directories, sort alphabetically
    for (final entry in listing.entries) {
      if (entry.isDirectory) {
        final dirName = entry.name.replaceAll('/', '');
        if (!widget.rule.excludeDirs.contains(dirName)) {
          directories.add(entry);
        }
      } else {
        // Add files first (breadth-first approach)
        final fileName = relativePath.isEmpty
            ? entry.name
            : '$relativePath/${entry.name}';
        results.add(
          DirectoryEntry(
            name: fileName,
            size: entry.size,
            attributes: entry.attributes,
            date: entry.date,
            time: entry.time,
          ),
        );
      }
    }

    // Sort directories alphabetically
    directories.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // Then recurse into subdirectories (breadth-first)
    for (final dir in directories) {
      final dirName = dir.name.replaceAll('/', '');
      final subPath = relativePath.isEmpty ? dirName : '$relativePath/$dirName';
      final subResults = await _loadDirectoryRecursive(
        disting,
        basePath,
        subPath,
      );
      results.addAll(subResults);
    }

    return results;
  }

  Future<List<DirectoryEntry>> _loadFlatFolderEntries(
    IDistingMidiManager disting,
    String path,
  ) async {
    final listing = await _requestDirectoryListing(disting, path);
    if (listing == null) return [];
    return listing.entries
        .where(
          (entry) =>
              _isDirectoryEntry(entry) &&
              !_directoryEntryName(entry).startsWith('.'),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<List<DirectoryEntry>> _loadNtSampleFolderEntries(
    IDistingMidiManager disting,
    String basePath,
  ) async {
    final results = <DirectoryEntry>[];

    Future<DirectoryListing?> listingFor(String path) async {
      try {
        final listing = await _requestDirectoryListing(disting, path);
        if (listing == null) _sampleCatalogueTraversalFailed = true;
        return listing;
      } catch (_) {
        _sampleCatalogueTraversalFailed = true;
        return null;
      }
    }

    List<DirectoryEntry> directoriesFor(DirectoryListing listing) {
      return listing.entries.where((entry) {
        final name = _directoryEntryName(entry);
        if (name.isEmpty || name.startsWith('.')) return false;
        if (_looksLikeFileName(name)) return false;
        return !widget.rule.excludeDirs.contains(name);
      }).toList()..sort((a, b) {
        final aName = _directoryEntryName(a).toLowerCase();
        final bName = _directoryEntryName(b).toLowerCase();
        return aName.compareTo(bName);
      });
    }

    bool containsPlayableSample(DirectoryListing listing) {
      const supportedExtensions = ['.wav', '.aif', '.aiff'];
      return listing.entries.any((entry) {
        final name = _directoryEntryName(entry);
        if (name.isEmpty || name.startsWith('.')) return false;
        if (_isDirectoryEntry(entry)) return false;
        final lowerName = name.toLowerCase();
        return supportedExtensions.any(lowerName.endsWith);
      });
    }

    final rootListing = await listingFor(basePath);
    if (rootListing == null) return results;

    // The NT walks folders alphabetically and depth-first. A directory with
    // playable samples consumes one catalogue value and is treated as a leaf.
    // Otherwise its subdirectories are expanded in place; non-sample files do
    // not affect the traversal.
    Future<void> walk(
      String currentPath,
      String relativePath,
      DirectoryListing listing,
    ) async {
      for (final directory in directoriesFor(listing)) {
        final name = _directoryEntryName(directory);
        final childRelativePath = relativePath.isEmpty
            ? name
            : '$relativePath/$name';
        final childPath = '$currentPath/$name';
        final childListing = await listingFor(childPath);
        if (childListing == null) continue;

        if (containsPlayableSample(childListing)) {
          results.add(
            DirectoryEntry(
              name: childRelativePath,
              attributes: directory.attributes | 0x10,
              date: directory.date,
              time: directory.time,
              size: directory.size,
            ),
          );
        } else {
          await walk(childPath, childRelativePath, childListing);
        }
      }
    }

    await walk(basePath, '', rootListing);
    return results;
  }

  bool _isDirectoryEntry(DirectoryEntry entry) {
    return entry.isDirectory || entry.name.endsWith('/');
  }

  String _directoryEntryName(DirectoryEntry entry) {
    return entry.name.replaceAll(RegExp(r'/+$'), '');
  }

  bool _looksLikeFileName(String name) {
    return path.extension(name).isNotEmpty;
  }

  int _entryIndexForParameterValue(int value) {
    if (_hasZeroValueSentinel) {
      return value <= 0 ? 0 : value;
    }
    return value - widget.parameterInfo.min;
  }

  int _parameterValueForEntryIndex(int index) {
    if (_hasZeroValueSentinel) {
      return index <= 0 ? 0 : index;
    }
    return index + widget.parameterInfo.min;
  }

  DirectoryEntry _zeroValueSentinelEntry() {
    return DirectoryEntry(
      name: _zeroValueSentinelLabel!,
      attributes: 0,
      date: 0,
      time: 0,
      size: 0,
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.wav') || ext.endsWith('.aif') || ext.endsWith('.aiff')) {
      return Icons.audio_file;
    } else if (ext.endsWith('.lua')) {
      return Icons.code;
    } else if (ext.endsWith('.scl') ||
        ext.endsWith('.kbm') ||
        ext.endsWith('.syx')) {
      return Icons.music_note;
    }
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _onTextSubmitted(String value) async {
    // Optimistic update - immediately update UI
    setState(() {
      _isEditingText = false;
      _currentDisplayValue = value;
      _textController.text = value;
    });

    // Update the parameter string value through the cubit
    final cubit = context.read<DistingCubit>();

    // Use the cubit's updateParameterString method which handles the update flow
    await cubit.updateParameterString(
      algorithmIndex: widget.slot.algorithm.algorithmIndex,
      parameterNumber: widget.parameterNumber,
      value: value,
    );

    // The cubit will handle updating the hardware and refreshing the value
    // No need for a snackbar - the optimistic update provides immediate feedback
  }

  Widget _buildTextInputEditor() {
    if (_isEditingText) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: DigitShortcutBlocker(
                child: TextField(
                  controller: _textController,
                  focusNode: _textInputFocusNode,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Enter name...',
                    counterText: '', // Hide the character counter
                  ),
                  onSubmitted: _onTextSubmitted,
                  onEditingComplete: () {
                    _onTextSubmitted(_textController.text);
                  },
                  style: const TextStyle(fontSize: 16),
                  maxLength: 31, // Hardware limit for text parameters
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                _onTextSubmitted(_textController.text);
              },
              icon: const Icon(
                Icons.check,
                semanticLabel: 'Confirm text input',
              ),
              iconSize: 24,
              visualDensity: VisualDensity.compact,
              color: Theme.of(context).colorScheme.primary,
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _isEditingText = false;
                  _textController.text = _currentDisplayValue ?? '';
                });
              },
              icon: const Icon(Icons.close, semanticLabel: 'Cancel text input'),
              iconSize: 24,
              visualDensity: VisualDensity.compact,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      );
    }

    return Semantics(
      label: _currentDisplayValue?.isNotEmpty == true
          ? '${widget.parameterInfo.name}: $_currentDisplayValue. Tap to edit.'
          : '${widget.parameterInfo.name}: empty. Tap to edit.',
      button: true,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isEditingText = true;
            _textController.text = _currentDisplayValue ?? '';
          });
          // autofocus is unreliable when an ancestor Focus already holds
          // primary focus; explicitly grab it so key events stop here.
          _textInputFocusNode.requestFocus();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _currentDisplayValue?.isNotEmpty == true
                      ? _currentDisplayValue!
                      : '',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.edit,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileSelectionEditor() {
    final itemType = widget.rule.mode == FileSelectionMode.folderOnly
        ? 'folder'
        : 'file';
    final canGoPrev = _hasZeroValueSentinel
        ? widget.currentValue > 0
        : widget.currentValue > widget.parameterInfo.min;
    final canGoNext = widget.currentValue < widget.parameterInfo.max;

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Previous $itemType',
          enabled: canGoPrev,
          child: InkWell(
            onTap: canGoPrev ? _decrementValue : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.navigate_before,
                size: 24,
                color: canGoPrev
                    ? null
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: Semantics(
            label: 'Selected: ${_currentDisplayValue ?? "No selection"}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _getIconForMode(),
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentDisplayValue ?? 'No selection',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        Semantics(
          button: true,
          label: 'Next $itemType',
          enabled: canGoNext,
          child: InkWell(
            onTap: canGoNext ? _incrementValue : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.navigate_next,
                size: 24,
                color: canGoNext
                    ? null
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),

        const SizedBox(width: 8),

        Visibility(
          visible: _devState == _DevelopmentState.inactive,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Semantics(
            button: true,
            label: 'Browse ${itemType}s',
            child: InkWell(
              onTap: _isLoadingFiles ? null : _showFileSelectionDialog,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isLoadingFiles
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isLoadingFiles ? 'Loading...' : 'Browse',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  IconData _getIconForMode() {
    switch (widget.rule.mode) {
      case FileSelectionMode.folderOnly:
        return Icons.folder;
      case FileSelectionMode.fileOnly:
      case FileSelectionMode.directFile:
        return Icons.insert_drive_file;
      case FileSelectionMode.folderThenFile:
        return Icons.folder_open;
      case FileSelectionMode.textInput:
        return Icons.text_fields;
    }
  }

  Widget _buildDragOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_upload,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Drop .lua file for dev mode',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevModeIndicator() {
    return Positioned(
      top: 8,
      right: 8,
      child: Semantics(
        label: 'Development mode: ${_getStateText()}',
        button: true,
        child: GestureDetector(
          onTap: _toggleDevelopmentMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getStateColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getStateColor()),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStateIcon(),
                const SizedBox(width: 4),
                Text(_getStateText(), style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStateIcon() {
    switch (_devState) {
      case _DevelopmentState.monitoring:
        return const Icon(Icons.visibility, size: 16);
      case _DevelopmentState.changed:
        return const Icon(Icons.pending, size: 16);
      case _DevelopmentState.uploading:
      case _DevelopmentState.reloading:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _DevelopmentState.error:
        return const Icon(Icons.error_outline, size: 16);
      default:
        return const Icon(Icons.code, size: 16);
    }
  }

  Color _getStateColor() {
    switch (_devState) {
      case _DevelopmentState.monitoring:
        return context.appColors.success.color;
      case _DevelopmentState.changed:
        return context.appColors.warning.color;
      case _DevelopmentState.uploading:
      case _DevelopmentState.reloading:
        return context.appColors.info.color;
      case _DevelopmentState.error:
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String _getStateText() {
    switch (_devState) {
      case _DevelopmentState.monitoring:
        return 'Watching';
      case _DevelopmentState.changed:
        return 'Changed';
      case _DevelopmentState.uploading:
        return 'Uploading';
      case _DevelopmentState.reloading:
        return 'Reloading';
      case _DevelopmentState.error:
        return 'Error';
      default:
        return 'Dev Mode';
    }
  }

  Future<void> _handleScriptDrop(DropDoneDetails details) async {
    setState(() => _isDragOver = false);

    // Filter for .lua files only
    final luaFiles = details.files
        .where((file) => file.path.toLowerCase().endsWith('.lua'))
        .toList();

    if (luaFiles.isEmpty) {
      _showError('Please drop a .lua file');
      return;
    }

    if (luaFiles.length > 1) {
      _showError('Please drop only one file at a time');
      return;
    }

    final file = luaFiles.first;

    // Ask user if they want to enable development mode
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Development Mode?'),
        content: Text(
          'Monitor "${path.basename(file.path)}" for changes and '
          'automatically reload on the Disting NT?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _startDevelopmentMode(file.path);
    }
  }

  void _toggleDevelopmentMode() {
    if (_devState == _DevelopmentState.inactive) {
      // Can't start without a file - this shouldn't normally happen
      return;
    } else {
      // Stop development mode
      _stopDevelopmentMode();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _startDevelopmentMode(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showError('File does not exist: ${path.basename(filePath)}');
        return;
      }

      _developmentFilePath = filePath;
      _lastModified = await file.lastModified();

      setState(() {
        _devState = _DevelopmentState.monitoring;
      });

      // Start file monitoring with 1-second Timer.periodic
      _fileWatchTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (_developmentFilePath == null) return;

        try {
          final file = File(_developmentFilePath!);
          final currentModified = await file.lastModified();

          if (currentModified != _lastModified) {
            _lastModified = currentModified;
            _onFileChanged();
          }
        } catch (e) {
          if (mounted) {
            setState(() => _devState = _DevelopmentState.error);
          }
        }
      });
    } catch (e) {
      _showError('Failed to start development mode: $e');
    }
  }

  void _stopDevelopmentMode() {
    _fileWatchTimer?.cancel();
    _debounceTimer?.cancel();
    _fileWatchTimer = null;
    _debounceTimer = null;
    _developmentFilePath = null;
    _lastModified = null;

    setState(() {
      _devState = _DevelopmentState.inactive;
    });
  }

  void _onFileChanged() {
    // Cancel any existing debounce timer
    _debounceTimer?.cancel();

    // Set state to 'changed' to show user that changes were detected
    if (mounted) {
      setState(() => _devState = _DevelopmentState.changed);
    }

    // Start a new debounce timer - wait 3 seconds for changes to settle
    _debounceTimer = Timer(const Duration(seconds: 3), () async {
      if (mounted && _devState == _DevelopmentState.changed) {
        await _uploadAndReloadScript();
      }
    });
  }

  Future<void> _uploadAndReloadScript() async {
    if (_developmentFilePath == null) return;

    setState(() => _devState = _DevelopmentState.uploading);

    try {
      // Get current Program parameter value and cubit before async operations
      final currentValue = widget.currentValue;
      final cubit = context.read<DistingCubit>();

      // Read the modified script
      final file = File(_developmentFilePath!);
      final contents = await file.readAsBytes();
      final fileName = path.basename(_developmentFilePath!);

      // Upload to hardware using installPlugin
      await cubit.installPlugin(
        fileName,
        contents,
        onProgress: (progress) {
          // Progress is shown via the uploading state indicator
        },
      );

      if (!mounted) return;
      setState(() => _devState = _DevelopmentState.reloading);

      // Force reload using state-preserving method
      // This preserves all parameter values, routing, and mappings during reload
      await cubit.forceReloadLuaScriptWithStatePreservation(
        widget.slot.algorithm.algorithmIndex,
        widget.parameterNumber, // Program parameter number
        currentValue, // Current program value
      );

      if (mounted) {
        setState(() => _devState = _DevelopmentState.monitoring);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _devState = _DevelopmentState.error);
        _showError('Upload failed: $e');
      }

      // Don't stop monitoring on upload errors, allow retry
      Timer(const Duration(seconds: 3), () {
        if (_devState == _DevelopmentState.error && mounted) {
          setState(() => _devState = _DevelopmentState.monitoring);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.rule.mode == FileSelectionMode.textInput) {
      content = _buildTextInputEditor();
    } else {
      content = _buildFileSelectionEditor();
    }

    // Wrap with DropTarget if it's Lua Script Program on desktop
    if (_isLuaScriptProgram &&
        !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return DropTarget(
        onDragDone: _handleScriptDrop,
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        child: Stack(
          children: [
            content,
            if (_isDragOver) _buildDragOverlay(),
            if (_devState != _DevelopmentState.inactive)
              _buildDevModeIndicator(),
          ],
        ),
      );
    }

    return content;
  }
}

class _FileSelectionDialog extends StatefulWidget {
  final List<DirectoryEntry> availableFiles;
  final String? currentDirectory;
  final int currentValue;
  final ParameterInfo parameterInfo;
  final ParameterEditorRule rule;
  final bool canRefresh;
  final String? emptyMessage;
  final String Function(String, {required bool isFolder}) cleanDisplayName;
  final IconData Function(String) getFileIcon;
  final String Function(int) formatFileSize;

  const _FileSelectionDialog({
    required this.availableFiles,
    required this.currentDirectory,
    required this.currentValue,
    required this.parameterInfo,
    required this.rule,
    required this.canRefresh,
    required this.emptyMessage,
    required this.cleanDisplayName,
    required this.getFileIcon,
    required this.formatFileSize,
  });

  @override
  State<_FileSelectionDialog> createState() => _FileSelectionDialogState();
}

class _FileSelectionDialogState extends State<_FileSelectionDialog> {
  String _searchQuery = '';
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (_searchQuery.isNotEmpty) return;
    final selectedIndex = _selectedIndex;
    if (selectedIndex >= 0 && selectedIndex < widget.availableFiles.length) {
      const itemHeight = 36.0;
      final offset = selectedIndex * itemHeight;
      final maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, maxScroll));
    }
  }

  List<(int, DirectoryEntry)> get _filteredFiles {
    final indexed = widget.availableFiles.asMap().entries.map(
      (e) => (e.key, e.value),
    );
    if (_searchQuery.isEmpty) return indexed.toList();
    final query = _searchQuery.toLowerCase();
    return indexed.where((entry) {
      final name = widget.cleanDisplayName(
        entry.$2.name,
        isFolder: entry.$2.isDirectory,
      );
      return name.toLowerCase().contains(query);
    }).toList();
  }

  int get _selectedIndex {
    if (widget.rule.zeroValueSentinelLabel != null) {
      return widget.currentValue <= 0 ? 0 : widget.currentValue;
    }
    return widget.currentValue - widget.parameterInfo.min;
  }

  @override
  Widget build(BuildContext context) {
    final isFolder = widget.rule.mode == FileSelectionMode.folderOnly;
    final filtered = _filteredFiles;
    final selectedIndex = _selectedIndex;

    return AlertDialog(
      title: Row(
        children: [
          Text('Select ${isFolder ? 'Folder' : 'File'}'),
          if (widget.currentDirectory != null) ...[
            const Spacer(),
            Text(
              widget.currentDirectory!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(
          children: [
            DigitShortcutBlocker(
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? widget.emptyMessage ??
                                  'No ${isFolder ? 'folders' : 'files'} found'
                            : 'No matching ${isFolder ? 'folders' : 'files'}',
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      itemExtent: 36,
                      itemBuilder: (context, index) {
                        final (originalIndex, entry) = filtered[index];
                        final isSelected = originalIndex == selectedIndex;
                        final displayName = widget.cleanDisplayName(
                          entry.name,
                          isFolder: entry.isDirectory,
                        );

                        return InkWell(
                          onTap: () => Navigator.of(context).pop(entry),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            color: isSelected
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withValues(alpha: 0.5)
                                : null,
                            child: Row(
                              children: [
                                Icon(
                                  entry.isDirectory
                                      ? Icons.folder
                                      : widget.getFileIcon(entry.name),
                                  size: 18,
                                  color: entry.isDirectory
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    overflow: TextOverflow.ellipsis,
                                    style: isSelected
                                        ? const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          )
                                        : null,
                                  ),
                                ),
                                if (!entry.isDirectory)
                                  Text(
                                    widget.formatFileSize(entry.size),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.canRefresh)
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_FileSelectionDialogAction.refresh),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

enum _FileSelectionDialogAction { refresh }
