import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/routing/accessible_routing_list_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_view.dart';
import 'package:nt_helper/ui/widgets/routing/movable_physical_io_node.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';
import 'package:nt_helper/ui/widgets/routing/ntx8cv_routing_outputs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers/cv_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  late _Disting disting;
  late _Manager manager;
  late RoutingEditorCubit cubit;
  late StreamController<DistingState> events;
  late Ntx8cvRouting config;
  late DistingStateSynchronized snapshot;
  late AppDatabase database;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });
  tearDownAll(() => database.close());
  setUp(() async {
    SharedPreferences.setMockInitialValues({'routing_view_mode': 'canvas'});
    await SettingsService().init();
    disting = _Disting();
    manager = _Manager();
    events = StreamController<DistingState>.broadcast(sync: true);
    config = Ntx8cvRouting(
      mode: Ntx8cvRoutingMode.cv,
      channelEnables: BigInt.from(0x85),
    );
    snapshot = DistingState.synchronized(
      disting: manager,
      distingVersion: '1.20beta',
      firmwareVersion: FirmwareVersion('1.20beta'),
      presetName: 'NTX view',
      algorithms: const [],
      slots: [
        cvSlot(0, outputs: [21, 23, 28]),
      ],
      unitStrings: const [],
    ) as DistingStateSynchronized;
    when(() => disting.state).thenAnswer((_) => snapshot);
    when(() => disting.ntx8cvRouting).thenAnswer((_) => config);
    when(() => disting.stream).thenAnswer((_) => events.stream);
    cubit = RoutingEditorCubit(disting);
  });
  tearDown(() async {
    await cubit.close();
    await events.close();
  });
  Future<void> pump(WidgetTester tester, Widget view) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<RoutingEditorCubit>.value(value: cubit),
            BlocProvider<DistingCubit>.value(value: disting),
          ],
          child: Scaffold(body: view),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void unavailable() {
    config = Ntx8cvRouting(
      mode: config.mode,
      channelEnables: config.channelEnables,
      available: false,
    );
    events.add(snapshot);
  }

  for (final entry in <String, Widget>{
    'canvas': RoutingEditorWidget(canvasSize: const Size(1200, 800)),
    'lanes': const BusLanesView(),
    'table': const RoutingTableView(),
    'list': const AccessibleRoutingListView(),
  }.entries) {
    testWidgets(
      '${entry.key}: eight stable jack identities, fixed holes, no routing controls',
      (tester) async {
        final semantics = tester.ensureSemantics();

        await pump(tester, entry.value);
        final loaded = cubit.state as RoutingEditorStateLoaded;
        expect(
          loaded.ntx8cvOutputs
              .where((p) => p.isActive)
              .map((p) => p.hardwareIndex),
          [1, 3, 8],
        );
        expect(find.textContaining('NTX-8CV'), findsWidgets);
        Rect before;
        Finder anchor;
        if (entry.key == 'canvas') {
          final node = find.byKey(const ValueKey(Ntx8cvRouting.nodeId));
          expect(node, findsOneWidget);
          final physical = tester.widget<MovablePhysicalIONode>(
            find.descendant(
              of: node,
              matching: find.byType(MovablePhysicalIONode),
            ),
          );
          expect(physical.ports, hasLength(8));
          expect(physical.onRoutingAction, isNull);
          expect(physical.onPortLongPress, isNull);
          final inputs = tester.widgetList<PortWidget>(
            find.descendant(of: node, matching: find.byType(PortWidget)),
          );
          expect(inputs.length, 8);
          expect(
            inputs.every(
              (p) => p.port!.effectiveRole == PortRole.expanderOutputBus,
            ),
            isTrue,
          );
          anchor = node;
        } else if (entry.key == 'lanes') {
          for (var i = 1; i <= 8; i++) {
            expect(find.byKey(ValueKey('ntx8cv_lane_$i')), findsOneWidget);
          }
          anchor = find.byKey(const ValueKey('ntx8cv_lane_1'));
        } else {
          for (var i = 1; i <= 8; i++) {
            expect(find.byKey(ValueKey('ntx8cv_summary_$i')), findsOneWidget);
          }
          anchor = find.byKey(const ValueKey('ntx8cv_summary_1'));
        }
        before = tester.getRect(anchor);
        unavailable();
        await tester.pumpAndSettle();
        expect(tester.getRect(anchor), before);
        expect(
          (cubit.state as RoutingEditorStateLoaded).ntx8cvOutputs.any(
            (p) => p.isActive,
          ),
          isFalse,
        );
        expect(
          (cubit.state as RoutingEditorStateLoaded).connections.where(
            (c) => c.destinationPortId.startsWith('ntx8cv_'),
          ),
          isEmpty,
        );
        verifyZeroInteractions(manager);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'NTX cable has no mode callback or label overlay; source editing remains available',
    (tester) async {
      snapshot = snapshot.copyWith(
        slots: [
          cvSlot(0, outputs: [21], modes: [OutputMode.add]),
          cvSlot(1, inputs: [21]),
        ],
      );
      events.add(snapshot);
      final writes = <int>[];
      when(
        () => disting.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      ).thenAnswer(
        (invocation) async =>
            writes.add(invocation.namedArguments[#value] as int),
      );
      await pump(
        tester,
        RoutingEditorWidget(
          loadNtxSettings: false,
          canvasSize: const Size(1200, 800),
        ),
      );
      var taps = 0;
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      )) {
        final painter = paint.painter;
        if (painter.runtimeType.toString() != '_ConnectionPainterWithBounds') {
          continue;
        }
        for (final dynamic data in (painter as dynamic).connections as List) {
          if (data.connection.destinationPortId == 'ntx8cv_out_1') {
            taps++;
            expect(data.onLabelTap, isNull);
          }
        }
      }
      expect(taps, greaterThan(0));
      final loaded = cubit.state as RoutingEditorStateLoaded;
      final tap = loaded.connections.firstWhere(
        (c) => c.destinationPortId == 'ntx8cv_out_1',
      );
      final ordinary = loaded.connections.firstWhere(
        (c) => c.destinationPortId == loaded.algorithms[1].inputPorts.first.id,
      );
      expect(find.byKey(ValueKey('connection-mode-${tap.id}')), findsNothing);
      expect(
        find.byKey(ValueKey('connection-mode-${ordinary.id}')),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      final port = (cubit.state as RoutingEditorStateLoaded)
          .algorithms
          .first
          .outputPorts
          .first;
      await cubit.togglePortOutputMode(portId: port.id);
      expect(writes, [1]);
      verifyZeroInteractions(manager);
    },
  );

  testWidgets(
    'actual Signal Flow viewport and headers stay fixed on first settings completion',
    (tester) async {
      final initial = (cubit.state as RoutingEditorStateLoaded).copyWith(
        ntx8cvRouting: null,
      );
      cubit.emit(initial);
      await pump(tester, const RoutingTableView());
      final frame = tester.widget<Ntx8cvRoutingFrame>(
        find.byType(Ntx8cvRoutingFrame),
      );
      final viewport = tester.getRect(find.byWidget(frame.child));
      final header = tester.getRect(find.text('Algorithm').first);
      for (final state in [
        initial.copyWith(ntx8cvRouting: const Ntx8cvRouting.unresolved()),
        initial.copyWith(ntx8cvRouting: config),
        initial.copyWith(ntx8cvRouting: const Ntx8cvRouting.unresolved()),
        initial,
      ]) {
        cubit.emit(state);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byWidget(frame.child)), viewport);
        expect(tester.getRect(find.text('Algorithm').first), header);
      }
    },
  );

  for (final width in [390.0, 960.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Signal Flow reserves endpoint area before discovery ($width, $scale)',
        (tester) async {
          await cubit.close();
          cubit = RoutingEditorCubit(null);
          final initial = RoutingEditorStateLoaded(
            physicalInputs: const [],
            physicalOutputs: const [],
            algorithms: const [],
            connections: const [],
          );
          cubit.emit(initial);
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: BlocProvider<RoutingEditorCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: Ntx8cvRoutingFrame(
                    child: Container(key: const ValueKey('flow-viewport')),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final viewport = tester.getRect(
            find.byKey(const ValueKey('flow-viewport')),
          );
          final semantics = tester.ensureSemantics();
          expect(find.bySemanticsLabel(RegExp(r'NTX-8CV 1:')), findsNothing);
          for (final config in [
            const Ntx8cvRouting.unresolved(),
            Ntx8cvRouting(
              mode: Ntx8cvRoutingMode.cv,
              channelEnables: BigInt.from(255),
            ),
            Ntx8cvRouting(
              mode: Ntx8cvRoutingMode.cv,
              channelEnables: BigInt.one,
              available: false,
            ),
            null,
          ]) {
            cubit.emit(initial.copyWith(ntx8cvRouting: config));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byKey(const ValueKey('flow-viewport'))),
              viewport,
            );
            expect(tester.takeException(), isNull);
          }
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('read-only Bus Lanes tap cannot delete a previously armed bead', (
    tester,
  ) async {
    await pump(tester, const BusLanesView());
    final sink = find.byKey(const ValueKey('ntx8cv_lane_1'));
    await tester.tap(sink);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    verifyZeroInteractions(manager);
    expect(tester.takeException(), isNull);
  });
}
