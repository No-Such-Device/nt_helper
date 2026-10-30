import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/routing/accessibility_colors.dart';

/// Enum for configurable label positioning relative to port
enum PortLabelPosition {
  /// Label on the left side of the port
  left,

  /// Label on the right side of the port
  right,
}

/// Enum for port rendering style
enum PortStyle {
  /// Simple circular dot style used in algorithm nodes
  dot,

  /// Jack socket style used in physical I/O nodes
  jack,
}

/// A reusable port widget for displaying connection points in routing nodes.
///
/// This widget provides a consistent visual representation for ports across
/// algorithm nodes and physical I/O nodes. It includes configurable label
/// positioning, rendering styles, and callback support for position resolution.
class PortWidget extends StatefulWidget {
  /// The text label for the port
  final String label;

  /// Whether this is an input port (affects visual styling)
  final bool isInput;

  /// Optional unique identifier for the port
  final String? portId;

  /// Optional Port model for richer functionality
  final Port? port;

  /// Configurable position of the label relative to the port
  final PortLabelPosition labelPosition;

  /// Visual style for rendering the port
  final PortStyle style;

  /// Theme data to use for styling the port
  final ThemeData? theme;

  /// Callback to report the port's global center position after layout
  final void Function(String portId, Offset globalCenter, bool isInput)?
  onPortPositionResolved;

  /// Callback for port tap events
  final VoidCallback? onTap;

  /// Callback for long press events (used for deletion)
  final VoidCallback? onLongPress;

  /// Callback for long press start (used for animated deletion)
  final VoidCallback? onLongPressStart;

  /// Callback for long press cancel/end (used for animated deletion)
  final VoidCallback? onLongPressCancel;

  /// Callback for drag start events
  final VoidCallback? onDragStart;

  /// Callback for drag update events
  final void Function(Offset position)? onDragUpdate;

  /// Callback for drag end events
  final void Function(Offset position)? onDragEnd;

  /// Callback for mouse hover enter events
  final VoidCallback? onHoverEnter;

  /// Callback for mouse hover exit events
  final VoidCallback? onHoverExit;

  /// Whether this port is currently connected to other ports
  final bool isConnected;

  /// List of connection IDs that involve this port
  final List<String> connectionIds;

  /// Direct callback to routing cubit for connection operations
  final void Function(String portId, String action)? onRoutingAction;

  /// Whether this port is currently highlighted (e.g., during drag operations)
  final bool isHighlighted;

  /// Show a centered red dot to indicate a "shadowed" output
  final bool showShadowDot;

  /// Whether this port is currently keyboard-focused
  final bool isFocused;

  const PortWidget({
    super.key,
    required this.label,
    required this.isInput,
    this.portId,
    this.port,
    this.labelPosition = PortLabelPosition.right,
    this.style = PortStyle.dot,
    this.theme,
    this.onPortPositionResolved,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressCancel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onHoverEnter,
    this.onHoverExit,
    this.isConnected = false,
    this.connectionIds = const [],
    this.onRoutingAction,
    this.isHighlighted = false,
    this.showShadowDot = false,
    this.isFocused = false,
  });

  @override
  State<PortWidget> createState() => _PortWidgetState();
}

class _PortWidgetState extends State<PortWidget> {
  late final GlobalKey _dotKey;
  Timer? _hoverTimer;
  bool _showDeleteHint = false;
  bool _suppressDeleteHint = false;

  /// Duration to wait before showing the delete hint tooltip
  static const _hoverHintDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _dotKey = GlobalKey();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _startHoverTimer() {
    // Only start timer if port is connected and has long press handler
    // Check both onLongPress (mobile) and onLongPressStart (desktop animated)
    final hasLongPressHandler =
        widget.onLongPress != null || widget.onLongPressStart != null;
    if (!widget.isConnected || !hasLongPressHandler || _suppressDeleteHint) {
      return;
    }

    _hoverTimer?.cancel();
    _hoverTimer = Timer(_hoverHintDelay, () {
      if (mounted) {
        setState(() {
          _showDeleteHint = true;
        });
      }
    });
  }

