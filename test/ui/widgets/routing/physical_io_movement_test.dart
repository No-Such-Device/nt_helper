import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/physical_input_node.dart';
import 'package:nt_helper/ui/widgets/routing/physical_output_node.dart';
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

/// Tests for physical I/O node movement functionality and connection updates.
///
/// Validates that physical I/O nodes can be moved correctly, port positions
/// update properly, and connections follow the nodes as they move.
void main() {
  group('Physical I/O Node Movement Tests', () {
    group('Position Constraints and Grid Snapping', () {
      testWidgets('Grid snapping works correctly', (tester) async {
        final List<Offset> positionHistory = [];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalOutputNode(
                ports: _createTestOutputPorts(),
                position: const Offset(100, 100),
                onPositionChanged: (newPosition) =>
                    positionHistory.add(newPosition),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Drag to positions that should snap to grid
        const List<Offset> testDrags = [
          Offset(12, 7), // Should snap to 25x25 grid
          Offset(38, 19), // Should snap to 50x25 grid
          Offset(63, 44), // Should snap to 75x50 grid
        ];

        for (final dragOffset in testDrags) {
          await tester.dragFrom(
            tester.getCenter(find.byType(PhysicalOutputNode)),
            dragOffset,
          );
          await tester.pumpAndSettle();
        }

        // Verify all positions are snapped to 25px grid
        for (final position in positionHistory) {
          expect(
            position.dx % 25,
            equals(0),
            reason: 'X position ${position.dx} should be snapped to 25px grid',
          );
          expect(
            position.dy % 25,
            equals(0),
            reason: 'Y position ${position.dy} should be snapped to 25px grid',
          );
        }
      });
    });

    group('Port Position Updates During Movement', () {
      testWidgets('All port types update positions correctly', (tester) async {
        final Set<String> updatedPortIds = {};

        void trackPortUpdate(Port port, Offset position) {
          updatedPortIds.add(port.id);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 50,
                    top: 50,
                    child: PhysicalInputNode(
                      ports: _createTestInputPorts(),
                      position: const Offset(50, 50),
                      onPortPositionResolved: trackPortUpdate,
                    ),
                  ),
                  Positioned(
                    left: 300,
                    top: 50,
                    child: PhysicalOutputNode(
                      ports: _createTestOutputPorts(),
                      position: const Offset(300, 50),
                      onPortPositionResolved: trackPortUpdate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.pump(); // Allow callbacks

        // Should have updates for all physical ports
        expect(updatedPortIds, hasLength(20)); // 12 inputs + 8 outputs

        // Verify specific port IDs
        for (int i = 1; i <= 12; i++) {
          expect(updatedPortIds, contains('hw_in_$i'));
        }
        for (int i = 1; i <= 8; i++) {
          expect(updatedPortIds, contains('hw_out_$i'));
        }
      });
    });

    group('Visual Feedback During Movement', () {
      
    });

    group('Error Handling and Edge Cases', () {
      testWidgets('Handles missing position callback gracefully', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PhysicalInputNode(
                ports: _createTestInputPorts(),
                position: const Offset(100, 100),
                // onPositionChanged is null
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Should render without errors
        expect(find.byType(PhysicalInputNode), findsOneWidget);

        // Drag should not cause errors
        await tester.dragFrom(
          tester.getCenter(find.byType(PhysicalInputNode)),
          const Offset(50, 50),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PhysicalInputNode), findsOneWidget);
      }, tags: ['regression']);
    });
  });
}
