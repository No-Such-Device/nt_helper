import 'dart:math' as math;
import 'dart:ui' as dart_ui;
import 'package:flutter/material.dart';
import 'package:nt_helper/core/routing/models/connection.dart'
    show Connection, ConnectionType;
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:collection/collection.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'accessibility_colors.dart';
import 'ghost_connection_tooltip.dart';
import 'connection_theme.dart';
import 'bus_label_formatter.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Represents connection data with bus and output mode information
class ConnectionData {
  final Connection connection;
  final Offset sourcePosition;
  final Offset destinationPosition;
  final int? busNumber;
  final OutputMode? outputMode; // Output mode from source port
  final bool isSelected;
  final bool isHighlighted;
  final bool isPhysicalConnection; // True if this is a physical connection
  final bool?
  isInputConnection; // True if physical input connection, false if output, null if not physical
  final String? busLabel; // Bus label for partial connections
  final Function(bool isHovering)?
  onLabelHover; // Callback for label hover events
  final VoidCallback? onLabelTap; // Callback for label tap events
  final bool isDimmed; // True when connection should be dimmed in focus mode

  const ConnectionData({
    required this.connection,
    required this.sourcePosition,
    required this.destinationPosition,
    this.busNumber,
    this.outputMode,
    this.isSelected = false,
    this.isHighlighted = false,
    this.isPhysicalConnection = false,
    this.isInputConnection,
    this.busLabel,
    this.onLabelHover,
    this.onLabelTap,
    this.sourceNodeBounds,
    this.destinationNodeBounds,
    this.sourceOccluderBounds = const [],
    this.destinationOccluderBounds = const [],
    this.isDimmed = false,
  });

  final Rect? sourceNodeBounds;
  final Rect? destinationNodeBounds;
  final List<Rect> sourceOccluderBounds;
  final List<Rect> destinationOccluderBounds;

  /// Convenience getter for ghost connection status from the connection model
  bool get isGhostConnection => connection.isGhostConnection;

  /// Convenience getter for invalid order status (backward edge)
  bool get isInvalidOrder => connection.isBackwardEdge;

  /// Convenience getter for partial connection status from the connection model
  bool get isPartial => connection.isPartial;
}

/// Custom painter for efficiently rendering multiple connection lines
///
/// This painter is optimized for rendering many connections in a single
/// paint operation, with support for overlap avoidance, connection types,
/// bus labeling, and animated flow effects for ghost connections.
class ConnectionPainter extends CustomPainter {
  final List<ConnectionData> connections;
  final ThemeData theme;
  final ConnectionStateManager? connectionStateManager;
  final bool enableAntiOverlap;
  final bool showLabels;
  final bool enableAnimations;
  final double? animationProgress;
  final String? hoveredConnectionId;
  final List<Rect> obstacles;
  final bool drawEndpointsOnly;

  /// Port ID being long-pressed for deletion animation
  final String? deletingPortId;

  /// Progress of delete animation (0.0 to 1.0) - red → orange → white
  final double deleteAnimationProgress;

  /// Progress of fade-out animation (0.0 to 1.0) - white → transparent
  final double fadeOutProgress;
  final bool hasExtendedAuxBuses;
  final DeviceIoProfile deviceIoProfile;

  /// Map storing label bounds for hit testing
  final Map<String, Rect> _labelBounds = {};

  ConnectionPainter({
    required this.connections,
    required this.theme,
    this.connectionStateManager,
    this.enableAntiOverlap = true,
    this.showLabels = true,
    this.enableAnimations = true,
    this.animationProgress,
    this.hoveredConnectionId,
    this.obstacles = const [],
    this.drawEndpointsOnly = false,
    this.deletingPortId,
    this.deleteAnimationProgress = 0.0,
    this.fadeOutProgress = 0.0,
    this.hasExtendedAuxBuses = false,
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  });

