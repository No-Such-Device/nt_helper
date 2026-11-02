import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/services/connection_validator.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/core/routing/models/port.dart';

void main() {
  group('ConnectionValidator State Management Integration Tests', () {
    group('Dynamic Connection Validation', () {
      test('should re-validate connections when algorithm order changes', () {
        // Create test algorithms representing different ordering scenarios
        final algorithmsBeforeReorder = [
          RoutingAlgorithm(
            id: 'alg_1',
            index: 0, // Slot 0
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Source Algorithm',
            ),
            inputPorts: [
              Port(
                id: 'alg_1_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_1_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_2',
            index: 1, // Slot 1
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Destination Algorithm',
            ),
            inputPorts: [
              Port(
                id: 'alg_2_input_1',
                name: 'Input 1',
                type: PortType.audio,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_2_output_1',
                name: 'Output 1',
                type: PortType.audio,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        // After reordering (user clicks "up" button on algorithm 2)
        final algorithmsAfterReorder = [
          RoutingAlgorithm(
            id: 'alg_2',
            index: 0, // Moved to slot 0
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Destination Algorithm',
            ),
            inputPorts: [
              Port(
                id: 'alg_2_input_1',
                name: 'Input 1',
                type: PortType.audio,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_2_output_1',
                name: 'Output 1',
                type: PortType.audio,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_1',
            index: 1, // Moved to slot 1
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Source Algorithm',
            ),
            inputPorts: [
              Port(
                id: 'alg_1_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_1_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        // Connection from alg_2 to alg_1 (same connection, different context)
        final connection = Connection(
          id: 'test_connection',
          sourcePortId: 'alg_2_output_1',
          destinationPortId: 'alg_1_input_1',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        // Before reordering: slot 1 -> slot 0 (INVALID)
        final beforeValidated = ConnectionValidator.validateConnections([
          connection,
        ], algorithmsBeforeReorder);

        expect(beforeValidated.length, equals(1));
        expect(beforeValidated.first.isBackwardEdge, isTrue);
        expect(beforeValidated.first.id, equals('test_connection'));

        // After reordering: slot 0 -> slot 1 (VALID)
        final afterValidated = ConnectionValidator.validateConnections([
          connection,
        ], algorithmsAfterReorder);

        expect(afterValidated.length, equals(1));
        expect(afterValidated.first.isBackwardEdge, isFalse);
        expect(afterValidated.first.id, equals('test_connection'));
      }, tags: ['regression']);

      test('should preserve connection data during validation updates', () {
        final algorithms = [
          RoutingAlgorithm(
            id: 'alg_1',
            index: 0,
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Algorithm 1',
            ),
            inputPorts: [
              Port(
                id: 'alg_1_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_1_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_2',
            index: 1,
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Algorithm 2',
            ),
            inputPorts: [
              Port(
                id: 'alg_2_input_1',
                name: 'Input 1',
                type: PortType.audio,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_2_output_1',
                name: 'Output 1',
                type: PortType.audio,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        // Connection with various properties
        final originalConnection = Connection(
          id: 'complex_connection',
          sourcePortId: 'alg_2_output_1',
          destinationPortId: 'alg_1_input_1',
          connectionType: ConnectionType.algorithmToAlgorithm,
          status: ConnectionStatus.active,
          name: 'Test Connection',
          description: 'A test connection with properties',
          gain: 0.8,
          isMuted: false,
          isInverted: true,
          delayMs: 5.0,
          busNumber: 7,
          busLabel: 'Bus 7',
        );

        final validatedConnections = ConnectionValidator.validateConnections([
          originalConnection,
        ], algorithms);

        expect(validatedConnections.length, equals(1));
        final validated = validatedConnections.first;

        // Validation flag should be set
        expect(validated.isBackwardEdge, isTrue);

        // All other properties should be preserved
        expect(validated.id, equals(originalConnection.id));
        expect(validated.sourcePortId, equals(originalConnection.sourcePortId));
        expect(
          validated.destinationPortId,
          equals(originalConnection.destinationPortId),
        );
        expect(
          validated.connectionType,
          equals(originalConnection.connectionType),
        );
        expect(validated.status, equals(originalConnection.status));
        expect(validated.name, equals(originalConnection.name));
        expect(validated.description, equals(originalConnection.description));
        expect(validated.gain, equals(originalConnection.gain));
        expect(validated.isMuted, equals(originalConnection.isMuted));
        expect(validated.isInverted, equals(originalConnection.isInverted));
        expect(validated.delayMs, equals(originalConnection.delayMs));
        expect(validated.busNumber, equals(originalConnection.busNumber));
        expect(validated.busLabel, equals(originalConnection.busLabel));
      });

      test('should handle multiple connections with mixed validity', () {
        final algorithms = [
          RoutingAlgorithm(
            id: 'alg_1',
            index: 0,
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Algorithm 1',
            ),
            inputPorts: [
              Port(
                id: 'alg_1_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_1_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_2',
            index: 1,
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Algorithm 2',
            ),
            inputPorts: [
              Port(
                id: 'alg_2_input_1',
                name: 'Input 1',
                type: PortType.audio,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_2_output_1',
                name: 'Output 1',
                type: PortType.audio,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_3',
            index: 2,
            algorithm: Algorithm(
              algorithmIndex: 2,
              guid: 'test-guid-3',
              name: 'Algorithm 3',
            ),
            inputPorts: [
              Port(
                id: 'alg_3_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_3_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        final connections = [
          // Valid: slot 0 -> slot 1
          Connection(
            id: 'valid_0_to_1',
            sourcePortId: 'alg_1_output_1',
            destinationPortId: 'alg_2_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
          // Valid: slot 1 -> slot 2
          Connection(
            id: 'valid_1_to_2',
            sourcePortId: 'alg_2_output_1',
            destinationPortId: 'alg_3_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
          // Invalid: slot 2 -> slot 0
          Connection(
            id: 'invalid_2_to_0',
            sourcePortId: 'alg_3_output_1',
            destinationPortId: 'alg_1_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
          // Invalid: slot 2 -> slot 1
          Connection(
            id: 'invalid_2_to_1',
            sourcePortId: 'alg_3_output_1',
            destinationPortId: 'alg_2_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
          // Physical connection (always valid)
          Connection(
            id: 'physical_input',
            sourcePortId: 'hw_in_1',
            destinationPortId: 'alg_1_input_1',
            connectionType: ConnectionType.hardwareInput,
          ),
        ];

        final validatedConnections = ConnectionValidator.validateConnections(
          connections,
          algorithms,
        );

        expect(validatedConnections.length, equals(5));

        // Check each connection's validation status
        final validConnection1 = validatedConnections.firstWhere(
          (c) => c.id == 'valid_0_to_1',
        );
        final validConnection2 = validatedConnections.firstWhere(
          (c) => c.id == 'valid_1_to_2',
        );
        final invalidConnection1 = validatedConnections.firstWhere(
          (c) => c.id == 'invalid_2_to_0',
        );
        final invalidConnection2 = validatedConnections.firstWhere(
          (c) => c.id == 'invalid_2_to_1',
        );
        final physicalConnection = validatedConnections.firstWhere(
          (c) => c.id == 'physical_input',
        );

        expect(validConnection1.isBackwardEdge, isFalse);
        expect(validConnection2.isBackwardEdge, isFalse);
        expect(invalidConnection1.isBackwardEdge, isTrue);
        expect(invalidConnection2.isBackwardEdge, isTrue);
        expect(physicalConnection.isBackwardEdge, isFalse);
      });
    });

    group('Algorithm Reordering Scenarios', () {
      test('should validate complex reordering with multiple connections', () {
        // Initial configuration: A(0) -> B(1) -> C(2) (all valid)
        final initialAlgorithms = [
          RoutingAlgorithm(
            id: 'alg_A',
            index: 0,
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-A',
              name: 'Algorithm A',
            ),
            inputPorts: [
              Port(
                id: 'alg_A_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_A_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_B',
            index: 1,
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-B',
              name: 'Algorithm B',
            ),
            inputPorts: [
              Port(
                id: 'alg_B_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_B_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_C',
            index: 2,
            algorithm: Algorithm(
              algorithmIndex: 2,
              guid: 'test-guid-C',
              name: 'Algorithm C',
            ),
            inputPorts: [
              Port(
                id: 'alg_C_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_C_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        // After reordering: C(0) -> A(1) -> B(2) (C moved to top)
        final reorderedAlgorithms = [
          RoutingAlgorithm(
            id: 'alg_C',
            index: 0, // Moved to slot 0
            algorithm: Algorithm(
              algorithmIndex: 2,
              guid: 'test-guid-C',
              name: 'Algorithm C',
            ),
            inputPorts: [
              Port(
                id: 'alg_C_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_C_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_A',
            index: 1, // Moved to slot 1
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-A',
              name: 'Algorithm A',
            ),
            inputPorts: [
              Port(
                id: 'alg_A_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_A_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
          RoutingAlgorithm(
            id: 'alg_B',
            index: 2, // Moved to slot 2
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-B',
              name: 'Algorithm B',
            ),
            inputPorts: [
              Port(
                id: 'alg_B_input_1',
                name: 'Input 1',
                type: PortType.cv,
                direction: PortDirection.input,
              ),
            ],
            outputPorts: [
              Port(
                id: 'alg_B_output_1',
                name: 'Output 1',
                type: PortType.cv,
                direction: PortDirection.output,
              ),
            ],
          ),
        ];

        final connections = [
          // A -> B connection
          Connection(
            id: 'A_to_B',
            sourcePortId: 'alg_A_output_1',
            destinationPortId: 'alg_B_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
          // B -> C connection
          Connection(
            id: 'B_to_C',
            sourcePortId: 'alg_B_output_1',
            destinationPortId: 'alg_C_input_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          ),
        ];

        // Initially: A(0) -> B(1) = VALID, B(1) -> C(2) = VALID
        final initialValidated = ConnectionValidator.validateConnections(
          connections,
          initialAlgorithms,
        );

        final initialAtoB = initialValidated.firstWhere(
          (c) => c.id == 'A_to_B',
        );
        final initialBtoC = initialValidated.firstWhere(
          (c) => c.id == 'B_to_C',
        );

        expect(initialAtoB.isBackwardEdge, isFalse); // A(0) -> B(1) = valid
        expect(initialBtoC.isBackwardEdge, isFalse); // B(1) -> C(2) = valid

        // After reordering: A(1) -> B(2) = VALID, B(2) -> C(0) = INVALID
        final reorderedValidated = ConnectionValidator.validateConnections(
          connections,
          reorderedAlgorithms,
        );

        final reorderedAtoB = reorderedValidated.firstWhere(
          (c) => c.id == 'A_to_B',
        );
        final reorderedBtoC = reorderedValidated.firstWhere(
          (c) => c.id == 'B_to_C',
        );

        expect(reorderedAtoB.isBackwardEdge, isFalse); // A(1) -> B(2) = valid
        expect(reorderedBtoC.isBackwardEdge, isTrue); // B(2) -> C(0) = invalid
      });
    });
  });
}
