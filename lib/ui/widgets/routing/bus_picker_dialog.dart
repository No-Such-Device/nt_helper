import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nt_helper/core/routing/bus_color_palette.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

/// Compact, color-coded bus picker for the Bus Lanes view.
///
/// Replaces the long `showMenu` dropdown with a grouped tile grid. Categories
/// are Inputs, Outputs, Aux, and (optionally) ES-5. Each tile is a 48×34
/// chip painted from [BusColorPalette.baseColor] for that bus.
///
/// Tapping a tile pops the dialog with the selected bus number; tapping
/// outside or pressing Esc dismisses with no selection.
class BusPickerDialog extends StatefulWidget {
  /// Display name of the port being routed (e.g. "Input 1", "Clock Out").
  final String portLabel;

  /// Fully classified choices and current-value validity.
  final BusSelectionModel model;

  const BusPickerDialog({
    super.key,
    required this.portLabel,
    required this.model,
  });

  @override
  State<BusPickerDialog> createState() => _BusPickerDialogState();
}

class _BusPickerDialogState extends State<BusPickerDialog> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _currentBusKey = GlobalKey();
  late final List<BusSelectionChoice> _inputs;
  late final List<BusSelectionChoice> _outputs;
  late final List<BusSelectionChoice> _aux;
  late final List<BusSelectionChoice> _es5;

  @override
  void initState() {
    super.initState();

    _inputs = widget.model.choicesFor(BusSelectionGroup.input);
    _outputs = widget.model.choicesFor(BusSelectionGroup.output);
    _aux = widget.model.choicesFor(BusSelectionGroup.aux);
    _es5 = widget.model.choicesFor(BusSelectionGroup.es5);

    WidgetsBinding.instance.addPostFrameCallback((_) => _centerCurrentBus());
  }

  void _centerCurrentBus() {
    if (!widget.model.isSelectable(widget.model.currentValue) ||
        widget.model.currentValue <= 0) {
      return;
    }
    final currentContext = _currentBusKey.currentContext;
    if (currentContext == null) return;
    Scrollable.ensureVisible(
      currentContext,
      alignment: 0.5,
      duration: Duration.zero,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Semantics(
            namesRoute: true,
            label: 'Bus picker',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          Icons.route_rounded,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Route ${widget.portLabel}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        MediaQuery.sizeOf(context).height * 0.65,
                        420.0,
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.model.allowNone)
                            _NoneSection(
                              selected: widget.model.currentValue == 0,
                              onTap: widget.model.currentValue == 0
                                  ? null
                                  : () => Navigator.of(context).pop(0),
                            ),
                          if (_inputs.isNotEmpty)
                            _section('Inputs', _inputs, theme),
                          if (_outputs.isNotEmpty)
                            _section('Outputs', _outputs, theme),
                          if (_aux.isNotEmpty) _section('Aux', _aux, theme),
                          if (_es5.isNotEmpty) _section('ES-5', _es5, theme),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Currently: ${widget.model.labelFor(widget.model.currentValue)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String header,
    List<BusSelectionChoice> choices,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                header,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final choice in choices)
                _BusTile(
                  key: choice.value == widget.model.currentValue
                      ? _currentBusKey
                      : null,
                  bus: choice.value,
                  label: choice.label,
                  deviceIoProfile: widget.model.deviceIoProfile,
                  selected: choice.value == widget.model.currentValue,
                  onTap: choice.value == widget.model.currentValue
                      ? null
                      : () => Navigator.of(context).pop(choice.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusTile extends StatefulWidget {
  final int bus;
  final String label;
  final DeviceIoProfile deviceIoProfile;
  final bool selected;
  final VoidCallback? onTap;
  const _BusTile({
    super.key,
    required this.bus,
    required this.label,
    required this.deviceIoProfile,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_BusTile> createState() => _BusTileState();
}

class _NoneSection extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  const _NoneSection({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    final borderWidth = selected ? 3.0 : 1.5;
    final fillColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'None',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Semantics(
                label: selected ? 'Current bus None' : 'Route to None',
                button: true,
                selected: selected,
                enabled: onTap != null,
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: borderColor, width: borderWidth),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onTap,
                    child: Container(
                      width: 48,
                      height: 34,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'None',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusTileState extends State<_BusTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = BusColorPalette.baseColor(
      widget.bus,
      isDark: isDark,
      deviceIoProfile: widget.deviceIoProfile,
    );
    final borderColor = widget.selected ? theme.colorScheme.primary : baseColor;
    final borderWidth = widget.selected ? 3.0 : (_hovered ? 2.0 : 1.5);
    final fillAlpha = widget.selected ? 0.45 : (_hovered ? 0.35 : 0.18);
    return Semantics(
      label: widget.selected
          ? 'Current bus ${widget.label}'
          : 'Route to ${widget.label}',
      button: true,
      selected: widget.selected,
      enabled: widget.onTap != null,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: widget.onTap,
          onHover: (h) {
            if (h != _hovered) setState(() => _hovered = h);
          },
          child: Container(
            width: 48,
            height: 34,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: fillAlpha),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}
