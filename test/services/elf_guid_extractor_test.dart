import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/elf_guid_extractor.dart';

// Fixtures in test/fixtures/plugins/ are real plug-in objects, one per
// toolchain, because each lays out `_NT_factory` differently:
//
// - directionalSequencer.o: C++ (GCC). Two factories, `ATds` and `ATdm`,
//   with named `_ZN…FactoryE` symbols.
// - wavesmith.o: Rust. One factory, `NRws`, emitted as an anonymous local
//   object (`.Lanon.*`) that no factory symbol name points at. Provenance
//   and license: wavesmith.o.LICENSE.txt.
// - nt_seq.o: C++ (GCC). Seven factories with names the fallback does not
//   recognise, in `.rodata` beside `_NT_parameter` tables, one of which
//   starts with the printable word `/*4(`. Provenance and license:
//   nt_seq.o.LICENSE.txt.
//
// When a plug-in is misdetected, add its object here with a test asserting
// its exact GUIDs.
Future<Uint8List> _fixture(String name) async =>
    Uint8List.fromList(await File('test/fixtures/plugins/$name').readAsBytes());

/// Returns a copy of [bytes] in which the one occurrence of [from] is
/// replaced by [to], which must be the same length.
Uint8List _replaceOnce(Uint8List bytes, String from, String to) {
  expect(to.length, from.length);
  final needle = from.codeUnits;
  final hits = <int>[];
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length && match; j++) {
      match = bytes[i + j] == needle[j];
    }
    if (match) hits.add(i);
  }
  expect(hits, hasLength(1), reason: '"$from" must occur exactly once');
  return Uint8List.fromList(bytes)..setAll(hits.single, to.codeUnits);
}

