import 'package:material_ui/material_ui.dart';

/// Wraps a slot tab (top TabBar) and renders a tertiary-coloured single-line
/// box around it when the corresponding slot is in the algorithm-clipboard
/// selection.
///
/// Stateful so the `selected` flag is explicit and testable: tests read
/// [ClipboardSelectableTabState.selected] instead of inspecting the widget
/// tree's decorations.
///
/// Each instance must be uniquely keyed so Flutter does not reuse state across
/// slots when the tab list rebuilds. Pass a stable [ValueKey] derived from the
/// slot index.
class ClipboardSelectableTab extends StatefulWidget {
  const ClipboardSelectableTab({
    super.key,
    required this.selection,
    required this.slotIndex,
    required this.child,
    this.horizontalPadding = 8.0,
  });

  final ValueNotifier<Set<int>> selection;
  final int slotIndex;
  final Widget child;

  /// Horizontal padding inside the selection box. Reserved unconditionally
  /// so the tab/tile width does not shift when the selection toggles. Top
  /// tabs use the default 8px; the side list passes a tighter 4px.
  final double horizontalPadding;

  @override
  State<ClipboardSelectableTab> createState() => ClipboardSelectableTabState();
}

class ClipboardSelectableTabState extends State<ClipboardSelectableTab> {
  bool _selected = false;

  /// Whether this tab is currently marked for the clipboard. Exposed for
  /// tests so they can assert on selection state without inspecting the
  /// widget tree's decorations.
  bool get selected => _selected;

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_handleChanged);
    _selected = widget.selection.value.contains(widget.slotIndex);
  }

  @override
  void didUpdateWidget(covariant ClipboardSelectableTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_handleChanged);
      widget.selection.addListener(_handleChanged);
    }
    if (oldWidget.slotIndex != widget.slotIndex ||
        oldWidget.selection != widget.selection) {
      _handleChanged();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    final next = widget.selection.value.contains(widget.slotIndex);
    if (next != _selected) {
      setState(() => _selected = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The border is painted as a top-most overlay (inside an IgnorePointer so
    // it never intercepts hit-testing) rather than as a DecoratedBox behind
    // the child. This keeps it above sibling overlays like the side-list
    // action bar, whose ShaderMask would otherwise fade the border out.
    // The horizontal padding is reserved unconditionally so the tab/tile
    // width does not shift when the selection toggles.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    width: 1,
                    color: _selected
                        ? Theme.of(context).colorScheme.tertiary
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
