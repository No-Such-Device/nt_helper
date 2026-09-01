import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert' as convert;

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/core/routing/node_layout_algorithm.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/zoom_hotkey_service.dart';
import 'package:nt_helper/models/device_io_profile.dart';
// Haptics can be reintroduced later if needed
import 'package:nt_helper/ui/widgets/routing/accessible_routing_list_view.dart';
import 'package:nt_helper/ui/widgets/routing/algorithm_node_widget.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart'
    as painter;
import 'package:nt_helper/ui/widgets/routing/connection_validator.dart';
import 'package:nt_helper/ui/widgets/routing/aux_bus_usage_widget.dart';
import 'package:nt_helper/ui/widgets/routing/mini_map_widget.dart';
import 'package:nt_helper/ui/widgets/routing/physical_input_node.dart';
import 'package:nt_helper/ui/widgets/routing/physical_output_node.dart';
import 'package:nt_helper/ui/widgets/routing/es5_node.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_controller.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_view.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

enum RoutingEditorViewMode {
  canvas,
  list,
  table,
  busLanes;

  static const _prefsKey = 'routing_view_mode';

  static RoutingEditorViewMode fromString(String? value) => switch (value) {
    'list' => list,
    'table' => table,
    'busLanes' => busLanes,
    _ => canvas,
  };
}

/// RoutingEditorWidget is the canonical widget for the routing editor UI.
/// It composes the routing canvas and exposes the same API for compatibility.
class RoutingEditorWidget extends StatefulWidget {
  final Object? routingFactory; // ignored (decisions in cubit)
  final Size canvasSize;
  final bool showPhysicalPorts;
  final bool showBusLabels;
  final Function(String nodeId)? onNodeSelected;
  final Function(String sourcePortId, String targetPortId)? onConnectionCreated;
  final Function(String connectionId)? onConnectionRemoved;
  final PlatformInteractionService? platformService;
  final RoutingEditorController? controller;
  final KeyBindingService? keyBindingService;
  final ValueChanged<RoutingEditorViewMode>? onViewModeChanged;

  RoutingEditorWidget({
    super.key,
    this.routingFactory,
    this.canvasSize = const Size(1200, 800),
    this.showPhysicalPorts = true,
    bool? showBusLabels,
    this.onNodeSelected,
    this.onConnectionCreated,
    this.onConnectionRemoved,
    this.platformService,
    this.controller,
    this.keyBindingService,
    this.onViewModeChanged,
  }) : showBusLabels = showBusLabels ?? (canvasSize.width >= 800);

  @override
  State<RoutingEditorWidget> createState() => _RoutingEditorWidgetState();
}

