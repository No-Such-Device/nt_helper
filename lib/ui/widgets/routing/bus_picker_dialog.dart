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

  /// Caller-owned selection animation. When null, the dialog creates and
  /// runs its own endlessly repeating fade.
  final Animation<double>? selectionAnimation;

  const BusPickerDialog({
    super.key,
    required this.portLabel,
    required this.model,
    this.selectionAnimation,
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
      child: SizedBox(
        key: const Key('bus-picker-dialog-surface'),
        width: 488,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 4, 16),
          child: Semantics(
            namesRoute: true,
            label: 'Bus picker',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Semantics(
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
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: Scrollbar(
                        controller: _scrollController,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.model.allowNone)
                                  _NoneSection(
                                    selected: widget.model.currentValue == 0,
                                    selectionAnimation:
                                        widget.selectionAnimation,
                                    onTap: widget.model.currentValue == 0
                                        ? null
                                        : () => Navigator.of(context).pop(0),
                                  ),
                                if (_inputs.isNotEmpty)
                                  _section('Inputs', _inputs, theme),
                                if (_outputs.isNotEmpty)
                                  _section('Outputs', _outputs, theme),
                                if (_aux.isNotEmpty)
                                  _section('Aux', _aux, theme),
                                if (_es5.isNotEmpty)
                                  _section('ES-5', _es5, theme),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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
                  selectionAnimation: widget.selectionAnimation,
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
  final Animation<double>? selectionAnimation;
  final VoidCallback? onTap;
  const _BusTile({
    super.key,
    required this.bus,
    required this.label,
    required this.deviceIoProfile,
    required this.selected,
    required this.selectionAnimation,
    required this.onTap,
  });

  @override
  State<_BusTile> createState() => _BusTileState();
}

class _NoneSection extends StatelessWidget {
  final bool selected;
  final Animation<double>? selectionAnimation;
  final VoidCallback? onTap;
  const _NoneSection({
    required this.selected,
    required this.selectionAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              _SelectedBusFade(
                selected: selected,
                animation: selectionAnimation,
                builder: (context, emphasis) {
                  final selectionColor = selected
                      ? Color.lerp(
                          theme.colorScheme.primary.withValues(alpha: 0),
                          theme.colorScheme.primary,
                          emphasis,
                        )!
                      : theme.colorScheme.outline;
                  final fillColor = selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.18)
                      : theme.colorScheme.surfaceContainerHighest;
                  return Semantics(
                    label: selected ? 'Current bus None' : 'Route to None',
                    button: true,
                    selected: selected,
                    enabled: onTap != null,
                    excludeSemantics: true,
                    child: Focus(
                      autofocus: selected,
                      canRequestFocus: selected,
                      child: _BusOutlineStack(
                        baseColor: theme.colorScheme.outline,
                        baseWidth: 1.5,
                        selectionColor: selectionColor,
                        showSelection: selected,
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
                  );
                },
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
    final baseBorderWidth = _hovered ? 2.0 : 1.5;
    return _SelectedBusFade(
      selected: widget.selected,
      animation: widget.selectionAnimation,
      builder: (context, emphasis) {
        final selectionColor = widget.selected
            ? Color.lerp(
                theme.colorScheme.primary.withValues(alpha: 0),
                theme.colorScheme.primary,
                emphasis,
              )!
            : baseColor;
        final fillAlpha = widget.selected ? 0.45 : (_hovered ? 0.35 : 0.18);
        return Semantics(
          label: widget.selected
              ? 'Current bus ${widget.label}'
              : 'Route to ${widget.label}',
          button: true,
          selected: widget.selected,
          enabled: widget.onTap != null,
          excludeSemantics: true,
          child: Focus(
            autofocus: widget.selected,
            canRequestFocus: widget.selected,
            child: _BusOutlineStack(
              baseColor: baseColor,
              baseWidth: baseBorderWidth,
              selectionColor: selectionColor,
              showSelection: widget.selected,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BusOutlineStack extends StatelessWidget {
  final Color baseColor;
  final double baseWidth;
  final Color selectionColor;
  final bool showSelection;
  final Widget child;

  const _BusOutlineStack({
    required this.baseColor,
    required this.baseWidth,
    required this.selectionColor,
    required this.showSelection,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: baseColor, width: baseWidth),
          ),
          child: child,
        ),
        if (showSelection)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('selected-bus-outline'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selectionColor, width: 3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SelectedBusFade extends StatefulWidget {
  final bool selected;
  final Animation<double>? animation;
  final Widget Function(BuildContext context, double emphasis) builder;

  const _SelectedBusFade({
    required this.selected,
    required this.animation,
    required this.builder,
  });

  @override
  State<_SelectedBusFade> createState() => _SelectedBusFadeState();
}

class _SelectedBusFadeState extends State<_SelectedBusFade>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  AnimationController get _internalController =>
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      );

  @override
  void initState() {
    super.initState();
    _configureAnimation();
  }

  @override
  void didUpdateWidget(covariant _SelectedBusFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.animation != widget.animation) {
      _configureAnimation();
    }
  }

  void _configureAnimation() {
    if (widget.animation != null) {
      _controller?.stop();
      return;
    }
    final controller = _internalController;
    controller.stop();
    if (!widget.selected) {
      controller.value = 0;
      return;
    }
    controller.value = 1;
    controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = widget.animation ?? _internalController;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => widget.builder(
        context,
        widget.selected ? Curves.easeInOut.transform(animation.value) : 0,
      ),
    );
  }
}
