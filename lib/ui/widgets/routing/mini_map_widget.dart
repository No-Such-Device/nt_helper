import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/core/routing/models/connection.dart';

/// A mini-map widget that provides a scaled overview of the entire routing canvas
/// and allows for quick navigation by showing the current viewport position.
class MiniMapWidget extends StatefulWidget {
  /// Horizontal scroll controller from the main canvas
  final ScrollController horizontalScrollController;

  /// Vertical scroll controller from the main canvas
  final ScrollController verticalScrollController;

  /// Width of the main canvas
  final double canvasWidth;

  /// Height of the main canvas
  final double canvasHeight;

  /// Width of the mini-map widget (defaults to 200px per spec)
  final double width;

  /// Height of the mini-map widget (defaults to 150px per spec)
  final double height;

  /// Node positions from the main canvas
  final Map<String, Offset>? nodePositions;

  /// List of connections to render
  final List<Connection>? connections;

  /// List of ports for connection endpoints
  final Map<String, Offset>? portPositions;

  const MiniMapWidget({
    super.key,
    required this.horizontalScrollController,
    required this.verticalScrollController,
    required this.canvasWidth,
    required this.canvasHeight,
    this.width = 200.0,
    this.height = 150.0,
    this.nodePositions,
    this.connections,
    this.portPositions,
  });

  @override
  State<MiniMapWidget> createState() => MiniMapWidgetState();
}

class MiniMapWidgetState extends State<MiniMapWidget> {
  /// Current viewport offset from scroll controllers
  Offset _viewportOffset = Offset.zero;

  /// Scale factor for converting canvas coordinates to mini-map coordinates
  late double scaleFactor;

  /// Whether the viewport rectangle is currently being dragged
  bool _isDragging = false;

  /// Starting position of the drag operation in mini-map coordinates
  Offset? _dragStartPosition;

  /// Initial scroll positions when drag started
  Offset? _initialScrollOffset;

  /// Whether to show the drag cursor
  bool _showDragCursor = false;

  /// Whether to show the hover cursor
  bool _showHoverCursor = false;

  /// Whether to highlight the viewport rectangle
  bool _highlightViewportRectangle = false;

  @override
  void initState() {
    super.initState();
    _calculateScaleFactor();
    _addScrollListeners();
    _updateViewportPosition();
  }

  @override
  void didUpdateWidget(MiniMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Recalculate scale factor if dimensions changed
    if (oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.canvasWidth != widget.canvasWidth ||
        oldWidget.canvasHeight != widget.canvasHeight) {
      _calculateScaleFactor();
    }

    // Update scroll listeners if controllers changed
    if (oldWidget.horizontalScrollController !=
            widget.horizontalScrollController ||
        oldWidget.verticalScrollController != widget.verticalScrollController) {
      _removeScrollListeners(oldWidget);
      _addScrollListeners();
    }
  }

  @override
  void dispose() {
    _removeScrollListeners(widget);
    super.dispose();
  }

  /// Calculate the scale factor based on canvas-to-minimap size ratio
  void _calculateScaleFactor() {
    final scaleX = widget.width / widget.canvasWidth;
    final scaleY = widget.height / widget.canvasHeight;
    // Use the smaller scale to ensure the entire canvas fits in the mini-map
    scaleFactor = scaleX < scaleY ? scaleX : scaleY;
  }

  /// Add listeners to scroll controllers for viewport position tracking
  void _addScrollListeners() {
    widget.horizontalScrollController.addListener(_updateViewportPosition);
    widget.verticalScrollController.addListener(_updateViewportPosition);
  }

  /// Remove listeners from scroll controllers
  void _removeScrollListeners(MiniMapWidget oldWidget) {
    oldWidget.horizontalScrollController.removeListener(
      _updateViewportPosition,
    );
    oldWidget.verticalScrollController.removeListener(_updateViewportPosition);
  }

  /// Update viewport position based on scroll controller offsets
  void _updateViewportPosition() {
    if (!mounted) return;

    final horizontalOffset = widget.horizontalScrollController.hasClients
        ? widget.horizontalScrollController.offset
        : 0.0;
    final verticalOffset = widget.verticalScrollController.hasClients
        ? widget.verticalScrollController.offset
        : 0.0;

    setState(() {
      _viewportOffset = Offset(horizontalOffset, verticalOffset);
    });
  }

  /// Get the current viewport offset for testing purposes
  Offset get viewportOffset => _viewportOffset;

