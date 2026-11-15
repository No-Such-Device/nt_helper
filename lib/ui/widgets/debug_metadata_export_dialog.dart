import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nt_helper/services/algorithm_json_exporter.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// DEBUG ONLY: Dialog to export ALL metadata for bundling as an asset
class DebugMetadataExportDialog extends StatefulWidget {
  final AppDatabase database;

  const DebugMetadataExportDialog({super.key, required this.database});

  @override
  State<DebugMetadataExportDialog> createState() =>
      _DebugMetadataExportDialogState();
}

class _DebugMetadataExportDialogState extends State<DebugMetadataExportDialog> {
  bool _isLoading = false;
  bool _isExporting = false;
  Map<String, dynamic>? _previewData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) {
      // This dialog should only be accessible in debug mode
      Navigator.of(context).pop();
      return;
    }
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exporter = AlgorithmJsonExporter(widget.database);
      final preview = await exporter.getFullExportPreview();

      if (mounted) {
        setState(() {
          _previewData = preview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load export preview: $e';
        });
      }
    }
  }

  Future<void> _performExport() async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final exporter = AlgorithmJsonExporter(widget.database);
      final result = await FilePicker.saveFile(
        mimeType: 'application/json',
        dialogTitle: 'Save Full Metadata Export (DEBUG)',
        fileName: 'full_metadata.json',
        bytes: await exporter.buildFullMetadataBytes(),
      );
      if (result == null) {
        if (mounted) setState(() => _isExporting = false);
        return;
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = 'Export failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    final warning = context.appColors.warning;
    return AlertDialog(
      title: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.bug_report, size: 24, color: warning.color),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DEBUG: Export Full Metadata'),
              Text(
                'For bundling as app asset',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: warning.container,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: warning.color),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: warning.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DEBUG ONLY: Exports ALL metadata tables for pre-population',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: warning.onContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Preview section
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_previewData != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export Preview:',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_previewData!['tableCounts'] != null) ...[
                      Text(
                        'Tables to export:',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      ...(_previewData!['tableCounts'] as Map<String, dynamic>)
                          .entries
                          .map(
                            (e) => Text(
                              '  • ${e.key}: ${e.value} entries',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      const SizedBox(height: 8),
                    ],
                    if (_previewData!['estimatedSizeKB'] != null)
                      Text(
                        'Estimated size: ${_previewData!['estimatedSizeKB']} KB',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Instructions
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'After export:',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1. Create assets/metadata/ directory in project\n'
                    '2. Copy exported file there as full_metadata.json\n'
                    '3. Add to pubspec.yaml:\n'
                    '   assets:\n'
                    '     - assets/metadata/full_metadata.json\n'
                    '4. Rebuild app - metadata will auto-import on first launch',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: (_isExporting || _previewData == null)
              ? null
              : _performExport,
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 18),
          label: Text(_isExporting ? 'Exporting...' : 'Export Full Metadata'),
          style: ElevatedButton.styleFrom(
            backgroundColor: warning.color,
            foregroundColor: warning.onColor,
          ),
        ),
      ],
    );
  }
}
