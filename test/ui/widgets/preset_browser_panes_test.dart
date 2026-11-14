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

DirectoryEntry entry(String name, {bool dir = false}) => DirectoryEntry(
  name: name,
  attributes: dir ? 0x10 : 0,
  date: 0,
  time: 0,
  size: 0,
);

void main() {
  late PresetBrowserCubit cubit;
  late _Manager manager;
  late DateTime now;
  late Map<String, List<DirectoryEntry>> files;
  late List<String> reads;
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime(2026);
    reads = [];
    manager = _Manager();
    files = {
      '/': [entry('A/', dir: true), entry('B/', dir: true), entry('root.json')],
      '/A': [entry('child/', dir: true), entry('one.json')],
      '/A/child': [entry('deep/', dir: true), entry('two.json')],
      '/A/child/deep': [entry('four/', dir: true), entry('three.json')],
      '/A/child/deep/four': [],
      '/B': [entry('B.json')],
    };
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final path = call.positionalArguments.single as String;
      reads.add(path);
      final values = files[path];
      return values == null ? null : DirectoryListing(entries: [...values]);
    });
    cubit = PresetBrowserCubit(
      midiManager: manager,
      prefs: prefs,
      clock: Clock(() => now),
    );
  });
  tearDown(() => cubit.close());
  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
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
    if (settle) await tester.pumpAndSettle();
  }

  Finder pane(int index) => find.byType(DirectoryPanel).at(index);
  List<String> paths(WidgetTester tester) => tester
      .widgetList<DirectoryPanel>(find.byType(DirectoryPanel))
      .map((w) => w.currentPath)
      .toList();
  Future<void> tap(WidgetTester tester, int column, String text) async {
    await tester.tap(
      find.descendant(of: pane(column), matching: find.text(text)),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Rect> geometry(WidgetTester tester) => {
    'dialog': tester.getRect(find.byKey(const Key('preset-browser-dialog'))),
    'toolbar': tester.getRect(find.byKey(const Key('preset-browser-toolbar'))),
    if (find
        .byKey(const Key('preset-browser-breadcrumbs'))
        .evaluate()
        .isNotEmpty)
      'breadcrumbs': tester.getRect(
        find.byKey(const Key('preset-browser-breadcrumbs')),
      ),
    'status': tester.getRect(find.byKey(const Key('preset-browser-status'))),
    if (find.byType(MobileDrillDownNavigator).evaluate().isNotEmpty)
      'mobileNavigator': tester.getRect(find.byType(MobileDrillDownNavigator)),
    if (find.byType(RefreshIndicator).evaluate().isNotEmpty)
      'mobileContent': tester.getRect(find.byType(RefreshIndicator)),
    'back': tester.getRect(find.byTooltip('Back')),
    'load': tester.getRect(find.widgetWithText(ElevatedButton, 'Load')),
    'cancel': tester.getRect(find.widgetWithText(TextButton, 'Cancel')),
    if (find.widgetWithText(OutlinedButton, 'Export').evaluate().isNotEmpty)
      'export': tester.getRect(find.widgetWithText(OutlinedButton, 'Export')),
    for (var i = 0; i < find.byType(DirectoryPanel).evaluate().length; i++)
      'column$i': tester.getRect(pane(i)),
    for (final p in PanelPosition.values)
      if (find
          .byKey(ValueKey('browser-column-header-${p.name}'))
          .evaluate()
          .isNotEmpty)
        'header${p.name}': tester.getRect(
          find.byKey(ValueKey('browser-column-header-${p.name}')),
        ),
  };

  testWidgets(
    'exactly three fixed columns cascade and shift with full Back and breadcrumb ancestry',
    (tester) async {
      await mount(tester);
      final rects = geometry(tester);
      expect(paths(tester), ['/', '', '']);
      expect(
        tester.widget<DirectoryPanel>(pane(1)).dropTargetDirectory,
        isNull,
      );
      expect(find.widgetWithText(OutlinedButton, 'Export'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 0, 'A');
      expect(paths(tester), ['/', '/A', '']);
      expect(geometry(tester), rects);
      await tap(tester, 1, 'child');
      expect(paths(tester), ['/', '/A', '/A/child']);
      expect(geometry(tester), rects);
      await tap(tester, 2, 'deep');
      expect(paths(tester), ['/A', '/A/child', '/A/child/deep']);
      expect(geometry(tester), rects);
      await tap(tester, 2, 'four');
      expect(paths(tester), [
        '/A/child',
        '/A/child/deep',
        '/A/child/deep/four',
      ]);
      expect(geometry(tester), rects);
      expect(find.byType(DirectoryPanel), findsNWidgets(3));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(paths(tester), ['/A', '/A/child', '/A/child/deep']);
      expect(geometry(tester), rects);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('preset-browser-breadcrumbs')),
          matching: find.byTooltip('/A'),
        ),
      );
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/A', '']);
      expect(geometry(tester), rects);
      await tester.tap(find.byTooltip('Go to root'));
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '', '']);
      expect(geometry(tester), rects);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Back',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'sibling and ancestor file selection discard obsolete columns without geometry changes',
    (tester) async {
      await mount(tester);
      final rects = geometry(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'child');
      await tap(tester, 2, 'two.json');
      expect(cubit.getSelectedPath(), '/A/child/two.json');
      expect(geometry(tester), rects);
      await tap(tester, 0, 'B');
      expect(paths(tester), ['/', '/B', '']);
      expect(cubit.getSelectedPath(), isEmpty);
      expect(geometry(tester), rects);
      await tap(tester, 0, 'root.json');
      expect(paths(tester), ['/', '', '']);
      expect(cubit.getSelectedPath(), '/root.json');
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'root pending error retry, refresh and empty states preserve dialog and all column rectangles',
    (tester) async {
      final started = Completer<void>();
      final root = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
        started.complete();
        return root.future;
      });
      await mount(tester, settle: false);
      await started.future;
      await tester.pump();
      final rects = geometry(tester);
      root.completeError(StateError('Unavailable'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Failed to load root'), findsOneWidget);
      expect(geometry(tester), rects);
      when(
        () => manager.requestDirectoryListing('/'),
      ).thenAnswer((_) async => DirectoryListing(entries: files['/']!));
      await tester.tap(find.byTooltip('Retry'));
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      await tap(tester, 0, 'A');
      final startedRefresh = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        startedRefresh.complete();
        return response.future;
      });
      final refresh = cubit.refreshPane();
      await startedRefresh.future;
      await tester.pump();
      expect(geometry(tester), rects);
      response.complete(DirectoryListing(entries: []));
      await refresh;
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      expect(paths(tester), ['/', '/A', '']);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'verified rename and held overwrite leave content and controls in reserved geometry',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'one.json');
      final rects = geometry(tester);
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(
        () => manager.requestFileRename('/A/one.json', '/A/new.json'),
      ).thenAnswer((_) async {
        files['/A']![1] = entry('new.json');
        return SdCardStatus(success: true, message: '');
      });
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final rename = cubit.renameEntry('/A/one.json', 'new.json');
      await tester.pump();
      await started.future;
      await tester.pump();
      expect(geometry(tester), rects);
      expect(find.text('one.json'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Load'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Export'),
            )
            .onPressed,
        isNull,
      );
      response.complete(DirectoryListing(entries: files['/A']!));
      await tester.pump();
      await rename;
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/new.json');
      expect(geometry(tester), rects);
      when(
        () => manager.requestDirectoryListing('/A'),
      ).thenAnswer((_) async => DirectoryListing(entries: files['/A']!));
      final chunkStarted = Completer<void>();
      final ack = Completer<SdCardStatus?>();
      final chunks = <(int, int)>[];
      when(
        () => manager.requestFileUploadChunk(
          '/A/new.json',
          any(),
          any(),
          createAlways: any(named: 'createAlways'),
        ),
      ).thenAnswer((call) {
        final offset = call.positionalArguments[2] as int;
        chunks.add((offset, (call.positionalArguments[1] as Uint8List).length));
        if (offset == 0) {
          chunkStarted.complete();
          return ack.future;
        }
        return Future.value(SdCardStatus(success: true, message: ''));
      });
      final upload = cubit.uploadFile('/A', 'new.json', Uint8List(513));
      await tester.pump();
      await chunkStarted.future;
      await tester.pump();
      expect(geometry(tester), rects);
      expect(cubit.getSelectedPath(), isEmpty);
      ack.complete(SdCardStatus(success: true, message: ''));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await upload;
      await tester.pumpAndSettle();
      expect(chunks, [(0, 512), (512, 1)]);
      expect(geometry(tester), rects);
      expect(cubit.getSelectedPath(), '/A/new.json');
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'folder rename rebases shifted columns and refresh removes a vanished descendant without moving boundaries',
    (tester) async {
      await mount(tester);
      final rects = geometry(tester);
      await cubit.navigateToAbsolutePath('/A/child/deep');
      await tester.pumpAndSettle();
      when(() => manager.requestFileRename('/A/child', '/A/Live')).thenAnswer((
        _,
      ) async {
        files['/A']![0] = entry('Live/', dir: true);
        for (final key
            in files.keys.where((p) => p.startsWith('/A/child')).toList()) {
          files['/A/Live${key.substring('/A/child'.length)}'] = files.remove(
            key,
          )!;
        }
        return SdCardStatus(success: true, message: '');
      });
      await cubit.renameEntry('/A/child', 'Live');
      await tester.pumpAndSettle();
      expect(paths(tester), ['/A', '/A/Live', '/A/Live/deep']);
      expect(geometry(tester), rects);
      files['/A/Live'] = [entry('other.json')];
      await cubit.refreshPane(PanelPosition.center);
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/A', '/A/Live']);
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'header focus and Alt-Left use shared ancestry; semantic header and selection are accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester);
        await tap(tester, 0, 'A');
        await tap(tester, 1, 'child');
        final centerHeader = tester.getSemantics(
          find.bySemanticsLabel('center pane: /A'),
        );
        expect(centerHeader.flagsCollection.isHeader, isTrue);
        final refresh = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'Refresh left pane',
          ),
        );
        refresh.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('left pane: /'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(paths(tester), ['/', '/A', '']);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    tags: ['regression'],
  );

  testWidgets(
    'keyboard opens folder into next column and selection focus does not open an independent browser',
    (tester) async {
      await mount(tester);
      await tester.tapAt(tester.getBottomLeft(pane(0)) + const Offset(10, -10));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/A', '']);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/A', '/A/child']);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'location scrolling survives column shift and Back; new locations start at top',
    (tester) async {
      files['/A'] = [
        for (var i = 0; i < 30; i++)
          entry('dir${i.toString().padLeft(2, '0')}/', dir: true),
        entry('zChild/', dir: true),
      ];
      files['/A/zChild'] = [
        entry('next/', dir: true),
        for (var i = 0; i < 70; i++)
          entry('${i.toString().padLeft(3, '0')}.json'),
      ];
      files['/A/zChild/next'] = [];
      await mount(tester);
      await tap(tester, 0, 'A');
      await tester.scrollUntilVisible(
        find.text('zChild'),
        500,
        scrollable: find.descendant(
          of: pane(1),
          matching: find.byType(Scrollable),
        ),
      );
      await tap(tester, 1, 'zChild');
      expect(find.text('000.json').hitTestable(), findsOneWidget);
      await tap(tester, 2, 'next');
      expect(paths(tester), ['/A', '/A/zChild', '/A/zChild/next']);
      expect(
        find.widgetWithText(ListTile, 'zChild').hitTestable(),
        findsOneWidget,
      ); // /A moved column, retaining its scroll.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ListTile, 'zChild').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'same-path refresh preserves arrow cursor identity and row geometry independent of committed selection',
    (tester) async {
      files['/A'] = [for (var i = 0; i < 8; i++) entry('0$i.json')];
      await mount(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, '00.json');
      final rects = geometry(tester);
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final refresh = cubit.refreshPane();
      await started.future;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      final rowBefore = tester.getRect(
        find.widgetWithText(ListTile, '02.json'),
      );
      response.complete(DirectoryListing(entries: files['/A']!));
      await refresh;
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      expect(
        tester.getRect(find.widgetWithText(ListTile, '02.json')),
        rowBefore,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/02.json');
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'mobile and desktop render one hierarchy across resizing with fixed mobile breadcrumb and status regions',
    (tester) async {
      await mount(tester);
      await cubit.navigateToAbsolutePath('/A/child');
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(MobileDrillDownNavigator), findsOneWidget);
      final rects = geometry(tester);
      await tester.tap(find.text('deep'));
      await tester.pumpAndSettle();
      expect(cubit.getCurrentDirectory(), '/A/child/deep');
      expect(geometry(tester), rects);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(cubit.getCurrentDirectory(), '/A/child');
      expect(geometry(tester), rects);
      reads.clear();
      now = now.add(const Duration(seconds: 6));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, ['/A/child']);
      await tester.tap(find.bySemanticsLabel('Navigate to root'));
      await tester.pumpAndSettle();
      expect(cubit.getCurrentDirectory(), '/');
      expect(geometry(tester), rects);
      tester.view.physicalSize = const Size(1400, 950);
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '', '']);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'mobile pull refresh awaits real completion and pending/empty/error do not move content viewport',
    (tester) async {
      await mount(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      final rects = geometry(tester);
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      var done = false;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh()
          .then((_) => done = true);
      await started.future;
      await tester.pump();
      expect(done, isFalse);
      expect(geometry(tester), rects);
      response.completeError(StateError('Unavailable'));
      await refresh;
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      expect(cubit.getSelectedPath(), isEmpty);
      when(
        () => manager.requestDirectoryListing('/'),
      ).thenAnswer((_) async => DirectoryListing(entries: []));
      await cubit.refreshPane();
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
}
