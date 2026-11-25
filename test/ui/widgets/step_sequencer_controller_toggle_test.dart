import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/algorithm_registry.dart';
import 'package:nt_helper/ui/notes_algorithm_view.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import 'package:nt_helper/ui/step_sequencer_view.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/lua_algorithm_controller_view.dart';
import 'package:nt_helper/ui/widgets/parameter_spreadsheet_view.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/ui/widgets/section_parameter_list_view.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_action_bar.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/playback_controls.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/bit_pattern_editor.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/quantize_controls.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/sequence_selector.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_column_widget.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_grid_view.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_sequencer_edit_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/step_sequencer_slot_fixture.dart';

class _Cubit extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

const _controller = ValueKey('slot-editor-mode-controller');
const _standard = ValueKey('slot-editor-mode-standard');
const _spreadsheet = ValueKey('slot-editor-mode-spreadsheet');

class _Harness extends StatefulWidget {
  final Slot slot;
  final int slotIndex;
  final bool enabled;
  final bool unavailableOffline;
  final SectionParameterController sections;
  const _Harness({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.sections,
    this.enabled = true,
    this.unavailableOffline = false,
  });
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  SlotEditorMode mode = SlotEditorMode.standard;
  final controllerSections = AlgorithmControllerSectionController(
    initiallyCollapsed: false,
  );
  @override
  void dispose() {
    controllerSections.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlotDetailView(
    key: ValueKey((widget.slotIndex, widget.slot.algorithm.guid)),
    slot: widget.slot,
    slotIndex: widget.slotIndex,
    units: const [],
    firmwareVersion: FirmwareVersion('1.20.0beta'),
    sectionController: widget.sections,
    algorithmControllerSections: controllerSections,
    editorMode: mode,
    editorModeEnabled: widget.enabled,
    unavailableOffline: widget.unavailableOffline,
    onEditorModeChanged: (value) => setState(() => mode = value),
  );
}

void main() {
  late _Cubit cubit;
  late DistingState state;
  late StreamController<DistingState> states;
  late Slot slot;
  late _Manager manager;
  late SectionParameterController sections;
  late GlobalKey<_HarnessState> harness;

  DistingStateSynchronized synchronized(
    List<Slot> slots, {
    IDistingMidiManager? device,
    bool offline = false,
    bool demo = false,
  }) => DistingStateSynchronized(
    disting: device ?? manager,
    distingVersion: '1.20.0beta',
    firmwareVersion: FirmwareVersion('1.20.0beta'),
    presetName: 'Toggle tests',
    algorithms: const [],
    slots: slots,
    unitStrings: const [],
    offline: offline,
    demo: demo,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cubit = _Cubit();
    manager = _Manager();
    slot = stepSequencerSlot();
    state = synchronized([slot]);
    states = StreamController<DistingState>.broadcast(sync: true);
    sections = SectionParameterController();
    harness = GlobalKey<_HarnessState>();
    when(() => cubit.state).thenAnswer((_) => state);
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.isClosed).thenReturn(false);
    when(
      () => cubit.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
    when(() => cubit.scheduleParameterRefresh(any())).thenReturn(null);
  });

  tearDown(() async {
    await states.close();
    sections.dispose();
  });

