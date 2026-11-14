import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  Future<void> mount(
    WidgetTester tester, {
    bool settle = true,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 950);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

  Future<void> backgroundMenu(WidgetTester tester, int column) async {
    await tester.tapAt(
      tester.getBottomRight(pane(column)) - const Offset(20, 20),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  Finder menuItem(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      )
      .first;

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
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
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
    'column focus and Alt-Left use shared ancestry; column paths and selection remain accessible without visible headers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester);
        await tap(tester, 0, 'A');
        await tap(tester, 1, 'child');
        expect(find.bySemanticsLabel('center pane: /A'), findsOneWidget);
        await tester.tapAt(
          tester.getBottomLeft(pane(0)) + const Offset(10, -10),
        );
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
      // ensureVisible updates the scroll position; render its final layout
      // before locating the last row's tap coordinates.
      await tester.pumpAndSettle();
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
  testWidgets(
    'breadcrumb text fits the reserved bar at the desktop UI scale without moving it',
    (tester) async {
      await mount(tester, textScale: 1.3);
      await cubit.navigateToAbsolutePath('/A');
      await tester.pumpAndSettle();
      final bar = find.byKey(const Key('preset-browser-breadcrumbs'));
      final normal = tester.getRect(bar);
      // The native retest exposed inner padding clipping at larger text sizes;
      // geometry-only navigation assertions could not catch content clipping.
      final text = find.descendant(of: bar, matching: find.text('A'));
      final rendered = tester.getRect(text);
      expect(rendered.top, greaterThanOrEqualTo(normal.top));
      expect(rendered.bottom, lessThanOrEqualTo(normal.bottom));
      await cubit.navigateToAbsolutePath('/A/child');
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), normal);
      expect(
        tester
            .getRect(find.descendant(of: bar, matching: find.text('child')))
            .bottom,
        lessThanOrEqualTo(normal.bottom),
      );
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
  testWidgets(
    'columns have no visible titles or refresh controls and unused columns remain blank',
    (tester) async {
      await mount(tester);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.text('/'), findsNothing);
      expect(find.text('—'), findsNothing);
      expect(find.text('Select a folder'), findsNothing);
      expect(find.text('Empty'), findsNothing);
      for (final position in PanelPosition.values) {
        expect(
          find.byKey(ValueKey('browser-column-header-${position.name}')),
          findsNothing,
        );
      }
      final bar = tester.getRect(
        find.byKey(const Key('preset-browser-breadcrumbs')),
      );
      expect(tester.getRect(pane(0)).top, bar.bottom);
      await backgroundMenu(tester, 1);
      expect(find.text('Refresh'), findsNothing);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'child');
      expect(find.text('/A'), findsNothing);
      expect(find.text('/A/child'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'blank column background and item context Refresh target their owning directory with contained menu placement',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'child');
      final rects = geometry(tester);
      for (var column = 0; column < 3; column++) {
        reads.clear();
        await backgroundMenu(tester, column);
        expect(find.text('Refresh'), findsOneWidget);
        final menu = tester.getRect(menuItem('Refresh'));
        expect(menu.left, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(1400));
        expect(menu.bottom, lessThanOrEqualTo(950));
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();
        expect(
          reads,
          [
            ['/'],
            ['/A'],
            ['/A/child'],
          ][column],
        );
        expect(geometry(tester), rects);
      }
      // On a folder item Refresh means refresh the containing column; folder-specific actions still target the folder.
      reads.clear();
      await tester.tap(find.text('child').last, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(reads, ['/A']);
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'refresh retains full-opacity contents until replacement with no Empty flash and blocks stale Load export and context mutations',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'one.json');
      final rects = geometry(tester);
      final original = tester.element(find.text('one.json'));
      final titleStyle = tester.widget<Text>(find.text('one.json')).style;
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final refresh = cubit.refreshDirectory('/A');
      await started.future;
      await tester.pump();
      expect(tester.element(find.text('one.json')), same(original));
      expect(tester.widget<Text>(find.text('one.json')).style, titleStyle);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'one.json'))
            .enabled,
        isTrue,
      );
      for (final opacity in tester.widgetList<Opacity>(
        find.ancestor(
          of: find.text('one.json'),
          matching: find.byType(Opacity),
        ),
      )) {
        expect(opacity.opacity, 1);
      }
      for (final fade in tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.text('one.json'),
          matching: find.byType(FadeTransition),
        ),
      )) {
        expect(fade.opacity.value, 1);
      }
      expect(find.textContaining('Empty'), findsNothing);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(geometry(tester), rects);
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
      await tester.tap(find.text('one.json'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      for (final label in ['Delete', 'Rename', 'Download']) {
        expect(tester.widget<PopupMenuItem>(menuItem(label)).enabled, isFalse);
      }
      expect(tester.widget<PopupMenuItem>(menuItem('Refresh')).enabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      response.completeError(StateError('Unavailable'));
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('one.json'), findsOneWidget);
      expect(find.textContaining('Empty'), findsNothing);
      expect(cubit.canUseEntry('/A/one.json'), isFalse);
      expect(geometry(tester), rects);
      when(() => manager.requestDirectoryListing('/A')).thenAnswer(
        (_) async => DirectoryListing(entries: [entry('replacement.json')]),
      );
      await cubit.refreshDirectory('/A');
      await tester.pumpAndSettle();
      expect(find.text('one.json'), findsNothing);
      expect(find.text('replacement.json'), findsOneWidget);
      expect(geometry(tester), rects);
      when(
        () => manager.requestDirectoryListing('/A'),
      ).thenAnswer((_) async => DirectoryListing(entries: []));
      await cubit.refreshDirectory('/A');
      await tester.pumpAndSettle();
      expect(find.textContaining('Empty'), findsNothing);
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'context action opened before a refresh cannot operate on retained uncertain entries',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tester.tap(find.text('one.json'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(tester.widget<PopupMenuItem>(menuItem('Delete')).enabled, isTrue);
      final response = Completer<DirectoryListing?>();
      when(
        () => manager.requestDirectoryListing('/A'),
      ).thenAnswer((_) => response.future);
      final refresh = cubit.refreshDirectory('/A');
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This cannot be undone'), findsNothing);
      verifyNever(() => manager.requestFileDelete(any()));
      response.complete(DirectoryListing(entries: files['/A']!));
      await refresh;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
  testWidgets(
    'mutation invalidation retains full-opacity listing until atomic verification rather than flashing empty',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'root.json');
      final rects = geometry(tester);
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(
        () => manager.requestDirectoryCreate('/new'),
      ).thenAnswer((_) async => SdCardStatus(success: true, message: ''));
      when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final create = cubit.createDirectory('/', 'new');
      await started.future;
      await tester.pump();
      expect(find.text('root.json'), findsOneWidget);
      expect(find.textContaining('Empty'), findsNothing);
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'root.json'))
            .enabled,
        isTrue,
      );
      expect(cubit.getSelectedPath(), isEmpty);
      expect(cubit.canUseEntry('/root.json'), isFalse);
      expect(geometry(tester), rects);
      response.complete(
        DirectoryListing(entries: [...files['/']!, entry('new/', dir: true)]),
      );
      await create;
      await tester.pumpAndSettle();
      expect(find.text('new'), findsOneWidget);
      expect(cubit.getSelectedPath(), '/root.json');
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'delete confirmation cannot submit while its parent is being revalidated',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tester.tap(find.text('one.json'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('This cannot be undone'), findsOneWidget);
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final refresh = cubit.refreshDirectory('/A');
      await started.future;
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      verifyNever(() => manager.requestFileDelete(any()));
      response.complete(DirectoryListing(entries: files['/A']!));
      await refresh;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
  Future<void> mouseClick(
    WidgetTester tester,
    Finder target, {
    int buttons = kPrimaryMouseButton,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
  }

  List<String> outlinedRows(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where(
        (container) =>
            container.foregroundDecoration is BoxDecoration &&
            (container.foregroundDecoration as BoxDecoration).borderRadius !=
                null,
      )
      .map(
        (container) =>
            (((container.child as ExcludeFocus).child as ListTile).title
                    as Text)
                .data!,
      )
      .toList();

  testWidgets(
    'mouse focus and rename dialog dismissal never outline row zero; renamed cursor and selection remain meaningful',
    (tester) async {
      files['/A'] = [entry('DualFilter.json'), entry('InitA.json')];
      await mount(tester);
      await mouseClick(tester, find.text('A'));
      await mouseClick(tester, find.text('InitA.json'));
      expect(outlinedRows(tester), isEmpty);
      when(
        () => manager.requestFileRename('/A/InitA.json', '/A/InitA1.json'),
      ).thenAnswer((_) async {
        files['/A']![1] = entry('InitA1.json');
        return SdCardStatus(success: true, message: '');
      });
      await mouseClick(
        tester,
        find.text('InitA.json'),
        buttons: kSecondaryMouseButton,
      );
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'InitA1.json');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/InitA1.json');
      expect(outlinedRows(tester), isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/InitA1.json');
      expect(outlinedRows(tester), ['InitA1.json']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(outlinedRows(tester), ['DualFilter.json']);
      final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await hover.addPointer(
        location: tester.getCenter(find.text('InitA1.json')),
      );
      await hover.moveTo(
        tester.getCenter(find.text('InitA1.json')) + const Offset(2, 0),
      );
      await tester.pump();
      expect(outlinedRows(tester), isEmpty);
      await hover.removePointer();
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'unselected context cursor follows a verified rename instead of falling back to the selected or first row',
    (tester) async {
      files['/A'] = [
        entry('first.json'),
        entry('middle.json'),
        entry('selected.json'),
      ];
      await mount(tester);
      await mouseClick(tester, find.text('A'));
      await mouseClick(tester, find.text('selected.json'));
      await mouseClick(
        tester,
        find.text('middle.json'),
        buttons: kSecondaryMouseButton,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      when(
        () => manager.requestFileRename('/A/middle.json', '/A/renamed.json'),
      ).thenAnswer((_) async {
        files['/A']![1] = entry('renamed.json');
        return SdCardStatus(success: true, message: '');
      });
      await cubit.renameEntry('/A/middle.json', 'renamed.json');
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/selected.json');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.getSelectedPath(), '/A/renamed.json');
      expect(outlinedRows(tester), ['renamed.json']);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'one mouse click in an unfocused stale column survives a focus refresh and row reorder between pointer down and up',
    (tester) async {
      await mount(tester);
      await mouseClick(tester, find.text('A'));
      now = now.add(const Duration(seconds: 6));
      reads.clear();
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('child')),
        kind: PointerDeviceKind.mouse,
      );
      await started.future;
      await tester.pump();
      response.complete(
        DirectoryListing(entries: [entry('aaa/', dir: true), ...files['/A']!]),
      );
      await tester.pump();
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(
        reads,
        contains('/A/child'),
      ); // No double-tap timeout or second click.
      await gesture.removePointer();
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/A', '/A/child']);
      expect(cubit.state.selectedCenterItem!.name, 'child/');
      expect(outlinedRows(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'rapid ordinary sibling clicks honor latest intent while pending and never publish blank or mislabeled destination columns',
    (tester) async {
      await mount(tester);
      final rects = geometry(tester);
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      await mouseClick(tester, find.text('A'));
      await started.future;
      expect(paths(tester), ['/', '', '']);
      expect(cubit.state.view!.pendingPath, '/A');
      await mouseClick(tester, find.text('B'));
      expect(paths(tester), ['/', '/B', '']);
      expect(find.text('B.json'), findsOneWidget);
      response.complete(DirectoryListing(entries: files['/A']!));
      await tester.pumpAndSettle();
      expect(paths(tester), ['/', '/B', '']);
      expect(find.text('B.json'), findsOneWidget);
      expect(geometry(tester), rects);
      expect(outlinedRows(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'held cascade navigation publishes path and contents in one frame without background-only real columns',
    (tester) async {
      await mount(tester);
      await tap(tester, 0, 'A');
      await tap(tester, 1, 'child');
      final rects = geometry(tester);
      final prior = paths(tester);
      final started = Completer<void>();
      final response = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A/child/deep')).thenAnswer((
        _,
      ) {
        started.complete();
        return response.future;
      });
      final frames = <BrowserSnapshot>[];
      final subscription = cubit.stream.listen((state) {
        if (state.view != null) frames.add(state.view!);
      });
      await mouseClick(tester, find.text('deep'));
      expect(
        started.isCompleted,
        isTrue,
        reason:
            'reads=$reads paths=${paths(tester)} pending=${cubit.state.view!.pendingPath}',
      );
      await started.future;
      expect(paths(tester), prior);
      expect(find.text('two.json'), findsOneWidget);
      expect(geometry(tester), rects);
      response.complete(DirectoryListing(entries: files['/A/child/deep']!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(paths(tester), ['/A', '/A/child', '/A/child/deep']);
      expect(find.text('three.json'), findsOneWidget);
      for (final frame in frames) {
        for (final position in PanelPosition.values) {
          if (frame.path(position) != null) {
            expect(frame.items(position), isNotEmpty);
          }
        }
      }
      expect(geometry(tester), rects);
      await tester.pumpAndSettle();
      addTearDown(subscription.cancel);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'folder rename keeps descendant list state and contents through every verification frame with no post-frame scroll correction',
    (tester) async {
      await mount(tester);
      await cubit.navigateToAbsolutePath('/A/child/deep');
      await tester.pumpAndSettle();
      final rects = geometry(tester);
      final scrollBefore = tester.state(
        find.descendant(of: pane(2), matching: find.byType(Scrollable)),
      );
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(() => manager.requestFileRename('/A/child', '/A/Live')).thenAnswer((
        _,
      ) async {
        files['/A']![0] = entry('Live/', dir: true);
        for (final path
            in files.keys
                .where(
                  (path) => path == '/A/child' || path.startsWith('/A/child/'),
                )
                .toList()) {
          files['/A/Live${path.substring('/A/child'.length)}'] = files.remove(
            path,
          )!;
        }
        return SdCardStatus(success: true, message: '');
      });
      when(() => manager.requestDirectoryListing('/A/Live/deep')).thenAnswer((
        _,
      ) {
        started.complete();
        return response.future;
      });
      final frames = <BrowserSnapshot>[];
      final subscription = cubit.stream.listen((state) {
        if (state.view != null) frames.add(state.view!);
      });
      final rename = cubit.renameEntry('/A/child', 'Live');
      await started.future;
      await tester.pump();
      expect(paths(tester), ['/A', '/A/Live', '/A/Live/deep']);
      expect(find.text('two.json'), findsOneWidget);
      expect(find.text('three.json'), findsOneWidget);
      expect(
        tester.state(
          find.descendant(of: pane(2), matching: find.byType(Scrollable)),
        ),
        same(scrollBefore),
      );
      expect(cubit.isDirectoryReady('/A/Live/deep'), isFalse);
      expect(geometry(tester), rects);
      response.complete(DirectoryListing(entries: files['/A/Live/deep']!));
      await rename;
      await tester.pumpAndSettle();
      for (final frame in frames) {
        for (final position in PanelPosition.values) {
          if (frame.path(position) != null) {
            expect(frame.items(position), isNotEmpty);
          }
        }
      }
      expect(geometry(tester), rects);
      addTearDown(subscription.cancel);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
  for (final scenario in [
    (column: 0, item: null, directory: '/A'),
    (column: 1, item: null, directory: '/A/child'),
    (column: 2, item: null, directory: '/A/child/deep'),
    (column: 0, item: 'child', directory: '/A/child'),
    (column: 0, item: 'one.json', directory: '/A'),
    (column: 2, item: 'four', directory: '/A/child/deep/four'),
  ]) {
    testWidgets(
      'context New Folder targets ${scenario.directory} from shifted column ${scenario.column} item ${scenario.item}, regardless of action focus',
      (tester) async {
        await mount(tester);
        await cubit.navigateToAbsolutePath('/A/child/deep');
        await tester.pumpAndSettle();
        final rects = geometry(tester);
        final created = <String>[];
        when(() => manager.requestDirectoryCreate(any())).thenAnswer((
          call,
        ) async {
          final path = call.positionalArguments.single as String;
          created.add(path);
          files[scenario.directory]!.add(entry('helper/', dir: true));
          return SdCardStatus(success: true, message: '');
        });
        expect(cubit.getCurrentDirectory(), '/A/child/deep');
        if (scenario.item == null) {
          await backgroundMenu(tester, scenario.column);
        } else {
          await tester.tap(
            find.descendant(
              of: pane(scenario.column),
              matching: find.text(scenario.item!),
            ),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('Refresh'), findsOneWidget);
        expect(
          tester.widget<PopupMenuItem>(menuItem('New Folder')).enabled,
          isTrue,
        );
        // A context operation belongs to its captured source, not a later focus.
        await cubit.focusPane(PanelPosition.right);
        await tester.pumpAndSettle();
        await tester.tap(find.text('New Folder'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'helper');
        await tester.tap(find.widgetWithText(TextButton, 'Create'));
        await tester.pumpAndSettle();
        expect(created, ['${scenario.directory}/helper']);
        expect(find.byType(SnackBar), findsNothing);
        expect(geometry(tester), rects);
        expect(paths(tester), ['/A', '/A/child', '/A/child/deep']);
        expect(tester.takeException(), isNull);
      },
      tags: ['regression'],
    );
  }

  testWidgets(
    'context New Folder is disabled while the clicked column or its ancestor is refreshing or uncertain; Refresh remains available',
    (tester) async {
      await mount(tester);
      await cubit.navigateToAbsolutePath('/A/child/deep');
      await tester.pumpAndSettle();
      final rects = geometry(tester);
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final refresh = cubit.refreshDirectory('/A');
      await started.future;
      await tester.pump();
      await backgroundMenu(tester, 0);
      expect(
        tester.widget<PopupMenuItem>(menuItem('New Folder')).enabled,
        isFalse,
      );
      expect(tester.widget<PopupMenuItem>(menuItem('Refresh')).enabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      response.completeError(StateError('Unavailable'));
      await refresh;
      await tester.pumpAndSettle();
      await backgroundMenu(tester, 2);
      expect(
        tester.widget<PopupMenuItem>(menuItem('New Folder')).enabled,
        isFalse,
      );
      expect(tester.widget<PopupMenuItem>(menuItem('Refresh')).enabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      verifyNever(() => manager.requestDirectoryCreate(any()));
      expect(geometry(tester), rects);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );

  testWidgets(
    'New Folder confirmation cannot create into a captured target whose ancestor becomes uncertain while typing',
    (tester) async {
      await mount(tester);
      await cubit.navigateToAbsolutePath('/A/child/deep');
      await tester.pumpAndSettle();
      final rects = geometry(tester);
      await backgroundMenu(tester, 1);
      await tester.tap(find.text('New Folder'));
      await tester.pumpAndSettle();
      final response = Completer<DirectoryListing?>();
      final started = Completer<void>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return response.future;
      });
      final refresh = cubit.refreshDirectory('/A');
      await started.future;
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'helper');
      await tester.tap(find.widgetWithText(TextButton, 'Create'));
      await tester.pumpAndSettle();
      verifyNever(() => manager.requestDirectoryCreate(any()));
      response.complete(DirectoryListing(entries: files['/A']!));
      await refresh;
      await tester.pumpAndSettle();
      expect(geometry(tester), rects);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
    tags: ['regression'],
  );
}
