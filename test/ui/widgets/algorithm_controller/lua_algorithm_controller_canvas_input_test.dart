import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:nt_helper/services/offline_algorithm_shape_resolver.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_canvas_input.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/lua_algorithm_controller_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockMidiManager extends Mock implements IDistingMidiManager {}

typedef _RecordedWrite = ({
  int algorithmIndex,
  int parameterNumber,
  int value,
  bool changing,
});

const _overlappingTwoAxisSource = r'''
return {
  version = 1,
  title = "Synthetic Interactive Canvas",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.spacer { size = 160 },
      ui.canvas {
        semantics_label = "Synthetic interactive surface",
        aspect_ratio = 2,
        drag_threshold = 8,
        cycle_overlapping_selection = true,
        shapes = {
          ui.rect {
            x = 0,
            y = 0,
            width = 1,
            height = 1,
            fill = "surface_container_highest"
          },
          ui.circle { x = 0.5, y = 0.5, radius = 0.08, fill = "primary" }
        },
        targets = {
          {
            id = "t2",
            label = "Target Two",
            shape = "circle",
            x = 0.5,
            y = 0.5,
            radius = 0.08,
            selectable = true,
            order = 2,
            x_axis = { parameter = 3, from = 0, to = 1, step = 1 },
            y_axis = { parameter = 4, from = 0, to = 1, step = 1, invert = true },
            wheel = { parameter = 5, step = 5 }
          },
          {
            id = "t1",
            label = "Target One",
            shape = "circle",
            x = 0.5,
            y = 0.5,
            radius = 0.08,
            selectable = true,
            order = 1,
            x_axis = { parameter = 1, from = 0, to = 1, step = 1 },
            y_axis = { parameter = 2, from = 0, to = 1, step = 1, invert = true },
            wheel = { parameter = 5, step = 5 }
          },
          {
            id = "solo-x",
            label = "Solo Horizontal",
            shape = "rect",
            x = 0.05,
            y = 0.1,
            width = 0.15,
            height = 0.8,
            selectable = true,
            order = 3,
            x_axis = { parameter = 1, from = 0.05, to = 0.95, step = 5 }
          },
          {
            id = "solo-y",
            label = "Solo Vertical",
            shape = "rect",
            x = 0.8,
            y = 0.1,
            width = 0.15,
            height = 0.8,
            selectable = true,
            order = 4,
            y_axis = { parameter = 2, from = 0.1, to = 0.9, step = 10, invert = true },
            wheel = { parameter = 5, step = 5 }
          },
          {
            id = "disabled-target",
            label = "Disabled Target",
            shape = "circle",
            x = 0.3,
            y = 0.8,
            radius = 0.07,
            selectable = true,
            enabled = false,
            x_axis = { parameter = 1 },
            wheel = { parameter = 5, step = 5 }
          },
          {
            id = "select-only",
            label = "Selection Only",
            shape = "circle",
            x = 0.3,
            y = 0.2,
            radius = 0.07,
            selectable = true
          },
          {
            id = "missing-param",
            label = "Missing Param",
            shape = "circle",
            x = 0.7,
            y = 0.2,
            radius = 0.07,
            x_axis = { parameter = 99 },
            wheel = { parameter = 99, step = 5 }
          }
        }
      },
      ui.slider { label = "Standalone X", parameter = 1 },
      ui.spacer { size = 600 }
    }
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDistingCubit cubit;
  late List<_RecordedWrite> writes;
  late StreamController<DistingState> stateStream;
  late AppDatabase metadataDatabase;
  late Map<String, ({String source, Slot slot})> bundledFixtures;

  setUpAll(() async {
    final metadataSource = await File('assets/metadata/full_metadata.json')
        .readAsString();
    final bundle = jsonDecode(metadataSource) as Map<String, dynamic>;
    metadataDatabase = AppDatabase.forTesting(NativeDatabase.memory());
    expect(
      await MetadataImportService(metadataDatabase)
          .importFromJson(metadataSource),
      isTrue,
    );
    final resolver = OfflineAlgorithmShapeResolver(
      metadataDatabase.metadataDao,
    );
    final tables = Map<String, dynamic>.from(bundle['tables'] as Map);

    bundledFixtures = {};
    for (final testCase in const [
      (
        guid: 'mix1',
        name: 'Mixer Mono',
        asset: 'assets/algorithm_controllers/mixer_mono.lua',
      ),
      (
        guid: 'mix2',
        name: 'Mixer Stereo',
        asset: 'assets/algorithm_controllers/mixer_stereo.lua',
      ),
      (
        guid: 'eqpa',
        name: 'EQ Parametric',
        asset: 'assets/algorithm_controllers/parametric_eq.lua',
      ),
      (
        guid: 'fbnk',
        name: 'Filter bank',
        asset: 'assets/algorithm_controllers/filter_bank.lua',
      ),
    ]) {
      bundledFixtures[testCase.guid] = (
        source: await File(testCase.asset).readAsString(),
        slot: await _slotFromBundledMetadata(
          tables,
          resolver,
          guid: testCase.guid,
          name: testCase.name,
        ),
      );
    }
  });

  tearDownAll(() async {
    await metadataDatabase.close();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cubit = _MockDistingCubit();
    writes = <_RecordedWrite>[];
    stateStream = StreamController<DistingState>.broadcast();
    when(() => cubit.isClosed).thenReturn(false);
    when(() => cubit.state).thenReturn(const DistingState.initial());
    when(() => cubit.stream).thenAnswer((_) => stateStream.stream);
    when(
      () => cubit.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((invocation) async {
      writes.add((
        algorithmIndex: invocation.namedArguments[#algorithmIndex] as int,
        parameterNumber: invocation.namedArguments[#parameterNumber] as int,
        value: invocation.namedArguments[#value] as int,
        changing: invocation.namedArguments[#userIsChangingTheValue] as bool,
      ));
    });
  });

  tearDown(() async {
    await stateStream.close();
  });

  group('AC-02: selection, focus, overlap, drag capture, and cancellation', () {
    testWidgets(
      'click and sub-threshold movement select and focus without writes, and cycle overlapping targets deterministically',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final overlapCenter = canvasRect.center;

        // First click with sub-threshold jitter (4px < 8px threshold) selects t1.
        final click1 = await tester.startGesture(
          overlapCenter,
          kind: PointerDeviceKind.mouse,
        );
        await click1.moveBy(const Offset(4, 0));
        await click1.up();
        await tester.pump();

        expect(writes, isEmpty);
        expect(events.map((e) => (e.type, e.targetId)), [
          (AlgorithmControllerCanvasInteractionEventType.selected, 't1'),
        ]);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t1',
        );
        expect(
          tester
              .getSemantics(
                find.byKey(
                  const ValueKey('algorithm-controller-canvas-target:t1'),
                ),
              )
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        // Second click at identical center cycles deterministically t1 -> t2.
        await tester.tapAt(overlapCenter);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.last.targetId, 't2');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t2',
        );

        // Third click wraps t2 -> t1.
        await tester.tapAt(overlapCenter);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.last.targetId, 't1');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t1',
        );

        // Fourth click leaves t2 selected; dragging from the exact overlap
        // captures t2 only and release does not cycle back to t1.
        await tester.tapAt(overlapCenter);
        await tester.pump();
        expect(events.last.targetId, 't2');
        events.clear();

        final drag = await tester.startGesture(
          overlapCenter,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(
          Offset(canvasRect.left + canvasRect.width * 0.75, overlapCenter.dy),
        );
        await drag.up();
        await tester.pump();

        expect(
          writes.every((write) => write.parameterNumber == 3),
          isTrue,
          reason: 'only selected overlapping target t2 X parameter must write',
        );
        expect(writes.first.changing, isTrue);
        expect(writes.last.changing, isFalse);
        expect(writes.last.value, 75);
        expect(events.map((e) => (e.type, e.targetId)), [
          (AlgorithmControllerCanvasInteractionEventType.dragStart, 't2'),
          (AlgorithmControllerCanvasInteractionEventType.dragUpdate, 't2'),
          (AlgorithmControllerCanvasInteractionEventType.dragEnd, 't2'),
        ]);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t2',
        );

        semanticsHandle.dispose();
      },
    );

    testWidgets(
      'drag captures one pointer and stable target through overlap, bounds exit, and concurrent pointer',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final startPoint = canvasRect.center;

        // First drag captures t1 (deterministic order 1 when nothing selected).
        final primary = await tester.startGesture(
          startPoint,
          kind: PointerDeviceKind.mouse,
        );
        // Move below threshold: zero writes, no dragStart.
        await primary.moveBy(const Offset(5, 0));
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // Cross threshold and move to (0.8, 0.25) -> X=80, Y=75 (inverted).
        await primary.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.8,
            canvasRect.top + canvasRect.height * 0.25,
          ),
        );
        await tester.pump();

        // A second concurrent pointer on solo-y must be ignored (no retarget).
        final secondary = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.875,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          kind: PointerDeviceKind.touch,
        );
        await secondary.moveBy(const Offset(0, -40));
        await secondary.up();
        await tester.pump();

        // Move primary pointer outside canvas bounds (right and above):
        // target stays captured and values clamp to maximums (100, 100).
        await primary.moveTo(
          Offset(canvasRect.right + 120, canvasRect.top - 80),
        );
        await tester.pump();
        await primary.up();
        await tester.pump();

        // Only t1's parameters (1 and 2) were ever written.
        expect(writes.map((w) => w.parameterNumber).toSet(), {1, 2});
        final finalWrites = writes.where((w) => !w.changing).toList();
        expect(finalWrites, hasLength(2));
        expect(finalWrites.map((w) => (w.parameterNumber, w.value)), [
          (1, 100),
          (2, 100),
        ]);

        // Ordered lifecycle with exactly one terminal event.
        expect(
          events.first.type,
          AlgorithmControllerCanvasInteractionEventType.dragStart,
        );
        expect(
          events.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragEnd ||
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel,
          ),
          hasLength(1),
        );
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragEnd,
        );
        expect(events.every((e) => e.targetId == 't1'), isTrue);
      },
    );

    testWidgets(
      'preserves active drag capture across live parameter value updates on the same slot',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final slot = _syntheticSlot(p1: 50, p2: 50);
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: slot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final drag = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.6,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();

        // Simulate optimistic / live value update arriving on the same Slot instance.
        final updatedSlot = slot.copyWith(
          values: [
            for (final v in slot.values)
              v.parameterNumber == 1
                  ? ParameterValue(
                      algorithmIndex: v.algorithmIndex,
                      parameterNumber: 1,
                      value: 60,
                    )
                  : v,
          ],
        );
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: updatedSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pump();

        await drag.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.8,
            canvasRect.center.dy,
          ),
        );
        await drag.up();
        await tester.pump();

        expect(
          events.where(
            (e) =>
                e.type ==
                AlgorithmControllerCanvasInteractionEventType.dragCancel,
          ),
          isEmpty,
        );
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragEnd,
        );
        expect(writes.last.parameterNumber, 1);
        expect(writes.last.value, 80);
        expect(writes.last.changing, isFalse);
      },
    );

    testWidgets(
      'without overlap cycling enabled, repeated overlap clicks select the deterministic first target without writes',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const nonCyclingSource = r'''