  Widget app({
    Slot? selected,
    int index = 0,
    bool enabled = true,
    bool unavailable = false,
    double textScale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: BlocProvider<DistingCubit>.value(
      value: cubit,
      child: Scaffold(
        body: _Harness(
          key: harness,
          slot: selected ?? slot,
          slotIndex: index,
          sections: sections,
          enabled: enabled,
          unavailableOffline: unavailable,
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(_controller));
    await tester.pumpAndSettle();
    expect(find.byType(StepSequencerView), findsOneWidget);
  }

  void emit(DistingState next) {
    state = next;
    states.add(next);
  }

  void noWrites() => verifyNever(
    () => cubit.updateParameterValue(
      algorithmIndex: any(named: 'algorithmIndex'),
      parameterNumber: any(named: 'parameterNumber'),
      value: any(named: 'value'),
      userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
    ),
  );

  test('registry separates native alternate from standard and Lua editors', () {
    final version = FirmwareVersion('1.0');
    expect(slot.parameters.length, 215);
    expect(AlgorithmViewRegistry.findViewFor(slot, 0, version), isNull);
    final alternate = AlgorithmViewRegistry.findAlternateForGuid('spsq')!;
    expect(alternate.name, 'Step Sequencer editor');
    expect(alternate.builder(slot, 0, version), isA<StepSequencerView>());
    expect(AlgorithmControllerRegistry.bundled.findForGuid('spsq'), isNull);
    for (final guid in ['spsh', 'seq ', 'ensq', 'note', 'ThPh', 'unknown']) {
      expect(AlgorithmViewRegistry.findAlternateForGuid(guid), isNull);
    }
    expect(AlgorithmControllerRegistry.bundled.findForGuid('ensq'), isNotNull);
    Slot named(String guid) => slot.copyWith(
      algorithm: Algorithm(algorithmIndex: 0, guid: guid, name: guid),
    );
    expect(
      AlgorithmViewRegistry.findViewFor(named('note'), 0, version),
      isA<NotesAlgorithmView>(),
    );
    expect(
      AlgorithmViewRegistry.findViewFor(named('ThPh'), 0, version),
      isA<PatchMapAlgorithmView>(),
    );
  });

  testWidgets(
    'default Standard contains real pages and shared toggle opens native editor',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      expect(find.byType(SectionParameterListView), findsOneWidget);
      expect(find.byType(StepSequencerView, skipOffstage: false), findsNothing);
      expect(find.byTooltip('Step Sequencer editor'), findsOneWidget);
      expect(
        tester
            .widget<SectionParameterListView>(
              find.byType(SectionParameterListView),
            )
            .pages,
        slot.pages,
      );
      tester
          .widget<IconButton>(find.byKey(_controller))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.byType(StepSequencerView), findsOneWidget);
      expect(find.byType(LuaAlgorithmControllerView), findsNothing);
      expect(find.byType(SlotEditorActionBar), findsOneWidget);
      expect(find.byKey(_controller), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byKey(_controller)).isSelected,
        isTrue,
      );
      expect(find.text('Pitch'), findsWidgets);
      noWrites();
    },
  );

