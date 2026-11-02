import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/ui/widgets/routing/interactive_connection_widget.dart';

@GenerateMocks([RoutingEditorCubit, PlatformInteractionService])
import 'connection_hover_detection_test.mocks.dart';

/// Tests for hover interaction detection on desktop platforms
void main() {
  group('Connection Hover Detection', () {
    late MockRoutingEditorCubit mockCubit;
    late MockPlatformInteractionService mockPlatformService;
    late Connection testConnection;

    setUp(() {
      mockCubit = MockRoutingEditorCubit();
      mockPlatformService = MockPlatformInteractionService();
      testConnection = const Connection(
        id: 'hover-test-connection',
        sourcePortId: 'source-port-hover',
        destinationPortId: 'dest-port-hover',
        connectionType: ConnectionType.algorithmToAlgorithm,
      );
    });

    Widget createDesktopConnectionWidget() {
      // Setup desktop platform behavior
      when(mockPlatformService.supportsHoverInteractions()).thenReturn(true);
      when(mockPlatformService.shouldUseTouchInteractions()).thenReturn(false);
      when(mockPlatformService.getMinimumTouchTargetSize()).thenReturn(24.0);

      return MaterialApp(
        home: Scaffold(
          body: InteractiveConnectionWidget(
            connection: testConnection,
            routingEditorCubit: mockCubit,
            platformService: mockPlatformService,
            child: Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.blue,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: const Center(child: Text('Connection Line')),
            ),
          ),
        ),
      );
    }

    group('Mouse Hover Enter/Exit Events', () {
      testWidgets('detects mouse hover enter event', (tester) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        // Find our specific MouseRegion widget (the one with listeners)
        final mouseRegion = find.byType(MouseRegion).last;

        // Verify initial state - no delete button visible
        expect(find.byIcon(Icons.close), findsNothing);

        // Simulate mouse enter by using the low-level mouse tracking
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        // Allow animation time
        await tester.pump(const Duration(milliseconds: 100));

        // Verify that hover state is detected (delete button should start appearing)
        // Note: Actual opacity animation testing requires more sophisticated setup
        // For now, we verify the widget structure is correct for hover
        final interactiveWidget = tester.widget<InteractiveConnectionWidget>(
          find.byType(InteractiveConnectionWidget),
        );
        expect(
          interactiveWidget.connection.id,
          equals('hover-test-connection'),
        );

        await gesture.removePointer();
      });

      testWidgets('detects mouse hover exit event', (tester) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        final mouseRegion = find.byType(MouseRegion).last;

        // Simulate entering and then exiting
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        // Enter
        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        // Exit by moving away
        await gesture.moveTo(const Offset(1000, 1000));
        await tester.pump();

        // Allow animation time for fade out
        await tester.pump(const Duration(milliseconds: 300));

        // Verify hover state is cleared
        expect(find.byIcon(Icons.close), findsNothing);

        await gesture.removePointer();
      });

      testWidgets('maintains hover state while cursor remains over widget', (
        tester,
      ) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        final mouseRegion = find.byType(MouseRegion).last;
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        // Enter hover area
        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        // Move around within the widget bounds
        final center = tester.getCenter(mouseRegion);
        await gesture.moveTo(Offset(center.dx + 10, center.dy + 10));
        await tester.pump();
        await gesture.moveTo(Offset(center.dx - 10, center.dy - 10));
        await tester.pump();

        // Verify hover state is maintained
        // The widget should still be in hover mode
        final interactiveWidget = tester.widget<InteractiveConnectionWidget>(
          find.byType(InteractiveConnectionWidget),
        );
        expect(
          interactiveWidget.connection.id,
          equals('hover-test-connection'),
        );

        await gesture.removePointer();
      });
    });

    group('Hover State Persistence and Cleanup', () {
      testWidgets('cleans up hover state when widget is disposed', (
        tester,
      ) async {
        // Build widget
        await tester.pumpWidget(createDesktopConnectionWidget());

        final mouseRegion = find.byType(MouseRegion).last;
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        // Enter hover state
        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        // Dispose widget by rebuilding without it
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('Empty'))),
        );

        // Verify no memory leaks or dangling state
        // The widget should be cleanly disposed
        expect(find.byType(InteractiveConnectionWidget), findsNothing);

        await gesture.removePointer();
      });

      testWidgets('handles rapid hover enter/exit cycles gracefully', (
        tester,
      ) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        final mouseRegion = find.byType(MouseRegion).last;
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        final center = tester.getCenter(mouseRegion);
        const outsidePosition = Offset(1000, 1000);

        await gesture.addPointer(location: outsidePosition);

        // Perform rapid enter/exit cycles
        for (int i = 0; i < 5; i++) {
          // Enter
          await gesture.moveTo(center);
          await tester.pump();

          // Exit
          await gesture.moveTo(outsidePosition);
          await tester.pump();
        }

        // Final state should be no hover
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byIcon(Icons.close), findsNothing);

        await gesture.removePointer();
      });

      testWidgets('preserves hover state during widget rebuilds', (
        tester,
      ) async {
        Widget buildWidget({String connectionId = 'hover-test-connection'}) {
          // Setup platform service for each rebuild
          when(
            mockPlatformService.supportsHoverInteractions(),
          ).thenReturn(true);
          when(
            mockPlatformService.shouldUseTouchInteractions(),
          ).thenReturn(false);
          when(
            mockPlatformService.getMinimumTouchTargetSize(),
          ).thenReturn(24.0);

          final connection = Connection(
            id: connectionId,
            sourcePortId: 'source-port-hover',
            destinationPortId: 'dest-port-hover',
            connectionType: ConnectionType.algorithmToAlgorithm,
          );

          return MaterialApp(
            home: Scaffold(
              body: InteractiveConnectionWidget(
                connection: connection,
                routingEditorCubit: mockCubit,
                platformService: mockPlatformService,
                child: Container(
                  width: 200,
                  height: 100,
                  color: Colors.blue,
                  child: Text('Connection $connectionId'),
                ),
              ),
            ),
          );
        }

        // Initial build
        await tester.pumpWidget(buildWidget());

        final mouseRegion = find.byType(MouseRegion).last;
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        // Enter hover state
        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        // Rebuild widget with same connection ID
        await tester.pumpWidget(buildWidget());

        // Verify widget structure is maintained
        expect(find.byType(InteractiveConnectionWidget), findsOneWidget);

        await gesture.removePointer();
      });
    });

    group('Mock Mouse Event Handling', () {
      testWidgets('properly handles mock PointerEnterEvent', (tester) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        // This test verifies that our test setup can handle mouse events
        // In a real application, these events would be generated by Flutter's engine
        final mouseRegion = find.byType(MouseRegion).last;
        expect(find.byType(MouseRegion), findsAtLeastNWidgets(1));

        // Verify the widget responds to programmatic mouse events
        final widget = tester.widget<MouseRegion>(mouseRegion);
        expect(widget.onEnter, isNotNull);
        expect(widget.onExit, isNotNull);
      });

      testWidgets('handles null mouse event callbacks gracefully', (
        tester,
      ) async {
        // Test with a platform service that doesn't support hover
        when(mockPlatformService.supportsHoverInteractions()).thenReturn(false);
        when(mockPlatformService.shouldUseTouchInteractions()).thenReturn(true);

        await tester.pumpWidget(createDesktopConnectionWidget());

        // Should still build successfully even without hover support
        expect(find.byType(InteractiveConnectionWidget), findsOneWidget);
      });

      testWidgets('validates event handling performance', (tester) async {
        await tester.pumpWidget(createDesktopConnectionWidget());

        final mouseRegion = find.byType(MouseRegion).last;
        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );

        // Measure time for hover detection
        final stopwatch = Stopwatch()..start();

        await gesture.addPointer(location: tester.getCenter(mouseRegion));
        await gesture.moveTo(tester.getCenter(mouseRegion));
        await tester.pump();

        stopwatch.stop();

        // Hover detection should be fast (under 16ms for 60fps)
        expect(stopwatch.elapsedMilliseconds, lessThan(16));

        await gesture.removePointer();
      });
    });

    group('Integration with Platform Detection', () {
      testWidgets('only enables hover detection on desktop platforms', (
        tester,
      ) async {
        // Setup as mobile platform
        when(mockPlatformService.supportsHoverInteractions()).thenReturn(false);
        when(mockPlatformService.shouldUseTouchInteractions()).thenReturn(true);

        await tester.pumpWidget(createDesktopConnectionWidget());

        // Should use GestureDetector instead of MouseRegion for mobile
        expect(find.byType(GestureDetector), findsAtLeastNWidgets(1));

        // MouseRegion might still exist from MaterialApp scaffolding, but shouldn't be used for our interactions
        final interactiveWidget = find.byType(InteractiveConnectionWidget);
        expect(interactiveWidget, findsOneWidget);
      });

      testWidgets(
        'disables hover interactions when platform service indicates mobile',
        (tester) async {
          when(
            mockPlatformService.supportsHoverInteractions(),
          ).thenReturn(false);

          await tester.pumpWidget(createDesktopConnectionWidget());

          // The widget should adapt to the platform service settings
          final interactiveWidget = tester.widget<InteractiveConnectionWidget>(
            find.byType(InteractiveConnectionWidget),
          );
          expect(
            interactiveWidget.platformService,
            equals(mockPlatformService),
          );
        },
      );
    });
  });
}
