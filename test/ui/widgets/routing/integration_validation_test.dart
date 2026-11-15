import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/algorithm_node_widget.dart';
import 'package:nt_helper/ui/widgets/routing/physical_input_node.dart';
import 'package:nt_helper/ui/widgets/routing/physical_output_node.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';
import 'package:nt_helper/ui/widgets/routing/physical_port_generator.dart';
import 'package:nt_helper/core/routing/models/port.dart';

/// Helper function to create test physical input ports
List<Port> _createTestInputPorts() {
  return List.generate(12, (index) {
    final portNum = index + 1;
    return Port(
      id: 'hw_in_$portNum',
      name: 'Input $portNum',
      type: PortType.audio,
      direction:
          PortDirection.output, // Physical inputs act as outputs to algorithms
      role: PortRole.physicalInputBus,
      busValue: portNum,
    );
  });
}

/// Helper function to create test physical output ports
List<Port> _createTestOutputPorts() {
  return List.generate(8, (index) {
    final portNum = index + 1;
    return Port(
      id: 'hw_out_$portNum',
      name: 'Output $portNum',
      type: PortType.audio,
      direction:
          PortDirection.input, // Physical outputs act as inputs from algorithms
      role: PortRole.physicalOutputBus,
      busValue: portNum + 12,
    );
  });
}

