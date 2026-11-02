import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart' as state;
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'routing_editor_widget_test.mocks.dart';

@GenerateMocks([RoutingEditorCubit, DistingCubit])
void main() {
  setUpAll(() {
    // Provide dummy value for RoutingEditorState
    provideDummy<state.RoutingEditorState>(
      const state.RoutingEditorStateInitial(),
    );
  });

  group('RoutingEditorWidget Hover State', () {
    late MockRoutingEditorCubit mockRoutingCubit;
    late MockDistingCubit mockDistingCubit;

    setUp(() {
      mockRoutingCubit = MockRoutingEditorCubit();
      mockDistingCubit = MockDistingCubit();
    });

    

    testWidgets(
      'hides backward connections from canvas semantics when setting disabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'show_backward_connections': false,
        });
        await SettingsService().init();
        final semanticsHandle = tester.ensureSemantics();

        final loadedState = _loadedStateWithBackwardConnection();
        when(mockRoutingCubit.state).thenReturn(loadedState);
        when(
          mockRoutingCubit.stream,
        ).thenAnswer((_) => Stream.value(loadedState));

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<RoutingEditorCubit>.value(value: mockRoutingCubit),
                BlocProvider<DistingCubit>.value(value: mockDistingCubit),
              ],
              child: Scaffold(
                body: RoutingEditorWidget(canvasSize: const Size(800, 600)),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.bySemanticsLabel(
            RegExp(r'Routing canvas with 0 algorithm nodes and 1 connections'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'Connection: Output 1 to Input 1')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'Invalid connection:')),
          findsNothing,
        );
        semanticsHandle.dispose();
      },
    );
  });
}

state.RoutingEditorStateLoaded _loadedStateWithBackwardConnection() {
  return state.RoutingEditorStateLoaded(
    physicalInputs: const [
      Port(
        id: 'input_1',
        name: 'Input 1',
        type: PortType.cv,
        direction: PortDirection.input,
      ),
      Port(
        id: 'input_2',
        name: 'Input 2',
        type: PortType.cv,
        direction: PortDirection.input,
      ),
    ],
    physicalOutputs: const [
      Port(
        id: 'output_1',
        name: 'Output 1',
        type: PortType.cv,
        direction: PortDirection.output,
      ),
      Port(
        id: 'output_2',
        name: 'Output 2',
        type: PortType.cv,
        direction: PortDirection.output,
      ),
    ],
    algorithms: [],
    connections: const [
      Connection(
        id: 'normal',
        sourcePortId: 'output_1',
        destinationPortId: 'input_1',
        connectionType: ConnectionType.hardwareOutput,
      ),
      Connection(
        id: 'backward',
        sourcePortId: 'output_2',
        destinationPortId: 'input_2',
        connectionType: ConnectionType.hardwareOutput,
        isBackwardEdge: true,
      ),
    ],
    buses: [],
    portOutputModes: {},
    isHardwareSynced: true,
    isPersistenceEnabled: false,
    lastSyncTime: null,
    lastPersistTime: null,
    lastError: null,
  );
}
