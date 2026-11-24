import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';

/// A movable widget for displaying physical I/O nodes with draggable functionality.
///
/// This widget provides a movable version of physical I/O nodes using the shared
/// PortWidget for consistent visualization across the routing system.
class MovablePhysicalIONode extends StatefulWidget {
  /// The list of ports to display in this node.
  final List<Port> ports;

  /// The title to display in the header.
  final String title;

  /// The icon to display in the header.
  final IconData icon;

  /// The initial position of this node in the canvas.
  final Offset position;

  /// Whether this is a physical input node (affects label positioning).
  /// Physical inputs act as outputs to algorithms (left labels).
  /// Physical outputs act as inputs from algorithms (right labels).
  final bool isInput;

  /// Callback when the node position changes.
  final Function(Offset)? onPositionChanged;

  /// Callback when a port is tapped.
  final Function(Port)? onPortTapped;

  /// Callback when a port is long-pressed (for connection deletion).
  final Function(Port)? onPortLongPress;

  /// Callback when long press starts on a port (for animated deletion).
  final Function(Port)? onPortLongPressStart;

  /// Callback when long press is cancelled on a port.
  final VoidCallback? onPortLongPressCancel;

  /// Callback when drag starts from a port.
  final Function(Port)? onPortDragStart;

  /// Callback when drag updates with new position.
  final Function(Port, Offset)? onPortDragUpdate;

  /// Callback when drag ends at a position.
  final Function(Port, Offset)? onPortDragEnd;

  /// Callback to report each port's global center for connection anchoring.
  final void Function(Port port, Offset globalCenter)? onPortPositionResolved;

  /// Callback when node drag starts.
  final VoidCallback? onNodeDragStart;

  /// Callback when node drag ends.
  final VoidCallback? onNodeDragEnd;

  /// Set of connected port IDs
  final Set<String>? connectedPorts;

  /// Callback for routing actions from ports
  final void Function(String portId, String action)? onRoutingAction;

  /// ID of the port that should be highlighted (during drag operations)
  final String? highlightedPortId;

  /// Callback when the node's size is resolved
  final ValueChanged<Size>? onSizeResolved;

  const MovablePhysicalIONode({
    super.key,
    required this.ports,
    required this.title,
    required this.icon,
    required this.position,
    required this.isInput,
    this.onPositionChanged,
    this.onPortTapped,
    this.onPortLongPress,
    this.onPortLongPressStart,
    this.onPortLongPressCancel,
    this.onPortDragStart,
    this.onPortDragUpdate,
    this.onPortDragEnd,
    this.onPortPositionResolved,
    this.onNodeDragStart,
    this.onNodeDragEnd,
    this.connectedPorts,
    this.onRoutingAction,
    this.highlightedPortId,
    this.onSizeResolved,
  });

  @override
  State<MovablePhysicalIONode> createState() => _MovablePhysicalIONodeState();
}

class _MovablePhysicalIONodeState extends State<MovablePhysicalIONode> {
  bool _isDragging = false;
  Offset _dragStartGlobal = Offset.zero;
  Offset _initialPosition = Offset.zero;
  double _dragScale = 1.0;
  final GlobalKey _nodeKey = GlobalKey();