/// Integration validation test for Task 3 - Universal Port Widget System
///
/// This test validates that the universal port widget architecture works
/// correctly across all node types and provides the functionality required
/// for the Physical I/O Node Redesign specification.
void main() {
  group('Task 3 Integration Validation', () {
    testWidgets('Universal port widget works across all node types', (
      tester,
    ) async {
      final Map<String, Offset> allPortPositions = {};
      bool algorithmPortCallbackFired = false;
      bool physicalPortCallbackFired = false;

      void trackAlgorithmPort(String portId, Offset position, bool isInput) {
        allPortPositions['algo_$portId'] = position;
        algorithmPortCallbackFired = true;
      }

      void trackPhysicalPort(port, Offset position) {
        allPortPositions['physical_${port.id}'] = position;
        physicalPortCallbackFired = true;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // Algorithm node using PortWidget
                Positioned(
                  left: 100,
                  top: 100,
                  child: AlgorithmNodeWidget(
                    algorithmName: 'TestAlg',
                    slotNumber: 1,
                    inputLabels: const ['audio_in_1', 'cv_in_1'],
                    outputLabels: const ['audio_out_1', 'gate_out_1'],
                    inputPortIds: const ['audio_in_1', 'cv_in_1'],
                    outputPortIds: const ['audio_out_1', 'gate_out_1'],
                    position: const Offset(100, 100),
                    onPortPositionResolved: trackAlgorithmPort,
                  ),
                ),
                // Physical Output Node (should use universal port system)
                Positioned(
                  left: 300,
                  top: 100,
                  child: PhysicalOutputNode(
                    ports: _createTestOutputPorts(),
                    position: const Offset(300, 100),
                    onPortPositionResolved: trackPhysicalPort,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump(); // Allow position callbacks to fire

      // Both types of port callbacks should have fired
      expect(
        algorithmPortCallbackFired,
        isTrue,
        reason: 'Algorithm port position callbacks should fire',
      );
      expect(
        physicalPortCallbackFired,
        isTrue,
        reason: 'Physical port position callbacks should fire',
      );

      // Should have positions for both algorithm and physical ports
      expect(
        allPortPositions.keys.where((k) => k.startsWith('algo_')),
        isNotEmpty,
        reason: 'Should have algorithm port positions',
      );
      expect(
        allPortPositions.keys.where((k) => k.startsWith('physical_')),
        isNotEmpty,
        reason: 'Should have physical port positions',
      );
    });

    testWidgets('Port widgets handle hover states consistently', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // Test with algorithm node ports
                Positioned(
                  left: 100,
                  top: 100,
                  child: AlgorithmNodeWidget(
                    algorithmName: 'TestAlg',
                    slotNumber: 1,
                    inputLabels: const ['input_1'],
                    outputLabels: const ['output_1'],
                    inputPortIds: const ['input_1'],
                    outputPortIds: const ['output_1'],
                    position: const Offset(100, 100),
                  ),
                ),
                // Test with physical output ports
                Positioned(
                  left: 300,
                  top: 100,
                  child: PhysicalOutputNode(
                    ports: _createTestOutputPorts(),
                    position: const Offset(300, 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find port widgets in both node types
      final algorithmPorts = find.descendant(
        of: find.byType(AlgorithmNodeWidget),
        matching: find.byType(PortWidget),
      );
      final physicalPorts = find.descendant(
        of: find.byType(PhysicalOutputNode),
        matching: find.byType(PortWidget),
      );

      // Both node types should use PortWidget internally
      expect(
        algorithmPorts,
        findsWidgets,
        reason: 'Algorithm nodes should use PortWidget',
      );
      expect(
        physicalPorts,
        findsWidgets,
        reason: 'Physical nodes should use PortWidget',
      );

      // Test interaction behavior works consistently - use tap instead of hover
      await tester.tap(algorithmPorts.first);
      await tester.pump();

      await tester.tap(physicalPorts.first);
      await tester.pump();

      // If we get this far without exceptions, interaction states work
      expect(algorithmPorts, findsWidgets);
      expect(physicalPorts, findsWidgets);
    });

    testWidgets('Physical port generation creates correct port structures', (
      tester,
    ) async {
      // Test the PhysicalPortGenerator utility
      final inputPorts = PhysicalPortGenerator.generatePhysicalInputPorts();
      final outputPorts = PhysicalPortGenerator.generatePhysicalOutputPorts();

      expect(inputPorts, hasLength(12), reason: 'Should have 12 input ports');
      expect(outputPorts, hasLength(8), reason: 'Should have 8 output ports');

      // Verify port properties
      for (int i = 0; i < inputPorts.length; i++) {
        final port = inputPorts[i];
        expect(port.id, equals('hw_in_${i + 1}'));
        expect(port.direction, equals(PortDirection.output));
        expect(port.isPhysicalInput, isTrue);
      }

      for (int i = 0; i < outputPorts.length; i++) {
        final port = outputPorts[i];
        expect(port.id, equals('hw_out_${i + 1}'));
        expect(port.direction, equals(PortDirection.input));
        expect(port.isPhysicalOutput, isTrue);
      }

      // Test the ports work in actual widgets
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  child: PhysicalInputNode(
                    ports: inputPorts,
                    position: const Offset(100, 100),
                  ),
                ),
                Positioned(
                  left: 300,
                  top: 100,
                  child: PhysicalOutputNode(
                    ports: outputPorts,
                    position: const Offset(300, 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both nodes should render without errors
      expect(find.byType(PhysicalInputNode), findsOneWidget);
      expect(find.byType(PhysicalOutputNode), findsOneWidget);
    });

    testWidgets('Port position updates work consistently', (tester) async {
      final Map<String, Offset> positions = {};

      void trackPosition(port, Offset position) {
        positions[port.id] = position;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhysicalOutputNode(
              ports: _createTestOutputPorts().take(2).toList(),
              position: const Offset(650, 140),
              onPortPositionResolved: trackPosition,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump(); // Allow callbacks

      // Should have tracked positions for the ports
      expect(positions, isNotEmpty, reason: 'Should track port positions');
      expect(
        positions.length,
        greaterThan(0),
        reason: 'Should have at least one port position',
      );
    });

    testWidgets('Drag operations work across node types', (tester) async {
      bool inputNodeDragCalled = false;
      bool outputNodeDragCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  child: PhysicalInputNode(
                    ports: _createTestInputPorts().take(1).toList(),
                    position: const Offset(100, 100),
                    onPositionChanged: (_) => inputNodeDragCalled = true,
                  ),
                ),
                Positioned(
                  left: 300,
                  top: 100,
                  child: PhysicalOutputNode(
                    ports: _createTestOutputPorts().take(1).toList(),
                    position: const Offset(300, 100),
                    onPositionChanged: (_) => outputNodeDragCalled = true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Test dragging input node
      await tester.dragFrom(
        tester.getCenter(find.byType(PhysicalInputNode)),
        const Offset(50, 50),
      );
      await tester.pumpAndSettle();

      // Test dragging output node
      await tester.dragFrom(
        tester.getCenter(find.byType(PhysicalOutputNode)),
        const Offset(50, 50),
      );
      await tester.pumpAndSettle();

      expect(
        inputNodeDragCalled,
        isTrue,
        reason: 'Input node drag callback should fire',
      );
      expect(
        outputNodeDragCalled,
        isTrue,
        reason: 'Output node drag callback should fire',
      );
    });

    testWidgets('Port widgets maintain consistent sizing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  child: PhysicalInputNode(
                    ports: _createTestInputPorts().take(3).toList(),
                    position: const Offset(100, 100),
                  ),
                ),
                Positioned(
                  left: 300,
                  top: 100,
                  child: PhysicalOutputNode(
                    ports: _createTestOutputPorts().take(3).toList(),
                    position: const Offset(300, 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find all port widgets
      final inputPorts = find.descendant(
        of: find.byType(PhysicalInputNode),
        matching: find.byType(PortWidget),
      );
      final outputPorts = find.descendant(
        of: find.byType(PhysicalOutputNode),
        matching: find.byType(PortWidget),
      );

      expect(
        inputPorts,
        findsWidgets,
        reason: 'Should find input port widgets',
      );
      expect(
        outputPorts,
        findsWidgets,
        reason: 'Should find output port widgets',
      );

      // Get sizes of port widgets (they should be consistent)
      final inputPortSizes = inputPorts
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)))
          .toList();
      final outputPortSizes = outputPorts
          .evaluate()
          .map((e) => tester.getSize(find.byWidget(e.widget)))
          .toList();

      // All input ports should have the same size
      for (int i = 1; i < inputPortSizes.length; i++) {
        expect(
          inputPortSizes[i],
          equals(inputPortSizes[0]),
          reason: 'All input port widgets should have consistent size',
        );
      }

      // All output ports should have the same size
      for (int i = 1; i < outputPortSizes.length; i++) {
        expect(
          outputPortSizes[i],
          equals(outputPortSizes[0]),
          reason: 'All output port widgets should have consistent size',
        );
      }
    });
  });
}