  /// Get the current dragging state for testing purposes
  bool get isDragging => _isDragging;

  /// Get the drag start position for testing purposes
  Offset? get dragStartPosition => _dragStartPosition;

  /// Get the show drag cursor state for testing purposes
  bool get showDragCursor => _showDragCursor;

  /// Get the show hover cursor state for testing purposes
  bool get showHoverCursor => _showHoverCursor;

  /// Get the highlight viewport rectangle state for testing purposes
  bool get highlightViewportRectangle => _highlightViewportRectangle;

  /// Handle tap down events on the mini-map for navigation
  void _handleTapDown(TapDownDetails details) {
    final miniMapTapPosition = details.localPosition;

    // Convert mini-map coordinates to canvas coordinates
    final canvasX = miniMapTapPosition.dx / scaleFactor;
    final canvasY = miniMapTapPosition.dy / scaleFactor;

    // Calculate scroll offset to center the viewport at the tapped position
    // Default viewport size from RoutingEditorWidget
    const viewportWidth = 1200.0;
    const viewportHeight = 800.0;

    final targetScrollX = canvasX - (viewportWidth / 2);
    final targetScrollY = canvasY - (viewportHeight / 2);

    // Apply boundary checking to prevent invalid scroll positions
    final boundedScrollX = _clampScrollOffset(
      targetScrollX,
      widget.horizontalScrollController,
    );
    final boundedScrollY = _clampScrollOffset(
      targetScrollY,
      widget.verticalScrollController,
    );

    // Animate to the target position for smooth navigation
    _animateToPosition(boundedScrollX, boundedScrollY);
  }

  /// Handle tap events for quick navigation (when no drag occurred)
  void _handleTap() {
    // This will be called for taps, _handleTapDown handles the navigation logic
  }

  /// Handle pan down events (similar to tap down but for drag)
  void _handlePanDown(DragDownDetails details) {
    // Pan down is called before pan start, we can use this to prepare for drag
  }

  /// Handle pan start events for drag operations
  void _handlePanStart(DragStartDetails details) {
    final miniMapPosition = details.localPosition;

    // Allow dragging from anywhere in the mini-map, not just the viewport rectangle
    // This provides a better user experience for navigation
    setState(() {
      _isDragging = true;
      _dragStartPosition = miniMapPosition;
      _initialScrollOffset = Offset(
        widget.horizontalScrollController.hasClients
            ? widget.horizontalScrollController.offset
            : 0.0,
        widget.verticalScrollController.hasClients
            ? widget.verticalScrollController.offset
            : 0.0,
      );
      _showDragCursor = true;
      _highlightViewportRectangle = true;
    });
  }