  // Focus and keyboard navigation state
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;
  int _focusedPortIndex = -1; // -1 = node level (no port focused)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MovablePhysicalIONode oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
    if (widget.ports.length != oldWidget.ports.length) {
      _focusedPortIndex = -1;
    }
  }

  void _reportSize() {
    final context = _nodeKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && widget.onSizeResolved != null) {
        widget.onSizeResolved!(box.size);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        setState(() {
          _hasFocus = hasFocus;
          if (!hasFocus) _focusedPortIndex = -1;
        });
      },
      onKeyEvent: _handleNodeKeyEvent,
      child: GestureDetector(
        onPanStart: _handleDragStart,
        onPanUpdate: _handleDragUpdate,
        onPanEnd: _handleDragEnd,
        child: AnimatedContainer(
          key: _nodeKey,
          duration: _isDragging
              ? Duration.zero
              : const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withValues(alpha: 0.95),
            border: Border.all(
              color: _hasFocus
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.4),
              width: _hasFocus ? 2.5 : 1.5,
            ),
            borderRadius: BorderRadius.circular(12.0),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: _isDragging ? 0.3 : 0.1,
                ),
                blurRadius: _isDragging ? 8 : 4,
                offset: Offset(0, _isDragging ? 4 : 2),
              ),
            ],
          ),
          child: IntrinsicWidth(
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(colorScheme, theme),
                  const SizedBox(height: 8.0),
                  _buildPortList(),
                  const SizedBox(height: 8.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the header section with title and icon.
  Widget _buildHeader(ColorScheme colorScheme, ThemeData theme) {
    return Semantics(
      header: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12.0),
            topRight: Radius.circular(12.0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, size: 16.0, color: colorScheme.primary),
            const SizedBox(width: 8.0),
            Text(
              widget.title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the list of port widgets using the shared PortWidget.
  Widget _buildPortList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < widget.ports.length; i++)
            _buildPortRow(widget.ports[i], i),
        ],
      ),
    );
  }

  /// Builds a single port row using PortWidget.
  Widget _buildPortRow(Port port, int portIndex) {
    final portIsInput = port.direction == PortDirection.input;

    Widget inner = PortWidget(
      label: port.name,
      // Use the port's actual direction instead of inverting widget.isInput
      // Physical inputs have PortDirection.output (they send signals TO algorithms)
      // Physical outputs have PortDirection.input (they receive signals FROM algorithms)
      isInput: portIsInput,
      portId: port.id,
      port: port,
      labelPosition: widget.isInput
          ? PortLabelPosition.left
          : PortLabelPosition.right,
      style: PortStyle.jack,
      isConnected:
          port.isActive &&
          (port.isConnected ||
              (widget.connectedPorts?.contains(port.id) ?? false)), // Check both port's connection status and connectedPorts
      isHighlighted: port.id == widget.highlightedPortId,
      isFocused: portIndex == _focusedPortIndex,
      onPortPositionResolved: widget.onPortPositionResolved != null
          ? (portId, globalCenter, isInput) {
              widget.onPortPositionResolved!(port, globalCenter);
            }
          : null,
      // Long-press to delete connections - available on all ports
      onLongPress: widget.onPortLongPress != null
          ? () => widget.onPortLongPress!(port)
          : null,
      // Animated long press (for desktop)
      onLongPressStart: widget.onPortLongPressStart != null
          ? () => widget.onPortLongPressStart!(port)
          : null,
      onLongPressCancel: widget.onPortLongPressCancel,
      onRoutingAction: widget.onRoutingAction,
      // Drag to create connections - available on all ports
      onDragStart: () => widget.onPortDragStart?.call(port),
      onDragUpdate: (position) => widget.onPortDragUpdate?.call(port, position),
      onDragEnd: (position) => widget.onPortDragEnd?.call(port, position),
    );

    // Ensure input side rows are right-justified inside the node
    if (widget.isInput) {
      inner = Align(alignment: Alignment.centerRight, child: inner);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: port.effectiveRole == PortRole.expanderOutputBus
          ? Semantics(
              label: port.description,
              child: Tooltip(
                message: port.description ?? port.name,
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: port.isActive ? 1 : 0.5,
                    child: inner,
                  ),
                ),
              ),
            )
          : inner,
    );
  }

  KeyEventResult _handleNodeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedPortIndex < 0 && widget.ports.isNotEmpty) {
        setState(() {
          _focusedPortIndex = 0;
        });
        return KeyEventResult.handled;
      }
      if (_focusedPortIndex >= 0) {
        _activateFocusedPort();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_focusedPortIndex >= 0) {
        setState(() {
          _focusedPortIndex = -1;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _focusedPortIndex >= 0) {
      setState(() {
        _focusedPortIndex = (_focusedPortIndex + 1).clamp(
          0,
          widget.ports.length - 1,
        );
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _focusedPortIndex >= 0) {
      setState(() {
        _focusedPortIndex = (_focusedPortIndex - 1).clamp(
          0,
          widget.ports.length - 1,
        );
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.space &&
        _focusedPortIndex >= 0) {
      _activateFocusedPort();
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) &&
        _focusedPortIndex >= 0) {
      _deleteFocusedPortConnections();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateFocusedPort() {
    if (_focusedPortIndex < 0 || _focusedPortIndex >= widget.ports.length) {
      return;
    }
    final port = widget.ports[_focusedPortIndex];
    widget.onPortTapped?.call(port);
  }

  void _deleteFocusedPortConnections() {
    if (_focusedPortIndex < 0 || _focusedPortIndex >= widget.ports.length) {
      return;
    }
    final port = widget.ports[_focusedPortIndex];
    widget.onPortLongPress?.call(port);
  }

  void _handleDragStart(DragStartDetails details) {
    // Capture the local-to-global scale factor from the render tree.
    // This accounts for any ancestor Transform.scale (e.g. canvas zoom).
    final box = context.findRenderObject() as RenderBox?;
    _dragScale = box != null ? box.getTransformTo(null).entry(0, 0) : 1.0;

    setState(() {
      _isDragging = true;
      _dragStartGlobal = details.globalPosition;
      _initialPosition = widget.position;
    });

    widget.onNodeDragStart?.call();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    // Account for canvas zoom level (screen pixels != canvas pixels)
    final dragDelta = (details.globalPosition - _dragStartGlobal) / _dragScale;
    final newPosition = _initialPosition + dragDelta;

    // Snap to grid
    const double gridSize = 25.0;
    final snappedPosition = Offset(
      (newPosition.dx / gridSize).round() * gridSize,
      (newPosition.dy / gridSize).round() * gridSize,
    );

    // Constrain to canvas bounds
    const double canvasSize = 5000.0;
    final constrainedPosition = Offset(
      snappedPosition.dx.clamp(0.0, canvasSize - 200),
      snappedPosition.dy.clamp(0.0, canvasSize - 300),
    );

    widget.onPositionChanged?.call(constrainedPosition);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    widget.onNodeDragEnd?.call();
  }
}
