import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/services/settings_service.dart';

class DraggableResizableOverlay extends StatefulWidget {
  final Widget child;
  final Widget? topBar;
  final OverlayEntry overlayEntry;
  final double initialWidth;
  final double initialHeight;
  final double minWidth;
  final double maxWidth;
  final double aspectRatio; // width / height
  final double topBarHeight;
  final Duration controlsHideDelay;
  final Widget? bottomContent;
  final double bottomContentHeight;
  final bool reserveTopBarSpace;
  final bool keepControlsVisible;

  const DraggableResizableOverlay({
    super.key,
    required this.child,
    this.topBar,
    required this.overlayEntry,
    this.initialWidth = 256.0,
    this.initialHeight = 64.0,
    this.minWidth = 128.0, // 0.5x scale (256 * 0.5)
    this.maxWidth = 1024.0, // 4x scale (256 * 4)
    this.aspectRatio = 4.0, // 4:1 aspect ratio for Disting NT display
    this.topBarHeight = 36.0,
    this.controlsHideDelay = const Duration(seconds: 10),
    this.bottomContent,
    this.bottomContentHeight = 0,
    this.reserveTopBarSpace = false,
    this.keepControlsVisible = false,
  });

  @override
  State<DraggableResizableOverlay> createState() =>
      _DraggableResizableOverlayState();
}

class _DraggableResizableOverlayState extends State<DraggableResizableOverlay> {
  late double _width;
  late double _height;
  late double _x;
  late double _y;
  bool _isDragging = false;
  bool _isResizing = false;
  bool _isHovering = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  final SettingsService _settings = SettingsService();

  @override
  void initState() {
    super.initState();
    // Initialize with default values
    _width = widget.initialWidth;
    _height = widget.initialHeight;
    _x = 0;
    _y = 0;

    // Load settings after the first frame to ensure MediaQuery is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });

    // Start the hide timer
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer({Duration? delay}) {
    if (_settings.videoToolbarAlwaysVisible || _isHovering) return;
    _hideTimer?.cancel();
    _hideTimer = Timer(delay ?? widget.controlsHideDelay, () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _showControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startHideTimer();
  }

  void _loadSettings() {
    // Load saved position and size from settings
    final savedX = _settings.overlayPositionX;
    final savedY = _settings.overlayPositionY;
    final savedScale = _settings.overlaySizeScale;

    // Calculate size from scale
    _width = widget.initialWidth * savedScale;
    _height = _width / widget.aspectRatio; // Maintain aspect ratio

    // Use saved position if available, otherwise use default
    if (savedX >= 0 && savedY >= 0) {
      _x = savedX;
      _y = savedY;
    } else {
      // Default positioning (bottom-right)
      final screenSize = MediaQuery.of(context).size;
      _x = screenSize.width - _width - 16;
      _y = screenSize.height - kBottomNavigationBarHeight - _totalHeight - 16;
    }

    // Ensure overlay stays within screen bounds
    setState(() {
      _constrainToScreen();
    });
  }

  double get _reservedBarHeight =>
      widget.reserveTopBarSpace && widget.topBar != null
      ? widget.topBarHeight
      : 0;
  double get _bottomHeight => math.min(
    widget.bottomContent == null ? 0 : widget.bottomContentHeight,
    math.max(
      0,
      MediaQuery.sizeOf(context).height - _height - _reservedBarHeight,
    ),
  );
  double get _totalHeight => _height + _reservedBarHeight + _bottomHeight;

  void _constrainToScreen() {
    final screenSize = MediaQuery.of(context).size;
    _width = _width.clamp(
      math.min(widget.minWidth, screenSize.width),
      math.min(widget.maxWidth, screenSize.width),
    );
    _height = _width / widget.aspectRatio;
    _x = _x.clamp(0, math.max(0, screenSize.width - _width));
    _y = _y.clamp(0, math.max(0, screenSize.height - _totalHeight));
  }

  @override
  void didUpdateWidget(covariant DraggableResizableOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _constrainToScreen();
  }

  void _saveSettings() {
    final scale = _width / widget.initialWidth;
    _settings.setOverlayPositionX(_x);
    _settings.setOverlayPositionY(_y);
    _settings.setOverlaySizeScale(scale);
  }

  void _onPanStart(DragStartDetails details) {
    _showControls();
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _x += details.delta.dx;
      _y += details.delta.dy;
      _constrainToScreen();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });
    _saveSettings();
  }