  testWidgets(
    'same-slot toggles retain native lane and quantize settings but exclude hidden focus and semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await open(tester);
        expect(
          find.bySemanticsLabel('Show Step Sequencer editor'),
          findsOneWidget,
        );
        final original = tester.state(find.byType(StepSequencerView));
        var quantize = tester.widget<QuantizeControls>(
          find.byType(QuantizeControls),
        );
        quantize.onToggleSnap();
        quantize.onScaleChanged('Minor');
        quantize.onRootNoteChanged(5);
        await tester.pump();
        await tester.tap(find.text('Velocity').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_standard));
        await tester.pumpAndSettle();
        expect(find.byType(StepSequencerView), findsNothing);
        expect(find.byType(StepGridView), findsNothing);
        expect(find.byType(SlotEditorActionBar), findsOneWidget);
        final retained = find.byType(StepSequencerView, skipOffstage: false);
        expect(tester.state(retained), same(original));
        final exclusion = tester.widget<ExcludeFocus>(
          find
              .ancestor(
                of: retained,
                matching: find.byType(ExcludeFocus, skipOffstage: false),
              )
              .first,
        );
        expect(exclusion.excluding, isTrue);
        expect(find.bySemanticsLabel(RegExp(r'^Step 1, ')), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        await tester.tap(find.byKey(_spreadsheet));
        await tester.pumpAndSettle();
        expect(find.byType(ParameterSpreadsheetView), findsOneWidget);
        await tester.tap(find.byKey(_controller));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(StepSequencerView)), same(original));
        expect(
          tester
              .widget<StepGridView>(find.byType(StepGridView))
              .activeParameter,
          StepParameter.velocity,
        );
        await tester.tap(find.text('Pitch').first);
        await tester.pumpAndSettle();
        quantize = tester.widget<QuantizeControls>(
          find.byType(QuantizeControls),
        );
        expect(quantize.snapEnabled, isTrue);
        expect(quantize.selectedScale, 'Minor');
        expect(quantize.rootNote, 5);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'SlotDetailView.controller',
        );
        expect(find.byType(SlotEditorActionBar), findsOneWidget);
        noWrites();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'accepted playback input settles before another editor is enabled',
    (tester) async {
      await open(tester);
      final playback = find.byType(PlaybackControls);
      final slider = tester.widget<Slider>(
        find.descendant(of: playback, matching: find.byType(Slider)).last,
      );
      slider.onChanged!(42);
      await tester.tap(find.byKey(_standard));
      final parameter = slot.parameters.indexWhere((p) => p.name == 'Glide');
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: parameter,
          value: 42,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      await tester.pump(const Duration(milliseconds: 100));
      noWrites();
    },
  );

  for (final change in [
    'disconnect',
    'manager',
    'algorithm',
    'sequence',
    'remove',
  ]) {
    testWidgets('pending grid input cannot target a changed $change context', (
      tester,
    ) async {
      await open(tester);
      final drag = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(StepGridView),
              matching: find.byWidgetPredicate(
                (w) => w is GestureDetector && w.onPanStart != null,
              ),
            )
            .first,
      );
      drag.onPanStart!(
        DragStartDetails(
          globalPosition: tester.getCenter(find.byType(StepColumnWidget).first),
        ),
      );
      final sync = state as DistingStateSynchronized;
      switch (change) {
        case 'disconnect':
          emit(const DistingState.initial());
        case 'manager':
          emit(sync.copyWith(disting: _Manager()));
        case 'algorithm':
          emit(sync.copyWith(slots: [stepSequencerSlot()]));
        case 'sequence':
          final sequence = slot.parameters.indexWhere(
            (p) => p.name == 'Sequence',
          );
          emit(
            sync.copyWith(
              slots: [
                slot.copyWith(
                  values: [
                    for (final value in slot.values)
                      value.parameterNumber == sequence
                          ? ParameterValue(
                              algorithmIndex: value.algorithmIndex,
                              parameterNumber: value.parameterNumber,
                              value: 2,
                            )
                          : value,
                  ],
                ),
              ],
            ),
          );
        case 'remove':
          emit(sync.copyWith(slots: const []));
      }
      await tester.pump(const Duration(milliseconds: 60));
      noWrites();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  for (final bounds in [(1, 32, 32), (0, 31, 31)]) {
    testWidgets('native sequence uses metadata bounds $bounds', (tester) async {
      slot = stepSequencerSlot(
        sequenceMin: bounds.$1,
        sequenceMax: bounds.$2,
        sequence: bounds.$3,
      );
      emit(synchronized([slot]));
      await open(tester);
      final selector = tester.widget<SequenceSelector>(
        find.byType(SequenceSelector),
      );
      expect(selector.currentSequence, bounds.$3);
      expect(selector.minValue, bounds.$1);
      expect(selector.maxValue, bounds.$2);
      expect(tester.takeException(), isNull);
      noWrites();
    });
  }

  testWidgets(
    'hidden editor receives immutable values and manager replacement resets local state',
    (tester) async {
      await open(tester);
      final original = tester.state(find.byType(StepSequencerView));
      await tester.tap(find.text('Velocity').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_standard));
      await tester.pumpAndSettle();
      final sequence = slot.parameters.indexWhere((p) => p.name == 'Sequence');
      slot = slot.copyWith(
        values: [
          for (final value in slot.values)
            value.parameterNumber == sequence
                ? ParameterValue(
                    algorithmIndex: value.algorithmIndex,
                    parameterNumber: value.parameterNumber,
                    value: 32,
                  )
                : value,
        ],
      );
      emit(synchronized([slot]));
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(_controller));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(StepSequencerView)), same(original));
      expect(
        tester
            .widget<SequenceSelector>(find.byType(SequenceSelector))
            .currentSequence,
        32,
      );
      emit(synchronized([slot], device: _Manager()));
      await tester.pump();
      expect(
        tester.state(find.byType(StepSequencerView)),
        isNot(same(original)),
      );
      expect(
        tester.widget<StepGridView>(find.byType(StepGridView)).activeParameter,
        StepParameter.pitch,
      );
    },
  );

  testWidgets(
    'unsupported slot fallback preserves workspace Controller request',
    (tester) async {
      await open(tester);
      final unsupported = slot.copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsh',
          name: 'Step Sequencer Head',
        ),
      );
      await tester.pumpWidget(app(selected: unsupported));
      await tester.pumpAndSettle();
      expect(find.byKey(_controller), findsNothing);
      expect(find.byType(SectionParameterListView), findsOneWidget);
      expect(harness.currentState!.mode, SlotEditorMode.controller);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(StepSequencerView), findsOneWidget);
      noWrites();
    },
  );

  testWidgets(
    'disabled toggle cannot select native and unavailable offline has no editor',
    (tester) async {
      await tester.pumpWidget(app(enabled: false));
      expect(
        tester.widget<IconButton>(find.byKey(_controller)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_controller));
      await tester.pump();
      expect(harness.currentState!.mode, SlotEditorMode.standard);
      await tester.pumpWidget(app(unavailable: true));
      await tester.pump();
      expect(find.byKey(_controller), findsNothing);
      expect(find.textContaining('unavailable offline'), findsOneWidget);
      noWrites();
    },
  );

  for (final mode in ['offline', 'demo']) {
    testWidgets(
      'valid $mode snapshot uses the same native Controller dispatcher',
      (tester) async {
        emit(
          synchronized(
            [slot],
            offline: mode == 'offline',
            demo: mode == 'demo',
          ),
        );
        await open(tester);
        expect(find.byType(StepSequencerView), findsOneWidget);
        noWrites();
      },
    );
  }

  testWidgets('native page shortcuts do not target Lua sections', (
    tester,
  ) async {
    await open(tester);
    sections.goToPage(
      0,
      slot.pages.pages.indexWhere(
        (p) => p.parameters.length == 1 && p.parameters.single == 0,
      ),
    );
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'SlotDetailView.bypass',
    );
    expect(harness.currentState!.controllerSections.sectionsCollapsed, isFalse);
  });
  testWidgets(
    'grid debounce survives a mode toggle and targets the real slot',
    (tester) async {
      final first = stepSequencerSlot();
      slot = stepSequencerSlot(index: 1);
      emit(synchronized([first, slot]));
      await tester.pumpWidget(app(index: 1));
      await tester.tap(find.byKey(_controller));
      await tester.pumpAndSettle();
      final drag = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(StepGridView),
              matching: find.byWidgetPredicate(
                (w) => w is GestureDetector && w.onPanStart != null,
              ),
            )
            .first,
      );
      drag.onPanStart!(
        DragStartDetails(
          globalPosition: tester.getCenter(find.byType(StepColumnWidget).first),
        ),
      );
      await tester.tap(find.byKey(_standard));
      await tester.pump(const Duration(milliseconds: 51));
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 1,
          parameterNumber: 1,
          value: any(named: 'value'),
          userIsChangingTheValue: true,
        ),
      ).called(1);
      noWrites();
    },
  );

  testWidgets(
    'sequence refresh is cancelled after disconnect without extra writes',
    (tester) async {
      await open(tester);
      tester
          .widget<SequenceSelector>(find.byType(SequenceSelector))
          .onSequenceChanged(2);
      await tester.pump();
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 207,
          value: 2,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      emit(const DistingState.initial());
      await tester.pump(const Duration(milliseconds: 101));
      verifyNever(() => cubit.scheduleParameterRefresh(any()));
      noWrites();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('randomize pulse never resets a replacement algorithm', (
    tester,
  ) async {
    await open(tester);
    tester
        .widget<PopupMenuButton<String>>(
          find
              .descendant(
                of: find.byType(StepSequencerView),
                matching: find.byType(PopupMenuButton<String>),
              )
              .first,
        )
        .onSelected!('randomize');
    await tester.pump();
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 171,
        value: 1,
        userIsChangingTheValue: true,
      ),
    ).called(1);
    emit(synchronized([stepSequencerSlot()]));
    await tester.pump(const Duration(milliseconds: 101));
    noWrites();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'quantize undo survives toggles but is cleared by a sequence change',
    (tester) async {
      slot = slot.copyWith(
        values: [
          for (final value in slot.values)
            value.parameterNumber == 1
                ? ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: 1,
                    value: 49,
                  )
                : value,
        ],
      );
      emit(synchronized([slot]));
      await open(tester);
      tester
          .widget<QuantizeControls>(find.byType(QuantizeControls))
          .onQuantizeAll();
      await tester.pump(const Duration(milliseconds: 11));
      expect(
        tester.widget<QuantizeControls>(find.byType(QuantizeControls)).canUndo,
        isTrue,
      );
      await tester.tap(find.byKey(_standard));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_controller));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QuantizeControls>(find.byType(QuantizeControls)).canUndo,
        isTrue,
      );
      slot = slot.copyWith(
        values: [
          for (final value in slot.values)
            value.parameterNumber == 207
                ? ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: 207,
                    value: 2,
                  )
                : value,
        ],
      );
      emit(synchronized([slot]));
      await tester.pumpWidget(app());
      await tester.pump();
      expect(
        tester.widget<QuantizeControls>(find.byType(QuantizeControls)).canUndo,
        isFalse,
      );
    },
  );

  testWidgets(
    'unrelated snapshots preserve playback text drafts across a mode toggle',
    (tester) async {
      await open(tester);
      final fields = find.descendant(
        of: find.byType(PlaybackControls),
        matching: find.byType(TextFormField),
      );
      final start = tester.widget<TextFormField>(fields.first).controller!;
      start.value = const TextEditingValue(
        text: '12',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.tap(find.byKey(_standard));
      await tester.pumpAndSettle();
      slot = slot.copyWith(
        values: [
          for (final value in slot.values)
            value.parameterNumber == 1
                ? ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: 1,
                    value: 55,
                  )
                : value,
        ],
      );
      emit(synchronized([slot]));
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(_controller));
      await tester.pumpAndSettle();
      final updated = tester.widget<TextFormField>(fields.first).controller!;
      expect(updated, same(start));
      expect(updated.text, '12');
      expect(updated.selection.baseOffset, 1);
      noWrites();
    },
  );

  for (final size in [(320.0, 1.0), (600.0, 2.0), (1200.0, 1.0)]) {
    testWidgets(
      'header remains fixed across modes and sequence loading at $size',
      (tester) async {
        tester.view.physicalSize = Size(size.$1, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(app(textScale: size.$2));
        final before = tester.getRect(find.byKey(_controller));
        await tester.tap(find.byKey(_controller));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(_controller)), before);
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(StepSequencerView)),
          ).scale(10),
          size.$2 * 10,
        );
        final dropdown = find.descendant(
          of: find.byType(SequenceSelector),
          matching: find.byType(DropdownButtonFormField<int>),
        );
        final rect = tester.getRect(dropdown);
        tester
            .widget<SequenceSelector>(find.byType(SequenceSelector))
            .onSequenceChanged(2);
        await tester.pump();
        expect(tester.getRect(dropdown), rect);
        expect(tester.getRect(find.byKey(_controller)), before);
        await tester.pump(const Duration(milliseconds: 101));
        expect(tester.getRect(dropdown), rect);
      },
    );
  }
  Slot sequenceValue(Slot value, int sequence) => value.copyWith(
    values: [
      for (final p in value.values)
        p.parameterNumber == 207
            ? ParameterValue(
                algorithmIndex: p.algorithmIndex,
                parameterNumber: 207,
                value: sequence,
              )
            : p,
    ],
  );

  void startGrid(WidgetTester tester) {
    final drag = tester.widget<GestureDetector>(
      find
          .descendant(
            of: find.byType(StepGridView),
            matching: find.byWidgetPredicate(
              (w) => w is GestureDetector && w.onPanStart != null,
            ),
          )
          .first,
    );
    drag.onPanStart!(
      DragStartDetails(
        globalPosition: tester.getCenter(find.byType(StepColumnWidget).first),
      ),
    );
  }

  test('stale displayed sequence cannot acquire a current edit scope', () {
    final oldUi = slot;
    emit(synchronized([sequenceValue(slot, 2)]));
    final scope = StepSequencerEditScope.capture(cubit, 0, oldUi);
    expect(scope, isNull);
    expect(oldUi.values[207].value, 1);
  });

  testWidgets('stale grid callback cannot write to a newer sequence', (
    tester,
  ) async {
    await open(tester);
    emit(synchronized([sequenceValue(slot, 2)]));
    // No pump: the displayed grid still belongs to sequence 1.
    startGrid(tester);
    await tester.pump(const Duration(milliseconds: 51));
    noWrites();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('scope invalidation is permanent after a sequence round trip', () {
    final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
    emit(synchronized([sequenceValue(slot, 2)]));
    expect(scope.isCurrent, isFalse);
    emit(synchronized([slot]));
    expect(scope.isCurrent, isFalse);
    scope.dispose();
    expect(states.hasListener, isFalse);
  });

  testWidgets(
    'pending grid edit is cancelled by departure even if its sequence returns',
    (tester) async {
      await open(tester);
      startGrid(tester);
      emit(synchronized([sequenceValue(slot, 2)]));
      emit(synchronized([slot]));
      await tester.pump(const Duration(milliseconds: 51));
      noWrites();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Randomise cleanup follows algorithm lifetime rather than sequence',
    (tester) async {
      await open(tester);
      tester
          .widget<PopupMenuButton<String>>(
            find
                .descendant(
                  of: find.byType(StepSequencerView),
                  matching: find.byType(PopupMenuButton<String>),
                )
                .first,
          )
          .onSelected!('randomize');
      await tester.pump();
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 171,
          value: 1,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      slot = sequenceValue(slot, 2).copyWith(
        values: [
          for (final p in sequenceValue(slot, 2).values)
            p.parameterNumber == 171
                ? ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: 171,
                    value: 1,
                  )
                : p,
        ],
      );
      emit(synchronized([slot]));
      await tester.pump(const Duration(milliseconds: 101));
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 171,
          value: 0,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      noWrites();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('visual style copies retain drafts and accepted grid input', (
    tester,
  ) async {
    await open(tester);
    final oldState = tester.state(find.byType(StepSequencerView));
    tester
        .widget<QuantizeControls>(find.byType(QuantizeControls))
        .onScaleChanged('Minor');
    await tester.pump();
    startGrid(tester);
    slot = slot.copyWith(
      algorithm: slot.algorithm.copyWith(
        visualStyle: const AlgorithmVisualStyle(leftIndent: 1),
      ),
    );
    emit(synchronized([slot]));
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 51));
    expect(tester.state(find.byType(StepSequencerView)), same(oldState));
    expect(
      tester
          .widget<QuantizeControls>(find.byType(QuantizeControls))
          .selectedScale,
      'Minor',
    );
    verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 1,
        value: any(named: 'value'),
        userIsChangingTheValue: true,
      ),
    ).called(1);
    noWrites();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('newer Standard intent follows the flushed native edit', (
    tester,
  ) async {
    await open(tester);
    final nativeSlider = tester.widget<Slider>(
      find
          .descendant(
            of: find.byType(PlaybackControls),
            matching: find.byType(Slider),
          )
          .last,
    );
    nativeSlider.onChanged!(42);
    await tester.tap(find.byKey(_standard));
    await tester.pump();
    final row = find.byWidgetPredicate(
      (w) => w is ParameterViewRow && w.name == 'Glide',
    );
    expect(row, findsOneWidget);
    final standardSlider = tester.widget<Slider>(
      find.descendant(of: row, matching: find.byType(Slider)),
    );
    standardSlider.onChangeStart!(0);
    standardSlider.onChanged!(55);
    await tester.pump(const Duration(milliseconds: 51));
    final parameter = slot.parameters.indexWhere((p) => p.name == 'Glide');
    final sent = verify(
      () => cubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: parameter,
        value: captureAny(named: 'value'),
        userIsChangingTheValue: true,
      ),
    ).captured;
    expect(sent, [42, 55]);
    noWrites();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'switching Standard to native and back keeps the latest intent last',
    (tester) async {
      await tester.pumpWidget(app());
      void editStandard(int value) {
        final row = find.byWidgetPredicate(
          (w) => w is ParameterViewRow && w.name == 'Glide',
        );
        final slider = tester.widget<Slider>(
          find.descendant(of: row, matching: find.byType(Slider)),
        );
        slider.onChangeStart!(0);
        slider.onChanged!(value.toDouble());
      }

      editStandard(55);
      await tester.tap(find.byKey(_controller));
      await tester.pump();
      tester
          .widget<Slider>(
            find
                .descendant(
                  of: find.byType(PlaybackControls),
                  matching: find.byType(Slider),
                )
                .last,
          )
          .onChanged!(42);
      await tester.tap(find.byKey(_standard));
      await tester.pump();
      editStandard(66);
      await tester.pump(const Duration(milliseconds: 51));
      final parameter = slot.parameters.indexWhere((p) => p.name == 'Glide');
      final sent = verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: parameter,
          value: captureAny(named: 'value'),
          userIsChangingTheValue: true,
        ),
      ).captured;
      expect(sent, [55, 42, 66]);
      noWrites();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'fresh grid render accepts its displayed sequence before parent props update',
    (tester) async {
      await open(tester);
      emit(synchronized([sequenceValue(slot, 2)]));
      await tester.pump();
      startGrid(tester);
      await tester.pump(const Duration(milliseconds: 51));
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: any(named: 'value'),
          userIsChangingTheValue: true,
        ),
      ).called(1);
      noWrites();
    },
  );

  testWidgets(
    'bit editor cannot submit a callback from the departed sequence',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Pattern').first);
      await tester.pumpAndSettle();
      final bit = tester.widget<BitPatternEditor>(
        find.byType(BitPatternEditor).first,
      );
      emit(synchronized([sequenceValue(slot, 2)]));
      bit.onChanged(0);
      noWrites();
    },
  );

  testWidgets(
    'fresh playback controls accept their displayed sequence before parent props update',
    (tester) async {
      await open(tester);
      emit(synchronized([sequenceValue(slot, 2)]));
      await tester.pump();
      tester
          .widget<Slider>(
            find
                .descendant(
                  of: find.byType(PlaybackControls),
                  matching: find.byType(Slider),
                )
                .last,
          )
          .onChanged!(42);
      await tester.pump(const Duration(milliseconds: 51));
      final glide = slot.parameters.indexWhere((p) => p.name == 'Glide');
      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: glide,
          value: 42,
          userIsChangingTheValue: true,
        ),
      ).called(1);
      noWrites();
    },
  );
}