  /// Classify a connection into the visual style bucket used for batching.
  ///
  /// Precedence (highest first): selected, partial, invalid (backward edge),
  /// ghost, regular. Selection is a transient user-driven highlight and wins
  /// over backward-edge styling. A backward edge that is also partial renders
  /// as partial, because an incomplete connection is the more important
  /// signal than a deferred-bus warning.
  @visibleForTesting
  static ConnectionVisualType classifyVisualType(ConnectionData conn) {
    if (conn.isSelected) return ConnectionVisualType.selected;
    if (conn.isPartial) return ConnectionVisualType.partial;
    if (conn.isInvalidOrder) return ConnectionVisualType.invalid;
    if (conn.isGhostConnection) return ConnectionVisualType.ghost;
    return ConnectionVisualType.regular;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (connections.isEmpty) return;

    // Clear previous label bounds
    _labelBounds.clear();

    // Group connections by type for batch rendering
    final regularConnections = <ConnectionData>[];
    final ghostConnections = <ConnectionData>[];
    final invalidConnections = <ConnectionData>[];
    final selectedConnections = <ConnectionData>[];
    final partialConnections = <ConnectionData>[];
    for (final conn in connections) {
      switch (classifyVisualType(conn)) {
        case ConnectionVisualType.selected:
          selectedConnections.add(conn);
          break;
        case ConnectionVisualType.partial:
          partialConnections.add(conn);
          break;
        case ConnectionVisualType.invalid:
          invalidConnections.add(conn);
          break;
        case ConnectionVisualType.ghost:
          ghostConnections.add(conn);
          break;
        case ConnectionVisualType.regular:
          regularConnections.add(conn);
          break;
      }
    }

    // Draw in order: regular -> ghost -> invalid -> partial -> backward partial -> selected
    _drawConnectionBatch(
      canvas,
      regularConnections,
      ConnectionVisualType.regular,
    );
    _drawConnectionBatch(canvas, ghostConnections, ConnectionVisualType.ghost);
    _drawConnectionBatch(
      canvas,
      invalidConnections,
      ConnectionVisualType.invalid,
    );
    _drawConnectionBatch(
      canvas,
      partialConnections,
      ConnectionVisualType.partial,
    );
    _drawConnectionBatch(
      canvas,
      selectedConnections,
      ConnectionVisualType.selected,
    );

    // Draw labels for regular connections only
    // Partial connections get their bus label drawn at the endpoint
    // via _drawPartialConnectionBusLabel, not at the midpoint
    if (showLabels) {
      for (final conn in regularConnections) {
        _drawConnectionLabel(canvas, conn);
      }
    }
  }

  /// Draw a batch of connections of the same type
  void _drawConnectionBatch(
    Canvas canvas,
    List<ConnectionData> batch,
    ConnectionVisualType type,
  ) {
    if (batch.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final conn in batch) {
      // Calculate path - special handling for partial connections
      Path path;
      if (type == ConnectionVisualType.partial) {
        // For partial connections, create a short straight line to the label
        path = _createPartialConnectionPath(conn);
      } else {
        // Regular path calculation for other connection types
        path = enableAntiOverlap
            ? _createRoutedPath(
                conn,
                connections,
              ) // Use ALL connections for routing
            : _createDirectPath(conn.sourcePosition, conn.destinationPosition);
      }

      // Apply visual style based on connection type
      _applyConnectionStyle(paint, conn, type);

      // Draw the connection
      if (type == ConnectionVisualType.ghost) {
        _drawDashedPath(canvas, path, paint);
      } else if (type == ConnectionVisualType.invalid) {
        _drawDottedPath(canvas, path, paint);
      } else if (type == ConnectionVisualType.partial) {
        _drawDashedPath(canvas, path, paint);

        // Draw bus label at the endpoint for partial connections
        _drawPartialConnectionBusLabel(canvas, conn);
      } else {
        // Draw the path
        if (drawEndpointsOnly) {
          // Draw path clipped to source and destination node bounds.
          // Additionally, subtract ("difference") any node bounds that are above
          // the endpoint node in z-order so overlapping nodes still occlude the
          // endpoint overlay.
          if (conn.sourceNodeBounds != null) {
            _drawClippedEndpointPath(
              canvas,
              path,
              paint,
              endpointBounds: conn.sourceNodeBounds!,
              occluderBounds: conn.sourceOccluderBounds,
            );
          }

          if (conn.destinationNodeBounds != null) {
            _drawClippedEndpointPath(
              canvas,
              path,
              paint,
              endpointBounds: conn.destinationNodeBounds!,
              occluderBounds: conn.destinationOccluderBounds,
            );
          }
        } else {
          // Draw full path
          canvas.drawPath(path, paint);
        }
      }

      // Draw endpoints (skip for partial and invalid connections; the latter
      // because port-color circles over an orange dot read as a
      // "double-ended broken connection").
      if (type != ConnectionVisualType.partial &&
          type != ConnectionVisualType.invalid) {
        _drawEndpoints(canvas, conn);
      }
    }
  }

