import 'package:dart_elf/dart_elf.dart';
import 'package:flutter/foundation.dart';
import 'package:nt_helper/interfaces/preset_file_system.dart';

/// Exception thrown during GUID extraction
class GuidExtractionException implements Exception {
  final String message;
  const GuidExtractionException(this.message);

  @override
  String toString() => 'GuidExtractionException: $message';
}

/// Represents a plugin GUID extracted from an ELF file
class PluginGuid {
  final String guid;
  final int rawValue;

  const PluginGuid({required this.guid, required this.rawValue});

  /// Check if GUID contains at least one uppercase letter (community plugin)
  bool get isCommunityPlugin => guid.chars.any((c) => c.isUppercase);

  /// Check if GUID is all lowercase (factory/system algorithm)
  bool get isFactoryAlgorithm =>
      guid.chars.every((c) => c.isLowercase || !c.isLetter);

  @override
  String toString() =>
      'PluginGuid(guid: $guid, raw: 0x${rawValue.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

/// Facts about an ELF object that decide whether the Disting NT can load it
/// as a plug-in. Produced by [ElfGuidExtractor.inspectPluginObject].
class PluginObjectInfo {
  const PluginObjectInfo({
    required this.is32Bit,
    required this.isLittleEndian,
    required this.machine,
    required this.fileType,
    required this.hasPluginEntry,
    required this.guids,
  });

  /// True for ELFCLASS32.
  final bool is32Bit;

  /// True for ELFDATA2LSB.
  final bool isLittleEndian;

  /// The `e_machine` value; the NT needs [ElfArchitectureIdentifier.arm].
  final ElfArchitectureIdentifier machine;

  /// The `e_type` value; the NT needs [ElfFileType.relocatable].
  final ElfFileType fileType;

  /// Whether `pluginEntry` is defined (not merely referenced).
  final bool hasPluginEntry;

  /// GUIDs of the recognised factory symbols, without duplicates.
  final List<PluginGuid> guids;

  /// Whether the header matches the NT's Cortex-M7 target: 32-bit,
  /// little-endian ARM.
  bool get isArm32LittleEndian =>
      is32Bit && isLittleEndian && machine == ElfArchitectureIdentifier.arm;
}

/// Service for extracting plugin GUIDs from ELF .o files
class ElfGuidExtractor {
  /// Convert a 32-bit integer to a 4-character GUID string
  /// This matches the NT_MULTICHAR macro: (a<<0) | (b<<8) | (c<<16) | (d<<24)
  static String _guidFromU32(int value) {
    final bytes = [
      (value & 0xFF),
      ((value >> 8) & 0xFF),
      ((value >> 16) & 0xFF),
      ((value >> 24) & 0xFF),
    ];

    // Convert bytes to ASCII characters, handling non-printable chars
    final chars = bytes.map((b) {
      if (b >= 32 && b <= 126) {
        // Printable ASCII range
        return String.fromCharCode(b);
      } else {
        return '?';
      }
    }).join();

    return chars;
  }

  /// Check if a symbol name represents a Factory symbol.
  /// Handles multiple naming patterns:
  /// - "_ZL7factory" - static factory variable (mangled)
  /// - "factory" - unmangled factory variable
  /// - "_ZN*FactoryE" - C++ namespaced Factory (e.g., "_ZN9DirSeqAlg7FactoryE")
  static bool _isFactorySymbol(String name) {
    if (name == '_ZL7factory' || name == 'factory') {
      return true;
    }
    // Match C++ namespaced Factory symbols like "_ZN9DirSeqAlg7FactoryE"
    // Pattern: _ZN followed by length-prefixed names, ending with "FactoryE"
    if (name.startsWith('_ZN') && name.endsWith('FactoryE')) {
      return true;
    }
    return false;
  }

