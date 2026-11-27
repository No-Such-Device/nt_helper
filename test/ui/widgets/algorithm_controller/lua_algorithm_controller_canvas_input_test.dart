import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
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

        // Second primary mouse click at identical center cycles deterministically t1 -> t2.
        await _mouseClick(tester, overlapCenter);
        expect(writes, isEmpty);
        expect(events.last.targetId, 't2');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t2',
        );

        // Third primary mouse click wraps t2 -> t1.
        await _mouseClick(tester, overlapCenter);
        expect(writes, isEmpty);
        expect(events.last.targetId, 't1');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:t1',
        );

        // Fourth primary mouse click leaves t2 selected; dragging from the exact overlap
        // captures t2 only and release does not cycle back to t1.
        await _mouseClick(tester, overlapCenter);
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

        // A second concurrent mouse or touch pointer on solo-y must be ignored (no retarget).
        final secondaryMouse = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.875,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          kind: PointerDeviceKind.mouse,
        );
        await secondaryMouse.moveBy(const Offset(0, -40));
        await secondaryMouse.up();
        await tester.pump();

        final secondaryTouch = await tester.startGesture(
          Offset(
            canvasRect.left + canvasRect.width * 0.875,
            canvasRect.top + canvasRect.height * 0.5,
          ),
          kind: PointerDeviceKind.touch,
        );
        await secondaryTouch.moveBy(const Offset(0, -40));
        await secondaryTouch.up();
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
        await _mouseClick(tester, center);
        await _mouseClick(tester, center);

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
      'pointer cancel and Escape settle dirty axes once with changing:false (not undo) and reject late writes',
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

        // 1. PointerCancelEvent: X moved from 50 -> 70, Y unchanged at 50.
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
        final lastWriteBeforeCancel = writes.last;
        expect(lastWriteBeforeCancel.parameterNumber, 1);
        expect(lastWriteBeforeCancel.value, 70);

        await gesture1.cancel();
        await tester.pump();

        // Same-session cancel settles ONLY already-edited axis X once at its
        // last accepted value (70, not undone to 50) with changing:false.
        expect(writes, hasLength(countBeforeCancel + 1));
        final settledCancelWrites = writes.where((w) => !w.changing).toList();
        expect(settledCancelWrites, hasLength(1));
        expect(settledCancelWrites.single.parameterNumber, 1);
        expect(settledCancelWrites.single.value, 70);
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
        expect(events.last.xValue, 70);
        expect(events.last.yValue, isNull);

        // 2. Escape key mid-drag settles dirty X once + late move/up rejected.
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
        expect(writes.last.parameterNumber, 1);
        expect(writes.last.value, 65);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        // Late move and release after Escape must emit zero extra writes & no 2nd terminal event.
        await gesture2.moveTo(
          Offset(
            canvasRect.left + canvasRect.width * 0.9,
            canvasRect.center.dy,
          ),
        );
        await gesture2.up();
        await tester.pump();

        expect(writes, hasLength(writesBeforeEscape + 1));
        final settledEscapeWrites = writes.where((w) => !w.changing).toList();
        expect(settledEscapeWrites, hasLength(1));
        expect(settledEscapeWrites.single.parameterNumber, 1);
        expect(settledEscapeWrites.single.value, 65);
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
        expect(terminalEvents.single.xValue, 65);
        expect(terminalEvents.single.yValue, isNull);
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

        // Without a rebuild, wheel down progresses from the latest local value (55 -> 50).
        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 5);
        expect(writes.single.value, 50);
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
        await _mouseClick(tester, canvasRect.center);
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

  group('Correction regressions: findings 1-5 and 7', () {
    testWidgets(
      'F1: Tab, Shift+Tab, and semantics follow declared order with geometry-independent tie-break, entry/exit, focus ring, and no-write keyboard select',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const traversalSource = r'''
return {
  version = 1,
  title = "Traversal Order Canvas",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.button {
        label = "Before Canvas",
        action = { type = "set_parameter", parameter = 1, value = 10 }
      },
      ui.canvas {
        semantics_label = "Ordered traversal surface",
        aspect_ratio = 2,
        shapes = {},
        targets = {
          {
            id = "left-order-2",
            label = "Left Order 2",
            shape = "circle",
            x = 0.15,
            y = 0.5,
            radius = 0.08,
            selectable = true,
            order = 2
          },
          {
            id = "right-tie-first",
            label = "Right Tie First",
            shape = "circle",
            x = 0.85,
            y = 0.25,
            radius = 0.08,
            selectable = true,
            order = 3
          },
          {
            id = "left-tie-second",
            label = "Left Tie Second",
            shape = "circle",
            x = 0.15,
            y = 0.25,
            radius = 0.08,
            selectable = true,
            order = 3
          },
          {
            id = "disabled-order-0",
            label = "Disabled Target",
            shape = "circle",
            x = 0.5,
            y = 0.25,
            radius = 0.08,
            selectable = true,
            enabled = false,
            order = 0
          },
          {
            id = "right-order-1",
            label = "Right Order 1",
            shape = "circle",
            x = 0.85,
            y = 0.5,
            radius = 0.08,
            selectable = true,
            order = 1,
            x_axis = { parameter = 1 }
          },
          {
            id = "unordered-right",
            label = "Unordered Right",
            shape = "circle",
            x = 0.85,
            y = 0.75,
            radius = 0.08,
            selectable = true
          },
          {
            id = "unordered-left",
            label = "Unordered Left",
            shape = "circle",
            x = 0.15,
            y = 0.75,
            radius = 0.08,
            selectable = true
          }
        }
      },
      ui.button {
        label = "After Canvas",
        action = { type = "set_parameter", parameter = 1, value = 20 }
      }
    }
  }
}
''';

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: traversalSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        // Focus the button before the canvas, then Tab through the entire canvas and out.
        final beforeButtonFocus = Focus.of(
          tester.element(find.text('Before Canvas')),
        );
        final afterButtonFocus = Focus.of(
          tester.element(find.text('After Canvas')),
        );
        beforeButtonFocus.requestFocus();
        await tester.pump();
        expect(beforeButtonFocus.hasFocus, isTrue);

        const expectedOrder = [
          'algorithm-controller-canvas-target:right-order-1',
          'algorithm-controller-canvas-target:left-order-2',
          'algorithm-controller-canvas-target:right-tie-first',
          'algorithm-controller-canvas-target:left-tie-second',
          'algorithm-controller-canvas-target:unordered-right',
          'algorithm-controller-canvas-target:unordered-left',
        ];

        final forwardLabels = <String?>[];
        for (var i = 0; i < expectedOrder.length; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          forwardLabels.add(FocusManager.instance.primaryFocus?.debugLabel);
        }
        expect(forwardLabels, expectedOrder);
        // Focus traversal alone does not write parameters or emit selection.
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // Focus indication: Semantics reports isFocused on the focused target and
        // overlay CustomPaint is mounted (base painter + interaction overlay painter).
        final focusedSemantics = tester
            .getSemantics(
              find.byKey(
                const ValueKey(
                  'algorithm-controller-canvas-target:unordered-left',
                ),
              ),
            )
            .getSemanticsData();
        expect(focusedSemantics.flagsCollection.isFocused, Tristate.isTrue);
        expect(
          find.descendant(
            of: find.byType(InteractiveAlgorithmControllerCanvas),
            matching: find.byType(CustomPaint),
          ),
          findsNWidgets(2),
        );

        // One more Tab exits canvas cleanly to the following button.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(afterButtonFocus.hasFocus, isTrue);

        // Shift+Tab enters canvas from the end and reverses exact declared order.
        final reverseLabels = <String?>[];
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var i = 0; i < expectedOrder.length; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          reverseLabels.add(FocusManager.instance.primaryFocus?.debugLabel);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(reverseLabels, expectedOrder.reversed.toList());

        // Keyboard selection action (Enter and Space) selects without writing.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.map((e) => (e.type, e.targetId)), [
          (
            AlgorithmControllerCanvasInteractionEventType.selected,
            'right-order-1',
          ),
        ]);
        expect(
          tester
              .getSemantics(
                find.byKey(
                  const ValueKey(
                    'algorithm-controller-canvas-target:right-order-1',
                  ),
                ),
              )
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.last.targetId, 'left-order-2');

        // Verify Semantics tree child order matches declared order (and excludes invalid targets).
        final canvasNode = tester.getSemantics(
          find.bySemanticsLabel('Ordered traversal surface'),
        );
        final childLabels = <String>[];
        canvasNode.visitChildren((child) {
          childLabels.add(child.label);
          return true;
        });
        expect(childLabels, [
          'Disabled Target',
          'Right Order 1',
          'Left Order 2',
          'Right Tie First',
          'Left Tie Second',
          'Unordered Right',
          'Unordered Left',
        ]);

        semanticsHandle.dispose();
      },
    );

    testWidgets(
      'F2: accessible targets expose named select, formatted values, unambiguous single/multi-axis adjust actions, and guard disabled/stale bindings',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final slot = Slot(
          algorithm: Algorithm(
            algorithmIndex: 2,
            guid: 'synt',
            name: 'Synthetic',
          ),
          routing: RoutingInfo.filler(),
          pages: ParameterPages(algorithmIndex: 2, pages: const []),
          parameters: [
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 0,
              min: 0,
              max: 1,
              defaultValue: 0,
              unit: 0,
              name: 'Bypass',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 1,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 2,
              name: 'Freq',
              powerOfTen: -1,
            ),
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 2,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 0,
              name: 'Gain',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 3,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 0,
              name: 'X2',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 4,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 0,
              name: 'Y2',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 2,
              parameterNumber: 5,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 0,
              name: 'Q',
              powerOfTen: 0,
            ),
          ],
          values: [
            ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 0),
            ParameterValue(algorithmIndex: 2, parameterNumber: 1, value: 50),
            ParameterValue(algorithmIndex: 2, parameterNumber: 2, value: 50),
            ParameterValue(algorithmIndex: 2, parameterNumber: 3, value: 50),
            ParameterValue(algorithmIndex: 2, parameterNumber: 4, value: 50),
            ParameterValue(algorithmIndex: 2, parameterNumber: 5, value: 50),
          ],
          enums: [
            ParameterEnumStrings(
              algorithmIndex: 2,
              parameterNumber: 0,
              values: const ['Off', 'On'],
            ),
            for (var i = 1; i <= 5; i++)
              ParameterEnumStrings(
                algorithmIndex: 2,
                parameterNumber: i,
                values: const [],
              ),
          ],
          mappings: [for (var i = 0; i <= 5; i++) Mapping.filler()],
          valueStrings: [
            ParameterValueString(
              algorithmIndex: 2,
              parameterNumber: 0,
              value: '',
            ),
            ParameterValueString(
              algorithmIndex: 2,
              parameterNumber: 1,
              value: '5.0 kHz',
            ),
            for (var i = 2; i <= 5; i++)
              ParameterValueString(
                algorithmIndex: 2,
                parameterNumber: i,
                value: '',
              ),
          ],
        );

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: slot,
            units: const ['%', 'kHz'],
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Single-axis target (solo-x -> param 1, step 5): named select, formatted
        // value/next-values, and standard increase/decrease actions.
        final soloXNode = tester.getSemantics(
          find.byKey(
            const ValueKey('algorithm-controller-canvas-target:solo-x'),
          ),
        );
        final owner = soloXNode.owner!;
        final soloXData = soloXNode.getSemanticsData();
        expect(soloXData.value, 'Freq 5.0 kHz');
        expect(soloXData.increasedValue, 'Freq 5.5 kHz');
        expect(soloXData.decreasedValue, 'Freq 4.5 kHz');
        expect(soloXData.hasAction(SemanticsAction.tap), isTrue);
        final soloXTapOverride =
            (soloXData.customSemanticsActionIds ?? const <int>[])
                .map(CustomSemanticsAction.getAction)
                .whereType<CustomSemanticsAction>()
                .firstWhere((action) => action.action == SemanticsAction.tap);
        expect(soloXTapOverride.hint, 'Select Solo Horizontal');
        expect(soloXData.hasAction(SemanticsAction.increase), isTrue);
        expect(soloXData.hasAction(SemanticsAction.decrease), isTrue);

        // Invoking named select (SemanticsAction.tap) selects without writing.
        owner.performAction(soloXNode.id, SemanticsAction.tap);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.map((e) => (e.type, e.targetId)), [
          (AlgorithmControllerCanvasInteractionEventType.selected, 'solo-x'),
        ]);

        // Invoking increase writes param 1 -> 55 with changing:false.
        owner.performAction(soloXNode.id, SemanticsAction.increase);
        await tester.pump();
        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 1);
        expect(writes.single.value, 55);
        expect(writes.single.changing, isFalse);

        // 2. Multi-parameter target (t1 -> Freq, Gain, Q): exposes all values,
        // named select, NO generic increase/decrease, and explicit parameter-named custom actions.
        writes.clear();
        final t1Node = tester.getSemantics(
          find.byKey(const ValueKey('algorithm-controller-canvas-target:t1')),
        );
        final t1Data = t1Node.getSemanticsData();
        expect(t1Data.value, 'Freq 5.0 kHz, Gain 50, Q 50');
        expect(t1Data.hasAction(SemanticsAction.tap), isTrue);
        final t1TapOverride = (t1Data.customSemanticsActionIds ?? const <int>[])
            .map(CustomSemanticsAction.getAction)
            .whereType<CustomSemanticsAction>()
            .firstWhere((action) => action.action == SemanticsAction.tap);
        expect(t1TapOverride.hint, 'Select Target One');
        expect(t1Data.hasAction(SemanticsAction.increase), isFalse);
        expect(t1Data.hasAction(SemanticsAction.decrease), isFalse);

        final customLabels = <String, int>{
          for (final id in t1Data.customSemanticsActionIds ?? const <int>[])
            ?CustomSemanticsAction.getAction(id)?.label: id,
        };
        expect(
          customLabels.keys,
          containsAll([
            'Increase Freq',
            'Decrease Freq',
            'Increase Gain',
            'Decrease Gain',
            'Increase Q',
            'Decrease Q',
          ]),
        );

        // Invoke 'Increase Gain' -> writes ONLY parameter 2 (50 -> 51).
        owner.performAction(
          t1Node.id,
          SemanticsAction.customAction,
          customLabels['Increase Gain'],
        );
        await tester.pump();
        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 2);
        expect(writes.single.value, 51);
        expect(writes.single.changing, isFalse);

        // Invoke 'Decrease Q' -> writes ONLY parameter 5 (50 -> 45, step=5).
        writes.clear();
        owner.performAction(
          t1Node.id,
          SemanticsAction.customAction,
          customLabels['Decrease Q'],
        );
        await tester.pump();
        expect(writes, hasLength(1));
        expect(writes.single.parameterNumber, 5);
        expect(writes.single.value, 45);
        expect(writes.single.changing, isFalse);

        // 3. Disabled target & missing-param target expose no adjust actions.
        final disabledData = tester
            .getSemantics(
              find.byKey(
                const ValueKey(
                  'algorithm-controller-canvas-target:disabled-target',
                ),
              ),
            )
            .getSemanticsData();
        expect(disabledData.hasAction(SemanticsAction.tap), isFalse);
        expect(disabledData.hasAction(SemanticsAction.increase), isFalse);
        expect(disabledData.hasAction(SemanticsAction.decrease), isFalse);
        expect(disabledData.customSemanticsActionIds, anyOf(isNull, isEmpty));

        final missingData = tester
            .getSemantics(
              find.byKey(
                const ValueKey(
                  'algorithm-controller-canvas-target:missing-param',
                ),
              ),
            )
            .getSemanticsData();
        expect(missingData.value, isEmpty);
        expect(missingData.hasAction(SemanticsAction.increase), isFalse);
        expect(missingData.hasAction(SemanticsAction.decrease), isFalse);

        // 4. Stale / disconnected session blocks semantics writes even before rebuild.
        writes.clear();
        final disconnected = const DistingState.selectDevice(
          inputDevices: [],
          outputDevices: [],
          canWorkOffline: false,
        );
        when(() => cubit.state).thenReturn(disconnected);
        owner.performAction(soloXNode.id, SemanticsAction.increase);
        await tester.pump();
        expect(writes, isEmpty);

        semanticsHandle.dispose();
      },
    );

    testWidgets(
      'F3: wheel accumulates fractional deltas, progresses across batched events, reconciles fresh readback, clears on target switch/remap/reconnect, and preserves pass-through',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const twoWheelSource = r'''
return {
  version = 1,
  title = "Wheel Delta Surface",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.canvas {
        semantics_label = "Wheel accumulation canvas",
        aspect_ratio = 2,
        shapes = {},
        targets = {
          {
            id = "wheel-a",
            label = "Wheel A",
            shape = "rect",
            x = 0.05,
            y = 0.1,
            width = 0.4,
            height = 0.8,
            wheel = { parameter = 5, step = 1 }
          },
          {
            id = "wheel-b",
            label = "Wheel B",
            shape = "rect",
            x = 0.55,
            y = 0.1,
            width = 0.4,
            height = 0.8,
            wheel = { parameter = 4, step = 5 }
          }
        }
      },
      ui.spacer { size = 1200 }
    }
  }
}
''';

        final slot0 = _syntheticSlot(p4: 50, p5: 50);
        await tester.pumpWidget(
          _Harness(cubit: cubit, slot: slot0, source: twoWheelSource),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final centerA = Offset(
          canvasRect.left + canvasRect.width * 0.25,
          canvasRect.top + canvasRect.height * 0.5,
        );
        final centerB = Offset(
          canvasRect.left + canvasRect.width * 0.75,
          canvasRect.top + canvasRect.height * 0.5,
        );
        final mouse = TestPointer(30, PointerDeviceKind.mouse);

        // 1. Sub-floor fragments: four dy=-10 events totaling the 40-logical-px floor -> ONE step ONCE.
        tester.binding.handlePointerEvent(mouse.hover(centerA));
        for (var i = 0; i < 3; i++) {
          tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -10)));
          await tester.pump();
          expect(writes, isEmpty);
          expect(scrollable.position.pixels, 0);
        }
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -10)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value, w.changing)), [
          (5, 51, false),
        ]);

        // Opposite direction: four dy=+10 events -> steps back 51 -> 50 once.
        writes.clear();
        for (var i = 0; i < 4; i++) {
          tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 10)));
          await tester.pump();
        }
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(5, 50)]);

        // 2. Batched events in a single frame without rebuild progress cleanly (no duplicates).
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -40)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -53)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -100)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [
          (5, 51),
          (5, 52),
          (5, 53),
        ]);

        // 3. Fresh readback reconciles immediately (even when hardware reports a different value).
        writes.clear();
        final readbackSlot = slot0.copyWith(
          values: [
            for (final v in slot0.values)
              v.parameterNumber == 5
                  ? ParameterValue(
                      algorithmIndex: v.algorithmIndex,
                      parameterNumber: 5,
                      value: 30,
                    )
                  : v,
          ],
        );
        await tester.pumpWidget(
          _Harness(cubit: cubit, slot: readbackSlot, source: twoWheelSource),
        );
        await tester.pump();

        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -40)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(5, 31)]);

        // 4. Unused sub-floor accumulation on Wheel A must NOT carry to Wheel B on target switch.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(writes, isEmpty);

        tester.binding.handlePointerEvent(mouse.hover(centerB));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(
          writes,
          isEmpty,
          reason: 'leftover -30 on wheel-a must not carry onto wheel-b',
        );
        // Completing the 40-logical-px floor on wheel-b (-20 + -20) steps param 4 by step=5 (50 -> 55).
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(4, 55)]);

        // 5. At-limit arbitration consumes scroll without writing and clears accumulation,
        // and remap / disconnect-reconnect clears unused accumulation.
        writes.clear();
        final atMaxSlot = slot0.copyWith(
          values: [
            for (final v in slot0.values)
              v.parameterNumber == 5
                  ? ParameterValue(
                      algorithmIndex: v.algorithmIndex,
                      parameterNumber: 5,
                      value: 100,
                    )
                  : v,
          ],
        );
        await tester.pumpWidget(
          _Harness(cubit: cubit, slot: atMaxSlot, source: twoWheelSource),
        );
        await tester.pump();
        tester.binding.handlePointerEvent(mouse.hover(centerA));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -40)));
        await tester.pump();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, 0);

        // Reconnect clears partial fractional accumulation (-30) so post-reconnect -20 does not fire.
        final mgrA = _MockMidiManager();
        final mgrB = _MockMidiManager();
        final reconSlot = _syntheticSlot(p5: 50);
        when(() => cubit.state).thenReturn(_synchronizedState(mgrA, reconSlot));
        await tester.pumpWidget(
          _Harness(cubit: cubit, slot: reconSlot, source: twoWheelSource),
        );
        await tester.pump();
        tester.binding.handlePointerEvent(mouse.hover(centerA));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(writes, isEmpty);

        final syncedB = _synchronizedState(mgrB, reconSlot);
        when(() => cubit.state).thenReturn(syncedB);
        stateStream.add(syncedB);
        await tester.pump();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(
          writes,
          isEmpty,
          reason: 'reconnect must clear prior partial wheel accumulation',
        );

        // 6. Horizontal wheel and trackpad scroll pass through to parent without writes.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.hover(centerB));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(120, 0)));
        await tester.pump();
        expect(writes, isEmpty);

        final trackpad = TestPointer(31, PointerDeviceKind.trackpad);
        tester.binding.handlePointerEvent(trackpad.hover(centerB));
        tester.binding.handlePointerEvent(trackpad.scroll(const Offset(0, 80)));
        await tester.pump();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));
      },
    );

    testWidgets(
      'F4: touch, pen, non-primary mouse, and trackpad pan/zoom over writable target do not capture or write; vertical touch drag scrolls parent',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(600, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const fullTargetSource = r'''
return {
  version = 1,
  title = "Pointer Kind Policy",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.canvas {
        semantics_label = "Full target surface",
        aspect_ratio = 2,
        drag_threshold = 4,
        shapes = {},
        targets = {
          {
            id = "full",
            label = "Full Target",
            shape = "rect",
            x = 0,
            y = 0,
            width = 1,
            height = 1,
            selectable = true,
            x_axis = { parameter = 1 },
            y_axis = { parameter = 2, invert = true }
          }
        }
      },
      ui.spacer { size = 1200 }
    }
  }
}
''';

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: fullTargetSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );

        // 1. Vertical touch drag directly over writable target scrolls parent with ZERO writes.
        final touchDrag = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.touch,
        );
        for (var i = 0; i < 8; i++) {
          await touchDrag.moveBy(const Offset(0, -12));
          await tester.pump();
        }
        await touchDrag.up();
        await tester.pumpAndSettle();
        expect(writes, isEmpty);
        expect(events, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));

        // Reset scroll to 0 for remaining pointer-kind assertions.
        scrollable.position.jumpTo(0);
        await tester.pump();

        // 2. Touch tap over selectable target does not select or write.
        await tester.tapAt(canvasRect.center);
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // 3. Stylus/pen drag over writable target does not capture or write.
        final stylusDrag = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.stylus,
        );
        await stylusDrag.moveBy(const Offset(60, 0));
        await stylusDrag.up();
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // 4. Secondary and middle mouse buttons do not capture or write.
        for (final button in const [
          kSecondaryMouseButton,
          kMiddleMouseButton,
        ]) {
          final nonPrimary = await tester.startGesture(
            canvasRect.center,
            kind: PointerDeviceKind.mouse,
            buttons: button,
          );
          await nonPrimary.moveBy(const Offset(60, 0));
          await nonPrimary.up();
          await tester.pump();
        }
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // 5. Trackpad pan/zoom over writable target scrolls parent without writes.
        final trackpad = TestPointer(40, PointerDeviceKind.trackpad);
        tester.binding.handlePointerEvent(
          trackpad.panZoomStart(canvasRect.center),
        );
        tester.binding.handlePointerEvent(
          trackpad.panZoomUpdate(canvasRect.center, pan: const Offset(0, -25)),
        );
        tester.binding.handlePointerEvent(
          trackpad.panZoomUpdate(canvasRect.center, pan: const Offset(0, -90)),
        );
        tester.binding.handlePointerEvent(trackpad.panZoomEnd());
        await tester.pumpAndSettle();
        expect(writes, isEmpty);
        expect(events, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));

        // 6. Primary mouse drag still captures and writes cleanly.
        scrollable.position.jumpTo(0);
        await tester.pump();
        final freshRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final mouseDrag = await tester.startGesture(
          freshRect.center,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await mouseDrag.moveTo(
          Offset(freshRect.left + freshRect.width * 0.75, freshRect.center.dy),
        );
        await mouseDrag.up();
        await tester.pump();
        expect(writes, isNotEmpty);
        expect(writes.last.parameterNumber, 1);
        expect(writes.last.value, 75);
        expect(writes.last.changing, isFalse);
      },
    );

    testWidgets(
      'F5: pre-threshold cancel, no-dirty cancel, stale-session Escape, and post-threshold gestureRejected follow exact settlement rules',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        // 1. Pre-threshold Escape and pointerCancel emit ZERO writes and ZERO dragCancel.
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

        final preThresholdEsc = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await preThresholdEsc.moveBy(const Offset(3, 0)); // < 8px threshold
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await preThresholdEsc.moveBy(const Offset(80, 0));
        await preThresholdEsc.up();
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        final preThresholdCancel = await tester.startGesture(
          canvasRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await preThresholdCancel.moveBy(const Offset(3, 0));
        await preThresholdCancel.cancel();
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // 2. Drag past threshold with no dirty axis (solo-x dragged vertically only so X stays 50).
        final soloXCenter = Offset(
          canvasRect.left + canvasRect.width * 0.5,
          canvasRect.top + canvasRect.height * 0.5,
        );
        // Put solo-x with step=100 or drag t1 vertically? Better: test solo-x where initial X=50
        // and drag straight up on solo-x? solo-x rect is x: 0.05..0.20, so at x=0.125 rawX is 8.
        // Instead use a dedicated 1-axis target with step=100 so small post-threshold move stays 50.
        const noDirtySource = r'''
return {
  version = 1,
  title = "No Dirty Axis",
  root = ui.canvas {
    semantics_label = "No dirty surface",
    aspect_ratio = 2,
    drag_threshold = 4,
    shapes = {},
    targets = {
      {
        id = "coarse",
        label = "Coarse",
        shape = "rect",
        x = 0,
        y = 0,
        width = 1,
        height = 1,
        x_axis = { parameter = 1, from = 0, to = 1, step = 50 }
      }
    }
  }
}
''';
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(p1: 50),
            source: noDirtySource,
            assetPath: 'no-dirty.lua',
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();
        final coarseRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final noDirtyDrag = await tester.startGesture(
          coarseRect.center,
          kind: PointerDeviceKind.mouse,
        );
        // Move 10px (> 4px threshold) — still quantizes to 50 (no dirty writes).
        await noDirtyDrag.moveBy(const Offset(10, 0));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await noDirtyDrag.up();
        await tester.pump();
        expect(writes, isEmpty);
        expect(events.map((e) => (e.type, e.cancelReason)), [
          (AlgorithmControllerCanvasInteractionEventType.dragStart, null),
          (
            AlgorithmControllerCanvasInteractionEventType.dragCancel,
            AlgorithmControllerCanvasCancelReason.escapeKey,
          ),
        ]);
        expect(soloXCenter.dx, greaterThan(0));

        // 3. Stale session invalidation synchronously before Escape -> ZERO final write.
        writes.clear();
        events.clear();
        final manager = _MockMidiManager();
        final syncSlot = _syntheticSlot(p1: 50);
        when(() => cubit.state)
            .thenReturn(_synchronizedState(manager, syncSlot));
        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: syncSlot,
            source: _overlappingTwoAxisSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();
        final syncRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final staleDrag = await tester.startGesture(
          syncRect.center,
          kind: PointerDeviceKind.mouse,
        );
        await staleDrag.moveTo(
          Offset(syncRect.left + syncRect.width * 0.7, syncRect.center.dy),
        );
        await tester.pump();
        final writesBeforeStaleEscape = writes.length;
        expect(writesBeforeStaleEscape, greaterThan(0));
        expect(writes.every((w) => w.changing), isTrue);

        // Cubit transitions to disconnected WITHOUT pumping a rebuild first, then Escape arrives.
        when(() => cubit.state).thenReturn(
          const DistingState.selectDevice(
            inputDevices: [],
            outputDevices: [],
            canWorkOffline: false,
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await staleDrag.up();
        await tester.pump();
        expect(writes, hasLength(writesBeforeStaleEscape));
        expect(writes.where((w) => !w.changing), isEmpty);

        // 4a. Real gesture-arena pre-threshold rejection (competing recognizer wins before threshold).
        writes.clear();
        events.clear();
        when(() => cubit.state).thenReturn(const DistingState.initial());
        const rejectNode = AlgorithmControllerCanvas(
          semanticsLabel: 'reject-probe',
          shapes: [],
          aspectRatio: 2,
          dragThreshold: 8,
          targets: [
            AlgorithmControllerCanvasTarget(
              id: 't',
              label: 'T',
              hitArea: AlgorithmControllerCanvasRectHitArea(
                x: 0,
                y: 0,
                width: 1,
                height: 1,
              ),
              xAxis: AlgorithmControllerCanvasAxisBinding(parameterNumber: 1),
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<DistingCubit>.value(
              value: cubit,
              child: Scaffold(
                body: RawGestureDetector(
                  gestures: {
                    _EarlyAcceptGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _EarlyAcceptGestureRecognizer
                        >(() => _EarlyAcceptGestureRecognizer(), (_) {}),
                  },
                  child: SizedBox(
                    width: 400,
                    height: 200,
                    child: InteractiveAlgorithmControllerCanvas(
                      node: rejectNode,
                      slot: _syntheticSlot(p1: 50),
                      slotIndex: 2,
                      documentGeneration: 0,
                      painter: _NoOpPainter(),
                      onWriteParameter: (p, v, {required changing}) =>
                          writes.add((
                            algorithmIndex: 2,
                            parameterNumber: p,
                            value: v,
                            changing: changing,
                          )),
                      onInteraction: events.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final preRejDrag = await tester.startGesture(
          const Offset(200, 100),
          kind: PointerDeviceKind.mouse,
        );
        // Move 3px (< 8px canvas threshold): parent claims arena -> canvas gets rejectGesture.
        await preRejDrag.moveBy(const Offset(3, 0));
        await preRejDrag.moveBy(const Offset(60, 0));
        await preRejDrag.up();
        await tester.pump();
        expect(writes, isEmpty);
        expect(events, isEmpty);

        // 4b. Post-threshold gestureRejected after actual drag writes settles dirty axis once.
        writes.clear();
        events.clear();
        _ManualClaimGestureRecognizer? manualParent;
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<DistingCubit>.value(
              value: cubit,
              child: Scaffold(
                body: RawGestureDetector(
                  gestures: {
                    _ManualClaimGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _ManualClaimGestureRecognizer
                        >(() => _ManualClaimGestureRecognizer(), (instance) {
                          manualParent = instance;
                        }),
                  },
                  child: SizedBox(
                    width: 400,
                    height: 200,
                    child: InteractiveAlgorithmControllerCanvas(
                      node: rejectNode,
                      slot: _syntheticSlot(p1: 50),
                      slotIndex: 2,
                      documentGeneration: 0,
                      painter: _NoOpPainter(),
                      onWriteParameter: (p, v, {required changing}) {
                        writes.add((
                          algorithmIndex: 2,
                          parameterNumber: p,
                          value: v,
                          changing: changing,
                        ));
                        // Competing recognizer claims the arena right after the
                        // first real-time write, before canvas claims acceptance.
                        if (changing) {
                          manualParent?.claimArena();
                        }
                      },
                      onInteraction: events.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rejDrag = await tester.startGesture(
          const Offset(200, 100),
          kind: PointerDeviceKind.mouse,
        );
        await rejDrag.moveBy(const Offset(60, 0));
        await tester.pump();

        // Late move/up after rejection must emit zero additional writes.
        await rejDrag.moveBy(const Offset(80, 0));
        await rejDrag.up();
        await tester.pump();

        expect(writes.map((w) => (w.parameterNumber, w.value, w.changing)), [
          (1, 65, true),
          (1, 65, false),
        ]);
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
          AlgorithmControllerCanvasCancelReason.gestureRejected,
        );
      },
    );

    testWidgets(
      'F7: non-cycling overlap aligns click and drag priority to highest-priority ordered target',
      (tester) async {
        final events = <AlgorithmControllerCanvasInteractionEvent>[];
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const partialOverlapSource = r'''
return {
  version = 1,
  title = "Non-cycling Overlap Priority",
  root = ui.canvas {
    semantics_label = "Non-cycling priority surface",
    aspect_ratio = 2,
    drag_threshold = 4,
    cycle_overlapping_selection = false,
    shapes = {},
    targets = {
      {
        id = "second",
        label = "Second",
        shape = "rect",
        x = 0.4,
        y = 0.0,
        width = 0.6,
        height = 1.0,
        selectable = true,
        order = 2,
        x_axis = { parameter = 3 }
      },
      {
        id = "first",
        label = "First",
        shape = "rect",
        x = 0.0,
        y = 0.0,
        width = 0.6,
        height = 1.0,
        selectable = true,
        order = 1,
        x_axis = { parameter = 1 }
      }
    }
  }
}
''';

        await tester.pumpWidget(
          _Harness(
            cubit: cubit,
            slot: _syntheticSlot(),
            source: partialOverlapSource,
            onCanvasInteraction: events.add,
          ),
        );
        await tester.pumpAndSettle();

        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final secondOnlyPoint = Offset(
          canvasRect.left + canvasRect.width * 0.85,
          canvasRect.center.dy,
        );
        final overlapPoint = canvasRect.center;

        // Select 'second' via its non-overlapping region (no writes).
        await _mouseClick(tester, secondOnlyPoint);
        expect(writes, isEmpty);
        expect(events.last.targetId, 'second');

        // Dragging from the overlap must capture 'first' (order 1), matching click priority.
        events.clear();
        final drag = await tester.startGesture(
          overlapPoint,
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(
          Offset(canvasRect.left + canvasRect.width * 0.75, overlapPoint.dy),
        );
        await drag.up();
        await tester.pump();

        expect(writes, isNotEmpty);
        expect(writes.every((w) => w.parameterNumber == 1), isTrue);
        expect(events.first.targetId, 'first');

        // Select 'second' again, then click the overlap -> also resolves to 'first' without writes.
        writes.clear();
        await _mouseClick(tester, secondOnlyPoint);
        expect(events.last.targetId, 'second');
        await _mouseClick(tester, overlapPoint);
        expect(writes, isEmpty);
        expect(events.last.targetId, 'first');
      },
    );

    testWidgets(
      'W1: desktop wheel discrete-event floor (±40/53/66.7/100) steps once without carry leak, accumulates sub-floor fragments, and preserves scroll pass-through',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const wheelPolicySource = r'''
return {
  version = 1,
  title = "W1 Wheel Policy",
  root = ui.column {
    gap = 12,
    padding = 16,
    children = {
      ui.canvas {
        semantics_label = "W1 wheel canvas",
        aspect_ratio = 2,
        shapes = {},
        targets = {
          {
            id = "wheel-a",
            label = "Wheel A",
            shape = "rect",
            x = 0.05,
            y = 0.1,
            width = 0.4,
            height = 0.8,
            wheel = { parameter = 5, step = 1 }
          },
          {
            id = "wheel-b",
            label = "Wheel B",
            shape = "rect",
            x = 0.55,
            y = 0.1,
            width = 0.4,
            height = 0.8,
            wheel = { parameter = 4, step = 5 }
          }
        }
      },
      ui.spacer { size = 1200 }
    }
  }
}
''';

        // 1. Parameterized embedder-derived samples in both directions on clean targets:
        // macOS line-wheel (~40), Linux (~53), Windows 150%/100% (~66.7/100).
        var pointerId = 60;
        for (final magnitude in const [40.0, 53.0, 66.7, 100.0]) {
          for (final isUp in const [true, false]) {
            writes.clear();
            final dy = isUp ? -magnitude : magnitude;
            final expectedValue = isUp ? 51 : 49;
            final label = 'dy=$dy';

            await tester.pumpWidget(
              _Harness(
                key: ValueKey('w1-$magnitude-$isUp'),
                cubit: cubit,
                slot: _syntheticSlot(p4: 50, p5: 50),
                source: wheelPolicySource,
              ),
            );
            await tester.pumpAndSettle();

            final scrollable = tester.state<ScrollableState>(
              find.byType(Scrollable).first,
            );
            final canvasRect = tester.getRect(
              find.byType(InteractiveAlgorithmControllerCanvas),
            );
            final centerA = Offset(
              canvasRect.left + canvasRect.width * 0.25,
              canvasRect.top + canvasRect.height * 0.5,
            );
            final mouse = TestPointer(pointerId++, PointerDeviceKind.mouse);

            tester.binding.handlePointerEvent(mouse.hover(centerA));
            tester.binding.handlePointerEvent(mouse.scroll(Offset(0, dy)));
            await tester.pump();

            expect(
              writes.map((w) => (w.parameterNumber, w.value, w.changing)),
              [(5, expectedValue, false)],
              reason: '$label must emit precisely one write',
            );
            expect(
              scrollable.position.pixels,
              0,
              reason: '$label must not scroll parent',
            );

            // Follow immediately with a sub-floor 30-px event in the same direction:
            // must produce zero writes, proving no fractional carry leaked from the
            // discrete event (e.g. 53/66.7/100 leaves 0 carry, not 13/26.7/60).
            writes.clear();
            final followUpDy = isUp ? -30.0 : 30.0;
            tester.binding.handlePointerEvent(
              mouse.scroll(Offset(0, followUpDy)),
            );
            await tester.pump();
            expect(
              writes,
              isEmpty,
              reason: 'no fraction may leak after discrete $label',
            );
            expect(scrollable.position.pixels, 0);
          }
        }

        // 2. Clean target for sub-floor accumulation, discrete carry discard,
        // batched events, reversal, target switch, and pass-through.
        writes.clear();
        await tester.pumpWidget(
          _Harness(
            key: const ValueKey('w1-subfloor-and-batch'),
            cubit: cubit,
            slot: _syntheticSlot(p4: 50, p5: 50),
            source: wheelPolicySource,
          ),
        );
        await tester.pumpAndSettle();

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        final canvasRect = tester.getRect(
          find.byType(InteractiveAlgorithmControllerCanvas),
        );
        final centerA = Offset(
          canvasRect.left + canvasRect.width * 0.25,
          canvasRect.top + canvasRect.height * 0.5,
        );
        final centerB = Offset(
          canvasRect.left + canvasRect.width * 0.75,
          canvasRect.top + canvasRect.height * 0.5,
        );
        final backgroundPoint = Offset(
          canvasRect.left + canvasRect.width * 0.5,
          canvasRect.top + canvasRect.height * 0.5,
        );
        final mouse = TestPointer(pointerId++, PointerDeviceKind.mouse);

        // 2a. Sub-floor fragments (4 x -10): zero before threshold, then one write.
        tester.binding.handlePointerEvent(mouse.hover(centerA));
        for (var i = 0; i < 3; i++) {
          tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -10)));
          await tester.pump();
          expect(writes, isEmpty);
          expect(scrollable.position.pixels, 0);
        }
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -10)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value, w.changing)), [
          (5, 51, false),
        ]);
        expect(scrollable.position.pixels, 0);

        // 2b. Direction reversal clears partial sub-floor carry.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -25)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 25)));
        await tester.pump();
        expect(writes, isEmpty);
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 15)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(5, 50)]);

        // 2c. Discrete event discards earlier sub-floor carry without leaking.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(writes, isEmpty);
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -53)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(5, 51)]);
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -15)));
        await tester.pump();
        expect(
          writes,
          isEmpty,
          reason: 'earlier -30 carry must be discarded by discrete -53 event',
        );

        // 2d. Batched events in one frame progress without rebuild.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -40)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -53)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -66.7)));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -100)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [
          (5, 52),
          (5, 53),
          (5, 54),
          (5, 55),
        ]);
        expect(scrollable.position.pixels, 0);

        // Batched sub-floor fragments in one frame (8 x -10 -> 2 steps).
        writes.clear();
        for (var i = 0; i < 8; i++) {
          tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -10)));
        }
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [
          (5, 56),
          (5, 57),
        ]);
        expect(scrollable.position.pixels, 0);

        // 2e. No fraction leaking onto a new target.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -30)));
        await tester.pump();
        expect(writes, isEmpty);
        tester.binding.handlePointerEvent(mouse.hover(centerB));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(writes, isEmpty);
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, -20)));
        await tester.pump();
        expect(writes.map((w) => (w.parameterNumber, w.value)), [(4, 55)]);

        // 2f. Ineligible background, horizontal wheel, and trackpad pass through.
        writes.clear();
        tester.binding.handlePointerEvent(mouse.hover(centerB));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(53, 0)));
        await tester.pump();
        expect(writes, isEmpty);

        tester.binding.handlePointerEvent(mouse.hover(backgroundPoint));
        tester.binding.handlePointerEvent(mouse.scroll(const Offset(0, 53)));
        await tester.pump();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));

        scrollable.position.jumpTo(0);
        await tester.pump();
        final trackpad = TestPointer(pointerId++, PointerDeviceKind.trackpad);
        tester.binding.handlePointerEvent(trackpad.hover(centerA));
        tester.binding.handlePointerEvent(trackpad.scroll(const Offset(0, 53)));
        await tester.pump();
        expect(writes, isEmpty);
        expect(scrollable.position.pixels, greaterThan(0));
      },
    );

    testWidgets(
      'K1: Escape has one owner across two canvases and ancestor shortcut, preserves unrelated shortcuts, handles focus transfer/repeat/disposal',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        var ancestorEscapeCount = 0;
        var unrelatedShortcutCount = 0;
        final writesA = <_RecordedWrite>[];
        final writesB = <_RecordedWrite>[];
        final eventsA = <AlgorithmControllerCanvasInteractionEvent>[];
        final eventsB = <AlgorithmControllerCanvasInteractionEvent>[];
        final externalFocus = FocusNode(debugLabel: 'external-button');
        addTearDown(externalFocus.dispose);

        const canvasANode = AlgorithmControllerCanvas(
          semanticsLabel: 'Canvas A',
          shapes: [],
          aspectRatio: 2,
          dragThreshold: 8,
          targets: [
            AlgorithmControllerCanvasTarget(
              id: 'a1',
              label: 'A1',
              order: 1,
              selectable: true,
              hitArea: AlgorithmControllerCanvasRectHitArea(
                x: 0.0,
                y: 0.0,
                width: 0.5,
                height: 1.0,
              ),
              xAxis: AlgorithmControllerCanvasAxisBinding(parameterNumber: 1),
            ),
            AlgorithmControllerCanvasTarget(
              id: 'a2',
              label: 'A2',
              order: 2,
              selectable: true,
              hitArea: AlgorithmControllerCanvasRectHitArea(
                x: 0.5,
                y: 0.0,
                width: 0.5,
                height: 1.0,
              ),
              xAxis: AlgorithmControllerCanvasAxisBinding(parameterNumber: 2),
            ),
          ],
        );

        const canvasBNode = AlgorithmControllerCanvas(
          semanticsLabel: 'Canvas B',
          shapes: [],
          aspectRatio: 2,
          dragThreshold: 8,
          targets: [
            AlgorithmControllerCanvasTarget(
              id: 'b1',
              label: 'B1',
              order: 1,
              selectable: true,
              hitArea: AlgorithmControllerCanvasRectHitArea(
                x: 0.0,
                y: 0.0,
                width: 1.0,
                height: 1.0,
              ),
              xAxis: AlgorithmControllerCanvasAxisBinding(parameterNumber: 3),
            ),
          ],
        );

        Widget buildTree({required bool mountCanvasA}) {
          return MaterialApp(
            home: BlocProvider<DistingCubit>.value(
              value: cubit,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.escape):
                      _TestClearSelectionIntent(),
                  SingleActivator(LogicalKeyboardKey.keyR):
                      _TestUnrelatedShortcutIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _TestClearSelectionIntent:
                        CallbackAction<_TestClearSelectionIntent>(
                          onInvoke: (_) {
                            ancestorEscapeCount++;
                            return null;
                          },
                        ),
                    _TestUnrelatedShortcutIntent:
                        CallbackAction<_TestUnrelatedShortcutIntent>(
                          onInvoke: (_) {
                            unrelatedShortcutCount++;
                            return null;
                          },
                        ),
                  },
                  child: Scaffold(
                    body: Column(
                      children: [
                        ElevatedButton(
                          focusNode: externalFocus,
                          onPressed: () {},
                          child: const Text('External'),
                        ),
                        if (mountCanvasA)
                          SizedBox(
                            key: const ValueKey('canvas-a-box'),
                            width: 400,
                            height: 200,
                            child: InteractiveAlgorithmControllerCanvas(
                              node: canvasANode,
                              slot: _syntheticSlot(p1: 50, p2: 50),
                              slotIndex: 2,
                              documentGeneration: 0,
                              painter: _NoOpPainter(),
                              onWriteParameter: (p, v, {required changing}) =>
                                  writesA.add((
                                    algorithmIndex: 2,
                                    parameterNumber: p,
                                    value: v,
                                    changing: changing,
                                  )),
                              onInteraction: eventsA.add,
                            ),
                          ),
                        SizedBox(
                          key: const ValueKey('canvas-b-box'),
                          width: 400,
                          height: 200,
                          child: InteractiveAlgorithmControllerCanvas(
                            node: canvasBNode,
                            slot: _syntheticSlot(p3: 50),
                            slotIndex: 2,
                            documentGeneration: 0,
                            painter: _NoOpPainter(),
                            onWriteParameter: (p, v, {required changing}) =>
                                writesB.add((
                                  algorithmIndex: 2,
                                  parameterNumber: p,
                                  value: v,
                                  changing: changing,
                                )),
                            onInteraction: eventsB.add,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildTree(mountCanvasA: true));
        await tester.pumpAndSettle();

        final rectA = tester.getRect(
          find.byKey(const ValueKey('canvas-a-box')),
        );
        final a1Point = Offset(
          rectA.left + rectA.width * 0.25,
          rectA.top + rectA.height * 0.5,
        );
        final a2Point = Offset(
          rectA.left + rectA.width * 0.75,
          rectA.top + rectA.height * 0.5,
        );

        // 1. Idle before drag: Escape reaches ancestor shortcut unchanged
        // (both from external focus and from focused canvas target).
        externalFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 1);
        expect(writesA, isEmpty);
        expect(writesB, isEmpty);

        await _mouseClick(tester, a1Point);
        expect(writesA, isEmpty);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'algorithm-controller-canvas-target:a1',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 2);
        expect(writesA, isEmpty);
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                AlgorithmControllerCanvasInteractionEventType.dragCancel,
          ),
          isEmpty,
        );

        // 2. Active drag on Canvas A:
        // - Unrelated ancestor shortcut (KeyR) still fires normally.
        // - Escape KeyDown + KeyRepeat cancels & settles Canvas A ONCE without
        //   triggering ancestor Escape or affecting Canvas B.
        eventsA.clear();
        writesA.clear();
        final drag1 = await tester.startGesture(
          a1Point,
          kind: PointerDeviceKind.mouse,
        );
        await drag1.moveTo(Offset(rectA.left + rectA.width * 0.65, a1Point.dy));
        await tester.pump();
        final writesBeforeEsc1 = writesA.length;
        expect(writesBeforeEsc1, greaterThan(0));
        expect(writesA.last.value, 65);
        expect(writesA.last.changing, isTrue);

        // Unrelated shortcut during active drag remains untouched.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.pump();
        expect(unrelatedShortcutCount, 1);

        // Escape cancels drag once; repeated key event while held must neither
        // trigger ancestor Escape nor emit a second terminal/settle write.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(
          ancestorEscapeCount,
          2,
          reason: 'ancestor Escape must not fire during Canvas A active drag',
        );
        expect(writesA, hasLength(writesBeforeEsc1 + 1));
        expect(
          writesA
              .where((w) => !w.changing)
              .map((w) => (w.parameterNumber, w.value)),
          [(1, 65)],
        );
        expect(writesB, isEmpty);
        expect(eventsB, isEmpty);

        // Late move/up after Escape produce zero writes and zero extra terminals.
        await drag1.moveTo(Offset(rectA.left + rectA.width * 0.9, a1Point.dy));
        await drag1.up();
        await tester.pump();
        expect(writesA, hasLength(writesBeforeEsc1 + 1));
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel ||
                e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
          ),
          hasLength(1),
        );
        expect(
          eventsA.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.escapeKey,
        );

        // 3. Idle after terminal cancel: Escape reaches ancestor shortcut again.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 3);
        expect(writesA, hasLength(writesBeforeEsc1 + 1));

        // 4. Focus transfer within Canvas A during drag + repeated Escape presses:
        // first cancels once (ancestor untouched), second reaches ancestor (idle),
        // zero extra terminals/settlements.
        writesA.clear();
        eventsA.clear();
        final drag2 = await tester.startGesture(
          a1Point,
          kind: PointerDeviceKind.mouse,
        );
        await drag2.moveTo(Offset(rectA.left + rectA.width * 0.70, a1Point.dy));
        await tester.pump();
        final writesBeforeEsc2 = writesA.length;

        // Transfer focus to sibling target a2 inside Canvas A mid-drag.
        final a2Focus = Focus.of(
          tester.element(
            find.byKey(const ValueKey('algorithm-controller-canvas-target:a2')),
          ),
        );
        a2Focus.requestFocus();
        await tester.pump();
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                AlgorithmControllerCanvasInteractionEventType.dragCancel,
          ),
          isEmpty,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 3);
        expect(writesA, hasLength(writesBeforeEsc2 + 1));
        expect(
          writesA
              .where((w) => !w.changing)
              .map((w) => (w.parameterNumber, w.value)),
          [(1, 70)],
        );

        // Second Escape while now idle reaches ancestor with zero extra Canvas A terminals.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 4);
        await drag2.up();
        await tester.pump();
        expect(writesA, hasLength(writesBeforeEsc2 + 1));
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel ||
                e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
          ),
          hasLength(1),
        );

        // 5. Focus transfer OUTSIDE Canvas A during drag does not cause extra
        // terminals/settlements; ancestor receives Escape when external widget
        // holds focus, and pointer release settles Canvas A cleanly once.
        writesA.clear();
        eventsA.clear();
        final drag3 = await tester.startGesture(
          a1Point,
          kind: PointerDeviceKind.mouse,
        );
        await drag3.moveTo(Offset(rectA.left + rectA.width * 0.75, a1Point.dy));
        await tester.pump();
        externalFocus.requestFocus();
        await tester.pump();
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel ||
                e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
          ),
          isEmpty,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 5);
        await drag3.up();
        await tester.pump();
        expect(
          eventsA.where(
            (e) =>
                e.type ==
                    AlgorithmControllerCanvasInteractionEventType.dragCancel ||
                e.type == AlgorithmControllerCanvasInteractionEventType.dragEnd,
          ),
          hasLength(1),
        );
        expect(
          eventsA.last.type,
          AlgorithmControllerCanvasInteractionEventType.dragEnd,
        );
        expect(writesA.where((w) => !w.changing), hasLength(1));

        // 6. Pre-threshold Escape cancels pending press with zero writes and
        // consumes Escape; subsequent idle Escape reaches ancestor unchanged.
        writesA.clear();
        eventsA.clear();
        final preDrag = await tester.startGesture(
          a2Point,
          kind: PointerDeviceKind.mouse,
        );
        await preDrag.moveBy(const Offset(2, 0));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 5);
        await preDrag.moveBy(const Offset(80, 0));
        await preDrag.up();
        await tester.pump();
        expect(writesA, isEmpty);
        expect(eventsA, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 6);

        // 7. Disposal during active drag emits disposed cancel with no settle
        // write, and Escape after disposal reaches ancestor shortcut unchanged.
        writesA.clear();
        eventsA.clear();
        final drag4 = await tester.startGesture(
          a1Point,
          kind: PointerDeviceKind.mouse,
        );
        await drag4.moveTo(Offset(rectA.left + rectA.width * 0.80, a1Point.dy));
        await tester.pump();
        expect(writesA.where((w) => w.changing), isNotEmpty);

        await tester.pumpWidget(buildTree(mountCanvasA: false));
        await tester.pump();
        expect(writesA.where((w) => !w.changing), isEmpty);
        expect(
          eventsA.last.cancelReason,
          AlgorithmControllerCanvasCancelReason.disposed,
        );

        externalFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(ancestorEscapeCount, 7);
        expect(writesB, isEmpty);
        expect(eventsB, isEmpty);
      },
    );
  });
}

final class _TestClearSelectionIntent extends Intent {
  const _TestClearSelectionIntent();
}

final class _TestUnrelatedShortcutIntent extends Intent {
  const _TestUnrelatedShortcutIntent();
}

Future<void> _mouseClick(
  WidgetTester tester,
  Offset position, {
  int buttons = kPrimaryMouseButton,
}) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await gesture.up();
  await tester.pump();
}

final class _NoOpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

final class _EarlyAcceptGestureRecognizer extends OneSequenceGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      resolve(GestureDisposition.accepted);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'earlyAcceptTestRecognizer';
}

final class _ManualClaimGestureRecognizer extends OneSequenceGestureRecognizer {
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
  }

  void claimArena() {
    final pointer = _pointer;
    if (pointer == null) return;
    _pointer = null;
    resolvePointer(pointer, GestureDisposition.accepted);
    stopTrackingPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_pointer == event.pointer) _pointer = null;
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'manualClaimTestRecognizer';
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.cubit,
    required this.slot,
    required this.source,
    this.units = const [],
    this.assetPath = 'synthetic.lua',
    this.onCanvasInteraction,
  });

  final DistingCubit cubit;
  final Slot slot;
  final String source;
  final List<String> units;
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
            units: widget.units,
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
