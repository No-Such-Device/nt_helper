import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/rendering.dart';
import 'package:drift/native.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/routing/algorithm_node_widget.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';
import 'package:nt_helper/ui/widgets/mapping_editor_bottom_sheet.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/routing/accessible_routing_list_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_painter.dart';
import 'package:nt_helper/ui/widgets/routing/cv_modulation_view.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers/cv_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

class _Midi extends Mock implements MidiListenerCubit {}

class _CvCanvas extends Fake implements Canvas {
  final paths = <Path>[];
  final circles = <(Offset, double)>[];
  @override
  void drawPath(Path path, Paint paint) => paths.add(path);
  @override
  void drawCircle(Offset center, double radius, Paint paint) =>
      circles.add((center, radius));
}

void main() {
  late _Disting disting;
  late _Manager manager;
  late _Midi midi;
  late StreamController<DistingState> events;
  late RoutingEditorCubit cubit;
  late DistingStateSynchronized snapshot;
  final source = cvSlot(0, outputs: [32, 33]);
  final target = cvSlot(1, cvBuses: [32, 33]);

  late AppDatabase database;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(PackedMappingData.filler());
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });
  tearDownAll(() => database.close());

  setUp(() async {
    SharedPreferences.setMockInitialValues({'routing_view_mode': 'canvas'});
    await SettingsService().init();
    disting = _Disting();
    manager = _Manager();
    midi = _Midi();
    when(() => midi.state).thenReturn(const MidiListenerState.data());
    when(() => midi.stream).thenAnswer((_) => const Stream.empty());
    events = StreamController<DistingState>.broadcast(sync: true);
    snapshot = DistingState.synchronized(
      disting: manager,
      distingVersion: '1.20beta',
      firmwareVersion: FirmwareVersion('1.20beta'),
      presetName: 'CV fixture',
      algorithms: const [],
      slots: [source, target],
      unitStrings: const [],
    ) as DistingStateSynchronized;
    when(() => disting.state).thenAnswer((_) => snapshot);
    when(() => disting.stream).thenAnswer((_) => events.stream);
    cubit = RoutingEditorCubit(disting);
  });
  tearDown(() async {
    await cubit.close();
    await events.close();
  });

  Future<void> pump(WidgetTester tester, Widget view, {Key? captureKey}) async {
    await cubit.close();
    cubit = RoutingEditorCubit(disting);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<RoutingEditorCubit>.value(value: cubit),
            BlocProvider<DistingCubit>.value(value: disting),
            BlocProvider<MidiListenerCubit>.value(value: midi),
          ],
          child: Scaffold(
            body: RepaintBoundary(key: captureKey, child: view),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  void setTarget(Slot slot) {
    snapshot = snapshot.copyWith(slots: [source, slot]);
    events.add(snapshot);
  }

  void pressInspect(WidgetTester tester, CvModulationButton button) {
    final parent = find.byWidget(button);
    if (button.standardInput) {
      tester
          .widget<PortWidget>(
            find.descendant(of: parent, matching: find.byType(PortWidget)),
          )
          .onTap!();
    } else {
      tester
          .widget<TextButton>(
            find.descendant(of: parent, matching: find.byType(TextButton)),
          )
          .onPressed!();
    }
  }

  Offset portCenter(WidgetTester tester, String id) {
    final port = find.byWidgetPredicate(
      (w) => w is PortWidget && w.portId == id,
    );
    final dot = tester
        .widgetList<Container>(
          find.descendant(of: port, matching: find.byType(Container)),
        )
        .firstWhere((w) => w.key is GlobalKey && w.constraints?.maxWidth == 12);
    return tester.getCenter(find.byWidget(dot));
  }

  final views = <String, Widget>{
    'canvas': RoutingEditorWidget(canvasSize: const Size(1000, 700)),
    'lanes': const BusLanesView(),
    'table': const RoutingTableView(),
    'list': const AccessibleRoutingListView(),
  };
  for (final entry in views.entries) {
    testWidgets(
      '${entry.key} exposes identical distinct CV targets with scoped activation',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, entry.value);
        if (entry.key == 'list') {
          await tester.tap(find.text(target.algorithm.name));
          await tester.pump();
          await tester.pumpAndSettle();
        }
        final expected = (cubit.state as RoutingEditorStateLoaded)
            .algorithms
            .last
            .cvModulations;
        final buttons = tester.widgetList<CvModulationButton>(
          find.byType(CvModulationButton),
        );
        expect(
          buttons.expand((b) => b.mappings).map((m) => m.id).toSet(),
          expected.map((m) => m.id).toSet(),
        );
        if (entry.key == 'canvas') {
          expect(
            tester
                .widgetList<AlgorithmNodeWidget>(
                  find.byType(AlgorithmNodeWidget),
                )
                .map((w) => w.algorithmName),
            contains(target.algorithm.name),
          );
          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<CvModulationCurve>()
              .single;
          expect(painter.endpoints, hasLength(2));
        }
        expect(
          find.bySemanticsLabel(RegExp('Slot 1: Step 0 - Step output 1')),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              entry.key == 'lanes' || entry.key == 'table'
                  ? 'Edit .*mapping'
                  : 'Inspect CV modulation:',
            ),
          ),
          findsWidgets,
        );
        // The same native keyboard-activatable inspect action is used by every adapter.
        pressInspect(tester, buttons.firstWhere((b) => b.mappings.isNotEmpty));
        await tester.pump();
        await tester.pumpAndSettle();
        if (entry.key == 'lanes' || entry.key == 'table') {
          final editor = tester.widget<MappingEditorBottomSheet>(
            find.byType(MappingEditorBottomSheet),
          );
          expect(editor.algorithmIndex, 1);
          expect(editor.parameterNumber, 0);
          expect(editor.data, snapshot.slots[1].mappings[0].packedMappingData);
          expect(find.byType(AlertDialog), findsNothing);
          await tester.tap(find.byTooltip('Close'));
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.text(
              'Slot 1: Step 0 - Step output 1 → Slot 2: MIDI CC Generator 1 - Main: CC 1',
            ),
            findsWidgets,
          );
          expect(find.textContaining('Configured modulation'), findsNothing);
          expect(find.text('Delete'), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(MappingEditorBottomSheet), findsNothing);
        verifyZeroInteractions(manager);
        verifyNever(
          () => disting.updateParameterValue(
            algorithmIndex: any(named: 'algorithmIndex'),
            parameterNumber: any(named: 'parameterNumber'),
            value: any(named: 'value'),
            userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
          ),
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('mapping refresh preserves canvas node rectangles and anchors', (
    tester,
  ) async {
    setTarget(cvSlot(1, cvBuses: [0, 0]));
    await pump(tester, views['canvas']!);
    final before = tester.getRect(find.byType(AlgorithmNodeWidget).first);
    setTarget(target);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AlgorithmNodeWidget).first), before);
    final targetBefore = tester.getRect(find.byType(AlgorithmNodeWidget).last);
    setTarget(cvSlot(1, cvBuses: [33, 32]));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AlgorithmNodeWidget).last), targetBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mapping-only lanes append without moving ordinary beads', (
    tester,
  ) async {
    final noMappings = cvSlot(1, cvBuses: [0, 0]);
    snapshot = snapshot.copyWith(
      slots: [
        cvSlot(0, outputs: [13]),
        noMappings,
      ],
    );
    events.add(snapshot);
    await pump(tester, views['lanes']!);
    final before = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<BusLanesPainter>()
        .single;
    final x = before.rails.single.x;
    snapshot = snapshot.copyWith(slots: [snapshot.slots.first, target]);
    events.add(snapshot);
    expect(
      (cubit.state as RoutingEditorStateLoaded).algorithms.last.cvModulations,
      hasLength(2),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final after = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<BusLanesPainter>()
        .single;
    expect(after.rails.firstWhere((r) => r.bus == 13).x, x);
    expect(after.metrics.cardTops, before.metrics.cardTops);
    expect(after.rails.map((r) => r.bus), [13, 32, 33]);
  });

  testWidgets(
    'table header and row geometry stay fixed during mapping refresh',
    (tester) async {
      setTarget(cvSlot(1, cvBuses: [0, 0]));
      await pump(tester, views['table']!);
      final title = find.text('2. ${target.algorithm.name}');
      final rect = tester.getRect(title);
      final header = tester.getRect(find.text('Algorithm').first);
      setTarget(target);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.getRect(title), rect);
      expect(tester.getRect(find.text('Algorithm').first), header);
    },
  );

  testWidgets(
    'open inspector marks removed mappings unavailable without resizing',
    (tester) async {
      await pump(tester, views['canvas']!);
      pressInspect(
        tester,
        tester
            .widgetList<CvModulationButton>(find.byType(CvModulationButton))
            .firstWhere((b) => b.standardInput),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(AlertDialog));
      setTarget(cvSlot(1, cvBuses: [0, 0]));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('mapping no longer available'),
        findsOneWidget,
      );
      expect(tester.getRect(find.byType(AlertDialog)), before);
      verifyZeroInteractions(manager);
    },
  );

  testWidgets('CV editor clears a selected ordinary bead before Delete', (
    tester,
  ) async {
    when(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
    await pump(tester, views['lanes']!);
    final bead = find.byWidgetPredicate((w) => w is Draggable).first;
    await tester.tap(bead);
    await tester.pump();
    tester
        .widget<TextButton>(
          find
              .descendant(
                of: find.byType(CvModulationButton),
                matching: find.byType(TextButton),
              )
              .first,
        )
        .onPressed!();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    verifyNever(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    );
  });

  testWidgets('out-of-profile CV editor also clears the armed ordinary bead', (
    tester,
  ) async {
    snapshot = snapshot.copyWith(
      deviceIoProfile: DeviceIoProfile.distingLegacy,
      slots: [
        cvSlot(0, outputs: [13]),
        cvSlot(1, cvBuses: [64]),
      ],
    );
    when(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
    await pump(tester, views['lanes']!);
    await tester.tap(find.byWidgetPredicate((w) => w is Draggable).first);
    await tester.pump();
    await tester.tap(find.byType(CvModulationButton).first);
    await tester.pumpAndSettle();
    expect(find.byType(MappingEditorBottomSheet), findsOneWidget);
    expect(
      tester
          .widget<MappingEditorBottomSheet>(
            find.byType(MappingEditorBottomSheet),
          )
          .data
          .cvInput,
      64,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    verifyNever(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    );
    verifyZeroInteractions(manager);
  });

  testWidgets('CV inspect supports Tab, Enter, Escape and focus return', (
    tester,
  ) async {
    final mappings =
        (cubit.state as RoutingEditorStateLoaded).algorithms.last.cvModulations;
    await pump(tester, Center(child: CvModulationButton(mappings: mappings)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(FocusManager.instance.primaryFocus, focus);
    verifyZeroInteractions(manager);
  });

  for (final viewName in ['canvas', 'lanes']) {
    testWidgets(
      '$viewName keeps every parameter named with distinct input anchors',
      (tester) async {
        setTarget(
          cvSlot(
            1,
            cvBuses: [32, 32, 33, 32],
            cvNames: ['Pitch', 'Pitch', 'Velocity', 'Gate'],
          ),
        );
        await pump(tester, views[viewName]!);
        final targets = tester
            .widgetList<CvModulationButton>(find.byType(CvModulationButton))
            .where((b) => b.endpointKey != null)
            .toList();
        expect(targets, hasLength(4));
        expect(
          targets.map((b) => b.displayLabel),
          containsAll([
            'Main: Pitch (p0)',
            'Main: Pitch (p1)',
            'Main: Velocity',
            'Main: Gate',
          ]),
        );
        if (viewName == 'canvas') {
          for (final name in [
            'Main: Pitch (p0)',
            'Main: Pitch (p1)',
            'Main: Velocity',
            'Main: Gate',
          ]) {
            expect(find.text(name), findsOneWidget);
          }
          final inputs = tester
              .widgetList<PortWidget>(find.byType(PortWidget))
              .where(
                (p) => p.interactionKind == PortInteractionKind.cvModulation,
              );
          expect(inputs, hasLength(4));
          expect(
            inputs.every(
              (p) =>
                  p.isInput &&
                  p.onDragStart == null &&
                  p.onLongPress == null &&
                  p.onRoutingAction == null &&
                  p.port == null,
            ),
            isTrue,
          );
        } else {
          final painter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((w) => w.painter)
              .whereType<BusBlockPainter>()
              .singleWhere(
                (p) => p.ports.any((r) => r.kind == PortRowKind.cvModulation),
              );
          final inputs = painter.ports.where(
            (r) => r.kind == PortRowKind.cvModulation,
          );
          expect(inputs.map((r) => r.label), [
            'Main: Pitch (p0)',
            'Main: Pitch (p1)',
            'Main: Velocity',
            'Main: Gate',
          ]);
          expect(
            inputs.every(
              (r) =>
                  !r.isOutput &&
                  r.directionGlyph.isEmpty &&
                  r.write == BandWrite.none,
            ),
            isTrue,
          );
          expect(
            inputs.every(
              (r) =>
                  BusLanesMetrics.portRowY(r.row) > BusLanesMetrics.titleHeight,
            ),
            isTrue,
          );
        }
        final centers = [
          for (final b in targets) tester.getCenter(find.byKey(b.endpointKey!)),
        ];
        expect(centers.map((c) => c.dy).toSet(), hasLength(4));
        final targetAlgorithm =
            (cubit.state as RoutingEditorStateLoaded).algorithms.last;
        final pathPainters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((w) => w.painter is CvModulationCurve)
            .toList();
        final canvasEnds = <Offset>[];
        for (final paint in pathPainters) {
          final box = tester.renderObject<RenderBox>(find.byWidget(paint));
          canvasEnds.addAll(
            (paint.painter! as CvModulationCurve).endpoints.map(
              (e) => box.localToGlobal(e.$2),
            ),
          );
        }
        for (final center in centers) {
          expect(
            canvasEnds.any((end) => (end - center).distance < 0.1),
            isTrue,
          );
        }
        if (viewName == 'canvas') {
          final paths =
              (pathPainters.single.painter! as CvModulationCurve).endpoints;
          expect(paths, hasLength(4));
          expect(paths[0].$1, paths[1].$1);
          expect(paths[0].$1, paths[3].$1);
          expect(paths[0].$1, isNot(paths[2].$1));
        }
        final before = [
          for (final b in targets) tester.getRect(find.byKey(b.endpointKey!)),
        ];
        final beforeNodes = viewName == 'canvas'
            ? tester.getRect(find.byType(AlgorithmNodeWidget).last)
            : tester.getRect(find.byKey(ValueKey(targetAlgorithm.id)));
        final updated = snapshot.slots.last.copyWith(
          values: [
            for (final value in snapshot.slots.last.values)
              ParameterValue(
                algorithmIndex: value.algorithmIndex,
                parameterNumber: value.parameterNumber,
                value: value.value + 1,
              ),
          ],
        );
        setTarget(updated);
        await tester.pumpAndSettle();
        for (var i = 0; i < targets.length; i++) {
          expect(
            tester.getRect(find.byKey(targets[i].endpointKey!)),
            before[i],
          );
        }
        expect(
          viewName == 'canvas'
              ? tester.getRect(find.byType(AlgorithmNodeWidget).last)
              : tester.getRect(find.byKey(ValueKey(targetAlgorithm.id))),
          beforeNodes,
        );
        // Re-publication of the same snapshot must not move any virtual input.
        setTarget(updated);
        await tester.pumpAndSettle();
        for (var i = 0; i < targets.length; i++) {
          expect(
            tester.getRect(find.byKey(targets[i].endpointKey!)),
            before[i],
          );
        }
        verifyZeroInteractions(manager);
      },
    );
  }

  testWidgets(
    'graph draws a raw-bus CV input with the ordinary unconnected bus geometry',
    (tester) async {
      const captureKey = ValueKey('graph capture');
      const viewport = Size(1100, 650);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(viewport);
      snapshot = snapshot.copyWith(
        slots: [
          cvSlot(0, outputs: [32]),
          cvSlot(
            1,
            inputs: [34],
            cvBuses: [34, 32],
            cvNames: ['Unwired cutoff', 'Mapped resonance'],
          ),
        ],
      );
      await pump(
        tester,
        RoutingEditorWidget(canvasSize: viewport, showPhysicalPorts: false),
        captureKey: captureKey,
      );
      final state = cubit.state as RoutingEditorStateLoaded;
      final destination = state.algorithms.last;
      await cubit.updateMultipleNodePositions({
        state.algorithms.first.id: const Offset(2120, 2315),
        destination.id: const Offset(2530, 2400),
      });
      await tester.pumpAndSettle();
      final [raw, enumerated] = destination.cvModulations;
      final ordinary = state.connections.singleWhere(
        (c) => c.connectionType == ConnectionType.partialBusToInput,
      );
      expect(raw.contributors, isEmpty);
      expect(enumerated.contributors.single.slotIndex, 0);
      expect(ordinary.busNumber, raw.bus);
      expect(
        state.connections.any((c) => c.destinationPortId == raw.id),
        isFalse,
      );

      Offset cvAnchor(String name) {
        final button = tester
            .widgetList<CvModulationButton>(find.byType(CvModulationButton))
            .singleWhere(
              (button) => button.standardInput && button.displayLabel == name,
            );
        return tester.getCenter(find.byKey(button.endpointKey!));
      }

      final rawAnchor = cvAnchor('Main: Unwired cutoff');
      final namedAnchor = cvAnchor('Main: Mapped resonance');
      final ordinaryAnchor = portCenter(tester, ordinary.destinationPortId);
      final sourceAnchor = portCenter(
        tester,
        enumerated.contributorPortIds.single,
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(captureKey),
      );
      final pixels = (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          const evidenceDir = String.fromEnvironment('CV_ROUTING_EVIDENCE_DIR');
          if (evidenceDir.isNotEmpty) {
            final png = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File('$evidenceDir/graph-${defaultTargetPlatform.name}.png')
                .writeAsBytes(
                  png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
                );
          }
          return (image.width, (await image.toByteData())!);
        } finally {
          image.dispose();
        }
      }))!;
      final context = tester.element(find.byKey(captureKey));
      final colors = Theme.of(context).colorScheme;
      final green = cvModulationColor(context);
      final neutral = Color.alphaBlend(
        colors.onSurface.withValues(alpha: .84),
        colors.surface,
      );

      int rgb(Offset point) {
        final local = boundary.globalToLocal(point);
        final offset = (local.dy.floor() * pixels.$1 + local.dx.floor()) * 4;
        return pixels.$2.getUint32(offset) >> 8;
      }

      void expectStroke(Offset point, Color ink) {
        final actual = rgb(point);
        final expected = ink.toARGB32();
        for (final shift in [16, 8, 0]) {
          expect(
            (actual >> shift) & 0xff,
            closeTo((expected >> shift) & 0xff, 3),
            reason: 'RGB at $point',
          );
        }
      }

      Set<(int, int)> labelInk(Offset center) => {
        for (var dy = -6; dy <= 6; dy++)
          for (var dx = -18; dx <= 18; dx++)
            if (rgb(center + Offset(dx.toDouble(), dy.toDouble())) ==
                (colors.onSurface.toARGB32() & 0xffffff))
              (dx, dy),
      };

      final rawLabel = rawAnchor - const Offset(75, 0);
      final ordinaryLabel = ordinaryAnchor - const Offset(75, 0);
      final ordinaryLabelInk = labelInk(ordinaryLabel);

      // Sample the center of a dash, the following gap and the next dash.
      for (final (anchor, ink) in [
        (rawAnchor, green),
        (ordinaryAnchor, neutral),
      ]) {
        expectStroke(anchor - const Offset(47, 0), ink);
        expectStroke(anchor - const Offset(41, 0), colors.surface);
        expectStroke(anchor - const Offset(35, 0), ink);
      }
      expect(ordinaryLabelInk, isNotEmpty);
      expect(labelInk(rawLabel), ordinaryLabelInk);
      expect(labelInk(namedAnchor - const Offset(75, 0)), isEmpty);
      final greenRgb = green.toARGB32() & 0xffffff;
      final offAxisTipPixels = [
        for (var dx = 4; dx <= 20; dx++)
          for (final dy in [-7, -6, -5, -4, -3, 3, 4, 5, 6, 7])
            rgb(rawAnchor + Offset(-dx.toDouble(), dy.toDouble())),
      ];
      expect(offAxisTipPixels, isNot(contains(greenRgb)));

      // The named modulation still reaches its producer on a curved, dotted path.
      final path = CvModulationCurve.pathFor(
        sourceAnchor,
        namedAnchor,
        graphInput: true,
      );
      final metric = path.computeMetrics().single;
      final distance = (metric.length * .5 ~/ 7) * 7 + 1.0;
      final namedCable = metric.getTangentForOffset(distance)!.position;
      expectStroke(namedCable, green);
      expect(find.text(raw.busLabel), findsNothing);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(
          find.bySemanticsLabel(
            RegExp('^Inspect CV modulation: ${raw.busLabel}.*Unwired cutoff'),
          ),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }

      Future<void> tapCanvasAt(Offset point) async {
        await tester.tapAt(point);
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
      }

      await tapCanvasAt(rawLabel + const Offset(10, 0));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MappingEditorBottomSheet), findsNothing);

      for (final (point, name) in [
        (rawAnchor - const Offset(40, 0), 'Unwired cutoff'),
        (namedCable, 'Mapped resonance'),
      ]) {
        await tapCanvasAt(point);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining(name, findRichText: true),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }

      final targetNode = find.byWidgetPredicate(
        (w) => w is AlgorithmNodeWidget && w.slotNumber == 2,
      );
      await tester.tap(
        find.descendant(of: targetNode, matching: find.byTooltip('More')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unwired cutoff'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<MappingEditorBottomSheet>(
        find.byType(MappingEditorBottomSheet),
      );
      expect(sheet.algorithmIndex, 1);
      expect(sheet.parameterNumber, raw.parameterNumber);
      expect(sheet.data.cvInput, raw.bus);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      when(
        () => disting.updateParameterValue(
          algorithmIndex: 1,
          parameterNumber: 0,
          value: 0,
          userIsChangingTheValue: true,
        ),
      ).thenAnswer((_) async {});
      await tester.tapAt(ordinaryLabel);
      verify(
        () => disting.updateParameterValue(
          algorithmIndex: 1,
          parameterNumber: 0,
          value: 0,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      verifyNever(() => disting.saveMapping(any(), any(), any()));
      verifyNever(() => disting.saveMappingImmediately(any(), any(), any()));
      verifyZeroInteractions(manager);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'canvas snapshot taps use real slot boundaries and unresolved open stubs',
    (tester) async {
      for (final sourceKind in [0, 1, 2, 9]) {
        final bus = sourceKind == 1 ? 1 : 32;
        setTarget(cvSlot(1, cvBuses: [bus], source: sourceKind));
        await pump(tester, views['canvas']!);
        final painter = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CvModulationCurve>()
            .single;
        if (sourceKind == 9) {
          final mapping = (cubit.state as RoutingEditorStateLoaded)
              .algorithms
              .last
              .cvModulations
              .single;
          final busPainter = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((widget) => widget.painter)
              .whereType<ConnectionPainter>()
              .single;
          expect(mapping.contributors, isEmpty);
          expect(painter.endpoints, isEmpty);
          expect(busPainter.getLabelBounds(), contains(mapping.id));
          continue;
        }
        final path = painter.endpoints.single;

        if (sourceKind == 0 || sourceKind == 2) {
          final mapping = (cubit.state as RoutingEditorStateLoaded)
              .algorithms
              .last
              .cvModulations
              .single;
          final paint = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .singleWhere((p) => identical(p.painter, painter));
          final box = tester.renderObject<RenderBox>(find.byWidget(paint));
          expect(
            box.localToGlobal(path.$1),
            portCenter(tester, mapping.contributors.single.portId),
          );
          expect(painter.sourceHalos, {path.$1});
          expect(painter.sourceHaloRadius, 8);
          final output = tester.widget<PortWidget>(
            find.byWidgetPredicate(
              (w) =>
                  w is PortWidget &&
                  w.portId == mapping.contributors.single.portId,
            ),
          );
          expect(output.interactionKind, PortInteractionKind.routing);
          expect(output.isInput, isFalse);
        } else {
          final mapping = (cubit.state as RoutingEditorStateLoaded)
              .algorithms
              .last
              .cvModulations
              .single;
          expect(mapping.contributorPortIds, ['hw_in_1']);
          expect(path.$1, isNot(path.$2 - const Offset(60, 0)));
        }
      }
      verifyZeroInteractions(manager);
    },
  );

  testWidgets('read-only virtual input consumes drag, long press and delete', (
    tester,
  ) async {
    final mappings =
        (cubit.state as RoutingEditorStateLoaded).algorithms.last.cvModulations;
    var drags = 0;
    var deletes = 0;
    await pump(
      tester,
      Center(
        child: AlgorithmNodeWidget(
          algorithmName: target.algorithm.name,
          slotNumber: 2,
          position: Offset.zero,
          inputLabels: const ['Input'],
          inputPortIds: const ['ordinary'],
          onDragStart: () => drags++,
          onPortLongPress: (_) => deletes++,
          virtualCvInputs: CvVirtualInputs(
            mappings: mappings,
            onInspect: () {},
            onAnchor: (_, _) {},
          ),
        ),
      ),
    );
    final input = find.byKey(const ValueKey('cv-virtual-input-0'));
    await tester.drag(input, const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.longPress(input);
    await tester.pumpAndSettle();
    expect(drags, 0);
    expect(deletes, 0);
    await tester.tap(input);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(deletes, 0);
    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
      final focus = Focus.of(
        tester.element(
          find.descendant(of: input, matching: find.text('Main: CC 1')),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    expect(find.text('Delete Algorithm'), findsNothing);
    verifyZeroInteractions(manager);
  });

  testWidgets(
    'lanes snapshot taps use actual preset indices, not a filtered card index',
    (tester) async {
      for (final sourceKind in [0, 1, 3, 9]) {
        await tester.pumpWidget(const SizedBox());
        snapshot = snapshot.copyWith(
          slots: [
            cvSlot(0),
            cvSlot(1, outputs: [32]),
            cvSlot(2),
            cvSlot(3, cvBuses: [sourceKind == 1 ? 1 : 32], source: sourceKind),
          ],
        );
        events.add(snapshot);
        await pump(tester, views['lanes']!);
        final metrics = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<BusLanesPainter>()
            .single
            .metrics;
        final paths = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CvModulationCurve>()
            .singleWhere((p) => p.endpoints.isNotEmpty)
            .endpoints;
        final startY = paths.first.$1.dy + metrics.cardTops[3];
        if (sourceKind == 0 || sourceKind == 3) {
          expect(startY, metrics.cardTops[1] + BusLanesMetrics.portRowY(0));
        } else if (sourceKind == 1) {
          expect(startY, metrics.railsTop);
        } else {
          expect(paths.first.$1.dy, paths.first.$2.dy - 16);
        }
      }
      verifyZeroInteractions(manager);
    },
  );

  test('input grouping only coalesces the same parameter identity', () {
    final maps = cvProjection([
      cvSlot(0, cvBuses: [32, 33, 32]),
    ]);
    final extra = CvModulation(
      destinationAlgorithmId: maps.first.destinationAlgorithmId,
      destinationSlot: 0,
      parameterNumber: maps.first.parameterNumber,
      parameterName: maps.first.parameterName,
      bus: 34,
      busLabel: 'A2',
      source: 0,
      snapshot: maps.first.snapshot,
      contributors: [],
      caveats: [],
    );
    final groups = cvInputGroups([...maps, extra]);
    expect(groups, hasLength(3));
    expect(groups.first, [maps.first, extra]);
    expect(groups.skip(1).every((g) => g.length == 1), isTrue);
  });

  testWidgets(
    'dialog contains only the exact named configured relationship and Close',
    (tester) async {
      snapshot = snapshot.copyWith(
        slots: [
          cvSlot(0),
          cvSlot(
            1,
            outputs: [32],
            algorithmName: 'Step Sequencer',
            outputNames: ['Step output'],
          ),
          cvSlot(2),
          cvSlot(
            3,
            cvBuses: [32],
            algorithmName: 'Midi CC Generator',
            pageName: 'Channel 1',
            cvNames: ['1:CC'],
          ),
        ],
      );
      events.add(snapshot);
      await pump(tester, views['canvas']!);
      final button = tester
          .widgetList<CvModulationButton>(find.byType(CvModulationButton))
          .firstWhere((b) => b.endpointKey != null);
      pressInspect(tester, button);
      await tester.pumpAndSettle();
      const relationship =
          'Slot 2: Step Sequencer - Step output → Slot 4: Midi CC Generator - Channel 1: CC';
      expect(find.text(relationship), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        tester
            .widgetList<SelectableText>(
              find.descendant(
                of: dialog,
                matching: find.byType(SelectableText),
              ),
            )
            .map((w) => w.data),
        [relationship],
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Close')),
        findsOneWidget,
      );
      expect(tester.widget<AlertDialog>(dialog).title, isNull);
      for (final prohibited in [
        'Inferred',
        'Configured modulation',
        'not voltage telemetry',
        'parameter_number',
        'Add/Replace',
      ]) {
        expect(find.textContaining(prohibited), findsNothing);
      }
      verifyZeroInteractions(manager);
    },
  );

  test(
    'channel naming removes only a repeated, matching metadata channel number',
    () {
      for (final entry in <(String, String, String)>[
        ('Channel 1', '1:CC', 'Channel 1: CC'),
        ('Channel 1', '2:CC', 'Channel 1: 2:CC'),
        ('Main', '1:CC', 'Main: 1:CC'),
        ('Channel 1', '12 semitones', 'Channel 1: 12 semitones'),
      ]) {
        expect(
          cvProjection([
            cvSlot(0, cvBuses: [32], pageName: entry.$1, cvNames: [entry.$2]),
          ]).single.parameterName,
          entry.$3,
        );
      }
    },
  );

  test('multiple bus writers use the exact configured snapshot instead of choosing one output', () {
    final mapping = cvProjection([
      cvSlot(0, outputs: [32]),
      cvSlot(1, outputs: [32]),
      cvSlot(2, cvBuses: [32]),
    ]).single;
    expect(mapping.contributors, hasLength(2));
    expect(
      cvInspectionSummary(mapping, destinationName: 'Target'),
      '${mapping.busLabel} · ${mapping.snapshot} → Slot 3: Target - Main: CC 1',
    );
    expect(cvInspectionSummary(mapping), isNot(contains('Inferred')));
  });

  testWidgets(
    'Signal Flow CV markers occupy the input line above their numbered algorithm',
    (tester) async {
      snapshot = snapshot.copyWith(
        slots: [
          cvSlot(0),
          cvSlot(1, outputs: [32, 33]),
          cvSlot(2),
          cvSlot(3, cvBuses: [32, 33]),
        ],
      );
      events.add(snapshot);
      await pump(tester, views['table']!);
      final algorithm = tester.getRect(find.text('4. MIDI CC Generator 3'));
      final markers = [
        tester.getRect(find.byKey(const ValueKey('cv-cell-3-32'))),
        tester.getRect(find.byKey(const ValueKey('cv-cell-3-33'))),
      ];
      for (final marker in markers) {
        expect(marker.center.dy, algorithm.center.dy - 28);
        expect(marker.bottom, lessThanOrEqualTo(algorithm.top));
      }
      expect(markers[1].center.dx - markers[0].center.dx, 32);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one selected-snapshot bus tap fans out to separately named nodes',
    (tester) async {
      snapshot = snapshot.copyWith(
        slots: [
          cvSlot(0),
          cvSlot(1, outputs: [32]),
          cvSlot(2, cvBuses: [32], source: 3, cvNames: ['Pitch']),
          cvSlot(3, cvBuses: [32], source: 3, cvNames: ['Velocity']),
        ],
      );
      events.add(snapshot);
      await pump(tester, views['canvas']!);
      final taps = tester
          .widgetList<CvModulationButton>(find.byType(CvModulationButton))
          .where(
            (b) =>
                b.key is ValueKey<String> &&
                (b.key! as ValueKey<String>).value.startsWith('cv-snapshot-'),
          );
      expect(taps, isEmpty);
      final paths = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CvModulationCurve>()
          .single
          .endpoints;
      expect(paths, hasLength(2));
      expect(paths.first.$1, paths.last.$1);
      expect(paths.first.$2, isNot(paths.last.$2));
      expect(find.text('Main: Pitch'), findsOneWidget);
      expect(find.text('Main: Velocity'), findsOneWidget);
    },
  );

  testWidgets(
    'Graph CV paths remain on standard ports through layout, pan and zoom',
    (tester) async {
      await pump(tester, views['canvas']!);
      final targetId =
          (cubit.state as RoutingEditorStateLoaded).algorithms.last.id;
      for (final zoom in [.75, 1.5]) {
        cubit.setZoomLevel(zoom);
        await cubit.updateNodePosition(
          targetId,
          3500 + zoom * 50,
          3400 + zoom * 40,
        );
        await tester.pumpAndSettle();
        for (final scroll in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          final p = scroll.position;
          p.jumpTo((p.pixels + 50).clamp(p.minScrollExtent, p.maxScrollExtent));
        }
        await tester.pumpAndSettle();
        final paint = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .singleWhere((w) => w.painter is CvModulationCurve);
        final painter = paint.painter! as CvModulationCurve;
        final box = tester.renderObject<RenderBox>(find.byWidget(paint));
        final inputs = tester
            .widgetList<CvModulationButton>(find.byType(CvModulationButton))
            .where((b) => b.standardInput)
            .toList();
        expect(painter.graphInput, isTrue);
        for (var i = 0; i < inputs.length; i++) {
          final mapping = inputs[i].mappings.single;
          final (source, target) = painter.endpoints[i];
          expect(
            (box.localToGlobal(source) -
                    portCenter(tester, mapping.contributors.single.portId))
                .distance,
            lessThan(.01),
          );
          expect(
            (box.localToGlobal(target) -
                    tester.getCenter(find.byKey(inputs[i].endpointKey!)))
                .distance,
            lessThan(.01),
          );
          final metric = CvModulationCurve.pathFor(
            source,
            target,
            graphInput: painter.graphInput,
          ).computeMetrics().single;
          expect(
            (metric.getTangentForOffset(metric.length)!.position - target)
                .distance,
            lessThan(.01),
          );
          expect(
            metric.getTangentForOffset(metric.length)!.vector.dx,
            greaterThan(0),
          );
          expect(painter.sourceHalos, contains(source));
        }
      }
      verifyZeroInteractions(manager);
    },
  );

  testWidgets(
    'Bus Lanes CV rows sit below the title with ordinary junction circles and no CV arrowheads',
    (tester) async {
      await pump(tester, views['lanes']!);
      final blocks = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<BusBlockPainter>();
      final target = blocks.singleWhere(
        (p) => p.ports.any((r) => r.kind == PortRowKind.cvModulation),
      );
      expect(
        target.ports
            .where((r) => r.kind == PortRowKind.cvModulation)
            .map((r) => r.label),
        ['Main: CC 1', 'Main: CC 2'],
      );
      expect(
        target.ports
            .where((r) => r.kind == PortRowKind.cvModulation)
            .every(
              (r) =>
                  BusLanesMetrics.portRowY(r.row) >
                      BusLanesMetrics.titleHeight &&
                  r.directionGlyph.isEmpty,
            ),
        isTrue,
      );
      final curves = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<CvModulationCurve>();
      final curve = curves.singleWhere((p) => p.endpoints.isNotEmpty);
      expect(curve.sourceHalos, hasLength(2));
      expect(curve.sourceHaloRadius, 9);
      final beads = tester
          .widgetList<CvModulationButton>(find.byType(CvModulationButton))
          .where(
            (b) =>
                b.key is ValueKey<String> &&
                (b.key! as ValueKey<String>).value.startsWith('cv-lane-cv_'),
          );
      expect(beads, hasLength(2));
      for (final bead in beads) {
        final circles = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byWidget(bead),
                matching: find.byType(Container),
              ),
            )
            .where(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration! as BoxDecoration).shape == BoxShape.circle,
            );
        expect(circles.single.constraints!.maxWidth, 14);
        expect(
          find.descendant(
            of: find.byWidget(bead),
            matching: find.byWidgetPredicate((w) => w is Draggable),
          ),
          findsNothing,
        );
      }
      expect(find.byWidgetPredicate((w) => w is Draggable), findsWidgets);
      verifyZeroInteractions(manager);
    },
  );

  test('CV layers paint only dotted paths and concentric source halos, never arrowheads', () {
    for (final graph in [false, true]) {
      final canvas = _CvCanvas();
      final painter = CvModulationCurve(
        endpoints: [(Offset.zero, const Offset(100, 0))],
        sourceHalos: {Offset.zero},
        color: Colors.green,
        graphInput: graph,
      );
      painter.paint(canvas, const Size(200, 100));
      final length = CvModulationCurve.pathFor(
        Offset.zero,
        const Offset(100, 0),
        graphInput: graph,
      ).computeMetrics().single.length;
      expect(canvas.paths, hasLength((length / 7).ceil()));
      expect(canvas.circles, [(Offset.zero, 8)]);
      expect(canvas.paths.every((p) => p.getBounds().height < .01), isTrue);
    }
  });

  for (final viewName in ['lanes', 'table']) {
    testWidgets(
      '$viewName edits the real target mapping through the existing editor without opening writes',
      (tester) async {
        snapshot = snapshot.copyWith(
          slots: [
            cvSlot(0, outputs: [32]),
            cvSlot(1),
            cvSlot(2),
            cvSlot(3, cvBuses: [32, 32], source: 3),
          ],
        );
        events.add(snapshot);
        await pump(tester, views[viewName]!);
        final buttons = tester.widgetList<CvModulationButton>(
          find.byType(CvModulationButton),
        );
        final button = viewName == 'lanes'
            ? buttons.firstWhere(
                (b) =>
                    b.endpointKey != null &&
                    b.mappings.single.parameterNumber == 1,
              )
            : buttons.firstWhere((b) => b.mappings.isNotEmpty);
        expect(button.onEdit, isNotNull);
        pressInspect(tester, button);
        await tester.pumpAndSettle();
        if (viewName == 'table') {
          expect(find.byType(MappingEditorBottomSheet), findsNothing);
          await tester.tap(find.text('Main: CC 2'));
          await tester.pumpAndSettle();
        }
        final sheet = tester.widget<MappingEditorBottomSheet>(
          find.byType(MappingEditorBottomSheet),
        );
        expect(sheet.algorithmIndex, 3);
        expect(sheet.parameterNumber, 1);
        expect(sheet.slots, hasLength(4));
        expect(sheet.data, snapshot.slots[3].mappings[1].packedMappingData);
        expect(find.byType(AlertDialog), findsNothing);
        verifyNever(() => disting.saveMapping(any(), any(), any()));
        verifyNever(() => disting.saveMappingImmediately(any(), any(), any()));
        verifyZeroInteractions(manager);
        final sourceChoice = tester
            .widgetList<DropdownMenu<int>>(find.byType(DropdownMenu<int>))
            .singleWhere(
              (d) => d.label is Text && (d.label! as Text).data == 'Source',
            );
        expect(sourceChoice.initialSelection, 3);
        expect(
          sourceChoice.dropdownMenuEntries
              .singleWhere((e) => e.value == 3)
              .label,
          'Slot 2: MIDI CC Generator 1',
        );
        when(() => disting.saveMapping(3, 1, any())).thenAnswer((
          invocation,
        ) async {
          final data = invocation.positionalArguments[2] as PackedMappingData;
          final slots = [...snapshot.slots];
          final mappings = [...slots[3].mappings];
          mappings[1] = Mapping(
            algorithmIndex: 3,
            parameterNumber: 1,
            packedMappingData: data,
          );
          slots[3] = slots[3].copyWith(mappings: mappings);
          snapshot = snapshot.copyWith(slots: slots);
          events.add(snapshot);
        });
        // Exercise the existing editor's ordinary user-change callback, not a CV routing write path.
        tester
            .widget<BusSelectionField>(
              find.byWidgetPredicate(
                (w) => w is BusSelectionField && w.label == 'CV Input',
              ),
            )
            .onChanged(33);
        await tester.pumpAndSettle();
        verify(() => disting.saveMapping(3, 1, any())).called(1);
        verifyNever(() => disting.saveMappingImmediately(any(), any(), any()));
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        final updated = (cubit.state as RoutingEditorStateLoaded).algorithms
            .singleWhere((a) => a.index == 3)
            .cvModulations;
        expect(updated.singleWhere((m) => m.parameterNumber == 1).bus, 33);
        expect(updated.singleWhere((m) => m.parameterNumber == 1).source, 3);
        expect(updated.singleWhere((m) => m.parameterNumber == 0).bus, 32);
        expect(
          tester
              .widgetList<CvModulationButton>(find.byType(CvModulationButton))
              .expand((b) => b.mappings)
              .any(
                (m) =>
                    m.destinationSlot == 3 &&
                    m.parameterNumber == 1 &&
                    m.bus == 33,
              ),
          isTrue,
        );
        verifyZeroInteractions(manager);
      },
    );
  }

  testWidgets('modulation color is readable in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      late Color color;
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              color = cvModulationColor(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final a = color.computeLuminance(),
          b = theme.colorScheme.surface.computeLuminance();
      final contrast = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
      expect(contrast, greaterThan(4.5));
    }
  });
}
