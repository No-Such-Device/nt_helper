import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';

class MockIDistingMidiManager extends Mock implements IDistingMidiManager {}

DirectoryEntry _file(String name) =>
    DirectoryEntry(name: name, attributes: 0x20, date: 0, time: 0, size: 0);

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: '$name/', attributes: 0x10, date: 0, time: 0, size: 0);

void main() {
  late MockIDistingMidiManager mockManager;
  late PresetFileSystemImpl fileSystem;

  setUp(() {
    mockManager = MockIDistingMidiManager();
    fileSystem = PresetFileSystemImpl(mockManager);
  });

  group('PresetFileSystemImpl.listFiles', () {
    test(
      'returns empty list when requestDirectoryListing returns null',
      () async {
        when(
          () => mockManager.requestDirectoryListing(any()),
        ).thenAnswer((_) async => null);

        final result = await fileSystem.listFiles('samples');

        expect(result, isEmpty);
      },
    );

    test('returns empty list for empty directory', () async {
      when(
        () => mockManager.requestDirectoryListing('samples'),
      ).thenAnswer((_) async => DirectoryListing(entries: []));

      final result = await fileSystem.listFiles('samples');

      expect(result, isEmpty);
    });

    test('returns full paths for files in root directory', () async {
      when(() => mockManager.requestDirectoryListing('samples')).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('kick.wav'), _file('snare.wav')]),
      );

      final result = await fileSystem.listFiles('samples');

      expect(result, ['samples/kick.wav', 'samples/snare.wav']);
    });

    test('root path does not introduce duplicate separators', () async {
      when(
        () => mockManager.requestDirectoryListing('/'),
      ).thenAnswer((_) async => DirectoryListing(entries: [_dir('samples')]));
      when(
        () => mockManager.requestDirectoryListing('/samples'),
      ).thenAnswer((_) async => DirectoryListing(entries: [_file('kick.wav')]));

      final result = await fileSystem.listFiles('/', recursive: true);

      expect(result, ['/samples/kick.wav']);
    });

    test('non-recursive does not descend into subdirectories', () async {
      when(() => mockManager.requestDirectoryListing('samples')).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('kick.wav'), _dir('Drums')]),
      );

      final result = await fileSystem.listFiles('samples', recursive: false);

      expect(result, ['samples/kick.wav']);
      verify(() => mockManager.requestDirectoryListing('samples')).called(1);
      verifyNever(() => mockManager.requestDirectoryListing('samples/Drums'));
    });

    test('recursive descends into subdirectories with full paths', () async {
      when(() => mockManager.requestDirectoryListing('samples')).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('root.wav'), _dir('Drums')]),
      );
      when(
        () => mockManager.requestDirectoryListing('samples/Drums'),
      ).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('kick.wav'), _file('snare.wav')]),
      );

      final result = await fileSystem.listFiles('samples', recursive: true);

      expect(
        result,
        unorderedEquals([
          'samples/root.wav',
          'samples/Drums/kick.wav',
          'samples/Drums/snare.wav',
        ]),
      );
    });

    test('recursive handles nested subdirectories', () async {
      when(
        () => mockManager.requestDirectoryListing('samples'),
      ).thenAnswer((_) async => DirectoryListing(entries: [_dir('A')]));
      when(
        () => mockManager.requestDirectoryListing('samples/A'),
      ).thenAnswer((_) async => DirectoryListing(entries: [_dir('B')]));
      when(
        () => mockManager.requestDirectoryListing('samples/A/B'),
      ).thenAnswer((_) async => DirectoryListing(entries: [_file('deep.wav')]));

      final result = await fileSystem.listFiles('samples', recursive: true);

      expect(result, ['samples/A/B/deep.wav']);
    });

    test(
      'strips trailing slash from directory names in path construction',
      () async {
        // Hardware appends '/' to directory names; ensure path is constructed correctly
        when(() => mockManager.requestDirectoryListing('samples')).thenAnswer(
          (_) async => DirectoryListing(
            entries: [
              _dir('Drums'), // stored as 'Drums/' by hardware
            ],
          ),
        );
        when(
          () => mockManager.requestDirectoryListing('samples/Drums'),
        ).thenAnswer(
          (_) async => DirectoryListing(entries: [_file('kick.wav')]),
        );

        final result = await fileSystem.listFiles('samples', recursive: true);

        // Should be 'samples/Drums/kick.wav' not 'samples/Drums//kick.wav'
        expect(result, ['samples/Drums/kick.wav']);
      },
    tags: ['regression']);

    test('directories are not included in file results', () async {
      when(() => mockManager.requestDirectoryListing('samples')).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_dir('Drums'), _file('top.wav')]),
      );

      final result = await fileSystem.listFiles('samples', recursive: false);

      expect(result, ['samples/top.wav']);
      expect(result, isNot(contains('samples/Drums')));
      expect(result, isNot(contains('samples/Drums/')));
    });
  });
}
