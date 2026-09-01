import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:nt_helper/core/routing/bus_color_palette.dart';
import 'package:nt_helper/ui/widgets/routing/bus_picker_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

/// Reusable field for every bus-valued setting in the app.
class BusSelectionField extends StatelessWidget {
  final String label;
  final BusSelectionModel model;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const BusSelectionField({
    super.key,
    required this.label,
    required this.model,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentLabel = model.labelFor(model.currentValue);
    final validBus =
        model.currentValue > 0 && model.isSelectable(model.currentValue);

    final Color borderColor;
    final Color fillColor;
    if (validBus) {
      final base = BusColorPalette.baseColor(
        model.currentValue,
        isDark: isDark,
        deviceIoProfile: model.deviceIoProfile,
      );
      borderColor = base;
      fillColor = base.withValues(alpha: isDark ? 0.42 : 0.22);
    } else {
      final isUnavailable =
          model.currentValue < 0 ||
          (model.currentValue > 0 && !model.isSelectable(model.currentValue));
      borderColor = isUnavailable
          ? theme.colorScheme.error
          : theme.colorScheme.outline;
      fillColor = theme.colorScheme.surfaceContainerHighest;
    }

    final showDisconnect = model.allowNone && model.currentValue > 0 && enabled;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '$label: $currentLabel',
          button: true,
          enabled: enabled && model.hasSelectableValue,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled && model.hasSelectableValue
                      ? () => _openPicker(context)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.route_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          currentLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showDisconnect) ...[
          const SizedBox(width: 4),
          Semantics(
            label: 'Disconnect $label',
            button: true,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'Disconnect $label',
              onPressed: () => _select(context, 0),
              icon: const Icon(Icons.close_rounded, size: 16),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => BusPickerDialog(portLabel: label, model: model),
    );
    if (choice == null || choice == model.currentValue || !context.mounted) {
      return;
    }
    _select(context, choice);
  }

  void _select(BuildContext context, int value) {
    if (!model.isSelectable(value)) return;
    onChanged(value);
    SemanticsService.sendAnnouncement(
      View.of(context),
      '$label: ${model.labelFor(value)}',
      TextDirection.ltr,
    );
  }
}