  void _cancelHoverTimer() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    if (_showDeleteHint && mounted) {
      setState(() {
        _showDeleteHint = false;
      });
    }
  }

  void _suppressHoverHint() {
    if (_suppressDeleteHint) return;
    _suppressDeleteHint = true;
    _cancelHoverTimer();
  }

  void _unsuppressHoverHint() {
    _suppressDeleteHint = false;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = widget.theme ?? Theme.of(context);

    Widget portWidget;

    switch (widget.style) {
      case PortStyle.dot:
        portWidget = _buildDotStyle(effectiveTheme);
        break;
      case PortStyle.jack:
        portWidget = _buildJackStyle(effectiveTheme);
        break;
    }

    // Add gesture detection for interaction callbacks
    if (widget.onTap != null ||
        widget.onLongPress != null ||
        widget.onLongPressStart != null ||
        widget.onDragStart != null ||
        widget.onDragUpdate != null ||
        widget.onDragEnd != null) {
      portWidget = GestureDetector(
        // Include row padding and the label gap so near-dot drags do not
        // fall through to the surrounding algorithm node's move gesture.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // Use animated long press if callbacks are provided, otherwise immediate
        onLongPress: widget.onLongPressStart == null
            ? widget.onLongPress
            : null,
        onLongPressStart: widget.onLongPressStart != null
            ? (_) {
                // Prevent the delayed hover tooltip from appearing mid-delete.
                _suppressHoverHint();
                widget.onLongPressStart!();
              }
            : null,
        onLongPressEnd: widget.onLongPressStart != null
            ? (_) {
                widget.onLongPressCancel?.call();
                _unsuppressHoverHint();
              }
            : null,
        onLongPressCancel: widget.onLongPressStart != null
            ? () {
                widget.onLongPressCancel?.call();
                _unsuppressHoverHint();
              }
            : widget.onLongPressCancel,
        onPanStart: widget.onDragStart != null
            ? (_) => widget.onDragStart!()
            : null,
        onPanUpdate: widget.onDragUpdate != null
            ? (details) => widget.onDragUpdate!(details.globalPosition)
            : null,
        onPanEnd: widget.onDragEnd != null
            ? (details) => widget.onDragEnd!(details.globalPosition)
            : null,
        child: portWidget,
      );
    }

    // Wrap in Semantics for accessibility
    final directionLabel = widget.isInput ? 'Input' : 'Output';
    final connectionLabel = widget.isConnected ? 'connected' : 'not connected';
    final shadowLabel = widget.showShadowDot ? ', shadowed by later slot' : '';
    final portTypeLabel = widget.port != null
        ? (widget.port!.type == PortType.audio ? 'Audio' : 'CV')
        : '';
    final typePrefix = portTypeLabel.isNotEmpty ? '$portTypeLabel ' : '';
    final hintText = widget.isConnected
        ? 'Long press to delete connections. Press Space to start connection.'
        : 'Press Space to start a connection.';

    return Semantics(
      label:
          '${widget.label}, $typePrefix$directionLabel, $connectionLabel$shadowLabel',
      hint: hintText,
      button: true,
      child: portWidget,
    );
  }

  /// Builds the simple dot style port (for algorithm nodes)
  Widget _buildDotStyle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: _buildPortElements(theme),
      ),
    );
  }

  /// Builds the jack socket style port (for physical I/O nodes)
  Widget _buildJackStyle(ThemeData theme) {
    // For now, use a simpler jack representation
    // This could be enhanced to use the full JackConnectionWidget functionality

    final portColor = _getPortColor(theme);

    Widget jackDot = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      key: _dotKey,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: portColor,
        border: Border.all(
          color: widget.isFocused
              ? theme.colorScheme.primary
              : widget.isHighlighted
              ? portColor.withValues(alpha: 0.8)
              : theme.colorScheme.outline,
          width: (widget.isFocused || widget.isHighlighted) ? 3 : 2,
        ),
        boxShadow: widget.isFocused
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : widget.isHighlighted
            ? [
                BoxShadow(
                  color: portColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    // Add hover detection only to the jack dot when routing action callback is provided
    if (widget.onRoutingAction != null) {
      jackDot = MouseRegion(
        onEnter: (_) {
          widget.onHoverEnter?.call();
          _startHoverTimer();
          // Notify routing cubit about hover start - it will determine if port is connected
          if (widget.portId != null) {
            widget.onRoutingAction?.call(widget.portId!, 'hover_start');
          }
        },
        onExit: (_) {
          widget.onHoverExit?.call();
          _cancelHoverTimer();
          // Notify routing cubit about hover end
          if (widget.portId != null) {
            widget.onRoutingAction?.call(widget.portId!, 'hover_end');
          }
        },
        child: jackDot,
      );

      // Wrap with tooltip when delete hint should show
      if (_showDeleteHint) {
        jackDot = Tooltip(
          message: 'Long-press to delete connection',
          preferBelow: true,
          showDuration: const Duration(seconds: 3),
          child: jackDot,
        );
      }
    }

    return SizedBox(
      height: 28,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.labelPosition == PortLabelPosition.left) ...[
            Text(
              widget.label,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 6),
          ],
          jackDot,
          if (widget.labelPosition == PortLabelPosition.right) ...[
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePortPositionResolution();
  }

  @override
  void didUpdateWidget(covariant PortWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePortPositionResolution();
  }

  /// Gets the appropriate color for the port based on its type and direction.
  ///
  /// Audio/CV distinction is cosmetic only - affects port circle color but not
  /// connection compatibility. All port types can connect to each other.
  ///
  /// Color scheme:
  /// - Audio ports: Warm colors (orange) - displayed as VU meters on hardware
  /// - CV ports: Cool colors (blue) - displayed as voltage values on hardware
  /// - Direction affects color brightness (input vs output)
  Color _getPortColor(ThemeData theme) {
    // If no port model provided, fall back to direction-based coloring
    if (widget.port == null) {
      return widget.isInput
          ? theme.colorScheme.primary
          : theme.colorScheme.secondary;
    }

    // Use accessible colors derived from the current theme's color scheme
    final colors = AccessibilityColors.fromColorScheme(theme.colorScheme);
    final baseColor = switch (widget.port!.type) {
      PortType.audio => colors.audioPortColor,
      PortType.cv => colors.cvPortColor,
    };

    // Slightly adjust brightness based on direction for additional distinction
    if (widget.isInput) {
      return HSLColor.fromColor(baseColor)
          .withLightness(theme.brightness == Brightness.dark ? 0.60 : 0.45)
          .toColor();
    } else {
      return baseColor;
    }
  }

  /// Builds the port elements based on label position
  List<Widget> _buildPortElements(ThemeData theme) {
    final portDot = _buildPortDot(theme);
    final portLabel = _buildPortLabel(theme);

    switch (widget.labelPosition) {
      case PortLabelPosition.left:
        return [portLabel, const SizedBox(width: 4), portDot];
      case PortLabelPosition.right:
        return [portDot, const SizedBox(width: 4), portLabel];
    }
  }

  /// Builds the visual port dot/circle
  Widget _buildPortDot(ThemeData theme) {
    // Base port circle with type-based coloring
    final Widget base = Container(
      key: _dotKey,
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getPortColor(theme),
        border: Border.all(
          color: widget.isFocused
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
          width: widget.isFocused ? 2 : 1,
        ),
        boxShadow: widget.isFocused
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    // Overlay: centered red dot when shadowed (non-blocking)
    final Widget withOverlay = widget.showShadowDot
        ? Stack(
            alignment: Alignment.center,
            children: [
              base,
              IgnorePointer(
                ignoring: true,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1,
                    ),
                  ),
                ),
              ),
            ],
          )
        : base;

    // Add hover detection only when routing action callback is provided
    if (widget.onRoutingAction != null) {
      Widget result = MouseRegion(
        onEnter: (_) {
          widget.onHoverEnter?.call();
          _startHoverTimer();
          if (widget.portId != null) {
            widget.onRoutingAction?.call(widget.portId!, 'hover_start');
          }
        },
        onExit: (_) {
          widget.onHoverExit?.call();
          _cancelHoverTimer();
          if (widget.portId != null) {
            widget.onRoutingAction?.call(widget.portId!, 'hover_end');
          }
        },
        child: withOverlay,
      );

      // Wrap with tooltip when delete hint should show
      if (_showDeleteHint) {
        result = Tooltip(
          message: 'Long-press to delete connection',
          preferBelow: true,
          showDuration: const Duration(seconds: 3),
          child: result,
        );
      }

      return result;
    }

    return withOverlay;
  }

  /// Builds the port label text
  Widget _buildPortLabel(ThemeData theme) {
    return Text(widget.label, style: theme.textTheme.labelSmall);
  }

  /// Schedules port position resolution after the next frame
  void _schedulePortPositionResolution() {
    if (widget.onPortPositionResolved == null || widget.portId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _dotKey.currentContext;
      if (ctx == null) return;

      final render = ctx.findRenderObject() as RenderBox?;
      if (render == null || !render.attached) return;

      // Get the port's position relative to the nearest ancestor that will handle the coordinate
      // We need the canvas coordinate, not the global coordinate
      final size = render.size; // 12x12
      final center = Offset(size.width / 2.0, size.height / 2.0);

      // Convert to global first, then let the callback convert to canvas coordinates
      final globalCenter = render.localToGlobal(center);

      widget.onPortPositionResolved!(
        widget.portId!,
        globalCenter,
        widget.isInput,
      );
    });
  }
}