  void _onResizeStart(DragStartDetails details) {
    _showControls();
    setState(() {
      _isResizing = true;
    });
  }

  void _onResizeUpdate(DragUpdateDetails details) {
    setState(() {
      // Calculate new width based on drag delta
      final newWidth = (_width + details.delta.dx).clamp(
        widget.minWidth,
        widget.maxWidth,
      );
      _width = newWidth;
      _height = _width / widget.aspectRatio; // Maintain aspect ratio

      // Ensure overlay stays within screen bounds after resize
      _constrainToScreen();
    });
  }

  void _onResizeEnd(DragEndDetails details) {
    setState(() {
      _isResizing = false;
    });
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _settings.videoToolbarAlwaysVisibleNotifier,
      builder: (context, alwaysShowToolbar, _) {
        final isAccessible = MediaQuery.of(context).accessibleNavigation;
        final showControls =
            alwaysShowToolbar ||
            widget.keepControlsVisible ||
            _controlsVisible ||
            _isResizing ||
            _isDragging ||
            isAccessible;

        final hasTopBar = widget.topBar != null;
        final barHeight = hasTopBar ? widget.topBarHeight : 0.0;

        _constrainToScreen();
        return Positioned(
          left: _x,
          top: _y,
          child: MouseRegion(
            onEnter: (_) {
              _isHovering = true;
              _showControls();
            },
            onExit: (_) {
              _isHovering = false;
              _startHideTimer(delay: const Duration(milliseconds: 350));
            },
            child: SizedBox(
              width: _width,
              height: _totalHeight,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Main content
                  Positioned(
                    top: _reservedBarHeight,
                    left: 0,
                    right: 0,
                    height: _height,
                    child: GestureDetector(
                      onTap: _showControls,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: _isDragging ? 0.3 : 0.2,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Opacity(
                            opacity: _isDragging ? 0.8 : 1.0,
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (widget.bottomContent != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _bottomHeight,
                      child: widget.bottomContent!,
                    ),

                  // Top action bar with integrated close button
                  if (hasTopBar)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: barHeight,
                      child: IgnorePointer(
                        ignoring: !showControls,
                        child: ClipRect(
                          child: AnimatedSlide(
                            offset: showControls
                                ? Offset.zero
                                : const Offset(0, -1),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: Row(
                              children: [
                                Expanded(child: widget.topBar!),
                                Container(
                                  width: barHeight,
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(6),
                                    ),
                                  ),
                                  child: IconButton(
                                    tooltip: 'Close overlay',
                                    onPressed: () =>
                                        widget.overlayEntry.remove(),
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Close button (top-right corner) -- only when no top bar
                  if (!hasTopBar)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IgnorePointer(
                        ignoring: !showControls,
                        child: AnimatedOpacity(
                          opacity: showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          child: Semantics(
                            label: 'Close overlay',
                            button: true,
                            child: GestureDetector(
                              onTap: () {
                                widget.overlayEntry.remove();
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Resize handle (bottom-right corner)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !showControls,
                      child: AnimatedOpacity(
                        opacity: showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: Semantics(
                          label: 'Resize overlay',
                          child: GestureDetector(
                            onPanStart: _onResizeStart,
                            onPanUpdate: _onResizeUpdate,
                            onPanEnd: _onResizeEnd,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(4),
                                  bottomRight: Radius.circular(6),
                                ),
                              ),
                              child: const Icon(
                                Icons.open_in_full,
                                size: 14,
                                color: Colors.white,
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
        );
      },
    );
  }
}
