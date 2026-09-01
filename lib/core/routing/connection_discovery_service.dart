import 'algorithm_routing.dart';
import 'es5_encoder_algorithm_routing.dart';
import 'usb_from_algorithm_routing.dart';
import 'models/port.dart';
import 'models/connection.dart';
import 'bus_session_resolver.dart';
import '../../ui/widgets/routing/bus_label_formatter.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Service for discovering connections between algorithms based on shared bus assignments.
///
/// This service analyzes AlgorithmRouting instances to discover connections
/// based on bus values stored in port metadata. It supports:
/// - Hardware connections (buses 1-12 inputs, 13-20 outputs)
/// - Algorithm-to-algorithm connections (any shared bus)
class ConnectionDiscoveryService {
  /// Discovers all connections from a list of AlgorithmRouting instances.
  ///
  /// Parameters:
  /// - [routings]: List of AlgorithmRouting instances to analyze
  ///
  /// Returns a list of Connection objects representing discovered connections
  static List<Connection> discoverConnections(
    List<AlgorithmRouting> routings, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
  }) {
    final profile =
        deviceIoProfile ??
        (hasExtendedAuxBuses
            ? DeviceIoProfile.distingExtended
            : DeviceIoProfile.distingLegacy);
    final connections = <Connection>[];

    // Build a bus registry mapping bus numbers to ports
    final busRegistry = <int, List<_PortAssignment>>{};

    // Process all algorithms to build the bus registry
    for (int i = 0; i < routings.length; i++) {
      final routing = routings[i];
      final algorithmId = _extractAlgorithmId(routing);

      // Register input ports (bus readers)
      _registerPorts(
        routing.inputPorts,
        algorithmId,
        i,
        PortRole.busReader,
        busRegistry,
        profile,
        allowContextualEs5: routing is UsbFromAlgorithmRouting,
      );

      // Register output ports (bus writers)
      _registerPorts(
        routing.outputPorts,
        algorithmId,
        i,
        PortRole.busWriter,
        busRegistry,
        profile,
        allowContextualEs5: routing is UsbFromAlgorithmRouting,
      );
    }

    // Debug: Print bus registry summary
    _logBusRegistrySummary(busRegistry);

    // Track matched ports to identify unmatched ones for partial connections
    final matchedPorts = <String>{};

    final totalSlots = routings.length;

    // Create connections based on bus assignments, but session-aware
    for (final entry in busRegistry.entries) {
      final busNumber = entry.key;
      final assignments = entry.value;

      // Separate outputs and inputs
      final outputs = assignments.where((a) => a.isOutput).toList();
      final inputs = assignments.where((a) => !a.isOutput).toList();

      // Build session resolver from output writes on this bus
      final builder = BusSessionBuilder();
      for (final o in outputs) {
        builder.addWrite(
          bus: busNumber,
          slot: o.algorithmIndex,
          portId: o.portId,
          mode: o.outputMode,
        );
      }
      final resolver = builder.build(totalSlots: totalSlots);

      final isHardwareInput = profile.isInput(busNumber);
      final isHardwareOutput =
          profile.isOutput(busNumber) ||
          profile.contextualEs5Buses.contains(busNumber);

      // Algorithm-to-algorithm: connect only from contributing writers for each reader slot.
      // Skip when the bus is a physical bus (inputs 1-12 or outputs 13-20) AND there are
      // algorithm outputs — those connections are better represented by the physical path
      // (writer → hw node → reader). ES-5 and AUX buses use direct algo-to-algo.
      final isPhysicalBusWithOutputs =
          outputs.isNotEmpty &&
          (profile.isOutput(busNumber) ||
              (isHardwareInput && outputs.isNotEmpty));
      if (outputs.isNotEmpty &&
          inputs.isNotEmpty &&
          !isPhysicalBusWithOutputs) {
        for (final input in inputs) {
          final contributingPortIds = resolver.contributorsForReader(
            busNumber,
            input.algorithmIndex,
          );

          for (final output in outputs) {
            if (output.algorithmId == input.algorithmId) continue; // no self

            final isForward = output.algorithmIndex < input.algorithmIndex;
            final isContributing = contributingPortIds.contains(output.portId);

            if (isForward && isContributing) {
              // Normal forward connection
              connections.add(
                Connection(
                  id: 'conn_${output.portId}_to_${input.portId}',
                  sourcePortId: output.portId,
                  destinationPortId: input.portId,
                  connectionType: ConnectionType.algorithmToAlgorithm,
                  busNumber: busNumber,
                  algorithmId: output.algorithmId,
                  algorithmIndex: output.algorithmIndex,
                  parameterNumber: output.parameterNumber,
                  signalType: _toSignalType(output.portType),
                  isBackwardEdge: false,
                  isOutput: true,
                  outputMode: output.outputMode,
                ),
              );

              matchedPorts.add(output.portId);
              matchedPorts.add(input.portId);
            } else if (!isForward) {
              // Backward edge: a non-physical shared bus where the writer's
              // slot index is greater than the reader's, between distinct
              // algorithms. Disting NT bus values persist across audio
              // frames, so the reader sees the writer's value one block
              // later regardless of OutputMode (Add vs Replace only changes
              // how the writer combines with the bus contents in the
              // current frame).
              connections.add(
                Connection(
                  id: 'conn_${output.portId}_to_${input.portId}_backward',
                  sourcePortId: output.portId,
                  destinationPortId: input.portId,
                  connectionType: ConnectionType.algorithmToAlgorithm,
                  busNumber: busNumber,
                  algorithmId: output.algorithmId,
                  algorithmIndex: output.algorithmIndex,
                  parameterNumber: output.parameterNumber,
                  signalType: _toSignalType(output.portType),
                  isBackwardEdge: true,
                  isOutput: true,
                  outputMode: output.outputMode,
                ),
              );

              matchedPorts.add(output.portId);
              matchedPorts.add(input.portId);
            }
          }
        }
      }

      // Hardware input (buses 1-12): jack contributes until first replace before reader.
      // When algorithm outputs also write to this bus, algorithm inputs are connected
      // through the hw_in node (physical path), so the hardware seed connection still
      // shows the jack's contribution alongside any algorithm writers.
      if (isHardwareInput && inputs.isNotEmpty) {
        for (final input in inputs) {
          final contributes = resolver.hardwareSeedContributes(
            busNumber,
            input.algorithmIndex,
          );
          if (!contributes && outputs.isEmpty) continue;
          connections.addAll(
            _createHardwareInputConnections(busNumber, [input], profile),
          );
          matchedPorts.add(input.portId);
        }
      }

      // Hardware input (buses 1-12): algorithm outputs writing to input buses.
      // This creates the writer → hw_in_N path (symmetric with output buses).
      if (isHardwareInput && outputs.isNotEmpty) {
        connections.addAll(
          _createHardwareInputWriteConnections(busNumber, outputs, profile),
        );
        for (final o in outputs) {
          matchedPorts.add(o.portId);
        }
      }

      // Physical output buses (13-20) as input sources: algorithm inputs reading from hardware outputs
      if (isHardwareOutput && inputs.isNotEmpty) {
        for (final input in inputs) {
          connections.addAll(
            _createPhysicalOutputAsInputConnections(busNumber, [
              input,
            ], profile),
          );
          matchedPorts.add(input.portId);
        }
      }

      // Hardware output (buses 13-20, ES-5): show all writers as connected.
      // Multiple Replace writers on the same bus can all contribute in practice
      // (e.g., step sequencers that write on different clock cycles).
      if (isHardwareOutput && outputs.isNotEmpty) {
        connections.addAll(
          _createHardwareOutputConnections(busNumber, outputs, profile),
        );
        for (final o in outputs) {
          matchedPorts.add(o.portId);
        }
      }
    }

    // Create ES-5 Encoder mirror connections
    for (final routing in routings) {
      if (routing is ES5EncoderAlgorithmRouting) {
        connections.addAll(_createEs5EncoderConnections(routing));
      }
    }

    // Create ES-5 direct connections for Clock/Euclidean algorithms
    for (final routing in routings) {
      connections.addAll(_createEs5DirectConnections(routing));
    }

    // Create partial connections for unmatched ports with non-zero bus values
    final partialConnections = _createPartialConnections(
      busRegistry,
      matchedPorts,
      profile,
    );
    connections.addAll(partialConnections);

    _logConnectionSummary(connections);

    return connections;
  }

  /// Registers ports in the bus registry based on their bus values
  static void _registerPorts(
    List<Port> ports,
    String algorithmId,
    int algorithmIndex,
    PortRole role,
    Map<int, List<_PortAssignment>> busRegistry,
    DeviceIoProfile profile, {
    required bool allowContextualEs5,
  }) {
    for (final port in ports) {
      if (port.busParam == 'es5_direct' ||
          port.busParam == ES5EncoderAlgorithmRouting.mirrorBusParam) {
        continue;
      }
      final busValue = port.busValue;
      final isAvailable =
          busValue != null &&
          (profile.contains(busValue) ||
              (allowContextualEs5 &&
                  profile.contextualEs5Buses.contains(busValue)));
      if (isAvailable) {
        busRegistry
            .putIfAbsent(busValue, () => [])
            .add(
              _PortAssignment(
                algorithmId: algorithmId,
                algorithmIndex: algorithmIndex,
                portId: port.id,
                portName: port.name,
                parameterName: port.busParam ?? '',
                parameterNumber: port.parameterNumber ?? 0,
                role: role,
                portType: port.type,
                busValue: busValue,
                outputMode: port.outputMode,
              ),
            );
      }
    }
  }

  /// Creates hardware input connections (physical hardware to algorithm inputs)
  static List<Connection> _createHardwareInputConnections(
    int busNumber,
    List<_PortAssignment> inputs,
    DeviceIoProfile profile,
  ) {
    final connections = <Connection>[];
    final hwPortId = 'hw_in_${profile.localNumber(busNumber)}';

    for (final input in inputs) {
      connections.add(
        Connection(
          id: 'conn_${hwPortId}_to_${input.portId}',
          sourcePortId: hwPortId,
          destinationPortId: input.portId,
          connectionType: ConnectionType.hardwareInput,
          busNumber: busNumber,
          algorithmId: input.algorithmId,
          algorithmIndex: input.algorithmIndex,
          parameterNumber: input.parameterNumber,
          signalType: _toSignalType(input.portType),
        ),
      );
    }

    return connections;
  }

  /// Creates connections for algorithm outputs writing to hardware input buses (1-12).
  ///
  /// This is the symmetric counterpart to _createHardwareOutputConnections:
  /// algorithms can write to input buses just as they write to output buses.
  /// The signal path is: algorithm output → hw_in_N.
  static List<Connection> _createHardwareInputWriteConnections(
    int busNumber,
    List<_PortAssignment> outputs,
    DeviceIoProfile profile,
  ) {
    final connections = <Connection>[];
    final hwPortId = 'hw_in_${profile.localNumber(busNumber)}';

    for (final output in outputs) {
      connections.add(
        Connection(
          id: 'conn_${output.portId}_to_$hwPortId',
          sourcePortId: output.portId,
          destinationPortId: hwPortId,
          connectionType: ConnectionType.hardwareOutput,
          busNumber: busNumber,
          algorithmId: output.algorithmId,
          algorithmIndex: output.algorithmIndex,
          parameterNumber: output.parameterNumber,
          signalType: _toSignalType(output.portType),
          isOutput: true,
          outputMode: output.outputMode,
        ),
      );
    }

    return connections;
  }

  /// Creates connections for algorithm inputs reading from physical output buses (13-20)
  ///
  /// This allows algorithms to use physical output buses as input sources.
  /// For example, an algorithm with input on bus 15 (physical output O3) will
  /// create a connection from hw_out_3 to the algorithm input.
  static List<Connection> _createPhysicalOutputAsInputConnections(
    int busNumber,
    List<_PortAssignment> inputs,
    DeviceIoProfile profile,
  ) {
    final connections = <Connection>[];
    final hwPortId = 'hw_out_${profile.localNumber(busNumber)}';

    for (final input in inputs) {
      connections.add(
        Connection(
          id: 'conn_${hwPortId}_to_${input.portId}',
          sourcePortId: hwPortId,
          destinationPortId: input.portId,
          connectionType: ConnectionType.hardwareInput,
          busNumber: busNumber,
          algorithmId: input.algorithmId,
          algorithmIndex: input.algorithmIndex,
          parameterNumber: input.parameterNumber,
          signalType: _toSignalType(input.portType),
        ),
      );
    }

    return connections;
  }

  /// Creates hardware output connections (algorithm outputs to physical hardware)
  static List<Connection> _createHardwareOutputConnections(
    int busNumber,
    List<_PortAssignment> outputs,
    DeviceIoProfile profile,
  ) {
    final connections = <Connection>[];

    if (profile.contextualEs5Buses.contains(busNumber)) {
      final es5LocalNumber = profile.contextualEs5Buses.indexOf(busNumber) + 1;
      final es5PortId = es5LocalNumber == 1 ? 'es5_L' : 'es5_R';

      for (final output in outputs) {
        connections.add(
          Connection(
            id: 'conn_${output.portId}_to_$es5PortId',
            sourcePortId: output.portId,
            destinationPortId: es5PortId,
            connectionType: ConnectionType.hardwareOutput,
            busNumber: busNumber,
            algorithmId: output.algorithmId,
            algorithmIndex: output.algorithmIndex,
            parameterNumber: output.parameterNumber,
            signalType: SignalType.audio, // ES-5 L/R are audio
            isOutput: true,
            outputMode: output.outputMode,
          ),
        );
      }
      return connections;
    }

    final hwPortId = 'hw_out_${profile.localNumber(busNumber)}';

    for (final output in outputs) {
      connections.add(
        Connection(
          id: 'conn_${output.portId}_to_$hwPortId',
          sourcePortId: output.portId,
          destinationPortId: hwPortId,
          connectionType: ConnectionType.hardwareOutput,
          busNumber: busNumber,
          algorithmId: output.algorithmId,
          algorithmIndex: output.algorithmIndex,
          parameterNumber: output.parameterNumber,
          signalType: _toSignalType(output.portType),
          isOutput: true,
          outputMode: output.outputMode,
        ),
      );
    }

    return connections;
  }

  /// Creates ES-5 Encoder mirror connections from output ports to ES-5 hardware ports
  static List<Connection> _createEs5EncoderConnections(
    ES5EncoderAlgorithmRouting routing,
  ) {
    final connections = <Connection>[];

    for (final outputPort in routing.outputPorts) {
      if (outputPort.busParam == ES5EncoderAlgorithmRouting.mirrorBusParam &&
          outputPort.channelNumber != null) {
        final es5PortId = 'es5_${outputPort.channelNumber}';

        connections.add(
          Connection(
            id: 'conn_${outputPort.id}_to_$es5PortId',
            sourcePortId: outputPort.id,
            destinationPortId: es5PortId,
            connectionType: ConnectionType.algorithmToAlgorithm,
            algorithmId:
                routing.algorithmUuid ??
                ES5EncoderAlgorithmRouting.defaultAlgorithmUuid,
            signalType: SignalType.gate,
            description: 'ES-5 Encoder mirror connection',
          ),
        );
      }
    }

    return connections;
  }

  /// Creates ES-5 direct connections for Clock/Euclidean algorithms
  ///
  /// When Clock or Euclidean algorithms have ES-5 Expander active,
  /// their outputs connect directly to ES-5 ports, bypassing normal bus routing.
  static List<Connection> _createEs5DirectConnections(
    AlgorithmRouting routing,
  ) {
    final connections = <Connection>[];

    for (final outputPort in routing.outputPorts) {
      if (outputPort.busParam == 'es5_direct') {
        // Extract ES-5 port number from channelNumber or stereoSide
        int? es5PortNumber = outputPort.channelNumber;

        // For poly CV algorithms, the ES-5 port may be stored in stereoSide as a string
        if (es5PortNumber == null && outputPort.stereoSide != null) {
          es5PortNumber = int.tryParse(outputPort.stereoSide!);
        }

        if (es5PortNumber != null) {
          final es5PortId = 'es5_$es5PortNumber';

          connections.add(
            Connection(
              id: 'conn_${outputPort.id}_to_$es5PortId',
              sourcePortId: outputPort.id,
              destinationPortId: es5PortId,
              connectionType: ConnectionType.algorithmToAlgorithm,
              algorithmId: routing.algorithmUuid!,
              signalType: SignalType.gate,
              description: 'ES-5 direct connection',
            ),
          );
        }
      }
    }

    if (connections.isNotEmpty) {}

    return connections;
  }

  // Removed legacy _createAlgorithmConnections; discovery is now session-aware

  /// Extracts algorithm ID from routing instance
  static String _extractAlgorithmId(AlgorithmRouting routing) {
    // Use the stable algorithmUuid from the routing instance
    if (routing.algorithmUuid != null) {
      return routing.algorithmUuid!;
    }

    // Fallback: Try to extract from port IDs (for backward compatibility)
    if (routing.inputPorts.isNotEmpty) {
      final firstPort = routing.inputPorts.first;
      if (firstPort.id.contains('_param_')) {
        return firstPort.id.split('_param_').first;
      }
    }
    if (routing.outputPorts.isNotEmpty) {
      final firstPort = routing.outputPorts.first;
      if (firstPort.id.contains('_param_')) {
        return firstPort.id.split('_param_').first;
      }
    }

    // Last resort fallback (should rarely be used now)
    return 'algo_${routing.hashCode}';
  }

  /// Converts PortType to SignalType enum
  static SignalType _toSignalType(PortType type) {
    switch (type) {
      case PortType.audio:
        return SignalType.audio;
      case PortType.cv:
        return SignalType.cv;
    }
  }

  /// Logs bus registry summary for debugging
  static void _logBusRegistrySummary(
    Map<int, List<_PortAssignment>> busRegistry,
  ) {
    // Debug logging removed - was used for debugPrint
  }

  /// Logs connection summary for debugging
  static void _logConnectionSummary(List<Connection> connections) {
    // Debug logging removed - was used for debugPrint
  }

  /// Creates partial connections for unmatched ports with non-zero bus values
  static List<Connection> _createPartialConnections(
    Map<int, List<_PortAssignment>> busRegistry,
    Set<String> matchedPorts,
    DeviceIoProfile profile,
  ) {
    final partialConnections = <Connection>[];

    // Process each bus to find unmatched ports
    for (final entry in busRegistry.entries) {
      final busNumber = entry.key;
      final assignments = entry.value;

      // Find unmatched ports (those with non-zero bus values that weren't matched)
      final unmatchedPorts = assignments
          .where((assignment) => !matchedPorts.contains(assignment.portId))
          .toList();

      if (unmatchedPorts.isEmpty) continue;

      // Create partial connections for each unmatched port
      for (final port in unmatchedPorts) {
        // For unmatched OUTPUT ports, include output mode in the label
        // so replace mode shows as "O# R" or "A# R". Inputs ignore mode.
        final String busLabel = port.isOutput
            ? (BusLabelFormatter.formatBusLabelWithMode(
                    busNumber,
                    port.outputMode,
                    deviceIoProfile: profile,
                  ) ??
                  'Bus$busNumber')
            : (BusLabelFormatter.formatBusNumber(
                    busNumber,
                    deviceIoProfile: profile,
                  ) ??
                  'Bus$busNumber');

        final partialConnection = _createPartialConnection(
          port,
          busNumber,
          busLabel,
        );
        partialConnections.add(partialConnection);
      }
    }

    return partialConnections;
  }

  /// Creates a single partial connection for an unmatched port
  static Connection _createPartialConnection(
    _PortAssignment portAssignment,
    int busNumber,
    String busLabel,
  ) {
    // Create unique IDs for the bus endpoint
    final busPortId = 'bus_${busNumber}_endpoint';

    // Determine connection direction based on port type
    final String sourcePortId;
    final String destinationPortId;
    final ConnectionType connectionType;

    if (portAssignment.isOutput) {
      // Output port connects TO bus
      sourcePortId = portAssignment.portId;
      destinationPortId = busPortId;
      connectionType = ConnectionType.partialOutputToBus;
    } else {
      // Input port connects FROM bus
      sourcePortId = busPortId;
      destinationPortId = portAssignment.portId;
      connectionType = ConnectionType.partialBusToInput;
    }

    return Connection(
      id: 'partial_conn_${portAssignment.portId}_bus_$busNumber',
      sourcePortId: sourcePortId,
      destinationPortId: destinationPortId,
      connectionType: connectionType,
      isPartial: true,
      busNumber: busNumber,
      busLabel: busLabel,
      algorithmId: portAssignment.algorithmId,
      algorithmIndex: portAssignment.algorithmIndex,
      parameterNumber: portAssignment.parameterNumber,
      parameterName: portAssignment.parameterName,
      portName: portAssignment.portName,
      signalType: _toSignalType(portAssignment.portType),
      isOutput: portAssignment.isOutput,
    );
  }
}

/// Internal class to track port assignments in the bus registry
class _PortAssignment {
  final String algorithmId;
  final int algorithmIndex;
  final String portId;
  final String portName;
  final String parameterName;
  final int parameterNumber;
  final PortRole role;
  final PortType portType;
  final int busValue;
  final OutputMode? outputMode;

  _PortAssignment({
    required this.algorithmId,
    required this.algorithmIndex,
    required this.portId,
    required this.portName,
    required this.parameterName,
    required this.parameterNumber,
    required this.role,
    required this.portType,
    required this.busValue,
    this.outputMode,
  });

  /// Whether this port writes to the bus (legacy compatibility).
  bool get isOutput => role == PortRole.busWriter;
}
