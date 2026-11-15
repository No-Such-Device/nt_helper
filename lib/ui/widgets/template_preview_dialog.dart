import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';

/// Dialog that previews a template injection before applying it to the device.
///
/// Shows:
/// - Current preset slot summary
/// - Template algorithms to be added
/// - Result preview with slot ranges
/// - Warning if the preset slot limit would be exceeded
/// - Loading state during injection
/// - Error state if injection fails
class TemplatePreviewDialog extends StatefulWidget {
  final FullPresetDetails template;
  final int currentSlotCount;
  final MetadataSyncCubit syncCubit;
  final IDistingMidiManager manager;

  const TemplatePreviewDialog({
    super.key,
    required this.template,
    required this.currentSlotCount,
    required this.syncCubit,
    required this.manager,
  });

  /// Shows the template preview dialog and returns true if injection succeeded.
  static Future<bool?> show(
    BuildContext context,
    FullPresetDetails template,
    int currentSlotCount,
    MetadataSyncCubit syncCubit,
    IDistingMidiManager manager,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TemplatePreviewDialog(
        template: template,
        currentSlotCount: currentSlotCount,
        syncCubit: syncCubit,
        manager: manager,
      ),
    );
  }

  @override
  State<TemplatePreviewDialog> createState() => _TemplatePreviewDialogState();
}

class _TemplatePreviewDialogState extends State<TemplatePreviewDialog> {
  bool _isLoading = false;
  bool _isCancelled = false;
  String? _errorMessage;

  int get _templateSlotCount => widget.template.slots.length;
  int get _totalSlotsAfterInjection =>
      widget.currentSlotCount + _templateSlotCount;
  bool get _exceedsLimit =>
      _totalSlotsAfterInjection > DistingLimits.maxPresetSlots;

  @override
  Widget build(BuildContext context) {
    // Show loading state
    if (_isLoading) {
      return _buildLoadingDialog();
    }

    // Show error state
    if (_errorMessage != null) {
      return _buildErrorDialog();
    }

    // Show preview
    return _buildPreviewDialog();
  }

  Widget _buildPreviewDialog() {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Inject Template: ${widget.template.preset.name}'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.6,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current preset section
              _buildSectionHeader('Current Preset', theme),
              const SizedBox(height: 8),
              Text(
                '${widget.currentSlotCount} algorithm${widget.currentSlotCount == 1 ? '' : 's'}${widget.currentSlotCount > 0 ? ' (slots 1-${widget.currentSlotCount})' : ''}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              // Template section
              _buildSectionHeader('Template', theme),
              const SizedBox(height: 8),
              Text(
                '$_templateSlotCount algorithm${_templateSlotCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              // Algorithm list (scrollable if many)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _templateSlotCount,
                  itemBuilder: (context, index) {
                    final slot = widget.template.slots[index];
                    return ListTile(
                      dense: true,
                      leading: ExcludeSemantics(
                        child: Icon(
                          Icons.music_note,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        slot.algorithm.name,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Result section
              _buildSectionHeader('After Injection', theme),
              const SizedBox(height: 8),
              Text(
                '$_totalSlotsAfterInjection algorithm${_totalSlotsAfterInjection == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.currentSlotCount > 0 && _templateSlotCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Current: slots 1-${widget.currentSlotCount}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Template: slots ${widget.currentSlotCount + 1}-$_totalSlotsAfterInjection',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Warning section if limit exceeded
              if (_exceedsLimit) _buildWarningSection(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _exceedsLimit ? null : _handleInject,
          child: const Text('Inject Template'),
        ),
      ],
    );
  }

  Widget _buildLoadingDialog() {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Injecting ${widget.template.preset.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Adding $_templateSlotCount algorithm${_templateSlotCount == 1 ? '' : 's'} to device...',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: _handleCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _handleCancel() {
    if (_isLoading && !_isCancelled) {
      // Cancel the injection in the cubit
      widget.syncCubit.cancelInjection();

      setState(() {
        _isCancelled = true;
        _isLoading = false;
        _errorMessage =
            'Injection cancelled. Preset may be partially modified.';
      });
    }
  }

  Widget _buildErrorDialog() {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.error, color: theme.colorScheme.error),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Text('Injection Failed')),
        ],
      ),
      content: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _errorMessage!,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildWarningSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error, width: 2),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Cannot inject: Would exceed ${DistingLimits.maxPresetSlots} slot limit (current: ${widget.currentSlotCount}, template: $_templateSlotCount, total would be: $_totalSlotsAfterInjection)',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleInject() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Call the injection method from the cubit
      // This method emits presetLoadSuccess then calls loadLocalData which emits viewingLocalData
      await widget.syncCubit.injectTemplateToDevice(
        widget.template,
        widget.manager,
      );

      if (!mounted) return;

      // The injection completed without throwing, which means it succeeded
      // (If it failed, it would have thrown an exception)
      // Auto-close on success
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Error injecting template: ${e.toString()}';
      });
    }
  }
}
