import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Wraps [child] in a [Shortcuts] widget that swallows bare digit key presses
/// (and, optionally, the period key) so they cannot bubble up to parent
/// handlers that bind digits to application shortcuts (e.g., page navigation
/// on the main synchronized screen).
///
/// Why: on desktop, `FocusNode.onKeyEvent` at a parent focus node intercepts
/// digits before the focused `TextField` receives them. Flutter issue #107037
/// documents that returning `KeyEventResult.handled` from a higher focus node
/// breaks text input. Using `DoNothingAndStopPropagationTextIntent` inside the
/// Shortcuts widget that scopes the TextField lets the field consume the key
/// normally while preventing propagation.
class DigitShortcutBlocker extends StatelessWidget {
  const DigitShortcutBlocker({
    super.key,
    required this.child,
    this.includePeriod = false,
  });

  final Widget child;
  final bool includePeriod;

  static const List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final key in _digitKeys)
          SingleActivator(key): const DoNothingAndStopPropagationTextIntent(),
        if (includePeriod)
          const SingleActivator(LogicalKeyboardKey.period):
              const DoNothingAndStopPropagationTextIntent(),
      },
      child: child,
    );
  }
}