return {
  version = 1,
  title = "Non-cycling overlap",
  root = ui.canvas {
    semantics_label = "Non-cycling surface",
    aspect_ratio = 2,
    shapes = {},
    targets = {
      {
        id = "second",
        label = "Second",
        shape = "circle",
        x = 0.5,
        y = 0.5,
        radius = 0.1,
        selectable = true,
        order = 2
      },
      {
        id = "first",
        label = "First",
        shape = "circle",
        x = 0.5,
        y = 0.5,
        radius = 0.1,
        selectable = true,
        order = 1
      }
    }
  }
}
''';

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: nonCyclingSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final center = tester.getCenter(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        await tester.tapAt(center);
        await tester.pump();
        await tester.tapAt(center);
        await tester.pump();

        expect(writes, isEmpty);
        expect(events.map((e) => e.targetId), ['first', 'first']);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:first',
        );
      },
    );

    testWidgets(
      'one-axis, disabled-axis, disabled-target, and selection-only targets write only eligible axes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(p2Disabled: false),
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );

        // 1-axis X target (solo-x, step=5) writes only parameter 1.
        final xDrag = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.12,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          kind: PointerDeviceKind.mouse,
        );
        await xDrag.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.725,
            canvasRect.top + canvasRect.height * 0.1,
          ),
        );
        await xDrag.up();
        await tester.pump();
        expect(writes, isNotEmpty);
        expect(writes.every((w) => w.parameterNumber == 1), isTrue);
        expect(writes.every((w) => w.value % 5 == 0), isTrue);
        expect(writes.last.value, 75);
        expect(writes.last.changing, isFalse);

        // 1-axis Y target (solo-y, step=10, inverted) writes only parameter 2.
        writes.clear();
        final yDrag = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.875,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          kind: PointerDeviceKind.mouse,
        );
        await yDrag.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.5,
            canvasRect.top + canvasRect.height * 0.1,
          ),
        );
        await yDrag.up();
        await tester.pump();
        expect(writes, isNotEmpty);
        expect(writes.every((w) => w.parameterNumber == 2), isTrue);
        expect(writes.last.value, 100);
        expect(writes.last.changing, isFalse);

        // Disabled target, selection-only target, and missing-param target emit zero writes.
        writes.clear();
        for (final normalized in const [
          Offset(0.3, 0.8), // disabled-target
          Offset(0.3, 0.2), // select-only
          Offset(0.7, 0.2), // missing-param
        ]) {
          final start = Offset(
            canvasRect.left + canvasRect.width * normalized.dx,
            canvasRect.top + canvasRect.height * normalized.dy,
          );
          final g = await tester.startGesture(
            start,
            kind: PointerDeviceKind.mouse,
          );
          await g.moveBy(const Offset(40, -20));
          await g.up();
          await tester.pump();
        }
        expect(writes, isEmpty);

        // Two-axis target with Y disabled writes only X.
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(p2Disabled: true),
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();
        writes.clear();

        final halfDisabledDrag = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await halfDisabledDrag.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.7,
            canvasRect.top + canvasRect.height * 0.2,
          ),
        );
        await halfDisabledDrag.up();
        await tester.pump();

        expect(writes, isNotEmpty);
        expect(writes.every((w) => w.parameterNumber == 1), isTrue);
      },
    );

    testWidgets(
      'pointer cancel and Escape clear active state immediately without final write or late writes',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );

        // 1. PointerCancelEvent
        final gesture1 = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await gesture1.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.7,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final countBeforeCancel = writes.length;
        expect(countBeforeCancel, greaterThan(0));
        expect(writes.every((w) => w.changing), isTrue);

        await gesture1.cancel();
        await tester.pump();

        // Cancel must not issue a final write or undo prior sent writes.
        expect(writes, hasLength(countBeforeCancel));
        expect(writes.where((w) => !w.changing), isEmpty);
        expect(
          events.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel ||
                e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
          ),
          hasLength(1),
        );
        expect(
          events.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.pointerCancel,
        );

        // 2. Escape key mid-drag + late move/up rejected
        writes.clear();
        events.clear();
        final gesture2 = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await gesture2.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.65,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final writesBeforeEscape = writes.length;
        expect(writesBeforeEscape, greaterThan(0));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        // Late move and release after Escape must emit zero writes & no 2nd terminal event.
        await gesture2.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await gesture2.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeEscape));
        expect(writes.where((w) => !w.changing), isEmpty);
        final terminalEvents = events.where(
          (e) =>
              e.type ==
                  AlgorithmControllerCanvasInteractionEventType.dragCancel ||
              e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
        );
        expect(terminalEvents, hasLength(1));
        expect(
          terminalEvents.single.cancelReason,
          AlgorithmControllerCanvasCancelReason.escapeKey,
        );
      },
    );

    testWidgets(
      'rejects late writes after disposal, slot replacement, binding replacement, and reconnect',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // --- Case A: Slot replacement mid-drag ---
        final initialSlot = _syntheticSlot();
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: initialSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final slotGesture = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await slotGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.65,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final writesBeforeSlotReplace = writes.length;
        expect(writesBeforeSlotReplace, greaterThan(0));

        // Replace with a brand-new Algorithm instance (new instanceIdentity).
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(slotIndex: 2),
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pump();

        await slotGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await slotGesture.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeSlotReplace));
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragCancel,
        );
        expect(
          events.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.slotChanged,
        );

        // --- Case B: Binding replacement mid-drag (same slot identity, target disabled/changed) ---
        writes.clear();
        events.clear();
        final persistentSlot = _syntheticSlot();
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: persistentSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final bindingGesture = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await bindingGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.65,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final writesBeforeBindingChange = writes.length;
        expect(writesBeforeBindingChange, greaterThan(0));

        // Same slot identity, but captured parameter 1 becomes disabled.
        final disabledParamSlot = persistentSlot.copyWith(
          values: [
            for (final v in persistentSlot.values)
              v.parameterNumber == 1
                  ? ParameterValue(
                      algorithmIndex: v.algorithmIndex,
                      parameterNumber: v.parameterNumber,
                      value: v.value,
                      isDisabled: true,
                    )
                  : v,
          ],
        );
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: disabledParamSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pump();

        await bindingGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await bindingGesture.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeBindingChange));
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragCancel,
        );
        expect(
          events.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.bindingChanged,
        );

        // --- Case C: Reconnect mid-drag ---
        writes.clear();
        events.clear();
        final managerA = _MockMidiManager();
        final managerB = _MockMidiManager();
        final syncSlot = _syntheticSlot();
        final syncedA = _synchronizedState(managerA, syncSlot);
        when(() => cubit.state).thenReturn(syncedA);

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: syncSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final reconnectGesture = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await reconnectGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.65,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final writesBeforeReconnect = writes.length;
        expect(writesBeforeReconnect, greaterThan(0));

        // Emit reconnect with new MIDI manager instance.
        final syncedB = _synchronizedState(managerB, syncSlot);
        when(() => cubit.state).thenReturn(syncedB);
        stateStream.add(syncedB);
        await tester.pump();

        await reconnectGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await reconnectGesture.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeReconnect));
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragCancel,
        );
        expect(
          events.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.reconnect,
        );

        // --- Case D: Disposal mid-drag ---
        writes.clear();
        events.clear();
        final disposeSlot = _syntheticSlot();
        final syncedDispose = _synchronizedState(managerB, disposeSlot);
        when(() => cubit.state).thenReturn(syncedDispose);

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: disposeSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final disposeGesture = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await disposeGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.65,
            canvasRect.center.dy,
          ),
        );
        await tester.pump();
        final writesBeforeDispose = writes.length;
        expect(writesBeforeDispose, greaterThan(0));

        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pump();
        await disposeGesture.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await disposeGesture.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeDispose));
        expect(
          events.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragCancel,
        );
        expect(
          events.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.disposed,
        );
      },
    );
  });

  group('AC-03: local hit geometry and scoped wheel routing', () {
    testWidgets(
      'routes hits accurately at two viewport sizes and scroll offsets',
      (tester) async {
        // Wide viewport, scroll offset 0 (canvas max-width capped at 720x360).
        await tester.binding.setSurfaceSize(const Size(1200, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(p5: 50),
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();

        final wideRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        expect(wideRect.width, 720);
        expect(wideRect.height, 360);

        final widePointer = TestPointer(1, PointerDeviceKind.mouse);
        final wideTargetCenter = Offset(
          wideRect.left + wideRect.width * 0.875,
          wideRect.top + wideRect.height * 0.5,
        );
        tester.binding.handlePointerEvent(widePointer.hover(wideTargetCenter));
        tester.binding.handlePointerEvent(
          widePointer.scroll(const Offset(0, -120)),
        );
        await tester.pump();

        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 5);
        expect(writes.single.value, 55);
        expect(writes.single.changing, isFalse);

        // Narrow viewport (380x500) + scrolled down inside SingleChildScrollView.
        writes.clear();
        await tester.binding.setSurfaceSize(const Size(380, 500));
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scrollable.position.jumpTo(140);
        await tester.pumpAndSettle();

        final narrowRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        expect(narrowRect.width, lessThan(wideRect.width));
        expect(narrowRect.top, lessThan(wideRect.top));

        final narrowPointer = TestPointer(2, PointerDeviceKind.mouse);
        final narrowTargetCenter = Offset(
          narrowRect.left + narrowRect.width * 0.875,
          narrowRect.top + narrowRect.height * 0.5,
        );
        tester.binding.handlePointerEvent(
          narrowPointer.hover(narrowTargetCenter),
        );
        tester.binding.handlePointerEvent(
          narrowPointer.scroll(const Offset(0, 120)),
        );
        await tester.pump();

        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 5);
        expect(writes.single.value, 45);
        expect(scrollable.position.pixels, 140);
      },
    );

    testWidgets(
      'consumes wheel only on one unambiguous eligible writable target and passes scroll through otherwise',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final baseSlot = _syntheticSlot(p5: 100);
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: baseSlot,
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final mouse = TestPointer(10, PointerDeviceKind.mouse);

        // 1. Eligible target at clamped max: wheel up consumes scroll and emits NO write.
        final soloY = Offset(
          canvasRect.left + canvasRect.width * 0.875,
          canvasRect.top + canvasRect.height * 0.5,
        );
        tester.binding.handlePointerEvent(mouse.hover(soloY));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -120)));
        await tester.pump();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, 0);

        // Eligible target wheel down steps from 100 -> 95 and consumes scroll.
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 120)));
        await tester.pump();
        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 5);
        expect(writes.single.value, 95);
        expect(scrollable.position.pixels, 0);

        // Helper asserting scroll passes through and produces zero writes.
        Future<void> expectScrollPassThrough(Offset point, String label) async {
          writes.clear();
          final before = scrollable.position.pixels;
          tester.binding.handlePointerEvent(mouse.hover(point));
          tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 60)));
          await tester.pump();
          expect(writes, isEmpty, reason: '$label must not write');
          expect(
            scrollable.position.pixels,
            greaterThan(before),
            reason: '$label must let parent SingleChildScrollView scroll',
          );
          scrollable.position.jumpTo(0);
          await tester.pump();
        }

        // 2. Background (no target hit)
        await expectScrollPassThrough(
          Offset(
            canvasRect.left + canvasRect.width * 0.5,
            canvasRect.top + canvasRect.height * 0.9,
          ),
          'background',
        );

        // 3. Ambiguous overlap (t1 + t2, even after selecting t1)
        await tester.tapAt(canvasRect.center);
        await tester.pump();
        await expectScrollPassThrough(canvasRect.center, 'ambiguous overlap');

        // 4. Unsupported target (wheel == null: solo-x)
        await expectScrollPassThrough(
          Offset(
            canvasRect.left + canvasRect.width * 0.12,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          'unsupported wheel target',
        );

        // 5. Disabled target (disabled-target)
        await expectScrollPassThrough(
          Offset(
            canvasRect.left + canvasRect.width * 0.3,
            canvasRect.top + canvasRect.height * 0.8,
          ),
          'disabled target',
        );

        // 6. Missing parameter target (missing-param)
        await expectScrollPassThrough(
          Offset(
            canvasRect.left + canvasRect.width * 0.7,
            canvasRect.top + canvasRect.height * 0.2,
          ),
          'missing parameter target',
        );

        // 7. Live disabled wheel parameter
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: baseSlot.copyWith(
              values: [
                for (final v in baseSlot.values)
                  v.parameterNumber == 5
                      ? ParameterValue(
                          algorithmIndex: v.algorithmIndex,
                          parameterNumber: v.parameterNumber,
                          value: v.value,
                          isDisabled: true,
                        )
                      : v,
              ],
            ),
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();
        await expectScrollPassThrough(soloY, 'live disabled wheel parameter');

        // 8. Stale session (cubit disconnected)
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: baseSlot,
            source: _overlappingTwoAxisSource,
          ),
        );
        await tester.pumpAndSettle();
        final disconnected = const DistingState.selectDevice(
          inputDevices: [],
          outputDevices: [],
          canWorkOffline: false,
        );
        when(() => cubit.state).thenReturn(disconnected);
        stateStream.add(disconnected);
        await tester.pump();
        await expectScrollPassThrough(soloY, 'stale disconnected session');
        // 4. Touch drag on canvas background scrolls SingleChildScrollView normally.
        writes.clear();
        scrollable.position.jumpTo(0);
        await tester.pump();
        final bgDrag = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.5,
            canvasRect.top + canvasRect.height * 0.9,
          ),
          kind: PointerDeviceKind.touch,
        );
        await bgDrag.moveBy(const Offset(0, -80));
        await bgDrag.up();
        await tester.pumpAndSettle();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));
      },
    );
  });

  group('AC-04: legacy compatibility and bundled controllers', () {
    testWidgets(
      'legacy paint-only canvas preserves geometry, semantics, scroll pass-through, and standalone controls',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(900, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const legacySource = r'''
