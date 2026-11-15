import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/ui/widgets/parameter_value_display.dart';

void main() {
  group('Widget Semantics', () {
    group('PortWidget', () {
      testWidgets(
        'announces disconnected output port with keyboard action hint',
        (tester) async {
          final semanticsHandle = tester.ensureSemantics();

          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: PortWidget(
                  label: 'Audio Out',
                  isInput: false,
                  portId: 'audio_out_1',
                ),
              ),
            ),
          );

          final node = tester.getSemantics(find.byType(PortWidget));
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.label, contains('Audio Out'));
          expect(data.label, contains('not connected'));
          expect(data.hint, contains('Press Space'));

          semanticsHandle.dispose();
        },
      );

      testWidgets('announces port type and connection state', (tester) async {
        final semanticsHandle = tester.ensureSemantics();

        const port = Port(
          id: 'test_port',
          name: 'Test Port',
          type: PortType.audio,
          direction: PortDirection.output,
          parameterNumber: 0,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PortWidget(
                label: 'Test Port',
                isInput: false,
                portId: 'test_port',
                port: port,
                isConnected: true,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(PortWidget));
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.label, contains('Test Port'));
        expect(data.label, contains('Audio Output'));
        expect(data.label, contains('connected'));
        expect(data.hint, contains('Long press'));

        semanticsHandle.dispose();
      });
    });

    group('ParameterValueDisplay', () {
      testWidgets('announces On/Off values', (tester) async {
        final semanticsHandle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterValueDisplay(
                currentValue: 1,
                min: 0,
                max: 1,
                name: 'Bypass',
                isOnOff: true,
                widescreen: false,
                onValueChanged: _noopOnValueChanged,
                onLongPress: _noopOnLongPress,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(ParameterValueDisplay));
        final data = node.getSemanticsData();
        expect(data.label, contains('Bypass: On'));
        expect(data.flagsCollection.isToggled == Tristate.isTrue, isTrue);

        semanticsHandle.dispose();
      });

      testWidgets('announces note values in a live region', (tester) async {
        final semanticsHandle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterValueDisplay(
                currentValue: 60,
                min: 0,
                max: 127,
                name: 'Root Note',
                widescreen: false,
                onValueChanged: _noopOnValueChanged,
                onLongPress: _noopOnLongPress,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(ParameterValueDisplay));
        final data = node.getSemanticsData();
        expect(data.label, contains('Root Note'));
        expect(data.label, contains('C4'));
        expect(data.flagsCollection.isLiveRegion, isTrue);

        semanticsHandle.dispose();
      });

      testWidgets('announces enumerated parameter labels and selected value', (
        tester,
      ) async {
        final semanticsHandle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterValueDisplay(
                currentValue: 1,
                min: 0,
                max: 2,
                name: 'Mode',
                dropdownItems: ['Off', 'On', 'Auto'],
                widescreen: false,
                onValueChanged: _noopOnValueChanged,
                onLongPress: _noopOnLongPress,
              ),
            ),
          ),
        );

        final node = tester.getSemantics(find.byType(ParameterValueDisplay));
        final data = node.getSemanticsData();
        expect(data.label, contains('Mode'));
        expect(data.value, contains('On'));

        semanticsHandle.dispose();
      });

      testWidgets('labels inline numeric edit fields', (tester) async {
        final semanticsHandle = tester.ensureSemantics();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParameterValueDisplay(
                currentValue: 50,
                min: 0,
                max: 100,
                name: 'Frequency',
                unit: 'Hz',
                widescreen: false,
                onValueChanged: _noopOnValueChanged,
                onLongPress: _noopOnLongPress,
              ),
            ),
          ),
        );

        await tester.tap(find.text('50 Hz'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('50 Hz'));
        await tester.pumpAndSettle();

        final editSemantics = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .map((widget) => widget.properties.label)
            .whereType<String>();
        expect(editSemantics, contains('Edit Frequency value'));

        semanticsHandle.dispose();
      });
    });
  });
}

void _noopOnValueChanged(int _) {}

void _noopOnLongPress() {}
