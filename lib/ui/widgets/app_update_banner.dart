import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/models/app_release.dart';

class AppUpdateBanner extends StatelessWidget {
  final AppRelease? release;
  final VoidCallback onWhatsNew;
  final VoidCallback onDismiss;

  static const _animationDuration = Duration(milliseconds: 200);

  const AppUpdateBanner({
    super.key,
    required this.release,
    required this.onWhatsNew,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = release != null;

    return Semantics(
      liveRegion: true,
      label: visible
          ? 'NT Helper ${release!.version} is available. Activate to see what\'s new.'
          : null,
      child: AnimatedContainer(
        duration: _animationDuration,
        height: visible ? 40 : 0,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: _animationDuration,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.system_update,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NT Helper ${release?.version ?? ""} available',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: onWhatsNew,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    "What's New",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: 'Dismiss update notification',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