  /// Handle pan update events during drag operations
  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDragging ||
        _dragStartPosition == null ||
        _initialScrollOffset == null) {
      return;
    }

    final currentPosition = details.localPosition;
    final dragDelta = currentPosition - _dragStartPosition!;

    // Convert mini-map delta to canvas delta
    final canvasDeltaX = dragDelta.dx / scaleFactor;
    final canvasDeltaY = dragDelta.dy / scaleFactor;

    // Calculate new scroll positions
    final targetScrollX = _initialScrollOffset!.dx + canvasDeltaX;
    final targetScrollY = _initialScrollOffset!.dy + canvasDeltaY;

    // Apply edge clamping to keep viewport within canvas bounds
    final clampedScrollX = _clampScrollOffset(
      targetScrollX,
      widget.horizontalScrollController,
    );
    final clampedScrollY = _clampScrollOffset(
      targetScrollY,
      widget.verticalScrollController,
    );

    // Update scroll positions in real-time
    if (widget.horizontalScrollController.hasClients) {
      widget.horizontalScrollController.jumpTo(clampedScrollX);
    }
    if (widget.verticalScrollController.hasClients) {
      widget.verticalScrollController.jumpTo(clampedScrollY);
    }
  }

  /// Handle pan end events when drag operations complete
  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
      _initialScrollOffset = null;
      _showDragCursor = false;
      _highlightViewportRectangle = false;
    });
  }

  /// Handle pointer enter events for hover feedback
  void _handlePointerEnter(PointerEnterEvent event) {
    final localPosition = event.localPosition;
    if (_isPositionWithinViewportRectangle(localPosition)) {
      setState(() {
        _showHoverCursor = true;
      });
    }
  }

  /// Handle pointer exit events for hover feedback
  void _handlePointerExit(PointerExitEvent event) {
    setState(() {
      _showHoverCursor = false;
    });
  }

  /// Handle pointer hover events for cursor changes
  void _handlePointerHover(PointerHoverEvent event) {
    final localPosition = event.localPosition;
    final isWithinViewport = _isPositionWithinViewportRectangle(localPosition);

    if (isWithinViewport != _showHoverCursor) {
      setState(() {
        _showHoverCursor = isWithinViewport;
      });
    }
  }

  /// Check if a position is within the viewport rectangle
  bool _isPositionWithinViewportRectangle(Offset position) {
    // Calculate viewport rectangle in mini-map coordinates
    const viewportWidth = 1200.0; // From RoutingEditorWidget default
    const viewportHeight = 800.0; // From RoutingEditorWidget default

    final viewportX = _viewportOffset.dx * scaleFactor;
    final viewportY = _viewportOffset.dy * scaleFactor;
    final scaledViewportWidth = viewportWidth * scaleFactor;
    final scaledViewportHeight = viewportHeight * scaleFactor;

    final viewportRect = Rect.fromLTWH(
      viewportX,
      viewportY,
      scaledViewportWidth,
      scaledViewportHeight,
    );

    // Clamp to mini-map bounds
    final clampedRect = Rect.fromLTWH(
      viewportRect.left.clamp(0, widget.width),
      viewportRect.top.clamp(0, widget.height),
      (viewportRect.right - viewportRect.left).clamp(
        0,
        widget.width - viewportRect.left,
      ),
      (viewportRect.bottom - viewportRect.top).clamp(
        0,
        widget.height - viewportRect.top,
      ),
    );

    return clampedRect.contains(position);
  }

  /// Clamp scroll offset to valid bounds for the given scroll controller
  double _clampScrollOffset(double targetOffset, ScrollController controller) {
    if (!controller.hasClients) return targetOffset;

    final position = controller.position;
    return targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  /// Animate the scroll controllers to the target position
  void _animateToPosition(double targetX, double targetY) {
    const animationDuration = Duration(milliseconds: 300);
    const animationCurve = Curves.easeInOut;

    // Animate both controllers simultaneously
    if (widget.horizontalScrollController.hasClients) {
      widget.horizontalScrollController.animateTo(
        targetX,
        duration: animationDuration,
        curve: animationCurve,
      );
    }

    if (widget.verticalScrollController.hasClients) {
      widget.verticalScrollController.animateTo(
        targetY,
        duration: animationDuration,
        curve: animationCurve,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine cursor based on drag state and hover
    MouseCursor cursor = MouseCursor.defer;
    if (_isDragging && _showDragCursor) {
      cursor = SystemMouseCursors.grabbing;
    } else if (_showHoverCursor) {
      cursor = SystemMouseCursors.grab;
    }

    return ExcludeSemantics(
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          border: Border.all(color: Theme.of(context).dividerColor, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: MouseRegion(
          cursor: cursor,
          onEnter: _handlePointerEnter,
          onExit: _handlePointerExit,
          onHover: _handlePointerHover,
          child: GestureDetector(
            onTapDown: _handleTapDown,
            onTap: _handleTap,
            onPanDown: _handlePanDown,
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            // Allow both tap and pan gestures
            behavior: HitTestBehavior.opaque,
            child: CustomPaint(
              painter: _MiniMapPainter(
                viewportOffset: _viewportOffset,
                scaleFactor: scaleFactor,
                theme: Theme.of(context),
                canvasWidth: widget.canvasWidth,
                canvasHeight: widget.canvasHeight,
                nodePositions: widget.nodePositions ?? {},
                connections: widget.connections ?? [],
                portPositions: widget.portPositions ?? {},
                isDragging: _isDragging,
                highlightViewportRectangle: _highlightViewportRectangle,
              ),
              size: Size(widget.width, widget.height),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for rendering the mini-map content
class _MiniMapPainter extends CustomPainter {
  final Offset viewportOffset;
  final double scaleFactor;
  final ThemeData theme;
  final double canvasWidth;
  final double canvasHeight;
  final Map<String, Offset> nodePositions;
  final List<Connection> connections;
  final Map<String, Offset> portPositions;
  final bool isDragging;
  final bool highlightViewportRectangle;

  const _MiniMapPainter({
    required this.viewportOffset,
    required this.scaleFactor,
    required this.theme,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.nodePositions,
    required this.connections,
    required this.portPositions,
    this.isDragging = false,
    this.highlightViewportRectangle = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Apply canvas clipping to prevent overflow
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Render in order: connections, nodes, then viewport rectangle on top
    _paintConnections(canvas, size);
    _paintNodes(canvas, size);
    _paintViewportRectangle(canvas, size);
  }

  /// Paint the viewport rectangle showing the current visible area
  void _paintViewportRectangle(Canvas canvas, Size size) {
    // Calculate viewport size in canvas coordinates
    // For now, assume a reasonable viewport size (this will be improved in future tasks)
    const viewportWidth = 1200.0; // From RoutingEditorWidget default
    const viewportHeight = 800.0; // From RoutingEditorWidget default

    // Convert viewport position and size to mini-map coordinates
    final viewportX = viewportOffset.dx * scaleFactor;
    final viewportY = viewportOffset.dy * scaleFactor;
    final scaledViewportWidth = viewportWidth * scaleFactor;
    final scaledViewportHeight = viewportHeight * scaleFactor;

    // Create viewport rectangle
    final viewportRect = Rect.fromLTWH(
      viewportX,
      viewportY,
      scaledViewportWidth,
      scaledViewportHeight,
    );

    // Clip to mini-map bounds
    final clippedRect = Rect.fromLTWH(
      viewportRect.left.clamp(0, size.width),
      viewportRect.top.clamp(0, size.height),
      (viewportRect.right - viewportRect.left).clamp(
        0,
        size.width - viewportRect.left,
      ),
      (viewportRect.bottom - viewportRect.top).clamp(
        0,
        size.height - viewportRect.top,
      ),
    );

    // Adjust visual feedback based on drag state
    final fillOpacity = highlightViewportRectangle
        ? 0.2
        : 0.1; // More opaque when dragging
    final borderWidth = highlightViewportRectangle
        ? 3.0
        : 2.0; // Thicker border when dragging

    // Paint viewport rectangle with semi-transparent fill
    final fillPaint = Paint()
      ..color = theme.colorScheme.primary.withValues(alpha: fillOpacity)
      ..style = PaintingStyle.fill;

    canvas.drawRect(clippedRect, fillPaint);

    // Paint viewport rectangle border
    final borderPaint = Paint()
      ..color = theme.colorScheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRect(clippedRect, borderPaint);
  }

  /// Paint all nodes as simplified colored rectangles
  void _paintNodes(Canvas canvas, Size size) {
    for (final entry in nodePositions.entries) {
      final nodeId = entry.key;
      final canvasPosition = entry.value;

      // Scale canvas coordinates to mini-map coordinates
      final miniMapPosition = Offset(
        canvasPosition.dx * scaleFactor,
        canvasPosition.dy * scaleFactor,
      );

      // Skip nodes that are completely outside the mini-map bounds
      if (miniMapPosition.dx < -10 ||
          miniMapPosition.dy < -10 ||
          miniMapPosition.dx > size.width + 10 ||
          miniMapPosition.dy > size.height + 10) {
        continue;
      }

      // Determine node color and shape based on node type
      Color nodeColor;
      bool isPhysicalNode = false;
      double nodeWidth = 8.0; // Default 8×6px per spec
      double nodeHeight = 6.0;

      if (nodeId == 'physical_inputs') {
        nodeColor = theme.colorScheme.secondary;
        isPhysicalNode = true;
        nodeWidth = 12.0; // Larger for physical nodes
        nodeHeight = 8.0;
      } else if (nodeId == 'physical_outputs' || nodeId == 'ntx8cv_outputs') {
        nodeColor = theme.colorScheme.tertiary;
        isPhysicalNode = true;
        nodeWidth = 12.0;
        nodeHeight = 8.0;
      } else {
        // Algorithm nodes use primary color variations
        final hash = nodeId.hashCode;
        final hue = (hash % 360).toDouble();
        nodeColor = HSVColor.fromAHSV(1.0, hue, 0.7, 0.8).toColor();
      }

      // Create node rectangle
      final nodeRect = Rect.fromCenter(
        center: miniMapPosition,
        width: nodeWidth,
        height: nodeHeight,
      );

      // Clip node to mini-map bounds
      final clippedNodeRect = _clipRectToSize(nodeRect, size);
      if (clippedNodeRect.isEmpty) continue;

      // Paint node
      final nodePaint = Paint()
        ..color = nodeColor
        ..style = PaintingStyle.fill;

      if (isPhysicalNode) {
        // Physical nodes: distinctive shapes (rounded rectangles)
        final roundedRect = RRect.fromRectAndRadius(
          clippedNodeRect,
          const Radius.circular(2.0),
        );
        canvas.drawRRect(roundedRect, nodePaint);

        // Add border for physical nodes
        final borderPaint = Paint()
          ..color = nodeColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRRect(roundedRect, borderPaint);
      } else {
        // Algorithm nodes: simple rectangles
        canvas.drawRect(clippedNodeRect, nodePaint);
      }
    }
  }

  /// Paint connections as thin lines without labels
  void _paintConnections(Canvas canvas, Size size) {
    final connectionPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5; // Thin lines per spec

    for (final connection in connections) {
      // Get start and end port positions
      final startPosition = portPositions[connection.sourcePortId];
      final endPosition = portPositions[connection.destinationPortId];

      if (startPosition == null || endPosition == null) continue;

      // Scale to mini-map coordinates
      final startMiniMap = Offset(
        startPosition.dx * scaleFactor,
        startPosition.dy * scaleFactor,
      );
      final endMiniMap = Offset(
        endPosition.dx * scaleFactor,
        endPosition.dy * scaleFactor,
      );

      // Skip connections that are completely outside bounds
      if (!_isLineInBounds(startMiniMap, endMiniMap, size)) continue;

      // Determine connection color based on connection type
      Color connectionColor;
      switch (connection.connectionType) {
        case ConnectionType.hardwareInput:
          connectionColor = theme.colorScheme.secondary.withValues(alpha: 0.7);
          break;
        case ConnectionType.hardwareOutput:
          connectionColor = theme.colorScheme.tertiary.withValues(alpha: 0.7);
          break;
        case ConnectionType.algorithmToAlgorithm:
          connectionColor = theme.colorScheme.primary.withValues(alpha: 0.6);
          break;
        default:
          connectionColor = theme.colorScheme.outline.withValues(alpha: 0.5);
      }

      connectionPaint.color = connectionColor;

      // Draw straight line connection (no curves in mini-map)
      canvas.drawLine(startMiniMap, endMiniMap, connectionPaint);
    }
  }

  /// Clip a rectangle to fit within the given size bounds
  Rect _clipRectToSize(Rect rect, Size size) {
    final clippedLeft = rect.left.clamp(0.0, size.width);
    final clippedTop = rect.top.clamp(0.0, size.height);
    final clippedRight = rect.right.clamp(0.0, size.width);
    final clippedBottom = rect.bottom.clamp(0.0, size.height);

    return Rect.fromLTRB(clippedLeft, clippedTop, clippedRight, clippedBottom);
  }

  /// Check if a line between two points intersects with the mini-map bounds
  bool _isLineInBounds(Offset start, Offset end, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);

    // Quick check: if either point is inside bounds, line is visible
    if (bounds.contains(start) || bounds.contains(end)) return true;

    // Check if line crosses any edge of the bounds
    return _lineIntersectsRect(start, end, bounds);
  }

  /// Check if a line intersects with a rectangle
  bool _lineIntersectsRect(Offset start, Offset end, Rect rect) {
    // Use simple bounds check for performance
    final minX = (start.dx < end.dx) ? start.dx : end.dx;
    final maxX = (start.dx > end.dx) ? start.dx : end.dx;
    final minY = (start.dy < end.dy) ? start.dy : end.dy;
    final maxY = (start.dy > end.dy) ? start.dy : end.dy;

    return !(maxX < rect.left ||
        minX > rect.right ||
        maxY < rect.top ||
        minY > rect.bottom);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.viewportOffset != viewportOffset ||
        oldDelegate.scaleFactor != scaleFactor ||
        oldDelegate.theme != theme ||
        oldDelegate.canvasWidth != canvasWidth ||
        oldDelegate.canvasHeight != canvasHeight ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.highlightViewportRectangle != highlightViewportRectangle ||
        !_mapEquals(oldDelegate.nodePositions, nodePositions) ||
        !_listEquals(oldDelegate.connections, connections) ||
        !_mapEquals(oldDelegate.portPositions, portPositions);
  }

  /// Compare two maps for equality
  bool _mapEquals<K, V>(Map<K, V>? a, Map<K, V>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  /// Compare two lists for equality
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
