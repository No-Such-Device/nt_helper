import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/parameter_value_display.dart';
import 'package:nt_helper/ui/widgets/parameter_value_edit_traversal_scope.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  );
}

Widget _wrapTraversal(List<Widget> children) {
  return MaterialApp(
    home: Scaffold(
      body: ParameterValueEditTraversalScope(
        child: Column(
          children: [
            for (final child in children) SizedBox(width: 300, child: child),
          ],
        ),
      ),
    ),
  );
}

/// Helper to perform a double-tap and settle gesture timers.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('ParameterValueDisplay double-tap editing', () {
    testWidgets('1. Double-tap unit display enters edit mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 440,
            min: 0,
            max: 20000,
            name: 'Frequency',
            unit: 'Hz',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('440 Hz'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await _doubleTap(tester, find.text('440 Hz'));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('440 Hz'), findsNothing);
    });

    testWidgets('2. Double-tap raw integer enters edit mode', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 50,
            min: 0,
            max: 100,
            name: 'Level',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('50'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await _doubleTap(tester, find.text('50'));

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('3. Double-tap On/Off does NOT enter edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 1,
            min: 0,
            max: 1,
            name: 'Enabled',
            isOnOff: true,
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('4. Double-tap enum dropdown does NOT enter edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 0,
            min: 0,
            max: 2,
            name: 'Mode',
            dropdownItems: const ['Sine', 'Square', 'Saw'],
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      // DropdownMenu has its own TextField internally, that's expected.
      // Verify there's exactly one (the dropdown's), not an editing one.
      expect(find.byType(DropdownMenu<String>), findsOneWidget);
      final textFieldCount = tester.widgetList(find.byType(TextField)).length;
      expect(textFieldCount, 1); // Only the dropdown's internal TextField
    });

    testWidgets('5. Double-tap MIDI note does NOT enter edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 60,
            min: 0,
            max: 127,
            name: 'Note',
            unit: 'semitones',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.byType(TextField), findsNothing);

      // Find the Text widget showing the MIDI note name
      final textFinder = find.byType(Text).first;
      await _doubleTap(tester, textFinder);

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('6. Double-tap displayString does NOT enter edit mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 5,
            min: 0,
            max: 10,
            name: 'Preset',
            displayString: 'Cool Preset',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('Cool Preset'), findsOneWidget);

      await _doubleTap(tester, find.text('Cool Preset'));

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('7. TextField shows scaled value without unit', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 440,
            min: 0,
            max: 20000,
            name: 'Frequency',
            unit: 'Hz',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('440 Hz'));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '440');
    });

    testWidgets('8. TextField shows correct decimal value', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 4400,
            min: 0,
            max: 20000,
            name: 'Frequency',
            unit: 'Hz',
            powerOfTen: -1,
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('440.0 Hz'), findsOneWidget);

      await _doubleTap(tester, find.text('440.0 Hz'));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '440.0');
    });

    testWidgets('9. Enter submits and converts to raw value', (tester) async {
      int? submittedValue;
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 440,
            min: 0,
            max: 20000,
            name: 'Frequency',
            unit: 'Hz',
            widescreen: false,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('440 Hz'));

      await tester.enterText(find.byType(TextField), '880');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedValue, 880);
    });

    testWidgets('10. Value clamped to max', (tester) async {
      int? submittedValue;
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 50,
            min: 0,
            max: 100,
            name: 'Level',
            widescreen: false,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('50'));

      await tester.enterText(find.byType(TextField), '200');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedValue, 100);
    });

    testWidgets('11. Escape cancels without value change', (tester) async {
      int? submittedValue;
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 50,
            min: 0,
            max: 100,
            name: 'Level',
            widescreen: false,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('50'));

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '999');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(submittedValue, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('12. Focus loss submits value', (tester) async {
      int? submittedValue;
      // Use a second focusable widget so we can shift focus away
      final otherFocus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 300,
                  child: ParameterValueDisplay(
                    currentValue: 50,
                    min: 0,
                    max: 100,
                    name: 'Level',
                    widescreen: false,
                    onValueChanged: (v) => submittedValue = v,
                    onLongPress: () {},
                  ),
                ),
                TextField(focusNode: otherFocus),
              ],
            ),
          ),
        ),
      );

      await _doubleTap(tester, find.text('50'));

      await tester.enterText(find.byType(TextField).first, '75');

      // Focus the other text field to trigger focus loss
      otherFocus.requestFocus();
      await tester.pumpAndSettle();

      expect(submittedValue, 75);
      otherFocus.dispose();
    });

    testWidgets('13. Decimal round-trip', (tester) async {
      int? submittedValue;
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 5000,
            min: 0,
            max: 10000,
            name: 'Frequency',
            unit: 'Hz',
            powerOfTen: -2,
            widescreen: false,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
        ),
      );

      expect(find.text('50.00 Hz'), findsOneWidget);

      await _doubleTap(tester, find.text('50.00 Hz'));

      await tester.enterText(find.byType(TextField), '50.00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedValue, 5000);
    });

    testWidgets('14. After submit, returns to text display', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 50,
            min: 0,
            max: 100,
            name: 'Level',
            widescreen: false,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('50'));

      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      // Widget still shows old currentValue since parent didn't rebuild
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('15. Negative value support', (tester) async {
      int? submittedValue;
      await tester.pumpWidget(
        _wrap(
          ParameterValueDisplay(
            currentValue: 0,
            min: -100,
            max: 100,
            name: 'Pan',
            widescreen: false,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
        ),
      );

      await _doubleTap(tester, find.text('0'));

      await tester.enterText(find.byType(TextField), '-50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedValue, -50);
    });

    testWidgets('16. Tab submits and edits next numeric value', (tester) async {
      int? firstSubmitted;
      int? secondSubmitted;

      await tester.pumpWidget(
        _wrapTraversal([
          ParameterValueDisplay(
            currentValue: 10,
            min: 0,
            max: 100,
            name: 'Level A',
            widescreen: false,
            traversalId: 'a',
            traversalOrder: 0,
            onValueChanged: (v) => firstSubmitted = v,
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 20,
            min: 0,
            max: 100,
            name: 'Level B',
            widescreen: false,
            traversalId: 'b',
            traversalOrder: 1,
            onValueChanged: (v) => secondSubmitted = v,
            onLongPress: () {},
          ),
        ]),
      );

      await _doubleTap(tester, find.text('10'));
      await tester.enterText(find.byType(TextField), '15');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(firstSubmitted, 15);
      expect(secondSubmitted, isNull);
      expect(find.byType(TextField), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '20');
    });

    testWidgets('17. Shift+Tab submits and edits previous numeric value', (
      tester,
    ) async {
      int? firstSubmitted;
      int? secondSubmitted;

      await tester.pumpWidget(
        _wrapTraversal([
          ParameterValueDisplay(
            currentValue: 10,
            min: 0,
            max: 100,
            name: 'Level A',
            widescreen: false,
            traversalId: 'a',
            traversalOrder: 0,
            onValueChanged: (v) => firstSubmitted = v,
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 20,
            min: 0,
            max: 100,
            name: 'Level B',
            widescreen: false,
            traversalId: 'b',
            traversalOrder: 1,
            onValueChanged: (v) => secondSubmitted = v,
            onLongPress: () {},
          ),
        ]),
      );

      await _doubleTap(tester, find.text('20'));
      await tester.enterText(find.byType(TextField), '25');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(firstSubmitted, isNull);
      expect(secondSubmitted, 25);
      expect(find.byType(TextField), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '10');
    });

    testWidgets('18. Invalid text plus Tab navigates without submitting', (
      tester,
    ) async {
      int? submittedValue;

      await tester.pumpWidget(
        _wrapTraversal([
          ParameterValueDisplay(
            currentValue: 10,
            min: 0,
            max: 100,
            name: 'Level A',
            widescreen: false,
            traversalId: 'a',
            traversalOrder: 0,
            onValueChanged: (v) => submittedValue = v,
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 20,
            min: 0,
            max: 100,
            name: 'Level B',
            widescreen: false,
            traversalId: 'b',
            traversalOrder: 1,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ]),
      );

      await _doubleTap(tester, find.text('10'));
      await tester.enterText(find.byType(TextField), '-');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(submittedValue, isNull);
      expect(find.byType(TextField), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '20');
    });

    testWidgets('19. Traversal skips non-editable and disabled values', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapTraversal([
          ParameterValueDisplay(
            currentValue: 10,
            min: 0,
            max: 100,
            name: 'Level A',
            widescreen: false,
            traversalId: 'a',
            traversalOrder: 0,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 20,
            min: 0,
            max: 100,
            name: 'Display Only',
            displayString: 'Twenty',
            widescreen: false,
            traversalId: 'display-only',
            traversalOrder: 1,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 30,
            min: 0,
            max: 100,
            name: 'Disabled Level',
            widescreen: false,
            enabled: false,
            traversalId: 'disabled',
            traversalOrder: 2,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
          ParameterValueDisplay(
            currentValue: 40,
            min: 0,
            max: 100,
            name: 'Level D',
            widescreen: false,
            traversalId: 'd',
            traversalOrder: 3,
            onValueChanged: (_) {},
            onLongPress: () {},
          ),
        ]),
      );

      await _doubleTap(tester, find.text('10'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '40');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _doubleTap(tester, find.text('30'));
      expect(find.byType(TextField), findsNothing);
    });
  });
}
