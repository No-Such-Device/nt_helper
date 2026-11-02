import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/ui/widgets/routing/invalid_connection_tooltip.dart';

void main() {
  group('InvalidConnectionTooltip Widget Tests', () {
    testWidgets('should create tooltip widget with correct structure', (
      WidgetTester tester,
    ) async {
      final invalidConnection = Connection(
        id: 'test_invalid',
        sourcePortId: 'alg_2_output_1',
        destinationPortId: 'alg_1_input_1',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: invalidConnection,
              sourceSlot: 1,
              destinationSlot: 0,
              delay: Duration.zero,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.blue,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Should create the widget without errors
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.byType(MouseRegion), findsNWidgets(2));
      expect(find.byType(Stack), findsAtLeastNWidgets(1));
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('should handle valid connections correctly', (
      WidgetTester tester,
    ) async {
      final validConnection = Connection(
        id: 'test_valid',
        sourcePortId: 'alg_1_output_1',
        destinationPortId: 'alg_2_input_1',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: validConnection,
              sourceSlot: 0,
              destinationSlot: 1,
              delay: Duration.zero,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.green,
                child: const Text('Valid Connection'),
              ),
            ),
          ),
        ),
      );

      // Should create the widget structure correctly for valid connections
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.byType(MouseRegion), findsNWidgets(2));
      expect(find.text('Valid Connection'), findsOneWidget);
    });

    testWidgets('should handle custom messages', (WidgetTester tester) async {
      final connection = Connection(
        id: 'test_connection',
        sourcePortId: 'test_port',
        destinationPortId: 'dest_port',
        connectionType: ConnectionType.algorithmToAlgorithm,
      );

      const customMessage = 'This is a custom tooltip message for testing.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: connection,
              customMessage: customMessage,
              delay: Duration.zero,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.purple,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Should create widget with custom message property
      final tooltipWidget = tester.widget<InvalidConnectionTooltip>(
        find.byType(InvalidConnectionTooltip),
      );
      expect(tooltipWidget.customMessage, equals(customMessage));
      expect(tooltipWidget.connection, equals(connection));
    });

    

    

    

    testWidgets('should handle missing slot numbers', (
      WidgetTester tester,
    ) async {
      final invalidConnection = Connection(
        id: 'test_invalid',
        sourcePortId: 'unknown_output',
        destinationPortId: 'unknown_input',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: invalidConnection,
              // No sourceSlot or destinationSlot provided
              delay: Duration.zero,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.pink,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Should handle missing slot numbers gracefully
      final tooltipWidget = tester.widget<InvalidConnectionTooltip>(
        find.byType(InvalidConnectionTooltip),
      );
      expect(tooltipWidget.sourceSlot, isNull);
      expect(tooltipWidget.destinationSlot, isNull);
    });

    
  });

  group('InvalidConnectionTooltip Animation Tests', () {
    testWidgets('should create widget with animation controller structure', (
      WidgetTester tester,
    ) async {
      final connection = Connection(
        id: 'test_connection',
        sourcePortId: 'test_port',
        destinationPortId: 'dest_port',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: connection,
              delay: Duration.zero,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.blue,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Should create the widget structure for animation
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.byType(MouseRegion), findsNWidgets(2));
      expect(find.byType(Stack), findsAtLeastNWidgets(1));
    });

    testWidgets('should handle different delay durations', (
      WidgetTester tester,
    ) async {
      final connection = Connection(
        id: 'test_connection',
        sourcePortId: 'test_port',
        destinationPortId: 'dest_port',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: connection,
              delay: const Duration(milliseconds: 100),
              child: Container(
                width: 100,
                height: 50,
                color: Colors.blue,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Should handle different delay durations
      final tooltipWidget = tester.widget<InvalidConnectionTooltip>(
        find.byType(InvalidConnectionTooltip),
      );
      expect(tooltipWidget.delay, equals(const Duration(milliseconds: 100)));
    });
  });
}
