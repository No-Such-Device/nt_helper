import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/decent_sampler_converter.dart';

void main() {
  group('DecentSamplerConverter', () {
    test('maps obvious Soft/Hard Decent groups to velocity layers', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/soft_c4_rr1.wav',
        'Samples/soft_c4_rr2.wav',
        'Samples/soft_d4_rr1.wav',
        'Samples/soft_d4_rr2.wav',
        'Samples/hard_c4_rr1.wav',
        'Samples/hard_c4_rr2.wav',
        'Samples/hard_d4_rr1.wav',
        'Samples/hard_d4_rr2.wav',
      ]);

      final preset = File('${tempDir.path}/Deep Drum.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Hard">
      <sample path="Samples/hard_c4_rr1.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="1"/>
      <sample path="Samples/hard_c4_rr2.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="2"/>
      <sample path="Samples/hard_d4_rr1.wav" rootNote="D4" loNote="D4" hiNote="D4" seqPosition="1"/>
      <sample path="Samples/hard_d4_rr2.wav" rootNote="D4" loNote="D4" hiNote="D4" seqPosition="2"/>
    </group>
    <group name="Soft">
      <sample path="Samples/soft_c4_rr1.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="1"/>
      <sample path="Samples/soft_c4_rr2.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="2"/>
      <sample path="Samples/soft_d4_rr1.wav" rootNote="D4" loNote="D4" hiNote="D4" seqPosition="1"/>
      <sample path="Samples/soft_d4_rr2.wav" rootNote="D4" loNote="D4" hiNote="D4" seqPosition="2"/>
    </group>
  </groups>
</DecentSampler>
''');

      final outputParent = Directory('${tempDir.path}/out');
      final result = await DecentSamplerConverter().convert(
        sourcePath: preset.path,
        outputParentPath: outputParent.path,
      );

      expect(result.copiedFiles, 8);
      expect(result.decisions.join('\n'), contains('Soft=V1'));
      expect(result.decisions.join('\n'), contains('Hard=V2'));

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, isNot(contains(contains('_dup'))));
      expect(outputFiles, contains('Deep_Drum_C4_V1_RR1.wav'));
      expect(outputFiles, contains('Deep_Drum_C4_V1_RR2.wav'));
      expect(outputFiles, contains('Deep_Drum_C4_V2_RR1.wav'));
      expect(outputFiles, contains('Deep_Drum_C4_V2_RR2.wav'));
      expect(outputFiles, contains('Deep_Drum_D4_V1_RR1.wav'));
      expect(outputFiles, contains('Deep_Drum_D4_V2_RR2.wav'));
    });

    test(
      'reads standalone preset samples from sibling folders under common parent',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_sibling_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final libraryDir = Directory('${tempDir.path}/Library')
          ..createSync(recursive: true);
        final presetDir = Directory('${libraryDir.path}/Preset')
          ..createSync(recursive: true);
        final samplesDir = Directory('${libraryDir.path}/Samples')
          ..createSync(recursive: true);
        await File('${samplesDir.path}/C4.wav').writeAsBytes(_dummyWav);
        final preset = File('${presetDir.path}/Sibling.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="../Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 1);
        expect(result.warnings, isEmpty);
        expect(
          await File('${result.outputFolders.single}/Sibling_C4.wav').exists(),
          isTrue,
        );
      },
    );

    test(
      'reads directory-imported preset samples from sibling folders under common parent',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_directory_sibling_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final libraryDir = Directory('${tempDir.path}/Library')
          ..createSync(recursive: true);
        final presetDir = Directory('${libraryDir.path}/Preset')
          ..createSync(recursive: true);
        final samplesDir = Directory('${libraryDir.path}/Samples')
          ..createSync(recursive: true);
        await File('${samplesDir.path}/C4.wav').writeAsBytes(_dummyWav);
        final preset = File('${presetDir.path}/DirectorySibling.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="../Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: presetDir.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 1);
        expect(result.warnings, isEmpty);
        expect(
          await File(
            '${result.outputFolders.single}/DirectorySibling_C4.wav',
          ).exists(),
          isTrue,
        );
      },
    );

    test(
      'does not read standalone preset samples outside common parent',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_escape_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final libraryDir = Directory('${tempDir.path}/Library')
          ..createSync(recursive: true);
        final presetDir = Directory('${libraryDir.path}/Preset')
          ..createSync(recursive: true);
        final outsideDir = Directory('${tempDir.path}/Outside')
          ..createSync(recursive: true);
        await File('${outsideDir.path}/leak.wav').writeAsBytes(_dummyWav);
        final preset = File('${presetDir.path}/Escape.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="../../Outside/leak.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 0);
        expect(
          result.warnings.join('\n'),
          contains('outside the selected source'),
        );
        expect(
          result.warnings.where(
            (warning) => warning.startsWith('Missing source sample'),
          ),
          isEmpty,
        );
        expect(
          await Directory(result.outputFolders.single)
              .list()
              .where((entity) => entity is File && entity.path.endsWith('.wav'))
              .isEmpty,
          isTrue,
        );
      },
    , tags: ['regression']);

    test(
      'does not read directory import samples outside selected root',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_dir_escape_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final libraryDir = Directory('${tempDir.path}/Library')
          ..createSync(recursive: true);
        final nestedPresetDir = Directory('${libraryDir.path}/Presets')
          ..createSync(recursive: true);
        final outsideDir = Directory('${tempDir.path}/Outside')..createSync();
        await File('${outsideDir.path}/leak.wav').writeAsBytes(_dummyWav);
        final preset = File('${nestedPresetDir.path}/Escape.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="../../Outside/leak.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: libraryDir.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 0);
        expect(
          result.warnings.join('\n'),
          contains('outside the selected source'),
        );
        expect(
          result.warnings.where(
            (warning) => warning.startsWith('Missing source sample'),
          ),
          isEmpty,
        );
      },
    , tags: ['regression']);

    test(
      'does not read absolute local sample paths inside selected root',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_absolute_local_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final samplesDir = Directory('${tempDir.path}/Samples')..createSync();
        final sample = File('${samplesDir.path}/C4.wav')
          ..writeAsBytesSync(_dummyWav);
        final preset = File('${tempDir.path}/AbsoluteLocal.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="${sample.path}" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 0);
        expect(
          result.warnings.join('\n'),
          contains('outside the selected source'),
        );
        expect(
          result.warnings.where(
            (warning) => warning.startsWith('Missing source sample'),
          ),
          isEmpty,
        );
      },
    , tags: ['regression']);

    test(
      'does not treat Windows rooted local paths as missing samples',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_windows_rooted_local_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final preset = File('${tempDir.path}/WindowsRooted.dspreset');
        await preset.writeAsString(r'''
<DecentSampler>
  <groups>
    <group>
      <sample path="\\server\share\C4.wav" rootNote="C4"/>
      <sample path="\Samples\C4.wav" rootNote="D4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 0);
        expect(
          result.warnings.where(
            (warning) => warning.contains('outside the selected source'),
          ),
          hasLength(2),
        );
        expect(
          result.warnings.where(
            (warning) => warning.startsWith('Missing source sample'),
          ),
          isEmpty,
        );
      },
    , tags: ['regression']);

    test(
      'does not follow local sample symlinks outside common parent',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_symlink_escape_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        final libraryDir = Directory('${tempDir.path}/Library')
          ..createSync(recursive: true);
        final presetDir = Directory('${libraryDir.path}/Preset')
          ..createSync(recursive: true);
        final outsideDir = Directory('${tempDir.path}/Outside')
          ..createSync(recursive: true);
        await File('${outsideDir.path}/leak.wav').writeAsBytes(_dummyWav);
        await Link(
          '${presetDir.path}/LinkedSamples',
        ).create(outsideDir.path, recursive: true);
        final preset = File('${presetDir.path}/Escape.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="LinkedSamples/leak.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
        );

        expect(result.copiedFiles, 0);
        expect(
          result.warnings.join('\n'),
          contains('outside the selected source'),
        );
        expect(
          result.warnings.where(
            (warning) => warning.startsWith('Missing source sample'),
          ),
          isEmpty,
        );
      },
    , tags: ['regression']);

    test('ignores macOS archive metadata entries', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_macos_junk_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'Antique Harmonium.dspreset',
            _singleSamplePreset.length,
            _singleSamplePreset.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('Samples/C4.wav', _dummyWav.length, _dummyWav))
        ..addFile(
          ArchiveFile(
            '__MACOSX/._Antique Harmonium.dspreset',
            _junkPreset.length,
            _junkPreset.codeUnits,
          ),
        )
        ..addFile(
          ArchiveFile(
            '._Antique Harmonium Swells.dspreset',
            _junkPreset.length,
            _junkPreset.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('.DS_Store', 0, const <int>[]));

      final source = File('${tempDir.path}/Antique Harmonium.dslibrary');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.outputFolders, hasLength(1));
      expect(result.outputFolders.single, endsWith('Antique_Harmonium'));
      expect(result.copiedFiles, 1);
      expect(result.warnings, isEmpty);
    }, tags: ['regression']);

    test('imports Decent Sampler zip archives', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_zip_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'Zip Library.dspreset',
            _singleSamplePreset.length,
            _singleSamplePreset.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('Samples/C4.wav', _dummyWav.length, _dummyWav));

      final source = File('${tempDir.path}/Zip Library.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 1);
      expect(result.outputFolders.single, endsWith('Zip_Library'));
      expect(
        await File(
          '${result.outputFolders.single}/Zip_Library_C4.wav',
        ).exists(),
        isTrue,
      );
    });

    test('does not read archive samples outside the archive root', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_archive_escape_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final preset = '''
<DecentSampler>
  <groups>
    <group>
      <sample path="../../Outside/leak.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''';
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'Presets/Escape.dspreset',
            preset.length,
            preset.codeUnits,
          ),
        )
        ..addFile(
          ArchiveFile('../Outside/leak.wav', _dummyWav.length, _dummyWav),
        );

      final source = File('${tempDir.path}/Escape.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 0);
      expect(
        result.warnings.join('\n'),
        contains('outside the selected source'),
      );
      expect(
        result.warnings.where(
          (warning) => warning.startsWith('Missing source sample'),
        ),
        isEmpty,
      );
    }, tags: ['regression']);

    test('does not rebase unsafe archive preset entries above root', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_archive_preset_rebase_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final preset = '''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''';
      final archive = Archive()
        ..addFile(
          ArchiveFile('../Escape.dspreset', preset.length, preset.codeUnits),
        )
        ..addFile(
          ArchiveFile('../Samples/C4.wav', _dummyWav.length, _dummyWav),
        );

      final source = File('${tempDir.path}/Rebase.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      await expectLater(
        DecentSamplerConverter().convert(
          sourcePath: source.path,
          outputParentPath: '${tempDir.path}/out',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(Directory('${tempDir.path}/out').existsSync(), isFalse);
    }, tags: ['regression']);

    test('does not read absolute archive sample paths', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_archive_absolute_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final preset = '''
<DecentSampler>
  <groups>
    <group>
      <sample path="/Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''';
      final archive = Archive()
        ..addFile(
          ArchiveFile('Absolute.dspreset', preset.length, preset.codeUnits),
        )
        ..addFile(ArchiveFile('Samples/C4.wav', _dummyWav.length, _dummyWav));

      final source = File('${tempDir.path}/Absolute.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 0);
      expect(
        result.warnings.join('\n'),
        contains('outside the selected source'),
      );
      expect(
        result.warnings.where(
          (warning) => warning.startsWith('Missing source sample'),
        ),
        isEmpty,
      );
    }, tags: ['regression']);

    test('does not read Windows absolute archive sample paths', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_archive_windows_absolute_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final preset = '''
<DecentSampler>
  <groups>
    <group>
      <sample path="C:\\Samples\\C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''';
      final archive = Archive()
        ..addFile(
          ArchiveFile('WinAbsolute.dspreset', preset.length, preset.codeUnits),
        )
        ..addFile(
          ArchiveFile('C:/Samples/C4.wav', _dummyWav.length, _dummyWav),
        );

      final source = File('${tempDir.path}/WinAbsolute.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 0);
      expect(
        result.warnings.join('\n'),
        contains('outside the selected source'),
      );
      expect(
        result.warnings.where(
          (warning) => warning.startsWith('Missing source sample'),
        ),
        isEmpty,
      );
    }, tags: ['regression']);

    test('lets user choose velocity layers for ambiguous groups', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_choice_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/g1_c4.wav',
        'Samples/g1_d4.wav',
        'Samples/g2_c4.wav',
        'Samples/g2_d4.wav',
      ]);

      final preset = File('${tempDir.path}/Kalimba Swarm.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Group 1">
      <sample path="Samples/g1_c4.wav" rootNote="C4" loNote="C4" hiNote="C4"/>
      <sample path="Samples/g1_d4.wav" rootNote="D4" loNote="D4" hiNote="D4"/>
    </group>
    <group name="Group 2">
      <sample path="Samples/g2_c4.wav" rootNote="C4" loNote="C4" hiNote="C4"/>
      <sample path="Samples/g2_d4.wav" rootNote="D4" loNote="D4" hiNote="D4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final converter = DecentSamplerConverter();
      final analysis = await converter.analyze(sourcePath: preset.path);
      expect(analysis.hasAmbiguousOverlaps, isTrue);
      expect(analysis.groups.map((group) => group.name), [
        'Group 1',
        'Group 2',
      ]);

      final result = await converter.convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
        options: const DecentSamplerConvertOptions(
          groupHandling: DecentSamplerGroupHandling.velocityLayers,
        ),
      );

      expect(result.warnings, isEmpty);
      expect(result.decisions.join('\n'), contains('user-selected velocity'));

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, contains('Kalimba_Swarm_C4_V1.wav'));
      expect(outputFiles, contains('Kalimba_Swarm_C4_V2.wav'));
      expect(outputFiles, contains('Kalimba_Swarm_D4_V1.wav'));
      expect(outputFiles, contains('Kalimba_Swarm_D4_V2.wav'));
    });

    test('analyze exposes tag XML mapping summaries', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_tag_summary_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final preset = File('${tempDir.path}/Dynamics.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Dynamics">
      <sample path="Samples/c4_p_rr1.wav" rootNote="C4" loNote="C4" hiNote="D4" loVel="1" hiVel="63" seqPosition="1" tags="p"/>
      <sample path="Samples/c4_p_rr2.wav" rootNote="C4" loNote="C4" hiNote="D4" loVel="1" hiVel="63" seqPosition="2" tags="p"/>
      <sample path="Samples/c4_mf.wav" rootNote="C4" loNote="C4" hiNote="D4" loVel="64" hiVel="127" tags="mf"/>
    </group>
  </groups>
</DecentSampler>
''');

      final analysis = await DecentSamplerConverter().analyze(
        sourcePath: preset.path,
      );

      final pTag = analysis.tags.singleWhere((tag) => tag.label == 'p');
      expect(pTag.noteRange, 'C4 - D4');
      expect(pTag.velocitySummary, '1-63');
      expect(pTag.roundRobinSummary, 'RR 1-2');

      final mfTag = analysis.tags.singleWhere((tag) => tag.label == 'mf');
      expect(mfTag.noteRange, 'C4 - D4');
      expect(mfTag.velocitySummary, '64-127');
      expect(mfTag.roundRobinSummary, 'No seqPosition');
    });

    test('summarizes fixed-pitch bed tags from actual XML structure', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_fixed_bed_tag_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/tron_g2.wav',
        'Samples/tron_gs2.wav',
        'Samples/tron_a2.wav',
        'Samples/tape.wav',
      ]);

      final preset = File('${tempDir.path}/DecenTron Cello.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group tags="Tron">
      <sample path="Samples/tron_g2.wav" rootNote="G2" loNote="G2" hiNote="G2"/>
      <sample path="Samples/tron_gs2.wav" rootNote="G#2" loNote="G#2" hiNote="G#2"/>
      <sample path="Samples/tron_a2.wav" rootNote="A2" loNote="A2" hiNote="A2"/>
    </group>
    <group tags="Tape" volume="2dB">
      <sample path="Samples/tape.wav" rootNote="G2" loNote="G2" hiNote="A2" pitchKeyTrack="0"/>
    </group>
  </groups>
</DecentSampler>
''');

      final analysis = await DecentSamplerConverter().analyze(
        sourcePath: preset.path,
      );
      final summaries = {
        for (final tag in analysis.tags) tag.label: tag.structureSummary,
      };

      expect(summaries['Tron'], '3 pitched samples, one per key, G2-A2');
      expect(summaries['Tape'], '1 fixed-pitch sample across G2-A2');
    });

    test('imports already extracted Decent Sampler folders', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_folder_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final libraryDir = Directory('${tempDir.path}/Extracted Library');
      await libraryDir.create(recursive: true);
      await _writeDummyWavs(libraryDir, ['Samples/C4.wav']);
      await File('${libraryDir.path}/Extracted.dspreset').writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final result = await DecentSamplerConverter().convert(
        sourcePath: libraryDir.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 1);
      expect(result.outputFolders.single, endsWith('Extracted'));
      expect(
        await File('${result.outputFolders.single}/Extracted_C4.wav').exists(),
        isTrue,
      );
    });

    test('copies local source docs and artwork into output folders', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_source_docs_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final libraryDir = Directory('${tempDir.path}/Documented Library');
      await libraryDir.create(recursive: true);
      await _writeDummyWavs(libraryDir, ['Samples/C4.wav']);
      await File('${libraryDir.path}/Documented.dspreset').writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');
      await File('${libraryDir.path}/LICENSE.txt').writeAsString('license');
      await File(
        '${libraryDir.path}/Docs/User Guide.pdf',
      ).create(recursive: true);
      await File(
        '${libraryDir.path}/Artwork/cover.png',
      ).create(recursive: true);
      await File(
        '${libraryDir.path}/Images/ui_knob.png',
      ).create(recursive: true);
      await File('${libraryDir.path}/.DS_Store').writeAsString('junk');

      final result = await DecentSamplerConverter().convert(
        sourcePath: libraryDir.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 1);
      expect(result.copiedDocumentationFiles, 3);
      final docsDir = Directory('${result.outputFolders.single}/_source_docs');
      final copiedDocs =
          await docsDir
                .list()
                .where((entity) => entity is File)
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(copiedDocs, ['LICENSE.txt', 'User Guide.pdf', 'cover.png']);
      expect(
        await File(
          '${result.outputFolders.single}/_CONVERSION_REPORT.md',
        ).readAsString(),
        contains('## Source documentation'),
      );
    });

    test('copies archive source docs without macOS junk', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_archive_docs_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'Presets/Archive.dspreset',
            _singleSamplePreset.length,
            _singleSamplePreset.codeUnits,
          ),
        )
        ..addFile(ArchiveFile('Presets/Samples/C4.wav', 4, _dummyWav))
        ..addFile(ArchiveFile('LICENSE.txt', 7, 'license'.codeUnits))
        ..addFile(ArchiveFile('Presets/Info/readme.md', 6, 'readme'.codeUnits))
        ..addFile(ArchiveFile('__MACOSX/._LICENSE.txt', 4, 'junk'.codeUnits));

      final source = File('${tempDir.path}/Archive.dslibrary');
      await source.writeAsBytes(ZipEncoder().encode(archive), flush: true);

      final result = await DecentSamplerConverter().convert(
        sourcePath: source.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.copiedFiles, 1);
      expect(result.copiedDocumentationFiles, 2);
      final docsDir = Directory('${result.outputFolders.single}/_source_docs');
      final copiedDocs =
          await docsDir
                .list()
                .where((entity) => entity is File)
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(copiedDocs, ['LICENSE.txt', 'readme.md']);
    }, tags: ['regression']);

    test('can skip source docs when requested', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_skip_docs_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final libraryDir = Directory('${tempDir.path}/No Docs Output');
      await libraryDir.create(recursive: true);
      await _writeDummyWavs(libraryDir, ['Samples/C4.wav']);
      await File('${libraryDir.path}/No Docs Output.dspreset').writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');
      await File('${libraryDir.path}/LICENSE.txt').writeAsString('license');

      final result = await DecentSamplerConverter().convert(
        sourcePath: libraryDir.path,
        outputParentPath: '${tempDir.path}/out',
        options: const DecentSamplerConvertOptions(includeSourceDocs: false),
      );

      expect(result.copiedFiles, 1);
      expect(result.copiedDocumentationFiles, 0);
      expect(
        await Directory('${result.outputFolders.single}/_source_docs').exists(),
        isFalse,
      );
    });

    test('analyzes every preset in extracted Decent folders', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_multi_preset_analysis_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final libraryDir = Directory('${tempDir.path}/Multi Preset Library');
      await libraryDir.create(recursive: true);
      await _writeDummyWavs(libraryDir, [
        'Samples/plain.wav',
        'Samples/dry.wav',
        'Samples/glitch.wav',
      ]);
      await File('${libraryDir.path}/A Plain.dspreset').writeAsString('''
<DecentSampler>
  <groups>
    <group name="Plain">
      <sample path="Samples/plain.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');
      await File('${libraryDir.path}/B Ambiguous.dspreset').writeAsString('''
<DecentSampler>
  <groups>
    <group name="Dry" tags="Dry">
      <sample path="Samples/dry.wav" rootNote="C4"/>
    </group>
    <group name="Glitch" tags="Glitch">
      <sample path="Samples/glitch.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final analysis = await DecentSamplerConverter().analyze(
        sourcePath: libraryDir.path,
      );

      expect(analysis.hasAmbiguousOverlaps, isTrue);
      expect(
        analysis.groups.map((group) => group.name),
        containsAll([
          'A_Plain / Plain',
          'B_Ambiguous / Dry',
          'B_Ambiguous / Glitch',
        ]),
      );
    });

    test(
      'summarizes same-structure tags without depending on label names',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_dry_layer_role_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/dry.wav',
          'Samples/glitch.wav',
          'Samples/jitter.wav',
          'Samples/air.wav',
          'Samples/wave.wav',
        ]);

        final preset = File('${tempDir.path}/D Mod.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Dry" tags="Dry">
      <sample path="Samples/dry.wav" rootNote="C4"/>
    </group>
    <group name="Glitch" tags="Glitch">
      <sample path="Samples/glitch.wav" rootNote="C4"/>
    </group>
    <group name="Jitter" tags="Jitter">
      <sample path="Samples/jitter.wav" rootNote="C4"/>
    </group>
    <group name="Air" tags="Air">
      <sample path="Samples/air.wav" rootNote="C4"/>
    </group>
    <group name="Wave" tags="Wave">
      <sample path="Samples/wave.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final analysis = await DecentSamplerConverter().analyze(
          sourcePath: preset.path,
        );
        final summaries = {
          for (final tag in analysis.tags) tag.label: tag.structureSummary,
        };

        expect(summaries['Dry'], '1 sample on C4');
        expect(summaries['Glitch'], '1 sample on C4');
        expect(summaries['Jitter'], '1 sample on C4');
        expect(summaries['Air'], '1 sample on C4');
        expect(summaries['Wave'], '1 sample on C4');
      },
    );

    test('summarizes repaired duplicate round robins as decisions', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_duplicate_rr_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/c4_rr1_a.wav',
        'Samples/c4_rr1_b.wav',
      ]);
      final preset = File('${tempDir.path}/Duplicate RR.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/c4_rr1_a.wav" rootNote="C4" seqPosition="1"/>
      <sample path="Samples/c4_rr1_b.wav" rootNote="C4" seqPosition="1"/>
    </group>
  </groups>
</DecentSampler>
''');

      final result = await DecentSamplerConverter().convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.warnings, isEmpty);
      expect(result.decisions.join('\n'), contains('repaired 1 duplicate'));
      expect(
        await File(
          '${result.outputFolders.single}/Duplicate_RR_C4_RR1.wav',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.outputFolders.single}/Duplicate_RR_C4_RR2.wav',
        ).exists(),
        isTrue,
      );
    });

    test(
      'splits structural banks while preserving group round robins',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_group_rr_bank_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/l1_c4_rr1.wav',
          'Samples/l1_c4_rr2.wav',
          'Samples/l1_d4_rr1.wav',
          'Samples/l1_d4_rr2.wav',
          'Samples/l2_c4_rr1.wav',
          'Samples/l2_c4_rr2.wav',
          'Samples/l2_d4_rr1.wav',
          'Samples/l2_d4_rr2.wav',
        ]);
        final preset = File('${tempDir.path}/Isolation.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1 RR1" seqPosition="1" ampVelTrack="1">
      <sample path="Samples/l1_c4_rr1.wav" rootNote="C4"/>
      <sample path="Samples/l1_d4_rr1.wav" rootNote="D4"/>
    </group>
    <group name="L1 RR2" seqPosition="2" ampVelTrack="1">
      <sample path="Samples/l1_c4_rr2.wav" rootNote="C4"/>
      <sample path="Samples/l1_d4_rr2.wav" rootNote="D4"/>
    </group>
    <group name="L2 RR1" seqPosition="1" ampVelTrack="1">
      <sample path="Samples/l2_c4_rr1.wav" rootNote="C4"/>
      <sample path="Samples/l2_d4_rr1.wav" rootNote="D4"/>
    </group>
    <group name="L2 RR2" seqPosition="2" ampVelTrack="1">
      <sample path="Samples/l2_c4_rr2.wav" rootNote="C4"/>
      <sample path="Samples/l2_d4_rr2.wav" rootNote="D4"/>
    </group>
  </groups>
  <ui>
    <labeled-knob label="Dynamics">
      <binding level="group" position="0" parameter="AMP_VOLUME"/>
      <binding level="group" position="1" parameter="AMP_VOLUME"/>
      <binding level="group" position="2" parameter="AMP_VOLUME"/>
      <binding level="group" position="3" parameter="AMP_VOLUME"/>
    </labeled-knob>
  </ui>
</DecentSampler>
''');

        final converter = DecentSamplerConverter();
        final analysis = await converter.analyze(sourcePath: preset.path);
        expect(analysis.hasAmbiguousOverlaps, isTrue);
        expect(analysis.structureSummary, contains('2 labelled group layer'));
        expect(analysis.structureSummary, contains('RR 1-2'));
        expect(analysis.structureSummary, contains('Dynamics'));
        expect(
          analysis.structureSummary,
          contains('control group volume for positions 0, 1, 2, 3'),
        );
        expect(
          analysis.recommendedGroupHandling,
          DecentSamplerGroupHandling.velocityLayers,
        );

        final result = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
          options: const DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.splitFolders,
          ),
        );

        expect(result.outputFolders, hasLength(2));
        expect(result.copiedFiles, 8);
        final l1Folder = result.outputFolders.singleWhere(
          (folder) => folder.endsWith('Isolation_L1'),
        );
        final l2Folder = result.outputFolders.singleWhere(
          (folder) => folder.endsWith('Isolation_L2'),
        );

        expect(
          await File('$l1Folder/Isolation_L1_C4_RR1.wav').exists(),
          isTrue,
        );
        expect(
          await File('$l1Folder/Isolation_L1_C4_RR2.wav').exists(),
          isTrue,
        );
        expect(
          await File('$l2Folder/Isolation_L2_D4_RR1.wav').exists(),
          isTrue,
        );
        expect(
          await File('$l2Folder/Isolation_L2_D4_RR2.wav').exists(),
          isTrue,
        );
        expect(result.warnings, isEmpty);
      },
    );

    test(
      'maps structural banks to velocity layers while preserving round robins',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_group_rr_velocity_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/l1_c4_rr1.wav',
          'Samples/l1_c4_rr2.wav',
          'Samples/l2_c4_rr1.wav',
          'Samples/l2_c4_rr2.wav',
        ]);
        final preset = File('${tempDir.path}/Layered RR.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1 RR1" seqPosition="1">
      <sample path="Samples/l1_c4_rr1.wav" rootNote="C4"/>
    </group>
    <group name="L1 RR2" seqPosition="2">
      <sample path="Samples/l1_c4_rr2.wav" rootNote="C4"/>
    </group>
    <group name="L2 RR1" seqPosition="1">
      <sample path="Samples/l2_c4_rr1.wav" rootNote="C4"/>
    </group>
    <group name="L2 RR2" seqPosition="2">
      <sample path="Samples/l2_c4_rr2.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final result = await DecentSamplerConverter().convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
          options: const DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.velocityLayers,
          ),
        );

        expect(result.outputFolders, hasLength(1));
        expect(result.copiedFiles, 4);
        final outputFolder = result.outputFolders.single;
        expect(
          await File('$outputFolder/Layered_RR_C4_V1_RR1.wav').exists(),
          isTrue,
        );
        expect(
          await File('$outputFolder/Layered_RR_C4_V1_RR2.wav').exists(),
          isTrue,
        );
        expect(
          await File('$outputFolder/Layered_RR_C4_V2_RR1.wav').exists(),
          isTrue,
        );
        expect(
          await File('$outputFolder/Layered_RR_C4_V2_RR2.wav').exists(),
          isTrue,
        );
        expect(result.warnings, isEmpty);
      },
    );

    test('keeps pure group-level round robins as round robins', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_pure_group_rr_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/c4_rr1.wav',
        'Samples/c4_rr2.wav',
        'Samples/d4_rr1.wav',
        'Samples/d4_rr2.wav',
      ]);
      final preset = File('${tempDir.path}/Pure RR.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="RR1" seqPosition="1">
      <sample path="Samples/c4_rr1.wav" rootNote="C4"/>
      <sample path="Samples/d4_rr1.wav" rootNote="D4"/>
    </group>
    <group name="RR2" seqPosition="2">
      <sample path="Samples/c4_rr2.wav" rootNote="C4"/>
      <sample path="Samples/d4_rr2.wav" rootNote="D4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final result = await DecentSamplerConverter().convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
      );

      expect(result.outputFolders, hasLength(1));
      expect(result.copiedFiles, 4);
      final outputFolder = result.outputFolders.single;
      expect(await File('$outputFolder/Pure_RR_C4_RR1.wav').exists(), isTrue);
      expect(await File('$outputFolder/Pure_RR_C4_RR2.wav').exists(), isTrue);
      expect(await File('$outputFolder/Pure_RR_D4_RR1.wav').exists(), isTrue);
      expect(await File('$outputFolder/Pure_RR_D4_RR2.wav').exists(), isTrue);
      expect(
        await Directory(
          outputFolder,
        ).list().where((entity) => entity.path.contains('_V')).isEmpty,
        isTrue,
      );
      expect(result.warnings, isEmpty);
    });

    test('forced tag round robins do not add velocity layers', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_tag_rr_only_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/take_a_c4.wav',
        'Samples/take_b_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Tag RR Only.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Take A" tags="Take A">
      <sample path="Samples/take_a_c4.wav" rootNote="C4"/>
    </group>
    <group name="Take B" tags="Take B">
      <sample path="Samples/take_b_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final converter = DecentSamplerConverter();
      final analysis = await converter.analyze(sourcePath: preset.path);
      final tagKeys = {for (final tag in analysis.tags) tag.label: tag.key};

      final result = await converter.convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
        options: DecentSamplerConvertOptions(
          groupHandling: DecentSamplerGroupHandling.tagMapping,
          selectedTagKeys: [tagKeys['Take A']!, tagKeys['Take B']!],
          tagRoundRobins: {tagKeys['Take A']!: 1, tagKeys['Take B']!: 2},
          preserveXmlMapping: true,
        ),
      );

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, ['Tag_RR_Only_C4_RR1.wav', 'Tag_RR_Only_C4_RR2.wav']);
      expect(outputFiles.any((name) => name.contains('_V')), isFalse);
      expect(result.warnings, isEmpty);
    });

    test('remapped tag key ranges keep round robin suffixes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_remapped_rr_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/take_1_c4.wav',
        'Samples/take_2_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Remapped RR.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Take" tags="Take">
      <sample path="Samples/take_1_c4.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="1"/>
      <sample path="Samples/take_2_c4.wav" rootNote="C4" loNote="C4" hiNote="C4" seqPosition="2"/>
    </group>
  </groups>
</DecentSampler>
''');

      final converter = DecentSamplerConverter();
      final analysis = await converter.analyze(sourcePath: preset.path);
      final tagKey = analysis.tags.single.key;

      final result = await converter.convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
        options: DecentSamplerConvertOptions(
          groupHandling: DecentSamplerGroupHandling.tagMapping,
          selectedTagKeys: [tagKey],
          tagKeyRanges: {
            tagKey: const DecentSamplerTagKeyRange(
              lowMidi: 48,
              rootMidi: 48,
              highMidi: 48,
            ),
          },
          preserveXmlMapping: true,
        ),
      );

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, ['Remapped_RR_C3_RR1.wav', 'Remapped_RR_C3_RR2.wav']);
      expect(result.warnings, isEmpty);
    }, tags: ['regression']);

    test('remapped tag key ranges keep velocity suffixes', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_remapped_velocity_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/soft_c4.wav',
        'Samples/hard_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Velocity Keyrange.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Take" tags="Take">
      <sample path="Samples/soft_c4.wav" rootNote="C4" loNote="C4" hiNote="C4" loVel="1" hiVel="63"/>
      <sample path="Samples/hard_c4.wav" rootNote="C4" loNote="C4" hiNote="C4" loVel="64" hiVel="127"/>
    </group>
  </groups>
</DecentSampler>
''');

      final converter = DecentSamplerConverter();
      final analysis = await converter.analyze(sourcePath: preset.path);
      final tagKey = analysis.tags.single.key;

      final result = await converter.convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
        options: DecentSamplerConvertOptions(
          groupHandling: DecentSamplerGroupHandling.tagMapping,
          selectedTagKeys: [tagKey],
          tagKeyRanges: {
            tagKey: const DecentSamplerTagKeyRange(
              lowMidi: 48,
              rootMidi: 48,
              highMidi: 48,
            ),
          },
          preserveXmlMapping: true,
        ),
      );

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, [
        'Velocity_Keyrange_C3_V1.wav',
        'Velocity_Keyrange_C3_V2.wav',
      ]);
      expect(result.copiedFiles, 2);
      expect(result.warnings, isEmpty);
    }, tags: ['regression']);

    test('single edited tag velocity keeps other selected tag layer', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_partial_tag_velocity_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/l1_c4.wav',
        'Samples/l2_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Partial Tag Velocity.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1" tags="L1">
      <sample path="Samples/l1_c4.wav" rootNote="C4"/>
    </group>
    <group name="L2" tags="L2">
      <sample path="Samples/l2_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final converter = DecentSamplerConverter();
      final analysis = await converter.analyze(sourcePath: preset.path);
      final tagKeys = {for (final tag in analysis.tags) tag.label: tag.key};

      final result = await converter.convert(
        sourcePath: preset.path,
        outputParentPath: '${tempDir.path}/out',
        options: DecentSamplerConvertOptions(
          groupHandling: DecentSamplerGroupHandling.tagMapping,
          selectedTagKeys: [tagKeys['L1']!, tagKeys['L2']!],
          tagVelocityLayers: {tagKeys['L2']!: 2},
          preserveXmlMapping: true,
        ),
      );

      final outputFiles =
          await Directory(result.outputFolders.single)
                .list()
                .where(
                  (entity) => entity is File && entity.path.endsWith('.wav'),
                )
                .map((entity) => entity.uri.pathSegments.last)
                .toList()
            ..sort();

      expect(outputFiles, [
        'Partial_Tag_Velocity_C4_V1.wav',
        'Partial_Tag_Velocity_C4_V2.wav',
      ]);
      expect(result.copiedFiles, 2);
      expect(result.warnings, isEmpty);
    });

    test(
      'first edited tag velocity avoids unedited tag fallback collision',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_first_tag_velocity_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/l1_c4.wav',
          'Samples/l2_c4.wav',
        ]);
        final preset = File('${tempDir.path}/First Tag Velocity.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1" tags="L1">
      <sample path="Samples/l1_c4.wav" rootNote="C4"/>
    </group>
    <group name="L2" tags="L2">
      <sample path="Samples/l2_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final converter = DecentSamplerConverter();
        final analysis = await converter.analyze(sourcePath: preset.path);
        final tagKeys = {for (final tag in analysis.tags) tag.label: tag.key};

        final result = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
          options: DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.tagMapping,
            selectedTagKeys: [tagKeys['L1']!, tagKeys['L2']!],
            tagVelocityLayers: {tagKeys['L1']!: 2},
            preserveXmlMapping: true,
          ),
        );

        final outputFiles =
            await Directory(result.outputFolders.single)
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.wav'),
                  )
                  .map((entity) => entity.uri.pathSegments.last)
                  .toList()
              ..sort();

        expect(outputFiles, [
          'First_Tag_Velocity_C4_V1.wav',
          'First_Tag_Velocity_C4_V2.wav',
        ]);
        expect(result.warnings, isEmpty);
      },
    , tags: ['regression']);

    test(
      'selected tag options apply ranges, layers and round robins',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_selected_tag_options_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/l1_c4.wav',
          'Samples/l2_c4.wav',
        ]);
        final preset = File('${tempDir.path}/Selected Tag Options.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1" tags="L1">
      <sample path="Samples/l1_c4.wav" rootNote="C4"/>
    </group>
    <group name="L2" tags="L2">
      <sample path="Samples/l2_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final converter = DecentSamplerConverter();
        final analysis = await converter.analyze(sourcePath: preset.path);
        final tagKeys = {for (final tag in analysis.tags) tag.label: tag.key};

        final result = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
          options: DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.selectedTags,
            selectedTagKeys: [tagKeys['L1']!, tagKeys['L2']!],
            tagVelocityLayers: {tagKeys['L2']!: 2},
            tagRoundRobins: {tagKeys['L1']!: 3},
            tagKeyRanges: {
              tagKeys['L1']!: const DecentSamplerTagKeyRange(
                lowMidi: 48,
                rootMidi: 48,
                highMidi: 48,
              ),
            },
            preserveXmlMapping: true,
          ),
        );

        final outputFiles =
            await Directory(result.outputFolders.single)
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.wav'),
                  )
                  .map((entity) => entity.uri.pathSegments.last)
                  .toList()
              ..sort();

        expect(outputFiles, [
          'Selected_Tag_Options_C3_V1_RR3.wav',
          'Selected_Tag_Options_C4_V2.wav',
        ]);
        expect(result.decisions.join('\n'), contains('round robins'));
        expect(result.warnings, isEmpty);
      },
    );

    test(
      'explicit singleton selected tag lanes survive filename rescan',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_singleton_tag_lane_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, ['Samples/l1_c4.wav']);
        final preset = File('${tempDir.path}/Singleton Tag.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="L1" tags="L1">
      <sample path="Samples/l1_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final converter = DecentSamplerConverter();
        final analysis = await converter.analyze(sourcePath: preset.path);
        final tagKey = analysis.tags.single.key;

        final velocityResult = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/velocity',
          options: DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.selectedTags,
            selectedTagKeys: [tagKey],
            tagVelocityLayers: {tagKey: 1},
            preserveXmlMapping: true,
          ),
        );
        final roundRobinResult = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/rr',
          options: DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.selectedTags,
            selectedTagKeys: [tagKey],
            tagRoundRobins: {tagKey: 1},
            preserveXmlMapping: true,
          ),
        );

        expect(
          await File(
            '${velocityResult.outputFolders.single}/Singleton_Tag_C4_V1.wav',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '${roundRobinResult.outputFolders.single}/Singleton_Tag_C4_RR1.wav',
          ).exists(),
          isTrue,
        );
      },
    );

    test(
      'partial group velocity selections avoid fallback collisions',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_partial_group_velocity_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/g1_c4.wav',
          'Samples/g2_c4.wav',
        ]);
        final preset = File('${tempDir.path}/Partial Group Velocity.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Group 1">
      <sample path="Samples/g1_c4.wav" rootNote="C4"/>
    </group>
    <group name="Group 2">
      <sample path="Samples/g2_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

        final converter = DecentSamplerConverter();
        final analysis = await converter.analyze(sourcePath: preset.path);
        final groupKeys = [for (final group in analysis.groups) group.key];

        final result = await converter.convert(
          sourcePath: preset.path,
          outputParentPath: '${tempDir.path}/out',
          options: DecentSamplerConvertOptions(
            groupHandling: DecentSamplerGroupHandling.velocityLayers,
            selectedGroupKeys: groupKeys,
            groupVelocityLayers: {groupKeys.first: 2},
            preserveXmlMapping: true,
          ),
        );

        final outputFiles =
            await Directory(result.outputFolders.single)
                  .list()
                  .where(
                    (entity) => entity is File && entity.path.endsWith('.wav'),
                  )
                  .map((entity) => entity.uri.pathSegments.last)
                  .toList()
              ..sort();

        expect(outputFiles, [
          'Partial_Group_Velocity_C4_V1.wav',
          'Partial_Group_Velocity_C4_V2.wav',
        ]);
        expect(result.warnings, isEmpty);
      },
    );

    test('previews raw buzz gloss without relying on label meaning', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_source_layer_tag_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/raw_c4.wav',
        'Samples/buzz_c4.wav',
        'Samples/gloss_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Kalimba Swarm.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="raw" tags="raw">
      <sample path="Samples/raw_c4.wav" rootNote="C4"/>
    </group>
    <group name="buzz" tags="buzz">
      <sample path="Samples/buzz_c4.wav" rootNote="C4"/>
    </group>
    <group name="gloss" tags="gloss">
      <sample path="Samples/gloss_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final analysis = await DecentSamplerConverter().analyze(
        sourcePath: preset.path,
      );
      final previews = {
        for (final tag in analysis.tags) tag.label: tag.previewSourcePath,
      };
      final summaries = {
        for (final tag in analysis.tags) tag.label: tag.structureSummary,
      };

      expect(previews['raw'], 'Samples/raw_c4.wav');
      expect(summaries['raw'], '1 sample on C4');
      expect(summaries['buzz'], '1 sample on C4');
      expect(summaries['gloss'], '1 sample on C4');
      expect(analysis.groups.first.previewSourcePath, 'Samples/raw_c4.wav');
    });

    test('classifies mic as a source layer tag', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'decent_converter_mic_tag_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      await _writeDummyWavs(tempDir, [
        'Samples/mic1_c4.wav',
        'Samples/mic2_c4.wav',
      ]);
      final preset = File('${tempDir.path}/Mic Choices.dspreset');
      await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Mic 1" mic="mic">
      <sample path="Samples/mic1_c4.wav" rootNote="C4"/>
    </group>
    <group name="Mic 2" tags="room">
      <sample path="Samples/mic2_c4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''');

      final analysis = await DecentSamplerConverter().analyze(
        sourcePath: preset.path,
      );
      final mic = analysis.tags.firstWhere((tag) => tag.key == 'tag:mic');

      expect(mic.previewSourcePath, 'Samples/mic1_c4.wav');
      expect(mic.structureSummary, '1 sample on C4');
    });

    test(
      'summarizes noise and named RR fallback groups structurally',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'decent_converter_noise_rr_fallback_test_',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });

        await _writeDummyWavs(tempDir, [
          'Samples/noise_91.wav',
          'Samples/dead_32_rr1.wav',
          'Samples/dead_32_rr2.wav',
        ]);
        final preset = File('${tempDir.path}/LoFi Nylon Shape.dspreset');
        await preset.writeAsString('''
<DecentSampler>
  <groups>
    <group name="Noises">
      <sample path="Samples/noise_91.wav" rootNote="91" loNote="91" hiNote="91"/>
    </group>
    <group name="DeadNotesRR1" seqMode="round_robin" seqLength="2" seqPosition="1">
      <sample path="Samples/dead_32_rr1.wav" rootNote="32" loNote="32" hiNote="32"/>
    </group>
    <group name="DeadNotesRR2" seqMode="round_robin" seqLength="2" seqPosition="2">
      <sample path="Samples/dead_32_rr2.wav" rootNote="32" loNote="32" hiNote="32"/>
    </group>
  </groups>
</DecentSampler>
''');

        final analysis = await DecentSamplerConverter().analyze(
          sourcePath: preset.path,
        );
        final summaries = {
          for (final tag in analysis.tags) tag.label: tag.structureSummary,
        };

        expect(summaries['Noises'], '1 sample on G6');
        expect(summaries['DeadNotesRR1'], '1 sample on G#1 · 1 RR slot');
        expect(summaries['DeadNotesRR2'], '1 sample on G#1 · 1 RR slot');
      },
    );
  });
}

Future<void> _writeDummyWavs(Directory baseDir, List<String> paths) async {
  for (final path in paths) {
    final file = File('${baseDir.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes([0x52, 0x49, 0x46, 0x46], flush: true);
  }
}

const _singleSamplePreset = '''
<DecentSampler>
  <groups>
    <group>
      <sample path="Samples/C4.wav" rootNote="C4"/>
    </group>
  </groups>
</DecentSampler>
''';

const _junkPreset = '''
This is an AppleDouble resource fork, not a Decent Sampler preset.
''';

const _dummyWav = [0x52, 0x49, 0x46, 0x46];
