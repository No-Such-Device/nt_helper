import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';

void main() {
  group('PortWidget', () {
    testWidgets('renders port with label on right by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Test Port',
              isInput: true,
              portId: 'test_port_1',
            ),
          ),
        ),
      );

      // Check that the port and label are rendered
      expect(find.text('Test Port'), findsOneWidget);
      expect(find.byType(Container), findsOneWidget);

      // Verify the port dot has correct decoration and size
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, equals(BoxShape.circle));

      // Check the actual rendered size
      final containerSize = tester.getSize(find.byType(Container));
      expect(containerSize.width, equals(12));
      expect(containerSize.height, equals(12));
    });

    testWidgets('renders input port with primary color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: PortWidget(
              label: 'Input Port',
              isInput: true,
              portId: 'input_port_1',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(ThemeData.light().colorScheme.primary));
    });

    testWidgets('renders output port with secondary color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: PortWidget(
              label: 'Output Port',
              isInput: false,
              portId: 'output_port_1',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(ThemeData.light().colorScheme.secondary));
    });

    testWidgets('positions label on left when specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Left Label',
              isInput: false,
              portId: 'left_label_port',
              labelPosition: PortLabelPosition.left,
            ),
          ),
        ),
      );

      // Find the Row widget that contains the port elements
      final rowWidget = tester.widget<Row>(find.byType(Row));
      expect(rowWidget.children.length, equals(3)); // label + spacer + dot

      // Verify order: first child should be Text (label)
      expect(rowWidget.children[0], isA<Text>());
      expect(rowWidget.children[1], isA<SizedBox>());
      expect(rowWidget.children[2], isA<Container>());

      // Verify label text
      final textWidget = rowWidget.children[0] as Text;
      expect(textWidget.data, equals('Left Label'));
    });

    testWidgets('positions label on right by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Right Label',
              isInput: true,
              portId: 'right_label_port',
            ),
          ),
        ),
      );

      // Find the Row widget that contains the port elements
      final rowWidget = tester.widget<Row>(find.byType(Row));
      expect(rowWidget.children.length, equals(3)); // dot + spacer + label

      // Verify order: first child should be Container (dot)
      expect(rowWidget.children[0], isA<Container>());
      expect(rowWidget.children[1], isA<SizedBox>());
      expect(rowWidget.children[2], isA<Text>());

      // Verify label text
      final textWidget = rowWidget.children[2] as Text;
      expect(textWidget.data, equals('Right Label'));
    });

    testWidgets('uses custom theme when provided', (tester) async {
      final customTheme = ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Colors.red,
          secondary: Colors.blue,
          outline: Colors.green,
        ),
        textTheme: const TextTheme(
          labelSmall: TextStyle(fontSize: 14, color: Colors.purple),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Custom Theme Port',
              isInput: true,
              portId: 'custom_theme_port',
              theme: customTheme,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.red));

      final text = tester.widget<Text>(find.text('Custom Theme Port'));
      expect(text.style?.color, equals(Colors.purple));
      expect(text.style?.fontSize, equals(14));
    });

    testWidgets('calls position resolved callback when portId is provided', (
      tester,
    ) async {
      String? resolvedPortId;
      Offset? resolvedPosition;
      bool? resolvedIsInput;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Callback Port',
              isInput: true,
              portId: 'callback_port_1',
              onPortPositionResolved: (portId, position, isInput) {
                resolvedPortId = portId;
                resolvedPosition = position;
                resolvedIsInput = isInput;
              },
            ),
          ),
        ),
      );

      // Trigger a frame and let the post-frame callback execute
      await tester.pumpAndSettle();
      await tester.pump();

      expect(resolvedPortId, equals('callback_port_1'));
      expect(resolvedPosition, isNotNull);
      expect(resolvedIsInput, equals(true));

      // Verify the position is reasonable (should be center of 12x12 dot)
      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);
      final containerRect = tester.getRect(containerFinder);
      final expectedCenter = containerRect.center;

      // Allow for some floating point tolerance
      expect((resolvedPosition!.dx - expectedCenter.dx).abs(), lessThan(1.0));
      expect((resolvedPosition!.dy - expectedCenter.dy).abs(), lessThan(1.0));
    });

    testWidgets('does not call position callback when portId is null', (
      tester,
    ) async {
      bool callbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'No Callback Port',
              isInput: false,
              // portId is null
              onPortPositionResolved: (portId, position, isInput) {
                callbackCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.pump();

      expect(callbackCalled, equals(false));
    });

    testWidgets('handles widget updates and recalls position callback', (
      tester,
    ) async {
      int callbackCount = 0;
      String? lastPortId;

      Widget buildWidget(String portId) {
        return MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Update Port',
              isInput: true,
              portId: portId,
              onPortPositionResolved: (portId, position, isInput) {
                callbackCount++;
                lastPortId = portId;
              },
            ),
          ),
        );
      }

      // Initial render
      await tester.pumpWidget(buildWidget('port_v1'));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(callbackCount, equals(1));
      expect(lastPortId, equals('port_v1'));

      // Update with new portId
      await tester.pumpWidget(buildWidget('port_v2'));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(callbackCount, equals(2));
      expect(lastPortId, equals('port_v2'));
    });

    group('PortLabelPosition enum', () {
      test('has correct values', () {
        expect(PortLabelPosition.values, hasLength(2));
        expect(PortLabelPosition.values, contains(PortLabelPosition.left));
        expect(PortLabelPosition.values, contains(PortLabelPosition.right));
      });
    });

    group('PortStyle enum', () {
      test('has correct values', () {
        expect(PortStyle.values, hasLength(2));
        expect(PortStyle.values, contains(PortStyle.dot));
        expect(PortStyle.values, contains(PortStyle.jack));
      });
    });

    testWidgets('renders jack style port correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Jack Port',
              isInput: true,
              portId: 'jack_port_1',
              style: PortStyle.jack,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that label and container are rendered
      expect(find.text('Jack Port'), findsOneWidget);

      // Jack style should render a Container with specific dimensions
      final containers = find.byType(Container);
      expect(
        containers,
        findsAtLeastNWidgets(1),
      ); // At least outer container and port dot

      // Check if we can find a PortWidget with the expected size
      final portWidget = find.byType(PortWidget);
      expect(portWidget, findsOneWidget);

      // Verify that we can find containers in the widget (there should be at least one)
      expect(containers.evaluate().length, greaterThanOrEqualTo(1));
    });

    testWidgets('handles tap callback correctly', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Tap Port',
              isInput: true,
              portId: 'tap_port_1',
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the port widget
      await tester.tap(find.byType(PortWidget));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('handles drag callbacks correctly', (tester) async {
      bool dragStarted = false;
      bool dragUpdated = false;
      bool dragEnded = false;
      Offset? dragUpdatePosition;
      Offset? dragEndPosition;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PortWidget(
              label: 'Drag Port',
              isInput: true,
              portId: 'drag_port_1',
              onDragStart: () {
                dragStarted = true;
              },
              onDragUpdate: (position) {
                dragUpdated = true;
                dragUpdatePosition = position;
              },
              onDragEnd: (position) {
                dragEnded = true;
                dragEndPosition = position;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Simulate drag gesture
      final portWidget = find.byType(PortWidget);
      await tester.dragFrom(tester.getCenter(portWidget), const Offset(50, 50));
      await tester.pumpAndSettle();

      expect(dragStarted, isTrue);
      expect(dragUpdated, isTrue);
      expect(dragEnded, isTrue);
      expect(dragUpdatePosition, isNotNull);
      expect(dragEndPosition, isNotNull);
    });

    testWidgets('maintains consistent visual spacing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PortWidget(
                  label: 'Port 1',
                  isInput: true,
                  portId: 'spacing_port_1',
                ),
                PortWidget(
                  label: 'Port 2',
                  isInput: false,
                  portId: 'spacing_port_2',
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final portWidgets = find.byType(PortWidget);
      expect(portWidgets, findsNWidgets(2));

      // Verify the ports have the expected vertical spacing by checking their sizes/positions
      final firstPortRect = tester.getRect(portWidgets.first);
      final secondPortRect = tester.getRect(portWidgets.last);

      // Each port should have vertical padding, so height should be label height + 8 (4+4 padding)
      expect(firstPortRect.height, greaterThan(8)); // Should include padding
      expect(secondPortRect.height, greaterThan(8)); // Should include padding
      expect(
        secondPortRect.top,
        greaterThanOrEqualTo(firstPortRect.bottom),
      ); // Second port below first
    });

    testWidgets('properly handles theme changes', (tester) async {
      Widget buildWithTheme(ThemeData theme) {
        return MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: PortWidget(
              label: 'Theme Test',
              isInput: true,
              portId: 'theme_test_port',
            ),
          ),
        );
      }

      // Start with light theme
      await tester.pumpWidget(buildWithTheme(ThemeData.light()));
      await tester.pumpAndSettle();

      final lightContainer = tester.widget<Container>(find.byType(Container));
      final lightDecoration = lightContainer.decoration as BoxDecoration;
      expect(
        lightDecoration.color,
        equals(ThemeData.light().colorScheme.primary),
      );

      // Switch to dark theme
      await tester.pumpWidget(buildWithTheme(ThemeData.dark()));
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(find.byType(Container));
      final darkDecoration = darkContainer.decoration as BoxDecoration;
      expect(
        darkDecoration.color,
        equals(ThemeData.dark().colorScheme.primary),
      );
    });
  });
}
