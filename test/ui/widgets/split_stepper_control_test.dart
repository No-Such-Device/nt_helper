import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/contextual_help_tooltip_scope.dart';
import 'package:nt_helper/ui/widgets/split_stepper_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpScopedSplitStepper(
    WidgetTester tester, {
    required bool contextualHelpEnabled,
  }) async {
    SharedPreferences.setMockInitialValues({
      'show_contextual_help': contextualHelpEnabled,
    });
    await SettingsService().init();

    await tester.pumpWidget(
      MaterialApp(
        home: ContextualHelpTooltipScope(
          child: Scaffold(
            body: Center(
              child: SplitStepperControl(
                label: 'Root',
                valueLabel: 'C3',
                onDecrement: () {},
                onIncrement: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> hoverOver(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(finder));
  }

  testWidgets(
    'compact split stepper renders two semantic buttons and fires callbacks',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var decrementCount = 0;
      var incrementCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SplitStepperControl(
                label: 'Root',
                valueLabel: 'C3',
                onDecrement: () => decrementCount++,
                onIncrement: () => incrementCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Decrease Root'), findsOneWidget);
      expect(find.byTooltip('Increase Root'), findsOneWidget);
      expect(find.bySemanticsLabel('Root'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Root')).value, 'C3');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Decrease Root'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byTooltip('Decrease Root'));
      await tester.tap(find.byTooltip('Increase Root'));

      expect(decrementCount, 1);
      expect(incrementCount, 1);
      semantics.dispose();
    },
  );

  testWidgets('large and small split stepper renders four ordered actions', (
    tester,
  ) async {
    final deltas = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SplitStepperControl.largeAndSmall(
              label: 'Trim start',
              valueLabel: '400 frames',
              smallStepLabel: '1',
              largeStepLabel: '100',
              smallStepSemanticsLabel: '1 frame',
              largeStepSemanticsLabel: '100 frames',
              onLargeDecrement: () => deltas.add(-100),
              onSmallDecrement: () => deltas.add(-1),
              onSmallIncrement: () => deltas.add(1),
              onLargeIncrement: () => deltas.add(100),
            ),
          ),
        ),
      ),
    );

    expect(find.text('−100'), findsOneWidget);
    expect(find.text('−1'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('+100'), findsOneWidget);
    expect(find.byTooltip('Decrease Trim start by 100 frames'), findsOneWidget);
    expect(find.byTooltip('Decrease Trim start by 1 frame'), findsOneWidget);
    expect(find.byTooltip('Increase Trim start by 1 frame'), findsOneWidget);
    expect(find.byTooltip('Increase Trim start by 100 frames'), findsOneWidget);

    await tester.tap(find.byTooltip('Decrease Trim start by 100 frames'));
    await tester.tap(find.byTooltip('Decrease Trim start by 1 frame'));
    await tester.tap(find.byTooltip('Increase Trim start by 1 frame'));
    await tester.tap(find.byTooltip('Increase Trim start by 100 frames'));

    expect(deltas, [-100, -1, 1, 100]);
  });

  testWidgets('contextual help setting shows visual tooltips when enabled', (
    tester,
  ) async {
    await pumpScopedSplitStepper(tester, contextualHelpEnabled: true);

    await hoverOver(tester, find.byTooltip('Increase Root'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Increase Root', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'contextual help setting suppresses visual tooltips when disabled without removing semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await pumpScopedSplitStepper(tester, contextualHelpEnabled: false);

        await hoverOver(tester, find.byTooltip('Increase Root'));
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text('Increase Root', findRichText: true), findsNothing);
        expect(find.bySemanticsLabel('Increase Root'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  , tags: ['regression']);

  testWidgets('contextual help toggle preserves descendant state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'show_contextual_help': true});
    await SettingsService().init();
    var disposeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ContextualHelpTooltipScope(
          child: Scaffold(
            body: _StatefulProbe(onDispose: () => disposeCount++),
          ),
        ),
      ),
    );

    await tester.tap(find.text('probe 0'));
    await tester.pump();
    expect(find.text('probe 1'), findsOneWidget);

    await SettingsService().setShowContextualHelp(false);
    await tester.pump();

    expect(disposeCount, 0);
    expect(find.text('probe 1'), findsOneWidget);

    await SettingsService().setShowContextualHelp(true);
    await tester.pump();

    expect(disposeCount, 0);
    expect(find.text('probe 1'), findsOneWidget);
  }, tags: ['regression']);

  testWidgets('split stepper supports keyboard focus activation', (
    tester,
  ) async {
    var decrementCount = 0;
    var incrementCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SplitStepperControl(
              label: 'Root',
              valueLabel: 'C3',
              onDecrement: () => decrementCount++,
              onIncrement: () => incrementCount++,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(decrementCount, 1);
    expect(incrementCount, 1);
  });
}

class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  var _value = 0;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => _value++),
      child: Text('probe $_value'),
    );
  }
}