  void _drawClippedEndpointPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required Rect endpointBounds,
    required List<Rect> occluderBounds,
  }) {
    canvas.save();
    canvas.clipRect(endpointBounds);
    for (final rect in occluderBounds) {
      if (!rect.overlaps(endpointBounds)) continue;
      canvas.clipRect(rect, clipOp: dart_ui.ClipOp.difference);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  // Removed _clipPathAgainstObstacles as it is no longer used

  /// Create a bezier path with routing to avoid overlaps
  Path _createRoutedPath(
    ConnectionData connection,
    List<ConnectionData> allConnections,
  ) {
    final start = connection.sourcePosition;
    final end = connection.destinationPosition;

    // Find overlapping connections
    final overlaps = _findOverlappingConnections(connection, allConnections);

    if (overlaps.isEmpty) {
      return _createDirectPath(start, end);
    }

    // Calculate offset to avoid overlaps
    final offsetIndex = overlaps.indexOf(connection);
    final offsetAmount = (offsetIndex + 1) * 10.0;

    return _createOffsetPath(start, end, offsetAmount);
  }

  /// Find connections that overlap with the given connection
  List<ConnectionData> _findOverlappingConnections(
    ConnectionData target,
    List<ConnectionData> connections,
  ) {
    final overlapping = <ConnectionData>[];

    for (final conn in connections) {
      if (conn == target) continue;

      // Check if connections share similar paths
      if (_pathsOverlap(target, conn)) {
        overlapping.add(conn);
      }
    }

    return overlapping;
  }

  /// Check if two connection paths overlap
  bool _pathsOverlap(ConnectionData a, ConnectionData b) {
    // Simple overlap detection based on endpoint proximity
    const threshold = 50.0;

    final startDistance = (a.sourcePosition - b.sourcePosition).distance;
    final endDistance =
        (a.destinationPosition - b.destinationPosition).distance;

    return startDistance < threshold && endDistance < threshold;
  }

  /// Create a direct bezier path between two points
  Path _createDirectPath(Offset start, Offset end) {
    return _createOffsetPath(start, end, 0);
  }

  /// Create an offset bezier path to avoid overlaps
  Path _createOffsetPath(Offset start, Offset end, double offset) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final dx = end.dx - start.dx;
    final controlOffset = (dx.abs() * 0.5).clamp(30.0, 150.0);

    // Initial control points with basic offset
    var cp1Y = start.dy + offset;
    var cp2Y = end.dy + offset;

    // Add vertical offset to control points
    final cp1 = Offset(
      start.dx + (dx > 0 ? controlOffset : -controlOffset),
      cp1Y,
    );
    final cp2 = Offset(
      end.dx - (dx > 0 ? controlOffset : -controlOffset),
      cp2Y,
    );

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    return path;
  }

  /// Create a short straight path for partial connections
  Path _createPartialConnectionPath(ConnectionData conn) {
    final path = Path();

    // For partial connections, we already have the correct positions:
    // - sourcePosition is the port (or label for inputs)
    // - destinationPosition is the label (or port for inputs)
    // Just draw a straight line between them
    path.moveTo(conn.sourcePosition.dx, conn.sourcePosition.dy);
    path.lineTo(conn.destinationPosition.dx, conn.destinationPosition.dy);

    return path;
  }

  /// Apply visual style to paint based on connection properties
  void _applyConnectionStyle(
    Paint paint,
    ConnectionData conn,
    ConnectionVisualType type,
  ) {
    // Handle backward edges (source slot index higher than destination)
    // with the theme's warning role so it remains visually distinct from the
    // muted dashed style used for partial/disconnected connections.
    if (type == ConnectionVisualType.invalid) {
      paint
        ..strokeWidth = 2.0
        ..color = theme.appColors.backwardConnection;
      return;
    }

    // Handle partial connections with distinctive styling
    if (type == ConnectionVisualType.partial) {
      paint
        ..strokeWidth = 2.0
        ..color = theme.colorScheme.onSurface.withValues(alpha: 0.6);
      return;
    }

    // Check if this connection is being deleted (involves the deleting port)
    final isBeingDeleted =
        deletingPortId != null &&
        (conn.connection.sourcePortId == deletingPortId ||
            conn.connection.destinationPortId == deletingPortId);

    if (isBeingDeleted) {
      // Two-phase animation:
      // Phase 1 (deleteAnimationProgress): red → orange → white
      // Phase 2 (fadeOutProgress): white → transparent
      final color = _getDeleteAnimationColor(
        deleteAnimationProgress,
        fadeOutProgress,
      );
      paint
        ..strokeWidth =
            3.0 // Slightly thicker during delete animation
        ..color = color;
      return;
    }

    // Get style from theme manager if available, otherwise fall back to defaults
    ConnectionStyle style;

    if (connectionStateManager != null) {
      style = connectionStateManager!.getConnectionStyle(
        conn.connection,
        outputMode: conn.outputMode,
      );
    } else {
      // Fallback to default theme
      final fallbackTheme = ConnectionVisualTheme.fromColorScheme(
        theme.colorScheme,
      );
      style = fallbackTheme.getStyleForConnection(
        connection: conn.connection,
        outputMode: conn.outputMode,
        isSelected: conn.isSelected,
        isHighlighted: conn.isHighlighted,
        hasError: conn.isInvalidOrder,
      );
    }

    // Mode-aware styles own the line colour for regular routed connections.
    // Connections without a mode retain the port-type colour blend.
    final baseColor = _getPortColor(conn.connection.sourcePortId);
    Color finalColor;

    // Replace mode only affects the "normal" (non-highlighted) appearance.
    // Hover/delete highlighting must always win.
    if (conn.isHighlighted) {
      finalColor = theme.colorScheme.error;
    } else if (type == ConnectionVisualType.regular &&
        (conn.outputMode ?? conn.connection.outputMode) != null) {
      finalColor = style.color;
    } else {
      finalColor = Color.lerp(baseColor, style.color, 0.7) ?? style.color;
    }

    // Apply focus mode dimming (unless highlighted)
    if (conn.isDimmed && !conn.isHighlighted) {
      finalColor = finalColor.withValues(alpha: 0.15);
      paint
        ..strokeWidth = style.strokeWidth * 0.7
        ..color = finalColor;
      return;
    }

    paint
      ..strokeWidth = style.strokeWidth
      ..color = finalColor;
  }

  /// Calculate the delete animation color based on two-phase progress
  /// Phase 1 (deleteProgress): red (0.0) → orange (0.5) → white (1.0)
  /// Phase 2 (fadeOutProgress): white → transparent
  Color _getDeleteAnimationColor(
    double deleteProgress,
    double fadeOutProgress,
  ) {
    // Clamp progress values
    final dp = deleteProgress.clamp(0.0, 1.0);
    final fp = fadeOutProgress.clamp(0.0, 1.0);

    // Phase 2: Fade the theme foreground to transparent.
    if (fp > 0.0) {
      return theme.colorScheme.onSurface.withValues(alpha: 1.0 - fp);
    }

    // Phase 1: Error → warning → theme foreground.
    if (dp < 0.5) {
      // Error to warning (0.0 - 0.5).
      final t = dp / 0.5;
      return Color.lerp(
        theme.colorScheme.error,
        theme.appColors.warning.color,
        t,
      )!;
    } else {
      // Warning to foreground (0.5 - 1.0).
      final t = (dp - 0.5) / 0.5;
      return Color.lerp(
        theme.appColors.warning.color,
        theme.colorScheme.onSurface,
        t,
      )!;
    }
  }

  /// Draw a stroked path as a sequence of round dots, used for backward-edge
  /// (uphill) connections. Visually distinct from the dashed pattern used for
  /// ghost/partial connections because each dot is a small filled circle, so
  /// the pattern reads as "warning" rather than "broken".
  void _drawDottedPath(Canvas canvas, Path path, Paint paint) {
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = paint.color;
    final dotRadius = paint.strokeWidth / 2;
    const dotSpacing = 6.0;

    for (final metric in path.computeMetrics()) {
      for (double d = 0.0; d <= metric.length; d += dotSpacing) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, dotRadius, dotPaint);
        }
      }
    }
  }

  /// Draw a dashed path for ghost connections
  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    final pathMetrics = path.computeMetrics();

    for (final metric in pathMetrics) {
      double distance = 0.0;
      bool draw = true;
      const dashLength = 8.0;
      const gapLength = 4.0;

      while (distance < metric.length) {
        final segmentLength = draw ? dashLength : gapLength;
        final endDistance = (distance + segmentLength).clamp(
          0.0,
          metric.length,
        );

        if (draw) {
          final segment = metric.extractPath(distance, endDistance);
          canvas.drawPath(segment, paint);
        }

        distance = endDistance;
        draw = !draw;
      }
    }
  }

  /// Find the best position along the path for the label
  /// Scans the path and picks the best spot based on:
  /// 1. Safety (must not overlap obstacles)
  /// 2. Proximity to center (t=0.5)
  /// This ensures the label "slides" just out of the way of obstacles but stays close.
  Offset _findSafeLabelPosition(
    dart_ui.PathMetric metric,
    double labelWidth,
    double labelHeight,
    Rect? sourceNodeBounds,
    Rect? destinationNodeBounds,
  ) {
    // Scan configuration
    const step = 0.01; // 1% steps
    const startT = 0.05;
    const endT = 0.95;

    // Margin for "safe" threshold
    const safeMargin = 20.0;

    Offset? bestPos;
    double maxScore = double.negativeInfinity;

    // Pre-calculate expanded obstacles to simplify point-vs-rect checks
    // We expand each obstacle by the label's half-size plus margin
    // This allows us to treat the label as a point
    final halfWidth = labelWidth / 2;
    final halfHeight = labelHeight / 2;

    final expandedObstacles = obstacles.map((rect) {
      // Use smaller margin for source/destination nodes to allow labels closer to them
      final isConnectedNode =
          rect == sourceNodeBounds || rect == destinationNodeBounds;
      final margin = isConnectedNode ? 5.0 : safeMargin;

      return Rect.fromLTRB(
        rect.left - halfWidth - margin,
        rect.top - halfHeight - margin,
        rect.right + halfWidth + margin,
        rect.bottom + halfHeight + margin,
      );
    }).toList();

    for (double t = startT; t <= endT; t += step) {
      final pos = _getPointAtT(metric, t);
      if (pos == null) continue;

      // Find distance to the nearest obstacle
      double minDistToObs = double.infinity;

      if (expandedObstacles.isEmpty) {
        minDistToObs = double.infinity;
      } else {
        for (final obs in expandedObstacles) {
          final dist = _signedDistanceToRect(pos, obs);
          if (dist < minDistToObs) {
            minDistToObs = dist;
          }
        }
      }

      // Calculate score
      double score;
      if (minDistToObs > 0) {
        // Safe spot: Prioritize proximity to center (t=0.5)
        // Score = 100000 - (distance from center * weight)
        // This ensures any safe spot beats any unsafe spot
        final distFromCenter = (t - 0.5).abs();
        score = 100000.0 - (distFromCenter * 1000.0);
      } else {
        // Unsafe spot: Prioritize minimizing overlap (maximizing signed distance)
        // Score is negative or zero
        score = minDistToObs;
      }

      // Update best position
      if (score > maxScore) {
        maxScore = score;
        bestPos = pos;
      }
    }

    // If scan failed completely (shouldn't happen), return center
    return bestPos ?? _getPointAtT(metric, 0.5) ?? Offset.zero;
  }

  /// Resolve overlap between a proposed label rect and already-placed labels.
  /// Nudges the rect downward with a 2px gap until it no longer overlaps.
  Rect _resolveOverlap(Rect proposed) {
    const gap = 2.0;
    const maxIterations = 10;
    var resolved = proposed;
    for (int i = 0; i < maxIterations; i++) {
      Rect? overlapping;
      for (final placed in _labelBounds.values) {
        if (resolved.overlaps(placed)) {
          overlapping = placed;
          break;
        }
      }
      if (overlapping == null) break;
      final shift = overlapping.bottom - resolved.top + gap;
      resolved = resolved.shift(Offset(0, shift));
    }
    return resolved;
  }

  /// Calculate signed distance from point to rect.
  /// Positive = outside. Negative = inside.
  double _signedDistanceToRect(Offset p, Rect rect) {
    // Calculate distance to each edge
    // dx > 0 if outside horizontal range
    final dx = math.max(rect.left - p.dx, p.dx - rect.right);
    // dy > 0 if outside vertical range
    final dy = math.max(rect.top - p.dy, p.dy - rect.bottom);

    if (dx > 0 || dy > 0) {
      // Outside: Euclidean distance to the nearest corner/edge
      return math.sqrt(
        math.max(0, dx) * math.max(0, dx) + math.max(0, dy) * math.max(0, dy),
      );
    } else {
      // Inside: Distance to nearest edge (negative)
      // Since both are negative, max(dx, dy) is the one closest to 0 (closest edge)
      return math.max(dx, dy);
    }
  }

  Offset? _getPointAtT(dart_ui.PathMetric metric, double t) {
    final tangent = metric.getTangentForOffset(metric.length * t);
    return tangent?.position;
  }

  /// Draw connection endpoints
  void _drawEndpoints(Canvas canvas, ConnectionData conn) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = _getPortColor(conn.connection.sourcePortId);

    const radius = 3.0;
    canvas.drawCircle(conn.sourcePosition, radius, paint);
    canvas.drawCircle(conn.destinationPosition, radius, paint);
  }

  /// Draw connection label with bus number and output mode
  void _drawConnectionLabel(Canvas canvas, ConnectionData conn) {
    if (conn.busNumber == null) {
      return;
    }

    // Use BusLabelFormatter to get the label with mode-aware formatting
    final label = formatBusLabelWithMode(
      conn.busNumber,
      conn.outputMode,
      hasExtendedAuxBuses,
      deviceIoProfile,
    );
    if (label.isEmpty) {
      return;
    }

    // If this connection is being deleted, fade the label out during the fade-out phase.
    final isBeingDeleted =
        deletingPortId != null &&
        (conn.connection.sourcePortId == deletingPortId ||
            conn.connection.destinationPortId == deletingPortId);
    final labelAlpha = isBeingDeleted
        ? (1.0 - fadeOutProgress).clamp(0.0, 1.0)
        : 1.0;

    // Create text painter with enhanced text style
    final textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface.withValues(alpha: labelAlpha),
    );

    final textPainter = createLabelTextPainter(label, textStyle);
    textPainter.layout();

    final labelWidth = textPainter.width + 12;
    final labelHeight = textPainter.height + 8;

    // Calculate midpoint - try path metrics first, fallback to simple calculation
    Offset midPoint;

    // Use the routed path logic to ensure label follows the actual line
    // We need to check for overlaps again to get the correct offset
    // This is slightly inefficient but ensures correctness
    // In a real optimized scenario, we would cache the path
    final overlaps = _findOverlappingConnections(conn, connections);
    final offsetIndex = overlaps.indexOf(conn);
    final offsetAmount = (offsetIndex + 1) * 10.0;

    final path = enableAntiOverlap
        ? _createOffsetPath(
            conn.sourcePosition,
            conn.destinationPosition,
            offsetAmount,
          )
        : _createDirectPath(conn.sourcePosition, conn.destinationPosition);

    final metrics = path.computeMetrics();

    // Find the longest contour in the path (the actual connection line)
    dart_ui.PathMetric? bestMetric;
    double maxLen = 0.0;

    for (final metric in metrics) {
      if (metric.length > maxLen) {
        maxLen = metric.length;
        bestMetric = metric;
      }
    }

    if (bestMetric != null && bestMetric.length > 0) {
      // Find a safe position along the path that doesn't overlap obstacles
      midPoint = _findSafeLabelPosition(
        bestMetric,
        labelWidth,
        labelHeight,
        conn.sourceNodeBounds,
        conn.destinationNodeBounds,
      );
    } else {
      // Fallback to simple midpoint calculation
      midPoint = Offset(
        (conn.sourcePosition.dx + conn.destinationPosition.dx) / 2,
        (conn.sourcePosition.dy + conn.destinationPosition.dy) / 2,
      );
    }

    // Calculate label position and resolve overlaps with existing labels
    var labelRect = Rect.fromCenter(
      center: midPoint,
      width: labelWidth,
      height: labelHeight,
    );
    labelRect = _resolveOverlap(labelRect);
    midPoint = labelRect.center;

    // Store label bounds for hit testing
    _labelBounds[conn.connection.id] = labelRect;

    // Draw label background with high contrast
    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = theme.colorScheme.surface.withValues(alpha: 0.95 * labelAlpha);

    // Check hover state and apply styling
    final isHovered = hoveredConnectionId == conn.connection.id;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isHovered ? 3.0 : 2.0
      ..color =
          (isHovered ? theme.colorScheme.primary : theme.colorScheme.outline)
              .withValues(alpha: labelAlpha);

    // Save canvas state
    canvas.save();

    // Draw label background
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
      backgroundPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
      borderPaint,
    );

    // Draw text
    final textOffset = Offset(
      midPoint.dx - textPainter.width / 2,
      midPoint.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, textOffset);

    // Restore canvas state
    canvas.restore();
  }

  /// Draw bus label at the endpoint of a partial connection
  void _drawPartialConnectionBusLabel(Canvas canvas, ConnectionData conn) {
    if (conn.busLabel == null || conn.busLabel!.isEmpty) {
      return;
    }

    final isBeingDeleted =
        deletingPortId != null &&
        (conn.connection.sourcePortId == deletingPortId ||
            conn.connection.destinationPortId == deletingPortId);
    final labelAlpha = isBeingDeleted
        ? (1.0 - fadeOutProgress).clamp(0.0, 1.0)
        : 1.0;

    // Determine which end has the label
    final connectionType = conn.connection.connectionType;
    final isOutputTobus = connectionType == ConnectionType.partialOutputToBus;

    // The label position is at the destination for outputs, source for inputs
    final labelCenter = isOutputTobus
        ? conn.destinationPosition
        : conn.sourcePosition;

    // Create text painter for bus label
    final textStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.onSurface.withValues(alpha: labelAlpha),
    );

    final textPainter = createLabelTextPainter(conn.busLabel!, textStyle);
    textPainter.layout();

    // Calculate label position centered at the endpoint
    final labelOffset = Offset(
      labelCenter.dx - textPainter.width / 2,
      labelCenter.dy - textPainter.height / 2,
    );

    // Create label background with padding and resolve overlaps
    var labelRect = Rect.fromLTWH(
      labelOffset.dx - 4,
      labelOffset.dy - 2,
      textPainter.width + 8,
      textPainter.height + 4,
    );
    labelRect = _resolveOverlap(labelRect);

    // Store bounds for partial connection bus labels to enable tap handling
    // Use a special prefix to distinguish from regular connection labels
    _labelBounds['partial_${conn.connection.id}'] = labelRect;

    // Draw label background with subtle styling
    final backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = theme.colorScheme.surface.withValues(alpha: 0.9 * labelAlpha);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = theme.colorScheme.outline.withValues(alpha: 0.5 * labelAlpha);

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      backgroundPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      borderPaint,
    );

    // Draw the text at the resolved position (reverse the padding)
    final resolvedLabelOffset = Offset(labelRect.left + 4, labelRect.top + 2);
    textPainter.paint(canvas, resolvedLabelOffset);
  }

  /// Calculate the midpoint of a Bezier curve path
  static Offset calculateBezierMidpoint(Offset start, Offset end) {
    // For simple implementation, use path metrics to find the actual midpoint
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final dx = end.dx - start.dx;
    final controlOffset = (dx.abs() * 0.5).clamp(30.0, 150.0);

    final cp1 = Offset(
      start.dx + (dx > 0 ? controlOffset : -controlOffset),
      start.dy,
    );
    final cp2 = Offset(
      end.dx - (dx > 0 ? controlOffset : -controlOffset),
      end.dy,
    );

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);

    final metrics = path.computeMetrics();

    // Safely iterate through metrics
    for (final metric in metrics) {
      final tangent = metric.getTangentForOffset(metric.length * 0.5);
      if (tangent != null) {
        return tangent.position;
      }
    }

    // Fallback to simple linear interpolation
    return Offset.lerp(start, end, 0.5)!;
  }

  /// Calculate the angle for label rotation based on connection direction
  static double calculateLabelAngle(Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    return math.atan2(dy, dx);
  }

  /// Format bus number into label string using BusLabelFormatter
  static String formatBusLabel(
    int? busNumber, [
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  ]) {
    return BusLabelFormatter.formatBusNumber(
          busNumber,
          hasExtendedAuxBuses: hasExtendedAuxBuses,
          deviceIoProfile: deviceIoProfile,
        ) ??
        '';
  }

  /// Format bus number into label string with mode-aware formatting using BusLabelFormatter
  static String formatBusLabelWithMode(
    int? busNumber,
    OutputMode? outputMode,
    bool hasExtendedAuxBuses, [
    DeviceIoProfile? deviceIoProfile,
  ]) {
    return BusLabelFormatter.formatBusLabelWithMode(
          busNumber,
          outputMode,
          hasExtendedAuxBuses: hasExtendedAuxBuses,
          deviceIoProfile: deviceIoProfile,
        ) ??
        '';
  }

  /// Create a TextPainter for label rendering
  static TextPainter createLabelTextPainter(String text, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    return TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
  }

  /// Create a bezier path between two points (static utility method)
  /// This uses the same bezier curve calculation as the ConnectionPainter
  static Path createBezierPath(Offset start, Offset end) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final dx = end.dx - start.dx;
    final controlOffset = (dx.abs() * 0.5).clamp(30.0, 150.0);

    final cp1 = Offset(
      start.dx + (dx > 0 ? controlOffset : -controlOffset),
      start.dy,
    );
    final cp2 = Offset(
      end.dx - (dx > 0 ? controlOffset : -controlOffset),
      end.dy,
    );

    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
    return path;
  }

  /// Get color for a port based on its type, using accessible colors
  Color _getPortColor(String portId) {
    final colors = AccessibilityColors.fromColorScheme(theme.colorScheme);
    if (portId.contains('audio')) return colors.audioPortColor;
    if (portId.contains('cv')) return colors.cvPortColor;
    if (portId.contains('gate')) return colors.gatePortColor;
    if (portId.contains('clock') || portId.contains('trigger')) {
      return colors.clockPortColor;
    }
    return theme.colorScheme.outline;
  }

  /// Resolve the stroke color a given connection would receive when painted.
  /// Exposes the result of `_applyConnectionStyle()` for unit tests.
  @visibleForTesting
  Color debugResolveStyleColor(ConnectionData conn) {
    final paint = Paint();
    _applyConnectionStyle(paint, conn, classifyVisualType(conn));
    return paint.color;
  }

  /// Resolve the stroke width a connection would receive when painted.
  /// Exposes the result of `_applyConnectionStyle()` for unit tests.
  @visibleForTesting
  double debugResolveStyleStrokeWidth(ConnectionData conn) {
    final paint = Paint();
    _applyConnectionStyle(paint, conn, classifyVisualType(conn));
    return paint.strokeWidth;
  }

  /// Get current label bounds for testing purposes
  Map<String, Rect> getLabelBounds() => Map.from(_labelBounds);

  /// Hit test for connection labels
  String? hitTestLabel(Offset point) {
    for (final entry in _labelBounds.entries) {
      if (entry.value.contains(point)) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.connections != connections ||
        oldDelegate.connectionStateManager != connectionStateManager ||
        oldDelegate.enableAntiOverlap != enableAntiOverlap ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.enableAnimations != enableAnimations ||
        oldDelegate.hoveredConnectionId != hoveredConnectionId ||
        oldDelegate.theme != theme ||
        oldDelegate.drawEndpointsOnly != drawEndpointsOnly ||
        oldDelegate.deletingPortId != deletingPortId ||
        oldDelegate.deleteAnimationProgress != deleteAnimationProgress ||
        oldDelegate.fadeOutProgress != fadeOutProgress ||
        oldDelegate.hasExtendedAuxBuses != hasExtendedAuxBuses ||
        oldDelegate.deviceIoProfile != deviceIoProfile ||
        !ListEquality().equals(oldDelegate.obstacles, obstacles);
  }
}

