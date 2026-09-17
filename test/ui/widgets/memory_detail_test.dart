import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/ui/widgets/memory_detail.dart';

const _sample = MemoryUsage(
  sram: MemoryPoolUsage(total: 64 * 1024, current: 16 * 1024),
  dram: MemoryPoolUsage(total: 8 * 1024 * 1024, current: 2 * 1024 * 1024),
  dtc: MemoryPoolUsage(total: 4 * 1024, current: 1024),
  itc: MemoryPoolUsage(total: 512, current: 128),
);

final class _ControlledMemorySource {
  final StreamController<MemoryDisplayState> _states =
      StreamController<MemoryDisplayState>.broadcast(sync: true);

  MemoryDisplayState state = const MemoryDisplayState.unavailable();
  int refreshCalls = 0;
  final List<Completer<void>> _pendingRefreshes = [];

  Stream<MemoryDisplayState> get states => _states.stream;

  Future<void> refresh() {
    refreshCalls += 1;
    emit(MemoryDisplayState.refreshing(previousSample: state.sample));
    final completion = Completer<void>();
    _pendingRefreshes.add(completion);
    return completion.future;
  }

  void completeRefresh(MemoryDisplayState nextState) {
    emit(nextState);
    _pendingRefreshes.removeAt(0).complete();
  }

  void emit(MemoryDisplayState nextState) {
    state = nextState;
    _states.add(nextState);
  }

  Future<void> close() async {
    for (final completion in _pendingRefreshes) {
      completion.complete();
    }
    await _states.close();
  }
}

