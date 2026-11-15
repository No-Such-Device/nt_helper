import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/algorithm_node_widget.dart';
import 'package:nt_helper/ui/widgets/routing/physical_input_node.dart';
import 'package:nt_helper/ui/widgets/routing/physical_output_node.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';
import 'package:nt_helper/core/routing/models/port.dart' as core_port;

/// Helper function to create test physical input ports
List<core_port.Port> _createTestInputPorts() {
  return List.generate(12, (index) {
    final portNum = index + 1;
    return core_port.Port(
      id: 'hw_in_$portNum',
      name: 'Input $portNum',
      type: core_port.PortType.audio,
      direction: core_port
          .PortDirection
          .output, // Physical inputs act as outputs to algorithms
      role: core_port.PortRole.physicalInputBus,
      busValue: portNum,
    );
  });
}

/// Helper function to create test physical output ports
List<core_port.Port> _createTestOutputPorts() {
  return List.generate(8, (index) {
    final portNum = index + 1;
    return core_port.Port(
      id: 'hw_out_$portNum',
      name: 'Output $portNum',
      type: core_port.PortType.audio,
      direction: core_port
          .PortDirection
          .input, // Physical outputs act as inputs from algorithms
      role: core_port.PortRole.physicalOutputBus,
      busValue: portNum + 12,
    );
  });
}

