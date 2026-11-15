import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';

import '../../models/package_analysis.dart';
import '../../models/package_file.dart';
import '../../services/file_conflict_detector.dart';
import '../../services/preset_package_analyzer.dart';
import '../../cubit/disting_cubit.dart';
import '../theme/app_theme.dart';

/// Dialog for reviewing and resolving file conflicts when installing a preset package
class PackageInstallDialog extends StatefulWidget {
  final PackageAnalysis analysis;
  final Uint8List packageData;
  final DistingCubit distingCubit;
  final VoidCallback? onInstall;
  final VoidCallback? onCancel;

  const PackageInstallDialog({
    super.key,
    required this.analysis,
    required this.packageData,
    required this.distingCubit,
    this.onInstall,
    this.onCancel,
  });

  @override
  State<PackageInstallDialog> createState() => _PackageInstallDialogState();
}

class _PackageInstallDialogState extends State<PackageInstallDialog> {
  late PackageAnalysis _currentAnalysis;
  bool _isInstalling = false;
  String _currentFile = '';
  int _completedFiles = 0;
  int _totalFiles = 0;
  final List<String> _errors = [];

  @override
  void initState() {
    super.initState();
    _currentAnalysis = widget.analysis;
  }

  void _updateFileAction(String targetPath, FileAction action) {
    setState(() {
      _currentAnalysis = FileConflictDetector.updateFileAction(
        _currentAnalysis,
        targetPath,
        action,
      );
    });
  }

  void _setActionForConflicts(FileAction action) {
    setState(() {
      _currentAnalysis = FileConflictDetector.setActionForConflicts(
        _currentAnalysis,
        action,
      );
    });
  }

