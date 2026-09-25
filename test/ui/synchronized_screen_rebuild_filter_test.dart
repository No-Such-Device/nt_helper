import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/algorithm_list_view.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

Slot _slot(int index, String guid, String name, {int value = 10}) => Slot(
  algorithm: Algorithm(algorithmIndex: index, guid: guid, name: name),
  routing: RoutingInfo.filler(),
  pages: ParameterPages(
    algorithmIndex: index,
    pages: [
      ParameterPage(name: 'Main', parameters: const [0]),
    ],
  ),
  parameters: [
    ParameterInfo(
      algorithmIndex: index,
      parameterNumber: 0,
      min: 0,
      max: 1000,
      defaultValue: 0,
      unit: 0,
      name: 'Level',
      powerOfTen: 0,
    ),
  ],
  values: [
    ParameterValue(algorithmIndex: index, parameterNumber: 0, value: value),
  ],
  enums: [ParameterEnumStrings.filler()],
  mappings: [Mapping.filler()],
  valueStrings: [ParameterValueString.filler()],
);

/// Replaces slot 0's parameter value, producing a new slots list as the
/// cubit does for parameter updates.
List<Slot> _withValue(List<Slot> slots, int value) => [
  slots[0].copyWith(
    values: [
      ParameterValue(
        algorithmIndex: slots[0].algorithm.algorithmIndex,
        parameterNumber: 0,
        value: value,
      ),
    ],
  ),
  ...slots.skip(1),
];

void main() {
  late MockDistingCubit cubit;
  late MockPlatformInteractionService platformService;
  late AppDatabase database;
  late StreamController<DistingState> states;
  late DistingState current;
  late int scaffoldBuilds;

  setUp(() async {
    cubit = MockDistingCubit();
    platformService = MockPlatformInteractionService();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
    states = StreamController<DistingState>.broadcast();
    scaffoldBuilds = 0;
    current = DistingStateSynchronized(
      disting: MockDistingMidiManager(),
      distingVersion: '1.10.0',
      firmwareVersion: FirmwareVersion('1.10.0'),
      presetName: 'Preset',
      algorithms: const [],
      slots: [_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')],
      unitStrings: const [],
      offline: true,
    );
    when(() => cubit.state).thenAnswer((_) => current);
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.checkpoints).thenReturn([]);
    when(() => cubit.cpuUsageStream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.database).thenReturn(database);
    when(() => cubit.supportsMemoryUsage).thenReturn(false);
    when(() => platformService.isMobilePlatform()).thenReturn(false);
    McpServerService.initialize(distingCubit: cubit);
  });

  tearDown(() async {
    await states.close();
    await database.close();
  });

  DistingStateSynchronized sync() => current as DistingStateSynchronized;

  Future<void> emit(WidgetTester tester, DistingState state) async {
    current = state;
    states.add(state);
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpApp(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<DistingCubit>.value(
        value: cubit,
        child: MaterialApp(
          home: BlocBuilder<DistingCubit, DistingState>(
            // Mirrors the outer scaffold consumer in disting_app.dart.
            buildWhen: synchronizedScaffoldShouldRebuild,
            builder: (context, state) {
              scaffoldBuilds++;
              final s = state as DistingStateSynchronized;
              return SynchronizedScreen(
                slots: s.slots,
                algorithms: s.algorithms,
                units: s.unitStrings,
                distingVersion: s.distingVersion,
                presetName: s.presetName,
                isDirty: s.isDirty,
                screenshot: s.screenshot,
                loading: s.loading,
                firmwareVersion: s.firmwareVersion,
                platformService: platformService,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  AlgorithmListView sidebar(WidgetTester tester) =>
      tester.widget<AlgorithmListView>(find.byType(AlgorithmListView));

  List<String> sidebarNames(WidgetTester tester) =>
      sidebar(tester).slots.map((s) => s.algorithm.name).toList();

  testWidgets('parameter-only emissions skip sidebar and scaffold builders '
      'while the parameter editor updates', (tester) async {
    await pumpApp(tester);
    expect(find.text('10'), findsWidgets);
    final initialSidebar = sidebar(tester);
    final initialScaffoldBuilds = scaffoldBuilds;

    for (final value in [42, 43, 44]) {
      final slots = _withValue(sync().slots, value);
      expect(identical(slots, sync().slots), isFalse);
      await emit(tester, sync().copyWith(slots: slots));
      expect(find.text('$value'), findsWidgets);
    }

    expect(scaffoldBuilds, initialScaffoldBuilds);
    expect(identical(sidebar(tester), initialSidebar), isTrue);
  });

  testWidgets('adding, removing, reordering and renaming slots update the '
      'sidebar', (tester) async {
    await pumpApp(tester);
    expect(sidebarNames(tester), ['Alpha', 'Beta']);

    await emit(
      tester,
      sync().copyWith(slots: [...sync().slots, _slot(2, 'G3', 'Gamma')]),
    );
    expect(sidebarNames(tester), ['Alpha', 'Beta', 'Gamma']);

    await emit(tester, sync().copyWith(slots: sync().slots.sublist(0, 2)));
    expect(sidebarNames(tester), ['Alpha', 'Beta']);

    await emit(
      tester,
      sync().copyWith(slots: [_slot(0, 'G2', 'Beta'), _slot(1, 'G1', 'Alpha')]),
    );
    expect(sidebarNames(tester), ['Beta', 'Alpha']);

    await emit(
      tester,
      sync().copyWith(
        slots: [_slot(0, 'G2', 'Renamed'), _slot(1, 'G1', 'Alpha')],
      ),
    );
    expect(sidebarNames(tester), ['Renamed', 'Alpha']);
    expect(find.text('Renamed'), findsWidgets);
  });

  testWidgets('selection and connection-state changes are not stale', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(sidebar(tester).selectedIndex, 0);

    sidebar(tester).onSelectionChanged(1);
    await tester.pump();
    expect(sidebar(tester).selectedIndex, 1);

    IconButton refresh() => tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.refresh_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(refresh().onPressed, isNull);

    final builds = scaffoldBuilds;
    await emit(tester, sync().copyWith(offline: false));
    expect(scaffoldBuilds, builds + 1);
    expect(refresh().onPressed, isNotNull);

    await emit(tester, sync().copyWith(offline: true));
    expect(scaffoldBuilds, builds + 2);
    expect(refresh().onPressed, isNull);
  });

  testWidgets('resizing between narrow, wide and wider layouts switches '
      'layout', (tester) async {
    await pumpApp(tester, width: 600);
    expect(find.byType(AlgorithmListView), findsNothing);
    expect(find.byType(TabBar), findsOneWidget);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();
    expect(find.byType(AlgorithmListView), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);

    tester.view.physicalSize = const Size(2400, 900);
    await tester.pump();
    expect(find.byType(AlgorithmListView), findsOneWidget);

    tester.view.physicalSize = const Size(600, 900);
    await tester.pump();
    expect(find.byType(AlgorithmListView), findsNothing);
    expect(find.byType(TabBar), findsOneWidget);
  });
}
