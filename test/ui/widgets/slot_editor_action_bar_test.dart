import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/algorithm_respecification.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/slot_editor_action_bar.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_container.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

final class _LiveRespecificationManager extends Mock
    implements IDistingMidiManager, AlgorithmRespecificationWriter {
  final List<(int, List<int>)> mutations = [];

  @override
  Future<void> requestRespecifyAlgorithm(
    int algorithmIndex,
    List<int> specifications,
  ) async {
    mutations.add((algorithmIndex, List<int>.from(specifications)));
  }
}

void main() {
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(const AlgorithmVisualStyle());
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() => database.close());

  testWidgets(
    'Reset Outputs ignores output-mode parameters when building bus choices',
    (tester) async {
      final profile = DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!;
      final slot = _slotWithOutputAndMode();
      final cubit = _MockDistingCubit();
      final state = DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.20',
        firmwareVersion: FirmwareVersion('1.20'),
        deviceIoProfile: profile,
        presetName: 'Test',
        algorithms: const [],
        slots: [slot],
        unitStrings: const [],
      );
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
      _stubRespecifyUnavailable(cubit);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: Scaffold(
              body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset Outputs'));
      await tester.pumpAndSettle();

      final field = tester.widget<BusSelectionField>(
        find.byType(BusSelectionField),
      );
      expect(field.model.choices.map((choice) => choice.value), profile.buses);
    },
  );

  testWidgets('hides algorithm style controls before firmware 1.18', (
    tester,
  ) async {
    final slot = _slotWithOutputAndMode();
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.17.9',
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    _stubRespecifyUnavailable(cubit);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('slot-editor-algorithm-style')),
      findsNothing,
    );
  });

  testWidgets('shows algorithm style preview control offline', (tester) async {
    final slot = _slotWithOutputAndMode();
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.15.0',
        offline: true,
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('slot-editor-algorithm-style')),
      findsOneWidget,
    );

    final button = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('slot-editor-algorithm-style')),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.iconSize, 24);
    expect(button.alignment, Alignment.center);
    expect(button.padding, const EdgeInsets.all(8));

    await tester.tap(find.byKey(const ValueKey('slot-editor-algorithm-style')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Offline preview'), findsNothing);
    expect(find.textContaining('SysEx'), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
  });

  testWidgets('keeps equal spacing around the algorithm style action', (
    tester,
  ) async {
    final slot = _slotWithOutputAndMode();
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.18.0',
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(
              slot: slot,
              sectionsCollapsed: false,
              editorModeSelector: IconButton.filledTonal(
                key: const ValueKey('editor-mode-selector'),
                onPressed: () {},
                icon: const Icon(Icons.extension),
              ),
            ),
          ),
        ),
      ),
    );

    final editorCenter = tester.getCenter(
      find.byKey(const ValueKey('editor-mode-selector')),
    );
    final styleCenter = tester.getCenter(
      find.byKey(const ValueKey('slot-editor-algorithm-style')),
    );
    final collapseCenter = tester.getCenter(
      find.byKey(const ValueKey('slot-editor-collapse-toggle')),
    );

    expect(
      styleCenter.dx - editorCenter.dx,
      collapseCenter.dx - styleCenter.dx,
    );
  });

  testWidgets('edits and syncs firmware 1.18 algorithm style immediately', (
    tester,
  ) async {
    const initialStyle = AlgorithmVisualStyle(
      leftIndent: 2,
      rightIndent: 4,
      lineAbove: true,
      bracket: AlgorithmVisualBracket.line,
    );
    final baseSlot = _slotWithOutputAndMode();
    final slot = baseSlot.copyWith(
      algorithm: baseSlot.algorithm.copyWith(visualStyle: initialStyle),
    );
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.18.0beta',
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    final syncCompleter = Completer<void>();
    when(
      () => cubit.setAlgorithmVisualStyle(any(), any()),
    ).thenAnswer((_) => syncCompleter.future);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-editor-algorithm-style')));
    await tester.pumpAndSettle();

    expect(find.text('Algorithm Style'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('NT overview preview'), findsNothing);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('algorithm-style-left-indent')),
          )
          .initialValue,
      2,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('algorithm-style-line-above')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('algorithm-style-bracket-line')),
          )
          .selected,
      isTrue,
    );
    expect(find.byKey(const ValueKey('algorithm-style-save')), findsNothing);
    expect(find.text('CANCEL'), findsNothing);

    final initialPreview = tester.widget<AlgorithmVisualStyleContainer>(
      find.byKey(const ValueKey('algorithm-style-live-preview')),
    );
    expect(initialPreview.style, initialStyle);

    await tester.tap(find.byKey(const ValueKey('algorithm-style-line-below')));
    await tester.pump();

    final updatedPreview = tester.widget<AlgorithmVisualStyleContainer>(
      find.byKey(const ValueKey('algorithm-style-live-preview')),
    );
    expect(updatedPreview.style.lineBelow, isTrue);
    expect(
      find.byKey(const ValueKey('algorithm-style-sync-indicator')),
      findsOneWidget,
    );

    verify(
      () => cubit.setAlgorithmVisualStyle(
        0,
        const AlgorithmVisualStyle(
          leftIndent: 2,
          rightIndent: 4,
          lineAbove: true,
          lineBelow: true,
          bracket: AlgorithmVisualBracket.line,
        ),
      ),
    ).called(1);

    syncCompleter.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('algorithm-style-sync-indicator')),
      findsNothing,
    );

    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(find.text('Algorithm Style'), findsNothing);
  });

  testWidgets(
    'shows only More → Respecify... for owner-provided 1.19 betas and later',
    (tester) async {
      final manager = _LiveRespecificationManager();
      final slot = _respecifiableSlot();
      final cubit = _createCubit(database);

      for (final firmware in [
        '1.19beta',
        '1.19.0beta',
        '1.19.0',
        '1.20beta',
        '2.0',
      ]) {
        cubit.emit(
          _synchronizedState(
            slot: slot,
            manager: manager,
            firmwareVersion: firmware,
            algorithms: [_respecificationMetadata()],
          ),
        );
        await tester.pumpWidget(_actionBarHarness(cubit, slot));

        expect(
          find.byKey(const ValueKey('slot-editor-respecify')),
          findsNothing,
          reason: 'Respecify must not be a standalone slot action',
        );
        await tester.tap(
          find.byKey(const ValueKey('slot-editor-more-options')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('slot-editor-respecify')),
          findsOneWidget,
          reason: firmware,
        );
        expect(find.text('Respecify...'), findsOneWidget);
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'hides Respecify for earlier, unknown, disconnected, offline, demo, and non-live states',
    (tester) async {
      final liveManager = _LiveRespecificationManager();
      final slot = _respecifiableSlot();
      final metadata = [_respecificationMetadata()];
      final cubit = _createCubit(database);
      final cases = <(String, DistingState)>[
        for (final firmware in ['1.9.999beta', '1.18.99', '1.18.100beta'])
          (
            firmware,
            _synchronizedState(
              slot: slot,
              manager: liveManager,
              firmwareVersion: firmware,
              algorithms: metadata,
            ),
          ),
        (
          'unknown firmware',
          _synchronizedState(
            slot: slot,
            manager: liveManager,
            firmwareVersion: 'unknown',
            algorithms: metadata,
          ),
        ),
        ('disconnected', DistingState.connected(disting: liveManager)),
        (
          'offline',
          _synchronizedState(
            slot: slot,
            manager: liveManager,
            firmwareVersion: '1.19beta',
            algorithms: metadata,
            offline: true,
          ),
        ),
        (
          'demo',
          _synchronizedState(
            slot: slot,
            manager: liveManager,
            firmwareVersion: '1.19beta',
            algorithms: metadata,
            demo: true,
          ),
        ),
        (
          'manager without live respecification transport',
          _synchronizedState(
            slot: slot,
            manager: _MockDistingMidiManager(),
            firmwareVersion: '1.19beta',
            algorithms: metadata,
          ),
        ),
      ];

      for (final entry in cases) {
        cubit.emit(entry.$2);
        await tester.pumpWidget(_actionBarHarness(cubit, slot));
        await tester.tap(
          find.byKey(const ValueKey('slot-editor-more-options')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('slot-editor-respecify')),
          findsNothing,
          reason: entry.$1,
        );
        expect(find.text('Respecify...'), findsNothing, reason: entry.$1);
        await tester.tapAt(const Offset(1, 1));
        await tester.pumpAndSettle();
      }
      expect(liveManager.mutations, isEmpty);
    },
  );

  testWidgets('hides Respecify instead of opening an empty form', (
    tester,
  ) async {
    final manager = _LiveRespecificationManager();
    final slot = _respecifiableSlot(
      specifications: const [],
      hasAuthoritativeSpecifications: true,
    );
    final cubit = _createCubit(database)
      ..emit(
        _synchronizedState(
          slot: slot,
          manager: manager,
          firmwareVersion: '1.19beta',
          algorithms: [_respecificationMetadata(specifications: const [])],
        ),
      );

    await tester.pumpWidget(_actionBarHarness(cubit, slot));
    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('slot-editor-respecify')), findsNothing);
    expect(find.textContaining('0 specifications required'), findsNothing);
    expect(manager.mutations, isEmpty);
  });

  testWidgets(
    'opens the reused Respecify dialog with authoritative current values and metadata',
    (tester) async {
      final manager = _LiveRespecificationManager();
      final slot = _respecifiableSlot(specifications: const [1, -7]);
      final cubit = _createCubit(database)
        ..emit(
          _synchronizedState(
            slot: slot,
            manager: manager,
            firmwareVersion: '1.19.0beta',
            algorithms: [_respecificationMetadata()],
          ),
        );

      await tester.pumpWidget(_actionBarHarness(cubit, slot));
      await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-editor-respecify')));
      await tester.pumpAndSettle();

      expect(find.text('Respecify Test'), findsOneWidget);
      expect(find.text('2 specifications required'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('test_spec_0')))
            .value,
        isTrue,
      );
      final offsetField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('test_spec_1')),
          matching: find.byType(TextField),
        ),
      );
      expect(offsetField.controller?.text, '-7');
      expect(
        tester.getSemantics(find.byKey(const ValueKey('test_spec_1'))).label,
        contains('Offset (-12-12)'),
      );
      expect(find.widgetWithText(ElevatedButton, 'Respecify'), findsOneWidget);
      expect(find.text('Add Algorithm'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Add'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(manager.mutations, isEmpty);
    },
  );

  testWidgets('rechecks eligibility at submit and performs zero mutation', (
    tester,
  ) async {
    final manager = _LiveRespecificationManager();
    final slot = _respecifiableSlot(specifications: const [1, -7]);
    final metadata = [_respecificationMetadata()];
    final cubit = _createCubit(database)
      ..emit(
        _synchronizedState(
          slot: slot,
          manager: manager,
          firmwareVersion: '1.19beta',
          algorithms: metadata,
        ),
      );

    await tester.pumpWidget(_actionBarHarness(cubit, slot));
    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-editor-respecify')));
    await tester.pumpAndSettle();

    cubit.emit(
      _synchronizedState(
        slot: slot,
        manager: manager,
        firmwareVersion: '1.18.100beta',
        algorithms: metadata,
      ),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
    await tester.pumpAndSettle();

    expect(manager.mutations, isEmpty);
    expect(
      find.text('Respecify requires confirmed firmware 1.19 beta or later.'),
      findsOneWidget,
    );
  });

  testWidgets('rechecks the prepared slot target before mutation', (
    tester,
  ) async {
    final manager = _LiveRespecificationManager();
    final slot = _respecifiableSlot(specifications: const [1, -7]);
    final cubit = _createCubit(database)
      ..emit(
        _synchronizedState(
          slot: slot,
          manager: manager,
          firmwareVersion: '1.19beta',
          algorithms: [_respecificationMetadata()],
        ),
      );

    await tester.pumpWidget(_actionBarHarness(cubit, slot));
    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('slot-editor-respecify')));
    await tester.pumpAndSettle();

    final replacement = _respecifiableSlot(
      guid: 'next',
      name: 'Replacement',
      specifications: const [0, -2],
    );
    cubit.emit(
      _synchronizedState(
        slot: replacement,
        manager: manager,
        firmwareVersion: '1.19beta',
        algorithms: [
          _respecificationMetadata(guid: 'next', name: 'Replacement'),
        ],
      ),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
    await tester.pumpAndSettle();

    expect(manager.mutations, isEmpty);
    expect(
      find.text(
        'The selected slot changed before respecification was submitted.',
      ),
      findsOneWidget,
    );
  });
}

