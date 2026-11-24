import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/routing/movable_physical_io_node.dart';

/// Widget representing the ES-5 Expander hardware node.
///
/// The ES-5 is an Expert Sleepers Eurorack expander that receives signals
/// from the Disting NT and outputs them to CV/gate jacks in the modular system.
///
/// From the algorithm perspective, these ES-5 ports act as inputs
/// (they receive signals from algorithms), so they use input port positioning.
class ES5Node extends StatelessWidget {
  static const title = 'ES-5';

  /// The list of ports from the routing state to display in this node.
  final List<Port> ports;

  /// Callback when a port is tapped.
  final Function(Port)? onPortTapped;

  /// Callback when a port is long-pressed (for connection deletion).
  final Function(Port)? onPortLongPress;

  /// Callback when long press starts on a port (for animated deletion).
  final Function(Port)? onPortLongPressStart;

  /// Callback when long press is cancelled on a port.
  final VoidCallback? onPortLongPressCancel;

  /// Callback when drag starts from a port.
  final Function(Port)? onDragStart;

  /// Callback when drag updates with new position.
  final Function(Port, Offset)? onDragUpdate;

  /// Callback when drag ends at a position.
  final Function(Port, Offset)? onDragEnd;

  /// The position of this node in the canvas.
  final Offset position;

  /// Callback when the node position changes due to dragging.
  final Function(Offset)? onPositionChanged;

  /// Custom jack spacing (defaults to optimal spacing).
  final double? jackSpacing;

  /// Whether to show port labels.
  final bool showLabels;

  /// Callback to report each jack's global center for connection anchoring
  final void Function(Port port, Offset globalCenter)? onPortPositionResolved;

  /// Callback when node drag starts.
  final VoidCallback? onNodeDragStart;

  /// Callback when node drag ends.
  final VoidCallback? onNodeDragEnd;

  /// Callback for routing actions from ports
  final void Function(String portId, String action)? onRoutingAction;

  /// Set of connected port IDs
  final Set<String>? connectedPorts;

  /// ID of the port that should be highlighted (during drag operations)
  final String? highlightedPortId;

  /// Callback when the node's size is resolved.
  final ValueChanged<Size>? onSizeResolved;

  const ES5Node({
    super.key,
    required this.ports,
    this.connectedPorts,
    this.onPortTapped,
    this.onPortLongPress,
    this.onPortLongPressStart,
    this.onPortLongPressCancel,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.position = Offset.zero,
    this.onPositionChanged,
    this.jackSpacing,
    this.showLabels = true,
    this.onPortPositionResolved,
    this.onNodeDragStart,
    this.onNodeDragEnd,
    this.onRoutingAction,
    this.highlightedPortId,
    this.onSizeResolved,
  });

  @override
  Widget build(BuildContext context) {
    final connectedCount =
        connectedPorts?.where((id) => ports.any((p) => p.id == id)).length ?? 0;
    return Semantics(
      label: 'ES-5 Expander: ${ports.length} jacks, $connectedCount connected',
      hint: 'ES-5 Eurorack expander jacks. Receives signals from algorithms and outputs to hardware.',
      container: true,
      child: MovablePhysicalIONode(
        ports: ports,
        connectedPorts: connectedPorts,
        title: title,
        icon: Icons.memory,
        position: position,
        isInput: false, // From algorithm perspective, these are inputs
        onPositionChanged: onPositionChanged,
        onPortTapped: onPortTapped,
        onPortLongPress: onPortLongPress,
        onPortLongPressStart: onPortLongPressStart,
        onPortLongPressCancel: onPortLongPressCancel,
        onPortDragStart: onDragStart,
        onPortDragUpdate: onDragUpdate,
        onPortDragEnd: onDragEnd,
        onPortPositionResolved: onPortPositionResolved,
        onNodeDragStart: onNodeDragStart,
        onNodeDragEnd: onNodeDragEnd,
        onRoutingAction: onRoutingAction,
        highlightedPortId: highlightedPortId,
        onSizeResolved: onSizeResolved,
      ),
    );
  }
}
