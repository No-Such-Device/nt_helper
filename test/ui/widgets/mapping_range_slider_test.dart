import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/mapping_range_slider.dart';

class _Recorder {
  final List<String> changes = [];
  final List<String> ends = [];
}

class _Harness extends StatefulWidget {
  final int parameterMin;
  final int parameterMax;
  final int powerOfTen;
  final String? unitString;
  final int initialMin;
  final int initialMax;
  final _Recorder recorder;

  const _Harness({
    required this.parameterMin,
    required this.parameterMax,
    required this.powerOfTen,
    this.unitString,
    required this.initialMin,
    required this.initialMax,
    required this.recorder,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _min;
  late int _max;

  @override
  void initState() {
    super.initState();
    _min = widget.initialMin;
    _max = widget.initialMax;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MappingRangeSlider(
            minValue: _min,
            maxValue: _max,
            parameterMin: widget.parameterMin,
            parameterMax: widget.parameterMax,
            powerOfTen: widget.powerOfTen,
            unitString: widget.unitString,
            onChanged: (a, b) {
              setState(() {
                _min = a;
                _max = b;
              });
              widget.recorder.changes.add('$a,$b');
            },
            onChangeEnd: (a, b) {
              widget.recorder.ends.add('$a,$b');
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('MappingRangeSlider', () {
    testWidgets('renders slider and Min/Max labels', (tester) async {
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          initialMin: 10,
          initialMax: 90,
          recorder: _Recorder(),
        ),
      );
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Min: 10'), findsOneWidget);
      expect(find.text('Max: 90'), findsOneWidget);
    });

    testWidgets('double-tap Min opens editor; submit updates min', (
      tester,
    ) async {
      final rec = _Recorder();
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          initialMin: 10,
          initialMax: 90,
          recorder: rec,
        ),
      );

      await _doubleTap(tester, find.text('Min: 10'));
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(rec.changes, ['25,90']);
      expect(rec.ends, ['25,90']);
      expect(find.text('Min: 25'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('double-tap Max opens editor; submit updates max', (
      tester,
    ) async {
      final rec = _Recorder();
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          initialMin: 10,
          initialMax: 90,
          recorder: rec,
        ),
      );

      await _doubleTap(tester, find.text('Max: 90'));
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), '75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(rec.changes, ['10,75']);
      expect(find.text('Max: 75'), findsOneWidget);
    });

    testWidgets('Escape cancels without changing the value', (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          initialMin: 10,
          initialMax: 90,
          recorder: rec,
        ),
      );

      await _doubleTap(tester, find.text('Min: 10'));
      await tester.enterText(find.byType(TextField), '25');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(rec.changes, isEmpty);
      expect(find.text('Min: 10'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('min is clamped to the current max', (tester) async {
      final rec = _Recorder();
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          initialMin: 10,
          initialMax: 40,
          recorder: rec,
        ),
      );

      await _doubleTap(tester, find.text('Min: 10'));
      await tester.enterText(find.byType(TextField), '80');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 80 > current max (40), so clamp to 40.
      expect(rec.changes, ['40,40']);
    });

    testWidgets('scaled value (powerOfTen -2) edits via display units', (
      tester,
    ) async {
      final rec = _Recorder();
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: -2,
          initialMin: 0,
          initialMax: 100,
          recorder: rec,
        ),
      );

      // 0 -> "0.00", 100 -> "1.00"
      expect(find.text('Min: 0.00'), findsOneWidget);
      expect(find.text('Max: 1.00'), findsOneWidget);

      await _doubleTap(tester, find.text('Min: 0.00'));
      await tester.enterText(find.byType(TextField), '0.50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 0.50 / 0.01 = 50 raw.
      expect(rec.changes, ['50,100']);
      expect(find.text('Min: 0.50'), findsOneWidget);
    });

    testWidgets('unit string is shown as a suffix in the editor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(
          parameterMin: 0,
          parameterMax: 100,
          powerOfTen: 0,
          unitString: 'V',
          initialMin: 10,
          initialMax: 90,
          recorder: _Recorder(),
        ),
      );

      expect(find.text('Min: 10 V'), findsOneWidget);

      await _doubleTap(tester, find.text('Min: 10 V'));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.suffixText, 'V');
    });

    testWidgets('degenerate range (min == max) shows a label', (tester) async {
      await tester.pumpWidget(
        _Harness(
          parameterMin: 7,
          parameterMax: 7,
          powerOfTen: 0,
          initialMin: 7,
          initialMax: 7,
          recorder: _Recorder(),
        ),
      );
      expect(find.byType(RangeSlider), findsNothing);
      expect(find.text('Range: 7'), findsOneWidget);
    });
  });
}
