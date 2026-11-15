import 'package:material_ui/material_ui.dart';

/// A widget that displays contextual help text at the bottom of the screen.
/// Shows help hints when users hover over interactive elements.
class ContextualHelpBar extends StatelessWidget {
  final String? helpText;
  final Duration fadeDuration;

  const ContextualHelpBar({
    super.key,
    this.helpText,
    this.fadeDuration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHelp = helpText != null && helpText!.isNotEmpty;

    return Semantics(
      liveRegion: true,
      label: hasHelp ? helpText : null,
      child: AnimatedContainer(
        duration: fadeDuration,
        height: hasHelp ? 32 : 0,
        child: AnimatedOpacity(
          opacity: hasHelp ? 1.0 : 0.0,
          duration: fadeDuration,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    helpText ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A widget that wraps a child and provides hover-based contextual help.
/// When the user hovers over the child, the help text is shown in the
/// ContextualHelpBar via the provided callback.
class HelpHoverRegion extends StatelessWidget {
  final Widget child;
  final String helpText;
  final ValueChanged<String?> onHelpChanged;

  const HelpHoverRegion({
    super.key,
    required this.child,
    required this.helpText,
    required this.onHelpChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHelpChanged(helpText),
      onExit: (_) => onHelpChanged(null),
      child: child,
    );
  }
}
