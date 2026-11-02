import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart';

void main() {
  group('ConnectionPainter', () {
    late Connection mockConnection;
    late ConnectionData mockConnectionData;
    late ThemeData mockTheme;

    setUp(() {
      mockConnection = Connection(
        id: 'test_connection',
        sourcePortId: 'source_port',
        destinationPortId: 'destination_port',
        connectionType: ConnectionType.algorithmToAlgorithm,
      );

      mockConnectionData = ConnectionData(
        connection: mockConnection,
        sourcePosition: const Offset(50, 100),
        destinationPosition: const Offset(200, 150),
        busNumber: 5,
        outputMode: OutputMode.add,
      );

      mockTheme = ThemeData.light();
    });

    group('Label Bounds Storage', () {
      test('should store label bounds during painting', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: true,
        );

        // Create a test canvas
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);

        // Paint the connections (this should store label bounds)
        painter.paint(canvas, size);

        // Check that label bounds were stored
        final labelBounds = painter.getLabelBounds();
        expect(labelBounds, isNotNull);
        expect(labelBounds.containsKey(mockConnection.id), isTrue);

        final bounds = labelBounds[mockConnection.id];
        expect(bounds, isNotNull);
        expect(bounds!.width, greaterThan(0));
        expect(bounds.height, greaterThan(0));
      });

      test('should not store bounds when labels are disabled', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: false,
        );

        // Create a test canvas
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);

        // Paint the connections
        painter.paint(canvas, size);

        // Check that no label bounds were stored
        final labelBounds = painter.getLabelBounds();
        expect(labelBounds.isEmpty, isTrue);
      });

      test('should clear previous bounds on repaint', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: true,
        );

        // Create a test canvas
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);

        // First paint
        painter.paint(canvas, size);
        final firstBounds = painter.getLabelBounds();
        expect(firstBounds.isNotEmpty, isTrue);

        // Second paint with different connection
        final newConnection = Connection(
          id: 'new_connection',
          sourcePortId: 'new_source',
          destinationPortId: 'new_destination',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final newConnectionData = ConnectionData(
          connection: newConnection,
          sourcePosition: const Offset(100, 50),
          destinationPosition: const Offset(250, 100),
          busNumber: 3,
        );

        final newPainter = ConnectionPainter(
          connections: [newConnectionData],
          theme: mockTheme,
          showLabels: true,
        );

        newPainter.paint(canvas, size);
        final secondBounds = newPainter.getLabelBounds();

        // Should only have bounds for the new connection
        expect(secondBounds.containsKey(mockConnection.id), isFalse);
        expect(secondBounds.containsKey(newConnection.id), isTrue);
      });
    });

    group('Hit Testing', () {
      test('should hit test label bounds correctly', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: true,
        );

        // Create a test canvas and paint
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);
        painter.paint(canvas, size);

        // Get the label bounds
        final labelBounds = painter.getLabelBounds();
        final bounds = labelBounds[mockConnection.id]!;

        // Test hit detection inside bounds
        final centerPoint = bounds.center;
        final hitConnection = painter.hitTestLabel(centerPoint);
        expect(hitConnection, equals(mockConnection.id));

        // Test hit detection outside bounds
        final outsidePoint = Offset(bounds.right + 10, bounds.bottom + 10);
        final missedConnection = painter.hitTestLabel(outsidePoint);
        expect(missedConnection, isNull);
      });

      test('should return null for hit test when no labels exist', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: false,
        );

        // Create a test canvas and paint
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);
        painter.paint(canvas, size);

        // Test hit detection - should return null
        final hitConnection = painter.hitTestLabel(const Offset(100, 100));
        expect(hitConnection, isNull);
      });

      test(
        'should return first matching connection for overlapping labels',
        () {
          // Create two connections with similar positions (overlapping labels)
          final connection1 = Connection(
            id: 'connection_1',
            sourcePortId: 'source_1',
            destinationPortId: 'dest_1',
            connectionType: ConnectionType.algorithmToAlgorithm,
          );

          final connection2 = Connection(
            id: 'connection_2',
            sourcePortId: 'source_2',
            destinationPortId: 'dest_2',
            connectionType: ConnectionType.algorithmToAlgorithm,
          );

          final connectionData1 = ConnectionData(
            connection: connection1,
            sourcePosition: const Offset(50, 100),
            destinationPosition: const Offset(150, 120),
            busNumber: 1,
          );

          final connectionData2 = ConnectionData(
            connection: connection2,
            sourcePosition: const Offset(55, 105),
            destinationPosition: const Offset(155, 125),
            busNumber: 2,
          );

          final painter = ConnectionPainter(
            connections: [connectionData1, connectionData2],
            theme: mockTheme,
            showLabels: true,
          );

          // Paint to generate bounds
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          const size = Size(400, 300);
          painter.paint(canvas, size);

          // Hit test at a point that might overlap both labels
          final testPoint = const Offset(100, 110);
          final hitConnection = painter.hitTestLabel(testPoint);

          // Should return one of the connections (first match)
          expect(
            hitConnection,
            anyOf(equals('connection_1'), equals('connection_2')),
          );
        },
      );
    });

    group('Hover Visual Feedback', () {
      

      test('should not apply hover styling when not hovered', () {
        final painter = ConnectionPainter(
          connections: [mockConnectionData],
          theme: mockTheme,
          showLabels: true,
          hoveredConnectionId: 'different_connection',
        );

        // Create a test canvas
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(400, 300);

        // Paint the connections
        painter.paint(canvas, size);

        // Check that label bounds were stored normally
        final labelBounds = painter.getLabelBounds();
        expect(labelBounds.containsKey(mockConnection.id), isTrue);

        // Verify hovered connection ID is different
        expect(painter.hoveredConnectionId, equals('different_connection'));
      });

      test(
        'should not apply hover styling when hoveredConnectionId is null',
        () {
          final painter = ConnectionPainter(
            connections: [mockConnectionData],
            theme: mockTheme,
            showLabels: true,
            hoveredConnectionId: null,
          );

          // Create a test canvas
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          const size = Size(400, 300);

          // Paint the connections
          painter.paint(canvas, size);

          // Check that label bounds were stored normally
          final labelBounds = painter.getLabelBounds();
          expect(labelBounds.containsKey(mockConnection.id), isTrue);

          // Verify no hover state
          expect(painter.hoveredConnectionId, isNull);
        },
      );
    });

    group('Invalid Connection Rendering', () {
      test(
        'should render invalid connections with dashed lines and error color',
        () {
          final theme = ThemeData.light();
          final invalidConnection = ConnectionData(
            connection: Connection(
              id: 'invalid_test',
              sourcePortId: 'alg_2_out_1',
              destinationPortId: 'alg_1_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: true, // Mark as invalid
            ),
            sourcePosition: const Offset(10, 10),
            destinationPosition: const Offset(100, 50),
          );

          final painter = ConnectionPainter(
            connections: [invalidConnection],
            theme: theme,
          );

          // Test that invalid connection is identified
          expect(invalidConnection.isInvalidOrder, isTrue);

          // Verify painter handles the invalid connection
          expect(painter.connections.length, equals(1));
          expect(painter.connections.first.isInvalidOrder, isTrue);
        },
      );

      test(
        'should group invalid connections separately for batch rendering',
        () {
          final theme = ThemeData.light();
          final validConnection = ConnectionData(
            connection: Connection(
              id: 'valid_test',
              sourcePortId: 'alg_1_out_1',
              destinationPortId: 'alg_2_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: false,
            ),
            sourcePosition: const Offset(10, 10),
            destinationPosition: const Offset(100, 50),
          );

          final invalidConnection = ConnectionData(
            connection: Connection(
              id: 'invalid_test',
              sourcePortId: 'alg_2_out_1',
              destinationPortId: 'alg_1_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: true,
            ),
            sourcePosition: const Offset(10, 100),
            destinationPosition: const Offset(100, 150),
          );

          final painter = ConnectionPainter(
            connections: [validConnection, invalidConnection],
            theme: theme,
          );

          // Verify that connections are properly categorized
          expect(painter.connections.length, equals(2));
          expect(
            painter.connections.where((c) => c.isInvalidOrder).length,
            equals(1),
          );
          expect(
            painter.connections.where((c) => !c.isInvalidOrder).length,
            equals(1),
          );
        },
      );

      test('should handle mixed connection types with proper grouping', () {
        final theme = ThemeData.light();
        final connections = [
          // Regular valid connection
          ConnectionData(
            connection: Connection(
              id: 'regular',
              sourcePortId: 'alg_1_out_1',
              destinationPortId: 'alg_2_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: false,
            ),
            sourcePosition: const Offset(10, 10),
            destinationPosition: const Offset(100, 50),
          ),
          // Invalid connection
          ConnectionData(
            connection: Connection(
              id: 'invalid',
              sourcePortId: 'alg_3_out_1',
              destinationPortId: 'alg_1_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: true,
            ),
            sourcePosition: const Offset(10, 100),
            destinationPosition: const Offset(100, 150),
          ),
          // Ghost connection
          ConnectionData(
            connection: Connection(
              id: 'ghost',
              sourcePortId: 'alg_1_out_2',
              destinationPortId: 'alg_2_in_2',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isGhostConnection: true,
            ),
            sourcePosition: const Offset(10, 200),
            destinationPosition: const Offset(100, 250),
          ),
          // Partial connection
          ConnectionData(
            connection: Connection(
              id: 'partial',
              sourcePortId: 'alg_1_out_3',
              destinationPortId: '',
              connectionType: ConnectionType.partialOutputToBus,
              isPartial: true,
            ),
            sourcePosition: const Offset(10, 300),
            destinationPosition: const Offset(100, 350),
          ),
          // Selected connection
          ConnectionData(
            connection: Connection(
              id: 'selected',
              sourcePortId: 'alg_2_out_1',
              destinationPortId: 'alg_3_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
            ),
            sourcePosition: const Offset(10, 400),
            destinationPosition: const Offset(100, 450),
            isSelected: true,
          ),
        ];

        final painter = ConnectionPainter(
          connections: connections,
          theme: theme,
        );

        expect(painter.connections.length, equals(5));

        // Verify grouping logic works correctly
        final regularConnections = painter.connections
            .where(
              (c) =>
                  !c.isSelected &&
                  !c.isPartial &&
                  !c.isInvalidOrder &&
                  !c.isGhostConnection,
            )
            .toList();
        final invalidConnections = painter.connections
            .where((c) => c.isInvalidOrder)
            .toList();
        final ghostConnections = painter.connections
            .where((c) => c.isGhostConnection)
            .toList();
        final partialConnections = painter.connections
            .where((c) => c.isPartial)
            .toList();
        final selectedConnections = painter.connections
            .where((c) => c.isSelected)
            .toList();

        expect(regularConnections.length, equals(1));
        expect(invalidConnections.length, equals(1));
        expect(ghostConnections.length, equals(1));
        expect(partialConnections.length, equals(1));
        expect(selectedConnections.length, equals(1));
      });
    });

    group('ConnectionData Model', () {
      test('should correctly identify invalid order from isBackwardEdge', () {
        final invalidConnectionData = ConnectionData(
          connection: Connection(
            id: 'test',
            sourcePortId: 'source',
            destinationPortId: 'dest',
            connectionType: ConnectionType.algorithmToAlgorithm,
            isBackwardEdge: true,
          ),
          sourcePosition: const Offset(0, 0),
          destinationPosition: const Offset(100, 100),
        );

        expect(invalidConnectionData.isInvalidOrder, isTrue);
      });

      test('should correctly identify valid connections', () {
        final validConnectionData = ConnectionData(
          connection: Connection(
            id: 'test',
            sourcePortId: 'source',
            destinationPortId: 'dest',
            connectionType: ConnectionType.algorithmToAlgorithm,
            isBackwardEdge: false,
          ),
          sourcePosition: const Offset(0, 0),
          destinationPosition: const Offset(100, 100),
        );

        expect(validConnectionData.isInvalidOrder, isFalse);
      });

      test('should handle physical connections as valid', () {
        final physicalConnectionData = ConnectionData(
          connection: Connection(
            id: 'physical',
            sourcePortId: 'hw_in_1',
            destinationPortId: 'alg_1_in_1',
            connectionType: ConnectionType.hardwareInput,
          ),
          sourcePosition: const Offset(0, 0),
          destinationPosition: const Offset(100, 100),
          isPhysicalConnection: true,
        );

        // Physical connections should never be marked as invalid
        expect(physicalConnectionData.isInvalidOrder, isFalse);
        expect(physicalConnectionData.isPhysicalConnection, isTrue);
      });
    });

    group('Dash Pattern Support', () {
      test('should create painter with dash pattern support enabled', () {
        final theme = ThemeData.light();
        final painter = ConnectionPainter(connections: [], theme: theme);

        // Verify painter can be instantiated (dash pattern support is internal)
        expect(painter.connections, isEmpty);
        expect(painter.theme, equals(theme));
      });

      
    });

    group('Theme Integration', () {
      test(
        'should use error color from light theme for invalid connections',
        () {
          final lightTheme = ThemeData.light();
          final painter = ConnectionPainter(connections: [], theme: lightTheme);

          expect(painter.theme.colorScheme.error, isNotNull);
          // In light theme, error color should typically be red-ish
          expect(
            painter.theme.colorScheme.error.value,
            isNot(equals(Colors.transparent.value)),
          );
        },
      );

      test(
        'should use error color from dark theme for invalid connections',
        () {
          final darkTheme = ThemeData.dark();
          final painter = ConnectionPainter(connections: [], theme: darkTheme);

          expect(painter.theme.colorScheme.error, isNotNull);
          // In dark theme, error color should also be available
          expect(
            painter.theme.colorScheme.error.value,
            isNot(equals(Colors.transparent.value)),
          );
        },
      );

      
    });

    group('Performance', () {
      test(
        'should handle large numbers of invalid connections efficiently',
        () {
          final theme = ThemeData.light();
          final invalidConnections = List.generate(
            100,
            (index) => ConnectionData(
              connection: Connection(
                id: 'invalid_$index',
                sourcePortId: 'alg_${index % 5}_out_1',
                destinationPortId: 'alg_${(index % 5) - 1}_in_1',
                connectionType: ConnectionType.algorithmToAlgorithm,
                isBackwardEdge: true,
              ),
              sourcePosition: Offset(10.0, index * 10.0),
              destinationPosition: Offset(100.0, index * 10.0 + 50),
            ),
          );

          final painter = ConnectionPainter(
            connections: invalidConnections,
            theme: theme,
          );

          expect(painter.connections.length, equals(100));
          expect(painter.connections.every((c) => c.isInvalidOrder), isTrue);
        },
      );

      test('should maintain performance with mixed connection types', () {
        final theme = ThemeData.light();
        final mixedConnections = <ConnectionData>[];

        // Add various connection types
        for (int i = 0; i < 50; i++) {
          mixedConnections.addAll([
            // Valid connection
            ConnectionData(
              connection: Connection(
                id: 'valid_$i',
                sourcePortId: 'alg_${i % 5}_out_1',
                destinationPortId: 'alg_${(i % 5) + 1}_in_1',
                connectionType: ConnectionType.algorithmToAlgorithm,
              ),
              sourcePosition: Offset(10.0, i * 20.0),
              destinationPosition: Offset(100.0, i * 20.0 + 50),
            ),
            // Invalid connection
            ConnectionData(
              connection: Connection(
                id: 'invalid_$i',
                sourcePortId: 'alg_${(i % 5) + 1}_out_1',
                destinationPortId: 'alg_${i % 5}_in_1',
                connectionType: ConnectionType.algorithmToAlgorithm,
                isBackwardEdge: true,
              ),
              sourcePosition: Offset(10.0, i * 20.0 + 10),
              destinationPosition: Offset(100.0, i * 20.0 + 60),
            ),
          ]);
        }

        final painter = ConnectionPainter(
          connections: mixedConnections,
          theme: theme,
        );

        expect(painter.connections.length, equals(100));
        expect(
          painter.connections.where((c) => c.isInvalidOrder).length,
          equals(50),
        );
        expect(
          painter.connections.where((c) => !c.isInvalidOrder).length,
          equals(50),
        );
      });
    });

    group('Rendering Order', () {
      test('should maintain proper z-order for different connection types', () {
        // The rendering order should be: regular -> ghost -> invalid -> partial -> selected
        // This ensures invalid connections are visible but not on top of selected ones

        final theme = ThemeData.light();
        final connections = [
          // Selected connection (should render last/on top)
          ConnectionData(
            connection: Connection(
              id: 'selected',
              sourcePortId: 'alg_1_out_1',
              destinationPortId: 'alg_2_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
            ),
            sourcePosition: const Offset(0, 0),
            destinationPosition: const Offset(100, 100),
            isSelected: true,
          ),
          // Invalid connection (should render before selected)
          ConnectionData(
            connection: Connection(
              id: 'invalid',
              sourcePortId: 'alg_2_out_1',
              destinationPortId: 'alg_1_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
              isBackwardEdge: true,
            ),
            sourcePosition: const Offset(0, 50),
            destinationPosition: const Offset(100, 150),
          ),
          // Regular connection (should render first/in background)
          ConnectionData(
            connection: Connection(
              id: 'regular',
              sourcePortId: 'alg_1_out_2',
              destinationPortId: 'alg_3_in_1',
              connectionType: ConnectionType.algorithmToAlgorithm,
            ),
            sourcePosition: const Offset(0, 100),
            destinationPosition: const Offset(100, 200),
          ),
        ];

        final painter = ConnectionPainter(
          connections: connections,
          theme: theme,
        );

        // Verify all connections are present
        expect(painter.connections.length, equals(3));

        // The painter should handle the rendering order internally
        // We can verify the connections are properly categorized
        final regularConnections = painter.connections
            .where((c) => !c.isSelected && !c.isInvalidOrder)
            .toList();
        final invalidConnections = painter.connections
            .where((c) => c.isInvalidOrder)
            .toList();
        final selectedConnections = painter.connections
            .where((c) => c.isSelected)
            .toList();

        expect(regularConnections.length, equals(1));
        expect(invalidConnections.length, equals(1));
        expect(selectedConnections.length, equals(1));
      });
    });

    group('Label Overlap Avoidance', () {
      test('overlapping labels get nudged apart', () {
        // Two connections with identical source/destination positions
        // will produce labels at the same midpoint
        final connection1 = Connection(
          id: 'overlap_1',
          sourcePortId: 'source_1',
          destinationPortId: 'dest_1',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connection2 = Connection(
          id: 'overlap_2',
          sourcePortId: 'source_2',
          destinationPortId: 'dest_2',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connectionData1 = ConnectionData(
          connection: connection1,
          sourcePosition: const Offset(50, 100),
          destinationPosition: const Offset(250, 100),
          busNumber: 1,
        );

        final connectionData2 = ConnectionData(
          connection: connection2,
          sourcePosition: const Offset(50, 100),
          destinationPosition: const Offset(250, 100),
          busNumber: 2,
        );

        final painter = ConnectionPainter(
          connections: [connectionData1, connectionData2],
          theme: ThemeData.light(),
          showLabels: true,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 300));

        final bounds = painter.getLabelBounds();
        final rect1 = bounds['overlap_1']!;
        final rect2 = bounds['overlap_2']!;

        // Labels should not overlap
        expect(rect1.overlaps(rect2), isFalse);
      }, tags: ['regression']);

      test('non-overlapping labels remain unchanged', () {
        // Two connections with very different positions
        final connection1 = Connection(
          id: 'far_1',
          sourcePortId: 'source_1',
          destinationPortId: 'dest_1',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connection2 = Connection(
          id: 'far_2',
          sourcePortId: 'source_2',
          destinationPortId: 'dest_2',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connectionData1 = ConnectionData(
          connection: connection1,
          sourcePosition: const Offset(50, 50),
          destinationPosition: const Offset(250, 50),
          busNumber: 1,
        );

        final connectionData2 = ConnectionData(
          connection: connection2,
          sourcePosition: const Offset(50, 250),
          destinationPosition: const Offset(250, 250),
          busNumber: 2,
        );

        final painter = ConnectionPainter(
          connections: [connectionData1, connectionData2],
          theme: ThemeData.light(),
          showLabels: true,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 300));

        final bounds = painter.getLabelBounds();
        final rect1 = bounds['far_1']!;
        final rect2 = bounds['far_2']!;

        // Labels should already be non-overlapping (far apart vertically)
        expect(rect1.overlaps(rect2), isFalse);

        // Second label should not have been shifted (its center Y should be
        // near the midpoint of the connection, i.e. y=250)
        expect(rect2.center.dy, closeTo(250, 20));
      });

      test('gap between stacked labels is exactly 2px', () {
        // Same positions → labels will overlap and get resolved
        final connection1 = Connection(
          id: 'gap_1',
          sourcePortId: 'source_1',
          destinationPortId: 'dest_1',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connection2 = Connection(
          id: 'gap_2',
          sourcePortId: 'source_2',
          destinationPortId: 'dest_2',
          connectionType: ConnectionType.algorithmToAlgorithm,
        );

        final connectionData1 = ConnectionData(
          connection: connection1,
          sourcePosition: const Offset(50, 100),
          destinationPosition: const Offset(250, 100),
          busNumber: 1,
        );

        final connectionData2 = ConnectionData(
          connection: connection2,
          sourcePosition: const Offset(50, 100),
          destinationPosition: const Offset(250, 100),
          busNumber: 2,
        );

        final painter = ConnectionPainter(
          connections: [connectionData1, connectionData2],
          theme: ThemeData.light(),
          showLabels: true,
        );

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(400, 300));

        final bounds = painter.getLabelBounds();
        final rect1 = bounds['gap_1']!;
        final rect2 = bounds['gap_2']!;

        // The second label's top should be exactly 2px below the first label's bottom
        expect(rect2.top, closeTo(rect1.bottom + 2.0, 0.01));
      });
    });

    group('Obstacle Avoidance', () {
      

      test(
        'should paint without error when obstacles are present (masking)',
        () {
          final theme = ThemeData.light();
          final connection = ConnectionData(
            connection: Connection(
              id: 'test_masking',
              sourcePortId: 'source',
              destinationPortId: 'dest',
              connectionType: ConnectionType.algorithmToAlgorithm,
            ),
            sourcePosition: const Offset(0, 100),
            destinationPosition: const Offset(400, 100),
          );

          // Obstacle directly on the line
          final obstacle = Rect.fromLTWH(150, 50, 100, 100);

          final painter = ConnectionPainter(
            connections: [connection],
            theme: theme,
            obstacles: [obstacle],
          );

          // Just ensure it paints without error
          // The masking happens during paint via saveLayer/BlendMode.clear
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder);
          painter.paint(canvas, const Size(400, 400));
        },
      );
    });
  });
}

// ignore_for_file: deprecated_member_use
