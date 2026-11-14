import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/ui/widgets/mobile_drill_down_navigator.dart';
import 'package:nt_helper/ui/widgets/preset_browser_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Manager extends Mock implements IDistingMidiManager {}

class _Disting extends Mock implements DistingCubit {}

DirectoryEntry _entry(String name, {bool directory = false}) => DirectoryEntry(
  name: name,
  attributes: directory ? 0x10 : 0,
  date: 0,
  time: 0,
  size: 0,
);

void main() {
  late PresetBrowserCubit cubit;
  late _Manager manager;
  late DateTime now;
  late Map<String, List<DirectoryEntry>> files;
  late List<String> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime(2026);
    requests = [];
    manager = _Manager();
    files = {
      '/': [_entry('A/', directory: true), _entry('B/', directory: true)],
      '/A': [_entry('one.json')],
      '/B': [_entry('two.json')],
    };
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final path = call.positionalArguments.single as String;
      requests.add(path);
      return DirectoryListing(entries: files[path]!);
    });
    cubit = PresetBrowserCubit(
      midiManager: manager,
      prefs: prefs,
      clock: Clock(() => now),
    );
  });
  tearDown(() => cubit.close());

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 950);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<PresetBrowserCubit>.value(
            value: cubit,
            child: PresetBrowserDialog(distingCubit: _Disting()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder pane(int index) => find.byType(DirectoryPanel).at(index);
  Future<void> tapItem(WidgetTester tester, int index, String name) async {
    await tester.tap(
      find.descendant(of: pane(index), matching: find.text(name)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'per-pane back, drop paths and mobile reflow use the same stacks',
    (tester) async {
      await mount(tester);
      await tapItem(tester, 0, 'A');
      await tapItem(tester, 0, 'one.json');
      await tapItem(tester, 1, 'B');
      await tapItem(tester, 1, 'two.json');
      expect(cubit.getSelectedPath(), '/B/two.json');
      expect(
        tester
            .widgetList<DirectoryPanel>(find.byType(DirectoryPanel))
            .map((p) => p.dropTargetDirectory),
        ['/A', '/B', '/'],
      );
      await tester.tap(find.byTooltip('Back in center pane'));
      await tester.pumpAndSettle();
      expect(cubit.getPanelDirectory(PanelPosition.center), '/');
      expect(cubit.state.view!.selection(PanelPosition.left)!.name, 'one.json');
      expect(cubit.getSelectedPath(), isEmpty);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(MobileDrillDownNavigator), findsOneWidget);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(cubit.getPanelDirectory(PanelPosition.center), '/B');
      await tester.tap(find.text('two.json'));
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/B/two.json');
      tester.view.physicalSize = const Size(1400, 950);
      await tester.pumpAndSettle();
      expect(cubit.getPanelDirectory(PanelPosition.left), '/A');
      expect(cubit.getPanelDirectory(PanelPosition.right), '/');
      expect(
        tester.widget<DirectoryPanel>(pane(1)).selectedItem!.name,
        'two.json',
      );
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'pane paths expose headers and active selection to screen readers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester);
        await tapItem(tester, 0, 'A');
        final left = tester.getSemantics(
          find.bySemanticsLabel('left pane: /A'),
        );
        expect(left.flagsCollection.isHeader, isTrue);
        expect(left.flagsCollection.isSelected, Tristate.isTrue);
        await tapItem(tester, 1, 'B');
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('left pane: /A'))
              .flagsCollection
              .isSelected,
          Tristate.isFalse,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('center pane: /B'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    tags: ['regression'],
  );

  testWidgets(
    'keyboard enter stays in its pane and Alt-Left pops only that pane',
    (tester) async {
      await mount(tester);
      await tester.tapAt(tester.getBottomLeft(pane(0)) + const Offset(10, -10));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.state.view!.activePane, PanelPosition.left);
      expect(cubit.getPanelDirectory(PanelPosition.left), '/A');
      expect(cubit.getPanelDirectory(PanelPosition.center), '/');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/one.json');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(cubit.getPanelDirectory(PanelPosition.left), '/');
      expect(cubit.state.view!.pane(PanelPosition.center).stack, hasLength(1));
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets('app resume revalidates stale visible paths once each', (
    tester,
  ) async {
    await mount(tester);
    await tapItem(tester, 0, 'A');
    requests.clear();
    files['/A'] = [_entry('external.json')];
    now = now.add(const Duration(seconds: 6));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests.toSet(), {'/A', '/'});
    expect(requests, hasLength(2));
    expect(find.text('external.json'), findsOneWidget);
    expect(cubit.getPanelDirectory(PanelPosition.left), '/A');
    expect(tester.takeException(), isNull);
  }, tags: ['regression']);

  testWidgets(
    'empty pane pointer focus refreshes stale data without polling',
    (tester) async {
      files['/A'] = [];
      await mount(tester);
      await tapItem(tester, 0, 'A');
      requests.clear();
      now = now.add(const Duration(seconds: 6));
      files['/A'] = [_entry('external #42.json')];
      await tester.tapAt(tester.getCenter(pane(0)));
      await tester.pumpAndSettle();
      expect(requests, ['/A']);
      expect(find.text('external #42.json'), findsOneWidget);
      await tester.tapAt(tester.getBottomLeft(pane(0)) + const Offset(10, -10));
      await tester.pumpAndSettle();
      expect(requests, ['/A']);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets('refresh and error feedback keep pane geometry stable', (
    tester,
  ) async {
    await mount(tester);
    await tapItem(tester, 0, 'A');
    final before = tester.getRect(pane(0));
    final started = Completer<void>();
    final response = Completer<DirectoryListing?>();
    when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
      started.complete();
      return response.future;
    });
    final refresh = cubit.refreshPane(PanelPosition.left);
    await started.future;
    await tester.pump();
    expect(tester.getRect(pane(0)), before);
    response.completeError(StateError('Unavailable'));
    await refresh;
    await tester.pumpAndSettle();
    expect(tester.getRect(pane(0)), before);
    expect(
      find.byTooltip('Retry left pane: Bad state: Unavailable'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }, tags: ['regression']);

  testWidgets('mobile pull refresh awaits the actual listing request', (
    tester,
  ) async {
    await mount(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final started = Completer<void>();
    final response = Completer<DirectoryListing?>();
    when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
      started.complete();
      return response.future;
    });
    var finished = false;
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh()
        .then((_) => finished = true);
    await started.future;
    expect(finished, isFalse);
    response.complete(DirectoryListing(entries: [_entry('new.json')]));
    await refresh;
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(find.text('new.json'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, tags: ['regression']);
}
