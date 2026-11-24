import 'package:nt_helper/core/routing/models/port.dart';

/// Validates connections between ports in the routing system.
///
/// Uses the bus-assignment model: ports have roles (busReader, busWriter,
/// physicalBus, es5Bus) and validation is symmetric — the order of
/// arguments does not matter.
class ConnectionValidator {
  /// Validates whether a connection between two ports is allowed.
  ///
  /// This method is symmetric: `isValidConnection(a, b)` returns the same
  /// result as `isValidConnection(b, a)`.
  ///
  /// Valid connections require:
  /// - At least one port must be an algorithm port (busReader or busWriter)
  /// - The two ports must not belong to the same node
  /// - Two bus ports (physical/ES-5) cannot connect directly
  /// - Two busReaders or two busWriters cannot connect directly
  static bool isValidConnection(Port portA, Port portB) {
    if (portA.effectiveRole == PortRole.expanderOutputBus ||
        portB.effectiveRole == PortRole.expanderOutputBus) {
      return false;
    }
    // Prevent same-node connections
    if (_isSameNode(portA, portB)) return false;

    final roleA = portA.effectiveRole;
    final roleB = portB.effectiveRole;

    // Two bus ports cannot connect directly
    if (portA.isBus && portB.isBus) return false;

    // Two readers cannot connect
    if (roleA == PortRole.busReader && roleB == PortRole.busReader) {
      return false;
    }

    // Two writers cannot connect
    if (roleA == PortRole.busWriter && roleB == PortRole.busWriter) {
      return false;
    }

    // At least one must be an algorithm port
    if (portA.isBus && portB.isBus) return false;

    // Valid: busReader + busWriter (algorithm to algorithm)
    // Valid: busReader + physicalBus/es5Bus
    // Valid: busWriter + physicalBus/es5Bus
    return true;
  }

  /// Returns a human-readable error message for invalid connection attempts.
  static String getValidationError(Port portA, Port portB) {
    if (portA.isBus && portB.isBus) {
      return 'Direct physical-to-physical connections are not supported. '
          'Signals must be routed through algorithms.';
    }

    if (_isSameNode(portA, portB)) {
      return 'Cannot connect a node to itself.';
    }

    final roleA = portA.effectiveRole;
    final roleB = portB.effectiveRole;

    if (roleA == PortRole.busReader && roleB == PortRole.busReader) {
      return 'Cannot connect two inputs directly.';
    }

    if (roleA == PortRole.busWriter && roleB == PortRole.busWriter) {
      return 'Cannot connect two outputs directly.';
    }

    return 'These ports cannot be connected.';
  }

  /// Determines if a connection represents a ghost connection
  /// (algorithm writer assigned to a physical input bus 1-12).
  static bool isGhostConnection(Port portA, Port portB) {
    return (_isWriterToPhysicalInput(portA, portB) ||
        _isWriterToPhysicalInput(portB, portA));
  }

  static bool _isWriterToPhysicalInput(Port writer, Port bus) {
    if (writer.effectiveRole != PortRole.busWriter) return false;
    return bus.isPhysicalInput;
  }

  /// Given two valid ports, determines which is the "writer" (source) and
  /// which is the "reader" (target) for connection creation.
  ///
  /// Returns (sourcePortId, targetPortId) or null if the connection is invalid.
  static (String source, String target)? resolveConnectionDirection(
    Port portA,
    Port portB,
  ) {
    if (!isValidConnection(portA, portB)) return null;

    final roleA = portA.effectiveRole;
    final roleB = portB.effectiveRole;

    // busWriter is always the source
    if (roleA == PortRole.busWriter) return (portA.id, portB.id);
    if (roleB == PortRole.busWriter) return (portB.id, portA.id);

    // Physical bus connected to busReader: physical bus is the source
    if (portA.isBus && roleB == PortRole.busReader) {
      return (portA.id, portB.id);
    }
    if (portB.isBus && roleA == PortRole.busReader) {
      return (portB.id, portA.id);
    }

    // Fallback (shouldn't reach here for valid connections)
    return (portA.id, portB.id);
  }

  /// Checks if two ports belong to the same node.
  static bool _isSameNode(Port portA, Port portB) {
    final nodeA = _extractNodeId(portA.id);
    final nodeB = _extractNodeId(portB.id);
    if (nodeA == null || nodeB == null) return false;
    return nodeA == nodeB;
  }

  /// Extracts the node ID from a port ID.
  static String? _extractNodeId(String portId) {
    if (portId.startsWith('hw_in')) return 'hw_inputs';
    if (portId.startsWith('hw_out')) return 'hw_outputs';
    if (portId.startsWith('es5_')) return 'es5';

    final parts = portId.split('_');
    if (parts.length >= 3) {
      return '${parts[0]}_${parts[1]}';
    }

    return null;
  }
}
