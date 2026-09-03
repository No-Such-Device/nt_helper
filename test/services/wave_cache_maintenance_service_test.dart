import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/wave_cache_maintenance_service.dart';

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

DirectoryEntry _file(String name) =>
    DirectoryEntry(name: name, attributes: 0x20, date: 0, time: 0, size: 0);

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: '$name/', attributes: 0x10, date: 0, time: 0, size: 0);

void main() {
  late _MockDistingMidiManager manager;
  late WaveCacheMaintenanceService service;

  setUp(() {
    manager = _MockDistingMidiManager();
    service = WaveCacheMaintenanceService(manager);
    when(() => manager.requestWake()).thenAnswer((_) async {});
  });

  void stubListings(Map<String, List<DirectoryEntry>> entriesByPath) {
    when(() => manager.requestDirectoryListing(any())).thenAnswer((invocation) {
      final path = invocation.positionalArguments.single as String;
      return Future.value(
        DirectoryListing(entries: entriesByPath[path] ?? const []),
      );
    });
  }

  test('findAll finds the canonical distingNT.wavcache filename', () async {
    stubListings({
      '/': [_file('distingNT.wavcache')],
    });

    final plan = await service.findAll();

    expect(plan.cachePaths, ['/distingNT.wavcache']);
  });

  test('finds only the cache beside a matching WAV filename', () async {
    stubListings({
      '/': [_dir('samples')],
      '/samples': [_dir('Future Music CD1'), _dir('Other')],
      '/samples/Future Music CD1': [
        _file('distingNT.wavcache'),
        _file('FM1 - Track 44.wav'),
        _file('FM1 - Track 43.wav'),
      ],
      '/samples/Other': [_file('distingNT.wavcache'), _file('Track 45.wav')],
    });

    final plan = await service.findForSampleFragment('track 44');

    expect(plan.matchedSamplePaths, [
      '/samples/Future Music CD1/FM1 - Track 44.wav',
    ]);
    expect(plan.cachePaths, ['/samples/Future Music CD1/distingNT.wavcache']);
    expect(plan.directoriesWithoutCache, isEmpty);
    verify(() => manager.requestWake()).called(1);
  });

  test(
    'matches filename fragments case-insensitively and deduplicates cache',
    () async {
      stubListings({
        '/': [_dir('samples')],
        '/samples': [_dir('Kit')],
        '/samples/Kit': [
          _file('DISTINGnt.WAVCACHE'),
          _file('Kick Loud.WAV'),
          _file('Kick Soft.wav'),
        ],
      });

      final plan = await service.findForSampleFragment('KICK');

      expect(plan.matchedSamplePaths, hasLength(2));
      expect(plan.cachePaths, ['/samples/Kit/DISTINGnt.WAVCACHE']);
    },
  );

  test(
    'reports matching sample directories that have no visible cache',
    () async {
      stubListings({
        '/': [_dir('samples')],
        '/samples': [_dir('Piano')],
        '/samples/Piano': [_file('Grand C4.wav')],
      });

      final plan = await service.findForSampleFragment('Grand C4');

      expect(plan.cachePaths, isEmpty);
      expect(plan.directoriesWithoutCache, ['/samples/Piano']);
    },
  );

  test('findAll returns every exact cache basename across the card', () async {
    stubListings({
      '/': [_file('distingNT.wavcache'), _dir('samples'), _dir('programs')],
      '/samples': [_dir('Kit')],
      '/samples/Kit': [_file('DISTINGNT.WAVCACHE'), _file('kick.wav')],
      '/programs': [_file('not-distingNT.wavcache')],
    });

    final plan = await service.findAll();

    expect(plan.isGlobal, true);
    expect(plan.cachePaths, [
      '/distingNT.wavcache',
      '/samples/Kit/DISTINGNT.WAVCACHE',
    ]);
  });

  test('rejects an empty sample fragment before scanning', () async {
    expect(() => service.findForSampleFragment('  '), throwsArgumentError);
    verifyNever(() => manager.requestWake());
  });

  test(
    'deletes planned caches and remounts after at least one success',
    () async {
      const plan = WaveCacheCleanupPlan(
        sampleFragment: 'kick',
        matchedSamplePaths: ['/samples/Kit/kick.wav'],
        cachePaths: [
          '/samples/Kit/distingNT.wavcache',
          '/samples/Other/distingNT.wavcache',
        ],
        directoriesWithoutCache: [],
      );
      when(
        () => manager.requestFileDelete('/samples/Kit/distingNT.wavcache'),
      ).thenAnswer(
        (_) async => SdCardStatus(success: true, message: 'Deleted'),
      );
      when(
        () => manager.requestFileDelete('/samples/Other/distingNT.wavcache'),
      ).thenAnswer(
        (_) async => SdCardStatus(success: false, message: 'Read only'),
      );
      when(() => manager.requestRemountSd()).thenAnswer((_) async {});

      final result = await service.deleteAndRemount(plan);

      expect(result.deletedCachePaths, ['/samples/Kit/distingNT.wavcache']);
      expect(
        result.failedCachePaths['/samples/Other/distingNT.wavcache'],
        'Read only',
      );
      expect(result.remountRequested, true);
      verify(() => manager.requestRemountSd()).called(1);
    },
  );

  test('does not remount when no cache deletion succeeds', () async {
    const plan = WaveCacheCleanupPlan(
      sampleFragment: null,
      matchedSamplePaths: [],
      cachePaths: ['/samples/Kit/distingNT.wavcache'],
      directoriesWithoutCache: [],
    );
    when(
      () => manager.requestFileDelete(any()),
    ).thenThrow(StateError('Device disconnected'));

    final result = await service.deleteAndRemount(plan);

    expect(result.deletedCachePaths, isEmpty);
    expect(result.failedCachePaths, hasLength(1));
    expect(result.remountRequested, false);
    verifyNever(() => manager.requestRemountSd());
  });

  test('reports a remount failure after deleting the cache', () async {
    const plan = WaveCacheCleanupPlan(
      sampleFragment: null,
      matchedSamplePaths: [],
      cachePaths: ['/samples/Kit/distingNT.wavcache'],
      directoriesWithoutCache: [],
    );
    when(
      () => manager.requestFileDelete(any()),
    ).thenAnswer((_) async => SdCardStatus(success: true, message: 'Deleted'));
    when(
      () => manager.requestRemountSd(),
    ).thenThrow(StateError('MIDI output closed'));

    final result = await service.deleteAndRemount(plan);

    expect(result.deletedCachePaths, hasLength(1));
    expect(result.remountRequested, false);
    expect(result.remountError, contains('MIDI output closed'));
  });
}