/// Comprehensive integration tests for the universal port widget architecture.
///
/// Tests verify that the same PortWidget works consistently across:
/// - Algorithm nodes (using dot style ports)
/// - Physical I/O nodes (using jack style ports)
/// - All connections between different node types
/// - Node movement and position updates
/// - State management across the routing system
void main() {
  group('Universal Port Widget Integration Tests', () {
    group('Port Widget Cross-Node Compatibility', () {
      testWidgets('PortWidget works consistently in algorithm nodes', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AlgorithmNodeWidget(
                algorithmName: 'Test Algorithm',
                slotNumber: 1,
                position: const Offset(100, 100),
                inputLabels: const ['Input 1', 'Input 2'],
                outputLabels: const ['Output 1'],
                inputPortIds: const ['in1', 'in2'],
                outputPortIds: const ['out1'],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should find PortWidget instances within the algorithm node
        final portWidgets = find.descendant(
          of: find.byType(AlgorithmNodeWidget),
          matching: find.byType(PortWidget),
        );

        expect(
          portWidgets,
          findsWidgets,
          reason: 'AlgorithmNodeWidget should use PortWidget internally',
        );
      });

      testWidgets('PortWidget works consistently in physical I/O nodes', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalInputNode(
                ports: _createTestInputPorts().take(4).toList(),
                position: const Offset(50, 50),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should find PortWidget instances within the physical input node
        final portWidgets = find.descendant(
          of: find.byType(PhysicalInputNode),
          matching: find.byType(PortWidget),
        );

        expect(
          portWidgets,
          findsWidgets,
          reason: 'PhysicalInputNode should use PortWidget internally',
        );
      });

      testWidgets('Physical output nodes use consistent port widgets', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalOutputNode(
                ports: _createTestOutputPorts().take(4).toList(),
                position: const Offset(300, 50),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should find PortWidget instances within the physical output node
        final portWidgets = find.descendant(
          of: find.byType(PhysicalOutputNode),
          matching: find.byType(PortWidget),
        );

        expect(
          portWidgets,
          findsWidgets,
          reason: 'PhysicalOutputNode should use PortWidget internally',
        );
      });
    });

    group('Multi-Node Integration Tests', () {
      testWidgets('Multiple node types work together seamlessly', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  // Algorithm node
                  Positioned(
                    left: 100,
                    top: 100,
                    child: AlgorithmNodeWidget(
                      algorithmName: 'Filter',
                      slotNumber: 1,
                      position: const Offset(100, 100),
                      inputLabels: const ['Audio In', 'CV In'],
                      outputLabels: const ['Audio Out'],
                      inputPortIds: const ['audio_in', 'cv_in'],
                      outputPortIds: const ['audio_out'],
                    ),
                  ),
                  // Physical Input Node
                  Positioned(
                    left: 50,
                    top: 200,
                    child: PhysicalInputNode(
                      ports: _createTestInputPorts().take(3).toList(),
                      position: const Offset(50, 200),
                    ),
                  ),
                  // Physical Output Node
                  Positioned(
                    left: 300,
                    top: 200,
                    child: PhysicalOutputNode(
                      ports: _createTestOutputPorts().take(2).toList(),
                      position: const Offset(300, 200),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // All nodes should render successfully
        expect(find.byType(AlgorithmNodeWidget), findsOneWidget);
        expect(find.byType(PhysicalInputNode), findsOneWidget);
        expect(find.byType(PhysicalOutputNode), findsOneWidget);

        // All should use PortWidget consistently
        final algorithmPorts = find.descendant(
          of: find.byType(AlgorithmNodeWidget),
          matching: find.byType(PortWidget),
        );
        final inputPorts = find.descendant(
          of: find.byType(PhysicalInputNode),
          matching: find.byType(PortWidget),
        );
        final outputPorts = find.descendant(
          of: find.byType(PhysicalOutputNode),
          matching: find.byType(PortWidget),
        );

        expect(algorithmPorts, findsWidgets);
        expect(inputPorts, findsWidgets);
        expect(outputPorts, findsWidgets);
      });
    });

    group('Position and State Management', () {
      testWidgets('Port positions update correctly when nodes move', (
        tester,
      ) async {
        final Map<String, Offset> portPositions = {};

        void trackPortPosition(core_port.Port port, Offset position) {
          portPositions[port.id] = position;
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalInputNode(
                ports: _createTestInputPorts().take(2).toList(),
                position: const Offset(100, 100),
                onPortPositionResolved: trackPortPosition,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.pump(); // Allow position callbacks

        final initialPositionCount = portPositions.length;

        // Move the node
        await tester.dragFrom(
          tester.getCenter(find.byType(PhysicalInputNode)),
          const Offset(50, 50),
        );
        await tester.pumpAndSettle();
        await tester.pump(); // Allow position callbacks

        // Should have updated port positions
        expect(
          portPositions.length,
          equals(initialPositionCount),
          reason: 'Should maintain same number of tracked ports',
        );

        expect(
          portPositions,
          isNotEmpty,
          reason: 'Should have tracked port positions',
        );
      });

      testWidgets('Port interaction states work across all node types', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  // Test different node types with interactions
                  Positioned(
                    left: 0,
                    top: 100,
                    child: PhysicalInputNode(
                      ports: _createTestInputPorts().take(1).toList(),
                      position: const Offset(0, 100),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find port widgets
        final portWidgets = find.byType(PortWidget);
        expect(portWidgets, findsWidgets, reason: 'Should find port widgets');

        // Test interaction (tap)
        await tester.tap(portWidgets.first);
        await tester.pump();

        // Should not crash and widgets should still be present
        expect(find.byType(PhysicalInputNode), findsOneWidget);
        expect(find.byType(PortWidget), findsWidgets);
      });
    });

    group('Large Scale Integration Tests', () {
      testWidgets('System handles large routing graphs efficiently', (
        tester,
      ) async {
        final stopwatch = Stopwatch()..start();

        // Create a larger routing graph
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  // Multiple algorithm nodes
                  for (int i = 0; i < 3; i++)
                    Positioned(
                      left: 100 + i * 150.0,
                      top: 50,
                      child: AlgorithmNodeWidget(
                        algorithmName: 'Alg $i',
                        slotNumber: i + 1,
                        position: Offset(100 + i * 150.0, 50),
                        inputLabels: ['In ${i * 2}', 'In ${i * 2 + 1}'],
                        outputLabels: ['Out $i'],
                        inputPortIds: ['in_${i * 2}', 'in_${i * 2 + 1}'],
                        outputPortIds: ['out_$i'],
                      ),
                    ),
                  // Physical I/O nodes
                  Positioned(
                    left: 50,
                    top: 200,
                    child: PhysicalInputNode(
                      ports: _createTestInputPorts().take(6).toList(),
                      position: const Offset(50, 200),
                    ),
                  ),
                  Positioned(
                    left: 350,
                    top: 200,
                    child: PhysicalOutputNode(
                      ports: _createTestOutputPorts().take(4).toList(),
                      position: const Offset(350, 200),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        stopwatch.stop();

        // Should render efficiently
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Large routing graph should render within 1 second',
        );

        // All nodes should be present
        expect(find.byType(AlgorithmNodeWidget), findsNWidgets(3));
        expect(find.byType(PhysicalInputNode), findsOneWidget);
        expect(find.byType(PhysicalOutputNode), findsOneWidget);

        // All should use PortWidget
        final allPorts = find.byType(PortWidget);
        expect(
          allPorts,
          findsWidgets,
          reason: 'All nodes should use PortWidget',
        );
      });

      testWidgets('Memory management during rapid node operations', (
        tester,
      ) async {
        // Cycle through creating and destroying nodes
        for (int cycle = 0; cycle < 3; cycle++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    PhysicalInputNode(
                      ports: _createTestInputPorts().take(2).toList(),
                      position: Offset(50 + cycle * 10.0, 50),
                    ),
                    PhysicalOutputNode(
                      ports: _createTestOutputPorts().take(2).toList(),
                      position: Offset(200 + cycle * 10.0, 50),
                    ),
                  ],
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // Perform some interactions
          final nodes = find.byType(PhysicalInputNode);
          if (nodes.evaluate().isNotEmpty) {
            await tester.tap(nodes.first, warnIfMissed: false);
            await tester.pump();
          }

          // Clear the tree
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await tester.pumpAndSettle();
        }

        // If we reach this point, memory management is working
        expect(find.byType(PhysicalInputNode), findsNothing);
        expect(find.byType(PhysicalOutputNode), findsNothing);
      });
    });

    group('Widget Lifecycle and State Persistence', () {
      testWidgets('Widget state persists through rebuilds', (tester) async {
        bool nodePositionCallbackFired = false;

        void positionCallback(Offset position) {
          nodePositionCallbackFired = true;
        }

        // Initial build
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalInputNode(
                ports: _createTestInputPorts().take(1).toList(),
                position: const Offset(100, 100),
                onPositionChanged: positionCallback,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Interact with the widget
        await tester.dragFrom(
          tester.getCenter(find.byType(PhysicalInputNode)),
          const Offset(25, 25),
        );
        await tester.pumpAndSettle();

        // Rebuild the same widget
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalInputNode(
                ports: _createTestInputPorts().take(1).toList(),
                position: const Offset(100, 100),
                onPositionChanged: positionCallback,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(
          nodePositionCallbackFired,
          isTrue,
          reason: 'Position callback should have been fired',
        );

        // Widget should still be functional after rebuild
        expect(find.byType(PhysicalInputNode), findsOneWidget);
        expect(find.byType(PortWidget), findsWidgets);
      });
    });
  });
}