DistingCubit _createCubit(AppDatabase database) {
  final cubit = DistingCubit(
    database,
    midiCommand: MockMidiCommand(),
    isWindowsOverride: true,
  );
  addTearDown(cubit.close);
  return cubit;
}

Widget _actionBarHarness(DistingCubit cubit, Slot slot) {
  return MaterialApp(
    home: BlocProvider<DistingCubit>.value(
      value: cubit,
      child: Scaffold(
        body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
      ),
    ),
  );
}

void _stubRespecifyUnavailable(_MockDistingCubit cubit) {
  when(
    () => cubit.prepareAlgorithmRespecification(any()),
  ).thenThrow(const AlgorithmRespecificationException('Unavailable in test'));
}

DistingStateSynchronized _synchronizedState({
  required Slot slot,
  required IDistingMidiManager manager,
  required String firmwareVersion,
  List<AlgorithmInfo>? algorithms,
  bool offline = false,
  bool demo = false,
}) {
  return DistingState.synchronized(
        disting: manager,
        distingVersion: firmwareVersion,
        firmwareVersion: FirmwareVersion(firmwareVersion),
        presetName: 'Test',
        algorithms: algorithms ?? const [],
        slots: [slot],
        unitStrings: const [],
        offline: offline,
        demo: demo,
      )
      as DistingStateSynchronized;
}

