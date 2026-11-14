import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sd_card_file_activity.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Manager extends Mock implements IDistingMidiManager {}

class _Prefs extends Mock implements SharedPreferences {}

DirectoryEntry entry(String name, {bool dir = false, int size = 0}) =>
    DirectoryEntry(
      name: name,
      attributes: dir ? 0x10 : 0,
      date: 0,
      time: 0,
      size: size,
    );

void main() {
  late _Manager manager;
  late SharedPreferences prefs;
  late PresetBrowserCubit cubit;
  late Map<String, List<DirectoryEntry>> files;
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    manager = _Manager();
    files = {
      '/': [entry('A/', dir: true), entry('B/', dir: true)],
      '/A': [entry('one.json'), entry('child/', dir: true)],
      '/A/child': [entry('deep.json')],
      '/B': [entry('two.json')],
    };
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final data = files[call.positionalArguments.single];
      return data == null ? null : DirectoryListing(entries: [...data]);
    });
    when(
      () => manager.requestFileRename('/A/one.json', '/A/new.json'),
    ).thenAnswer((_) async {
      files['/A']![0] = entry('new.json');
      return SdCardStatus(success: true, message: '');
    });
    cubit = PresetBrowserCubit(midiManager: manager, prefs: prefs);
  });
  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  test(
    'startup captures saved location before root pane focus can overwrite preferences',
    () async {
      await prefs.setString('fileBrowserLastPath', '/A');
      final started = Completer<void>();
      final reply = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/')).thenAnswer((_) {
        started.complete();
        return reply.future;
      });
      final startup = cubit.loadRootDirectory();
      await started.future;
      final focus = cubit.focusPane(PanelPosition.center);
      expect(prefs.getString('fileBrowserLastPath'), '/A');
      reply.complete(DirectoryListing(entries: files['/']!));
      await Future.wait([startup, focus]);
      expect(cubit.getPanelDirectory(PanelPosition.center), '/A');
      expect(cubit.getCurrentDirectory(), '/A');
    },
    tags: ['regression'],
  );

  test(
    'failed restoration cannot reset newer shared navigation',
    () async {
      await prefs.setString('fileBrowserLastPath', '/missing');
      final started = Completer<void>();
      final reply = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/missing')).thenAnswer((_) {
        started.complete();
        return reply.future;
      });
      final startup = cubit.loadRootDirectory();
      await started.future;
      await cubit.navigateToAbsolutePath('/B');
      reply.complete(null);
      await startup;
      expect(cubit.getCurrentDirectory(), '/B');
      expect(cubit.state.view!.stack.map((f) => f.path), ['/', '/B']);
    },
    tags: ['regression'],
  );

  test(
    'deleting an old stack frame preserves a surviving current location',
    () async {
      await cubit.loadRootDirectory();
      await cubit.navigateToAbsolutePath('/A/child');
      await cubit.navigateToPathSegment(0);
      expect(cubit.state.view!.stack.map((f) => f.path), ['/', '/A']);
      when(() => manager.requestFileDelete('/A/child')).thenAnswer((_) async {
        files['/A']!.removeWhere((e) => e.name == 'child/');
        return SdCardStatus(success: true, message: '');
      });
      await cubit.deleteEntry('/A/child');
      expect(cubit.state.view!.stack.map((f) => f.path), ['/', '/A']);
      expect(cubit.getCurrentDirectory(), '/A');
    },
    tags: ['regression'],
  );

  test(
    'rename verification retains stale content with pending feedback and atomically rebases selection',
    () async {
      await cubit.loadRootDirectory();
      await cubit.navigateToAbsolutePath('/A');
      await cubit.selectFile(files['/A']!.first, PanelPosition.center);
      final started = Completer<void>();
      final reply = Completer<DirectoryListing?>();
      when(() => manager.requestDirectoryListing('/A')).thenAnswer((_) {
        started.complete();
        return reply.future;
      });
      final rename = cubit.renameEntry('/A/one.json', 'new.json');
      await started.future;
      expect(cubit.state.view!.refreshing, contains('/A'));
      expect(
        cubit.state.view!.items(PanelPosition.center).map((e) => e.name),
        contains('one.json'),
      );
      expect(cubit.getSelectedPath(), isEmpty);
      final focus = cubit
          .refreshPane(); // Coalesces with verification, not a competing publish.
      reply.complete(DirectoryListing(entries: files['/A']!));
      await Future.wait([rename, focus]);
      expect(cubit.getSelectedPath(), '/A/new.json');
    },
    tags: ['regression'],
  );

  test(
    'slow failing preferences cannot overwrite newer refresh or undo a verified rename',
    () async {
      await cubit.close();
      final storage = _Prefs();
      when(() => storage.getBool(any())).thenReturn(false);
      when(() => storage.getString(any())).thenReturn(null);
      when(() => storage.getStringList(any())).thenReturn(['/A/one.json']);
      when(() => storage.setString(any(), any())).thenAnswer((_) async => true);
      final started = Completer<void>();
      final persisted = Completer<bool>();
      var delay = false;
      when(() => storage.setStringList(any(), any())).thenAnswer((_) async {
        if (!delay) return true;
        started.complete();
        return persisted.future;
      });
      cubit = PresetBrowserCubit(midiManager: manager, prefs: storage);
      await cubit.loadRootDirectory();
      await cubit.navigateToAbsolutePath('/A');
      await cubit.selectFile(files['/A']!.first, PanelPosition.center);
      delay = true;
      final rename = cubit.renameEntry('/A/one.json', 'new.json');
      await started.future;
      expect(
        cubit.state.view!.selection(PanelPosition.center)!.name,
        'new.json',
      );
      files['/A']!.add(entry('external.json'));
      await cubit.refreshPane();
      persisted.complete(false);
      await rename; // Device rename still succeeds.
      expect(cubit.getSelectedPath(), '/A/new.json');
      expect(
        cubit.state.view!.items(PanelPosition.center).map((e) => e.name),
        contains('external.json'),
      );
      expect(cubit.state.view!.warning, contains('Renamed on the device'));
    },
    tags: ['regression'],
  );

  test(
    'an upload lease survives browser disposal and blocks reopened load/export/delete',
    () async {
      await cubit.loadRootDirectory();
      await cubit.navigateToAbsolutePath('/A');
      await cubit.selectFile(files['/A']!.first, PanelPosition.center);
      final started = Completer<void>();
      final acknowledgement = Completer<SdCardStatus?>();
      when(
        () => manager.requestFileUploadChunk(
          '/A/one.json',
          any(),
          0,
          createAlways: true,
        ),
      ).thenAnswer((_) {
        started.complete();
        return acknowledgement.future;
      });
      final upload = cubit.uploadFile(
        '/A',
        'one.json',
        Uint8List.fromList([1]),
      );
      await started.future;
      expect(cubit.getSelectedPath(), isEmpty);
      expect(cubit.state.view!.busyPaths, contains('/a/one.json'));
      await cubit.close();
      final reopened = PresetBrowserCubit(midiManager: manager, prefs: prefs);
      try {
        await reopened.loadRootDirectory();
        await reopened.navigateToAbsolutePath('/A');
        await reopened.selectFile(files['/A']!.first, PanelPosition.center);
        expect(reopened.getSelectedPath(), isEmpty);
        expect(
          () => PresetFileSystemImpl(manager).readFile('/A/one.json'),
          throwsA(isA<SdCardFileBusyException>()),
        );
        await expectLater(
          reopened.deleteEntry('/A/one.json'),
          throwsA(isA<SdCardFileBusyException>()),
        );
        verifyNever(() => manager.requestFileDelete(any()));
        files['/A']![0] = entry('one.json', size: 1);
        acknowledgement.complete(SdCardStatus(success: true, message: ''));
        await upload;
        await reopened.refreshPane();
        expect(reopened.getSelectedPath(), '/A/one.json');
        expect(reopened.state.view!.selection(PanelPosition.center)!.size, 1);
      } finally {
        await reopened.close();
      }
    },
    tags: ['regression'],
  );
}