  /// Extract a GUID from a factory symbol in an ELF file.
  /// Returns null if the GUID cannot be extracted from this symbol.
  static PluginGuid? _extractGuidFromSymbol(
    ElfReader reader,
    ElfSymbol symbol,
    String symbolName,
  ) {
    try {
      // Get the section containing the factory symbol
      final sectionIndex = symbol.shndx;
      if (sectionIndex >= reader.sections.length) {
        return null;
      }

      final section = reader.sections[sectionIndex];

      // Calculate offset within section
      final symbolAddress = symbol.value;
      final sectionAddress = section.header.addr;

      if (symbolAddress < sectionAddress) {
        return null;
      }

      final offset = (symbolAddress - sectionAddress).toInt();

      // Get section data
      final sectionData = section.data();

      // Ensure we have enough data for the GUID (first 4 bytes of the factory struct)
      if (offset + 4 > sectionData.length) {
        return null;
      }

      // Extract the GUID as a 32-bit little-endian integer
      // The _NT_factory struct starts with: uint32_t guid;
      final guidBytes = sectionData.sublist(offset, offset + 4);
      final rawGuid = ByteData.sublistView(
        Uint8List.fromList(guidBytes),
      ).getUint32(0, Endian.little);

      // Convert to string representation
      final guidString = _guidFromU32(rawGuid);

      // Validate that we got a reasonable GUID (4 printable ASCII characters)
      if (guidString.length != 4 || guidString.contains('?')) {
        return null;
      }

      return PluginGuid(guid: guidString, rawValue: rawGuid);
    } catch (e) {
      return null;
    }
  }

  /// Byte offset of `name` in `_NT_factory`, after the 4-byte `guid`.
  static const _factoryNameOffset = 4;

  /// Byte offset of `construct` in `_NT_factory`. On the NT's 32-bit target
  /// it follows eight 4-byte fields: guid, name, description,
  /// numSpecifications, specifications, calculateStaticRequirements,
  /// initialise and calculateRequirements.
  static const _factoryConstructOffset = 32;

  /// Hops the walk from `pluginEntry` follows. One reaches a factory that
  /// `pluginEntry` returns directly; two reach one behind a pointer array or
  /// a helper function; three reach one behind both.
  static const _maxEntryHops = 3;

  static const _sectionFlagAlloc = 0x2;
  static const _sectionFlagExecInstr = 0x4;
  static const _sectionTypeNoBits = 8;

  /// Collects the plug-in's GUIDs without duplicates: those of the factories
  /// reachable from `pluginEntry` or, when none can be reached that way,
  /// those of recognised factory symbol names.
  static List<PluginGuid> _collectGuids(ElfReader reader) {
    final reachable = _collectGuidsFromPluginEntry(reader);
    if (reachable.isNotEmpty) return reachable;
    return _collectGuidsFromFactoryNames(reader);
  }

  /// GUIDs of the factories reachable from `pluginEntry` through relocations:
  /// the ones the module hands the NT for `kNT_selector_factoryInfo`.
  ///
  /// This follows the plug-in contract rather than a compiler's naming, so it
  /// holds whatever language built the object. A Rust build, for one, emits
  /// its factory as an anonymous local object (`.Lanon.*`) that no symbol
  /// name pattern recognises.
  ///
  /// Returns an empty list when the object is not relocatable, defines no
  /// `pluginEntry`, or reaches its factories in a way this walk cannot see
  /// (for example a call through a section symbol, whose extent is unknown).
  static List<PluginGuid> _collectGuidsFromPluginEntry(ElfReader reader) {
    // The factory offsets and the r_info split below are the 32-bit ABI's.
    if (reader.header.type != ElfFileType.relocatable ||
        reader.header.word != ElfWordSize.word32Bit) {
      return const [];
    }
    final symbolTable = reader.symbolTableSection;
    if (symbolTable == null) return const [];
    final symbols = symbolTable.symbols;
    final names = reader.stringTable;
    final sections = reader.sections;
    bool isDefined(ElfSymbol symbol) =>
        symbol.shndx != 0 && symbol.shndx < sections.length;

    ElfSymbol? entry;
    for (final symbol in symbols) {
      if (isDefined(symbol) && names?.at(symbol.nindex) == pluginEntrySymbol) {
        entry = symbol;
        break;
      }
    }
    if (entry == null) return const [];

    // In a relocatable object r_offset is relative to the section that the
    // relocation table's sh_info names.
    final relocations = <int, List<ElfRelocation>>{};
    for (final section in sections) {
      if (section is! ElfRelocationSection) continue;
      relocations
          .putIfAbsent(section.header.info, () => [])
          .addAll(section.entries);
    }

    final guids = <PluginGuid>[];
    final scannedData = <int>{};
    final followedCode = <(int, int)>{};
    // A Thumb function's symbol value carries the Thumb bit; clear it.
    final entryStart = entry.value & ~1;
    var frontier = <({int section, int start, int end})>[
      (section: entry.shndx, start: entryStart, end: entryStart + entry.size),
    ];
    for (var hop = 0; hop < _maxEntryHops && frontier.isNotEmpty; hop++) {
      final next = <({int section, int start, int end})>[];
      for (final range in frontier) {
        for (final relocation in relocations[range.section] ?? const []) {
          if (relocation.offset < range.start ||
              relocation.offset >= range.end) {
            continue;
          }
          final symbolIndex = relocation.info >> 8;
          if (symbolIndex >= symbols.length) continue;
          final target = symbols[symbolIndex];
          if (!isDefined(target)) continue;
          final section = sections[target.shndx];
          final flags = section.header.flags;
          if (flags & _sectionFlagAlloc == 0) continue;

          if (flags & _sectionFlagExecInstr != 0) {
            // Follow a helper function only when its extent is known.
            final start = target.value & ~1;
            if (target.type == ElfSymbolType.func &&
                target.size > 0 &&
                followedCode.add((target.shndx, start))) {
              next.add((
                section: target.shndx,
                start: start,
                end: start + target.size,
              ));
            }
            continue;
          }

          if (section.header.type == _sectionTypeNoBits) continue;
          if (!scannedData.add(target.shndx)) continue;
          final found = _factoriesInSection(section, {
            for (final r in relocations[target.shndx] ?? const []) r.offset,
          });
          if (found.isEmpty) {
            // Not a factory itself; perhaps an array of factory pointers.
            next.add((
              section: target.shndx,
              start: 0,
              end: section.header.size,
            ));
          }
          for (final guid in found) {
            if (!guids.any((g) => g.guid == guid.guid)) guids.add(guid);
          }
        }
      }
      frontier = next;
    }
    return guids;
  }

