import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/bus_spec.dart';
import 'package:nt_helper/ui/widgets/routing/bus_picker_dialog.dart';
import 'package:nt_helper/ui/widgets/routing_parameter_value.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('RoutingParameterValue', () {
    testWidgets('renders current bus label and semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            onValueChanged: (_) {},
          ),
        ),
      );
      expect(find.text('O1'), findsOneWidget);
      expect(find.bySemanticsLabel('Output 1: O1'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('renders None when currentBus is 0', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 0,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            onValueChanged: (_) {},
          ),
        ),
      );
      expect(find.text('None'), findsOneWidget);
    });

    testWidgets(
      'tapping opens the bus picker and selecting a bus fires callback',
      (tester) async {
        int? selected;
        await tester.pumpWidget(
          _wrap(
            RoutingParameterValue(
              portLabel: 'Output 1',
              currentBus: 13,
              showEs5: false,
              hasExtendedAuxBuses: false,
              onValueChanged: (b) => selected = b,
            ),
          ),
        );

        // Open the picker by tapping the chip.
        await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(BusPickerDialog), findsOneWidget);

        // Select bus 14 (O2).
        await tester.tap(find.text('O2'));
        await tester.pumpAndSettle();

        expect(selected, 14);
      },
    );

    testWidgets('bus picker is bounded by the parameter range', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: BusSpec.outputMin,
            parameterMin: BusSpec.outputMin,
            parameterMax: BusSpec.outputMax,
            showEs5: false,
            hasExtendedAuxBuses: false,
            onValueChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BusPickerDialog), findsOneWidget);
      expect(find.text('Outputs'), findsOneWidget);
      expect(find.bySemanticsLabel('Current bus O1'), findsOneWidget);
      expect(find.text('O8'), findsOneWidget);
      expect(find.text('Inputs'), findsNothing);
      expect(find.text('Aux'), findsNothing);
      expect(find.text('I1'), findsNothing);
      expect(find.text('A1'), findsNothing);
    });

    testWidgets('disabled control does not open the picker', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            showEs5: false,
            hasExtendedAuxBuses: false,
            enabled: false,
            onValueChanged: (b) => selected = b,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BusPickerDialog), findsNothing);
      expect(selected, isNull);
    });

    testWidgets('shows ES-5 section when showEs5 is true', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            showEs5: true,
            hasExtendedAuxBuses: false,
            onValueChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('ES-5'), findsOneWidget);
      expect(find.text('ES-5 L'), findsOneWidget);
    });

    testWidgets('shows aux buses', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            showEs5: false,
            hasExtendedAuxBuses: false,
            onValueChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Aux'), findsOneWidget);
      expect(find.text('A1'), findsOneWidget);
    });

    testWidgets('does not show disconnect (x) when canDisconnect is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: false,
            onValueChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('does not show disconnect (x) when currentBus is already 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 0,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            onValueChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('tapping disconnect (x) fires onValueChanged with 0', (
      tester,
    ) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            onValueChanged: (b) => selected = b,
          ),
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(selected, 0);
    });

    testWidgets('disconnect (x) is hidden when disabled', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            enabled: false,
            onValueChanged: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('bus picker shows None tile when canDisconnect is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            onValueChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Two "None" texts: section header + tile.
      expect(find.text('None'), findsNWidgets(2));
    });

    testWidgets('bus picker hides None tile when canDisconnect is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: false,
            onValueChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('None'), findsNothing);
    });

    testWidgets('selecting None in the picker fires onValueChanged with 0', (
      tester,
    ) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          RoutingParameterValue(
            portLabel: 'Output 1',
            currentBus: 13,
            parameterMin: 0,
            showEs5: false,
            hasExtendedAuxBuses: false,
            canDisconnect: true,
            onValueChanged: (b) => selected = b,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.route_rounded), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Tap the None tile (the one inside the Wrap, not the header).
      final noneTiles = find.text('None');
      await tester.tap(noneTiles.at(1));
      await tester.pumpAndSettle();

      expect(selected, 0);
    });
  });
}