/// Connection type for visual styling
enum ConnectionVisualType { regular, ghost, invalid, partial, selected }

/// Widget that uses ConnectionPainter for efficient batch rendering with animation support
class ConnectionCanvas extends StatefulWidget {
  final List<ConnectionData> connections;
  final ConnectionStateManager? connectionStateManager;
  final bool enableAntiOverlap;
  final bool showLabels;
  final bool enableAnimations;
  final Function(ConnectionData)? onConnectionTapped;
  final DeviceIoProfile deviceIoProfile;

  const ConnectionCanvas({
    super.key,
    required this.connections,
    this.connectionStateManager,
    this.enableAntiOverlap = true,
    this.showLabels = true,
    this.enableAnimations = true,
    this.onConnectionTapped,
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  });

  @override
  State<ConnectionCanvas> createState() => _ConnectionCanvasState();
}

class _ConnectionCanvasState extends State<ConnectionCanvas> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Main connection rendering
        CustomPaint(
          painter: ConnectionPainter(
            connections: widget.connections,
            theme: theme,
            connectionStateManager: widget.connectionStateManager,
            enableAntiOverlap: widget.enableAntiOverlap,
            showLabels: widget.showLabels,
            enableAnimations: false,
            deviceIoProfile: widget.deviceIoProfile,
          ),
          child: Container(), // Provides hit test area
        ),
        // Invisible tooltip trigger areas for ghost connections
        ...widget.connections
            .where((conn) => conn.isGhostConnection)
            .map((conn) => _buildTooltipTrigger(conn)),
      ],
    );
  }

  /// Build an invisible hover area for tooltip triggering
  Widget _buildTooltipTrigger(ConnectionData conn) {
    // Calculate the midpoint of the connection for tooltip placement
    final midpoint = Offset(
      (conn.sourcePosition.dx + conn.destinationPosition.dx) / 2,
      (conn.sourcePosition.dy + conn.destinationPosition.dy) / 2,
    );

    return Positioned(
      left: midpoint.dx - 20, // 40px wide hit area
      top: midpoint.dy - 10, // 20px tall hit area
      child: GhostConnectionTooltip(
        connection: conn.connection,
        child: Container(
          width: 40,
          height: 20,
          color: Colors.transparent, // Invisible but accepts hover events
        ),
      ),
    );
  }
}
