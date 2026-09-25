import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';

class _MockRoutingEditorCubit extends Mock implements RoutingEditorCubit {}

void main() {
  // Writing bus 64 makes the table show 64 bus columns, far wider than the
  // 500px viewport, so the bus columns overflow horizontally. Many [slots]
  // also overflow vertically, so the desktop vertical scrollbar is present.
  Future<ScrollPosition> pumpOverflowingTable(
    WidgetTester tester, {
    int slots = 1,
  }) async {
    tester.view.physicalSize = const Size(500, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final cubit = _MockRoutingEditorCubit();
    when(() => cubit.state).thenReturn(
      RoutingEditorState.loaded(
        deviceIoProfile: DeviceIoProfile.distingExtended,
        physicalInputs: const [],
        physicalOutputs: const [],
        algorithms: [for (var i = 0; i < slots; i++) _algorithmWritingBus64(i)],
        connections: const [],
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RoutingEditorCubit>.value(
          value: cubit,
          child: const Scaffold(body: RoutingTableView()),
        ),
      ),
    );

    final position = tester
        .state<ScrollableState>(
          find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          ),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, 0);
    return position;
  }

  testWidgets('left-button mouse drag on the table scrolls horizontally', (
    tester,
  ) async {
    final position = await pumpOverflowingTable(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(const Offset(400, 60));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-80, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
  });

  testWidgets('mouse drag past the end clamps to the scroll extent', (
    tester,
  ) async {
    final position = await pumpOverflowingTable(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(const Offset(450, 60));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-5000, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position.pixels, position.maxScrollExtent);
  });

  testWidgets('pointer-scroll signal still scrolls the table horizontally', (
    tester,
  ) async {
    final position = await pumpOverflowingTable(tester);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(400, 60)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(120, 0)));
    await tester.pumpAndSettle();

    expect(position.pixels, 120);
  });

  testWidgets(
    'desktop vertical scrollbar thumb drag still works over the bus columns',
    (tester) async {
      final horizontal = await pumpOverflowingTable(tester, slots: 12);
      final vertical = tester
          .state<ScrollableState>(
            find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .position;
      expect(vertical.maxScrollExtent, greaterThan(0));
      // A small wheel scroll reveals the (auto-hiding) desktop thumb, which
      // then sits near the top of the right edge, over the mouse-draggable
      // bus columns.
      const thumb = Offset(496, 30);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: thumb);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(450, 30),
          scrollDelta: Offset(0, 10),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(vertical.pixels, 10);
      await mouse.down(thumb);
      await tester.pumpAndSettle();
      await mouse.moveBy(const Offset(0, 30));
      await tester.pumpAndSettle();
      await mouse.up();
      await tester.pumpAndSettle();

      expect(vertical.pixels, greaterThan(10));
      expect(horizontal.pixels, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('trackpad pan still scrolls the table horizontally', (
    tester,
  ) async {
    final position = await pumpOverflowingTable(tester);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(const Offset(400, 60));
    await gesture.panZoomUpdate(
      const Offset(400, 60),
      pan: const Offset(-120, 0),
    );
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
  });
}

RoutingAlgorithm _algorithmWritingBus64(int index) => RoutingAlgorithm(
  id: 'writer_$index',
  index: index,
  algorithm: Algorithm(
    algorithmIndex: index,
    guid: 'writer',
    name: 'Writer $index',
  ),
  inputPorts: const [],
  outputPorts: [
    Port(
      id: 'writer_${index}_out',
      name: 'Output',
      type: PortType.audio,
      direction: PortDirection.output,
      busValue: 64,
      outputMode: OutputMode.add,
    ),
  ],
);
