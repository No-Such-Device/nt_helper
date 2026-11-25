import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';

class SlotEditorModeSelector extends StatelessWidget {
  const SlotEditorModeSelector({
    super.key,
    required this.mode,
    required this.onSelected,
    this.controllerName,
    this.enabled = true,
    this.focusNodes,
  });

  final SlotEditorMode mode;
  final ValueChanged<SlotEditorMode> onSelected;
  final String? controllerName;
  final bool enabled;
  final Map<SlotEditorMode, FocusNode>? focusNodes;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Editor mode',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            key: const ValueKey('slot-editor-mode-standard'),
            mode: SlotEditorMode.standard,
            label: 'Standard parameter editor',
            semanticsLabel: 'Show standard parameter editor',
            hint: 'Shows the standard controls for this algorithm',
            icon: Icons.view_list_rounded,
          ),
          const SizedBox(width: 8),
          _button(
            key: const ValueKey('slot-editor-mode-spreadsheet'),
            mode: SlotEditorMode.spreadsheet,
            label: 'Spreadsheet parameter editor',
            semanticsLabel: 'Show spreadsheet parameter editor',
            hint: 'Shows numeric parameter names and value cells',
            icon: Icons.table_rows_rounded,
          ),
          if (controllerName != null) ...[
            const SizedBox(width: 8),
            _button(
              key: const ValueKey('slot-editor-mode-controller'),
              mode: SlotEditorMode.controller,
              label: controllerName!,
              semanticsLabel: 'Show ${controllerName!}',
              hint: 'Shows the alternate editor for this algorithm',
              icon: Icons.extension_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _button({
    required Key key,
    required SlotEditorMode mode,
    required String label,
    required String semanticsLabel,
    required String hint,
    required IconData icon,
  }) {
    final selected = this.mode == mode;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      hint: selected ? '$hint. Currently selected.' : hint,
      onTap: enabled ? () => onSelected(mode) : null,
      child: ExcludeSemantics(
        child: IconButton.filledTonal(
          key: key,
          focusNode: focusNodes?[mode],
          tooltip: label,
          isSelected: selected,
          onPressed: enabled ? () => onSelected(mode) : null,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