void main() {
  Widget openerHost(_ControlledMemorySource source) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: Scaffold(
        body: Center(
          child: MemoryDetailOpener(
            initialState: source.state,
            stateStream: source.states,
            onOpened: source.refresh,
            child: const Icon(Icons.memory, key: ValueKey('memory-trigger')),
          ),
        ),
      ),
    );
  }

  Widget presenterHost(MemoryDisplayState state) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: MemoryDetailPresenter(state: state)),
      ),
    );
  }

  group('MemoryDetailOpener', () {
    testWidgets(
      'mouse, focus, touch and keyboard share one refresh per opening',
      (tester) async {
        final source = _ControlledMemorySource();
        addTearDown(source.close);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(openerHost(source));

        final trigger = find.bySemanticsLabel('Show memory details');
        expect(trigger, findsOneWidget);
        final triggerNode = tester.getSemantics(trigger).getSemanticsData();
        expect(triggerNode.flagsCollection.isButton, isTrue);
        expect(triggerNode.hasAction(SemanticsAction.tap), isTrue);
        expect(tester.getSize(trigger).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer();
        await mouse.moveTo(tester.getCenter(trigger));
        await tester.pump();

        expect(source.refreshCalls, 1);
        expect(find.byType(MemoryDetailPresenter), findsOneWidget);

        // A touch activation focuses the already-open control. Enter and Space
        // are then further open requests, not new opening transitions.
        await tester.tap(trigger);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(source.refreshCalls, 1);

        final focusedNode = tester.getSemantics(trigger).getSemanticsData();
        expect(focusedNode.flagsCollection.isFocused, Tristate.isTrue);
        final decoration = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(MemoryDetailOpener),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((widget) => widget.decoration)
            .whereType<BoxDecoration>()
            .singleWhere((value) => value.border != null);
        expect(
          (decoration.border! as Border).top.color,
          Theme.of(tester.element(trigger)).colorScheme.primary,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(MemoryDetailPresenter), findsNothing);
        expect(source.refreshCalls, 1);

        // Focus remains on the opener, so a later keyboard activation is a
        // genuine closed-to-open transition.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.byType(MemoryDetailPresenter), findsOneWidget);
        expect(source.refreshCalls, 2);
        semantics.dispose();
      },
    );

    testWidgets('keyboard focus and touch can each open the detail', (
      tester,
    ) async {
      final source = _ControlledMemorySource();
      addTearDown(source.close);
      await tester.pumpWidget(openerHost(source));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(source.refreshCalls, 1);
      expect(find.byType(MemoryDetailPresenter), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsNothing);

      await tester.tap(find.byKey(const ValueKey('memory-trigger')));
      await tester.pump();
      expect(source.refreshCalls, 2);
      expect(find.byType(MemoryDetailPresenter), findsOneWidget);
    });

    testWidgets(
      'synchronous refresh state is safe and completes asynchronously',
      (tester) async {
        final source = _ControlledMemorySource();
        addTearDown(source.close);
        await tester.pumpWidget(openerHost(source));

        await tester.tap(find.byKey(const ValueKey('memory-trigger')));
        await tester.pump();
        expect(source.refreshCalls, 1);
        expect(tester.takeException(), isNull);

        await tester.pump();
        expect(find.text('Refreshing'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(12));
        expect(find.text('0 B'), findsNothing);

        source.completeRefresh(const MemoryDisplayState.available(_sample));
        await tester.pump();
        expect(find.text('Updated'), findsOneWidget);
        expect(find.text('2 MiB'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byType(MemoryDetailPresenter), findsNothing);
        expect(source.refreshCalls, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(source.refreshCalls, 2);
        expect(tester.takeException(), isNull);

        await tester.pump();
        expect(find.text('Refreshing'), findsOneWidget);
        expect(find.text('16 KiB'), findsOneWidget);
        expect(source.refreshCalls, 2);
      },
    );
  });

  group('MemoryDetailOpeningHook', () {
    testWidgets('calls once per mount and can wrap System detail directly', (
      tester,
    ) async {
      final source = _ControlledMemorySource();
      addTearDown(source.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MemoryDetailOpeningHook(
            key: const ValueKey('system-memory-opening'),
            onOpened: source.refresh,
            child: MemoryDetailPresenter(state: source.state),
          ),
        ),
      );
      expect(source.refreshCalls, 1);

      source.emit(const MemoryDisplayState.available(_sample));
      await tester.pumpWidget(
        const MaterialApp(
          home: MemoryDetailOpeningHook(
            key: ValueKey('system-memory-opening'),
            onOpened: _noOpOpen,
            child: MemoryDetailPresenter(
              state: MemoryDisplayState.available(_sample),
            ),
          ),
        ),
      );
      expect(source.refreshCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: MemoryDetailOpeningHook(
            key: const ValueKey('system-memory-opening'),
            onOpened: source.refresh,
            child: MemoryDetailPresenter(state: source.state),
          ),
        ),
      );
      expect(source.refreshCalls, 2);
    });
  });

  group('MemoryDetailPresenter', () {
    testWidgets('renders pools and current, total and free values in order', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        presenterHost(const MemoryDisplayState.available(_sample)),
      );

      final poolNames = ['SRAM', 'DRAM', 'DTC', 'ITC'];
      final poolOffsets = poolNames
          .map((name) => tester.getTopLeft(find.text(name)).dy)
          .toList();
      expect(poolOffsets, orderedEquals([...poolOffsets]..sort()));

      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.bySemanticsLabel('SRAM current, 16 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('SRAM total, 64 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('SRAM free, 48 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DRAM current, 2 MiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DRAM total, 8 MiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DRAM free, 6 MiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DTC current, 1 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('ITC current, 128 B'), findsOneWidget);
      expect(find.bySemanticsLabel('ITC free, 384 B'), findsOneWidget);

      expect(find.text('Used / total · free shown at right'), findsNothing);
      expect(find.textContaining('fit'), findsNothing);
      expect(find.textContaining('topology'), findsNothing);
      expect(find.textContaining('required'), findsNothing);
      semantics.dispose();
    });

    testWidgets('formats fractional binary units without losing exact values', (
      tester,
    ) async {
      const fractionalSample = MemoryUsage(
        sram: MemoryPoolUsage(total: 0, current: 1536),
        dram: MemoryPoolUsage(total: 3 * 1024 * 1024, current: 1572864),
        dtc: MemoryPoolUsage(total: 1537, current: 1),
        itc: MemoryPoolUsage(total: 512, current: 128),
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        presenterHost(const MemoryDisplayState.available(fractionalSample)),
      );

      expect(find.text('1.5 KiB'), findsNWidgets(2));
      expect(find.text('1.5 MiB'), findsNWidgets(2));
      expect(find.text('1537 B'), findsOneWidget);
      expect(find.text('-1.5 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('SRAM current, 1.5 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('SRAM free, -1.5 KiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DRAM current, 1.5 MiB'), findsOneWidget);
      expect(find.bySemanticsLabel('DTC total, 1537 B'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('retains readings while refreshing and exposes live status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        presenterHost(
          const MemoryDisplayState.refreshing(previousSample: _sample),
        ),
      );

      expect(find.text('Refreshing'), findsOneWidget);
      expect(find.text('16 KiB'), findsOneWidget);
      expect(find.text('2 MiB'), findsOneWidget);
      final status = tester.getSemantics(
        find.bySemanticsLabel('Refreshing memory values'),
      );
      expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });

    testWidgets(
      'uses placeholders without a sample and never fabricates zero',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          presenterHost(const MemoryDisplayState.unavailable()),
        );

        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.text('—'), findsNWidgets(12));
        expect(find.text('0 B'), findsNothing);
        expect(find.bySemanticsLabel('SRAM current, —'), findsOneWidget);
        expect(find.bySemanticsLabel('ITC free, —'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('marks retained failed-refresh data as subtly unfresh', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        presenterHost(const MemoryDisplayState.unfresh(_sample)),
      );

      expect(find.text('Unfresh'), findsOneWidget);
      expect(find.text('16 KiB'), findsOneWidget);
      expect(find.textContaining('warning', findRichText: true), findsNothing);
      expect(find.textContaining('failed', findRichText: true), findsNothing);
      final status = tester.getSemantics(
        find.bySemanticsLabel(
          'Memory values are unfresh because the latest refresh failed',
        ),
      );
      expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });
  });
}

Future<void> _noOpOpen() async {}
