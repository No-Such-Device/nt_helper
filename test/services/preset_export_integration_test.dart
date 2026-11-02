// End-to-end integration test for preset export.
//
// Drives a real [PresetAnalyzer] + [FileCollector] + [PackageCreator]
// against a fake [PresetFileSystem] backed by an in-memory map. Verifies
// that, given a preset JSON whose dependencies all exist on the (fake)
// SD card, the resulting `.zip` contains every referenced sample,
// wavetable, Lua script, FM bank, and so on at the canonical SD path.
//
// This is the regression guard against silently producing JSON-only
// packages: if any dependency type stops being collected, the unzip
// path-set check below fails.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/interfaces/preset_file_system.dart';
import 'package:nt_helper/models/package_config.dart';
import 'package:nt_helper/services/file_collector.dart';
import 'package:nt_helper/services/package_creator.dart';

/// In-memory fake of [PresetFileSystem] driven by a map of relative path
/// to bytes. Directory listings are derived from the map's keyspace.
class _FakeFileSystem implements PresetFileSystem {
  final Map<String, Uint8List> store;

  _FakeFileSystem(this.store);

  @override
  Future<Uint8List?> readFile(String relativePath) async {
    return store[relativePath];
  }

  @override
  Future<List<String>> listFiles(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final prefix = directoryPath.endsWith('/')
        ? directoryPath
        : '$directoryPath/';
    return store.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<List<FileEntryInfo>> listEntries(
    String directoryPath, {
    bool recursive = false,
  }) async {
    final paths = await listFiles(directoryPath, recursive: recursive);
    return [
      for (final p in paths)
        FileEntryInfo(path: p, size: store[p]?.length ?? 0),
    ];
  }

  @override
  Future<int?> getFileSize(String relativePath) async {
    return store[relativePath]?.length;
  }
}

void main() {
  test(
    'SyncLatchDemo round-trip captures lua + samp triggers + pyms folder',
    () async {
      final presetJson = File(
        'test/fixtures/presets/sync_latch_demo.json',
      ).readAsStringSync();
      final presetBytes = Uint8List.fromList(utf8.encode(presetJson));

      // Lay out the fake SD card with every file the preset references.
      final lua = Uint8List.fromList(utf8.encode('-- lua content'));
      final wav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]); // "RIFF"
      final aif = Uint8List.fromList([0x46, 0x4F, 0x52, 0x4D]); // "FORM"

      final fs = _FakeFileSystem({
        'presets/SyncLatchDemo.json': presetBytes,
        'programs/lua/sync_latch.lua': lua,
        // samp triggers
        'samples/Cheetah_MD16/MD16_BD_Gated_1.wav': wav,
        'samples/DMX606_SamplePack/DMX606_SD1_A.wav': wav,
        'samples/DMX606_SamplePack/DMX606_HHclosed_A.wav': wav,
        'samples/!LABS Soft Pno - PedOn/PedOn_A#-1.wav': wav,
        // pyms multisample folder content (recursively listed)
        'multisamples/LABS Soft Pno - PedOn/A1.aif': aif,
        'multisamples/LABS Soft Pno - PedOn/C2.aif': aif,
      });

      final creator = PackageCreator(fs);
      final result = await creator.createPackage(
        presetFilePath: 'presets/SyncLatchDemo.json',
        config: const PackageConfig(),
      );

      // Decode the zip and check the file list.
      final archive = ZipDecoder().decodeBytes(result.zipBytes);
      final names = archive.files.map((f) => f.name).toSet();

      expect(names, contains('root/presets/SyncLatchDemo.json'));
      expect(names, contains('root/programs/lua/sync_latch.lua'));
      expect(names, contains('root/samples/Cheetah_MD16/MD16_BD_Gated_1.wav'));
      expect(
        names,
        contains('root/samples/DMX606_SamplePack/DMX606_SD1_A.wav'),
      );
      expect(
        names,
        contains('root/samples/!LABS Soft Pno - PedOn/PedOn_A#-1.wav'),
      );
      expect(names, contains('root/multisamples/LABS Soft Pno - PedOn/A1.aif'));
      expect(names, contains('manifest.json'));

      // Manifest should report the lua and trigger samples in the
      // included-files list (proving they were actually packaged).
      final manifestEntry = archive.files.firstWhere(
        (f) => f.name == 'manifest.json',
      );
      final manifest =
          jsonDecode(utf8.decode(manifestEntry.content as List<int>))
              as Map<String, dynamic>;
      final included = (manifest['package']['includedFiles'] as List)
          .cast<String>();
      expect(included, contains('programs/lua/sync_latch.lua'));
      expect(included, contains('samples/Cheetah_MD16/MD16_BD_Gated_1.wav'));

      // No warnings since every referenced file exists in the fake FS.
      expect(result.warnings, isEmpty);
    },
  );

  test('missing dependencies produce warnings but still write a zip', () async {
    // Same preset, but the SD card is empty except for the preset itself.
    final presetJson = File(
      'test/fixtures/presets/sync_latch_demo.json',
    ).readAsStringSync();
    final presetBytes = Uint8List.fromList(utf8.encode(presetJson));

    final fs = _FakeFileSystem({'presets/SyncLatchDemo.json': presetBytes});

    final creator = PackageCreator(fs);
    final result = await creator.createPackage(
      presetFilePath: 'presets/SyncLatchDemo.json',
      config: const PackageConfig(),
    );

    expect(result.zipBytes, isNotEmpty);
    expect(result.hasWarnings, isTrue);

    // Warnings should mention the missing Lua script and at least one
    // missing sample so the user sees what's incomplete.
    expect(result.warnings.any((w) => w.contains('sync_latch.lua')), isTrue);
    expect(
      result.warnings.any((w) => w.contains('MD16_BD_Gated_1.wav')),
      isTrue,
    );
  });

  test(
    '<MULTISAMPLE> trigger bundles whole folder, not a literal file',
    () async {
      // Synthetic preset: a single `samp` slot whose first trigger uses the
      // firmware token `<MULTISAMPLE>`. The destination NT picks a file
      // from the folder at runtime, so we need the entire folder to ship.
      final preset = {
        'name': 'MultiSampleDemo',
        'slots': [
          {
            'guid': 'samp',
            'triggers': [
              {'folder': 'MD16_Kit', 'sample': '<MULTISAMPLE>'},
              // Second trigger explicitly references one file in the same
              // folder. After the dedup guard, the zip should still
              // contain each file exactly once.
              {'folder': 'MD16_Kit', 'sample': 'MD16_BD.wav'},
            ],
          },
        ],
      };
      final presetBytes = Uint8List.fromList(utf8.encode(jsonEncode(preset)));
      final wav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);

      final fs = _FakeFileSystem({
        'presets/MultiSampleDemo.json': presetBytes,
        'samples/MD16_Kit/MD16_BD.wav': wav,
        'samples/MD16_Kit/MD16_SD.wav': wav,
        'samples/MD16_Kit/MD16_HH.wav': wav,
      });

      final creator = PackageCreator(fs);
      final result = await creator.createPackage(
        presetFilePath: 'presets/MultiSampleDemo.json',
        config: const PackageConfig(),
      );

      final archive = ZipDecoder().decodeBytes(result.zipBytes);
      final names = archive.files.map((f) => f.name).toList();

      // Every sibling file must travel with the preset.
      expect(names, contains('root/samples/MD16_Kit/MD16_BD.wav'));
      expect(names, contains('root/samples/MD16_Kit/MD16_SD.wav'));
      expect(names, contains('root/samples/MD16_Kit/MD16_HH.wav'));

      // Each file appears exactly once — the dedup guard prevents the
      // explicit-filename trigger from re-adding `MD16_BD.wav`.
      final bdEntries = names.where(
        (n) => n == 'root/samples/MD16_Kit/MD16_BD.wav',
      );
      expect(bdEntries.length, 1);

      // No warning should mention `<MULTISAMPLE>` as a missing file —
      // it's no longer treated as a filename.
      expect(result.warnings.any((w) => w.contains('<MULTISAMPLE>')), isFalse);
    },
  tags: ['regression']);

  test('midp slot bundles the whole MIDI tree', () async {
    final preset = {
      'name': 'MidiDemo',
      'slots': [
        {
          'guid': 'midp',
          'parameters': [0, 1, 1, 1, 0],
        },
      ],
    };
    final presetBytes = Uint8List.fromList(utf8.encode(jsonEncode(preset)));
    final mid = Uint8List.fromList([0x4D, 0x54, 0x68, 0x64]); // "MThd"

    final fs = _FakeFileSystem({
      'presets/MidiDemo.json': presetBytes,
      'MIDI/Demo/song1.mid': mid,
      'MIDI/Demo/song2.mid': mid,
      'MIDI/Other/groove.mid': mid,
    });

    final creator = PackageCreator(fs);
    final result = await creator.createPackage(
      presetFilePath: 'presets/MidiDemo.json',
      config: const PackageConfig(),
    );

    final names = ZipDecoder()
        .decodeBytes(result.zipBytes)
        .files
        .map((f) => f.name)
        .toSet();
    expect(names, contains('root/MIDI/Demo/song1.mid'));
    expect(names, contains('root/MIDI/Demo/song2.mid'));
    expect(names, contains('root/MIDI/Other/groove.mid'));
  });

  test('quan slot bundles scl and kbm trees', () async {
    final preset = {
      'name': 'ScaleDemo',
      'slots': [
        {
          'guid': 'quan',
          'parameters': [0],
        },
      ],
    };
    final presetBytes = Uint8List.fromList(utf8.encode(jsonEncode(preset)));

    final fs = _FakeFileSystem({
      'presets/ScaleDemo.json': presetBytes,
      'scl/12tone.scl': Uint8List.fromList(utf8.encode('! 12 tone')),
      'scl/Aeolian JI.scl': Uint8List.fromList(utf8.encode('! aeolian')),
      'kbm/standard.kbm': Uint8List.fromList(utf8.encode('0\n')),
    });

    final creator = PackageCreator(fs);
    final result = await creator.createPackage(
      presetFilePath: 'presets/ScaleDemo.json',
      config: const PackageConfig(),
    );

    final names = ZipDecoder()
        .decodeBytes(result.zipBytes)
        .files
        .map((f) => f.name)
        .toSet();
    expect(names, contains('root/scl/12tone.scl'));
    expect(names, contains('root/scl/Aeolian JI.scl'));
    expect(names, contains('root/kbm/standard.kbm'));
  });

  test('includeMidiTree=false skips the MIDI tree', () async {
    final preset = {
      'name': 'MidiOptOut',
      'slots': [
        {
          'guid': 'midp',
          'parameters': [0],
        },
      ],
    };
    final presetBytes = Uint8List.fromList(utf8.encode(jsonEncode(preset)));

    final fs = _FakeFileSystem({
      'presets/MidiOptOut.json': presetBytes,
      'MIDI/Demo/song1.mid': Uint8List.fromList([0x4D, 0x54, 0x68, 0x64]),
    });

    final creator = PackageCreator(fs);
    final result = await creator.createPackage(
      presetFilePath: 'presets/MidiOptOut.json',
      config: const PackageConfig(includeMidiTree: false),
    );

    final names = ZipDecoder()
        .decodeBytes(result.zipBytes)
        .files
        .map((f) => f.name)
        .toSet();
    expect(names.any((n) => n.startsWith('root/MIDI/')), isFalse);
  });

  test(
    'progress callback fires monotonically and ends at file total',
    () async {
      final presetJson = File(
        'test/fixtures/presets/sync_latch_demo.json',
      ).readAsStringSync();
      final presetBytes = Uint8List.fromList(utf8.encode(presetJson));
      final wav = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
      final aif = Uint8List.fromList([0x46, 0x4F, 0x52, 0x4D]);
      final lua = Uint8List.fromList(utf8.encode('-- lua content'));

      final fs = _FakeFileSystem({
        'presets/SyncLatchDemo.json': presetBytes,
        'programs/lua/sync_latch.lua': lua,
        'samples/Cheetah_MD16/MD16_BD_Gated_1.wav': wav,
        'samples/DMX606_SamplePack/DMX606_SD1_A.wav': wav,
        'samples/DMX606_SamplePack/DMX606_HHclosed_A.wav': wav,
        'samples/!LABS Soft Pno - PedOn/PedOn_A#-1.wav': wav,
        'multisamples/LABS Soft Pno - PedOn/A1.aif': aif,
        'multisamples/LABS Soft Pno - PedOn/C2.aif': aif,
      });

      final updates = <FileProgressUpdate>[];
      final creator = PackageCreator(fs);
      await creator.createPackage(
        presetFilePath: 'presets/SyncLatchDemo.json',
        config: const PackageConfig(),
        onFileProgress: updates.add,
        estimatedFileCount: 7, // 6 samples + 1 lua
      );

      expect(updates, isNotEmpty);
      // filesCompleted is monotonic non-decreasing.
      var prev = 0;
      for (final u in updates) {
        expect(u.filesCompleted, greaterThanOrEqualTo(prev));
        prev = u.filesCompleted;
      }
      // Last update should reflect the final collected count.
      expect(updates.last.filesCompleted, 7);
    },
  );
}
