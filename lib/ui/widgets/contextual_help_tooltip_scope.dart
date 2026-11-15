import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/services/settings_service.dart';

/// Applies the contextual-help setting to descendant Flutter [Tooltip] widgets.
///
/// When contextual help is disabled, visual tooltip popups are made inert or
/// visually empty while preserving the tooltip widgets and their semantics for
/// assistive technologies.
class ContextualHelpTooltipScope extends StatelessWidget {
  const ContextualHelpTooltipScope({super.key, required this.child});

  final Widget child;

  static const TooltipThemeData _hiddenVisualTooltipTheme = TooltipThemeData(
    triggerMode: TooltipTriggerMode.manual,
    waitDuration: Duration(days: 1),
    constraints: BoxConstraints.tightFor(width: 0, height: 0),
    padding: EdgeInsets.zero,
    margin: EdgeInsets.zero,
    decoration: BoxDecoration(color: Colors.transparent),
    textStyle: TextStyle(color: Colors.transparent, fontSize: 0, height: 0),
    excludeFromSemantics: false,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().contextualHelpEnabledNotifier,
      builder: (context, enabled, child) {
        return TooltipTheme(
          data: enabled ? const TooltipThemeData() : _hiddenVisualTooltipTheme,
          child: child ?? const SizedBox.shrink(),
        );
      },
      child: child,
    );
  }
}