  /// GUIDs of the `_NT_factory` structs laid out in [section], whose
  /// relocations patch the section-relative offsets in [relocatedOffsets].
  ///
  /// Matches the struct's shape, not a name. A factory starts with a literal
  /// guid of four printable ASCII characters, so no relocation patches it.
  /// Its `name` pointer and its `construct` pointer, the one callback the API
  /// requires every algorithm to supply, are both relocated.
  static List<PluginGuid> _factoriesInSection(
    ElfSection section,
    Set<int> relocatedOffsets,
  ) {
    final data = section.data();
    final view = ByteData.sublistView(data);
    final found = <PluginGuid>[];
    for (
      var offset = 0;
      offset + _factoryConstructOffset + 4 <= data.length;
      offset += 4
    ) {
      if (relocatedOffsets.contains(offset) ||
          !relocatedOffsets.contains(offset + _factoryNameOffset) ||
          !relocatedOffsets.contains(offset + _factoryConstructOffset)) {
        continue;
      }
      final raw = view.getUint32(offset, Endian.little);
      final guid = _guidFromU32(raw);
      if (guid.contains('?')) continue;
      found.add(PluginGuid(guid: guid, rawValue: raw));
    }
    return found;
  }

  /// GUIDs reachable from `pluginEntry` alone, without the symbol-name
  /// fallback, so a test can prove the contract path finds them itself.
  @visibleForTesting
  static List<PluginGuid> guidsReachableFromPluginEntry(Uint8List bytes) =>
      _collectGuidsFromPluginEntry(ElfReader.fromBytes(bytes));

  /// GUIDs found by symbol name alone, without the `pluginEntry` walk.
  @visibleForTesting
  static List<PluginGuid> guidsFromFactorySymbolNames(Uint8List bytes) =>
      _collectGuidsFromFactoryNames(ElfReader.fromBytes(bytes));

  /// Collects the GUIDs of every recognised factory symbol in [reader],
  /// from the static and dynamic symbol tables, without duplicates.
  static List<PluginGuid> _collectGuidsFromFactoryNames(ElfReader reader) {
    final guids = <PluginGuid>[];
    void scan(ElfSymbolTableSection? table, ElfStringTable? names) {
      if (table == null) return;
      for (final symbol in table.symbols) {
        final name = names?.at(symbol.nindex) ?? '';
        if (!_isFactorySymbol(name)) continue;
        final guid = _extractGuidFromSymbol(reader, symbol, name);
        if (guid != null && !guids.any((g) => g.guid == guid.guid)) {
          guids.add(guid);
        }
      }
    }

    scan(reader.symbolTableSection, reader.stringTable);
    scan(reader.dynamicSymbolTableSection, reader.dynamicStringTable);
    return guids;
  }

