import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nt_helper/interfaces/preset_file_system.dart';
import 'package:nt_helper/models/preset_dependencies.dart';
import 'package:nt_helper/models/package_config.dart';
import 'package:nt_helper/services/file_collector.dart';
import 'package:nt_helper/services/package_estimator.dart';
import 'package:nt_helper/services/preset_analyzer.dart';
import 'package:nt_helper/services/package_creator.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Dialog for creating preset packages
class PresetPackageDialog extends StatefulWidget {
  final String presetFilePath; // e.g., "presets/MyPreset.json"
  final PresetFileSystem fileSystem;

  /// Plugin GUID → SD-card file path map, sourced from live AlgorithmInfo.
  /// Required for community-plugin packaging — without it, plugin binaries
  /// cannot be located.
  final Map<String, String>? pluginPaths;

  const PresetPackageDialog({
    super.key,
    required this.presetFilePath,
    required this.fileSystem,
    this.pluginPaths,
  });

  @override
  State<PresetPackageDialog> createState() => _PresetPackageDialogState();
}

class _PresetPackageDialogState extends State<PresetPackageDialog> {
  PresetDependencies? dependencies;
  PackageSizeEstimate? estimate;
  bool isAnalyzing = false;
  bool isEstimating = false;
  bool isPackaging = false;
  String _status = '';
  FileProgressUpdate? _fileProgress;
  PackageConfig config = const PackageConfig();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _analyzeDependencies();
  }

  void _loadSettings() {
    final settings = SettingsService();
    config = config.copyWith(
      includeCommunityPlugins: settings.includeCommunityPlugins,
    );
  }

  Future<void> _analyzeDependencies() async {
    setState(() => isAnalyzing = true);

    try {
      // Load and parse preset JSON directly
      final presetBytes = await widget.fileSystem.readFile(
        widget.presetFilePath,
      );
      if (presetBytes == null) throw Exception('Preset file not found');

      final presetJson = utf8.decode(presetBytes);
      final presetData = jsonDecode(presetJson) as Map<String, dynamic>;

      final deps = PresetAnalyzer.analyzeDependencies(presetData);

      // If plugin paths were provided (from live AlgorithmInfo), add them
      if (widget.pluginPaths != null) {
        deps.pluginPaths.addAll(widget.pluginPaths!);
      }

      setState(() {
        dependencies = deps;
        isAnalyzing = false;
      });

      // Kick off size estimate now that we know the deps. This is
      // advisory only — the actual zip is built fresh when the user
      // clicks Export.
      _runEstimate();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error analyzing preset: $e')));
      setState(() => isAnalyzing = false);
    }
  }

  Future<void> _runEstimate() async {
    final deps = dependencies;
    if (deps == null) return;
    setState(() => isEstimating = true);
    try {
      final estimator = PackageEstimator(widget.fileSystem);
      final result = await estimator.estimate(deps, config: config);
      if (!mounted) return;
      setState(() {
        estimate = result;
        isEstimating = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Failure is non-fatal: dialog just shows "Size unknown".
      setState(() {
        estimate = null;
        isEstimating = false;
      });
    }
  }

  Future<void> _createPackage() async {
    setState(() {
      isPackaging = true;
      _fileProgress = null;
    });

    // Save context references before async operations.
    // `rootNavigator` is the parent that hosts this dialog — we use it
    // to show a follow-up warnings dialog after this one closes (this
    // dialog's own context will be defunct by then).
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    try {
      final presetName = widget.presetFilePath
          .split('/')
          .last
          .replaceAll('.json', '');
      final packageCreator = PackageCreator(widget.fileSystem);
      final packageResult = await packageCreator.createPackage(
        presetFilePath: widget.presetFilePath,
        config: config,
        onProgress: (status) => setState(() => _status = status),
        onFileProgress: (update) => setState(() => _fileProgress = update),
        estimatedFileCount: estimate?.fileCount,
        estimatedTotalBytes: estimate?.totalBytes,
        pluginPaths: widget.pluginPaths,
      );
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save Preset Package',
        fileName: '${presetName}_package.zip',
        mimeType: 'application/zip',
        bytes: packageResult.zipBytes,
      );

      if (outputPath != null) {
        navigator.pop();

        if (packageResult.hasWarnings && rootNavigator.mounted) {
          // Show in a dialog rather than a snackbar — warning lists can be
          // long (e.g. one entry per missing sample), and the user needs
          // to be able to read them all.
          await showDialog<void>(
            context: rootNavigator.context,
            builder: (ctx) =>
                _PackageWarningsDialog(warnings: packageResult.warnings),
          );
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error creating package: $e')),
      );
    } finally {
      if (mounted) setState(() => isPackaging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presetName = widget.presetFilePath.split('/').last;

    return AlertDialog(
      title: Semantics(header: true, child: Text('Package: $presetName')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isAnalyzing) ...[
                Center(
                  child: Semantics(
                    label: 'Analyzing preset dependencies',
                    child: const CircularProgressIndicator(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Analyzing preset dependencies...'),
              ] else if (dependencies != null) ...[
                Text('Dependencies found: ${dependencies!.totalCount}'),
                const SizedBox(height: 16),
                _buildDependencyList(),
                const SizedBox(height: 12),
                _buildSizeEstimate(),
                const SizedBox(height: 12),
                _buildConfigOptions(),
              ],
              if (isPackaging) ...[
                const SizedBox(height: 16),
                _buildPackagingProgress(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isPackaging ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: dependencies != null && !isPackaging
              ? _createPackage
              : null,
          child: isPackaging
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Package'),
        ),
      ],
    );
  }

  Widget _buildPackagingProgress() {
    final fp = _fileProgress;
    final totalFiles = fp?.filesTotal ?? estimate?.fileCount;
    final totalBytes = fp?.bytesTotal ?? estimate?.totalBytes;
    double? fraction;
    if (fp != null && totalBytes != null && totalBytes > 0) {
      fraction = (fp.bytesCompleted / totalBytes).clamp(0.0, 1.0);
    } else if (fp != null && totalFiles != null && totalFiles > 0) {
      fraction = (fp.filesCompleted / totalFiles).clamp(0.0, 1.0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 8),
        if (fp != null) ...[
          Text(
            'Reading: ${fp.currentPath}',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            totalFiles != null
                ? '${fp.filesCompleted}/$totalFiles files · '
                      '${_formatBytes(fp.bytesCompleted)}'
                      '${totalBytes != null ? ' / ${_formatBytes(totalBytes)}' : ''}'
                : '${fp.filesCompleted} files · ${_formatBytes(fp.bytesCompleted)}',
            style: const TextStyle(fontSize: 12),
          ),
        ] else ...[
          Text(_status, style: const TextStyle(fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildSizeEstimate() {
    if (isEstimating) {
      return Row(
        children: const [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Estimating package size...', style: TextStyle(fontSize: 12)),
        ],
      );
    }
    final est = estimate;
    if (est == null) {
      return const Text(
        'Estimated package size: unknown',
        style: TextStyle(fontSize: 12),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estimated package size: ${_formatBytes(est.totalBytes)} '
              '(${est.fileCount} files)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (est.warnings.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${est.warnings.length} item(s) could not be sized — '
                'estimate is a lower bound.',
                style: TextStyle(
                  fontSize: 11,
                  color: context.appColors.warning.color,
                ),
              ),
            ],
            if (est.folders.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final f in est.folders.take(8))
                Text(
                  '  ${f.path}: ${_formatBytes(f.bytes)} '
                  '(${f.fileCount} ${f.fileCount == 1 ? 'file' : 'files'})',
                  style: const TextStyle(fontSize: 11),
                ),
              if (est.folders.length > 8)
                Text(
                  '  …and ${est.folders.length - 8} more',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDependencyList() {
    if (dependencies == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dependencies:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (dependencies!.wavetables.isNotEmpty)
              Text('Wavetables: ${dependencies!.wavetables.length}'),
            if (dependencies!.sampleFolders.isNotEmpty)
              Text('Sample folders: ${dependencies!.sampleFolders.length}'),
            if (dependencies!.sampleFiles.isNotEmpty)
              Text('Sample files: ${dependencies!.sampleFiles.length}'),
            if (dependencies!.granulatorSamples.isNotEmpty)
              Text(
                'Granulator samples: ${dependencies!.granulatorSamples.length}',
              ),
            if (dependencies!.multisampleFolders.isNotEmpty)
              Text(
                'Multisample folders: ${dependencies!.multisampleFolders.length}',
              ),
            if (dependencies!.fmBanks.isNotEmpty)
              Text('FM banks: ${dependencies!.fmBanks.length}'),
            if (dependencies!.threePotPrograms.isNotEmpty)
              Text(
                'Three Pot programs: ${dependencies!.threePotPrograms.length}',
              ),
            if (dependencies!.luaScripts.isNotEmpty)
              Text('Lua scripts: ${dependencies!.luaScripts.length}'),
            if (dependencies!.bundleMidiTree)
              const Text('MIDI files: bundling /MIDI tree'),
            if (dependencies!.bundleSclTree || dependencies!.bundleKbmTree)
              const Text('Tuning files: bundling /scl + /kbm trees'),
            if (dependencies!.communityPlugins.isNotEmpty) ...[
              Text(
                'Community plugins: ${dependencies!.communityPlugins.length}',
              ),
              if (config.includeCommunityPlugins)
                Text(
                  '✓ Will be included in package',
                  style: TextStyle(
                    color: context.appColors.success.color,
                    fontSize: 12,
                  ),
                )
              else
                Text(
                  '⚠️ Requires manual installation',
                  style: TextStyle(
                    color: context.appColors.warning.color,
                    fontSize: 12,
                  ),
                ),
            ],
            if (dependencies!.isEmpty) const Text('No dependencies found'),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigOptions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Package Options:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Include Wavetables'),
              value: config.includeWavetables,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeWavetables: value)),
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('Include Samples & Multisamples'),
              value: config.includeSamples,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeSamples: value)),
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('Include FM Banks'),
              value: config.includeFMBanks,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeFMBanks: value)),
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('Include Three Pot Programs'),
              value: config.includeThreePot,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeThreePot: value)),
              dense: true,
            ),
            CheckboxListTile(
              title: const Text('Include Lua Scripts'),
              value: config.includeLua,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeLua: value)),
              dense: true,
            ),
            if (dependencies?.bundleMidiTree == true)
              CheckboxListTile(
                title: const Text('Include MIDI Files'),
                subtitle: const Text(
                  'Bundles entire /MIDI/ tree (firmware selects by index)',
                ),
                value: config.includeMidiTree,
                onChanged: (value) =>
                    _updateConfig(config.copyWith(includeMidiTree: value)),
                dense: true,
              ),
            if (dependencies?.bundleSclTree == true ||
                dependencies?.bundleKbmTree == true)
              CheckboxListTile(
                title: const Text('Include Scales (.scl / .kbm)'),
                subtitle: const Text('Bundles entire /scl/ and /kbm/ trees'),
                value: config.includeScales,
                onChanged: (value) =>
                    _updateConfig(config.copyWith(includeScales: value)),
                dense: true,
              ),
            CheckboxListTile(
              title: const Text('Include README'),
              value: config.includeReadme,
              onChanged: (value) =>
                  _updateConfig(config.copyWith(includeReadme: value)),
              dense: true,
            ),
            if (dependencies?.hasCommunityPlugins == true)
              CheckboxListTile(
                title: const Text('Include Community Plugins'),
                subtitle: const Text(
                  'Package community plugins with preset (default: on)',
                ),
                value: config.includeCommunityPlugins,
                onChanged: (value) {
                  _updateConfig(
                    config.copyWith(includeCommunityPlugins: value),
                  );
                  // Save preference for future exports
                  SettingsService().setIncludeCommunityPlugins(value ?? false);
                },
                dense: true,
              ),
          ],
        ),
      ),
    );
  }

  void _updateConfig(PackageConfig next) {
    setState(() => config = next);
    // Re-estimate when toggles change so the size summary stays in sync
    // with what the user actually plans to export.
    _runEstimate();
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Modal dialog that surfaces non-fatal warnings produced while
/// collecting dependency files for a preset package (missing files,
/// oversized files, read errors). The package was still written, but
/// some referenced content could not be included — the user needs to
/// see this so they know the package is incomplete.
class _PackageWarningsDialog extends StatelessWidget {
  final List<String> warnings;

  const _PackageWarningsDialog({required this.warnings});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Semantics(
        header: true,
        child: const Text('Package created with warnings'),
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The package was saved, but ${warnings.length} '
              '${warnings.length == 1 ? 'item was' : 'items were'} '
              'skipped or missing:',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Scrollbar(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: warnings.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${warnings[i]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