void main() {
  group('ElfGuidExtractor', () {
    group('extractAllGuidsFromBytes', () {
      test('extracts multiple GUIDs from multi-algorithm plugin', () async {
        // DirectionalSequencer plugin by AgentTerror (@NerdRoger) has two algorithms:
        // - DirSeqAlg::Factory (ATds)
        // - DirSeqModMatrixAlg::Factory (ATdm)
        final pluginFile = File('test/fixtures/plugins/directionalSequencer.o');
        final bytes = Uint8List.fromList(await pluginFile.readAsBytes());

        final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
          bytes,
          'directionalSequencer.o',
        );

        // Should find exactly 2 GUIDs
        expect(guids.length, 2);

        // Extract just the GUID strings
        final guidStrings = guids.map((g) => g.guid).toSet();

        // Verify the expected GUIDs are present
        expect(guidStrings, containsAll(['ATds', 'ATdm']));

        // Both should be community plugins (have uppercase letters)
        for (final guid in guids) {
          expect(guid.isCommunityPlugin, isTrue);
        }
      });

      test(
        'extractGuidFromBytes returns first GUID for compatibility',
        () async {
          final pluginFile = File(
            'test/fixtures/plugins/directionalSequencer.o',
          );
          final bytes = Uint8List.fromList(await pluginFile.readAsBytes());

          final guid = await ElfGuidExtractor.extractGuidFromBytes(
            bytes,
            'directionalSequencer.o',
          );

          // Should return a valid GUID
          expect(guid.guid.length, 4);
          expect(guid.isCommunityPlugin, isTrue);
        },
      );
    });

    group('pluginEntry contract', () {
      test('finds the single GUID of a Rust plug-in', () async {
        final bytes = await _fixture('wavesmith.o');

        final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
          bytes,
          'wavesmith.o',
        );

        expect(guids.map((g) => g.guid), ['NRws']);
        expect(guids.single.isCommunityPlugin, isTrue);
      });

      test('symbol names alone cannot see the Rust factory', () async {
        // The control for the test above: the Rust factory has no name the
        // old heuristic recognises, so only the pluginEntry walk finds it.
        final bytes = await _fixture('wavesmith.o');

        expect(ElfGuidExtractor.guidsFromFactorySymbolNames(bytes), isEmpty);
        expect(
          ElfGuidExtractor.guidsReachableFromPluginEntry(
            bytes,
          ).map((g) => g.guid),
          ['NRws'],
        );
      });

      test(
        'reaches both C++ factories without the symbol-name fallback',
        () async {
          final bytes = await _fixture('directionalSequencer.o');

          final guids = ElfGuidExtractor.guidsReachableFromPluginEntry(bytes);

          expect(guids.map((g) => g.guid), unorderedEquals(['ATds', 'ATdm']));
        },
      );

      test(
        'reads every factory of a C++ plug-in and no parameter table',
        () async {
          // A parameter table also pairs a literal word with a string pointer
          // and a pointer 32 bytes on; only a factory's `construct` is code.
          final bytes = await _fixture('nt_seq.o');

          final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
            bytes,
            'nt_seq.o',
          );

          expect(
            guids.map((g) => g.guid),
            unorderedEquals([
              'NsTh',
              'NsSo',
              'NsAe',
              'NsMk',
              'NsFe',
              'NsQu',
              'NsMx',
            ]),
          );
          expect(ElfGuidExtractor.guidsFromFactorySymbolNames(bytes), isEmpty);
        },
      );

      test('falls back to symbol names when pluginEntry is absent', () async {
        final bytes = _replaceOnce(
          await _fixture('directionalSequencer.o'),
          'pluginEntry\u0000',
          'pluginEntrX\u0000',
        );

        expect(ElfGuidExtractor.guidsReachableFromPluginEntry(bytes), isEmpty);
        final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
          bytes,
          'renamed.o',
        );
        expect(guids.map((g) => g.guid), unorderedEquals(['ATds', 'ATdm']));
      });

      test(
        'inspectPluginObject reports the Rust plug-in as loadable',
        () async {
          final info = ElfGuidExtractor.inspectPluginObject(
            await _fixture('wavesmith.o'),
            'wavesmith.o',
          );

          expect(info.isArm32LittleEndian, isTrue);
          expect(info.hasPluginEntry, isTrue);
          expect(info.guids.map((g) => g.guid), ['NRws']);
        },
      );
    });

    group('_isFactorySymbol pattern matching', () {
      // Test the symbol matching logic indirectly through the extractor
      test('handles C++ namespaced Factory symbols', () async {
        // The directionalSequencer.o has symbols like:
        // _ZN9DirSeqAlg7FactoryE
        // _ZN18DirSeqModMatrixAlg7FactoryE
        final pluginFile = File('test/fixtures/plugins/directionalSequencer.o');
        final bytes = Uint8List.fromList(await pluginFile.readAsBytes());

        final guids = await ElfGuidExtractor.extractAllGuidsFromBytes(
          bytes,
          'directionalSequencer.o',
        );

        // If we found 2 GUIDs, the namespaced pattern matching worked
        expect(guids.length, 2);
      });
    });

    group('PluginGuid', () {
      test('isCommunityPlugin returns true for uppercase GUIDs', () {
        const guid = PluginGuid(guid: 'Test', rawValue: 0);
        expect(guid.isCommunityPlugin, isTrue);
      });

      test('isCommunityPlugin returns false for lowercase GUIDs', () {
        const guid = PluginGuid(guid: 'test', rawValue: 0);
        expect(guid.isCommunityPlugin, isFalse);
      });

      test('isFactoryAlgorithm returns true for lowercase GUIDs', () {
        const guid = PluginGuid(guid: 'satu', rawValue: 0);
        expect(guid.isFactoryAlgorithm, isTrue);
      });

      test('isFactoryAlgorithm returns false for uppercase GUIDs', () {
        const guid = PluginGuid(guid: 'Satu', rawValue: 0);
        expect(guid.isFactoryAlgorithm, isFalse);
      });

      test('toString formats GUID correctly', () {
        const guid = PluginGuid(guid: 'Test', rawValue: 0x74736554);
        expect(guid.toString(), contains('Test'));
        expect(guid.toString(), contains('74736554'));
      });
    });

    group('error handling', () {
      test('throws GuidExtractionException for invalid ELF data', () async {
        final invalidBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);

        expect(
          () => ElfGuidExtractor.extractAllGuidsFromBytes(
            invalidBytes,
            'invalid.o',
          ),
          throwsA(isA<GuidExtractionException>()),
        );
      });

      test('throws GuidExtractionException when no Factory found', () async {
        // Create minimal valid ELF header but with no factory symbols
        // This is a simplified test - in practice we'd need a proper ELF without Factory
        final emptyElf = Uint8List.fromList([
          0x7f, 0x45, 0x4c, 0x46, // ELF magic
          0x01, // 32-bit
          0x01, // Little endian
          0x01, // ELF version
          0x00, // OS/ABI
          ...List.filled(8, 0), // Padding
          0x01, 0x00, // Type: relocatable
          0x28, 0x00, // Machine: ARM
          0x01, 0x00, 0x00, 0x00, // Version
          ...List.filled(36, 0), // Rest of header
        ]);

        expect(
          () => ElfGuidExtractor.extractAllGuidsFromBytes(emptyElf, 'empty.o'),
          throwsA(isA<GuidExtractionException>()),
        );
      });
    });
  });
}