  void _setActionForAllFiles(FileAction action) {
    setState(() {
      _currentAnalysis = FileConflictDetector.setActionForAllFiles(
        _currentAnalysis,
        action,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.archive,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Install Package: ${_currentAnalysis.presetName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPackageInfo(),
            const SizedBox(height: 16),
            _buildActionButtons(),
            const SizedBox(height: 16),
            Expanded(child: _buildFileList()),
            const SizedBox(height: 16),
            if (_isInstalling)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _currentFile.isNotEmpty
                        ? 'Installing: $_currentFile ($_completedFiles/$_totalFiles)'
                        : 'Preparing installation...',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isInstalling ? null : () => widget.onCancel?.call(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isInstalling || _currentAnalysis.installCount == 0
              ? null
              : _handleInstall,
          child: Text('Install ${_currentAnalysis.installCount} Files'),
        ),
      ],
    );
  }

  Widget _buildPackageInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentAnalysis.presetName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text('by ${_currentAnalysis.author}'),
                      Text('Version ${_currentAnalysis.version}'),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${_currentAnalysis.totalFiles} files'),
                    if (_currentAnalysis.hasConflicts) ...[
                      Text(
                        '${_currentAnalysis.conflictCount} conflicts',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (!_currentAnalysis.hasConflicts) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Text('Bulk actions:', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Install All'),
                onPressed: () => _setActionForAllFiles(FileAction.install),
                avatar: const Icon(Icons.check_circle, size: 16),
              ),
              ActionChip(
                label: const Text('Skip Conflicts'),
                onPressed: () => _setActionForConflicts(FileAction.skip),
                avatar: const Icon(Icons.warning, size: 16),
              ),
              ActionChip(
                label: const Text('Skip All'),
                onPressed: () => _setActionForAllFiles(FileAction.skip),
                avatar: const Icon(Icons.cancel, size: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileList() {
    final filesByDirectory = _currentAnalysis.filesByDirectory;

    return ListView.builder(
      itemCount: filesByDirectory.length,
      itemBuilder: (context, index) {
        final directory = filesByDirectory.keys.elementAt(index);
        final files = filesByDirectory[directory]!;

        return ExpansionTile(
          title: Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.folder,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text('/$directory'),
              const SizedBox(width: 8),
              Chip(
                label: Text('${files.length}'),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          initiallyExpanded: files.any((f) => f.hasConflict),
          children: files.map((file) => _buildFileItem(file)).toList(),
        );
      },
    );
  }

  Widget _buildFileItem(PackageFile file) {
    final hasConflict = file.hasConflict;
    final willInstall = file.shouldInstall;

    return ListTile(
      dense: true,
      leading: Semantics(
        label: _getFileStatusDescription(file),
        child: CircleAvatar(
          radius: 12,
          backgroundColor: _getFileStatusColor(file),
          child: ExcludeSemantics(
            child: Icon(
              _getFileStatusIcon(file),
              size: 16,
              color: _getFileStatusForeground(file),
            ),
          ),
        ),
      ),
      title: Text(
        file.filename,
        style: TextStyle(
          decoration: willInstall ? null : TextDecoration.lineThrough,
          color: willInstall ? null : Theme.of(context).disabledColor,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(file.targetPath, style: Theme.of(context).textTheme.bodySmall),
          if (hasConflict)
            Text(
              'File exists on SD card',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      trailing: hasConflict
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  selected: willInstall,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Install'),
                    onPressed: () =>
                        _updateFileAction(file.targetPath, FileAction.install),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: willInstall
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface,
                      foregroundColor: willInstall
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      elevation: willInstall ? 2 : 0,
                      minimumSize: const Size(80, 32),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  selected: !willInstall,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Skip'),
                    onPressed: () =>
                        _updateFileAction(file.targetPath, FileAction.skip),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !willInstall
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.surface,
                      foregroundColor: !willInstall
                          ? Theme.of(context).colorScheme.onError
                          : Theme.of(context).colorScheme.onSurface,
                      elevation: !willInstall ? 2 : 0,
                      minimumSize: const Size(80, 32),
                    ),
                  ),
                ),
              ],
            )
          : Text(
              '${(file.size / 1024).toStringAsFixed(1)} KB',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    );
  }

  Color _getFileStatusColor(PackageFile file) {
    if (file.hasConflict) {
      return file.shouldInstall
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error;
    }
    return file.shouldInstall
        ? context.appColors.success.color
        : Theme.of(context).disabledColor;
  }

  Color _getFileStatusForeground(PackageFile file) {
    final scheme = Theme.of(context).colorScheme;
    if (file.hasConflict) {
      return file.shouldInstall ? scheme.onPrimary : scheme.onError;
    }
    return file.shouldInstall
        ? context.appColors.success.onColor
        : scheme.onSurfaceVariant;
  }

  IconData _getFileStatusIcon(PackageFile file) {
    if (file.hasConflict) {
      return file.shouldInstall ? Icons.download : Icons.skip_next;
    }
    return file.shouldInstall ? Icons.check : Icons.remove;
  }

  String _getFileStatusDescription(PackageFile file) {
    if (file.hasConflict) {
      return file.shouldInstall
          ? 'Conflict: will overwrite'
          : 'Conflict: will skip';
    }
    return file.shouldInstall ? 'Will install' : 'Will skip';
  }

  void _handleInstall() async {
    setState(() {
      _isInstalling = true;
      _totalFiles = _currentAnalysis.installCount;
      _completedFiles = 0;
      _currentFile = '';
      _errors.clear();
    });

    try {
      // Extract file data from package
      final fileData = await _extractFileData();

      // Install files using DistingCubit
      await widget.distingCubit.installPackageFiles(
        _currentAnalysis.files,
        fileData,
        onFileStart: (fileName, completed, total) {
          setState(() {
            _currentFile = fileName;
            _completedFiles = completed - 1; // completed is 1-based
          });
        },
        onFileComplete: (fileName) {
          setState(() {
            _completedFiles++;
          });
        },
        onFileError: (fileName, error) {
          setState(() {
            _errors.add('$fileName: $error');
            _isInstalling = false; // Stop progress bar
          });
        },
      );

      setState(() {
        _isInstalling = false;
      });

      // Check if there were any errors
      if (_errors.isNotEmpty) {
        _showErrorDialog();
      } else {
        // Installation completed successfully
        widget.onInstall?.call();
      }
    } catch (e) {
      setState(() {
        _isInstalling = false;
        _errors.add('Installation failed: $e');
      });

      _showErrorDialog();
    }
  }

  Future<Map<String, Uint8List>> _extractFileData() async {
    final fileData = <String, Uint8List>{};

    try {
      // Use the PresetPackageAnalyzer to extract individual files
      for (final file in _currentAnalysis.files) {
        if (file.shouldInstall) {
          final data = await PresetPackageAnalyzer.extractFile(
            widget.packageData,
            file.relativePath,
          );
          if (data != null) {
            fileData[file.relativePath] = data;
          }
        }
      }
    } catch (e) {
      throw Exception('Failed to extract files from package: $e');
    }

    return fileData;
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.error,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Installation Errors'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following errors occurred during installation:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: Scrollbar(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _errors.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.close,
                              size: 16,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errors[index],
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Successfully installed: $_completedFiles of $_totalFiles files',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close error dialog
              Navigator.of(context).pop(); // Close package dialog
              Navigator.of(context).pop(); // Close load preset dialog
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Simple dialog showing installation progress
class PackageInstallProgressDialog extends StatelessWidget {
  final String currentFile;
  final int completedFiles;
  final int totalFiles;
  final double progress;

  const PackageInstallProgressDialog({
    super.key,
    required this.currentFile,
    required this.completedFiles,
    required this.totalFiles,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Installing Package'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 16),
          Text('Installing: $currentFile'),
          const SizedBox(height: 8),
          Text('Progress: $completedFiles of $totalFiles files'),
        ],
      ),
    );
  }
}
