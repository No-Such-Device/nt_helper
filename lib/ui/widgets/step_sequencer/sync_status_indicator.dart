import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Sync status states for parameter synchronization
enum SyncStatus {
  /// All parameters synced with hardware
  synced,

  /// User actively editing, debounce pending
  editing,

  /// MIDI write in progress
  syncing,

  /// MIDI write failed
  error,

  /// Hardware disconnected, editing locally
  offline,
}

/// Displays sync status for Step Sequencer parameter changes
///
/// Shows a colored indicator dot with optional text label (desktop/tablet only).
/// Colors indicate current sync state:
/// - Green (synced): All changes written to hardware
/// - Orange (editing): User actively editing, pending debounce
/// - Blue (syncing): MIDI write in progress
/// - Red (error): Write failed, retry button appears
///
/// Supports responsive layouts:
/// - Desktop/Tablet (width > 768px): Dot + text label + retry button
/// - Mobile (width ≤ 768px): Dot only (compact)
class SyncStatusIndicator extends StatelessWidget {
  final SyncStatus status;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const SyncStatusIndicator({
    super.key,
    required this.status,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 768;
    final statusText = _getStatusText(status);
    final semanticLabel =
        'Sync status: $statusText'
        '${status == SyncStatus.error && errorMessage != null ? ". Error: $errorMessage" : ""}';

    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: isMobile ? 8 : 12,
              height: isMobile ? 8 : 12,
              decoration: BoxDecoration(
                color: _getStatusColor(context, status),
                shape: BoxShape.circle,
              ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ],
          if (status == SyncStatus.error && onRetry != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.refresh,
                size: 16,
                semanticLabel: 'Retry failed writes',
              ),
              onPressed: onRetry,
              tooltip: 'Retry failed writes',
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(BuildContext context, SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return context.appColors.success.color;
      case SyncStatus.editing:
        return context.appColors.warning.color;
      case SyncStatus.syncing:
        return context.appColors.info.color;
      case SyncStatus.error:
        return Theme.of(context).colorScheme.error;
      case SyncStatus.offline:
        return context.appColors.warning.color;
    }
  }

  String _getStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.editing:
        return 'Editing...';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.error:
        return 'Error';
      case SyncStatus.offline:
        return 'Offline';
    }
  }
}
