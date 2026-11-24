import 'package:drift/native.dart';
import 'package:nt_helper/db/database.dart';
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
import 'package:nt_helper/ui/widgets/routing/accessible_routing_list_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_view.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_painter.dart';
import 'package:nt_helper/ui/widgets/routing/cv_modulation_view.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers/cv_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  late _Disting disting;
  late _Manager manager;
  late StreamController<DistingState> events;
  late RoutingEditorCubit cubit;
  late DistingStateSynchronized snapshot;
  final source = cvSlot(0, outputs: [32, 33]);
  final target = cvSlot(1, cvBuses: [32, 33]);

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

  Future<void> pump(WidgetTester tester, Widget view) async {
    await cubit.close();
    cubit = RoutingEditorCubit(disting);
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
    await tester.pump();
    await tester.pumpAndSettle();
  }

  void setTarget(Slot slot) {
    snapshot = snapshot.copyWith(slots: [source, slot]);
    events.add(snapshot);
  }

  final views = <String, Widget>{
    'canvas': RoutingEditorWidget(canvasSize: const Size(1000, 700)),
    'lanes': const BusLanesView(),
    'table': const RoutingTableView(),
    'list': const AccessibleRoutingListView(),
  };
  for (final entry in views.entries) {
    testWidgets(
      '${entry.key} exposes identical distinct inspect-only CV targets',
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
          find.bySemanticsLabel(
            RegExp('Inferred producer: Slot 1: Step 0 — Step output 1'),
          ),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(RegExp('Inspect CV modulation:')),
          findsWidgets,
        );
        // The same native keyboard-activatable inspect action is used by every adapter.
        final selectedButton = find
            .descendant(
              of: find.byType(CvModulationButton),
              matching: find.byType(TextButton),
            )
            .first;
        final widget = tester.widget<TextButton>(selectedButton);
        widget.onPressed!();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('CV modulation'), findsOneWidget);
        expect(find.textContaining('parameter 0'), findsWidgets);
        expect(find.text('Delete'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('CV modulation'), findsNothing);
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
      await pump(tester, views['lanes']!);
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

  testWidgets('CV inspect clears a selected ordinary bead before Delete', (
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

  testWidgets('out-of-profile CV inspect also clears the armed ordinary bead', (
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
    expect(find.text('CV modulation'), findsOneWidget);
    expect(
      find.textContaining('Bus outside this device profile'),
      findsOneWidget,
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
    expect(find.text('CV modulation'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('CV modulation'), findsNothing);
    expect(FocusManager.instance.primaryFocus, focus);
    verifyZeroInteractions(manager);
  });

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
