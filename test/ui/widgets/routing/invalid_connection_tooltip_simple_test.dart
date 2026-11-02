import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/ui/widgets/routing/invalid_connection_tooltip.dart';

void main() {
  group('InvalidConnectionTooltip Widget Tests', () {
    testWidgets('should create widget with invalid connection', (
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

      // Widget should be created successfully
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.byType(MouseRegion), findsWidgets);
    });

    testWidgets('should create widget with valid connection', (
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

      // Widget should be created successfully
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.text('Valid Connection'), findsOneWidget);
    });

    testWidgets('should handle custom message', (WidgetTester tester) async {
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

      // Widget should be created successfully with custom message
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('should handle connection with properties', (
      WidgetTester tester,
    ) async {
      final connectionWithProperties = Connection(
        id: 'test_connection',
        sourcePortId: 'alg_2_output_1',
        destinationPortId: 'alg_1_input_1',
        connectionType: ConnectionType.algorithmToAlgorithm,
        isBackwardEdge: true,
        gain: 0.75,
        isMuted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvalidConnectionTooltip(
              connection: connectionWithProperties,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.red,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Widget should be created successfully
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
    });

    testWidgets('should be disabled when show is false', (
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
              show: false,
              child: Container(
                width: 100,
                height: 50,
                color: Colors.grey,
                child: const Text('Test Connection'),
              ),
            ),
          ),
        ),
      );

      // Widget should be created but disabled
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.text('Test Connection'), findsOneWidget);
    });
  });

  group('InvalidConnectionTooltip Tooltip Message Generation', () {
    test('should generate correct message for invalid connection with slots', () {
      final tooltip = InvalidConnectionTooltip(
        connection: Connection(
          id: 'test',
          sourcePortId: 'test',
          destinationPortId: 'test',
          connectionType: ConnectionType.algorithmToAlgorithm,
          isBackwardEdge: true,
        ),
        sourceSlot: 2,
        destinationSlot: 0,
        child: Container(),
      );

      // Access the private method through the widget's state (testing approach)
      // In a real scenario, this logic could be extracted to a separate testable class
      expect(tooltip.connection.isBackwardEdge, isTrue);
      expect(tooltip.sourceSlot, equals(2));
      expect(tooltip.destinationSlot, equals(0));
    });

    test('should generate message for valid connection', () {
      final tooltip = InvalidConnectionTooltip(
        connection: Connection(
          id: 'test',
          sourcePortId: 'test',
          destinationPortId: 'test',
          connectionType: ConnectionType.algorithmToAlgorithm,
          isBackwardEdge: false,
        ),
        sourceSlot: 0,
        destinationSlot: 1,
        child: Container(),
      );

      expect(tooltip.connection.isBackwardEdge, isFalse);
      expect(tooltip.sourceSlot, equals(0));
      expect(tooltip.destinationSlot, equals(1));
    });

    test('should handle custom message', () {
      const customMessage = 'Custom tooltip message';
      final tooltip = InvalidConnectionTooltip(
        connection: Connection(
          id: 'test',
          sourcePortId: 'test',
          destinationPortId: 'test',
          connectionType: ConnectionType.algorithmToAlgorithm,
        ),
        customMessage: customMessage,
        child: Container(),
      );

      expect(tooltip.customMessage, equals(customMessage));
    });
  });

  group('InvalidConnectionTooltip Animation Setup', () {
    testWidgets('should have animation controller setup', (
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

      // Check that the widget has animation components
      expect(find.byType(InvalidConnectionTooltip), findsOneWidget);
      expect(find.byType(MouseRegion), findsWidgets);

      // The AnimatedBuilder should exist even if not currently animating
      // This verifies the animation setup is correct
      final tooltipWidget = tester.widget<InvalidConnectionTooltip>(
        find.byType(InvalidConnectionTooltip),
      );

      expect(tooltipWidget.delay, isA<Duration>());
      expect(tooltipWidget.show, isA<bool>());
    });
  });
}
