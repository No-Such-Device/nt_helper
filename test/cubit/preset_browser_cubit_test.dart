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

DirectoryEntry file(String name, {bool directory = false, int date = 0}) =>
    DirectoryEntry(
      name: name,
      attributes: directory ? 0x10 : 0,
      date: date,
      time: 0,
      size: 0,
    );

void main() {
  late PresetBrowserCubit cubit;
  late _Manager manager;
  late SharedPreferences prefs;
  late Map<String, List<DirectoryEntry>> files;
  late List<String> requests;
  late DateTime now;
  BrowserSnapshot view() => cubit.state.view!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime(2026);
    manager = _Manager();
    files = {
      '/': [file('A/', directory: true), file('B/', directory: true)],
      '/A': [file('one.json'), file('child/', directory: true)],
      '/A/child': [file('deep.json')],
      '/B': [file('two.json')],
    };
    requests = [];
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final path = call.positionalArguments.single as String;
      requests.add(path);
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

  group('independent pane stacks', () {
    test('initializes three real panes with one root request', () async {
      expect(cubit.state, const PresetBrowserState.initial());
      await cubit.loadRootDirectory();
      expect(requests, ['/']);
      for (final panel in PanelPosition.values) {
        expect(view().pane(panel).stack.map((f) => f.path), ['/']);
        expect(view().items(panel).map((e) => e.name), ['A/', 'B/']);
      }
    });

    test('root failure exposes the cause in the retry view', () async {
      when(
        () => manager.requestDirectoryListing('/'),
      ).thenThrow(StateError('Unavailable'));
      await cubit.loadRootDirectory();
      expect(
        cubit.state.mapOrNull(error: (error) => error.message),
        contains('Unavailable'),
      );
      expect(cubit.state.mapOrNull(error: (error) => error.lastPath), '/');
      expect(cubit.getSelectedPath(), isEmpty);
    }, tags: ['regression']);

    test(
      'enter, select and back affect only their own pane stack',
      () async {
        await cubit.loadRootDirectory();
        await cubit.selectDirectory(files['/']!.first, PanelPosition.left);
        await cubit.selectFile(files['/A']!.first, PanelPosition.left);
        await cubit.selectDirectory(files['/']!.last, PanelPosition.center);
        await cubit.selectFile(files['/B']!.single, PanelPosition.center);
        await cubit.navigateToAbsolutePath(
          '/A/child',
          panel: PanelPosition.right,
        );
        expect(view().pane(PanelPosition.left).stack.map((f) => f.path), [
          '/',
          '/A',
        ]);
        expect(view().pane(PanelPosition.center).stack.map((f) => f.path), [
          '/',
          '/B',
        ]);
        expect(view().pane(PanelPosition.right).stack.map((f) => f.path), [
          '/',
          '/A/child',
        ]);
        expect(
          cubit.getSelectedPath(),
          isEmpty,
        ); // Active right pane has no selection.
        await cubit.focusPane(PanelPosition.center);
        expect(cubit.getSelectedPath(), '/B/two.json');
        await cubit.navigateBack(PanelPosition.left);
        expect(cubit.getPanelDirectory(PanelPosition.left), '/');
        expect(cubit.getPanelDirectory(PanelPosition.center), '/B');
        expect(cubit.getPanelDirectory(PanelPosition.right), '/A/child');
        expect(view().selection(PanelPosition.center)!.name, 'two.json');
        await cubit.navigateBack(PanelPosition.left); // Root is bounded.
        expect(view().pane(PanelPosition.left).stack, hasLength(1));
      },
      tags: ['regression'],
    );

    test(
      'mobile uses the active pane, including root breadcrumb and back',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/B', panel: PanelPosition.right);
        await cubit.selectDrillItem(files['/B']!.single);
        expect(cubit.state.selectedRightItem, cubit.state.selectedDrillItem);
        expect(cubit.getSelectedPath(), '/B/two.json');
        await cubit.focusPane(PanelPosition.left);
        expect(cubit.getSelectedPath(), isEmpty);
        await cubit.navigateIntoDirectory(files['/']!.first);
        await cubit.navigateIntoDirectory(files['/A']!.last);
        expect(cubit.state.breadcrumbs, ['A', 'child']);
        await cubit.navigateToPathSegment(0);
        expect(cubit.getCurrentDirectory(), '/A');
        await cubit.navigateToPathSegment(-1);
        expect(cubit.getCurrentDirectory(), '/');
        expect(cubit.getPanelDirectory(PanelPosition.right), '/B');
        await cubit.focusPane(PanelPosition.right);
        expect(cubit.getSelectedPath(), '/B/two.json');
      },
      tags: ['regression'],
    );

    test(
      'restores saved path only in first pane and retains bounded root',
      () async {
        await prefs.setString('fileBrowserLastPath', '/A/child');
        await cubit.loadRootDirectory();
        expect(cubit.getCurrentDirectory(), '/A/child');
        expect(cubit.getPanelDirectory(PanelPosition.center), '/');
        expect(cubit.getPanelDirectory(PanelPosition.right), '/');
        await cubit.navigateBack();
        expect(cubit.getCurrentDirectory(), '/');
      },
    );

    test('missing saved directory falls back to fresh root', () async {
      await prefs.setString('fileBrowserLastPath', '/missing');
      await cubit.loadRootDirectory();
      expect(cubit.getCurrentDirectory(), '/');
      expect(view().active.stack, hasLength(1));
    });
  });

  group('event-driven freshness', () {
    test(
      'revisiting/back reads external changes instead of cached entries',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        await cubit.selectFile(files['/A']!.first, PanelPosition.left);
        await cubit.navigateIntoDirectory(files['/A']!.last);
        files['/A'] = [file('renamed #42.json')];
        await cubit.navigateBack();
        expect(requests.where((path) => path == '/A'), hasLength(2));
        expect(
          view().items(PanelPosition.left).single.name,
          'renamed #42.json',
        );
        expect(
          cubit.getSelectedPath(),
          isEmpty,
        ); // Vanished selection is cleared.
      },
      tags: ['regression'],
    );

    test(
      'focus/resume coalesce shared paths and do not poll or reread fresh data',
      () async {
        await cubit.loadRootDirectory();
        await cubit.focusPane(PanelPosition.center);
        await cubit.focusPane(PanelPosition.left);
        await cubit.refreshVisiblePanes(onlyIfStale: true);
        expect(requests, ['/']);
        now = now.add(const Duration(seconds: 6));
        final started = Completer<void>();
        final response = Completer<DirectoryListing?>();
        when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
          requests.add('/');
          started.complete();
          return response.future;
        });
        final first = cubit.focusPane(PanelPosition.left);
        await started.future;
        final second = cubit.focusPane(PanelPosition.right);
        response.complete(DirectoryListing(entries: [file('external.json')]));
        await Future.wait([first, second]);
        expect(requests, ['/', '/']);
        for (final panel in PanelPosition.values) {
          expect(view().items(panel).single.name, 'external.json');
        }
      },
      tags: ['regression'],
    );

    test(
      'delayed navigation reply cannot restore a pane after back',
      () async {
        await cubit.loadRootDirectory();
        final started = Completer<void>();
        final response = Completer<DirectoryListing?>();
        when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
          started.complete();
          return response.future;
        });
        final enter = cubit.navigateToAbsolutePath('/A');
        await started.future;
        await cubit.navigateBack();
        response.complete(DirectoryListing(entries: files['/A']!));
        await enter;
        expect(cubit.getCurrentDirectory(), '/');
        expect(view().active.stack, hasLength(1));
      },
      tags: ['regression'],
    );

    test(
      'mutation invalidation rejects an older in-flight listing',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        final started = Completer<void>();
        final stale = Completer<DirectoryListing?>();
        var reads = 0;
        when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
          if (reads++ == 0) {
            started.complete();
            return stale.future;
          }
          return Future.value(DirectoryListing(entries: files['/A']!));
        });
        when(
          () => manager.requestFileRename('/A/one.json', '/A/one #42.json'),
        ).thenAnswer((_) async {
          files['/A'] = [file('one #42.json')];
          return SdCardStatus(success: true, message: '');
        });
        final refresh = cubit.refreshPane();
        await started.future;
        await cubit.renameEntry('/A/one.json', 'one #42.json');
        stale.complete(DirectoryListing(entries: [file('one.json')]));
        await refresh;
        expect(view().items(PanelPosition.left).single.name, 'one #42.json');
        expect(view().refreshing, isEmpty);
        expect(
          reads,
          2,
        ); // Only the stale refresh and verified rename read-back.
      },
      tags: ['regression'],
    );

    test(
      'all panes sharing a directory update after create/delete/upload',
      () async {
        await cubit.loadRootDirectory();
        for (final panel in PanelPosition.values) {
          await cubit.navigateToAbsolutePath('/A', panel: panel);
        }
        await cubit.selectFile(files['/A']!.first, PanelPosition.right);
        when(() => manager.requestDirectoryCreate('/A/new')).thenAnswer((
          _,
        ) async {
          files['/A']!.add(file('new/', directory: true));
          return SdCardStatus(success: true, message: '');
        });
        await cubit.createDirectory('/A', 'new');
        for (final panel in PanelPosition.values) {
          expect(
            view().items(panel).any((entry) => entry.name == 'new/'),
            isTrue,
          );
        }
        when(() => manager.requestFileDelete('/A/one.json')).thenAnswer((
          _,
        ) async {
          files['/A']!.removeWhere((e) => e.name == 'one.json');
          return SdCardStatus(success: true, message: '');
        });
        await cubit.deleteEntry('/A/one.json');
        expect(cubit.getSelectedPath(), isEmpty);
        when(
          () => manager.requestFileUploadChunk(
            '/A/new.json',
            any(),
            0,
            createAlways: true,
          ),
        ).thenAnswer((_) async {
          files['/A']!.add(file('new.json'));
          return SdCardStatus(success: true, message: '');
        });
        await cubit.uploadFile('/A', 'new.json', Uint8List.fromList([1]));
        for (final panel in PanelPosition.values) {
          expect(
            view().items(panel).any((entry) => entry.name == 'new.json'),
            isTrue,
          );
          expect(
            view().items(panel).any((entry) => entry.name == 'one.json'),
            isFalse,
          );
        }
      },
      tags: ['regression'],
    );

    test('fresh unrelated panes are not read after a mutation', () async {
      await cubit.loadRootDirectory();
      await cubit.navigateToAbsolutePath('/A');
      await cubit.navigateToAbsolutePath('/B', panel: PanelPosition.center);
      requests.clear();
      when(
        () => manager.requestDirectoryCreate('/A/new'),
      ).thenAnswer((_) async => SdCardStatus(success: true, message: ''));
      await cubit.createDirectory('/A', 'new');
      expect(requests, ['/A']);
      expect(cubit.getPanelDirectory(PanelPosition.center), '/B');
    }, tags: ['regression']);

    test(
      'failed mutation does not poison the queue and partial writes are revalidated',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        when(() => manager.requestDirectoryCreate('/A/denied')).thenAnswer(
          (_) async => SdCardStatus(success: false, message: 'Denied'),
        );
        await expectLater(
          cubit.createDirectory('/A', 'denied'),
          throwsStateError,
        );
        when(
          () => manager.requestFileUploadChunk(
            '/A/partial.json',
            any(),
            0,
            createAlways: true,
          ),
        ).thenAnswer((_) async {
          files['/A']!.add(file('partial.json'));
          throw StateError('Connection lost after write');
        });
        await expectLater(
          cubit.uploadFile('/A', 'partial.json', Uint8List.fromList([1])),
          throwsStateError,
        );
        expect(
          view().items(PanelPosition.left).any((e) => e.name == 'partial.json'),
          isTrue,
        );
        expect(view().refreshing, isEmpty);
        verify(() => manager.requestDirectoryCreate('/A/denied')).called(1);
        verify(
          () => manager.requestFileUploadChunk(
            '/A/partial.json',
            any(),
            0,
            createAlways: true,
          ),
        ).called(1);
      },
      tags: ['regression'],
    );

    test(
      'mutation workflows are serialized through verification',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        final started = Completer<void>();
        final reply = Completer<SdCardStatus?>();
        when(
          () => manager.requestFileRename('/A/one.json', '/A/first.json'),
        ).thenAnswer((_) {
          started.complete();
          return reply.future;
        });
        when(
          () => manager.requestFileRename('/A/first.json', '/A/second.json'),
        ).thenAnswer((_) async {
          files['/A'] = [file('second.json')];
          return SdCardStatus(success: true, message: '');
        });
        final first = cubit.renameEntry('/A/one.json', 'first.json');
        await started.future;
        final second = cubit.renameEntry('/A/first.json', 'second.json');
        verifyNever(
          () => manager.requestFileRename('/A/first.json', '/A/second.json'),
        );
        files['/A'] = [file('first.json')];
        reply.complete(SdCardStatus(success: true, message: ''));
        await Future.wait([first, second]);
        expect(view().items(PanelPosition.left).single.name, 'second.json');
      },
      tags: ['regression'],
    );

    test(
      'deleting an open folder pops only affected stacks and clears history',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        await cubit.navigateIntoDirectory(files['/A']!.last);
        await cubit.selectDrillItem(files['/A/child']!.single);
        await cubit.navigateToAbsolutePath('/B', panel: PanelPosition.center);
        when(() => manager.requestFileDelete('/A/child')).thenAnswer((_) async {
          files.remove('/A/child');
          files['/A']!.removeWhere((e) => e.name == 'child/');
          return SdCardStatus(success: true, message: '');
        });
        await cubit.deleteEntry('/A/child');
        expect(cubit.getPanelDirectory(PanelPosition.left), '/A');
        expect(cubit.getPanelDirectory(PanelPosition.center), '/B');
        expect(cubit.getPanelDirectory(PanelPosition.right), '/');
        expect(await cubit.loadRecentPresets(), isEmpty);
        expect(
          view().items(PanelPosition.left).any((e) => e.name == 'child/'),
          isFalse,
        );
      },
      tags: ['regression'],
    );

    test(
      'uncertain rename disables only its directory and preserves other panes',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/A');
        await cubit.selectFile(files['/A']!.first, PanelPosition.left);
        await cubit.navigateToAbsolutePath('/B', panel: PanelPosition.right);
        await cubit.selectFile(files['/B']!.single, PanelPosition.right);
        when(
          () => manager.requestFileRename('/A/one.json', '/A/new.json'),
        ).thenAnswer((_) async => null);
        await expectLater(
          cubit.renameEntry('/A/one.json', 'new.json'),
          throwsStateError,
        );
        expect(cubit.getSelectedPath(), '/B/two.json');
        expect(view().errors['/A'], contains('not acknowledged'));
        await cubit.focusPane(
          PanelPosition.left,
        ); // Fresh listing resolves uncertainty.
        expect(cubit.getPanelDirectory(PanelPosition.left), '/A');
        expect(cubit.getSelectedPath(), '/A/one.json');
        expect(cubit.getPanelDirectory(PanelPosition.right), '/B');
      },
      tags: ['regression'],
    );

    test(
      'failed refresh disables stale selection and can retry without moving panes',
      () async {
        await cubit.loadRootDirectory();
        await cubit.navigateToAbsolutePath('/B');
        await cubit.selectFile(files['/B']!.single, PanelPosition.left);
        when(
          () => manager.requestDirectoryListing('/B'),
        ).thenThrow(StateError('Unavailable'));
        await cubit.refreshPane();
        expect(cubit.getSelectedPath(), isEmpty);
        expect(view().errors['/B'], contains('Unavailable'));
        expect(cubit.getCurrentDirectory(), '/B');
        when(
          () => manager.requestDirectoryListing('/B'),
        ).thenAnswer((_) async => DirectoryListing(entries: files['/B']!));
        await cubit.refreshPane();
        expect(view().errors, isEmpty);
        expect(cubit.getSelectedPath(), '/B/two.json');
      },
      tags: ['regression'],
    );
  });

  test('sorting updates shared listings without MIDI traffic', () async {
    files['/'] = [file('old.json'), file('recent.json', date: 1)];
    await cubit.loadRootDirectory();
    cubit.toggleSortMode();
    expect(view().items(PanelPosition.left).first.name, 'recent.json');
    expect(prefs.getBool('fileBrowserSortByDate'), isTrue);
    expect(requests, ['/']);
  });

  test('recent history deduplicates and is bounded', () async {
    for (var i = 0; i < 25; i++) {
      await cubit.addToHistory('/$i.json');
    }
    await cubit.addToHistory('/23.json');
    expect(await cubit.loadRecentPresets(), hasLength(20));
    expect((await cubit.loadRecentPresets()).first, '/23.json');
  });

  setUpAll(() => registerFallbackValue(Uint8List(0)));
}
