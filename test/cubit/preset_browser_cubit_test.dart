import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Manager extends Mock implements IDistingMidiManager {}

DirectoryEntry entry(String name, {bool dir = false, int date = 0}) =>
    DirectoryEntry(
      name: name,
      attributes: dir ? 0x10 : 0,
      date: date,
      time: 0,
      size: 0,
    );

void main() {
  late PresetBrowserCubit cubit;
  late _Manager manager;
  late SharedPreferences prefs;
  late DateTime now;
  late List<String> reads;
  late Map<String, List<DirectoryEntry>> files;
  BrowserSnapshot view() => cubit.state.view!;
  List<String?> columns() => PanelPosition.values.map(view().path).toList();
  List<String> ancestry() => view().stack.map((f) => f.path).toList();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    manager = _Manager();
    now = DateTime(2026);
    reads = [];
    files = {
      '/': [entry('A/', dir: true), entry('B/', dir: true), entry('root.json')],
      '/A': [
        entry('child/', dir: true),
        entry('sibling/', dir: true),
        entry('one.json'),
      ],
      '/A/child': [entry('deep/', dir: true), entry('two.json')],
      '/A/child/deep': [entry('four/', dir: true), entry('three.json')],
      '/A/child/deep/four': [entry('four.json')],
      '/A/sibling': [],
      '/B': [entry('B.json')],
    };
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final path = call.positionalArguments.single as String;
      reads.add(path);
      final entries = files[path];
      return entries == null ? null : DirectoryListing(entries: [...entries]);
    });
    cubit = PresetBrowserCubit(
      midiManager: manager,
      prefs: prefs,
      clock: Clock(() => now),
    );
  });
  tearDown(() => cubit.close());

  group('one hierarchy and exactly three projected columns', () {
    test(
      'root, child and grandchild fill left then center then right with no independent roots',
      () async {
        expect(cubit.state, const PresetBrowserState.initial());
        await cubit.loadRootDirectory();
        expect(columns(), ['/', null, null]);
        expect(reads, ['/']);
        expect(view().items(PanelPosition.center), isEmpty);
        await cubit.focusPane(PanelPosition.right);
        expect(reads, ['/']);
        expect(cubit.getPanelDirectory(PanelPosition.right), '');
        await cubit.selectDirectory(files['/']!.first, PanelPosition.left);
        expect(columns(), ['/', '/A', null]);
        expect(view().selection(PanelPosition.left)!.name, 'A/');
        await cubit.selectDirectory(files['/A']!.first, PanelPosition.center);
        expect(columns(), ['/', '/A', '/A/child']);
        expect(view().selection(PanelPosition.center)!.name, 'child/');
        await cubit.selectFile(files['/A/child']!.last, PanelPosition.right);
        expect(cubit.getSelectedPath(), '/A/child/two.json');
      },
      tags: ['regression'],
    );

    test(
      'fourth and deeper levels shift a fixed three-column viewport while retaining offscreen ancestry',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child/deep');
        expect(columns(), ['/A', '/A/child', '/A/child/deep']);
        expect(ancestry(), ['/', '/A', '/A/child', '/A/child/deep']);
        expect(view().stack[0].selectedName, 'A/');
        await cubit.selectDirectory(
          files['/A/child/deep']!.first,
          PanelPosition.right,
        );
        expect(columns(), ['/A/child', '/A/child/deep', '/A/child/deep/four']);
        expect(ancestry(), [
          '/',
          '/A',
          '/A/child',
          '/A/child/deep',
          '/A/child/deep/four',
        ]);
        await cubit.navigateBack();
        expect(columns(), ['/A', '/A/child', '/A/child/deep']);
        await cubit.navigateBack();
        expect(columns(), ['/', '/A', '/A/child']);
        await cubit.navigateToPathSegment(0);
        expect(columns(), ['/', '/A', null]);
        await cubit.navigateToPathSegment(-1);
        expect(columns(), ['/', null, null]);
        await cubit.navigateBack();
        expect(ancestry(), ['/']);
        expect(cubit.state.breadcrumbs, isEmpty);
      },
      tags: ['regression'],
    );

    test(
      'sibling folder or file selection truncates descendants and action targets',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child/deep');
        await cubit.selectFile(
          files['/A/child/deep']!.last,
          PanelPosition.right,
        );
        await cubit.selectDirectory(files['/A']![1], PanelPosition.left);
        expect(ancestry(), ['/', '/A', '/A/sibling']);
        expect(columns(), ['/', '/A', '/A/sibling']);
        expect(cubit.getSelectedPath(), isEmpty);
        expect(view().selection(PanelPosition.center)!.name, 'sibling/');
        await cubit.selectFile(files['/']!.last, PanelPosition.left);
        expect(columns(), ['/', null, null]);
        expect(cubit.getSelectedPath(), '/root.json');
        await cubit.selectDirectory(files['/']![1], PanelPosition.left);
        expect(columns(), ['/', '/B', null]);
        expect(cubit.getSelectedPath(), isEmpty);
      },
      tags: ['regression'],
    );

    test(
      'Back preserves parent folder highlight without reentering it; breadcrumbs are ancestry, not visit history',
      () async {
        await prefs.setString('fileBrowserLastPath', '/A/child/deep');
        await cubit.loadRootDirectory();
        expect(ancestry(), ['/', '/A', '/A/child', '/A/child/deep']);
        await cubit.navigateBack();
        expect(view().current.path, '/A/child');
        expect(view().selection(PanelPosition.right)!.name, 'deep/');
        await cubit.navigateToAbsolutePath('/B');
        expect(ancestry(), ['/', '/B']);
        await cubit.navigateBack();
        expect(ancestry(), ['/']);
        await cubit.navigateToAbsolutePath('/A/child');
        await cubit.navigateToPathSegment(0);
        expect(ancestry(), ['/', '/A']); // Never [/, /A/child, /A].
      },
      tags: ['regression'],
    );

    test(
      'mobile renders the deepest shared frame; focus does not fork navigation or persist an ancestor root',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child');
        await cubit.selectDrillItem(files['/A/child']!.last);
        expect(
          cubit.state.selectedDrillItem,
          view().selection(PanelPosition.right),
        );
        expect(cubit.getSelectedPath(), '/A/child/two.json');
        await cubit.focusPane(PanelPosition.left);
        expect(ancestry(), ['/', '/A', '/A/child']);
        expect(
          cubit.state.currentDrillItems,
          view().items(PanelPosition.right),
        );
        expect(prefs.getString('fileBrowserLastPath'), '/A/child');
        cubit.setSinglePaneLayout(true);
        reads.clear();
        now = now.add(const Duration(seconds: 6));
        await cubit.refreshVisiblePanes(onlyIfStale: true);
        expect(reads, ['/A/child']);
      },
      tags: ['regression'],
    );
  });

  group('freshness and mutation protections survive shared hierarchy', () {
    test(
      'Back rereads external changes, clears vanished selection, and refresh truncates obsolete descendant branch',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child/deep');
        files['/A/child'] = [entry('new.json')];
        await cubit.navigateBack();
        expect(view().selection(PanelPosition.right), isNull);
        expect(view().current.path, '/A/child');
        expect(view().items(PanelPosition.right).single.name, 'new.json');
        files['/A'] = [entry('one.json')];
        await cubit.refreshPane(PanelPosition.center);
        expect(ancestry(), ['/', '/A']);
        expect(columns(), ['/', '/A', null]);
      },
      tags: ['regression'],
    );

    test(
      'stale focus coalesces and fresh focus/placeholder produces no reads or polling',
      () async {
        await cubit.loadRootDirectory();
        await cubit.focusPane(PanelPosition.left);
        await cubit.focusPane(PanelPosition.center);
        await cubit.refreshVisiblePanes(onlyIfStale: true);
        expect(reads, ['/']);
        now = now.add(const Duration(seconds: 6));
        final started = Completer<void>();
        final reply = Completer<DirectoryListing?>();
        when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
          reads.add('/');
          started.complete();
          return reply.future;
        });
        final first = cubit.focusPane(PanelPosition.left);
        await started.future;
        final second = cubit.focusPane(PanelPosition.left);
        reply.complete(DirectoryListing(entries: files['/']!));
        await Future.wait([first, second]);
        expect(reads, ['/', '/']);
      },
      tags: ['regression'],
    );

    test(
      'late reply cannot restore navigation after Back or sibling replacement',
      () async {
        await cubit.loadRootDirectory();
        final started = Completer<void>();
        final reply = Completer<DirectoryListing?>();
        when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
          started.complete();
          return reply.future;
        });
        final enter = cubit.selectDirectory(
          files['/']!.first,
          PanelPosition.left,
        );
        await started.future;
        await cubit.selectDirectory(files['/']![1], PanelPosition.left);
        reply.complete(DirectoryListing(entries: files['/A']!));
        await enter;
        expect(ancestry(), ['/', '/B']);
        expect(view().selection(PanelPosition.left)!.name, 'B/');
      },
      tags: ['regression'],
    );

    test(
      'older in-flight read cannot overwrite verified rename',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        final started = Completer<void>();
        final reply = Completer<DirectoryListing?>();
        var count = 0;
        when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
          if (count++ == 0) {
            started.complete();
            return reply.future;
          }
          return Future.value(DirectoryListing(entries: files['/A']!));
        });
        when(
          () => manager.requestFileRename('/A/one.json', '/A/one #42.json'),
        ).thenAnswer((_) async {
          files['/A'] = [entry('one #42.json')];
          return SdCardStatus(success: true, message: '');
        });
        final refresh = cubit.refreshPane();
        await started.future;
        await cubit.renameEntry('/A/one.json', 'one #42.json');
        reply.complete(DirectoryListing(entries: [entry('one.json')]));
        await refresh;
        expect(view().items(PanelPosition.center).single.name, 'one #42.json');
        expect(count, 2);
      },
      tags: ['regression'],
    );

    test(
      'folder rename rebases entire ancestry and refreshed parent selection without losing viewport',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child/deep');
        await cubit.selectFile(
          files['/A/child/deep']!.last,
          PanelPosition.right,
        );
        when(() => manager.requestFileRename('/A', '/Live')).thenAnswer((
          _,
        ) async {
          files['/']![0] = entry('Live/', dir: true);
          for (final path
              in files.keys
                  .where((p) => p == '/A' || p.startsWith('/A/'))
                  .toList()) {
            files['/Live${path.substring(2)}'] = files.remove(path)!;
          }
          return SdCardStatus(success: true, message: '');
        });
        await cubit.renameEntry('/A', 'Live');
        expect(ancestry(), ['/', '/Live', '/Live/child', '/Live/child/deep']);
        expect(columns(), ['/Live', '/Live/child', '/Live/child/deep']);
        expect(cubit.getSelectedPath(), '/Live/child/deep/three.json');
        expect(await cubit.loadRecentPresets(), [
          '/Live/child/deep/three.json',
        ]);
        expect(prefs.getString('fileBrowserLastPath'), '/Live/child/deep');
        expect(
          view().listings.keys.any((p) => p == '/A' || p.startsWith('/A/')),
          isFalse,
        );
        await cubit.navigateBack();
        expect(view().current.path, '/Live/child');
      },
      tags: ['regression'],
    );

    test(
      'delete pops vanished subtree to surviving ancestor and invalidates recent path',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A/child');
        await cubit.selectDrillItem(files['/A/child']!.last);
        when(() => manager.requestFileDelete('/A/child')).thenAnswer((_) async {
          files['/A']!.removeAt(0);
          files.remove('/A/child');
          return SdCardStatus(success: true, message: '');
        });
        await cubit.deleteEntry('/A/child');
        expect(ancestry(), ['/', '/A']);
        expect(await cubit.loadRecentPresets(), isEmpty);
      },
      tags: ['regression'],
    );

    test(
      'create delete upload refresh only affected current listing and serialize mutation workflows',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        reads.clear();
        when(() => manager.requestDirectoryCreate('/A/new')).thenAnswer((
          _,
        ) async {
          files['/A']!.add(entry('new/', dir: true));
          return SdCardStatus(success: true, message: '');
        });
        await cubit.createDirectory('/A', 'new');
        expect(reads, ['/A']);
        when(() => manager.requestFileDelete('/A/one.json')).thenAnswer((
          _,
        ) async {
          files['/A']!.removeWhere((e) => e.name == 'one.json');
          return SdCardStatus(success: true, message: '');
        });
        await cubit.deleteEntry('/A/one.json');
        expect(
          view().items(PanelPosition.center).any((e) => e.name == 'one.json'),
          isFalse,
        );
        when(
          () => manager.requestFileUploadChunk(
            '/A/new.json',
            any(),
            0,
            createAlways: true,
          ),
        ).thenAnswer((_) async {
          files['/A']!.add(entry('new.json'));
          return SdCardStatus(success: true, message: '');
        });
        await cubit.uploadFile('/A', 'new.json', Uint8List.fromList([1]));
        expect(
          view().items(PanelPosition.center).any((e) => e.name == 'new.json'),
          isTrue,
        );
        final started = Completer<void>();
        final ack = Completer<SdCardStatus?>();
        when(
          () => manager.requestFileRename('/A/new.json', '/A/first.json'),
        ).thenAnswer((_) {
          started.complete();
          return ack.future;
        });
        when(
          () => manager.requestFileRename('/A/first.json', '/A/second.json'),
        ).thenAnswer((_) async {
          files['/A']!.removeWhere((e) => e.name == 'first.json');
          files['/A']!.add(entry('second.json'));
          return SdCardStatus(success: true, message: '');
        });
        final first = cubit.renameEntry('/A/new.json', 'first.json');
        await started.future;
        final second = cubit.renameEntry('/A/first.json', 'second.json');
        verifyNever(
          () => manager.requestFileRename('/A/first.json', '/A/second.json'),
        );
        files['/A']!.removeWhere((e) => e.name == 'new.json');
        files['/A']!.add(entry('first.json'));
        ack.complete(SdCardStatus(success: true, message: ''));
        await Future.wait([first, second]);
        expect(
          view()
              .items(PanelPosition.center)
              .any((e) => e.name == 'second.json'),
          isTrue,
        );
      },
      tags: ['regression'],
    );

    test(
      'failed mutation does not poison queue; partial writes and failed refresh reconcile safely',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        when(() => manager.requestDirectoryCreate('/A/no')).thenAnswer(
          (_) async => SdCardStatus(success: false, message: 'Denied'),
        );
        await expectLater(cubit.createDirectory('/A', 'no'), throwsStateError);
        when(
          () => manager.requestFileUploadChunk(
            '/A/partial.json',
            any(),
            0,
            createAlways: true,
          ),
        ).thenAnswer((_) async {
          files['/A']!.add(entry('partial.json'));
          throw StateError('Lost reply');
        });
        await expectLater(
          cubit.uploadFile('/A', 'partial.json', Uint8List(1)),
          throwsStateError,
        );
        expect(
          view()
              .items(PanelPosition.center)
              .any((e) => e.name == 'partial.json'),
          isTrue,
        );
        await cubit.selectFile(
          files['/A']!.firstWhere((e) => e.name == 'one.json'),
          PanelPosition.center,
        );
        when(
          () => manager.requestDirectoryListing('/A'),
        ).thenThrow(StateError('Unavailable'));
        await cubit.refreshPane();
        expect(cubit.getSelectedPath(), isEmpty);
        when(
          () => manager.requestDirectoryListing('/A'),
        ).thenAnswer((_) async => DirectoryListing(entries: files['/A']!));
        await cubit.refreshPane();
        expect(cubit.getSelectedPath(), '/A/one.json');
      },
      tags: ['regression'],
    );
  });
  test(
    'sort and bounded deduplicated recents retain no-MIDI preference behavior',
    () async {
      files['/'] = [entry('old.json'), entry('recent.json', date: 1)];
      await cubit.loadRootDirectory();
      cubit.toggleSortMode();
      expect(view().items(PanelPosition.left).first.name, 'recent.json');
      expect(reads, ['/']);
      for (var i = 0; i < 25; i++) {
        await cubit.addToHistory('/$i.json');
      }
      await cubit.addToHistory('/23.json');
      expect(await cubit.loadRecentPresets(), hasLength(20));
      expect((await cubit.loadRecentPresets()).first, '/23.json');
    },
  );
}
