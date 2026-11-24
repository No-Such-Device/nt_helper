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
