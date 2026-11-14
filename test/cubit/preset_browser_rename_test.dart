import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MidiManager extends Mock implements IDistingMidiManager {}

DirectoryEntry _entry(String name, {bool directory = false}) => DirectoryEntry(
  name: name,
  attributes: directory ? 0x10 : 0,
  date: 0,
  time: 0,
  size: 0,
);

void main() {
  late _MidiManager manager;
  late PresetBrowserCubit cubit;
  late SharedPreferences prefs;
  late Map<String, List<DirectoryEntry>> files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    manager = _MidiManager();
    files = {
      '/': [_entry('presets/', directory: true)],
      '/presets': [_entry('Alpha.json'), _entry('Beta.json')],
    };
    when(() => manager.requestDirectoryListing(any())).thenAnswer((call) async {
      final entries = files[call.positionalArguments.single];
      return entries == null
          ? null
          : DirectoryListing(entries: List.of(entries));
    });
    when(() => manager.requestFileRename(any(), any())).thenAnswer((
      call,
    ) async {
      final oldPath = call.positionalArguments[0] as String;
      final newPath = call.positionalArguments[1] as String;
      final parent = oldPath.lastIndexOf('/') == 0
          ? '/'
          : oldPath.substring(0, oldPath.lastIndexOf('/'));
      final oldName = oldPath.split('/').last;
      final entries = files[parent]!;
      final index = entries.indexWhere((e) => e.name == oldName);
      if (index < 0) return SdCardStatus(success: false, message: 'Not found');
      entries[index] = _entry(newPath.split('/').last);
      return SdCardStatus(success: true, message: '');
    });
    cubit = PresetBrowserCubit(midiManager: manager, prefs: prefs);
    await cubit.loadRootDirectory();
    await cubit.navigateToAbsolutePath('/presets');
    clearInteractions(manager);
  });

  tearDown(() => cubit.close());

  group('browser rename consistency', () {
    test(
      'device rejection is not reported as a successful rename',
      () async {
        when(() => manager.requestFileRename(any(), any())).thenAnswer(
          (_) async =>
              SdCardStatus(success: false, message: 'Destination exists'),
        );
        await expectLater(
          cubit.renameEntry('/presets/Alpha.json', 'Alpha #42.json'),
          throwsA(
            predicate((e) => e.toString().contains('Destination exists')),
          ),
        );
        verify(() => manager.requestFileRename(any(), any())).called(1);
        expect(files['/presets']!.first.name, 'Alpha.json');
      },
      tags: ['regression'],
    );

    test(
      'renaming #n presets updates desktop, mobile, cache and recents',
      () async {
        await cubit.selectDrillItem(files['/presets']!.first);
        await cubit.addToHistory('/presets/Alpha.json');
        await cubit.renameEntry('/presets/Alpha.json', 'Alpha #42.json');

        expect(cubit.getSelectedPath(), '/presets/Alpha #42.json');
        cubit.state.mapOrNull(
          loaded: (s) {
            expect(s.centerPanelItems.map((e) => e.name), [
              'Alpha #42.json',
              'Beta.json',
            ]);
            expect(s.currentDrillItems!.map((e) => e.name), [
              'Alpha #42.json',
              'Beta.json',
            ]);
            expect(s.selectedDrillItem!.name, 'Alpha #42.json');
            expect(s.directoryCache!['/presets']!.map((e) => e.name), [
              'Alpha #42.json',
              'Beta.json',
            ]);
          },
        );
        expect(await cubit.loadRecentPresets(), ['/presets/Alpha #42.json']);

        // A second rename must use the fresh filename, not a retained UI/cache entry.
        await cubit.renameEntry(cubit.getSelectedPath(), 'Alpha #7.json');
        expect(cubit.getSelectedPath(), '/presets/Alpha #7.json');
        expect(await cubit.loadRecentPresets(), ['/presets/Alpha #7.json']);
        await cubit.navigateToAbsolutePath('/presets');
        cubit.state.mapOrNull(
          loaded: (s) {
            expect(s.currentDrillItems!.map((e) => e.name), [
              'Alpha #7.json',
              'Beta.json',
            ]);
            expect(
              s.currentDrillItems!.any((e) => e.name == 'Alpha.json'),
              isFalse,
            );
          },
        );
        // No host-side PC lookup exists. These are the on-card filenames the
        // documented firmware #n/fallback resolver consumes, not a firmware emulation.
        expect(files['/presets']!.map((e) => e.name), [
          'Alpha #7.json',
          'Beta.json',
        ]);
        verifyNever(() => manager.requestSetPresetName(any()));
        verifyNever(() => manager.requestRemountSd());
      },
      tags: ['regression'],
    );

    test(
      'renumbering multiple presets never retains old #n browser entries',
      () async {
        for (final (before, after) in [
          ('Alpha.json', 'Alpha #42.json'),
          ('Beta.json', 'Beta #7.json'),
          ('Alpha #42.json', 'Alpha #3.json'),
          ('Beta #7.json', 'Beta #42.json'),
        ]) {
          final entry = cubit.state.mapOrNull(
            loaded: (s) =>
                s.currentDrillItems!.singleWhere((e) => e.name == before),
          )!;
          await cubit.selectDrillItem(entry);
          await cubit.renameEntry(cubit.getSelectedPath(), after);
          expect(cubit.getSelectedPath(), '/presets/$after');
        }
        cubit.state.mapOrNull(
          loaded: (s) {
            for (final entries in [
              s.centerPanelItems,
              s.currentDrillItems!,
              s.directoryCache!['/presets']!,
            ]) {
              expect(entries.map((e) => e.name), [
                'Alpha #3.json',
                'Beta #42.json',
              ]);
            }
          },
        );
        expect(await cubit.loadRecentPresets(), [
          '/presets/Beta #42.json',
          '/presets/Alpha #3.json',
        ]);
      },
      tags: ['regression'],
    );

    test(
      'firmware exception is propagated without replaying a rename',
      () async {
        const error = SdCardOperationException(
          operation: SdCardOperation.fileRename,
          message: 'Denied',
        );
        when(() => manager.requestFileRename(any(), any())).thenThrow(error);
        await expectLater(
          cubit.renameEntry('/presets/Alpha.json', 'Alpha #42.json'),
          throwsA(same(error)),
        );
        verify(() => manager.requestFileRename(any(), any())).called(1);
        // Even an uncertain outcome must evict cached directory data.
        await cubit.navigateToAbsolutePath('/presets');
        verify(() => manager.requestDirectoryListing('/presets')).called(2);
      },
      tags: ['regression'],
    );

    for (final panel in PanelPosition.values) {
      test(
        'keeps the renamed file selected in the $panel panel',
        () async {
          var directory = '/presets';
          if (panel == PanelPosition.left) {
            files['/']!.add(_entry('Alpha.json'));
            await cubit.navigateToAbsolutePath('/');
            directory = '/';
          } else if (panel == PanelPosition.right) {
            files['/presets']!.add(_entry('Set/', directory: true));
            files['/presets/Set'] = [_entry('Alpha.json')];
            await cubit.navigateToAbsolutePath('/presets/Set');
            directory = '/presets/Set';
          }
          await cubit.selectFile(
            files[directory]!.firstWhere((e) => e.name == 'Alpha.json'),
            panel,
          );
          await cubit.renameEntry(
            directory == '/' ? '/Alpha.json' : '$directory/Alpha.json',
            'Alpha #42.json',
          );
          expect(
            cubit.getSelectedPath(),
            directory == '/' ? '/Alpha #42.json' : '$directory/Alpha #42.json',
          );
        },
        tags: ['regression'],
      );
    }

    test(
      'folder rename invalidates descendants and rewrites remembered paths',
      () async {
        files['/presets'] = [
          _entry('Set/', directory: true),
          _entry('Setup/', directory: true),
        ];
        files['/presets/Set'] = [_entry('Alpha #42.json')];
        files['/presets/Setup'] = [_entry('Other.json')];
        await cubit.navigateToAbsolutePath('/presets/Setup');
        await cubit.navigateToAbsolutePath('/presets/Set');
        await cubit.selectDrillItem(files['/presets/Set']!.single);
        await cubit.addToHistory('/presets/Set/Alpha #42.json');
        await cubit.addToHistory('/presets/Setup/Other.json');
        when(
          () => manager.requestFileRename('/presets/Set', '/presets/Live'),
        ).thenAnswer((_) async {
          files['/presets']![0] = _entry('Live/', directory: true);
          files['/presets/Live'] = files.remove('/presets/Set')!;
          return SdCardStatus(success: true, message: '');
        });
        await cubit.renameEntry('/presets/Set', 'Live');
        expect(cubit.getCurrentDirectory(), '/presets/Live');
        expect(cubit.getSelectedPath(), '/presets/Live/Alpha #42.json');
        expect(prefs.getString('fileBrowserLastPath'), '/presets/Live');
        expect(await cubit.loadRecentPresets(), [
          '/presets/Setup/Other.json',
          '/presets/Live/Alpha #42.json',
        ]);
        cubit.state.mapOrNull(
          loaded: (s) {
            expect(s.directoryCache!.containsKey('/presets/Set'), isFalse);
            expect(s.directoryCache!.containsKey('/presets/Setup'), isTrue);
            expect(s.breadcrumbs, ['presets', 'Live']);
          },
        );
        await cubit.navigateToAbsolutePath('/');
        await cubit.navigateToAbsolutePath('/presets/Live');
        verify(
          () => manager.requestDirectoryListing('/presets/Live'),
        ).called(2);
      },
      tags: ['regression'],
    );

    test(
      'requires read-back evidence instead of trusting an unchanged listing',
      () async {
        await cubit.selectFile(files['/presets']!.first, PanelPosition.center);
        expect(cubit.getSelectedPath(), '/presets/Alpha.json');
        when(
          () => manager.requestFileRename(any(), any()),
        ).thenAnswer((_) async => SdCardStatus(success: true, message: ''));
        await expectLater(
          cubit.renameEntry('/presets/Alpha.json', 'Alpha #42.json'),
          throwsA(isA<StateError>()),
        );
        expect(await cubit.loadRecentPresets(), ['/presets/Alpha.json']);
        expect(cubit.getSelectedPath(), isEmpty);
        expect(
          cubit.state.view!.errors['/presets'],
          contains('could not be verified'),
        );
      },
      tags: ['regression'],
    );

    test('missing acknowledgement is not blindly retried', () async {
      when(
        () => manager.requestFileRename(any(), any()),
      ).thenAnswer((_) async => null);
      await expectLater(
        cubit.renameEntry('/presets/Alpha.json', 'Alpha #42.json'),
        throwsA(isA<StateError>()),
      );
      verify(() => manager.requestFileRename(any(), any())).called(1);
    }, tags: ['regression']);

    test(
      'directory refresh does not restore navigation captured before await',
      () async {
        final listingStarted = Completer<void>();
        final listing = Completer<DirectoryListing?>();
        when(() => manager.requestDirectoryListing('/presets')).thenAnswer((_) {
          listingStarted.complete();
          return listing.future;
        });
        final rename = cubit.renameEntry(
          '/presets/Alpha.json',
          'Alpha #42.json',
        );
        await listingStarted.future;
        await cubit.navigateToAbsolutePath('/');
        listing.complete(DirectoryListing(entries: files['/presets']!));
        await rename;
        expect(cubit.getCurrentDirectory(), '/');
        cubit.state.mapOrNull(
          loaded: (s) {
            expect(s.selectedLeftItem!.name, 'presets/');
            expect(s.browser.path(PanelPosition.center), null);
            expect(s.centerPanelItems, isEmpty);
          },
        );
      },
      tags: ['regression'],
    );

    test(
      'invalid filename is rejected before the wire operation',
      () async {
        for (final name in [
          '',
          '.',
          '..',
          'folder/Alpha.json',
          'Alpha\u0000.json',
        ]) {
          await expectLater(
            cubit.renameEntry('/presets/Alpha.json', name),
            throwsArgumentError,
          );
        }
        verifyNever(() => manager.requestFileRename(any(), any()));
      },
      tags: ['regression'],
    );
  });
}