AlgorithmInfo _respecificationMetadata({
  String guid = 'test',
  String name = 'Test',
  List<Specification>? specifications,
}) {
  return AlgorithmInfo(
    algorithmIndex: 42,
    guid: guid,
    name: name,
    specifications:
        specifications ??
        [
          Specification(
            name: 'Stereo',
            min: 0,
            max: 1,
            defaultValue: 0,
            type: 2,
          ),
          Specification(
            name: 'Offset',
            min: -12,
            max: 12,
            defaultValue: 0,
            type: 0,
          ),
        ],
  );
}

Slot _respecifiableSlot({
  String guid = 'test',
  String name = 'Test',
  List<int> specifications = const [1, -7],
  bool hasAuthoritativeSpecifications = true,
}) {
  return _slotWithOutputAndMode().copyWith(
    algorithm: Algorithm(
      algorithmIndex: 0,
      guid: guid,
      name: name,
      specifications: specifications,
      hasAuthoritativeSpecifications: hasAuthoritativeSpecifications,
    ),
  );
}

Slot _slotWithOutputAndMode() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 12,
      defaultValue: 5,
      unit: 1,
      name: 'Output A',
      powerOfTen: 0,
      ioFlags: 2,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 1,
      defaultValue: 1,
      unit: 1,
      name: 'Output A mode',
      powerOfTen: 0,
      ioFlags: 8,
    ),
  ],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
