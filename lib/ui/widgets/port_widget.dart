import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/models/algorithm_port.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

enum PortType { input, output }

typedef PortPanStartCallback = void Function(DragStartDetails details);
typedef PortPanUpdateCallback = void Function(DragUpdateDetails details);
typedef PortPanEndCallback = void Function(DragEndDetails details);

class PortWidget extends StatefulWidget {
  final AlgorithmPort port;
  final PortType type;
  final VoidCallback? onConnectionStart;
  final VoidCallback? onConnectionEnd;
  final PortPanStartCallback? onPanStart;
  final PortPanUpdateCallback? onPanUpdate;
  final PortPanEndCallback? onPanEnd;
  final bool isHovered;
  final bool isConnected;

  const PortWidget({
    super.key,
    required this.port,
    required this.type,
    this.onConnectionStart,
    this.onConnectionEnd,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.isHovered = false,
    this.isConnected = false,
  });

  @override
  State<PortWidget> createState() => _PortWidgetState();
}

class _PortWidgetState extends State<PortWidget> {
  bool _isPressed = false;
  bool _isDragging = false;
  Offset? _dragStartPosition;

  // Dead zone threshold - minimum distance to drag before starting a connection
  // This prevents accidental connection starts when trying to tap on the port
  static const double _dragThreshold = 10.0;

  String _getPortTypeLabel() {
    final portName = widget.port.name.toLowerCase();
    if (portName.contains('audio') || portName.contains('signal')) {
      return 'Audio';
    }
    if (portName.contains('cv') || portName.contains('control')) return 'CV';
    if (portName.contains('gate') || portName.contains('trigger')) {
      return 'Gate';
    }
    if (portName.contains('clock') || portName.contains('sync')) return 'Clock';
    return 'Signal';
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = widget.type == PortType.input ? 'Input' : 'Output';
    final connectionLabel = widget.isConnected ? 'Connected' : 'Not connected';
    final portColors = _getPortTypeColors(context);
    final portColor = _getPortColor(portColors.color);

    return Semantics(
      label:
          '${widget.port.name}, ${_getPortTypeLabel()} $typeLabel, $connectionLabel',
      button: true,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _isPressed = true;
            _dragStartPosition = details.localPosition;
            _isDragging = false;
          });
        },
        onPanUpdate: (details) {
          if (widget.type == PortType.output) {
            // Check if we've moved beyond the threshold
            if (!_isDragging && _dragStartPosition != null) {
              final distance =
                  (details.localPosition - _dragStartPosition!).distance;
              if (distance > _dragThreshold) {
                // Start the connection only after moving beyond threshold
                setState(() {
                  _isDragging = true;
                });
                widget.onConnectionStart?.call();
                // Create a synthetic pan start at the original position
                final syntheticStart = DragStartDetails(
                  localPosition: _dragStartPosition!,
                  globalPosition:
                      details.globalPosition -
                      (details.localPosition - _dragStartPosition!),
                );
                widget.onPanStart?.call(syntheticStart);
              }
            }

            // Continue updating if we're dragging
            if (_isDragging) {
              widget.onPanUpdate?.call(details);
            }
          }
        },
        onPanEnd: (details) {
          setState(() {
            _isPressed = false;
          });

          if (widget.type == PortType.input) {
            widget.onConnectionEnd?.call();
          }

          if (widget.type == PortType.output && _isDragging) {
            // Only trigger pan end if we were actually dragging
            widget.onPanEnd?.call(details);
          }

          setState(() {
            _isDragging = false;
            _dragStartPosition = null;
          });
        },
        onTapDown: (_) {
          setState(() {
            _isPressed = true;
          });
        },
        onTap: () {
          // For now, taps on ports don't do anything
          // Connection creation requires dragging beyond the threshold
          // Connection removal is handled through the connection lines themselves
        },
        onTapUp: (_) {
          setState(() {
            _isPressed = false;
          });
        },
        onTapCancel: () {
          setState(() {
            _isPressed = false;
            _isDragging = false;
            _dragStartPosition = null;
          });
        },
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: portColor,
            border: Border.all(
              color: _getBorderColor(portColors.onColor),
              width: _getBorderWidth(),
            ),
            boxShadow: widget.isHovered || _isPressed
                ? [
                    BoxShadow(
                      color: portColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.isConnected ? 8 : 6,
              height: widget.isConnected ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isConnected
                    ? portColors.onColor
                    : portColors.onColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getPortColor(Color baseColor) {
    if (_isPressed) {
      return baseColor.withValues(alpha: 0.8);
    } else if (widget.isHovered) {
      return baseColor.withValues(alpha: 0.9);
    } else if (widget.isConnected) {
      return baseColor;
    } else {
      return baseColor.withValues(alpha: 0.6);
    }
  }

  AppColorPair _getPortTypeColors(BuildContext context) {
    // Color code by signal type based on port name
    final portName = widget.port.name.toLowerCase();

    if (portName.contains('audio') || portName.contains('signal')) {
      return context.appColors.audioPort;
    } else if (portName.contains('cv') || portName.contains('control')) {
      return context.appColors.cvPort;
    } else if (portName.contains('gate') || portName.contains('trigger')) {
      return context.appColors.gatePort;
    } else if (portName.contains('clock') || portName.contains('sync')) {
      return context.appColors.clockPort;
    } else {
      return context.appColors.unknownPort;
    }
  }

  Color _getBorderColor(Color foregroundColor) {
    if (widget.isHovered || _isPressed) {
      return foregroundColor;
    } else if (widget.isConnected) {
      return foregroundColor.withValues(alpha: 0.8);
    } else {
      return foregroundColor.withValues(alpha: 0.5);
    }
  }

  double _getBorderWidth() {
    if (widget.isHovered || _isPressed) {
      return 2.0;
    } else if (widget.isConnected) {
      return 1.5;
    } else {
      return 1.0;
    }
  }
}
