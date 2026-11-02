import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/preset_analyzer.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/presets/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('PresetAnalyzer.extractPluginPaths', () {
    test('extracts plugin paths from AlgorithmInfo with isPlugin=true', () {
      // Arrange
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'MYPLUGIN',
          name: 'My Plugin',
          specifications: const [],
          isPlugin: true,
          filename: 'programs/plug-ins/MyPlugin.elf',
        ),
      ];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, {'MYPLUGIN': 'programs/plug-ins/MyPlugin.elf'});
    });

    test('ignores factory algorithms (isPlugin=false)', () {
      // Arrange
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'sdly',
          name: 'SD Multisample',
          specifications: const [],
          isPlugin: false,
          filename: null,
        ),
      ];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, isEmpty);
    });

    test('ignores plugins with null filename', () {
      // Arrange
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'PLUGIN1',
          name: 'Plugin Without Path',
          specifications: const [],
          isPlugin: true,
          filename: null,
        ),
      ];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, isEmpty);
    });

    test('ignores plugins with empty filename', () {
      // Arrange
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'PLUGIN2',
          name: 'Plugin Empty Path',
          specifications: const [],
          isPlugin: true,
          filename: '',
        ),
      ];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, isEmpty);
    });

    test('extracts multiple plugin paths', () {
      // Arrange
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'PLUGIN_A',
          name: 'Plugin A',
          specifications: const [],
          isPlugin: true,
          filename: 'programs/plug-ins/PluginA.elf',
        ),
        AlgorithmInfo(
          algorithmIndex: 1,
          guid: 'sdly',
          name: 'SD Multisample',
          specifications: const [],
          isPlugin: false,
          filename: null,
        ),
        AlgorithmInfo(
          algorithmIndex: 2,
          guid: 'PLUGIN_B',
          name: 'Plugin B',
          specifications: const [],
          isPlugin: true,
          filename: 'programs/plug-ins/subfolder/PluginB.elf',
        ),
      ];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, {
        'PLUGIN_A': 'programs/plug-ins/PluginA.elf',
        'PLUGIN_B': 'programs/plug-ins/subfolder/PluginB.elf',
      });
    });

    test('returns empty map for empty input', () {
      // Arrange
      final algorithmInfos = <AlgorithmInfo>[];

      // Act
      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      // Assert
      expect(result, isEmpty);
    });

    test('normalizes bare filenames into the correct plugin directory', () {
      // The firmware returns bare filenames (no directory prefix) for some
      // plugins. We have to prepend the canonical directory based on the
      // file extension or readFile() will fail at the SD card root.
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'Th26',
          name: 'ARP 2600',
          specifications: const [],
          isPlugin: true,
          filename: 'arp2600.o',
        ),
        AlgorithmInfo(
          algorithmIndex: 1,
          guid: 'LUAX',
          name: 'Lua plugin',
          specifications: const [],
          isPlugin: true,
          filename: 'my_script.lua',
        ),
        AlgorithmInfo(
          algorithmIndex: 2,
          guid: 'TPOT',
          name: 'Three Pot plugin',
          specifications: const [],
          isPlugin: true,
          filename: 'knob_demo.3pot',
        ),
      ];

      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      expect(result, {
        'Th26': 'programs/plug-ins/arp2600.o',
        'LUAX': 'programs/lua/my_script.lua',
        'TPOT': 'programs/three_pot/knob_demo.3pot',
      });
    }, tags: ['regression']);

    test('prepends plug-ins dir even when filename has a subfolder', () {
      // Firmware returns filenames relative to the plugin directory, so
      // `corrupter/corrupter.o` means `/programs/plug-ins/corrupter/corrupter.o`
      // — the firmware strips the common `programs/plug-ins/` prefix to
      // save null-terminated string bytes in the SysEx payload.
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'ThCo',
          name: 'Corrupter',
          specifications: const [],
          isPlugin: true,
          filename: 'corrupter/corrupter.o',
        ),
      ];

      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      expect(result, {'ThCo': 'programs/plug-ins/corrupter/corrupter.o'});
    }, tags: ['regression']);

    test('trusts filenames that already start with programs/', () {
      // If the firmware does return a full SD-rooted path (e.g. on newer
      // firmware), leave it alone.
      final algorithmInfos = [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'PLUGIN_C',
          name: 'Already fully qualified',
          specifications: const [],
          isPlugin: true,
          filename: 'programs/plug-ins/subfolder/PluginC.o',
        ),
      ];

      final result = PresetAnalyzer.extractPluginPaths(algorithmInfos);

      expect(result, {'PLUGIN_C': 'programs/plug-ins/subfolder/PluginC.o'});
    });
  });

  // ---------------------------------------------------------------------------
  // analyzeDependencies — exercises against real preset JSON fixtures captured
  // from the distingNT reference repo. Each fixture is a complete `.json` file
  // as the firmware would emit, so these tests guard against regressions in
  // the GUID/field-name conventions emitted by real hardware.
  // ---------------------------------------------------------------------------
  group('PresetAnalyzer.analyzeDependencies', () {
    test('Granulated Piano: pyms multisample folder', () {
      final preset = _loadFixture('granulated_piano.json');

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      // pyms timbre folder → multisample
      expect(deps.multisampleFolders, contains('LABS Soft Pno - PedOn'));
      // gran has an empty `sample` field; analyzer should ignore it.
      expect(deps.granulatorSamples, isEmpty);
      // No Lua, 3pot, or wavetable in this preset
      expect(deps.luaScripts, isEmpty);
      expect(deps.threePotPrograms, isEmpty);
      expect(deps.wavetables, isEmpty);
      // No community plugins (all factory algorithms)
      expect(deps.communityPlugins, isEmpty);
    });

    test('SyncLatchDemo: lua program + samp triggers + pyms folder', () {
      final preset = _loadFixture('sync_latch_demo.json');

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      // Lua slot has guid 'lua ' (with trailing space) and field `program` —
      // the previous (broken) check looked at guid=='lua' and field 'script',
      // so this case is the regression guard.
      expect(deps.luaScripts, contains('sync_latch.lua'));

      // samp slot has 8 trigger entries — only unique paths survive in the Set
      expect(
        deps.sampleFiles,
        containsAll([
          'Cheetah_MD16/MD16_BD_Gated_1.wav',
          'DMX606_SamplePack/DMX606_SD1_A.wav',
          'DMX606_SamplePack/DMX606_HHclosed_A.wav',
          '!LABS Soft Pno - PedOn/PedOn_A#-1.wav',
        ]),
      );
      // Four distinct sample paths after dedup
      expect(deps.sampleFiles.length, 4);

      // pyms timbre folder
      expect(deps.multisampleFolders, contains('LABS Soft Pno - PedOn'));
    }, tags: ['regression']);

    test('Automatronic: pyfm banks + waos wavetable', () {
      final preset = _loadFixture('automatronic.json');

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.fmBanks, containsAll(['!ROM1B.syx', '!ROM2A.syx']));
      expect(deps.wavetables, contains('warm-squ'));
      // No community plugins
      expect(deps.communityPlugins, isEmpty);
    });

    test('FM banks: built-in synth banks are skipped (no file on SD)', () {
      // The pyfm `bank` field can be `<built-in N>` for firmware-
      // synthesized ROMs that have no corresponding /FMSYX/ file.
      // Including them as deps would generate spurious warnings on
      // export. Real preset: presets/Community/Play in time.json.
      final preset = {
        'slots': [
          {
            'guid': 'pyfm',
            'timbres': [
              {'bank': '<built-in 2>', 'voice': 'BELL C    '},
              {'bank': '!ROM1A.syx', 'voice': 'PIANO 1   '},
            ],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.fmBanks, {'!ROM1A.syx'});
    }, tags: ['regression']);

    test('community plugin GUID detection preserves trailing space', () {
      // Synthetic preset to verify the analyzer:
      //  - detects uppercase GUIDs as community plugins
      //  - preserves the original (un-trimmed) GUID for path lookup
      final preset = {
        'slots': [
          {'guid': 'MyPlu', 'name': 'Community plugin'},
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.communityPlugins, contains('MyPlu'));
    });

    test('lua field "program" matches even when guid has trailing space', () {
      final preset = {
        'slots': [
          {'guid': 'lua ', 'program': 'my_script.lua'},
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.luaScripts, {'my_script.lua'});
    }, tags: ['regression']);

    test('pymu collects top-level folder as multisample folder', () {
      // `pymu` (current Poly Multisample, firmware >= 1.10) has no
      // `timbres[]` array — one folder per slot, stored top-level. The
      // `saveFolder`/`saveFilename` fields are the recording destination
      // and must NOT be treated as dependencies.
      final preset = {
        'slots': [
          {
            'guid': 'pymu',
            'folder': '!CORec_Modular Percussion Stereo',
            'saveFolder': 'untitled',
            'saveFilename': 'sample',
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.multisampleFolders, {'!CORec_Modular Percussion Stereo'});
      // saveFolder is a record destination, not a dependency.
      expect(deps.sampleFolders, isEmpty);
    }, tags: ['regression']);

    test('granulator slot collects sample when populated', () {
      final preset = {
        'slots': [
          {'guid': 'gran', 'sample': 'kick.wav'},
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.granulatorSamples, {'kick.wav'});
    });

    test('<MULTISAMPLE> trigger maps to folder, not file', () {
      // The firmware token `<MULTISAMPLE>` means "the algorithm picks a
      // file from this folder by pitch/velocity at runtime". The whole
      // folder must travel; no single-file path should be added.
      final preset = {
        'slots': [
          {
            'guid': 'samp',
            'triggers': [
              {'folder': 'MD16_Kit', 'sample': '<MULTISAMPLE>'},
            ],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.sampleFolders, contains('MD16_Kit'));
      expect(deps.sampleFiles.any((p) => p.contains('<MULTISAMPLE>')), isFalse);
    });

    test('explicit-filename trigger still maps to single-file', () {
      final preset = {
        'slots': [
          {
            'guid': 'samp',
            'triggers': [
              {'folder': 'MD16_Kit', 'sample': 'kick.wav'},
            ],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.sampleFiles, contains('MD16_Kit/kick.wav'));
      expect(deps.sampleFolders, isNot(contains('MD16_Kit')));
    });

    test('trigger with no folder is silently skipped', () {
      final preset = {
        'slots': [
          {
            'guid': 'samp',
            'triggers': [
              {'sample': 'kick.wav'},
              {'folder': '', 'sample': 'snare.wav'},
            ],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.sampleFiles, isEmpty);
      expect(deps.sampleFolders, isEmpty);
    });

    test('midp slot triggers MIDI-tree bundling', () {
      // MIDI Player references files by parameter-array index, not by
      // name string — we bundle the whole tree.
      final preset = {
        'slots': [
          {
            'guid': 'midp',
            'parameters': [0, 1, 1, 1, 0],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.bundleMidiTree, isTrue);
      expect(deps.bundleSclTree, isFalse);
    });

    test('quan slot triggers scl + kbm bundling', () {
      final preset = {
        'slots': [
          {
            'guid': 'quan',
            'parameters': [0],
          },
        ],
      };

      final deps = PresetAnalyzer.analyzeDependencies(preset);

      expect(deps.bundleSclTree, isTrue);
      expect(deps.bundleKbmTree, isTrue);
      expect(deps.bundleMidiTree, isFalse);
    });
  });
}
