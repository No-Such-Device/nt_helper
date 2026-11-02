import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/routing/accessibility_colors.dart';
import 'package:nt_helper/ui/widgets/routing/accessible_routing_list_view.dart';

void main() {
  group('Routing Accessibility', () {
    group('AccessibilityColors', () {
      test('calculates contrast ratio between black and white', () {
        final ratio = AccessibilityColors.getContrastRatio(
          Colors.black,
          Colors.white,
        );
        expect(ratio, closeTo(21.0, 0.1));
      });

      test('identical colors have contrast ratio of 1', () {
        final ratio = AccessibilityColors.getContrastRatio(
          Colors.red,
          Colors.red,
        );
        expect(ratio, closeTo(1.0, 0.01));
      });

      test('meetsWCAGAA passes for black on white', () {
        expect(
          AccessibilityColors.meetsWCAGAA(Colors.black, Colors.white),
          isTrue,
        );
      });

      test('meetsWCAGAA fails for light grey on white', () {
        expect(
          AccessibilityColors.meetsWCAGAA(Colors.grey.shade300, Colors.white),
          isFalse,
        );
      });

      test('ensureContrast returns compliant color', () {
        final adjusted = AccessibilityColors.ensureContrast(
          Colors.grey.shade300,
          Colors.white,
        );
        final ratio = AccessibilityColors.getContrastRatio(
          adjusted,
          Colors.white,
        );
        expect(ratio, greaterThanOrEqualTo(4.5));
      });

      test('fromColorScheme produces all accessible colors', () {
        final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
        final colors = AccessibilityColors.fromColorScheme(scheme);

        // All connection colors should meet WCAG AA against surface
        expect(
          AccessibilityColors.getContrastRatio(
            colors.primaryConnection,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          AccessibilityColors.getContrastRatio(
            colors.audioPortColor,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          AccessibilityColors.getContrastRatio(
            colors.cvPortColor,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          AccessibilityColors.getContrastRatio(
            colors.gatePortColor,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          AccessibilityColors.getContrastRatio(
            colors.clockPortColor,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }, tags: ['regression']);

      test('fromColorScheme works with dark scheme', () {
        final scheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        );
        final colors = AccessibilityColors.fromColorScheme(scheme);

        expect(
          AccessibilityColors.getContrastRatio(
            colors.primaryConnection,
            scheme.surface,
          ),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('high contrast scheme produces higher contrast colors', () {
        final normalScheme = ColorScheme.fromSeed(seedColor: Colors.teal);
        final highContrastScheme = ColorScheme.fromSeed(
          seedColor: Colors.teal,
          contrastLevel: 1.0,
        );

        final normalColors = AccessibilityColors.fromColorScheme(normalScheme);
        final highContrastColors = AccessibilityColors.fromColorScheme(
          highContrastScheme,
        );

        // Selection indicator should meet AAA in high contrast
        final ratio = AccessibilityColors.getContrastRatio(
          highContrastColors.selectionIndicator,
          highContrastScheme.surface,
        );
        expect(ratio, greaterThanOrEqualTo(7.0));

        // Both should be valid, but we just verify they're accessible
        expect(
          AccessibilityColors.meetsWCAGAA(
            normalColors.focusIndicator,
            normalScheme.surface,
          ),
          isTrue,
        );
        expect(
          AccessibilityColors.meetsWCAGAA(
            highContrastColors.focusIndicator,
            highContrastScheme.surface,
          ),
          isTrue,
        );
      });
    });

    group('Accessible routing list view', () {
      testWidgets('announces algorithm and connection summaries', (
        tester,
      ) async {
        final semanticsHandle = tester.ensureSemantics();
        final cubit = _TestRoutingEditorCubit(_loadedState());

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<RoutingEditorCubit>.value(
              value: cubit,
              child: const Scaffold(body: AccessibleRoutingListView()),
            ),
          ),
        );

        expect(find.text('Algorithms (1)'), findsOneWidget);
        expect(find.text('Connections (1)'), findsOneWidget);
        expect(find.byTooltip('Delete this connection'), findsOneWidget);

        expect(
          find.bySemanticsLabel(
            RegExp(r'Slot 1: Bassline.*1 active connections'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Bassline: Audio Out to Bassline: CV In via Aux 1'),
          ),
          findsOneWidget,
        );

        semanticsHandle.dispose();
        await cubit.close();
      });

      testWidgets('renders an explicit empty connections message', (
        tester,
      ) async {
        final cubit = _TestRoutingEditorCubit(
          _loadedState(connections: const []),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<RoutingEditorCubit>.value(
              value: cubit,
              child: const Scaffold(body: AccessibleRoutingListView()),
            ),
          ),
        );

        expect(find.text('Connections (0)'), findsOneWidget);
        expect(
          find.text(
            'No connections. Use the canvas view to create connections between ports.',
          ),
          findsOneWidget,
        );

        await cubit.close();
      });
    });
  });
}

RoutingEditorState _loadedState({List<Connection>? connections}) {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'test',
    name: 'Bassline',
  );

  const inputPort = Port(
    id: 'algo_1_in',
    name: 'CV In',
    type: PortType.cv,
    direction: PortDirection.input,
    parameterNumber: 1,
  );

  const outputPort = Port(
    id: 'algo_1_out',
    name: 'Audio Out',
    type: PortType.audio,
    direction: PortDirection.output,
    parameterNumber: 2,
  );

  final defaultConnections = <Connection>[
    const Connection(
      id: 'conn_1',
      sourcePortId: 'algo_1_out',
      destinationPortId: 'algo_1_in',
      connectionType: ConnectionType.algorithmToAlgorithm,
      busNumber: 21,
      busLabel: 'Bus A1',
    ),
  ];

  return RoutingEditorState.loaded(
    physicalInputs: const [],
    physicalOutputs: const [],
    algorithms: [
      RoutingAlgorithm(
        id: 'algo_1',
        index: 0,
        algorithm: algorithm,
        inputPorts: const [inputPort],
        outputPorts: const [outputPort],
      ),
    ],
    connections: connections ?? defaultConnections,
  );
}

class _TestRoutingEditorCubit extends RoutingEditorCubit {
  _TestRoutingEditorCubit(RoutingEditorState initialState) : super(null) {
    emit(initialState);
  }
}