class _RoutingEditorWidgetState extends State<RoutingEditorWidget>
    with TickerProviderStateMixin {
  // Map of node IDs to their positions
  final Map<String, Offset> _nodePositions = {};
  // Map of node IDs to their actual rendered sizes
  final Map<String, Size> _nodeSizes = {};
  final Set<String> _selectedNodes = {};

  // Drag state management for connection creation
  bool _isDraggingConnection = false;
  Port? _dragSourcePort;
  Offset? _dragCurrentPosition;
  _ConnectionHighlight? _connectionHighlight; // single highlighted connection
  String? _hoveredLabelConnectionId; // For label hover (mode switching)
  String? _highlightedPortId; // For port highlighting during drag operations
  Timer? _connectionHighlightTimer;

  // Error handling state
  String? _errorMessage;
  Timer? _errorDismissTimer;
  Timer? _dragUpdateDebounceTimer;

  // Delete animation state
  late AnimationController _deleteAnimationController;
  late Animation<double> _deleteAnimation;
  late AnimationController _fadeOutAnimationController;
  late Animation<double> _fadeOutAnimation;
  String? _deletingPortId;
  Port? _deletingPort;
  bool _isFadingOut =
      false; // True during the final fade-out phase (not cancellable)

  // View mode toggle (canvas, list, table) — persisted via SharedPreferences
  RoutingEditorViewMode _viewMode = RoutingEditorViewMode.canvas;
  bool _viewModeLoaded = false;
  Timer? _scrollSaveTimer;
  // Tracks the last known scroll offset so it can be restored when the canvas
  // re-enters the tree (e.g. after switching away to list/table view).
  Offset _lastScrollOffset = Offset.zero;

  Future<void> _loadViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(RoutingEditorViewMode._prefsKey);
    if (mounted) {
      setState(() {
        if (saved != null) _viewMode = RoutingEditorViewMode.fromString(saved);
        _viewModeLoaded = true;
      });
      widget.onViewModeChanged?.call(_viewMode);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cubitState = context.read<RoutingEditorCubit>().state;
        final pan = cubitState is RoutingEditorStateLoaded
            ? cubitState.panOffset
            : Offset.zero;
        if (pan != Offset.zero) {
          if (_horizontalScrollController.hasClients) {
            _horizontalScrollController.jumpTo(pan.dx);
          }
          if (_verticalScrollController.hasClients) {
            _verticalScrollController.jumpTo(pan.dy);
          }
        } else {
          _fitToView();
        }
      });
    }
  }

  void _setViewMode(RoutingEditorViewMode mode) {
    setState(() => _viewMode = mode);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(RoutingEditorViewMode._prefsKey, mode.name),
    );
    widget.onViewModeChanged?.call(mode);
    if (mode == RoutingEditorViewMode.canvas) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _lastScrollOffset != Offset.zero
            ? _lastScrollOffset
            : (context.read<RoutingEditorCubit>().state
                      is RoutingEditorStateLoaded
                  ? (context.read<RoutingEditorCubit>().state
                            as RoutingEditorStateLoaded)
                        .panOffset
                  : Offset.zero);
        if (target != Offset.zero) {
          if (_horizontalScrollController.hasClients) {
            _horizontalScrollController.jumpTo(target.dx);
          }
          if (_verticalScrollController.hasClients) {
            _verticalScrollController.jumpTo(target.dy);
          }
        } else {
          _fitToView();
        }
      });
    }
  }

  // Platform service for hover detection
  late final PlatformInteractionService _platformService;
  late final KeyBindingService _keyBindingService;

  // ScrollControllers for manual pan control
  late ScrollController _horizontalScrollController;
  late ScrollController _verticalScrollController;
  // Canvas container key for coordinate transforms
  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _captureKey = GlobalKey();
  final FocusNode _canvasFocusNode = FocusNode();

  // Canvas dimensions
  static const double _canvasWidth = 5000.0;
  static const double _canvasHeight = 5000.0;

  // Dragging state for canvas pan
  bool _isPanning = false;
  Offset _lastPanPosition = Offset.zero;
  bool _isDraggingNode = false;

  // Store the current connection label bounds for hit testing
  Map<String, Rect> _connectionLabelBounds = {};

  // Actual port positions from widget callbacks
  final Map<String, Offset> _portPositions = {};
  List<Connection> _latestConnections = const [];
  final Map<String, Port> _portById = {};
  Set<String> _focusedAlgorithmIds = const {};
  StreamSubscription<ZoomHotkeyAction>? _zoomHotkeySubscription;

  // Multi-drag state: when dragging a selected node, all selected nodes move together
  Map<String, Offset> _multiDragStartPositions = {};
  String? _multiDragPrimaryNodeId;

  // Ephemeral fading overlays for labels of connections deleted instantly (click delete).
  final List<_FadingDeletedConnectionLabel> _fadingDeletedConnectionLabels = [];

  // Pending connection source for keyboard connection creation flow
  String? _pendingConnectionSourcePortId;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    _platformService = widget.platformService ?? PlatformInteractionService();
    _keyBindingService =
        widget.keyBindingService ??
        KeyBindingService(platformInteractionService: _platformService);
    _horizontalScrollController = ScrollController();
    _verticalScrollController = ScrollController();
    _horizontalScrollController.addListener(_onScrollChanged);
    _verticalScrollController.addListener(_onScrollChanged);

    // Initialize delete animation controller (red → orange → white phase)
    _deleteAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _deleteAnimation = CurvedAnimation(
      parent: _deleteAnimationController,
      curve: Curves.easeInOut,
    );
    _deleteAnimationController.addStatusListener(_onDeleteAnimationStatus);
    _deleteAnimationController.addListener(_onDeleteAnimationTick);

    // Initialize fade-out animation controller (quick white → transparent phase)
    _fadeOutAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _fadeOutAnimation = CurvedAnimation(
      parent: _fadeOutAnimationController,
      curve: Curves.easeOut,
    );
    _fadeOutAnimationController.addStatusListener(_onFadeOutAnimationStatus);
    _fadeOutAnimationController.addListener(_onDeleteAnimationTick);

    // Attach controller if provided
    widget.controller?.attach(
      fitToView: _fitToView,
      // Default copy uses exact viewport crop (same size/aspect, no minimap).
      copyCanvasImage: _copyCanvasImageViewport,
      copyCanvasImageFit: _copyCanvasImageToClipboardFit,
      copyNodesImage: _copyNodesAreaToClipboard,
      shareCanvasImage: _shareCanvasViewportImage,
      shareNodesImage: _shareNodesAreaImage,
      showError: _showError,
    );

    _initializeNodePositions();

    if (_platformService.usesCommandModifier()) {
      _zoomHotkeySubscription = ZoomHotkeyService.instance.stream.listen(
        _handleZoomHotkeyAction,
      );
    }
  }

  void _centerCanvas() {
    // Center the scroll view on the canvas
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.jumpTo(
        (_canvasWidth - widget.canvasSize.width) / 2,
      );
    }
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.jumpTo(
        (_canvasHeight - widget.canvasSize.height) / 2,
      );
    }
  }

  void _initializeNodePositions() {
    const double centerX = _canvasWidth / 2;
    const double centerY = _canvasHeight / 2;
    final routingState = context.read<RoutingEditorCubit>().state;
    final saved = routingState is RoutingEditorStateLoaded
        ? routingState.nodePositions
        : const <String, NodePosition>{};

    final savedIn = saved['physical_inputs'];
    _nodePositions['physical_inputs'] = savedIn != null
        ? Offset(savedIn.x, savedIn.y)
        : const Offset(centerX - 800, centerY - 300);

    final savedOut = saved['physical_outputs'];
    _nodePositions['physical_outputs'] = savedOut != null
        ? Offset(savedOut.x, savedOut.y)
        : const Offset(centerX + 600, centerY - 300);

    if (routingState is RoutingEditorStateLoaded) {
      const double algorithmStartX = centerX - 250;
      const double algorithmSpacing = 300.0;
      const double algorithmRowSpacing = 200.0;
      for (int i = 0; i < routingState.algorithms.length && i < 8; i++) {
        final algo = routingState.algorithms[i];
        final savedPos = saved[algo.id];
        _nodePositions[algo.id] = savedPos != null
            ? Offset(savedPos.x, savedPos.y)
            : Offset(
                algorithmStartX + (i % 2) * algorithmSpacing,
                centerY - 300 + (i ~/ 2) * algorithmRowSpacing,
              );
      }
    }
  }

  @override
  void dispose() {
    _connectionHighlightTimer?.cancel();
    _errorDismissTimer?.cancel();
    _dragUpdateDebounceTimer?.cancel();
    _scrollSaveTimer?.cancel();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _zoomHotkeySubscription?.cancel();
    _canvasFocusNode.dispose();
    _deleteAnimationController.removeStatusListener(_onDeleteAnimationStatus);
    _deleteAnimationController.removeListener(_onDeleteAnimationTick);
    _deleteAnimationController.dispose();
    _fadeOutAnimationController.removeStatusListener(_onFadeOutAnimationStatus);
    _fadeOutAnimationController.removeListener(_onDeleteAnimationTick);
    _fadeOutAnimationController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    final h = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset
        : 0.0;
    final v = _verticalScrollController.hasClients
        ? _verticalScrollController.offset
        : 0.0;
    _lastScrollOffset = Offset(h, v);
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      context.read<RoutingEditorCubit>().updateViewport(_lastScrollOffset);
    });
  }

  /// Trigger rebuild on each animation frame
  void _onDeleteAnimationTick() {
    if (mounted) {
      setState(() {
        // Just trigger rebuild - the animation value will be read by the painters
      });
    }
  }

  /// Handle delete animation completion (phase 1: red → orange → white)
  void _onDeleteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _deletingPort != null) {
      // Phase 1 completed - start the fade-out phase (no longer cancellable)
      setState(() {
        _isFadingOut = true;
      });
      _fadeOutAnimationController.forward();
    } else if (status == AnimationStatus.dismissed) {
      // Animation was cancelled/reversed - just reset state (only if not fading out)
      if (!_isFadingOut) {
        setState(() {
          _deletingPortId = null;
          _deletingPort = null;
        });
      }
    }
  }

  /// Handle fade-out animation completion (phase 2: white → transparent)
  void _onFadeOutAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _deletingPort != null) {
      // Fade-out completed - delete the connections
      final portName = _deletingPort!.name;
      final cubit = context.read<RoutingEditorCubit>();
      cubit.deleteConnectionsForPort(_deletingPort!.id);

      SemanticsService.sendAnnouncement(
        View.of(context),
        'All connections on $portName deleted',
        TextDirection.ltr,
      );

      // Reset all delete state
      setState(() {
        _deletingPortId = null;
        _deletingPort = null;
        _isFadingOut = false;
      });
      _deleteAnimationController.reset();
      _fadeOutAnimationController.reset();
    }
  }

  /// Handle long press start on a port (begin delete animation)
  void _handlePortLongPressStart(Port port) {
    // Only animate if the port has connections
    final state = context.read<RoutingEditorCubit>().state;
    if (state is! RoutingEditorStateLoaded) return;

    final connectionsToDelete = state.connections
        .where(
          (conn) =>
              conn.sourcePortId == port.id || conn.destinationPortId == port.id,
        )
        .toList();

    if (connectionsToDelete.isEmpty) return;

    final reason = context
        .read<RoutingEditorCubit>()
        .deletionBlockReasonForPortConnections(port.id);
    if (reason != null) {
      _showError('Some connections cannot be removed ($reason)');
      return;
    }

    setState(() {
      _deletingPortId = port.id;
      _deletingPort = port;
    });
    _deleteAnimationController.forward();
  }

  /// Handle long press cancel on a port (reverse delete animation)
  void _handlePortLongPressCancel() {
    // Don't allow cancellation during fade-out phase
    if (_deletingPortId != null && !_isFadingOut) {
      // Reverse the animation
      _deleteAnimationController.reverse();
    }
  }

  /// Handle long press start by port ID
  void _handlePortLongPressStartById(String portId) {
    final port = _portById[portId];
    if (port != null) {
      _handlePortLongPressStart(port);
    }
  }

  void _handleZoomHotkeyAction(ZoomHotkeyAction action) {
    if (!mounted) {
      return;
    }
    _clearSelectedConnection();
    final routingCubit = context.read<RoutingEditorCubit>();
    switch (action) {
      case ZoomHotkeyAction.zoomIn:
        routingCubit.zoomIn();
        break;
      case ZoomHotkeyAction.zoomOut:
        routingCubit.zoomOut();
        break;
      case ZoomHotkeyAction.resetZoom:
        routingCubit.resetZoom();
        break;
    }
  }

  /// Update a port's anchor position from widget callback
  void _updatePortAnchor(String portId, Offset globalCenter, bool isInput) {
    if (!mounted) return;

    // The port widget provides its global position
    // We need to convert this to the canvas's local coordinate system
    // The canvas is the Container with _canvasKey, which is inside Transform.scale

    final canvasContext = _canvasKey.currentContext;
    if (canvasContext == null) return;

    final canvasBox = canvasContext.findRenderObject() as RenderBox?;
    if (canvasBox == null || !canvasBox.attached) return;

    // Convert from global to local coordinates within the canvas
    // This gives us the position in the canvas's coordinate space
    final canvasPosition = canvasBox.globalToLocal(globalCenter);

    final existing = _portPositions[portId];
    if (existing == canvasPosition) return;

    setState(() {
      _portPositions[portId] = canvasPosition;
    });
  }

  // Fit viewport to current content center (no zoom)
  void _fitToView() {
    if (_nodePositions.isEmpty) {
      _centerCanvas();
      return;
    }

    // Compute content bounds from node positions including their dimensions
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final e in _nodePositions.entries) {
      final id = e.key;
      final p = e.value;

      // Estimate node dimensions based on type
      final bool isPhysical =
          id == 'physical_inputs' || id == 'physical_outputs';
      final double nodeWidth = isPhysical
          ? 180
          : 340; // Physical nodes are narrower
      final double nodeHeight = isPhysical
          ? 320
          : 200; // Physical nodes are taller

      // Update bounding box considering node dimensions
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx + nodeWidth > maxX) maxX = p.dx + nodeWidth;
      if (p.dy + nodeHeight > maxY) maxY = p.dy + nodeHeight;
    }

    // Calculate the true center of the content bounding box
    final contentCenterX = ((minX + maxX) / 2).clamp(0.0, _canvasWidth);
    final contentCenterY = ((minY + maxY) / 2).clamp(0.0, _canvasHeight);

    // Transform.scale uses Alignment.center, so a canvas point maps to
    // visual position: (point - canvasCenter) * zoom + canvasCenter
    final routingState = context.read<RoutingEditorCubit>().state;
    final zoomLevel = routingState is RoutingEditorStateLoaded
        ? routingState.zoomLevel
        : 1.0;
    final halfW = _canvasWidth / 2;
    final halfH = _canvasHeight / 2;
    final visualCenterX = (contentCenterX - halfW) * zoomLevel + halfW;
    final visualCenterY = (contentCenterY - halfH) * zoomLevel + halfH;

    final targetHX = (visualCenterX - widget.canvasSize.width / 2).clamp(
      0.0,
      _canvasWidth - widget.canvasSize.width,
    );
    final targetVY = (visualCenterY - widget.canvasSize.height / 2).clamp(
      0.0,
      _canvasHeight - widget.canvasSize.height,
    );

    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.animateTo(
        targetHX,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.animateTo(
        targetVY,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  /// Scroll the canvas to center on a specific position
  void _scrollToPosition(Offset position, double zoomLevel) {
    // Transform.scale uses Alignment.center, so a canvas point maps to
    // visual position: (point - canvasCenter) * zoom + canvasCenter
    final halfW = _canvasWidth / 2;
    final halfH = _canvasHeight / 2;
    final visualX = (position.dx - halfW) * zoomLevel + halfW;
    final visualY = (position.dy - halfH) * zoomLevel + halfH;
    final viewportW = widget.canvasSize.width;
    final viewportH = widget.canvasSize.height;

    // Layout is unaffected by Transform, so max scroll = canvas - viewport
    final targetHX = (visualX - viewportW / 2).clamp(
      0.0,
      _canvasWidth - viewportW,
    );
    final targetVY = (visualY - viewportH / 2).clamp(
      0.0,
      _canvasHeight - viewportH,
    );

    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.animateTo(
        targetHX,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.animateTo(
        targetVY,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _copyCanvasImageToClipboard() async {
    try {
      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        _showFeedback('Canvas not ready');
        return;
      }
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showFeedback('Capture unavailable');
        return;
      }
      // Capture at device pixel ratio for consistent high quality output
      // regardless of zoom level
      final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showFeedback('Encode failed');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      bool ok = true;
      try {
        await Pasteboard.writeImage(bytes);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        _showFeedback('Canvas image copied to clipboard');
        return;
      } else {
        // Fallback to data URL if native image copy is unsupported
        final b64 = convert.base64Encode(bytes);
        await Clipboard.setData(
          ClipboardData(text: 'data:image/png;base64,$b64'),
        );
        _showFeedback('Canvas image copied (data URL)');
      }
    } catch (e) {
      _showError('Copy failed: $e');
    }
  }

  // Copy exactly the current viewport (same size/aspect), excluding UI outside
  // the canvas repaint boundary (e.g., minimap/toolbar).
  Future<void> _copyCanvasImageViewport() async {
    try {
      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        _showFeedback('Canvas not ready');
        return;
      }
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showFeedback('Capture unavailable');
        return;
      }

      final dpr = MediaQuery.of(context).devicePixelRatio;
      final ui.Image full = await boundary.toImage(pixelRatio: dpr);

      final double vx = _horizontalScrollController.hasClients
          ? _horizontalScrollController.offset * dpr
          : 0.0;
      final double vy = _verticalScrollController.hasClients
          ? _verticalScrollController.offset * dpr
          : 0.0;
      final int outW = (widget.canvasSize.width * dpr).round();
      final int outH = (widget.canvasSize.height * dpr).round();
      final Rect src = Rect.fromLTWH(vx, vy, outW.toDouble(), outH.toDouble());

      final recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Rect dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      final Paint paint = Paint()..isAntiAlias = true;
      canvas.drawImageRect(full, src, dst, paint);
      final ui.Image out = await recorder.endRecording().toImage(outW, outH);
      final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showFeedback('Encode failed');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      bool ok = true;
      try {
        await Pasteboard.writeImage(bytes);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        _showFeedback('Viewport copied to clipboard');
      } else {
        final b64 = convert.base64Encode(bytes);
        await Clipboard.setData(
          ClipboardData(text: 'data:image/png;base64,$b64'),
        );
        _showFeedback('Viewport copied (data URL)');
      }
    } catch (e) {
      _showError('Copy failed: $e');
    }
  }

  // Copy tight nodes area with 24px margin all around, preserving canvas theme.
  Future<void> _copyNodesAreaToClipboard() async {
    try {
      if (_nodePositions.isEmpty) {
        _showFeedback('Nothing to copy');
        return;
      }
      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        _showFeedback('Canvas not ready');
        return;
      }
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showFeedback('Capture unavailable');
        return;
      }

      // Full canvas at DPR for crisp crop
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final ui.Image full = await boundary.toImage(pixelRatio: dpr);

      // Compute content bounds from node positions (approximate node size)
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final e in _nodePositions.entries) {
        final id = e.key;
        final p = e.value;
        final bool isPhysical =
            id == 'physical_inputs' || id == 'physical_outputs';
        final double w = isPhysical ? 180 : 340; // slightly wider algo node
        final double h = isPhysical ? 320 : 200; // include title/ports
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx + w > maxX) maxX = p.dx + w;
        if (p.dy + h > maxY) maxY = p.dy + h;
      }
      // 24px margin in canvas logical pixels
      const double margin = 24.0;
      final double sx = ((minX - margin).clamp(0.0, _canvasWidth)) * dpr;
      final double sy = ((minY - margin).clamp(0.0, _canvasHeight)) * dpr;
      final double sw =
          ((maxX - minX + 2 * margin).clamp(1.0, _canvasWidth)) * dpr;
      final double sh =
          ((maxY - minY + 2 * margin).clamp(1.0, _canvasHeight)) * dpr;

      final int outW = sw.round();
      final int outH = sh.round();

      final recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Rect src = Rect.fromLTWH(sx, sy, sw, sh);
      final Rect dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      final Paint paint = Paint()..isAntiAlias = true;
      canvas.drawImageRect(full, src, dst, paint);
      final ui.Image out = await recorder.endRecording().toImage(outW, outH);
      final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showFeedback('Encode failed');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      bool ok = true;
      try {
        await Pasteboard.writeImage(bytes);
      } catch (_) {
        ok = false;
      }
      if (ok) {
        _showFeedback('Nodes image copied to clipboard');
      } else {
        final b64 = convert.base64Encode(bytes);
        await Clipboard.setData(
          ClipboardData(text: 'data:image/png;base64,$b64'),
        );
        _showFeedback('Nodes image copied (data URL)');
      }
    } catch (e) {
      _showError('Copy failed: $e');
    }
  }

  // Copy a scale-to-fit image of content bounds to clipboard (native image).
  Future<void> _copyCanvasImageToClipboardFit() async {
    try {
      final ctx = _captureKey.currentContext;
      if (ctx == null) {
        _showFeedback('Canvas not ready');
        return;
      }
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showFeedback('Capture unavailable');
        return;
      }

      // Capture full canvas at device pixel ratio for high quality output
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final ui.Image full = await boundary.toImage(pixelRatio: dpr);

      // Compute tight content bounds from node positions
      if (_nodePositions.isEmpty) {
        // Fall back to plain copy
        return _copyCanvasImageToClipboard();
      }
      double minX = double.infinity, maxX = double.negativeInfinity;
      double minY = double.infinity, maxY = double.negativeInfinity;
      // Use rough node sizes (algorithm ~300x180, physical ~180x300)
      for (final entry in _nodePositions.entries) {
        final id = entry.key;
        final p = entry.value;
        final bool isPhysical =
            id == 'physical_inputs' || id == 'physical_outputs';
        final double w = isPhysical ? 180 : 300;
        final double h = isPhysical ? 300 : 180;
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx + w > maxX) maxX = p.dx + w;
        if (p.dy + h > maxY) maxY = p.dy + h;
      }
      const double pad = 60.0;
      final src = Rect.fromLTWH(
        ((minX - pad).clamp(0.0, _canvasWidth)) * dpr,
        ((minY - pad).clamp(0.0, _canvasHeight)) * dpr,
        ((maxX - minX + 2 * pad).clamp(1.0, _canvasWidth)) * dpr,
        ((maxY - minY + 2 * pad).clamp(1.0, _canvasHeight)) * dpr,
      );

      // Target size: viewport at device pixel ratio for high quality
      final int outW = (widget.canvasSize.width * dpr).round();
      final int outH = (widget.canvasSize.height * dpr).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      final paint = Paint()..isAntiAlias = true;
      canvas.drawImageRect(full, src, dst, paint);
      final ui.Image out = await recorder.endRecording().toImage(outW, outH);
      final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showFeedback('Encode failed');
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      try {
        await Pasteboard.writeImage(bytes);
        _showFeedback('Canvas (fit) copied to clipboard');
      } catch (_) {
        final b64 = convert.base64Encode(bytes);
        await Clipboard.setData(
          ClipboardData(text: 'data:image/png;base64,$b64'),
        );
        _showFeedback('Canvas (fit) copied (data URL)');
      }
    } catch (e) {
      _showError('Copy failed: $e');
    }
  }

  // Share nodes area image using platform-native sharing on mobile
  Future<void> _shareNodesAreaImage() async {
    try {
      final bytes = await _captureNodesAreaImageBytes();
      if (bytes == null) return;

      final platformService = widget.platformService;
      if (platformService?.isMobilePlatform() == true) {
        // Use native sharing on mobile
        final xFile = XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'routing_diagram.png',
        );
        await SharePlus.instance.share(
          ShareParams(files: [xFile], text: 'Routing diagram from nt_helper'),
        );
        _showFeedback('Routing diagram shared');
      } else {
        // Fall back to clipboard on desktop
        await _copyNodesAreaToClipboard();
      }
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  // Share canvas viewport image using platform-native sharing on mobile
  Future<void> _shareCanvasViewportImage() async {
    try {
      final bytes = await _captureCanvasViewportImageBytes();
      if (bytes == null) return;

      final platformService = widget.platformService;
      if (platformService?.isMobilePlatform() == true) {
        // Use native sharing on mobile
        final xFile = XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'routing_canvas.png',
        );
        await SharePlus.instance.share(
          ShareParams(files: [xFile], text: 'Routing canvas from nt_helper'),
        );
        _showFeedback('Routing canvas shared');
      } else {
        // Fall back to clipboard on desktop
        await _copyCanvasImageViewport();
      }
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  // Helper function to capture nodes area image bytes (extracted from _copyNodesAreaToClipboard)
  Future<Uint8List?> _captureNodesAreaImageBytes() async {
    if (_nodePositions.isEmpty) {
      _showFeedback('Nothing to capture');
      return null;
    }
    final ctx = _captureKey.currentContext;
    if (ctx == null) {
      _showFeedback('Canvas not ready');
      return null;
    }
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      _showFeedback('Capture unavailable');
      return null;
    }

    // Full canvas at DPR for crisp crop
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final ui.Image full = await boundary.toImage(pixelRatio: dpr);

    // Compute content bounds from node positions (approximate node size)
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final e in _nodePositions.entries) {
      final id = e.key;
      final p = e.value;
      final bool isPhysical =
          id == 'physical_inputs' || id == 'physical_outputs';
      final double w = isPhysical ? 180 : 340; // slightly wider algo node
      final double h = isPhysical ? 320 : 200; // include title/ports
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx + w > maxX) maxX = p.dx + w;
      if (p.dy + h > maxY) maxY = p.dy + h;
    }
    // 24px margin in canvas logical pixels
    const double margin = 24.0;
    final double sx = ((minX - margin).clamp(0.0, _canvasWidth)) * dpr;
    final double sy = ((minY - margin).clamp(0.0, _canvasHeight)) * dpr;
    final double sw =
        ((maxX - minX + 2 * margin).clamp(1.0, _canvasWidth)) * dpr;
    final double sh =
        ((maxY - minY + 2 * margin).clamp(1.0, _canvasHeight)) * dpr;

    final int outW = sw.round();
    final int outH = sh.round();

    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect src = Rect.fromLTWH(sx, sy, sw, sh);
    final Rect dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
    final Paint paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(full, src, dst, paint);
    final ui.Image out = await recorder.endRecording().toImage(outW, outH);
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      _showFeedback('Encode failed');
      return null;
    }
    return byteData.buffer.asUint8List();
  }

  // Helper function to capture canvas viewport image bytes (extracted from _copyCanvasImageViewport)
  Future<Uint8List?> _captureCanvasViewportImageBytes() async {
    final ctx = _captureKey.currentContext;
    if (ctx == null) {
      _showFeedback('Canvas not ready');
      return null;
    }
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      _showFeedback('Capture unavailable');
      return null;
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final ui.Image full = await boundary.toImage(pixelRatio: dpr);

    final double vx = _horizontalScrollController.hasClients
        ? _horizontalScrollController.offset * dpr
        : 0.0;
    final double vy = _verticalScrollController.hasClients
        ? _verticalScrollController.offset * dpr
        : 0.0;
    final int outW = (widget.canvasSize.width * dpr).round();
    final int outH = (widget.canvasSize.height * dpr).round();
    final Rect src = Rect.fromLTWH(vx, vy, outW.toDouble(), outH.toDouble());

    final recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Rect dst = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
    final Paint paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(full, src, dst, paint);
    final ui.Image out = await recorder.endRecording().toImage(outW, outH);
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      _showFeedback('Encode failed');
      return null;
    }
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().showBackwardConnectionsNotifier,
      builder: (context, showBackwardConnections, _) {
        return BlocConsumer<RoutingEditorCubit, RoutingEditorState>(
          listenWhen: (previous, current) {
            // Listen for cascade scroll target changes
            if (previous is RoutingEditorStateLoaded &&
                current is RoutingEditorStateLoaded) {
              return previous.cascadeScrollTarget !=
                      current.cascadeScrollTarget &&
                  current.cascadeScrollTarget != null;
            }
            return false;
          },
          listener: (context, state) {
            // Scroll to cascade target when it changes
            if (state is RoutingEditorStateLoaded &&
                state.cascadeScrollTarget != null) {
              _scrollToPosition(state.cascadeScrollTarget!, state.zoomLevel);
              // Clear the scroll target after scrolling
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  context.read<RoutingEditorCubit>().clearCascadeScrollTarget();
                }
              });
            }
          },
          buildWhen: (previous, current) {
            final shouldRebuild =
                previous.runtimeType != current.runtimeType ||
                (previous is RoutingEditorStateLoaded &&
                    current is RoutingEditorStateLoaded &&
                    _hasLoadedStateChanged(previous, current));

            // Only clear port positions when the routing structure actually changes
            // Since we now calculate positions from node layout, we don't need to clear on zoom
            if (shouldRebuild && current is RoutingEditorStateLoaded) {
              if (previous is! RoutingEditorStateLoaded ||
                  _hasRoutingStructureChanged(previous, current)) {
                _pruneAndInitNodePositions(current);
              }
            }

            return shouldRebuild;
          },
          builder: (context, state) {
            if (!_viewModeLoaded) {
              return SizedBox(
                width: widget.canvasSize.width,
                height: widget.canvasSize.height,
              );
            }

            // Auto-detect accessible navigation mode
            final effectiveMode = MediaQuery.of(context).accessibleNavigation
                ? RoutingEditorViewMode.list
                : _viewMode;

            if (effectiveMode == RoutingEditorViewMode.list) {
              return Stack(
                children: [
                  Container(
                    width: widget.canvasSize.width,
                    height: widget.canvasSize.height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const AccessibleRoutingListView(),
                  ),
                  Positioned(top: 8, right: 8, child: _buildViewModeButton()),
                ],
              );
            }

            if (effectiveMode == RoutingEditorViewMode.table) {
              return Stack(
                children: [
                  Container(
                    width: widget.canvasSize.width,
                    height: widget.canvasSize.height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const RoutingTableView(),
                  ),
                  Positioned(top: 8, right: 8, child: _buildViewModeButton()),
                ],
              );
            }

            if (effectiveMode == RoutingEditorViewMode.busLanes) {
              return Stack(
                children: [
                  Container(
                    width: widget.canvasSize.width,
                    height: widget.canvasSize.height,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const BusLanesView(),
                  ),
                  Positioned(top: 8, right: 8, child: _buildViewModeButton()),
                ],
              );
            }

            return Stack(
              children: [
                Container(
                  width: widget.canvasSize.width,
                  height: widget.canvasSize.height,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _platformService.isDesktopPlatform()
                        ? Shortcuts(
                            shortcuts: _keyBindingService.desktopZoomShortcuts,
                            child: Actions(
                              actions: _keyBindingService.buildZoomActions(
                                onZoomIn: () =>
                                    context.read<RoutingEditorCubit>().zoomIn(),
                                onZoomOut: () => context
                                    .read<RoutingEditorCubit>()
                                    .zoomOut(),
                                onResetZoom: () => context
                                    .read<RoutingEditorCubit>()
                                    .resetZoom(),
                              ),
                              child: Focus(
                                focusNode: _canvasFocusNode,
                                autofocus: true,
                                onKeyEvent: _handleKeyEvent,
                                child: _buildCanvasContent(
                                  context,
                                  state,
                                  showBackwardConnections,
                                ),
                              ),
                            ),
                          )
                        : _buildCanvasContent(
                            context,
                            state,
                            showBackwardConnections,
                          ),
                  ),
                ),
                Positioned(top: 8, right: 8, child: _buildViewModeButton()),
                // AUX bus usage + MiniMap in bottom-right corner
                if (state is RoutingEditorStateLoaded)
                  Positioned(
                    bottom: 16.0,
                    right: 16.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AuxBusUsageWidget(
                          auxBusUsage: state.auxBusUsage,
                          deviceIoProfile: state.deviceIoProfile,
                          focusedBusNumber: _deriveFocusedBusNumber(state),
                          onBusTapped: (bus) => context
                              .read<RoutingEditorCubit>()
                              .focusAuxBus(bus),
                          onBusMoved: (source, dest) => context
                              .read<RoutingEditorCubit>()
                              .moveAuxBus(source, dest),
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            double miniMapWidth;
                            double miniMapHeight;

                            if (_platformService.isMobilePlatform()) {
                              miniMapWidth = 120.0;
                              miniMapHeight = 90.0;
                            } else {
                              final screenWidth = MediaQuery.of(
                                context,
                              ).size.width;
                              if (screenWidth < 900) {
                                miniMapWidth = 160.0;
                                miniMapHeight = 120.0;
                              } else {
                                miniMapWidth = 200.0;
                                miniMapHeight = 150.0;
                              }
                            }

                            return ExcludeSemantics(
                              child: MiniMapWidget(
                                horizontalScrollController:
                                    _horizontalScrollController,
                                verticalScrollController:
                                    _verticalScrollController,
                                canvasWidth: _canvasWidth,
                                canvasHeight: _canvasHeight,
                                width: miniMapWidth,
                                height: miniMapHeight,
                                nodePositions: _nodePositions,
                                connections: state.connections,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                // Error display widget in top-right corner (above mini-map in z-order)
                if (_errorMessage != null) _buildErrorDisplay(),
              ],
            );
          },
        );
      },
    );
  }

  /// Derive which AUX bus is currently focused (if any) from the state.
  int? _deriveFocusedBusNumber(RoutingEditorStateLoaded state) {
    if (state.focusedAlgorithmIds.isEmpty) return null;
    for (final entry in state.auxBusUsage.entries) {
      final info = entry.value;
      if (info.algorithmIds.isNotEmpty &&
          info.algorithmIds.length == state.focusedAlgorithmIds.length &&
          state.focusedAlgorithmIds.containsAll(info.algorithmIds)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Remove stale node positions and ensure required defaults exist for the
  /// current routing structure (e.g., after loading a new preset).
  void _pruneAndInitNodePositions(RoutingEditorStateLoaded current) {
    final allowedKeys = <String>{
      'physical_inputs',
      'physical_outputs',
      ...current.algorithms.map((a) => a.id),
    };

    _nodePositions.removeWhere((key, value) => !allowedKeys.contains(key));

    const double centerX = _canvasWidth / 2;
    const double centerY = _canvasHeight / 2;
    final saved = current.nodePositions;

    final savedIn = saved['physical_inputs'];
    _nodePositions.putIfAbsent(
      'physical_inputs',
      () => savedIn != null
          ? Offset(savedIn.x, savedIn.y)
          : const Offset(centerX - 800, centerY - 300),
    );
    final savedOut = saved['physical_outputs'];
    _nodePositions.putIfAbsent(
      'physical_outputs',
      () => savedOut != null
          ? Offset(savedOut.x, savedOut.y)
          : const Offset(centerX + 600, centerY - 300),
    );

    const double algorithmStartX = centerX - 250;
    const double algorithmSpacing = 300.0;
    const double algorithmRowSpacing = 200.0;
    for (int i = 0; i < current.algorithms.length && i < 8; i++) {
      final algo = current.algorithms[i];
      final savedPos = saved[algo.id];
      _nodePositions.putIfAbsent(algo.id, () {
        if (savedPos != null) return Offset(savedPos.x, savedPos.y);
        return Offset(
          algorithmStartX + (i % 2) * algorithmSpacing,
          centerY - 300 + (i ~/ 2) * algorithmRowSpacing,
        );
      });
    }
  }

  /// Build dismissable error display widget
  Widget _buildErrorDisplay() {
    return Positioned(
      top: 8,
      right: 8,
      child: Semantics(
        liveRegion: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 16,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _dismissError,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle keyboard events not covered by shortcuts (Escape for drag cancel).
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_platformService.isDesktopPlatform()) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      // Cancel pending keyboard connection first
      if (_pendingConnectionSourcePortId != null) {
        setState(() {
          _pendingConnectionSourcePortId = null;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Connection cancelled',
          TextDirection.ltr,
        );
        return KeyEventResult.handled;
      }
      if (_isDraggingConnection) {
        _cancelDragOperation();
        return KeyEventResult.handled;
      }
      if (_connectionHighlight?.source == _ConnectionHighlightSource.selected) {
        _clearSelectedConnection();
        return KeyEventResult.handled;
      }
      // Clear focus mode selection with Escape
      if (_focusedAlgorithmIds.isNotEmpty) {
        context.read<RoutingEditorCubit>().clearFocus();
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace)) {
      final highlight = _connectionHighlight;
      if (highlight != null &&
          highlight.source == _ConnectionHighlightSource.selected) {
        _deleteConnection(highlight.id, _latestConnections);
        _clearSelectedConnection();
        return KeyEventResult.handled;
      }
    }

    // Arrow keys for canvas pan when no child node is focused
    if (event is KeyDownEvent && _canvasFocusNode.hasPrimaryFocus) {
      const scrollAmount = 50.0;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(
            (_horizontalScrollController.offset - scrollAmount).clamp(
              0.0,
              _horizontalScrollController.position.maxScrollExtent,
            ),
          );
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_horizontalScrollController.hasClients) {
          _horizontalScrollController.jumpTo(
            (_horizontalScrollController.offset + scrollAmount).clamp(
              0.0,
              _horizontalScrollController.position.maxScrollExtent,
            ),
          );
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_verticalScrollController.hasClients) {
          _verticalScrollController.jumpTo(
            (_verticalScrollController.offset - scrollAmount).clamp(
              0.0,
              _verticalScrollController.position.maxScrollExtent,
            ),
          );
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_verticalScrollController.hasClients) {
          _verticalScrollController.jumpTo(
            (_verticalScrollController.offset + scrollAmount).clamp(
              0.0,
              _verticalScrollController.position.maxScrollExtent,
            ),
          );
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  /// Handle keyboard Space/Enter on a port for accessible connection creation.
  void _handlePortKeyboardActivation(String portId) {
    if (_pendingConnectionSourcePortId == null) {
      // First press: select source
      setState(() {
        _pendingConnectionSourcePortId = portId;
      });
      final portName = _portById[portId]?.name ?? portId;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Selected $portName as connection source. Navigate to a destination port and press Space to connect, or press Escape to cancel.',
        TextDirection.ltr,
      );
    } else if (_pendingConnectionSourcePortId == portId) {
      // Same port: cancel
      setState(() {
        _pendingConnectionSourcePortId = null;
      });
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Connection cancelled',
        TextDirection.ltr,
      );
    } else {
      // Second press: create connection
      final sourceId = _pendingConnectionSourcePortId!;
      setState(() {
        _pendingConnectionSourcePortId = null;
      });
      final cubit = context.read<RoutingEditorCubit>();
      _createConnectionWithErrorHandling(cubit, sourceId, portId);
    }
  }

  /// Cancel current drag operation
  void _cancelDragOperation() {
    setState(() {
      _isDraggingConnection = false;
      _dragSourcePort = null;
      _dragCurrentPosition = null;
      _highlightedPortId = null;
    });
  }

  /// Display an error message with auto-dismiss after 5 seconds
  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });

    // Cancel previous timer if exists
    _errorDismissTimer?.cancel();

    // Auto-dismiss after 5 seconds
    _errorDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _errorMessage == message) {
        _dismissError();
      }
    });
  }

  /// Dismiss current error message
  void _dismissError() {
    _errorDismissTimer?.cancel();
    setState(() {
      _errorMessage = null;
    });
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _clearSelectedConnection() => _clearConnectionHighlightState(
    source: _ConnectionHighlightSource.selected,
  );

  void _setConnectionHighlight(
    String connectionId,
    _ConnectionHighlightSource source,
  ) {
    setState(() {
      _connectionHighlight = _ConnectionHighlight(
        id: connectionId,
        source: source,
      );
    });
  }

  void _clearConnectionHighlightState({_ConnectionHighlightSource? source}) {
    if (_connectionHighlight == null) return;
    if (source != null && _connectionHighlight!.source != source) return;
    setState(() {
      _connectionHighlight = null;
    });
  }

  /// Create connection with comprehensive error handling
  Future<void> _createConnectionWithErrorHandling(
    RoutingEditorCubit cubit,
    String sourcePortId,
    String targetPortId,
  ) async {
    final view = View.of(context);
    try {
      // Check current state
      final currentState = cubit.state;
      if (currentState is! RoutingEditorStateLoaded) {
        _showError('Routing editor not ready');
        return;
      }

      // Let the cubit choose a suitable internal bus (aux preferred),
      // so we do not hard-block when aux buses are exhausted.
      // Hardware connections remain always available.

      // Attempt to create the connection
      await cubit.createConnection(
        sourcePortId: sourcePortId,
        targetPortId: targetPortId,
      );

      // Announce success for screen readers
      final sourceName = _portById[sourcePortId]?.name ?? sourcePortId;
      final destName = _portById[targetPortId]?.name ?? targetPortId;
      SemanticsService.sendAnnouncement(
        view,
        'Connection created from $sourceName to $destName',
        TextDirection.ltr,
      );
    } on ArgumentError catch (e) {
      _showError('Invalid connection: ${e.message}');
      SemanticsService.sendAnnouncement(
        view,
        'Connection failed: ${e.message}',
        TextDirection.ltr,
      );
    } on StateError catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Connection failed: ${e.toString()}');
    }
  }

  // No longer used: previously pre-checked for aux-only availability.
  // The cubit now picks an appropriate internal bus (aux preferred),
  // so we skip rigid preflight here to avoid blocking valid cases.

  Widget _buildViewModeButton() {
    return PopupMenuButton<RoutingEditorViewMode>(
      initialValue: _viewMode,
      onSelected: _setViewMode,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: RoutingEditorViewMode.canvas,
          child: ListTile(
            leading: Icon(Icons.grid_view),
            title: Text('Canvas'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: RoutingEditorViewMode.table,
          child: ListTile(
            leading: Icon(Icons.table_chart),
            title: Text('Signal Flow'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: RoutingEditorViewMode.busLanes,
          child: ListTile(
            leading: Icon(Icons.view_column),
            title: Text('Bus Lanes'),
            dense: true,
          ),
        ),
        PopupMenuItem(
          value: RoutingEditorViewMode.list,
          child: ListTile(
            leading: Icon(Icons.list_alt),
            title: Text('Accessible List'),
            dense: true,
          ),
        ),
      ],
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (_viewMode) {
                RoutingEditorViewMode.canvas => Icons.grid_view,
                RoutingEditorViewMode.table => Icons.table_chart,
                RoutingEditorViewMode.busLanes => Icons.view_column,
                RoutingEditorViewMode.list => Icons.list_alt,
              },
              size: 20,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasContent(
    BuildContext context,
    RoutingEditorState state,
    bool showBackwardConnections,
  ) {
    return state.when(
      initial: () =>
          _buildEmptyState(context, 'Initializing routing editor...'),
      disconnected: () => _buildEmptyState(context, 'Hardware disconnected'),
      loaded:
          (
            deviceIoProfile,
            physicalInputs,
            physicalOutputs,
            es5Inputs,
            algorithms,
            connections,
            buses,
            portOutputModes,
            nodePositions,
            zoomLevel,
            panOffset,
            isHardwareSynced,
            isPersistenceEnabled,
            lastSyncTime,
            lastPersistTime,
            lastError,
            subState,
            focusedAlgorithmIds,
            cascadeScrollTarget,
            auxBusUsage,
            hasExtendedAuxBuses,
          ) => _buildLoadedCanvas(
            context,
            physicalInputs,
            physicalOutputs,
            es5Inputs,
            algorithms,
            connections,
            nodePositions,
            zoomLevel,
            panOffset,
            showBackwardConnections,
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String message) {
    /* identical to RoutingCanvas */
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.device_hub,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedCanvas(
    BuildContext context,
    List<Port> physicalInputs,
    List<Port> physicalOutputs,
    List<Port> es5Inputs,
    List<RoutingAlgorithm> algorithms,
    List<Connection> connections,
    Map<String, NodePosition> stateNodePositions,
    double zoomLevel,
    Offset panOffset,
    bool showBackwardConnections,
  ) {
    final visibleConnections = _visibleCanvasConnections(
      connections,
      showBackwardConnections,
    );
    _latestConnections = visibleConnections;
    final routingCubit = context.read<RoutingEditorCubit>();

    // Get focused algorithm IDs for focus mode dimming
    final routingState = routingCubit.state;
    _focusedAlgorithmIds = routingState is RoutingEditorStateLoaded
        ? routingState.focusedAlgorithmIds
        : const {};

    // Rebuild port lookup map for this frame.
    _portById
      ..clear()
      ..addEntries(physicalInputs.map((p) => MapEntry(p.id, p)))
      ..addEntries(physicalOutputs.map((p) => MapEntry(p.id, p)))
      ..addEntries(es5Inputs.map((p) => MapEntry(p.id, p)));
    for (final algo in algorithms) {
      for (final p in algo.inputPorts) {
        _portById[p.id] = p;
      }
      for (final p in algo.outputPorts) {
        _portById[p.id] = p;
      }
    }

    final nodeBoundsMap = _calculateNodeBoundsMap();
    final portToNodeIdMap = <String, String>{};
    final zIndexByNodeId = <String, int>{};

    // Build port ID to Node ID map
    for (final port in physicalInputs) {
      portToNodeIdMap[port.id] = 'physical_inputs';
    }
    for (final port in physicalOutputs) {
      portToNodeIdMap[port.id] = 'physical_outputs';
    }
    for (final port in es5Inputs) {
      portToNodeIdMap[port.id] = 'es5_node';
    }
    for (final algo in algorithms) {
      for (final port in algo.inputPorts) {
        portToNodeIdMap[port.id] = algo.id;
      }
      for (final port in algo.outputPorts) {
        portToNodeIdMap[port.id] = algo.id;
      }
    }

    // Compute node z-order indices matching the Stack child order: later children
    // are on top. Foreground connection overlays should only appear on top of
    // their endpoint node, while still allowing nodes above to occlude them.
    var zIndex = 0;
    if (widget.showPhysicalPorts) {
      if (physicalOutputs.isNotEmpty) {
        zIndexByNodeId['physical_outputs'] = zIndex++;
      }
      if (physicalInputs.isNotEmpty) {
        zIndexByNodeId['physical_inputs'] = zIndex++;
      }
      if (es5Inputs.isNotEmpty) {
        zIndexByNodeId['es5_node'] = zIndex++;
      }
    }
    for (var i = 0; i < algorithms.length; i++) {
      zIndexByNodeId[algorithms[i].id] = zIndex + i;
    }

    _clearHiddenConnectionState(visibleConnections);

    return Semantics(
      label:
          'Routing canvas with ${algorithms.length} algorithm nodes and ${visibleConnections.length} connections',
      hint:
          'Interactive routing canvas. Pan and zoom to navigate. Drag between ports to create connections.',
      container: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        physics:
            const NeverScrollableScrollPhysics(), // Disable scroll gestures
        child: SingleChildScrollView(
          controller: _verticalScrollController,
          scrollDirection: Axis.vertical,
          physics:
              const NeverScrollableScrollPhysics(), // Disable scroll gestures
          child: Listener(
            // Handle mouse wheel and trackpad scrolling/zooming
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                _clearSelectedConnection();

                // Check for zoom modifier keys (Ctrl/Cmd + wheel)
                if (_keyBindingService.isZoomModifierPressed()) {
                  // Zoom with mouse wheel
                  final zoomDelta = -pointerSignal.scrollDelta.dy * 0.001;
                  final newZoom = (zoomLevel + zoomDelta).clamp(0.1, 2.0);
                  routingCubit.setZoomLevel(newZoom);
                  return;
                }

                // Regular panning
                // Handle horizontal scrolling (trackpad side-scroll or shift+wheel)
                if (_horizontalScrollController.hasClients) {
                  final newHorizontal =
                      _horizontalScrollController.offset +
                      pointerSignal.scrollDelta.dx;
                  _horizontalScrollController.jumpTo(
                    newHorizontal.clamp(
                      _horizontalScrollController.position.minScrollExtent,
                      _horizontalScrollController.position.maxScrollExtent,
                    ),
                  );
                }

                // Handle vertical scrolling (mouse wheel or trackpad)
                if (_verticalScrollController.hasClients) {
                  final newVertical =
                      _verticalScrollController.offset +
                      pointerSignal.scrollDelta.dy;
                  _verticalScrollController.jumpTo(
                    newVertical.clamp(
                      _verticalScrollController.position.minScrollExtent,
                      _verticalScrollController.position.maxScrollExtent,
                    ),
                  );
                }
              }
            },
            child: RepaintBoundary(
              key: _captureKey,
              child: Transform.scale(
                scale: zoomLevel,
                child: Container(
                  key: _canvasKey,
                  width: _canvasWidth,
                  height: _canvasHeight,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Grid background with gesture detector for empty space (bottom layer)
                        SizedBox(
                          width: _canvasWidth,
                          height: _canvasHeight,
                          child: GestureDetector(
                            // Handle taps and panning on empty space
                            onTapDown: (details) {
                              _handleCanvasTap(
                                details.localPosition,
                                visibleConnections,
                              );
                            },
                            onDoubleTap: () {
                              // Double tap to reset zoom
                              final routingCubit = context
                                  .read<RoutingEditorCubit>();
                              routingCubit.resetZoom();
                            },
                            onPanStart: _handleCanvasPanStart,
                            onPanUpdate: _handleCanvasPanUpdate,
                            onPanEnd: _handleCanvasPanEnd,
                            behavior: HitTestBehavior
                                .translucent, // Allow events to pass through to child widgets
                            child: ExcludeSemantics(
                              child: CustomPaint(
                                painter: _CanvasGridPainter(
                                  minorGridColor: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.1),
                                  majorGridColor: Theme.of(
                                    context,
                                  ).colorScheme.outline.withValues(alpha: 0.2),
                                  gridSize: 50.0,
                                  majorEvery: 5,
                                ),
                                size: Size(_canvasWidth, _canvasHeight),
                              ),
                            ),
                          ),
                        ),

                        // 1. Background Connections (Full paths, behind everything)
                        _buildConnections(
                          visibleConnections,
                          portToNodeIdMap,
                          nodeBoundsMap,
                          zIndexByNodeId,
                        ),

                        // 2. Nodes (Stacked from bottom to top)

                        // Physical Output Nodes (Lowest Z-order)
                        if (widget.showPhysicalPorts)
                          ..._buildPhysicalOutputNodes(
                            physicalOutputs,
                            connections,
                            stateNodePositions,
                          ),

                        // Physical Input Nodes
                        if (widget.showPhysicalPorts)
                          ..._buildPhysicalInputNodes(
                            physicalInputs,
                            connections,
                            stateNodePositions,
                          ),

                        // ES-5 Nodes
                        if (widget.showPhysicalPorts)
                          ..._buildEs5Nodes(
                            es5Inputs,
                            connections,
                            stateNodePositions,
                          ),

                        // Algorithm Nodes (Highest Z-order among nodes)
                        ..._buildAlgorithmNodes(
                          algorithms,
                          connections,
                          stateNodePositions,
                        ),

                        // 3. Foreground Connections (Tips only, on top of everything)
                        _buildConnections(
                          visibleConnections,
                          portToNodeIdMap,
                          nodeBoundsMap,
                          zIndexByNodeId,
                          drawEndpointsOnly: true,
                        ),

                        // Temporary connection (dragging)
                        if (_isDraggingConnection &&
                            _dragCurrentPosition != null)
                          _buildTemporaryConnection(),

                        // Connection label overlays (for tap detection)
                        ..._buildConnectionLabelOverlays(visibleConnections),

                        // Labels for instant-deleted connections fade out here.
                        ..._buildFadingDeletedConnectionLabelOverlays(),

                        // Semantic-only connection list for screen readers
                        _buildConnectionSemanticsOverlay(visibleConnections),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Connection> _visibleCanvasConnections(
    List<Connection> connections,
    bool showBackwardConnections,
  ) {
    if (showBackwardConnections) return connections;
    return connections
        .where((connection) => !connection.isBackwardEdge)
        .toList(growable: false);
  }

  void _clearHiddenConnectionState(List<Connection> visibleConnections) {
    final highlight = _connectionHighlight;
    if (highlight == null) return;
    final highlightIsVisible = visibleConnections.any(
      (connection) => connection.id == highlight.id,
    );
    if (highlightIsVisible) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _connectionHighlight?.id != highlight.id) return;
      _clearConnectionHighlightState(source: highlight.source);
    });
  }

  /// Build a semantic-only overlay listing all connections for screen readers.
  Widget _buildConnectionSemanticsOverlay(List<Connection> connections) {
    if (connections.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: 1,
        height: 1,
        child: Semantics(
          container: true,
          label: '${connections.length} connections',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: connections.map((conn) {
              final sourceName =
                  _portById[conn.sourcePortId]?.name ?? conn.sourcePortId;
              final destName =
                  _portById[conn.destinationPortId]?.name ??
                  conn.destinationPortId;
              final statusPrefix = conn.isGhostConnection
                  ? 'Ghost connection'
                  : conn.isBackwardEdge
                  ? 'Invalid connection'
                  : 'Connection';
              final busLabel = conn.busLabel ?? '';
              final busText = busLabel.isNotEmpty ? ' via $busLabel' : '';

              return Semantics(
                label: '$statusPrefix: $sourceName to $destName$busText',
                child: const SizedBox.shrink(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Below methods are copied from RoutingCanvas (handlers, builders, validators)
  List<Widget> _buildPhysicalInputNodes(
    List<Port> physicalInputs,
    List<Connection> connections,
    Map<String, NodePosition> stateNodePositions,
  ) {
    if (physicalInputs.isEmpty) return [];
    // Position in the center area of the canvas, to the left of algorithms
    const double centerY = _canvasHeight / 2;

    // Check for position from state first
    final statePosition = stateNodePositions['physical_inputs'];
    final Offset nodePosition;

    if (statePosition != null) {
      nodePosition = Offset(statePosition.x, statePosition.y);
      _nodePositions['physical_inputs'] = nodePosition;
    } else {
      nodePosition =
          _nodePositions['physical_inputs'] ?? const Offset(100, centerY);
    }

    return [
      Positioned(
        key: const ValueKey('physical_input_node'),
        left: nodePosition.dx,
        top: nodePosition.dy,
        child: FocusTraversalOrder(
          order: const NumericFocusOrder(0),
          child: PhysicalInputNode(
            ports: physicalInputs,
            connectedPorts: _getConnectedPortIds(connections).toSet(),
            position: nodePosition,
            onPositionChanged: (newPosition) {
              setState(() {
                _nodePositions['physical_inputs'] = newPosition;
              });
              // Save position to preferences
              context.read<RoutingEditorCubit>().updateNodePosition(
                'physical_inputs',
                newPosition.dx,
                newPosition.dy,
              );
            },
            showLabels: widget.canvasSize.width >= 800,
            onPortTapped: (port) => _handlePortTap(port),
            onPortLongPress: (port) => _handlePortLongPress(port),
            // Use animated long-press for desktop, skip for mobile (uses confirmation dialog)
            onPortLongPressStart: _platformService.isMobilePlatform()
                ? null
                : (port) => _handlePortLongPressStart(port),
            onPortLongPressCancel: _platformService.isMobilePlatform()
                ? null
                : _handlePortLongPressCancel,
            onDragStart: (port) => _handlePortDragStart(port),
            onDragUpdate: (port, position) =>
                _handlePortDragUpdate(port, position),
            onDragEnd: (port, position) => _handlePortDragEnd(port, position),
            onPortPositionResolved: (port, globalCenter) {
              // Update port position cache - physical inputs/outputs have opposite directions from algorithm perspective
              final isInput = port.direction == PortDirection.input;
              _updatePortAnchor(port.id, globalCenter, isInput);
            },
            onRoutingAction: (portId, action) =>
                _handlePortRoutingAction(portId, action, connections),
            highlightedPortId: _isDraggingConnection
                ? _highlightedPortId
                : null,
            onNodeDragStart: () {
              // Node drag start handler (could be used for visual feedback)
            },
            onNodeDragEnd: () {
              // Node drag end handler (could be used for cleanup)
            },
            onSizeResolved: (size) =>
                _handleNodeSizeResolved('physical_inputs', size),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildPhysicalOutputNodes(
    List<Port> physicalOutputs,
    List<Connection> connections,
    Map<String, NodePosition> stateNodePositions,
  ) {
    if (physicalOutputs.isEmpty) return [];
    // Position in the center area of the canvas, to the right of algorithms
    const double centerX = _canvasWidth / 2;
    const double centerY = _canvasHeight / 2;

    // Check for position from state first
    final statePosition = stateNodePositions['physical_outputs'];
    final Offset nodePosition;

    if (statePosition != null) {
      nodePosition = Offset(statePosition.x, statePosition.y);
      _nodePositions['physical_outputs'] = nodePosition;
    } else {
      nodePosition =
          _nodePositions['physical_outputs'] ??
          const Offset(centerX + 600, centerY - 300);
    }

    return [
      Positioned(
        key: const ValueKey('physical_output_node'),
        left: nodePosition.dx,
        top: nodePosition.dy,
        child: FocusTraversalOrder(
          order: const NumericFocusOrder(100),
          child: PhysicalOutputNode(
            ports: physicalOutputs,
            connectedPorts: _getConnectedPortIds(connections).toSet(),
            position: nodePosition,
            onPositionChanged: (newPosition) {
              setState(() {
                _nodePositions['physical_outputs'] = newPosition;
              });
              // Save position to preferences
              context.read<RoutingEditorCubit>().updateNodePosition(
                'physical_outputs',
                newPosition.dx,
                newPosition.dy,
              );
            },
            showLabels: widget.canvasSize.width >= 800,
            onPortTapped: (port) => _handlePortTap(port),
            onPortLongPress: (port) => _handlePortLongPress(port),
            // Use animated long-press for desktop, skip for mobile (uses confirmation dialog)
            onPortLongPressStart: _platformService.isMobilePlatform()
                ? null
                : (port) => _handlePortLongPressStart(port),
            onPortLongPressCancel: _platformService.isMobilePlatform()
                ? null
                : _handlePortLongPressCancel,
            onDragStart: (port) => _handlePortDragStart(port),
            onDragUpdate: (port, position) =>
                _handlePortDragUpdate(port, position),
            onDragEnd: (port, position) => _handlePortDragEnd(port, position),
            onPortPositionResolved: (port, globalCenter) {
              // Update port position cache - physical inputs/outputs have opposite directions from algorithm perspective
              final isInput = port.direction == PortDirection.input;
              _updatePortAnchor(port.id, globalCenter, isInput);
            },
            onRoutingAction: (portId, action) =>
                _handlePortRoutingAction(portId, action, connections),
            highlightedPortId: _isDraggingConnection
                ? _highlightedPortId
                : null,
            onNodeDragStart: () {
              // Node drag start handler (could be used for visual feedback)
            },
            onNodeDragEnd: () {
              // Node drag end handler (could be used for cleanup)
            },
            onSizeResolved: (size) =>
                _handleNodeSizeResolved('physical_outputs', size),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildEs5Nodes(
    List<Port> es5Inputs,
    List<Connection> connections,
    Map<String, NodePosition> stateNodePositions,
  ) {
    if (es5Inputs.isEmpty) return [];
    // Position after Physical Outputs in the layout
    const double centerX = _canvasWidth / 2;
    const double centerY = _canvasHeight / 2;

    // Check for position from state first
    final statePosition = stateNodePositions['es5_node'];
    final Offset nodePosition;

    if (statePosition != null) {
      nodePosition = Offset(statePosition.x, statePosition.y);
      _nodePositions['es5_node'] = nodePosition;
    } else {
      // Position after physical outputs with consistent spacing
      nodePosition =
          _nodePositions['es5_node'] ??
          const Offset(centerX + 600, centerY + 200);
    }

    return [
      Positioned(
        key: const ValueKey('es5_node'),
        left: nodePosition.dx,
        top: nodePosition.dy,
        child: FocusTraversalOrder(
          order: const NumericFocusOrder(50),
          child: ES5Node(
            ports: es5Inputs,
            connectedPorts: _getConnectedPortIds(connections).toSet(),
            position: nodePosition,
            onPositionChanged: (newPosition) {
              setState(() {
                _nodePositions['es5_node'] = newPosition;
              });
              // Save position to preferences
              context.read<RoutingEditorCubit>().updateNodePosition(
                'es5_node',
                newPosition.dx,
                newPosition.dy,
              );
            },
            showLabels: widget.canvasSize.width >= 800,
            onPortTapped: (port) => _handlePortTap(port),
            onPortLongPress: (port) => _handlePortLongPress(port),
            // Use animated long-press for desktop, skip for mobile (uses confirmation dialog)
            onPortLongPressStart: _platformService.isMobilePlatform()
                ? null
                : (port) => _handlePortLongPressStart(port),
            onPortLongPressCancel: _platformService.isMobilePlatform()
                ? null
                : _handlePortLongPressCancel,
            onDragStart: (port) => _handlePortDragStart(port),
            onDragUpdate: (port, position) =>
                _handlePortDragUpdate(port, position),
            onDragEnd: (port, position) => _handlePortDragEnd(port, position),
            onPortPositionResolved: (port, globalCenter) {
              // Update port position cache
              final isInput = port.direction == PortDirection.input;
              _updatePortAnchor(port.id, globalCenter, isInput);
            },
            onRoutingAction: (portId, action) =>
                _handlePortRoutingAction(portId, action, connections),
            highlightedPortId: _isDraggingConnection
                ? _highlightedPortId
                : null,
            onNodeDragStart: () {
              // Node drag start handler
            },
            onNodeDragEnd: () {
              // Node drag end handler
            },
            onSizeResolved: (size) => _handleNodeSizeResolved('es5_node', size),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAlgorithmNodes(
    List<RoutingAlgorithm> algorithms,
    List<Connection> connections,
    Map<String, NodePosition> stateNodePositions,
  ) {
    // Compute shadowed outputs once for all algorithms
    final shadowedOutputPortIds = _computeShadowedOutputPortIds(algorithms);

    return algorithms.expand((algorithm) {
      // Use stable algorithm ID instead of index for consistent positioning
      final nodeId = algorithm.id;

      // First check if there's a position from the layout algorithm in state
      final statePosition = stateNodePositions[nodeId];
      final Offset position;

      if (statePosition != null) {
        // Use position from state (layout algorithm result)
        position = Offset(statePosition.x, statePosition.y);
        // Update local cache with state position
        _nodePositions[nodeId] = position;
      } else {
        // Fall back to local position or default
        final defaultPosition = Offset(
          _canvasWidth / 2 - 250 + ((algorithm.index % 2) * 300),
          _canvasHeight / 2 - 300 + ((algorithm.index ~/ 2) * 200),
        );
        position = _nodePositions[nodeId] ?? defaultPosition;
        // Store the default position if not already in the map
        if (!_nodePositions.containsKey(nodeId)) {
          _nodePositions[nodeId] = defaultPosition;
        }
      }
      final isSelected = _focusedAlgorithmIds.contains(nodeId);

      // Extract ES-5 toggle data if this is a Clock or Euclidean algorithm
      final es5Data = _extractEs5ToggleData(algorithm);

      return [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: FocusTraversalOrder(
            order: NumericFocusOrder(algorithm.index + 1.0),
            child: AlgorithmNodeWidget(
              key: ValueKey(algorithm.id), // Use stable ID for widget key
              algorithmName: algorithm.algorithm.name,
              algorithmGuid: algorithm.algorithm.guid,
              slotNumber: algorithm.index + 1, // 1-indexed for display
              position: position,
              isSelected: isSelected,
              isDimmed: _focusedAlgorithmIds.isNotEmpty && !isSelected,
              inputLabels: algorithm.inputPorts.map((p) => p.name).toList(),
              outputLabels: algorithm.outputPorts.map((p) => p.name).toList(),
              inputPortIds: algorithm.inputPorts.map((p) => p.id).toList(),
              outputPortIds: algorithm.outputPorts.map((p) => p.id).toList(),
              outputChannelNumbers: es5Data != null
                  ? _buildOutputChannelNumbers(algorithm, es5Data)
                  : null,
              connectedPorts: _getConnectedPortIds(connections),
              shadowedPortIds: shadowedOutputPortIds,
              onPortPositionResolved: (portId, globalCenter, isInput) {
                _updatePortAnchor(portId, globalCenter, isInput);
              },
              onDragStart: () {
                _clearSelectedConnection();
                if (!_isDraggingNode) {
                  setState(() {
                    _isDraggingNode = true;
                    _isPanning = false;
                  });
                }
                // Multi-drag: if dragging a selected node with multiple selections,
                // capture all selected node positions
                if (_focusedAlgorithmIds.length > 1 &&
                    _focusedAlgorithmIds.contains(nodeId)) {
                  _multiDragPrimaryNodeId = nodeId;
                  _multiDragStartPositions = {
                    for (final id in _focusedAlgorithmIds)
                      if (_nodePositions.containsKey(id))
                        id: _nodePositions[id]!,
                  };
                }
              },
              onPositionChanged: (newPosition) {
                // When a node is being dragged, flag it so canvas doesn't pan
                if (!_isDraggingNode) {
                  setState(() {
                    _isDraggingNode = true;
                    _isPanning = false;
                  });
                }

                // Multi-drag: move all selected nodes together
                if (_multiDragStartPositions.isNotEmpty &&
                    _multiDragPrimaryNodeId == nodeId) {
                  final originalPos = _multiDragStartPositions[nodeId];
                  if (originalPos != null) {
                    final delta = newPosition - originalPos;
                    setState(() {
                      for (final entry in _multiDragStartPositions.entries) {
                        _nodePositions[entry.key] = entry.value + delta;
                      }
                    });
                    // Batch update to cubit
                    final updates = <String, Offset>{};
                    for (final entry in _multiDragStartPositions.entries) {
                      final pos = _nodePositions[entry.key];
                      if (pos != null) updates[entry.key] = pos;
                    }
                    context
                        .read<RoutingEditorCubit>()
                        .updateMultipleNodePositions(updates);
                  }
                } else {
                  // Single node drag (existing behavior)
                  setState(() {
                    _nodePositions[nodeId] = newPosition;
                  });
                  context.read<RoutingEditorCubit>().updateNodePosition(
                    nodeId,
                    newPosition.dx,
                    newPosition.dy,
                  );
                }
              },
              onDragEnd: () {
                if (_isDraggingNode) {
                  setState(() {
                    _isDraggingNode = false;
                  });
                }
                // Clear multi-drag state
                _multiDragStartPositions.clear();
                _multiDragPrimaryNodeId = null;
              },
              onMoveUp: algorithm.index > 0
                  ? () => _handleAlgorithmMoveUp(algorithm.index)
                  : null,
              onMoveDown: algorithm.index < algorithms.length - 1
                  ? () => _handleAlgorithmMoveDown(algorithm.index)
                  : null,
              // Deletion is performed inside AlgorithmNodeWidget after confirmation.
              // This callback is used for local UI cleanup only to avoid double-deletes.
              onDelete: () => _handleAlgorithmDeleted(nodeId),
              onRoutingAction: (portId, action) =>
                  _handlePortRoutingAction(portId, action, connections),
              onPortTapped: (portId) => _handlePortTapById(portId),
              onPortLongPress: (portId) => _handlePortLongPressById(portId),
              // Use animated long-press for desktop, skip for mobile (uses confirmation dialog)
              onPortLongPressStart: _platformService.isMobilePlatform()
                  ? null
                  : (portId) => _handlePortLongPressStartById(portId),
              onPortLongPressCancel: _platformService.isMobilePlatform()
                  ? null
                  : _handlePortLongPressCancel,
              onPortDragStart: _handleAlgorithmPortDragStart,
              onPortDragUpdate: _handleAlgorithmPortDragUpdate,
              onPortDragEnd: _handleAlgorithmPortDragEnd,
              highlightedPortId: _isDraggingConnection
                  ? _highlightedPortId
                  : null,
              // ES-5 toggle support for Clock/Euclidean algorithms
              es5ChannelToggles: es5Data?.toggles,
              es5ExpanderParameterNumbers: es5Data?.parameterNumbers,
              onEs5ToggleChanged: es5Data != null
                  ? (channel, enabled) => _handleEs5ToggleChange(
                      algorithm.index,
                      channel,
                      enabled,
                    )
                  : null,
              onSizeResolved: (size) => _handleNodeSizeResolved(nodeId, size),
              onTap: () => _handleNodeTap(nodeId),
            ),
          ),
        ),
      ];
    }).toList();
  }

  /// Determine which output ports are shadowed (later replace before any reader).
  Set<String> _computeShadowedOutputPortIds(List<RoutingAlgorithm> algorithms) {
    final result = <String>{};

    // Build per-bus lists of outputs and inputs with slot indices
    final outputsByBus =
        <int, List<({int slot, String portId, OutputMode? mode})>>{};
    final inputsByBus = <int, List<int>>{}; // bus -> reader slots

    for (final algo in algorithms) {
      final slot = algo.index;
      for (final p in algo.outputPorts) {
        final bus = p.busValue;
        if (bus != null && bus > 0) {
          outputsByBus.putIfAbsent(bus, () => []).add((
            slot: slot,
            portId: p.id,
            mode: p.outputMode,
          ));
        }
      }
      for (final p in algo.inputPorts) {
        final bus = p.busValue;
        if (bus != null && bus > 0) {
          inputsByBus.putIfAbsent(bus, () => []).add(slot);
        }
      }
    }

    for (final entry in outputsByBus.entries) {
      final bus = entry.key;
      final outs = List.of(entry.value)
        ..sort((a, b) => a.slot.compareTo(b.slot));
      final readers = (inputsByBus[bus] ?? const <int>[]).toList()..sort();

      for (int i = 0; i < outs.length; i++) {
        final w = outs[i];
        // Find next replace after this writer
        int? nextReplaceSlot;
        for (int j = i + 1; j < outs.length; j++) {
          final cand = outs[j];
          final mode = cand.mode ?? OutputMode.add;
          if (mode == OutputMode.replace) {
            nextReplaceSlot = cand.slot;
            break;
          }
        }

        if (nextReplaceSlot == null) {
          // No later replace: not shadowed by definition
          continue;
        }

        // Is there any reader between (w.slot, nextReplaceSlot]?
        final hasReaderBeforeNext = readers.any(
          (k) => k > w.slot && k <= nextReplaceSlot!,
        );
        if (!hasReaderBeforeNext) {
          result.add(w.portId);
        }
      }
    }

    return result;
  }

  /// Extract ES-5 toggle data for Clock/Euclidean/Clock Multiplier/Clock Divider/Poly CV algorithms.
  ///
  /// Returns null if the algorithm doesn't support ES-5 direct output.
  /// Returns maps of channel numbers to:
  /// - ES-5 Expander enabled state (true if value > 0)
  /// - ES-5 Expander parameter numbers
  /// - Channel numbers (for port identification)
  ({
    Map<int, bool> toggles,
    Map<int, int> parameterNumbers,
    List<int> channelNumbers,
  })?
  _extractEs5ToggleData(RoutingAlgorithm algorithm) {
    // Check if this is a Clock, Euclidean, Clock Multiplier, Clock Divider, or Poly CV algorithm
    final guid = algorithm.algorithm.guid;
    final isPolyCV = guid.startsWith('py');
    if (guid != 'clck' &&
        guid != 'eucp' &&
        guid != 'clkm' && // Clock Multiplier
        guid != 'clkd' && // Clock Divider
        !isPolyCV) {
      return null;
    }

    // Get the slot from DistingCubit
    final cubit = context.read<DistingCubit>();
    final state = cubit.state;
    if (state is! DistingStateSynchronized) {
      return null;
    }

    final slotIndex = algorithm.index;
    if (slotIndex < 0 || slotIndex >= state.slots.length) {
      return null;
    }

    final slot = state.slots[slotIndex];

    // Extract ES-5 Expander parameters for each channel
    final toggles = <int, bool>{};
    final parameterNumbers = <int, int>{};
    final channelNumbers = <int>[];

    if (isPolyCV) {
      // Poly CV uses global ES-5 configuration
      // Find the global ES-5 Expander parameter (no channel prefix)
      final es5ExpanderParam = slot.parameters.firstWhere(
        (p) => p.name == 'ES-5 Expander',
        orElse: () => ParameterInfo.filler(),
      );

      if (es5ExpanderParam.parameterNumber < 0) {
        return null; // No ES-5 Expander parameter found
      }

      // Get ES-5 Expander value
      final es5ExpanderValue = slot.values
          .firstWhere(
            (v) => v.parameterNumber == es5ExpanderParam.parameterNumber,
            orElse: () => ParameterValue(
              algorithmIndex: slotIndex,
              parameterNumber: es5ExpanderParam.parameterNumber,
              value: es5ExpanderParam.defaultValue,
            ),
          )
          .value;

      // Get ES-5 Output base value
      final es5OutputParam = slot.parameters.firstWhere(
        (p) => p.name == 'ES-5 Output',
        orElse: () => ParameterInfo.filler(),
      );

      final es5OutputValue = es5OutputParam.parameterNumber >= 0
          ? slot.values
                .firstWhere(
                  (v) => v.parameterNumber == es5OutputParam.parameterNumber,
                  orElse: () => ParameterValue(
                    algorithmIndex: slotIndex,
                    parameterNumber: es5OutputParam.parameterNumber,
                    value: es5OutputParam.defaultValue,
                  ),
                )
                .value
          : 1;

      // Get voice count
      final voiceCountParam = slot.parameters.firstWhere(
        (p) => p.name == 'Voices',
        orElse: () => ParameterInfo.filler(),
      );

      final voiceCount = voiceCountParam.parameterNumber >= 0
          ? slot.values
                .firstWhere(
                  (v) => v.parameterNumber == voiceCountParam.parameterNumber,
                  orElse: () => ParameterValue(
                    algorithmIndex: slotIndex,
                    parameterNumber: voiceCountParam.parameterNumber,
                    value: voiceCountParam.defaultValue,
                  ),
                )
                .value
          : 1;

      // Check if Gate outputs are enabled
      final gateOutputsParam = slot.parameters.firstWhere(
        (p) => p.name == 'Gate outputs',
        orElse: () => ParameterInfo.filler(),
      );

      final gateOutputsEnabled = gateOutputsParam.parameterNumber >= 0
          ? slot.values
                    .firstWhere(
                      (v) =>
                          v.parameterNumber == gateOutputsParam.parameterNumber,
                      orElse: () => ParameterValue(
                        algorithmIndex: slotIndex,
                        parameterNumber: gateOutputsParam.parameterNumber,
                        value: gateOutputsParam.defaultValue,
                      ),
                    )
                    .value >
                0
          : false;

      // Only populate ES-5 toggles if gates are enabled
      if (gateOutputsEnabled && es5ExpanderValue >= 0) {
        final es5Enabled = es5ExpanderValue > 0;

        // Generate synchronized toggles for each gate output (up to 8 ES-5 ports)
        for (int voice = 0; voice < voiceCount; voice++) {
          final es5Port = es5OutputValue + voice;

          // Clip to ES-5 port range (1-8)
          if (es5Port >= 1 && es5Port <= 8) {
            toggles[es5Port] = es5Enabled;
            parameterNumbers[es5Port] = es5ExpanderParam.parameterNumber;
            channelNumbers.add(es5Port);
          }
        }
      }
    } else {
      // Clock/Euclidean/Clock Multiplier/Clock Divider: per-channel ES-5 configuration
      // Find all ES-5 Expander parameters (format: "N:ES-5 Expander" for multi-channel,
      // or "ES-5 Expander" for single-channel algorithms like Clock Multiplier)
      for (final param in slot.parameters) {
        // Try multi-channel format first (e.g., "1:ES-5 Expander")
        final multiChannelMatch = RegExp(
          r'^(\d+):ES-5 Expander$',
        ).firstMatch(param.name);
        if (multiChannelMatch != null) {
          final channel = int.parse(multiChannelMatch.group(1)!);

          // Get the parameter value
          final value = slot.values
              .firstWhere(
                (v) => v.parameterNumber == param.parameterNumber,
                orElse: () => ParameterValue(
                  algorithmIndex: slotIndex,
                  parameterNumber: param.parameterNumber,
                  value: param.defaultValue,
                ),
              )
              .value;

          toggles[channel] = value > 0;
          parameterNumbers[channel] = param.parameterNumber;
          channelNumbers.add(channel);
        } else if (param.name == 'ES-5 Expander') {
          // Single-channel format (e.g., Clock Multiplier uses "ES-5 Expander" without channel prefix)
          final channel = 1; // Single-channel algorithms always use channel 1

          // Get the parameter value
          final value = slot.values
              .firstWhere(
                (v) => v.parameterNumber == param.parameterNumber,
                orElse: () => ParameterValue(
                  algorithmIndex: slotIndex,
                  parameterNumber: param.parameterNumber,
                  value: param.defaultValue,
                ),
              )
              .value;

          toggles[channel] = value > 0;
          parameterNumbers[channel] = param.parameterNumber;
          channelNumbers.add(channel);
        }
      }
    }

    if (channelNumbers.isEmpty) {
      return null;
    }

    channelNumbers.sort();

    return (
      toggles: toggles,
      parameterNumbers: parameterNumbers,
      channelNumbers: channelNumbers,
    );
  }

  /// Builds the outputChannelNumbers list aligned with output ports.
  ///
  /// For Poly CV, output ports interleave gates and pitch/velocity, so we
  /// must map channel numbers to the correct port indices. Gate ports (with
  /// busParam 'es5_direct') get their ES-5 channel number; other ports get 0.
  ///
  /// For Clock/Euclidean algorithms, each channel has exactly one output port,
  /// so the channelNumbers list from es5Data aligns naturally.
  List<int> _buildOutputChannelNumbers(
    RoutingAlgorithm algorithm,
    ({
      Map<int, bool> toggles,
      Map<int, int> parameterNumbers,
      List<int> channelNumbers,
    })
    es5Data,
  ) {
    final guid = algorithm.algorithm.guid;
    if (guid.startsWith('py')) {
      // Poly CV: gates and pitch/velocity are interleaved.
      // Only gate ports should get an ES-5 channel number.
      // Gate ports are identified by name containing "Gate" (both modes:
      // "Gate output N" when ES-5 off, "Voice N Gate → ES-5 N" when on).
      int gateIndex = 0;
      return algorithm.outputPorts.map((p) {
        final isGate = p.name.contains('Gate');
        if (isGate && gateIndex < es5Data.channelNumbers.length) {
          return es5Data.channelNumbers[gateIndex++];
        }
        return 0;
      }).toList();
    }
    // Clock/Euclidean/etc: 1:1 mapping
    return es5Data.channelNumbers;
  }

  /// Handle ES-5 toggle change for a channel.
  ///
  /// For Clock/Euclidean: Updates per-channel ES-5 Expander parameter.
  /// For Poly CV: Updates global ES-5 Expander parameter (synchronized across all gates).
  Future<void> _handleEs5ToggleChange(
    int algorithmIndex,
    int channel,
    bool enabled,
  ) async {
    final cubit = context.read<DistingCubit>();
    final state = cubit.state;
    if (state is! DistingStateSynchronized) {
      return;
    }

    if (algorithmIndex < 0 || algorithmIndex >= state.slots.length) {
      return;
    }

    final slot = state.slots[algorithmIndex];
    final guid = slot.algorithm.guid;
    final isPolyCV = guid.startsWith('py');

    ParameterInfo param;

    if (isPolyCV) {
      // Poly CV: Find the global ES-5 Expander parameter (no channel prefix)
      param = slot.parameters.firstWhere(
        (p) => p.name == 'ES-5 Expander',
        orElse: () => ParameterInfo.filler(),
      );

      if (param.parameterNumber < 0) {
        return;
      }
    } else {
      // Clock/Euclidean/Clock Multiplier/Clock Divider: Find the per-channel ES-5 Expander parameter
      // Try channel-prefixed format first (e.g., "1:ES-5 Expander")
      final paramName = '$channel:ES-5 Expander';
      param = slot.parameters.firstWhere(
        (p) => p.name == paramName,
        orElse: () => ParameterInfo.filler(),
      );

      // For single-channel algorithms (e.g., Clock Multiplier), fall back to non-prefixed parameter
      if (param.parameterNumber < 0 && channel == 1) {
        param = slot.parameters.firstWhere(
          (p) => p.name == 'ES-5 Expander',
          orElse: () => ParameterInfo.filler(),
        );
      }

      if (param.parameterNumber < 0) {
        return;
      }
    }

    // Update the parameter: 0 = Off, 1 = Expander 1
    final newValue = enabled ? 1 : 0;
    await cubit.updateParameterValue(
      algorithmIndex: algorithmIndex,
      parameterNumber: param.parameterNumber,
      value: newValue,
      userIsChangingTheValue: false,
    );
  }

  List<painter.ConnectionData> _buildConnectionDataList(
    List<Connection> connections,
    Map<String, String> portToNodeIdMap,
    Map<String, Rect> nodeBoundsMap,
    Map<String, int> zIndexByNodeId,
  ) {
    final connectionDataList = <painter.ConnectionData>[];
    final highlightedConnectionId = _connectionHighlight?.id;

    List<Rect> buildOccluderBoundsForNode(String? nodeId) {
      if (nodeId == null) return const [];
      final nodeZ = zIndexByNodeId[nodeId];
      if (nodeZ == null) return const [];
      final occluders = <Rect>[];
      nodeBoundsMap.forEach((otherNodeId, otherBounds) {
        final otherZ = zIndexByNodeId[otherNodeId];
        if (otherZ == null) return;
        if (otherZ <= nodeZ) return;
        occluders.add(otherBounds);
      });
      return occluders;
    }

    for (final connection in connections) {
      // For partial connections, we need special handling
      Offset? sourcePosition;
      Offset? targetPosition;

      if (connection.isPartial) {
        // For partial connections, one endpoint is a virtual bus endpoint
        // We only need the actual port position
        final connectionType = connection.connectionType;
        if (connectionType == ConnectionType.partialOutputToBus) {
          // Source is the actual output port
          sourcePosition = _getPortPosition(connection.sourcePortId);
          // For destination, create a position 75px to the right for the label
          if (sourcePosition != null) {
            targetPosition = Offset(sourcePosition.dx + 75, sourcePosition.dy);
          }
        } else if (connectionType == ConnectionType.partialBusToInput) {
          // Destination is the actual input port
          targetPosition = _getPortPosition(connection.destinationPortId);
          // For source, create a position 75px to the left for the label
          if (targetPosition != null) {
            sourcePosition = Offset(targetPosition.dx - 75, targetPosition.dy);
          }
        }
      } else {
        // Regular connection handling
        sourcePosition = _getPortPosition(connection.sourcePortId);
        targetPosition = _getPortPosition(connection.destinationPortId);
      }

      if (sourcePosition == null || targetPosition == null) {
        continue;
      }

      // Extract connection metadata to determine connection type
      final connectionType = connection.connectionType;

      final isPhysicalConnection =
          connectionType == ConnectionType.hardwareInput ||
          connectionType == ConnectionType.hardwareOutput;
      final isInputConnection =
          connectionType == ConnectionType.hardwareInput ||
          connectionType == ConnectionType.partialBusToInput;

      // Get bus number directly from the connection
      int? busNumber = connection.busNumber;

      // Fallback to extracting from busId if needed (e.g., "bus_5" -> 5)
      if (busNumber == null && connection.busId != null) {
        final busIdMatch = RegExp(r'bus_(\d+)').firstMatch(connection.busId!);
        if (busIdMatch != null) {
          busNumber = int.tryParse(busIdMatch.group(1)!);
        }
      }

      final sourceNodeId = portToNodeIdMap[connection.sourcePortId];
      final destinationNodeId = portToNodeIdMap[connection.destinationPortId];

      // Compute isDimmed for focus mode
      // A connection is dimmed if focus mode is active and neither endpoint belongs to a focused algorithm
      bool isDimmed = false;
      if (_focusedAlgorithmIds.isNotEmpty) {
        final sourceIsFocused = _focusedAlgorithmIds.any(
          (algoId) => connection.sourcePortId.startsWith(algoId),
        );
        final destIsFocused = _focusedAlgorithmIds.any(
          (algoId) => connection.destinationPortId.startsWith(algoId),
        );
        isDimmed = !sourceIsFocused && !destIsFocused;
      }

      connectionDataList.add(
        painter.ConnectionData(
          connection: connection,
          sourcePosition: sourcePosition,
          destinationPosition: targetPosition,
          busNumber: busNumber,
          outputMode: connection.outputMode,
          isSelected:
              _connectionHighlight?.source ==
                  _ConnectionHighlightSource.selected &&
              highlightedConnectionId == connection.id,
          isHighlighted: highlightedConnectionId == connection.id,
          isPhysicalConnection: isPhysicalConnection,
          isInputConnection: isInputConnection,
          busLabel: connection
              .busLabel, // Pass through bus label for partial connections
          onLabelHover:
              null, // Label hover is handled by the overlay widgets, not here
          onLabelTap: () => _toggleConnectionOutputMode(connection.id),
          sourceNodeBounds: nodeBoundsMap[sourceNodeId],
          destinationNodeBounds: nodeBoundsMap[destinationNodeId],
          sourceOccluderBounds: buildOccluderBoundsForNode(sourceNodeId),
          destinationOccluderBounds: buildOccluderBoundsForNode(
            destinationNodeId,
          ),
          isDimmed: isDimmed,
        ),
      );
    }
    return connectionDataList;
  }

  Widget _buildConnections(
    List<Connection> connections,
    Map<String, String> portToNodeIdMap,
    Map<String, Rect> nodeBoundsMap,
    Map<String, int> zIndexByNodeId, {
    bool drawEndpointsOnly = false,
  }) {
    if (connections.isEmpty) {
      return const SizedBox.shrink();
    }

    final connectionDataList = _buildConnectionDataList(
      connections,
      portToNodeIdMap,
      nodeBoundsMap,
      zIndexByNodeId,
    );

    if (connectionDataList.isEmpty) {
      return const SizedBox.shrink();
    }

    final editorState = context.read<RoutingEditorCubit>().state;
    final hasExtended =
        editorState is RoutingEditorStateLoaded &&
        editorState.hasExtendedAuxBuses;
    final deviceIoProfile = editorState is RoutingEditorStateLoaded
        ? editorState.deviceIoProfile
        : DeviceIoProfile.distingExtended;

    // Choose rendering approach based on platform capabilities
    if (_platformService.supportsHoverInteractions()) {
      // Desktop: Draw connections in two passes:
      // - background: full paths behind nodes, no labels
      // - foreground: clipped tips + labels above nodes (labels need bounds for hover)
      if (drawEndpointsOnly) {
        return Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(_canvasWidth, _canvasHeight),
                painter: _ConnectionPainterWithBounds(
                  connections: connectionDataList,
                  theme: Theme.of(context),
                  showLabels:
                      widget.showBusLabels &&
                      drawEndpointsOnly, // Only show labels in foreground pass
                  enableAnimations: false,
                  hoveredConnectionId: _hoveredLabelConnectionId,
                  obstacles: _calculateNodeBounds(),
                  drawEndpointsOnly: true,
                  hasExtendedAuxBuses: hasExtended,
                  deviceIoProfile: deviceIoProfile,
                  onBoundsUpdated: (bounds) {
                    if (!_areBoundsEqual(_connectionLabelBounds, bounds)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _connectionLabelBounds = bounds;
                        });
                      });
                    }
                  },
                  deletingPortId: _deletingPortId,
                  deleteAnimationProgress: _deleteAnimation.value,
                  fadeOutProgress: _fadeOutAnimation.value,
                ),
              ),
            ),
          ),
        );
      }
      return Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(_canvasWidth, _canvasHeight),
              painter: _ConnectionPainterWithBounds(
                connections: connectionDataList,
                theme: Theme.of(context),
                showLabels: false, // Labels are drawn in the foreground pass
                enableAnimations: false,
                hoveredConnectionId: null,
                obstacles: _calculateNodeBounds(),
                drawEndpointsOnly: false,
                hasExtendedAuxBuses: hasExtended,
                deviceIoProfile: deviceIoProfile,
                onBoundsUpdated: (_) {},
                deletingPortId: _deletingPortId,
                deleteAnimationProgress: _deleteAnimation.value,
                fadeOutProgress: _fadeOutAnimation.value,
              ),
            ),
          ),
        ),
      );
    } else {
      // Mobile/other: Use unified painter
      return Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(_canvasWidth, _canvasHeight),
              painter: _ConnectionPainterWithBounds(
                connections: connectionDataList,
                theme: Theme.of(context),
                showLabels: widget.showBusLabels && !drawEndpointsOnly,
                enableAnimations: false,
                hoveredConnectionId: _hoveredLabelConnectionId,
                obstacles: _calculateNodeBounds(),
                drawEndpointsOnly: drawEndpointsOnly,
                hasExtendedAuxBuses: hasExtended,
                deviceIoProfile: deviceIoProfile,
                onBoundsUpdated: (bounds) {
                  // Only update bounds for the main pass
                  if (!drawEndpointsOnly &&
                      !_areBoundsEqual(_connectionLabelBounds, bounds)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _connectionLabelBounds.addAll(bounds);
                        });
                      }
                    });
                  }
                },
                deletingPortId: _deletingPortId,
                deleteAnimationProgress: _deleteAnimation.value,
                fadeOutProgress: _fadeOutAnimation.value,
              ),
            ),
          ),
        ),
      );
    }
  }

  List<Rect> _calculateNodeBounds() {
    return _calculateNodeBoundsMap().values.toList();
  }

  Map<String, Rect> _calculateNodeBoundsMap() {
    final bounds = <String, Rect>{};

    // Access the current state to get algorithm details for accurate sizing
    final state = context.read<RoutingEditorCubit>().state;
    if (state is! RoutingEditorStateLoaded) return bounds;

    for (final entry in _nodePositions.entries) {
      final id = entry.key;
      final pos = entry.value;

      // Determine node size based on type
      // Physical nodes: 180x320
      // Algorithm nodes: Dynamic height based on ports
      final isPhysical = id == 'physical_inputs' || id == 'physical_outputs';

      // Skip physical nodes for obstacle avoidance if desired, but we need them for clipping
      // For clipping we need ALL nodes. For obstacles we might filter.
      // The original code filtered physical nodes for obstacles.
      // We should keep them in the map but maybe filter later for obstacles?
      // Actually, the original code skipped physical nodes: "if (isPhysical) continue;"
      // But for clipping we definitely need physical node bounds.

      // Let's calculate bounds for everything, and filter in _calculateNodeBounds for obstacles.

      double width = 280.0; // Default width used in layout
      double height = 200.0; // Default height

      if (isPhysical) {
        // Physical node size estimation
        // They are usually rendered with a specific width/height in PhysicalInputNode/PhysicalOutputNode
        // Let's assume a reasonable default or use reported size if available
        if (_nodeSizes.containsKey(id)) {
          width = _nodeSizes[id]!.width;
          height = _nodeSizes[id]!.height;
        } else {
          width = 180.0; // Approximate
          height = 320.0; // Approximate
        }
      } else {
        // Find the algorithm corresponding to this node ID
        final algorithm = state.algorithms.firstWhereOrNull((a) => a.id == id);

        // Use actual reported size if available
        if (_nodeSizes.containsKey(id)) {
          width = _nodeSizes[id]!.width;
          height = _nodeSizes[id]!.height;
        } else if (algorithm != null) {
          // Fallback calculation for first frame
          final inputCount = algorithm.inputPorts.length;
          final outputCount = algorithm.outputPorts.length;
          final maxPorts = math.max(inputCount, outputCount);

          // Height = Header + Padding + (Ports * PortHeight)
          height = 50.0 + 24.0 + (maxPorts * 24.0) + 4.0;
          width = 300.0;
        }
      }

      bounds[id] = Rect.fromLTWH(pos.dx, pos.dy, width, height);
    }
    return bounds;
  }

  /// Handle tap on algorithm node with shift-awareness
  ///
  /// Shift-click: toggle this algorithm in the focus set (multi-select)
  /// Plain click: select only this algorithm, or clear if already sole selection
  void _handleNodeTap(String nodeId) {
    final cubit = context.read<RoutingEditorCubit>();
    final isShiftHeld = HardwareKeyboard.instance.logicalKeysPressed.any(
      (k) =>
          k == LogicalKeyboardKey.shiftLeft ||
          k == LogicalKeyboardKey.shiftRight,
    );

    if (isShiftHeld) {
      cubit.toggleAlgorithmFocus(nodeId);
    } else {
      final currentState = cubit.state;
      if (currentState is RoutingEditorStateLoaded &&
          currentState.focusedAlgorithmIds.length == 1 &&
          currentState.focusedAlgorithmIds.contains(nodeId)) {
        cubit.clearFocus();
      } else {
        cubit.setFocusedAlgorithm(nodeId);
      }
    }
  }

  void _handleNodeSizeResolved(String nodeId, Size size) {
    if (_nodeSizes[nodeId] != size) {
      setState(() {
        _nodeSizes[nodeId] = size;
      });
      // Update cubit with actual size for layout calculations
      context.read<RoutingEditorCubit>().updateNodeSize(
        nodeId,
        size.width,
        size.height,
      );
    }
  }

  bool _areBoundsEqual(Map<String, Rect> a, Map<String, Rect> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  Widget _buildTemporaryConnection() {
    if (!_isDraggingConnection ||
        _dragSourcePort == null ||
        _dragCurrentPosition == null) {
      return const SizedBox.shrink();
    }

    final sourcePosition = _getPortPosition(_dragSourcePort!.id);
    if (sourcePosition == null) return const SizedBox.shrink();

    // Use RepaintBoundary for performance during drag operations
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TemporaryConnectionPainter(
          sourcePosition: sourcePosition,
          targetPosition: _dragCurrentPosition!,
          sourcePortId: _dragSourcePort!.id,
          theme: Theme.of(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _handleCanvasTap(Offset tapPosition, List<Connection> connections) {
    _requestCanvasFocus();
    final hitId = _findConnectionNearPoint(tapPosition, connections);
    if (hitId != null) {
      _setConnectionHighlight(hitId, _ConnectionHighlightSource.selected);
      return;
    }

    // Tap didn't hit a connection - clear selection/highlights
    _clearSelectedConnection();
    _clearConnectionHighlightState(source: _ConnectionHighlightSource.hover);
    _clearConnectionHighlightState(
      source: _ConnectionHighlightSource.deleteConfirm,
    );

    // Clear focus mode selection when tapping empty canvas
    context.read<RoutingEditorCubit>().clearFocus();
  }

  void _requestCanvasFocus() {
    if (!_platformService.isDesktopPlatform()) return;
    if (_canvasFocusNode.hasFocus) return;
    _canvasFocusNode.requestFocus();
  }

  String? _findConnectionNearPoint(
    Offset tapPoint,
    List<Connection> connections,
  ) {
    const hitRadius = 15.0;
    String? bestId;
    double bestDistance = double.infinity;

    for (final connection in connections) {
      final sourcePos = _getPortPosition(connection.sourcePortId);
      final destPos = _getPortPosition(connection.destinationPortId);
      if (sourcePos == null || destPos == null) continue;

      final d = connection.isPartial
          ? _distanceFromPointToLine(tapPoint, sourcePos, destPos)
          : _distanceFromPointToBezier(tapPoint, sourcePos, destPos);
      if (d <= hitRadius && d < bestDistance) {
        bestDistance = d;
        bestId = connection.id;
      }
    }

    return bestId;
  }

  double _distanceFromPointToLine(
    Offset point,
    Offset lineStart,
    Offset lineEnd,
  ) {
    // Calculate distance from point to line segment
    final A = point.dx - lineStart.dx;
    final B = point.dy - lineStart.dy;
    final C = lineEnd.dx - lineStart.dx;
    final D = lineEnd.dy - lineStart.dy;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;

    if (lenSq == 0) {
      // Line is a point
      return math.sqrt(A * A + B * B);
    }

    final param = dot / lenSq;

    double xx, yy;
    if (param < 0) {
      xx = lineStart.dx;
      yy = lineStart.dy;
    } else if (param > 1) {
      xx = lineEnd.dx;
      yy = lineEnd.dy;
    } else {
      xx = lineStart.dx + param * C;
      yy = lineStart.dy + param * D;
    }

    final dx = point.dx - xx;
    final dy = point.dy - yy;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _distanceFromPointToBezier(Offset point, Offset start, Offset end) {
    final path = painter.ConnectionPainter.createBezierPath(start, end);
    final metrics = path.computeMetrics();
    double minDistance = double.infinity;
    for (final metric in metrics) {
      final length = metric.length;
      const step = 2.0;
      for (double distance = 0; distance <= length; distance += step) {
        final pos = metric.getTangentForOffset(distance)?.position;
        if (pos != null) {
          final d = (point - pos).distance;
          if (d < minDistance) minDistance = d;
        }
      }
    }
    return minDistance;
  }

  void _deleteConnection(String connectionId, List<Connection> connections) {
    final routingCubit = context.read<RoutingEditorCubit>();
    final conn = connections.firstWhereOrNull((c) => c.id == connectionId);
    final reason = conn == null
        ? null
        : routingCubit.deletionBlockReasonForConnection(conn);
    if (reason != null) {
      _showError('This connection cannot be removed ($reason)');
      _clearConnectionHighlight();
      return;
    }

    _startDeletedConnectionLabelFade(connectionId, connections);

    // Announce deletion for screen readers
    if (conn != null) {
      final sourceName =
          _portById[conn.sourcePortId]?.name ?? conn.sourcePortId;
      final destName =
          _portById[conn.destinationPortId]?.name ?? conn.destinationPortId;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Connection deleted from $sourceName to $destName',
        TextDirection.ltr,
      );
    }

    // Call the cubit to delete the connection
    context.read<RoutingEditorCubit>().deleteConnection(connectionId);

    // Clear highlighting
    _clearConnectionHighlight();
  }

  void _startDeletedConnectionLabelFade(
    String connectionId,
    List<Connection> connections,
  ) {
    final bounds = _connectionLabelBounds[connectionId];
    if (bounds == null) return;

    Connection? conn;
    for (final c in connections) {
      if (c.id == connectionId) {
        conn = c;
        break;
      }
    }
    if (conn == null) return;

    final editorState = context.read<RoutingEditorCubit>().state;
    final hasExtended =
        editorState is RoutingEditorStateLoaded &&
        editorState.hasExtendedAuxBuses;
    final deviceIoProfile = editorState is RoutingEditorStateLoaded
        ? editorState.deviceIoProfile
        : DeviceIoProfile.distingExtended;
    final label = painter.ConnectionPainter.formatBusLabelWithMode(
      conn.busNumber,
      conn.outputMode,
      hasExtended,
      deviceIoProfile,
    );
    if (label.isEmpty) return;

    setState(() {
      _fadingDeletedConnectionLabels.add(
        _FadingDeletedConnectionLabel(
          key: UniqueKey(),
          bounds: bounds,
          label: label,
        ),
      );
    });
  }

  List<Widget> _buildFadingDeletedConnectionLabelOverlays() {
    if (_fadingDeletedConnectionLabels.isEmpty) return const [];

    final overlays = <Widget>[];
    for (final entry in _fadingDeletedConnectionLabels) {
      overlays.add(
        Positioned(
          left: entry.bounds.left,
          top: entry.bounds.top,
          width: entry.bounds.width,
          height: entry.bounds.height,
          child: IgnorePointer(
            child: _FadingLabelOverlay(
              key: entry.key,
              label: entry.label,
              onDone: () {
                if (!mounted) return;
                setState(() {
                  _fadingDeletedConnectionLabels.removeWhere(
                    (e) => e.key == entry.key,
                  );
                });
              },
            ),
          ),
        ),
      );
    }

    return overlays;
  }

  void _clearConnectionHighlight() {
    _connectionHighlightTimer?.cancel();
    _clearConnectionHighlightState(source: _ConnectionHighlightSource.hover);
  }

  // Transform-aware event handlers for InteractiveViewer
  void _handleCanvasPanStart(DragStartDetails details) {
    // Only start panning if we're not dragging a node
    if (!_isDraggingNode) {
      _requestCanvasFocus();
      _clearSelectedConnection();
      _isPanning = true;
      _lastPanPosition = details.globalPosition;
    }
  }

  void _handleCanvasPanUpdate(DragUpdateDetails details) {
    if (_isPanning && !_isDraggingNode) {
      // Pan the canvas by adjusting scroll controllers
      final delta = details.globalPosition - _lastPanPosition;
      _lastPanPosition = details.globalPosition;

      if (_horizontalScrollController.hasClients) {
        final newHorizontal = _horizontalScrollController.offset - delta.dx;
        _horizontalScrollController.jumpTo(
          newHorizontal.clamp(
            0.0,
            _horizontalScrollController.position.maxScrollExtent,
          ),
        );
      }

      if (_verticalScrollController.hasClients) {
        final newVertical = _verticalScrollController.offset - delta.dy;
        _verticalScrollController.jumpTo(
          newVertical.clamp(
            0.0,
            _verticalScrollController.position.maxScrollExtent,
          ),
        );
      }
    }
  }

  void _handleCanvasPanEnd(DragEndDetails details) {
    setState(() {
      _isPanning = false;
      _isDraggingNode = false;
    });
  }

  // Port and node interaction handlers
  void _handlePortTap(Port port) {
    _clearSelectedConnection();
    // Use tap for accessible connection creation (two-tap flow)
    _handlePortKeyboardActivation(port.id);
  }

  /// Handle long-press on a port to delete its connections.
  /// Works on both inputs and outputs for consistent UX.
  void _handlePortLongPress(Port port) {
    _clearSelectedConnection();
    if (_platformService.isMobilePlatform()) {
      // Mobile: Show confirmation dialog
      _showPortConnectionsDeleteConfirmation(port.id, port.name);
    } else {
      // Desktop: Immediate deletion on long-press
      final cubit = context.read<RoutingEditorCubit>();
      cubit.deleteConnectionsForPort(port.id);
    }
  }

  /// Handle long-press on a port by its ID (for algorithm nodes).
  void _handlePortLongPressById(String portId) {
    _clearSelectedConnection();
    final port = _portById[portId];
    if (port != null) {
      _handlePortLongPress(port);
    }
  }

  void _handlePortTapById(String portId) {
    _clearSelectedConnection();
    final tappedPort = _portById[portId];
    if (tappedPort == null || !tappedPort.isInput) return;

    if (_platformService.isMobilePlatform()) {
      // Mobile: Show confirmation dialog
      _showPortConnectionsDeleteConfirmation(portId, null);
    } else {
      // Desktop: Keep immediate deletion
      final cubit = context.read<RoutingEditorCubit>();
      cubit.deleteConnectionsForPort(portId);
    }
  }

  void _handlePortDragStart(Port port) {
    _clearSelectedConnection();
    // Allow dragging from both input and output ports for bidirectional connection creation
    // - From output: drag to input (original behavior)
    // - From input: drag to output (new bidirectional support)

    // Get the current port position
    final portPosition = _getPortPosition(port.id);
    if (portPosition == null) {
      return;
    }

    setState(() {
      _isDraggingConnection = true;
      _dragSourcePort = port;
      _dragCurrentPosition = portPosition;
    });
  }

  void _handlePortDragUpdate(Port port, Offset position) {
    // Only update if we're dragging a connection and this is the source port
    if (!_isDraggingConnection || _dragSourcePort?.id != port.id) {
      return;
    }

    // Convert global position to local canvas coordinates
    // The canvas is already scaled by Transform.scale, so globalToLocal gives us
    // the correct coordinates in the scaled space
    final ctx = _canvasKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPosition = box.globalToLocal(position);

    // Immediate position update for fluid preview
    setState(() {
      _dragCurrentPosition = localPosition;
    });

    // Cancel previous debounce timer
    _dragUpdateDebounceTimer?.cancel();

    // Debounced port detection (16ms for 60fps)
    _dragUpdateDebounceTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted ||
          !_isDraggingConnection ||
          _dragSourcePort?.id != port.id) {
        return;
      }

      final targetPort = _findPortAtPosition(localPosition);
      String? newHighlight;
      if (targetPort != null &&
          _dragSourcePort != null &&
          ConnectionValidator.isValidConnection(_dragSourcePort!, targetPort)) {
        newHighlight = targetPort.id;
      }

      // Only setState if highlight actually changed
      if (newHighlight != _highlightedPortId) {
        setState(() {
          _highlightedPortId = newHighlight;
        });
      }
    });
  }

  // Handler methods for algorithm port drags (using port ID instead of Port object)
  void _handleAlgorithmPortDragStart(String portId) {
    _clearSelectedConnection();
    final port = _portById[portId];
    if (port == null) return;

    // Allow dragging from both input and output ports for bidirectional connection creation

    // Get the current port position
    final portPosition = _getPortPosition(portId);
    if (portPosition == null) {
      return;
    }

    setState(() {
      _isDraggingConnection = true;
      _dragSourcePort = port;
      _dragCurrentPosition = portPosition;
    });
  }

  void _handleAlgorithmPortDragUpdate(String portId, Offset position) {
    // Only update if we're dragging a connection and this is the source port
    if (!_isDraggingConnection || _dragSourcePort?.id != portId) {
      return;
    }

    // Convert global position to local canvas coordinates
    final ctx = _canvasKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPosition = box.globalToLocal(position);

    // Immediate position update for fluid preview
    setState(() {
      _dragCurrentPosition = localPosition;
    });

    // Cancel previous debounce timer
    _dragUpdateDebounceTimer?.cancel();

    // Debounced port detection (16ms for 60fps)
    _dragUpdateDebounceTimer = Timer(const Duration(milliseconds: 16), () {
      if (!mounted || !_isDraggingConnection || _dragSourcePort?.id != portId) {
        return;
      }

      final targetPort = _findPortAtPosition(localPosition);
      String? newHighlight;
      if (targetPort != null &&
          _dragSourcePort != null &&
          ConnectionValidator.isValidConnection(_dragSourcePort!, targetPort)) {
        newHighlight = targetPort.id;
      }

      // Only setState if highlight actually changed
      if (newHighlight != _highlightedPortId) {
        setState(() {
          _highlightedPortId = newHighlight;
        });
      }
    });
  }

  Future<void> _handleAlgorithmPortDragEnd(
    String portId,
    Offset position,
  ) async {
    // Convert global position to local canvas coordinates
    final ctx = _canvasKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPosition = box.globalToLocal(position);

    // Only handle if we're dragging a connection and this is the source port
    if (!_isDraggingConnection || _dragSourcePort?.id != portId) {
      return;
    }

    // Cancel any pending drag update
    _dragUpdateDebounceTimer?.cancel();

    try {
      // Find port at drop position
      final targetPort = _findPortAtPosition(localPosition);
      final sourcePort = _dragSourcePort;

      if (targetPort == null || sourcePort == null) {
        return;
      }

      if (ConnectionValidator.isValidConnection(sourcePort, targetPort)) {
        final resolved = ConnectionValidator.resolveConnectionDirection(
          sourcePort,
          targetPort,
        );
        if (resolved == null) return;
        final (actualSourcePortId, actualTargetPortId) = resolved;

        // Check for duplicate connection before attempting to create
        final cubit = context.read<RoutingEditorCubit>();
        final currentState = cubit.state;
        if (currentState is RoutingEditorStateLoaded) {
          final exists = currentState.connections.any(
            (conn) =>
                conn.sourcePortId == actualSourcePortId &&
                conn.destinationPortId == actualTargetPortId,
          );

          if (exists) {
            _showError('Connection already exists between these ports');
            return;
          }
        }

        // Create the connection
        try {
          await cubit.createConnection(
            sourcePortId: actualSourcePortId,
            targetPortId: actualTargetPortId,
          );
        } catch (e) {
          _showError(
            e is StateError ? e.message : 'Connection failed: ${e.toString()}',
          );
        }
      }
    } finally {
      // Always clear drag state
      setState(() {
        _isDraggingConnection = false;
        _dragSourcePort = null;
        _dragCurrentPosition = null;
        _highlightedPortId = null;
      });
    }
  }

  Future<void> _handlePortDragEnd(Port port, Offset position) async {
    // Convert global position to local canvas coordinates
    // The canvas is already scaled by Transform.scale, so globalToLocal gives us
    // the correct coordinates in the scaled space
    final ctx = _canvasKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final localPosition = box.globalToLocal(position);

    // Only handle if we're dragging a connection and this is the source port
    if (!_isDraggingConnection || _dragSourcePort?.id != port.id) {
      return;
    }

    // Cancel any pending drag update
    _dragUpdateDebounceTimer?.cancel();

    try {
      // Find port at drop position
      final targetPort = _findPortAtPosition(localPosition);
      final sourcePort = _dragSourcePort;

      if (targetPort == null || sourcePort == null) {
        return;
      }

      // Validate using symmetric ConnectionValidator
      if (ConnectionValidator.isValidConnection(sourcePort, targetPort)) {
        // Resolve which port is source vs target based on roles
        final resolved = ConnectionValidator.resolveConnectionDirection(
          sourcePort,
          targetPort,
        );
        if (resolved == null) return;
        final (actualSourcePortId, actualTargetPortId) = resolved;

        // Check for duplicate connection before attempting to create
        final currentState = context.read<RoutingEditorCubit>().state;
        if (currentState is RoutingEditorStateLoaded) {
          final existingConnection = currentState.connections.any(
            (conn) =>
                conn.sourcePortId == actualSourcePortId &&
                conn.destinationPortId == actualTargetPortId,
          );

          if (existingConnection) {
            _showError('Connection already exists between these ports');
            return;
          }
        }

        // Create the connection using the cubit
        final cubit = context.read<RoutingEditorCubit>();
        await _createConnectionWithErrorHandling(
          cubit,
          actualSourcePortId,
          actualTargetPortId,
        );
      }
    } catch (e) {
      _showError(
        e is StateError ? e.message : 'Connection failed: ${e.toString()}',
      );
    } finally {
      // Always clear drag state
      setState(() {
        _isDraggingConnection = false;
        _dragSourcePort = null;
        _dragCurrentPosition = null;
        _highlightedPortId = null; // Clear highlighting when drag ends
      });
    }
  }

  Future<void> _showPortConnectionsDeleteConfirmation(
    String portId,
    String? portName,
  ) async {
    // Get the current state to find connections
    final routingState = context.read<RoutingEditorCubit>().state;
    if (routingState is! RoutingEditorStateLoaded) return;

    // Find all connections for this port
    final portConnections = routingState.connections
        .where(
          (conn) =>
              conn.sourcePortId == portId || conn.destinationPortId == portId,
        )
        .toList();

    if (portConnections.isEmpty) {
      return;
    }

    // Highlight the connections that will be deleted
    setState(() {
      // Only allow a single highlighted connection at a time.
      _connectionHighlight = _ConnectionHighlight(
        id: portConnections.first.id,
        source: _ConnectionHighlightSource.deleteConfirm,
      );
    });

    // Build connection descriptions for the dialog
    final connectionDescriptions = <String>[];
    for (final connection in portConnections) {
      // Try to find actual port names
      final allPorts = [
        ...routingState.physicalInputs,
        ...routingState.physicalOutputs,
        for (final algo in routingState.algorithms) ...[
          ...algo.inputPorts,
          ...algo.outputPorts,
        ],
      ];

      final sourcePort = allPorts.firstWhere(
        (p) => p.id == connection.sourcePortId,
        orElse: () => Port(
          id: '',
          name: connection.sourcePortId,
          type: PortType.cv,
          direction: PortDirection.input,
        ),
      );
      final destPort = allPorts.firstWhere(
        (p) => p.id == connection.destinationPortId,
        orElse: () => Port(
          id: '',
          name: connection.destinationPortId,
          type: PortType.cv,
          direction: PortDirection.input,
        ),
      );

      connectionDescriptions.add('${sourcePort.name} → ${destPort.name}');
    }

    // Show confirmation dialog
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          portConnections.length == 1
              ? 'Delete Connection?'
              : 'Delete ${portConnections.length} Connections?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (portName != null) Text('From port: $portName\n'),
            Text(
              portConnections.length == 1
                  ? 'This will delete the connection:'
                  : 'This will delete the following connections:',
            ),
            const SizedBox(height: 8),
            ...connectionDescriptions.map(
              (desc) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $desc', style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
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

    // Clear highlighting
    _clearConnectionHighlightState(
      source: _ConnectionHighlightSource.deleteConfirm,
    );

    // Delete connections if confirmed
    if (shouldDelete == true && mounted) {
      final cubit = context.read<RoutingEditorCubit>();
      await cubit.runBatched(() async {
        for (final connection in portConnections) {
          await cubit.deleteConnectionWithSmartBusLogic(connection.id);
        }
      });
    }
  }

  bool _hasLoadedStateChanged(
    RoutingEditorStateLoaded previous,
    RoutingEditorStateLoaded current,
  ) {
    /* same as RoutingCanvas */
    if (previous.physicalInputs.length != current.physicalInputs.length ||
        previous.physicalOutputs.length != current.physicalOutputs.length ||
        previous.algorithms.length != current.algorithms.length ||
        previous.connections.length != current.connections.length ||
        previous.nodePositions.length != current.nodePositions.length ||
        previous.zoomLevel != current.zoomLevel ||
        previous.panOffset != current.panOffset) {
      return true;
    }

    // Check if node positions have changed
    for (final entry in current.nodePositions.entries) {
      final prevPosition = previous.nodePositions[entry.key];
      if (prevPosition == null ||
          prevPosition.x != entry.value.x ||
          prevPosition.y != entry.value.y) {
        return true;
      }
    }
    for (int i = 0; i < current.algorithms.length; i++) {
      if (i >= previous.algorithms.length) return true;
      final prevAlg = previous.algorithms[i];
      final currAlg = current.algorithms[i];
      if (prevAlg.index != currAlg.index ||
          prevAlg.algorithm.name != currAlg.algorithm.name) {
        return true;
      }
      if (prevAlg.inputPorts.length != currAlg.inputPorts.length) return true;
      for (int p = 0; p < currAlg.inputPorts.length; p++) {
        final a = prevAlg.inputPorts[p];
        final b = currAlg.inputPorts[p];
        if (a.id != b.id ||
            a.name != b.name ||
            a.type != b.type ||
            a.direction != b.direction) {
          return true;
        }
      }
      if (prevAlg.outputPorts.length != currAlg.outputPorts.length) return true;
      for (int p = 0; p < currAlg.outputPorts.length; p++) {
        final a = prevAlg.outputPorts[p];
        final b = currAlg.outputPorts[p];
        if (a.id != b.id ||
            a.name != b.name ||
            a.type != b.type ||
            a.direction != b.direction) {
          return true;
        }
      }
    }
    if (previous.connections.length != current.connections.length) return true;
    for (int i = 0; i < current.connections.length; i++) {
      if (i >= previous.connections.length) return true;
      final prev = previous.connections[i];
      final curr = current.connections[i];
      if (prev.sourcePortId != curr.sourcePortId ||
          prev.destinationPortId != curr.destinationPortId ||
          prev.outputMode != curr.outputMode ||
          prev.gain != curr.gain ||
          prev.isMuted != curr.isMuted ||
          prev.busNumber != curr.busNumber ||
          prev.busLabel != curr.busLabel) {
        return true;
      }
    }

    // Check focused algorithm IDs for highlight changes
    if (!_setEquals(
      previous.focusedAlgorithmIds,
      current.focusedAlgorithmIds,
    )) {
      return true;
    }

    return false;
  }

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// Check if the routing structure (ports and algorithms) has actually changed
  /// This is more restrictive than _hasLoadedStateChanged and only returns true
  /// when the visual layout needs to be recreated
  bool _hasRoutingStructureChanged(
    RoutingEditorStateLoaded previous,
    RoutingEditorStateLoaded current,
  ) {
    // Check if algorithms changed structurally
    if (previous.algorithms.length != current.algorithms.length) {
      return true;
    }

    for (int i = 0; i < current.algorithms.length; i++) {
      final prevAlg = previous.algorithms[i];
      final currAlg = current.algorithms[i];

      // Algorithm changed (different type or position)
      if (prevAlg.algorithm.guid != currAlg.algorithm.guid ||
          prevAlg.index != currAlg.index) {
        return true;
      }

      // Port structure changed
      if (prevAlg.inputPorts.length != currAlg.inputPorts.length ||
          prevAlg.outputPorts.length != currAlg.outputPorts.length) {
        return true;
      }

      // Port IDs changed (indicates different routing)
      for (int p = 0; p < currAlg.inputPorts.length; p++) {
        if (prevAlg.inputPorts[p].id != currAlg.inputPorts[p].id) {
          return true;
        }
      }
      for (int p = 0; p < currAlg.outputPorts.length; p++) {
        if (prevAlg.outputPorts[p].id != currAlg.outputPorts[p].id) {
          return true;
        }
      }
    }

    // Physical ports structure changed
    if (previous.physicalInputs.length != current.physicalInputs.length ||
        previous.physicalOutputs.length != current.physicalOutputs.length) {
      return true;
    }

    return false;
  }

  // Algorithm operation handlers
  void _handleAlgorithmMoveUp(int algorithmIndex) {
    final cubit = context.read<DistingCubit>();
    cubit.moveAlgorithmUp(algorithmIndex);
  }

  void _handleAlgorithmMoveDown(int algorithmIndex) {
    final cubit = context.read<DistingCubit>();
    cubit.moveAlgorithmDown(algorithmIndex);
  }

  void _handleAlgorithmDeleted(String algorithmId) {
    setState(() {
      _selectedNodes.remove(algorithmId);
      _nodePositions.remove(algorithmId);
      _nodeSizes.remove(algorithmId);
      _portPositions.removeWhere((portId, _) => portId.startsWith(algorithmId));
    });
  }

  /// Calculate port position based on node position and port layout
  /// This provides consistent positions without relying on cached values
  Offset? _calculatePortPositionFromNodeLayout(String portId) {
    final routingState = context.read<RoutingEditorCubit>().state;
    if (routingState is! RoutingEditorStateLoaded) return null;

    // Physical input ports
    if (portId.startsWith('hw_in_')) {
      final nodePos =
          _nodePositions['physical_inputs'] ??
          const Offset(100, _canvasHeight / 2);
      // Find the port in the physical inputs list
      final portIndex = routingState.physicalInputs.indexWhere(
        (p) => p.id == portId,
      );
      if (portIndex == -1) return null;

      // Physical inputs node layout:
      // - Header: ~48px height (includes padding and icon row)
      // - Each port: ~32px height (including spacing)
      // - Port dot is on the right side of the node
      final headerHeight = 48.0;
      final portHeight = 32.0;
      final nodeWidth = 145.0; // Approximate width of physical input node

      final yOffset =
          headerHeight + (portIndex * portHeight) + (portHeight / 2);
      return Offset(nodePos.dx + nodeWidth, nodePos.dy + yOffset);
    }

    // Physical output ports
    if (portId.startsWith('hw_out_')) {
      final nodePos =
          _nodePositions['physical_outputs'] ??
          Offset(_canvasWidth - 300, _canvasHeight / 2);
      // Find the port in the physical outputs list
      final portIndex = routingState.physicalOutputs.indexWhere(
        (p) => p.id == portId,
      );
      if (portIndex == -1) return null;

      // Physical outputs node layout (similar to inputs):
      // - Header: ~40px height
      // - Each port: ~28px height
      // - Port dot is on the left side of the node
      final headerHeight = 40.0;
      final portHeight = 28.0;

      final yOffset =
          headerHeight + (portIndex * portHeight) + (portHeight / 2);
      return Offset(nodePos.dx, nodePos.dy + yOffset);
    }

    // Algorithm ports
    for (final algo in routingState.algorithms) {
      // Check input ports
      final inputPortIndex = algo.inputPorts.indexWhere((p) => p.id == portId);
      if (inputPortIndex != -1) {
        final nodePos = _nodePositions[algo.id];
        if (nodePos == null) return null;

        // Algorithm node layout:
        // - Header: ~52px height (title + index + padding)
        // - Each port: ~32px height (including spacing)
        // - Inputs on left edge
        final headerHeight = 52.0;
        final portHeight = 32.0;

        final yOffset =
            headerHeight + (inputPortIndex * portHeight) + (portHeight / 2);
        return Offset(nodePos.dx, nodePos.dy + yOffset);
      }

      // Check output ports
      final outputPortIndex = algo.outputPorts.indexWhere(
        (p) => p.id == portId,
      );
      if (outputPortIndex != -1) {
        final nodePos = _nodePositions[algo.id];
        if (nodePos == null) return null;

        // Algorithm node layout (outputs on right)
        final headerHeight = 52.0;
        final portHeight = 32.0;
        final nodeWidth = 280.0; // Approximate width of algorithm node

        final yOffset =
            headerHeight + (outputPortIndex * portHeight) + (portHeight / 2);
        return Offset(nodePos.dx + nodeWidth, nodePos.dy + yOffset);
      }
    }

    // Port not found
    return null;
  }

  Offset? _getPortPosition(String portId) {
    // Use actual port position from widget callbacks
    // Fall back to calculated position if not yet available
    return _portPositions[portId] ??
        _calculatePortPositionFromNodeLayout(portId);
  }

  /// Find a port at the given position within a reasonable hit radius
  Port? _findPortAtPosition(Offset position) {
    const double hitRadius = 20.0; // Pixels

    final routingState = context.read<RoutingEditorCubit>().state;
    if (routingState is! RoutingEditorStateLoaded) return null;

    // Check all ports and find the closest one within hit radius
    Port? closestPort;
    double closestDistance = double.infinity;

    // Helper function to check a port's position
    void checkPort(Port port) {
      final portPosition = _getPortPosition(port.id);
      if (portPosition != null) {
        final distance = (position - portPosition).distance;
        if (distance <= hitRadius && distance < closestDistance) {
          closestDistance = distance;
          closestPort = port;
        }
      }
    }

    // Check physical inputs
    for (final port in routingState.physicalInputs) {
      checkPort(port);
    }

    // Check physical outputs
    for (final port in routingState.physicalOutputs) {
      checkPort(port);
    }

    // Check ES-5 ports
    for (final port in routingState.es5Inputs) {
      checkPort(port);
    }

    // Check algorithm ports
    for (final algorithm in routingState.algorithms) {
      for (final port in algorithm.inputPorts) {
        checkPort(port);
      }
      for (final port in algorithm.outputPorts) {
        checkPort(port);
      }
    }

    return closestPort;
  }

  /// Get a set of all connected port IDs
  Set<String> _getConnectedPortIds(List<Connection> connections) {
    final connectedPorts = <String>{};
    for (final connection in connections) {
      connectedPorts.add(connection.sourcePortId);
      connectedPorts.add(connection.destinationPortId);
    }
    return connectedPorts;
  }

  /// Handle routing actions from PortWidget
  void _handlePortRoutingAction(
    String portId,
    String action,
    List<Connection> connections,
  ) {
    switch (action) {
      case 'hover_start':
        // Do not override an explicit user selection with a transient hover
        // highlight; selection has priority for keyboard delete.
        if (_connectionHighlight?.source ==
            _ConnectionHighlightSource.selected) {
          break;
        }
        // Find connections involving this port and highlight the first one
        final portConnections = connections
            .where(
              (conn) =>
                  conn.sourcePortId == portId ||
                  conn.destinationPortId == portId,
            )
            .toList();

        if (portConnections.isNotEmpty) {
          _connectionHighlightTimer?.cancel();
          setState(() {
            // Ensure only one highlighted connection at a time.
            _connectionHighlight = _ConnectionHighlight(
              id: portConnections.first.id,
              source: _ConnectionHighlightSource.hover,
            );
          });

          // Auto-deselect after 5 seconds
          _connectionHighlightTimer = Timer(const Duration(seconds: 5), () {
            _clearConnectionHighlightState(
              source: _ConnectionHighlightSource.hover,
            );
          });
        }
        break;

      case 'hover_end':
        if (_connectionHighlight?.source ==
            _ConnectionHighlightSource.selected) {
          break;
        }
        _clearConnectionHighlightState(
          source: _ConnectionHighlightSource.hover,
        );
        break;

      case 'delete_connections':
        // Find and delete all connections for this port
        final portConnections = connections
            .where(
              (conn) =>
                  conn.sourcePortId == portId ||
                  conn.destinationPortId == portId,
            )
            .toList();

        final cubit = context.read<RoutingEditorCubit>();
        for (final connection in portConnections) {
          cubit.deleteConnectionWithSmartBusLogic(connection.id);
        }
        break;
    }
  }

  /// Build invisible overlays positioned over connection labels for gesture detection
  List<Widget> _buildConnectionLabelOverlays(
    List<Connection> visibleConnections,
  ) {
    final overlays = <Widget>[];
    final routingState = context.read<RoutingEditorCubit>().state;
    if (routingState is! RoutingEditorStateLoaded) return overlays;
    final visibleConnectionIds = visibleConnections
        .map((connection) => connection.id)
        .toSet();

    for (final entry in _connectionLabelBounds.entries) {
      final connectionId = entry.key;
      final bounds = entry.value;

      // Check if this is a partial connection bus label
      if (connectionId.startsWith('partial_')) {
        // This is an unconnected bus label - add tap handler to clear the output
        final actualConnectionId = connectionId.substring(
          8,
        ); // Remove 'partial_' prefix
        if (!visibleConnectionIds.contains(actualConnectionId)) continue;

        overlays.add(
          Positioned(
            left: bounds.left,
            top: bounds.top,
            width: bounds.width,
            height: bounds.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  _clearOutputBusForPartialConnection(actualConnectionId),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  color: Colors.transparent, // Invisible but tappable
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // Find the connection to check if it has a mode parameter
      final connection = visibleConnections.firstWhere(
        (conn) => conn.id == connectionId,
        orElse: () => Connection(
          id: connectionId,
          sourcePortId: '',
          destinationPortId: '',
          connectionType: ConnectionType.algorithmToAlgorithm,
        ),
      );
      if (!visibleConnectionIds.contains(connection.id)) continue;

      // Find the source port to check for mode parameter
      // Collect all ports from algorithms
      final allPorts = [
        ...routingState.physicalInputs,
        ...routingState.physicalOutputs,
        for (final algo in routingState.algorithms) ...[
          ...algo.inputPorts,
          ...algo.outputPorts,
        ],
      ];

      final sourcePort = allPorts.firstWhere(
        (port) => port.id == connection.sourcePortId,
        orElse: () => Port(
          id: '',
          name: '',
          type: PortType.cv,
          direction: PortDirection.input,
        ),
      );

      // Only add hover effect if the port has a mode parameter
      final hasModeParameter = sourcePort.modeParameterNumber != null;

      Widget overlay = GestureDetector(
        behavior: HitTestBehavior.opaque, // Capture all taps in this area
        onTap: () {
          _requestCanvasFocus();
          _clearSelectedConnection();
          _toggleConnectionOutputMode(connectionId);
        },
        child: const SizedBox.expand(), // Fill the entire positioned area
      );

      // Wrap in MouseRegion only if it has a mode parameter
      if (hasModeParameter) {
        overlay = MouseRegion(
          onEnter: (_) {
            setState(() {
              _hoveredLabelConnectionId = connectionId;
            });
          },
          onExit: (_) {
            setState(() {
              _hoveredLabelConnectionId = null;
            });
          },
          child: overlay,
        );
      }

      overlays.add(
        Positioned(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
          child: overlay,
        ),
      );
    }

    return overlays;
  }

  /// Toggle output mode for a connection between add (0) and replace (1)
  /// Clear the output bus assignment for a partial connection
  void _clearOutputBusForPartialConnection(String connectionId) {
    final routingCubit = context.read<RoutingEditorCubit>();
    final routingState = routingCubit.state;

    if (routingState is! RoutingEditorStateLoaded) return;

    // Find the partial connection
    final connection = routingState.connections.firstWhere(
      (conn) => conn.id == connectionId && conn.isPartial,
      orElse: () => Connection(
        id: '',
        sourcePortId: '',
        destinationPortId: '',
        connectionType: ConnectionType.algorithmToAlgorithm,
      ),
    );

    if (connection.id.isEmpty) {
      return;
    }

    // For partial output-to-bus connections, the source is the output port
    if (connection.connectionType == ConnectionType.partialOutputToBus) {
      final sourcePortId = connection.sourcePortId;

      // Find the port and its algorithm
      for (final algorithm in routingState.algorithms) {
        for (final port in algorithm.outputPorts) {
          if (port.id == sourcePortId &&
              port.parameterNumber != null &&
              port.parameterNumber! >= 0) {
            // Clear the bus assignment by setting parameter to 0
            context.read<DistingCubit>().updateParameterValue(
              algorithmIndex: algorithm.index,
              parameterNumber: port.parameterNumber!,
              value: 0, // 0 means "None" for bus assignments
              userIsChangingTheValue: true,
            );
            return;
          }
        }
      }
    }

    // For partial bus-to-input connections, the destination is the input port
    if (connection.connectionType == ConnectionType.partialBusToInput) {
      final destPortId = connection.destinationPortId;

      for (final algorithm in routingState.algorithms) {
        for (final port in algorithm.inputPorts) {
          if (port.id == destPortId &&
              port.parameterNumber != null &&
              port.parameterNumber! >= 0) {
            context.read<DistingCubit>().updateParameterValue(
              algorithmIndex: algorithm.index,
              parameterNumber: port.parameterNumber!,
              value: 0,
              userIsChangingTheValue: true,
            );
            return;
          }
        }
      }
    }
  }

  void _toggleConnectionOutputMode(String connectionId) {
    final routingState = context.read<RoutingEditorCubit>().state;
    if (routingState is! RoutingEditorStateLoaded) return;

    // Find the connection to get its source port
    final connection = routingState.connections.firstWhere(
      (conn) => conn.id == connectionId,
      orElse: () => throw ArgumentError('Connection not found: $connectionId'),
    );

    // Toggle the output mode for the source port
    context.read<RoutingEditorCubit>().togglePortOutputMode(
      portId: connection.sourcePortId,
    );
  }
}

class _FadingDeletedConnectionLabel {
  final Key key;
  final Rect bounds;
  final String label;

  const _FadingDeletedConnectionLabel({
    required this.key,
    required this.bounds,
    required this.label,
  });
}

enum _ConnectionHighlightSource { selected, hover, deleteConfirm }

class _ConnectionHighlight {
  final String id;
  final _ConnectionHighlightSource source;

  const _ConnectionHighlight({required this.id, required this.source});
}

class _FadingLabelOverlay extends StatelessWidget {
  final String label;
  final VoidCallback onDone;

  const _FadingLabelOverlay({
    super.key,
    required this.label,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 200),
      onEnd: onDone,
      builder: (context, value, child) {
        return Opacity(opacity: value, child: child);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(width: 2.0, color: scheme.outline),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasGridPainter extends CustomPainter {
  /* same as canvas */
  final Color minorGridColor;
  final Color majorGridColor;
  final double gridSize;
  final int majorEvery;
  const _CanvasGridPainter({
    required this.minorGridColor,
    required this.majorGridColor,
    this.gridSize = 50.0,
    this.majorEvery = 5,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final minorPaint = Paint()
      ..color = minorGridColor
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = majorGridColor
      ..strokeWidth = 1.5;
    for (double x = 0; x <= size.width; x += gridSize) {
      final isMajor = (x / gridSize) % majorEvery == 0;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorPaint : minorPaint,
      );
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      final isMajor = (y / gridSize) % majorEvery == 0;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? majorPaint : minorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ConnectionPainter wrapper that stores bounds in the widget state
class _ConnectionPainterWithBounds extends CustomPainter {
  final List<painter.ConnectionData> connections;
  final ThemeData theme;
  final bool showLabels;
  final bool enableAnimations;
  final String? hoveredConnectionId;
  final List<Rect> obstacles;
  final bool drawEndpointsOnly;
  final Function(Map<String, Rect>) onBoundsUpdated;

  /// Port ID being long-pressed for deletion animation
  final String? deletingPortId;

  /// Progress of delete animation (0.0 to 1.0) - red → orange → white
  final double deleteAnimationProgress;

  /// Progress of fade-out animation (0.0 to 1.0) - white → transparent
  final double fadeOutProgress;

  late final painter.ConnectionPainter _delegate;

  final bool hasExtendedAuxBuses;
  final DeviceIoProfile deviceIoProfile;

  _ConnectionPainterWithBounds({
    required this.connections,
    required this.theme,
    required this.showLabels,
    required this.enableAnimations,
    required this.hoveredConnectionId,
    required this.obstacles,
    this.drawEndpointsOnly = false,
    required this.onBoundsUpdated,
    this.deletingPortId,
    this.deleteAnimationProgress = 0.0,
    this.fadeOutProgress = 0.0,
    this.hasExtendedAuxBuses = false,
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    _delegate = painter.ConnectionPainter(
      connections: connections,
      theme: theme,
      showLabels: showLabels,
      enableAnimations: enableAnimations,
      hoveredConnectionId: hoveredConnectionId,
      obstacles: obstacles,
      drawEndpointsOnly: drawEndpointsOnly,
      deletingPortId: deletingPortId,
      deleteAnimationProgress: deleteAnimationProgress,
      fadeOutProgress: fadeOutProgress,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: deviceIoProfile,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Delegate to the original painter
    _delegate.paint(canvas, size);

    // Extract and store the bounds in the widget
    onBoundsUpdated(_delegate.getLabelBounds());
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainterWithBounds oldDelegate) {
    return _delegate.shouldRepaint(oldDelegate._delegate);
  }
}

/// Custom painter for temporary connection preview during drag operations
class _TemporaryConnectionPainter extends CustomPainter {
  final Offset sourcePosition;
  final Offset targetPosition;
  final String sourcePortId;
  final ThemeData theme;

  const _TemporaryConnectionPainter({
    required this.sourcePosition,
    required this.targetPosition,
    required this.sourcePortId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Create the bezier path using the same calculation as ConnectionPainter
    final path = painter.ConnectionPainter.createBezierPath(
      sourcePosition,
      targetPosition,
    );

    // Get color for the source port type (similar to ConnectionPainter._getPortColor)
    Color connectionColor = _getPortColor(sourcePortId);

    // Apply semi-transparent styling for preview
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = connectionColor.withValues(alpha: 0.5); // Semi-transparent

    // Draw the connection path
    canvas.drawPath(path, paint);

    // Draw endpoints with semi-transparent styling
    final endpointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = connectionColor.withValues(alpha: 0.7);

    const radius = 4.0;
    canvas.drawCircle(sourcePosition, radius, endpointPaint);
    canvas.drawCircle(targetPosition, radius, endpointPaint);
  }

  /// Get color for a port based on its type (simplified version from ConnectionPainter)
  Color _getPortColor(String portId) {
    // Parse port type from ID (simplified - should use actual port data)
    if (portId.contains('audio')) return theme.appColors.audioPort.color;
    if (portId.contains('cv')) return theme.appColors.cvPort.color;
    if (portId.contains('gate')) return theme.appColors.gatePort.color;
    if (portId.contains('clock') || portId.contains('trigger')) {
      return theme.appColors.clockPort.color;
    }
    return theme.appColors.unknownPort.color;
  }

  @override
  bool shouldRepaint(covariant _TemporaryConnectionPainter oldDelegate) {
    return oldDelegate.sourcePosition != sourcePosition ||
        oldDelegate.targetPosition != targetPosition ||
        oldDelegate.sourcePortId != sourcePortId ||
        oldDelegate.theme != theme;
  }
}