  /// Extract ALL plugin GUIDs from ELF bytes.
  /// A single .o file can contain multiple algorithms, each with its own Factory.
  static Future<List<PluginGuid>> extractAllGuidsFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final guids = _collectGuids(ElfReader.fromBytes(bytes));
      if (guids.isEmpty) {
        throw GuidExtractionException('No Factory symbols found in $fileName');
      }
      return guids;
    } catch (e) {
      if (e is GuidExtractionException) rethrow;
      throw GuidExtractionException(
        'Failed to extract GUIDs from $fileName: $e',
      );
    }
  }

  /// Name of the symbol the Disting NT calls to enter a C++ plug-in, as
  /// declared by distingNT_API's `NT_DECLARE_PLUGIN`.
  static const pluginEntrySymbol = 'pluginEntry';

  /// Reads, in one ELF parse, everything needed to judge whether [bytes]
  /// can be loaded as a Disting NT plug-in: word size, byte order, machine,
  /// file type, whether [pluginEntrySymbol] is defined, and the factory GUIDs.
  ///
  /// Throws [GuidExtractionException] when the bytes are not a readable ELF.
  static PluginObjectInfo inspectPluginObject(
    Uint8List bytes,
    String fileName,
  ) {
    try {
      final reader = ElfReader.fromBytes(bytes);
      final header = reader.header;
      var hasPluginEntry = false;
      final symbols = reader.symbolTableSection;
      if (symbols != null) {
        final names = reader.stringTable;
        hasPluginEntry = symbols.symbols.any(
          (symbol) =>
              symbol.shndx != 0 &&
              names?.at(symbol.nindex) == pluginEntrySymbol,
        );
      }
      return PluginObjectInfo(
        is32Bit: header.word == ElfWordSize.word32Bit,
        isLittleEndian: header.endian == Endian.little,
        machine: header.arch,
        fileType: header.type,
        hasPluginEntry: hasPluginEntry,
        guids: _collectGuids(reader),
      );
    } catch (e) {
      throw GuidExtractionException('$fileName is not a readable ELF file: $e');
    }
  }

  /// Extract plugin GUID from ELF bytes (returns first GUID for backwards compatibility)
  static Future<PluginGuid> extractGuidFromBytes(
    Uint8List bytes,
    String fileName,
  ) async {
    final guids = await extractAllGuidsFromBytes(bytes, fileName);
    return guids.first;
  }

  /// Scan a directory for .o files and extract GUIDs using PresetFileSystem
  /// Returns a Map of GUID -> relative file path
  /// Note: A single .o file can contain multiple algorithms (GUIDs)
  static Future<Map<String, String>> scanPluginDirectory(
    PresetFileSystem fileSystem,
    String directoryPath,
  ) async {
    final result = <String, String>{};

    try {
      // List all files in the plugin directory
      final allFiles = await fileSystem.listFiles(
        directoryPath,
        recursive: true,
      );

      // Filter for .o files
      final pluginFiles = allFiles
          .where((path) => path.endsWith('.o'))
          .toList();

      for (final filePath in pluginFiles) {
        try {
          // Read the file via SYSEX
          final fileBytes = await fileSystem.readFile(filePath);
          if (fileBytes == null) {
            continue;
          }

          // Extract ALL GUIDs from the file (multi-algorithm plugins)
          final pluginGuids = await extractAllGuidsFromBytes(
            fileBytes,
            filePath,
          );
          for (final guid in pluginGuids) {
            result[guid.guid] = filePath;
          }
        } catch (e) {
          // Continue processing other files
        }
      }
    } catch (e) {
      // Intentionally empty
    }

    return result;
  }
}

// Extension to make character checking easier
extension on String {
  Iterable<String> get chars => split('');
}

extension on String {
  bool get isUppercase => this == toUpperCase();
  bool get isLowercase => this == toLowerCase();
  bool get isLetter => RegExp(r'[a-zA-Z]').hasMatch(this);
}
