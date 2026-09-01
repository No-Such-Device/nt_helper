import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart' as state;
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_view.dart';

import 'bus_lanes_view_test.mocks.dart';

@GenerateMocks([RoutingEditorCubit])
void main() {
  setUpAll(() {
    provideDummy<state.RoutingEditorState>(
      const state.RoutingEditorStateInitial(),
    );
    provideDummy<BusAssignmentResult>(
      const BusAssignmentResult(
        algorithmIndex: 0,
        parameterNumber: 0,
        previousBusValue: 0,
        newBusValue: 0,
        reorder: null,
      ),
    );
    provideDummy<ReorderResult>(
      const ReorderResult(
        previousOrder: [],
        newOrder: [],
        description: '',
        changed: false,
      ),
    );
  });

  late MockRoutingEditorCubit cubit;

  setUp(() {
    cubit = MockRoutingEditorCubit();
    when(cubit.stream).thenAnswer((_) => const Stream.empty());
  });

  state.RoutingEditorStateLoaded loadedWith(
    List<state.RoutingAlgorithm> algorithms,
  ) => state.RoutingEditorStateLoaded(
    physicalInputs: const [],
    physicalOutputs: const [],
    algorithms: algorithms,
    connections: const [],
  );

  // One algorithm with a single output writing bus 13 (Add). With one used
  // bus the lane field shows 1..24, so bus 13 sits at column 13.
  state.RoutingAlgorithm oscWithOutput() => state.RoutingAlgorithm(
    id: 'algoA',
    index: 0,
    algorithm: Algorithm(algorithmIndex: 0, guid: 'a', name: 'Osc'),
    inputPorts: const [],
    outputPorts: const [
      Port(
        id: 'a_out',
        name: 'Out',
        type: PortType.audio,
        direction: PortDirection.output,
        busValue: 13,
        outputMode: OutputMode.add,
        parameterNumber: 3,
        modeParameterNumber: 5,
      ),
    ],
  );

  state.RoutingAlgorithm dualOutputsOnAdjacentBuses() => state.RoutingAlgorithm(
    id: 'algoDual',
    index: 0,
    algorithm: Algorithm(algorithmIndex: 0, guid: 'dual', name: 'Dual'),
    inputPorts: const [],
    outputPorts: const [
      Port(
        id: 'dual_out_13',
        name: 'Out 13',
        type: PortType.audio,
        direction: PortDirection.output,
        busValue: 13,
        outputMode: OutputMode.add,
        parameterNumber: 3,
        modeParameterNumber: 5,
      ),
      Port(
        id: 'dual_out_14',
        name: 'Out 14',
        type: PortType.audio,
        direction: PortDirection.output,
        busValue: 14,
        outputMode: OutputMode.add,
        parameterNumber: 4,
        modeParameterNumber: 6,
      ),
    ],
  );

  state.RoutingAlgorithm inPlaceOutputOnInputBus() => state.RoutingAlgorithm(
    id: 'algoInPlace',
    index: 0,
    algorithm: Algorithm(algorithmIndex: 0, guid: 'attn', name: 'Attn'),
    inputPorts: const [
      Port(
        id: 'attn_in',
        name: 'Input',
        type: PortType.audio,
        direction: PortDirection.input,
        busValue: 5,
        parameterNumber: 0,
        busParam: 'Input',
      ),
    ],
    outputPorts: const [
      Port(
        id: 'attn_out',
        name: 'Output',
        type: PortType.audio,
        direction: PortDirection.output,
        busValue: 5,
        outputMode: OutputMode.replace,
        parameterNumber: 1,
        busParam: 'Output',
      ),
    ],
  );

  List<state.RoutingAlgorithm> oversizedPreset() => [
    for (var index = 0; index < 10; index++)
      state.RoutingAlgorithm(
        id: 'algo_$index',
        index: index,
        algorithm: Algorithm(
          algorithmIndex: index,
          guid: 'oversized_$index',
          name: 'Algorithm $index',
        ),
        inputPorts: [
          Port(
            id: 'algo_${index}_in',
            name: 'Input',
            type: PortType.audio,
            direction: PortDirection.input,
            busValue: (index % 12) + 1,
            parameterNumber: index * 2,
            busParam: 'Input',
          ),
        ],
        outputPorts: [
          Port(
            id: 'algo_${index}_out',
            name: 'Output',
            type: PortType.audio,
            direction: PortDirection.output,
            busValue: 13 + (index % 8),
            outputMode: OutputMode.add,
            parameterNumber: index * 2 + 1,
            modeParameterNumber: 100 + index,
            busParam: 'Output',
          ),
        ],
      ),
  ];

  // Only bus 13 is in use, so it's column 1: gutter 172 + 1*42 + 21 = 235.
  // Output row 0 center y = header 28 + portRowY(0) 45 = 73.
  const beadCenter = Offset(235, 73);
  // None column 0 center: gutter 172 + 21 = 193.
  const noneCenter = Offset(193, 73);

  Widget host() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<RoutingEditorCubit>.value(
        value: cubit,
        child: const BusLanesView(),
      ),
    ),
  );

  Widget constrainedHost(Size size) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: BlocProvider<RoutingEditorCubit>.value(
          value: cubit,
          child: const BusLanesView(),
        ),
      ),
    ),
  );

  List<ScrollController> scrollControllers(WidgetTester tester) {
    return tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .map((view) => view.controller)
        .whereType<ScrollController>()
        .toList();
  }

  (ScrollController horizontal, ScrollController vertical) busLaneScrolls(
    WidgetTester tester,
  ) {
    final controllers = scrollControllers(tester);
    expect(controllers, hasLength(2));
    final vertical = controllers.firstWhere(
      (controller) => controller.position.axis == Axis.vertical,
    );
    final horizontal = controllers.firstWhere(
      (controller) => controller.position.axis == Axis.horizontal,
    );
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    expect(vertical.position.maxScrollExtent, greaterThan(0));
    return (horizontal, vertical);
  }

  Future<(ScrollController horizontal, ScrollController vertical)>
  pumpConstrainedOversizedPreset(WidgetTester tester) async {
    when(cubit.state).thenReturn(loadedWith(oversizedPreset()));

    await tester.pumpWidget(constrainedHost(const Size(320, 220)));
    await tester.pump();

    final scrolls = busLaneScrolls(tester);
    expect(scrolls.$1.offset, 0);
    expect(scrolls.$2.offset, 0);
    return scrolls;
  }

  Future<void> dragEmptyCanvas(
    WidgetTester tester, {
    required PointerDeviceKind kind,
  }) async {
    final gesture = await tester.createGesture(kind: kind);
    await gesture.down(const Offset(300, 18));
    await gesture.moveBy(const Offset(-100, -80));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('shows empty message when there are no algorithms', (
    tester,
  ) async {
    when(cubit.state).thenReturn(loadedWith(const []));
    await tester.pumpWidget(host());
    expect(find.text('No algorithms loaded.'), findsOneWidget);
  });

  testWidgets('renders lanes and a block for a loaded preset', (tester) async {
    when(cubit.state).thenReturn(loadedWith([oscWithOutput()]));
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.byType(BusLanesView), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bus picker opened from plus lane shows current and used lower buses',
    (tester) async {
      when(cubit.state).thenReturn(loadedWith([dualOutputsOnAdjacentBuses()]));
      when(
        cubit.busParameterRange(algorithmIndex: 0, parameterNumber: 4),
      ).thenReturn((min: 0, max: 64));

      await tester.pumpWidget(host());
      await tester.pump();

      // Visible buses are 13 and 14. The second output bead is on bus 14
      // at column 2, row 1. Dropping it one rail to the right lands on plus.
      await tester.dragFrom(const Offset(277, 99), const Offset(42, 0));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Current bus O2'), findsOneWidget);
      expect(find.text('O1'), findsOneWidget);
      expect(find.text('O2'), findsOneWidget);
    },
  );

  testWidgets('touch dragging empty bus lanes canvas pans the view', (
    tester,
  ) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);
    await dragEmptyCanvas(tester, kind: PointerDeviceKind.touch);

    expect(horizontal.offset, greaterThan(0));
    expect(vertical.offset, greaterThan(0));
  });

  testWidgets('mouse dragging empty bus lanes canvas pans the view', (
    tester,
  ) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);
    await dragEmptyCanvas(tester, kind: PointerDeviceKind.mouse);

    expect(horizontal.offset, greaterThan(0));
    expect(vertical.offset, greaterThan(0));
  });

  testWidgets('touch dragging painted lane content pans the view', (
    tester,
  ) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(const Offset(300, 73));
    await gesture.moveBy(const Offset(-100, -60));
    await gesture.up();
    await tester.pump();

    expect(horizontal.offset, greaterThan(0));
    expect(vertical.offset, greaterThan(0));
  });

  testWidgets('mouse dragging painted lane content pans the view', (
    tester,
  ) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(const Offset(300, 73));
    await gesture.moveBy(const Offset(-100, -60));
    await gesture.up();
    await tester.pump();

    expect(horizontal.offset, greaterThan(0));
    expect(vertical.offset, greaterThan(0));
  });

  testWidgets('dragging a bead does not pan the canvas', (tester) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
    await gesture.down(const Offset(235, 73));
    await gesture.moveBy(const Offset(-100, -60));
    await gesture.up();
    await tester.pump();

    expect(horizontal.offset, 0);
    expect(vertical.offset, 0);
  });

  testWidgets('scrollbars are laid out against the visible viewport', (
    tester,
  ) async {
    final (horizontal, vertical) = await pumpConstrainedOversizedPreset(tester);

    final horizontalScrollbar = find.byWidgetPredicate(
      (widget) => widget is Scrollbar && widget.controller == horizontal,
    );
    final verticalScrollbar = find.byWidgetPredicate(
      (widget) => widget is Scrollbar && widget.controller == vertical,
    );

    expect(tester.getSize(horizontalScrollbar), const Size(320, 220));
    expect(tester.getSize(verticalScrollbar), const Size(320, 220));
  });

  testWidgets('background pan does not trigger bus lane edit actions', (
    tester,
  ) async {
    await pumpConstrainedOversizedPreset(tester);

    await dragEmptyCanvas(tester, kind: PointerDeviceKind.touch);

    verifyNever(
      cubit.assignBusAndSolve(
        algorithmIndex: anyNamed('algorithmIndex'),
        parameterNumber: anyNamed('parameterNumber'),
        previousBusValue: anyNamed('previousBusValue'),
        busValue: anyNamed('busValue'),
      ),
    );
    verifyNever(cubit.togglePortOutputMode(portId: anyNamed('portId')));
    verifyNever(cubit.applyReorder(any));
  });

  testWidgets('dragging the gutter still reorders algorithms', (tester) async {
    when(cubit.state).thenReturn(loadedWith(oversizedPreset()));
    when(cubit.applyReorder(any)).thenAnswer(
      (_) async => const ReorderResult(
        previousOrder: ['algo_0', 'algo_1'],
        newOrder: ['algo_1', 'algo_0'],
        description: 'Moved Algorithm 0 down',
        changed: true,
      ),
    );

    await tester.pumpWidget(constrainedHost(const Size(320, 220)));
    await tester.pump();

    await tester.dragFrom(const Offset(24, 40), const Offset(0, 160));
    await tester.pumpAndSettle();

    verify(cubit.applyReorder(any)).called(1);
  });

  testWidgets('bus lanes canvas exposes semantics label and hint', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    when(cubit.state).thenReturn(loadedWith([oscWithOutput()]));

    await tester.pumpWidget(host());
    await tester.pump();

    expect(
      find.bySemanticsLabel(RegExp(r'Bus lanes canvas with 1 algorithm block')),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('double-tapping an output bead toggles the output mode', (
    tester,
  ) async {
    when(cubit.state).thenReturn(loadedWith([oscWithOutput()]));
    when(
      cubit.togglePortOutputMode(portId: anyNamed('portId')),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tapAt(beadCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(beadCenter);
    // Drain the double-tap recognizer's timers.
    await tester.pump(const Duration(seconds: 1));

    verify(cubit.togglePortOutputMode(portId: 'a_out')).called(1);
  });

  testWidgets('selecting a bead and pressing Delete disconnects it', (
    tester,
  ) async {
    when(cubit.state).thenReturn(loadedWith([oscWithOutput()]));
    when(
      cubit.assignBusAndSolve(
        algorithmIndex: anyNamed('algorithmIndex'),
        parameterNumber: anyNamed('parameterNumber'),
        previousBusValue: anyNamed('previousBusValue'),
        busValue: anyNamed('busValue'),
      ),
    ).thenAnswer(
      (_) async => const BusAssignmentResult(
        algorithmIndex: 0,
        parameterNumber: 3,
        previousBusValue: 13,
        newBusValue: 0,
        reorder: null,
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();

    // Single tap selects (pump past the double-tap window so onTap resolves).
    await tester.tapAt(beadCenter);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    verify(
      cubit.assignBusAndSolve(
        algorithmIndex: 0,
        parameterNumber: 3,
        previousBusValue: 13,
        busValue: 0,
      ),
    ).called(1);
  });

  testWidgets('dragging an output bead to the None column disconnects it', (
    tester,
  ) async {
    when(cubit.state).thenReturn(loadedWith([oscWithOutput()]));
    when(
      cubit.assignBusAndSolve(
        algorithmIndex: anyNamed('algorithmIndex'),
        parameterNumber: anyNamed('parameterNumber'),
        previousBusValue: anyNamed('previousBusValue'),
        busValue: anyNamed('busValue'),
      ),
    ).thenAnswer(
      (_) async => const BusAssignmentResult(
        algorithmIndex: 0,
        parameterNumber: 3,
        previousBusValue: 13,
        newBusValue: 0,
        reorder: null,
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();

    await tester.dragFrom(beadCenter, noneCenter - beadCenter);
    await tester.pumpAndSettle();

    verify(
      cubit.assignBusAndSolve(
        algorithmIndex: 0,
        parameterNumber: 3,
        previousBusValue: 13,
        busValue: 0,
      ),
    ).called(1);
  });

  testWidgets('dragging an in-place output bead assigns another bus', (
    tester,
  ) async {
    when(
      cubit.state,
    ).thenReturn(loadedWith([inPlaceOutputOnInputBus(), oscWithOutput()]));
    when(
      cubit.assignBusAndSolve(
        algorithmIndex: anyNamed('algorithmIndex'),
        parameterNumber: anyNamed('parameterNumber'),
        previousBusValue: anyNamed('previousBusValue'),
        busValue: anyNamed('busValue'),
      ),
    ).thenAnswer(
      (_) async => const BusAssignmentResult(
        algorithmIndex: 0,
        parameterNumber: 1,
        previousBusValue: 5,
        newBusValue: 13,
        reorder: null,
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();

    // Visible buses are 5 and 13. The first algorithm's output row is row 1,
    // so the bead starts on bus 5 at column 1 and drops onto bus 13 at column 2.
    await tester.dragFrom(const Offset(235, 99), const Offset(42, 0));
    await tester.pumpAndSettle();

    verify(
      cubit.assignBusAndSolve(
        algorithmIndex: 0,
        parameterNumber: 1,
        previousBusValue: 5,
        busValue: 13,
      ),
    ).called(1);
  });
}
