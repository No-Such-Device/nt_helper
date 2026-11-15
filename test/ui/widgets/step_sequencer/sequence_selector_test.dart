import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/sequence_selector.dart';

void main() {
  group('SequenceSelector Widget Tests', () {
    testWidgets('displays sequence options based on min/max values', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (_) {},
              minValue: 0,
              maxValue: 31,
            ),
          ),
        ),
      );

      // Find the dropdown
      final dropdown = find.byType(DropdownButtonFormField<int>);
      expect(dropdown, findsOneWidget);

      // Open dropdown
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Verify first few sequences are visible (numeric values)
      expect(find.text('0'), findsWidgets);
      expect(find.text('1'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('displays current sequence correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 5,
              isLoading: false,
              onSequenceChanged: (_) {},
              minValue: 0,
              maxValue: 31,
            ),
          ),
        ),
      );

      // Should display "5" (the raw value)
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('calls onSequenceChanged when selection changes', (
      tester,
    ) async {
      int? selectedSequence;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (sequence) {
                selectedSequence = sequence;
              },
              minValue: 0,
              maxValue: 31,
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      // Select "9" (hardware value 9)
      await tester.tap(find.text('9').last);
      await tester.pumpAndSettle();

      // Verify callback was called with correct value
      expect(selectedSequence, equals(9));
    });

    testWidgets('shows loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: true,
              onSequenceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify loading indicator is present
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Verify dropdown is disabled (onChanged should be null)
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(dropdown.onChanged, isNull);
    });

    testWidgets('hides loading indicator when isLoading is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify loading indicator is NOT present
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Verify dropdown is enabled
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(dropdown.onChanged, isNotNull);
    });

    testWidgets(
      'displays custom sequence names when provided via sequenceNames',
      (tester) async {
        final customNames = {0: 'Intro', 1: 'Verse', 2: 'Chorus'};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SequenceSelector(
                currentSequence: 0,
                isLoading: false,
                onSequenceChanged: (_) {},
                sequenceNames: customNames,
                minValue: 0,
                maxValue: 4,
              ),
            ),
          ),
        );

        // Open dropdown
        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();

        // Verify custom names are displayed
        expect(find.text('Intro'), findsWidgets);
        expect(find.text('Verse'), findsWidgets);
        expect(find.text('Chorus'), findsWidgets);

        // Verify unnamed sequences show numeric value fallback
        expect(find.text('3'), findsWidgets);
      },
    );

    testWidgets('displays enumStrings when provided', (tester) async {
      final enumStrings = ['Pattern A', 'Pattern B', 'Pattern C'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (_) {},
              enumStrings: enumStrings,
              minValue: 0,
              maxValue: 2,
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      // Verify enum strings are displayed
      expect(find.text('Pattern A'), findsWidgets);
      expect(find.text('Pattern B'), findsWidgets);
      expect(find.text('Pattern C'), findsWidgets);
    });

    testWidgets('dropdown disabled when isLoading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: true,
              onSequenceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify dropdown is disabled by checking onChanged is null
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(dropdown.onChanged, isNull);

      // Also verify loading indicator is present
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders correctly in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify widget renders without errors in dark mode
      expect(find.byType(SequenceSelector), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });

    testWidgets('renders correctly in light mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: SequenceSelector(
              currentSequence: 0,
              isLoading: false,
              onSequenceChanged: (_) {},
            ),
          ),
        ),
      );

      // Verify widget renders without errors in light mode
      expect(find.byType(SequenceSelector), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });
  });
}
