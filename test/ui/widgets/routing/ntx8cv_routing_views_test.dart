import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/es5_node.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_painter.dart';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/core/routing/models/es5_hardware_node.dart';
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
          child: RepaintBoundary(
            key: const ValueKey('evidence'),
            child: Scaffold(body: view),
          ),
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
        } else if (entry.key == 'lanes' || entry.key == 'table') {
          for (var i = 1; i <= 8; i++) {
            expect(find.byKey(ValueKey('ntx8cv_bus_$i')), findsOneWidget);
          }
          anchor = find.byKey(const ValueKey('ntx8cv_bus_1'));
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

  for (final entry in <String, Widget>{
    'table': const RoutingTableView(),
    'lanes': const BusLanesView(),
  }.entries) {
    for (final width in [390.0, 1200.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${entry.key}: AUX-aligned single row and stable settings geometry ($width, $scale)',
          (tester) async {
            final initial = (cubit.state as RoutingEditorStateLoaded).copyWith(
              ntx8cvRouting: null,
            );
            cubit.emit(initial);
            await pump(tester, entry.value);
            tester.view.physicalSize = Size(width, 900);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpAndSettle();
            final semantics = tester.ensureSemantics();
            final header = entry.key == 'table'
                ? tester.getRect(find.text('Algorithm').first)
                : null;
            final anchors = [
              for (var jack = 1; jack <= 8; jack++)
                tester.getRect(find.byKey(ValueKey('ntx8cv_bus_$jack'))),
            ];
            expect(find.bySemanticsLabel(RegExp(r'NTX-8CV 1:')), findsNothing);
            for (final next in [
              const Ntx8cvRouting.unresolved(),
              config,
              Ntx8cvRouting(
                mode: config.mode,
                channelEnables: config.channelEnables,
                available: false,
              ),
              Ntx8cvRouting(
                mode: Ntx8cvRoutingMode.audio32,
                channelEnables: BigInt.zero,
              ),
              Ntx8cvRouting(
                mode: Ntx8cvRoutingMode.audio16,
                channelEnables: BigInt.zero,
              ),
              config,
              null,
            ]) {
              cubit.emit(initial.copyWith(ntx8cvRouting: next));
              await tester.pumpAndSettle();
              if (header != null) {
                expect(tester.getRect(find.text('Algorithm').first), header);
              }
              expect(find.byType(Ntx8cvRoutingOutputs), findsNothing);
              expect(
                find.text('NTX-8CV'),
                next == null ? findsNothing : findsOneWidget,
              );
              final assignments = tester
                  .widgetList<Ntx8cvBusAssignment>(
                    find.byType(Ntx8cvBusAssignment),
                  )
                  .toList();
              expect(
                assignments.map((a) => a.jack),
                orderedEquals([1, 2, 3, 4, 5, 6, 7, 8]),
              );
              for (var jack = 1; jack <= 8; jack++) {
                final cell = find.byKey(ValueKey('ntx8cv_bus_$jack'));
                final rect = tester.getRect(cell);
                expect(rect, anchors[jack - 1]);
                if (next != null) {
                  expect(
                    find.descendant(of: cell, matching: find.text('$jack')),
                    findsOneWidget,
                  );
                  expect(
                    find.bySemanticsLabel(RegExp('NTX-8CV $jack: Aux $jack,')),
                    findsOneWidget,
                  );
                }
                if (jack > 1) {
                  expect(rect.left, greaterThan(anchors[jack - 2].left));
                }
                expect(
                  find.descendant(
                    of: cell,
                    matching: find.byIcon(Icons.circle_outlined),
                  ),
                  findsOneWidget,
                );
                expect(
                  find.descendant(of: cell, matching: find.byIcon(Icons.south)),
                  findsNothing,
                );
                expect(
                  find.descendant(of: cell, matching: find.byType(Container)),
                  findsNothing,
                );
                if (entry.key == 'table') {
                  final label = tester.getRect(find.text('A$jack').last);
                  // The cell starts immediately after the bottom AUX header row.
                  expect(rect.top, label.center.dy + 14);
                  expect(rect.center.dx, label.center.dx);
                } else {
                  final painter = tester
                      .widgetList<CustomPaint>(find.byType(CustomPaint))
                      .map((p) => p.painter)
                      .whereType<BusLanesPainter>()
                      .single;
                  final rail = painter.rails.singleWhere(
                    (r) => r.bus == 20 + jack,
                  );
                  expect(rect.center.dx, rail.x);
                  expect(rect.top, painter.metrics.contentHeight);
                  expect(
                    rail.segments.every(
                      (segment) =>
                          segment.bottom <= painter.metrics.railsBottom,
                    ),
                    isTrue,
                  );
                  final icon = tester.getRect(
                    find.descendant(
                      of: cell,
                      matching: find.byIcon(Icons.circle_outlined),
                    ),
                  );
                  expect(
                    icon.top,
                    greaterThanOrEqualTo(painter.metrics.contentHeight),
                  );
                }
              }
              expect(tester.takeException(), isNull);
            }
            semantics.dispose();
            verifyZeroInteractions(manager);
          },
        );
      }
    }
    testWidgets('${entry.key}: assignments survive an empty preset', (
      tester,
    ) async {
      cubit.emit(
        (cubit.state as RoutingEditorStateLoaded).copyWith(
          algorithms: const [],
          connections: const [],
        ),
      );
      await pump(tester, entry.value);
      expect(find.byType(Ntx8cvBusAssignment), findsNWidgets(8));
      expect(find.text('NTX-8CV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${entry.key}: visual evidence', (tester) async {
      const dir = String.fromEnvironment('NTX_EVIDENCE_DIR');
      if (dir.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('Roboto')
            ..addFont(
              File(const String.fromEnvironment('NTX_EVIDENCE_FONT'))
                  .readAsBytes()
                  .then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      await pump(tester, entry.value);
      expect(find.byType(Ntx8cvBusAssignment), findsNWidgets(8));
      if (dir.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('evidence')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await Directory(dir).create(recursive: true);
          await File('$dir/${entry.key}.png')
              .writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets(
    'graph title is only NTX-8CV and width matches the existing ES-5 node',
    (tester) async {
      await pump(
        tester,
        RoutingEditorWidget(
          loadNtxSettings: false,
          canvasSize: const Size(1200, 800),
        ),
      );
      final ntx = find.byKey(const ValueKey(Ntx8cvRouting.nodeId));
      expect(
        find.descendant(of: ntx, matching: find.text('NTX-8CV')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ntx, matching: find.textContaining('channels')),
        findsNothing,
      );
      final ntxNode = find.descendant(
        of: ntx,
        matching: find.byType(MovablePhysicalIONode),
      );
      final ntxSize = tester.getSize(ntxNode);
      await pump(
        tester,
        Center(
          child: ES5Node(
            ports: ES5HardwareNode.createInputPorts(
              deviceIoProfile: DeviceIoProfile.distingExtended,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(MovablePhysicalIONode)).width,
        closeTo(ntxSize.width, 0.001),
      );
      expect(config.scopeLabel, contains('channels 1–8'));
      expect(
        config.toJson(DeviceIoProfile.distingExtended)['scope'],
        'first_channel_group',
      );
    },
  );

  testWidgets('read-only Bus Lanes tap cannot delete a previously armed bead', (
    tester,
  ) async {
    await pump(tester, const BusLanesView());
    final sink = find.byKey(const ValueKey('ntx8cv_bus_1'));
    await tester.tap(sink);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    verifyZeroInteractions(manager);
    expect(tester.takeException(), isNull);
  });
}