return {
  version = 1,
  title = "Legacy Controller",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.canvas {
        semantics_label = "Legacy visual diagram",
        aspect_ratio = 4,
        shapes = {
          ui.rect { x = 0, y = 0, width = 1, height = 1, fill = "surface_container_highest" },
          ui.circle { x = 0.5, y = 0.5, radius = 0.1, fill = "primary" }
        }
      },
      ui.slider { label = "Param X", parameter = 1 },
      ui.spacer { size = 700 }
    }
  }
}
''';

        await tester.pumpWidget(
          _Harness(cubit: cubit, slot: _syntheticSlot(), source: legacySource),
        );
        await tester.pumpAndSettle();

        expect(find.byType(InteractiveAlgorithmControllerCanvas), findsNothing);
        final canvasFinder = find.bySemanticsLabel('Legacy visual diagram');
        expect(canvasFinder, findsOneWidget);
        expect(tester.getSize(canvasFinder), const Size(720, 180));
        final semData = tester.getSemantics(canvasFinder).getSemanticsData();
        expect(semData.flagsCollection.isImage, isTrue);

        // Wheel over legacy paint-only canvas scrolls parent with zero writes.
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final mouse = TestPointer(20, PointerDeviceKind.mouse);
        final center = tester.getCenter(canvasFinder);
        tester.binding.handlePointerEvent(mouse.hover(center));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 80)));
        await tester.pump();

        expect(writes, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));

        // Standalone slider control continues writing through DistingCubit.
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged!(64);
        slider.onChangeEnd!(64);
        expect(writes, hasLength(2));
        expect(writes[0].parameterNumber, 1);
        expect(writes[0].value, 64);
        expect(writes[0].changing, isTrue);
        expect(writes[1].changing, isFalse);

        semanticsHandle.dispose();
      },
    );

    testWidgets(
      'bundled mix1, mix2, eqpa, and visual-only fbnk render as paint-only canvases with scroll pass-through',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const cases = [
          (guid: 'mix1', asset: 'assets/algorithm_controllers/mixer_mono.lua'),
          (
            guid: 'mix2',
            asset: 'assets/algorithm_controllers/mixer_stereo.lua',
          ),
          (
            guid: 'eqpa',
            asset: 'assets/algorithm_controllers/parametric_eq.lua',
          ),
          (guid: 'fbnk', asset: 'assets/algorithm_controllers/filter_bank.lua'),
        ];

        for (final testCase in cases) {
          writes.clear();
          final fixture = bundledFixtures[testCase.guid]!;

          await tester.pumpWidget(
            _Harness(
              key: ValueKey('bundled:${testCase.guid}'),
              cubit: cubit,
              slot: fixture.slot,
              source: fixture.source,
              assetPath: testCase.asset,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byType(InteractiveAlgorithmControllerCanvas),
            findsNothing,
            reason: '${testCase.guid} must remain legacy paint-only',
          );
          final legacyCanvases = find.descendant(
            of: find.byType(LuaAlgorithmControllerView),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.image == true &&
                  (widget.properties.label?.isNotEmpty ?? false),
            ),
          );
          expect(
            legacyCanvases,
            findsWidgets,
            reason: '${testCase.guid} should render its preview canvas',
          );
          await tester.ensureVisible(legacyCanvases.first);
          await tester.pumpAndSettle();
          final firstCanvasSize = tester.getSize(legacyCanvases.first);
          expect(firstCanvasSize.width, greaterThan(0));
          expect(firstCanvasSize.width, lessThanOrEqualTo(720));
          expect(firstCanvasSize.height, greaterThan(0));

          final scrollable = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          final scrollBefore = scrollable.position.pixels;
          final pointer = TestPointer(
            100 + cases.indexOf(testCase),
            PointerDeviceKind.mouse,
          );
          final canvasCenter = tester.getCenter(legacyCanvases.first);
          tester.binding.handlePointerEvent(pointer.hover(canvasCenter));
          tester.binding.handlePointerEvent(
            pointer.scroll(const Offset(0, 80)),
          );
          await tester.pump();

          expect(
            writes,
            isEmpty,
            reason: '${testCase.guid} wheel over canvas must not write',
          );
          expect(
            scrollable.position.pixels,
            greaterThan(scrollBefore),
            reason: '${testCase.guid} wheel over canvas must pass to scroll',
          );
        }
      },
    );
  });
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.cubit,
    required this.slot,
    required this.source,
    this.assetPath = 'synthetic.lua',
    this.onCanvasInteraction,
  });

  final DistingCubit cubit;
  final Slot slot;
  final String source;
  final String assetPath;
  final ValueChanged<AlgorithmControllerCanvasInteractionEvent>?
  onCanvasInteraction;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final AlgorithmControllerSectionController _sectionController =
      AlgorithmControllerSectionController(initiallyCollapsed: false);

  Future<String> _loadSource(String _) async => widget.source;

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BlocProvider<DistingCubit>.value(
        value: widget.cubit,
        child: Scaffold(
          body: LuaAlgorithmControllerView(
            definition: AlgorithmControllerDefinition(
              id: 'test.synthetic',
              algorithmGuid: widget.slot.algorithm.guid,
              name: 'Synthetic controller',
              assetPath: widget.assetPath,
            ),
            slot: widget.slot,
            slotIndex: widget.slot.algorithm.algorithmIndex,
            units: const [],
            sectionController: _sectionController,
            sourceLoader: _loadSource,
            onCanvasInteraction: widget.onCanvasInteraction,
          ),
        ),
      ),
    );
  }
}

DistingStateSynchronized _synchronizedState(
  IDistingMidiManager manager,
  Slot slot, {
  bool loading = false,
}) {
  final slots = List<Slot>.generate(
    slot.algorithm.algorithmIndex + 1,
    (index) => index == slot.algorithm.algorithmIndex
        ? slot
        : _syntheticSlot(slotIndex: index),
  );
  return DistingState.synchronized(
    disting: manager,
    distingVersion: '1.19.0',
    firmwareVersion: FirmwareVersion('1.19.0'),
    presetName: 'Test',
    algorithms: const [],
    slots: slots,
    unitStrings: const [],
    loading: loading,
  ) as DistingStateSynchronized;
}

Slot _syntheticSlot({
  int slotIndex = 2,
  int p1 = 50,
  int p2 = 50,
  int p3 = 50,
  int p4 = 50,
  int p5 = 50,
  bool p2Disabled = false,
}) {
  final values = [0, p1, p2, p3, p4, p5];
  final names = ['Bypass', 'X1', 'Y1', 'X2', 'Y2', 'Q'];
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: slotIndex,
      guid: 'synt',
      name: 'Synthetic',
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(algorithmIndex: slotIndex, pages: const []),
    parameters: [
      for (var index = 0; index < values.length; index++)
        ParameterInfo(
          algorithmIndex: slotIndex,
          parameterNumber: index,
          min: 0,
          max: index == 0 ? 1 : 100,
          defaultValue: index == 0 ? 0 : 50,
          unit: 0,
          name: names[index],
          powerOfTen: 0,
        ),
    ],
    values: [
      for (var index = 0; index < values.length; index++)
        ParameterValue(
          algorithmIndex: slotIndex,
          parameterNumber: index,
          value: values[index],
          isDisabled: index == 2 && p2Disabled,
        ),
    ],
    enums: [
      for (var index = 0; index < values.length; index++)
        ParameterEnumStrings(
          algorithmIndex: slotIndex,
          parameterNumber: index,
          values: index == 0 ? const ['Off', 'On'] : const [],
        ),
    ],
    mappings: [for (final _ in values) Mapping.filler()],
    valueStrings: [
      for (var index = 0; index < values.length; index++)
        ParameterValueString(
          algorithmIndex: slotIndex,
          parameterNumber: index,
          value: '',
        ),
    ],
  );
}

Future<Slot> _slotFromBundledMetadata(
  Map<String, dynamic> tables,
  OfflineAlgorithmShapeResolver resolver, {
  required String guid,
  required String name,
}) async {
  const algorithmIndex = 7;
  final specificationRows =
      [
        for (final row in tables['specifications'] as List)
          Map<String, dynamic>.from(row as Map),
      ].where((row) => row['algorithmGuid'] == guid).toList()..sort(
        (left, right) => ((left['specIndex'] as num?)?.toInt() ?? 0).compareTo(
          (right['specIndex'] as num?)?.toInt() ?? 0,
        ),
      );
  final specifications = [
    for (final row in specificationRows)
      (row['defaultValue'] as num?)?.toInt() ?? 0,
  ];
  final resolved = await resolver.resolve(guid, specifications);
  final snapshot = resolved.snapshot;
  final parameters = snapshot.parameters;

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: algorithmIndex,
      guid: guid,
      name: name,
      specifications: specifications,
    ),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: [
        for (var pageIndex = 0; pageIndex < snapshot.pages.length; pageIndex++)
          ParameterPage(
            name: snapshot.pages[pageIndex].name,
            parameters: [
              for (final membership in snapshot.pageMemberships)
                if (membership.pageIndex == pageIndex)
                  membership.parameterNumber,
            ]..sort(),
          ),
      ],
    ),
    parameters: [
      for (var number = 0; number < parameters.length; number++)
        ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          min: parameters[number].min,
          max: parameters[number].max,
          defaultValue: parameters[number].defaultValue,
          unit: parameters[number].rawUnitIndex,
          name: parameters[number].name,
          powerOfTen: parameters[number].powerOfTen,
          ioFlags: parameters[number].ioFlags,
        ),
    ],
    values: [
      for (var number = 0; number < parameters.length; number++)
        ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          value: parameters[number].defaultValue,
        ),
    ],
    enums: [
      for (var number = 0; number < parameters.length; number++)
        ParameterEnumStrings(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          values: parameters[number].enumStrings,
        ),
    ],
    mappings: [for (final _ in parameters) Mapping.filler()],
    valueStrings: [
      for (var number = 0; number < parameters.length; number++)
        ParameterValueString(
          algorithmIndex: algorithmIndex,
          parameterNumber: number,
          value: '',
        ),
    ],
  );
}
