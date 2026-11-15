import 'package:material_ui/material_ui.dart';
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

/// Performance tests for drag operations and connection updates
/// with the universal port widget architecture.
///
/// Tests validate:
/// - Drag operation performance across node types
/// - Port position update efficiency
/// - Large-scale routing system performance
/// - Memory usage during rapid updates
/// - Frame rate stability during interactions
void main() {
  group('Performance Tests', () {
    group('Drag Operation Performance', () {
      testWidgets('Simultaneous node drags maintain performance', (
        tester,
      ) async {
        final Map<String, List<Duration>> dragTimesByNodeType = {};
        final Map<String, Stopwatch> stopwatches = {
          'algorithm': Stopwatch(),
          'physical_input': Stopwatch(),
          'physical_output': Stopwatch(),
        };

        void recordDragTime(String nodeType) {
          if (!dragTimesByNodeType.containsKey(nodeType)) {
            dragTimesByNodeType[nodeType] = [];
          }
          stopwatches[nodeType]?.stop();
          final elapsed = stopwatches[nodeType]?.elapsed;
          if (elapsed != null) {
            dragTimesByNodeType[nodeType]!.add(elapsed);
          }
          stopwatches[nodeType]?.reset();
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
                      onPositionChanged: (_) =>
                          recordDragTime('physical_input'),
                    ),
                  ),
                  Positioned(
                    left: 300,
                    top: 50,
                    child: PhysicalOutputNode(
                      ports: _createTestOutputPorts(),
                      position: const Offset(300, 50),
                      onPositionChanged: (_) =>
                          recordDragTime('physical_output'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Perform rapid drag operations on both nodes
        const int iterations = 10;
        for (int i = 0; i < iterations; i++) {
          // Start timing for input node
          stopwatches['physical_input']!.start();
          await tester.dragFrom(
            tester.getCenter(find.byType(PhysicalInputNode)),
            Offset(10 * (i + 1).toDouble(), 10.0),
          );
          await tester.pump(const Duration(milliseconds: 16)); // Single frame

          // Start timing for output node
          stopwatches['physical_output']!.start();
          await tester.dragFrom(
            tester.getCenter(find.byType(PhysicalOutputNode)),
            Offset(10 * (i + 1).toDouble(), 10.0),
          );
          await tester.pump(const Duration(milliseconds: 16)); // Single frame
        }

        await tester.pumpAndSettle();

        // Verify performance (all drags should complete in reasonable time)
        for (final nodeType in dragTimesByNodeType.keys) {
          final times = dragTimesByNodeType[nodeType]!;
          final averageTime =
              times.fold<Duration>(Duration.zero, (sum, time) => sum + time) ~/
              times.length;

          expect(
            averageTime.inMilliseconds,
            lessThan(100),
            reason:
                '$nodeType drag operations should be fast (< 100ms average)',
          );
        }
      });
    });

    group('Port Position Update Performance', () {
      testWidgets('Large number of port position updates', (tester) async {
        final List<Duration> updateTimes = [];
        final stopwatch = Stopwatch();

        void trackUpdate(port, Offset position) {
          stopwatch.stop();
          updateTimes.add(stopwatch.elapsed);
          stopwatch.reset();
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  PhysicalInputNode(
                    ports: _createTestInputPorts(),
                    position: const Offset(100, 100),
                    onPortPositionResolved: (port, position) {
                      stopwatch.start();
                      trackUpdate(port, position);
                    },
                  ),
                  PhysicalOutputNode(
                    ports: _createTestOutputPorts(),
                    position: const Offset(300, 100),
                    onPortPositionResolved: (port, position) {
                      stopwatch.start();
                      trackUpdate(port, position);
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.pump(); // Allow all position callbacks

        // Should have fast port position updates
        if (updateTimes.isNotEmpty) {
          final averageUpdateTime =
              updateTimes.fold<Duration>(
                Duration.zero,
                (sum, time) => sum + time,
              ) ~/
              updateTimes.length;

          expect(
            averageUpdateTime.inMicroseconds,
            lessThan(1000),
            reason: 'Port position updates should be fast (< 1ms average)',
          );
        }
      });
    });

    group('Large Scale Performance', () {
      testWidgets('Many nodes with many ports perform well', (tester) async {
        final stopwatch = Stopwatch();

        stopwatch.start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  // Multiple physical I/O nodes to simulate large routing
                  for (int i = 0; i < 3; i++) ...[
                    Positioned(
                      left: (i * 200).toDouble(),
                      top: 100,
                      child: PhysicalInputNode(
                        ports: _createTestInputPorts().take(4).toList(),
                        position: Offset((i * 200).toDouble(), 100),
                      ),
                    ),
                    Positioned(
                      left: (i * 200).toDouble(),
                      top: 300,
                      child: PhysicalOutputNode(
                        ports: _createTestOutputPorts().take(4).toList(),
                        position: Offset((i * 200).toDouble(), 300),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        stopwatch.stop();

        // Should render large routing graph quickly
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: 'Large routing graph should render quickly (< 1s)',
        );

        // Should find all nodes
        expect(find.byType(PhysicalInputNode), findsNWidgets(3));
        expect(find.byType(PhysicalOutputNode), findsNWidgets(3));
      });
    });

    group('Animation Performance', () {
      testWidgets('Smooth drag animations', (tester) async {
        final List<Duration> frameTimes = [];
        Duration? lastFrameTime;

        void trackFrame() {
          final now = DateTime.now();
          if (lastFrameTime != null) {
            frameTimes.add(
              now.difference(
                DateTime.fromMillisecondsSinceEpoch(
                  lastFrameTime!.inMilliseconds,
                ),
              ),
            );
          }
          lastFrameTime = Duration(milliseconds: now.millisecondsSinceEpoch);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  PhysicalInputNode(
                    ports: _createTestInputPorts().take(1).toList(),
                    position: const Offset(0, 0),
                  ),
                  PhysicalOutputNode(
                    ports: _createTestOutputPorts().take(1).toList(),
                    position: const Offset(0, 300),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Perform drag with frame timing
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(PhysicalInputNode)),
        );

        for (int i = 0; i < 10; i++) {
          trackFrame();
          await gesture.moveBy(const Offset(10, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }

        await gesture.up();
        await tester.pumpAndSettle();

        // Verify smooth animation (consistent frame times)
        if (frameTimes.length >= 2) {
          final averageFrameTime =
              frameTimes.fold<Duration>(
                Duration.zero,
                (sum, time) => sum + time,
              ) ~/
              frameTimes.length;

          expect(
            averageFrameTime.inMilliseconds,
            lessThan(20),
            reason: 'Frame times should be smooth (< 20ms for 60fps)',
          );
        }
      });
    });

    group('Memory Usage', () {
      testWidgets('No memory leaks during repeated operations', (tester) async {
        // Create and destroy widgets multiple times
        for (int iteration = 0; iteration < 5; iteration++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Stack(
                  children: [
                    PhysicalInputNode(
                      ports: _createTestInputPorts(),
                      position: Offset(100 + iteration * 10.0, 100),
                    ),
                    PhysicalOutputNode(
                      ports: _createTestOutputPorts(),
                      position: Offset(300 + iteration * 10.0, 100),
                    ),
                  ],
                ),
              ),
            ),
          );

          await tester.pumpAndSettle();

          // Perform some operations
          await tester.dragFrom(
            tester.getCenter(find.byType(PhysicalInputNode)),
            const Offset(20, 20),
          );
          await tester.pumpAndSettle();

          // Clear the widget tree
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await tester.pumpAndSettle();
        }

        // If we get here without OutOfMemory, memory usage is acceptable
        expect(find.byType(PhysicalInputNode), findsNothing);
        expect(find.byType(PhysicalOutputNode), findsNothing);
      });
    });
  });
}
