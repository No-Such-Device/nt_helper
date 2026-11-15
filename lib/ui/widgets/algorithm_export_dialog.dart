import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nt_helper/services/algorithm_json_exporter.dart';
import 'package:nt_helper/db/database.dart';

class AlgorithmExportDialog extends StatefulWidget {
  final AppDatabase database;

  const AlgorithmExportDialog({super.key, required this.database});

  @override
  State<AlgorithmExportDialog> createState() => _AlgorithmExportDialogState();
}

class _AlgorithmExportDialogState extends State<AlgorithmExportDialog> {
  bool _isLoading = false;
  bool _isExporting = false;
  Map<String, dynamic>? _previewData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exporter = AlgorithmJsonExporter(widget.database);
      final preview = await exporter.getExportPreview();

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
        dialogTitle: 'Save Algorithm Details Export',
        fileName:
            'nt_algorithm_details_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json',
        bytes: await exporter.buildAlgorithmDetailsBytes(),
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
    return AlertDialog(
      title: const Row(
        children: [
          ExcludeSemantics(child: Icon(Icons.download, size: 24)),
          SizedBox(width: 8),
          Text('Export Algorithm Details'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export all algorithm details with parameters to a structured JSON file.',
              style: Theme.of(context).textTheme.bodyMedium,
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
                    Text('• ${_previewData!['totalAlgorithms']} algorithms'),
                    Text(
                      '• Estimated file size: ${_previewData!['estimatedSize']}',
                    ),
                    Text(
                      '• ${_previewData!['hasParameters'] ? 'Includes' : 'No'} parameter details',
                    ),
                    if ((_previewData!['sampleAlgorithms'] as List)
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sample algorithms:',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      for (final sample
                          in _previewData!['sampleAlgorithms'] as List<String>)
                        Text(
                          '  • $sample',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
          label: Text(_isExporting ? 'Exporting...' : 'Export'),
        ),
      ],
    );
  }
}
