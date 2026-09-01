import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart'
    as painter;

/// Widget that handles platform-specific interactions for connection deletion
///
/// This widget provides two modes:
/// - Desktop: Hover detection with delete button overlay at connection midpoint
/// - Mobile: Tap-based selection with confirmation dialogs
///
/// Can be used in two ways:
/// 1. Wrap mode: Takes a child widget and overlays interaction on top
/// 2. Connection mode: Takes connectionData and renders the connection with interaction
class InteractiveConnectionWidget extends StatefulWidget {
  const InteractiveConnectionWidget({
    super.key,
    required this.connection,
    required this.routingEditorCubit,
    this.child,
    this.connectionData,
    this.size,
    this.onHoverChange,
    this.platformService,
  });

  final Connection connection;
  final RoutingEditorCubit routingEditorCubit;
  final Widget? child;
  final painter.ConnectionData? connectionData;
  final Size? size;
  final ValueChanged<bool>? onHoverChange;
  final PlatformInteractionService? platformService;

  @override
  State<InteractiveConnectionWidget> createState() =>
      _InteractiveConnectionWidgetState();
}

class _InteractiveConnectionWidgetState
    extends State<InteractiveConnectionWidget>
    with SingleTickerProviderStateMixin {
  late final PlatformInteractionService _platformService;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;

  bool _isHovering = false;
  bool _isSelected = false;
  Offset? _deleteButtonPosition;

  @override
  void initState() {
    super.initState();
    _platformService = widget.platformService ?? PlatformInteractionService();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHoverEnter([PointerEnterEvent? event]) {
    if (!_platformService.supportsHoverInteractions()) return;

    setState(() {
      _isHovering = true;
      // For connection data mode, position delete button along the connection curve
      if (widget.connectionData != null) {
        _deleteButtonPosition = _calculateConnectionDeletePosition();
      }
    });
    _animationController.forward();
    widget.onHoverChange?.call(true);
  }

  void _onHoverExit([PointerExitEvent? event]) {
    if (!_platformService.supportsHoverInteractions()) return;

    setState(() {
      _isHovering = false;
      _deleteButtonPosition = null;
    });
    _animationController.reverse();
    widget.onHoverChange?.call(false);
  }

  void _onTap() {
    if (_platformService.supportsHoverInteractions()) {
      // Desktop: Direct delete on click (when hovering)
      if (_isHovering) {
        _deleteConnection();
      }
    } else {
      // Mobile: Toggle selection
      setState(() {
        _isSelected = !_isSelected;
      });

      if (_isSelected) {
        _showDeleteConfirmationDialog();
      }
    }
  }

  void _onLongPress() {
    if (!_platformService.shouldUseTouchInteractions()) return;

    // Mobile long press: Show delete confirmation
    _showDeleteConfirmationDialog();
  }

  /// Calculate the optimal position for the delete button along the connection curve
  /// Places it at a point on the curve that's away from labels and easily clickable
  Offset _calculateConnectionDeletePosition() {
    if (widget.connectionData == null) return Offset.zero;

    final sourcePos = widget.connectionData!.sourcePosition;
    final destPos = widget.connectionData!.destinationPosition;

    // Calculate point at 90% along the cubic bezier curve (near the destination)
    const t = 0.9; // Position along curve (0 = source, 1 = destination)

    // Create control points for the cubic bezier (same as in ConnectionPainter)
    final controlPoint1 = Offset(
      sourcePos.dx + (destPos.dx - sourcePos.dx) * 0.5,
      sourcePos.dy,
    );
    final controlPoint2 = Offset(
      destPos.dx - (destPos.dx - sourcePos.dx) * 0.5,
      destPos.dy,
    );

    // Calculate point on cubic bezier curve using De Casteljau's algorithm
    final x = _cubicBezier(
      sourcePos.dx,
      controlPoint1.dx,
      controlPoint2.dx,
      destPos.dx,
      t,
    );
    final y = _cubicBezier(
      sourcePos.dy,
      controlPoint1.dy,
      controlPoint2.dy,
      destPos.dy,
      t,
    );

    return Offset(x, y);
  }

  /// Calculate point on cubic bezier curve at parameter t
  double _cubicBezier(double p0, double p1, double p2, double p3, double t) {
    final oneMinusT = 1 - t;
    return oneMinusT * oneMinusT * oneMinusT * p0 +
        3 * oneMinusT * oneMinusT * t * p1 +
        3 * oneMinusT * t * t * p2 +
        t * t * t * p3;
  }

  /// Build a single narrow hover region along the connection line
  Widget _buildConnectionHoverRegion() {
    if (widget.connectionData == null) return const SizedBox.shrink();

    final sourcePos = widget.connectionData!.sourcePosition;
    final destPos = widget.connectionData!.destinationPosition;

    // Calculate bounds for the connection area
    final left = (sourcePos.dx < destPos.dx ? sourcePos.dx : destPos.dx) - 10;
    final right = (sourcePos.dx > destPos.dx ? sourcePos.dx : destPos.dx) + 10;
    final top = (sourcePos.dy < destPos.dy ? sourcePos.dy : destPos.dy) - 10;
    final bottom = (sourcePos.dy > destPos.dy ? sourcePos.dy : destPos.dy) + 10;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: MouseRegion(
          onEnter: _onHoverEnter,
          onExit: _onHoverExit,
          child: CustomPaint(
            size: Size(right - left, bottom - top),
            painter: _ConnectionHoverPainter(
              connectionData: widget.connectionData!,
              offsetX: -left,
              offsetY: -top,
              isHovering: _isHovering,
              hoverColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteConnection() async {
    try {
      await widget.routingEditorCubit.deleteConnectionWithSmartBusLogic(
        widget.connection.id,
      );

      // Reset interaction state after successful deletion
      if (mounted) {
        setState(() {
          _isHovering = false;
          _isSelected = false;
          _deleteButtonPosition = null;
        });
        _animationController.reset();
      }
    } catch (e) {
      // Show error feedback to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete connection: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showDeleteConfirmationDialog() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: const Text('Are you sure you want to delete this connection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteConnection();
    } else {
      // Reset selection if cancelled
      setState(() {
        _isSelected = false;
      });
    }
  }

  Widget _buildDeleteButton() {
    if (!_isHovering && !_isSelected) return const SizedBox.shrink();

    final minSize = _platformService.getMinimumTouchTargetSize();

    // For connection data mode, position button at connection midpoint
    if (widget.connectionData != null && _deleteButtonPosition != null) {
      return Positioned(
        left: _deleteButtonPosition!.dx - minSize / 2,
        top: _deleteButtonPosition!.dy - minSize / 2,
        child: AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnimation.value,
              child: GestureDetector(
                onTap: _deleteConnection,
                child: Container(
                  width: minSize,
                  height: minSize,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.shadow.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.close,
                    color: Theme.of(context).colorScheme.onError,
                    size: minSize * 0.5,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    // For wrap mode, center the button
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _platformService.supportsHoverInteractions()
                ? _fadeAnimation.value
                : (_isSelected ? 1.0 : 0.0),
            child: Center(
              child: Container(
                width: minSize,
                height: minSize,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.shadow.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.onError,
                  size: minSize * 0.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _getConnectionSemanticLabel() {
    final conn = widget.connection;
    final parts = <String>[
      'Connection from ${conn.sourcePortId} to ${conn.destinationPortId}',
    ];
    final busLabel = widget.connectionData?.busLabel ?? conn.busLabel;
    if (busLabel != null && busLabel.isNotEmpty) {
      parts.add('on bus $busLabel');
    }
    switch (widget.connectionData?.outputMode ?? conn.outputMode) {
      case OutputMode.add:
        parts.add('Add mode');
      case OutputMode.replace:
        parts.add('Replace mode');
      case null:
        break;
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    // Connection data mode: render the connection with hover detection
    if (widget.connectionData != null) {
      final editorState = widget.routingEditorCubit.state;
      final hasExtended =
          editorState is RoutingEditorStateLoaded &&
          editorState.hasExtendedAuxBuses;
      final deviceIoProfile = editorState is RoutingEditorStateLoaded
          ? editorState.deviceIoProfile
          : DeviceIoProfile.distingExtended;

      if (!_platformService.supportsHoverInteractions()) {
        // Mobile: just render the connection without hover
        return Semantics(
          label: _getConnectionSemanticLabel(),
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Delete this connection'): () =>
                _showDeleteConfirmationDialog(),
          },
          child: CustomPaint(
            size: widget.size ?? Size.zero,
            painter: painter.ConnectionPainter(
              connections: [widget.connectionData!],
              theme: Theme.of(context),
              showLabels: true,
              hasExtendedAuxBuses: hasExtended,
              deviceIoProfile: deviceIoProfile,
            ),
          ),
        );
      }

      // Desktop: render with hover detection
      return Semantics(
        label: _getConnectionSemanticLabel(),
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Delete this connection'): () =>
              _deleteConnection(),
        },
        child: Stack(
          children: [
            // Render the actual connection
            CustomPaint(
              size: widget.size ?? Size.zero,
              painter: painter.ConnectionPainter(
                connections: [widget.connectionData!],
                theme: Theme.of(context),
                showLabels: true,
                hoveredConnectionId: _isHovering
                    ? widget.connectionData!.connection.id
                    : null,
                hasExtendedAuxBuses: hasExtended,
                deviceIoProfile: deviceIoProfile,
              ),
            ),

            // Single hover region along connection with very narrow hit area
            _buildConnectionHoverRegion(),

            // Delete button overlay
            _buildDeleteButton(),
          ],
        ),
      );
    }

    // Wrap mode: legacy behavior with child widget
    Widget interactiveChild = widget.child ?? const SizedBox();

    // Wrap with appropriate gesture detectors based on platform
    if (_platformService.supportsHoverInteractions()) {
      // Desktop: Mouse hover and click
      interactiveChild = MouseRegion(
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.opaque,
          child: interactiveChild,
        ),
      );
    } else {
      // Mobile: Tap and long press
      interactiveChild = GestureDetector(
        onTap: _onTap,
        onLongPress: _onLongPress,
        behavior: HitTestBehavior.opaque,
        child: interactiveChild,
      );
    }

    // Add selection highlight for mobile
    if (_isSelected && _platformService.shouldUseTouchInteractions()) {
      interactiveChild = Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: interactiveChild,
      );
    }

    return Stack(children: [interactiveChild, _buildDeleteButton()]);
  }
}

/// Painter that provides precise hit testing only along the connection path
class _ConnectionHoverPainter extends CustomPainter {
  final painter.ConnectionData connectionData;
  final double offsetX;
  final double offsetY;
  final bool isHovering;
  final Color hoverColor;

  const _ConnectionHoverPainter({
    required this.connectionData,
    required this.offsetX,
    required this.offsetY,
    required this.isHovering,
    required this.hoverColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isHovering) {
      // Optional debug visualization
      final debugPaint = Paint()
        ..color = hoverColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0;

      canvas.drawPath(_createConnectionPath(), debugPaint);
    }
  }

  @override
  bool hitTest(Offset position) {
    final path = _createConnectionPath();
    return _isPointNearPath(path, position, hitRadius: 8.0);
  }

  Path _createConnectionPath() {
    final sourcePos = Offset(
      connectionData.sourcePosition.dx + offsetX,
      connectionData.sourcePosition.dy + offsetY,
    );
    final destPos = Offset(
      connectionData.destinationPosition.dx + offsetX,
      connectionData.destinationPosition.dy + offsetY,
    );

    final path = Path();
    path.moveTo(sourcePos.dx, sourcePos.dy);

    // Create the same cubic bezier curve as ConnectionPainter
    final controlPoint1 = Offset(
      sourcePos.dx + (destPos.dx - sourcePos.dx) * 0.5,
      sourcePos.dy,
    );
    final controlPoint2 = Offset(
      destPos.dx - (destPos.dx - sourcePos.dx) * 0.5,
      destPos.dy,
    );

    path.cubicTo(
      controlPoint1.dx,
      controlPoint1.dy,
      controlPoint2.dx,
      controlPoint2.dy,
      destPos.dx,
      destPos.dy,
    );

    return path;
  }

  bool _isPointNearPath(Path path, Offset point, {required double hitRadius}) {
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      final length = metric.length;
      const step = 2.0;

      for (double distance = 0; distance <= length; distance += step) {
        final pos = metric.getTangentForOffset(distance)?.position;
        if (pos != null) {
          final distanceToPoint = (point - pos).distance;
          if (distanceToPoint <= hitRadius) {
            return true;
          }
        }
      }
    }

    return false;
  }

  @override
  bool shouldRepaint(covariant _ConnectionHoverPainter oldDelegate) {
    return isHovering != oldDelegate.isHovering ||
        connectionData != oldDelegate.connectionData;
  }
}
