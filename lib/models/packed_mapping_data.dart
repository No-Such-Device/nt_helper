import 'dart:math' show min;
import 'dart:typed_data';

import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/firmware_version.dart';

enum MidiMappingType {
  cc(0),
  noteMomentary(1),
  noteToggle(2),
  cc14BitLow(3),
  cc14BitHigh(4),
  pitchBend(5),
  channelPressure(6);

  final int value;
  const MidiMappingType(this.value);
}

class PackedMappingData {
  // Version
  final int version;

  // CV Mapping
  final int source; // Source of the CV input
  final int cvInput; // Input source for CV
  final bool isUnipolar; // Unipolar or bipolar mapping
  final bool isGate; // Gate mapping enabled
  final int volts; // Voltage scale
  final int delta; // CV delta (sensitivity)

  // MIDI Mapping
  final int midiChannel; // MIDI channel
  final MidiMappingType midiMappingType; // CC, Note Momentary, or Note Toggle
  final int midiCC; // MIDI control change number (or note number if type != cc)
  final bool isMidiEnabled; // MIDI mapping enabled
  final bool isMidiSymmetric; // MIDI mapping symmetric
  final bool isMidiRelative; // MIDI mapping relative
  final int midiMin; // Minimum MIDI value
  final int midiMax; // Maximum MIDI value

  // I2C Mapping
  final int i2cCC; // I2C control code
  final bool isI2cEnabled; // I2C mapping enabled
  final bool isI2cSymmetric; // I2C mapping symmetric
  final int i2cMin; // Minimum I2C value
  final int i2cMax; // Maximum I2C value

  // Mapping v8 (upstream distingNT commit 905deb6). View change is the
  // inverse of MIDI flags bit 2; bypass flags are MIDI flags2 bit 1 / I2C bit 2.
  final bool midiViewChange;
  final bool midiIgnoreWhenBypassed;
  final bool i2cIgnoreWhenBypassed;
  // Preserve reserved bits without assigning undocumented semantics.
  final int cvFlagsExtra;
  final int i2cFlagsExtra;
  final int? unknownMidiMappingType;

  // Performance Page (used for sort order only, not navigation)
  final int perfPageIndex; // Performance page index (0 = not assigned, 1-30 = valid pages)

  // Constructor
  PackedMappingData({
    required this.source,
    required this.cvInput,
    required this.isUnipolar,
    required this.isGate,
    required this.volts,
    required this.delta,
    required this.midiChannel,
    required this.midiMappingType,
    required this.midiCC,
    required this.isMidiEnabled,
    required this.isMidiSymmetric,
    required this.isMidiRelative,
    required this.midiMin,
    required this.midiMax,
    required this.i2cCC,
    required this.isI2cEnabled,
    required this.isI2cSymmetric,
    required this.i2cMin,
    required this.i2cMax,
    required this.perfPageIndex,
    required this.version,
    this.midiViewChange = true,
    this.midiIgnoreWhenBypassed = false,
    this.i2cIgnoreWhenBypassed = false,
    this.cvFlagsExtra = 0,
    this.i2cFlagsExtra = 0,
    this.unknownMidiMappingType,
  });

  factory PackedMappingData.filler() {
    return PackedMappingData(
      source: -1,
      cvInput: -1,
      isUnipolar: false,
      isGate: false,
      volts: -1,
      delta: -1,
      midiChannel: -1,
      midiMappingType: MidiMappingType.cc,
      midiCC: -1,
      isMidiEnabled: false,
      isMidiSymmetric: false,
      isMidiRelative: false,
      midiMin: -1,
      midiMax: -1,
      i2cCC: -1,
      isI2cEnabled: false,
      isI2cSymmetric: false,
      i2cMin: -1,
      i2cMax: -1,
      perfPageIndex: 0,
      version: -1,
    );
  }

  // Decode from packed Uint8List with bounds checking
  factory PackedMappingData.fromBytes(int version, Uint8List data) {
    if (version < 1) {
      return PackedMappingData.filler();
    }

    // Parse using the highest known feature set. Version-conditional reads
    // below handle per-version field presence. For truly unknown future
    // versions (> 8) we parse as v8 and let safe-read helpers handle any
    // fields beyond the data boundary.
    final int parseVersion = version.clamp(1, 8);

    int offset = 0;
    final dataLength = data.length;

    // Helper function for safe decoding (decode16 needs 3 bytes) - using unsigned version to match JavaScript
    int safeDecode16Unsigned(int currentOffset) {
      if (currentOffset + 3 > dataLength) {
        return 0;
      }
      return decode16Unsigned(data, currentOffset);
    }

    // Helper function for safe signed 16-bit decoding
    int safeDecode16Signed(int currentOffset) {
      if (currentOffset + 3 > dataLength) {
        return 0;
      }
      return decode16(data, currentOffset);
    }

    // Helper function for safe byte read
    int safeReadByte(int currentOffset) {
      if (currentOffset >= dataLength) {
        return 0;
      }
      return data[currentOffset];
    }

    // Expected byte counts per version (from reference: dnt_preset_editor.html):
    //   v1: CV(6) + MIDI(8) + I2C(8)           = 22
    //   v2: CV(6) + MIDI(9) + I2C(8)           = 23
    //   v3: CV(6) + MIDI(9) + I2C(9)           = 24
    //   v4: CV(7) + MIDI(9) + I2C(9)           = 25
    //   v5: CV(7) + MIDI(9) + I2C(9) + Perf(1) = 26
    //   v6: CV(7) + MIDI(9) + I2C(9)           = 25  (perf page removed)
    //   v7: CV(7) + MIDI(9) + I2C(9)           = 25  (pitch bend/channel pressure)
    //   v8: CV(7) + MIDI(9) + I2C(9)           = 25  (view/bypass flags)
    // For unknown future versions (> 8), require the v4 core (25 bytes).
    final int expectedLength = switch (parseVersion) {
      1 => 22,
      2 => 23,
      3 => 24,
      4 => 25,
      5 => 26,
      _ => 25, // v6+ : same core as v4, no perf page byte
    };

    if (dataLength < expectedLength) {
      return PackedMappingData.filler();
    }

    // --- Decode CV Mapping ---
    final source = (parseVersion >= 4) ? safeReadByte(offset++) : 0;
    final cvInput = safeReadByte(offset++);
    final cvFlags = safeReadByte(offset++);
    final isUnipolar = (cvFlags & 1) != 0;
    final isGate = (cvFlags & 2) != 0;
    final volts = safeReadByte(offset++);
    final delta = safeDecode16Unsigned(offset);
    offset += 3;

    // --- Decode MIDI Mapping ---
    var midiCC = safeReadByte(offset++);
    final midiFlags = safeReadByte(offset++);
    final midiFlags2 = parseVersion >= 2 ? safeReadByte(offset++) : 0;

    // Mapping v7 replaced the legacy CC 128 aftertouch convention with
    // explicit MIDI type values for pitch bend and channel pressure.
    if (parseVersion < 7 && midiFlags & 4 != 0) {
      midiCC = 128;
    }

    final midiChannel = (midiFlags >> 3) & 0xF;
    final isMidiEnabled = (midiFlags & 1) != 0;
    final isMidiSymmetric = (midiFlags & 2) != 0;

    // Extract relative flag (bit 0) and type value (bits 2-6) using bit-shift
    final isMidiRelative = (midiFlags2 & 0x01) != 0;
    final typeValue = midiFlags2 >> 2; // Extract type from bits 2-6

    // Map type value to MidiMappingType enum.
    final MidiMappingType midiMappingType;
    if (typeValue >= 0 && typeValue < MidiMappingType.values.length) {
      midiMappingType = MidiMappingType.values[typeValue];
    } else {
      midiMappingType = MidiMappingType.cc;
    }

    final midiMin = safeDecode16Signed(offset);
    offset += 3;
    final midiMax = safeDecode16Signed(offset);
    offset += 3;

    // --- Decode I2C Mapping ---
    var i2cCC = safeReadByte(offset++);
    if (parseVersion >= 3) {
      i2cCC |= (safeReadByte(offset++) & 1) << 7;
    }
    final i2cFlags = safeReadByte(offset++);
    final isI2cEnabled = (i2cFlags & 1) != 0;
    final isI2cSymmetric = (i2cFlags & 2) != 0;
    final i2cMin = safeDecode16Signed(offset);
    offset += 3;
    final i2cMax = safeDecode16Signed(offset);
    offset += 3;

    // --- Decode Performance Page ---
    // Per reference (dnt_preset_editor.html): perf page byte is only present
    // in version exactly 5. Version 6 removed it from the mapping data;
    // perf page assignments are now managed via separate SysEx commands.
    final perfPageIndex = (version == 5) ? safeReadByte(offset++) : 0;

    return PackedMappingData(
      source: source,
      cvInput: cvInput,
      isUnipolar: isUnipolar,
      isGate: isGate,
      volts: volts,
      delta: delta,
      midiChannel: midiChannel,
      midiMappingType: midiMappingType,
      midiCC: midiCC,
      isMidiEnabled: isMidiEnabled,
      isMidiSymmetric: isMidiSymmetric,
      isMidiRelative: isMidiRelative,
      midiMin: midiMin,
      midiMax: midiMax,
      i2cCC: i2cCC,
      isI2cEnabled: isI2cEnabled,
      isI2cSymmetric: isI2cSymmetric,
      i2cMin: i2cMin,
      i2cMax: i2cMax,
      perfPageIndex: perfPageIndex,
      version: version,
      midiViewChange: version < 8 || (midiFlags & 4) == 0,
      midiIgnoreWhenBypassed: version >= 8 && (midiFlags2 & 2) != 0,
      i2cIgnoreWhenBypassed: version >= 8 && (i2cFlags & 4) != 0,
      cvFlagsExtra: cvFlags & 0x7C,
      i2cFlagsExtra: i2cFlags & (version >= 8 ? 0x78 : 0x7C),
      unknownMidiMappingType: typeValue >= MidiMappingType.values.length
          ? typeValue
          : null,
    );
  }

  bool get hasV8Options =>
      !midiViewChange || midiIgnoreWhenBypassed || i2cIgnoreWhenBypassed;

  /// Reject lossy or unsupported live writes before any mapping subset is sent.
  /// Reading/caching observed data remains independent of firmware eligibility.
  void validateForFirmware(FirmwareVersion firmware) {
    if (version > 8 || unknownMidiMappingType != null) {
      throw UnsupportedError(
        'Unknown mapping version or MIDI type is read-only',
      );
    }
    if ((version >= 8 || hasV8Options) && !firmware.hasBypassAwareMappings) {
      throw UnsupportedError(
        'Bypass-aware mappings require firmware 1.20 or newer',
      );
    }
    if (hasV8Options && version < 8) {
      throw UnsupportedError(
        'Bypass-aware mappings require an observed v8 mapping',
      );
    }
  }

  Uint8List encodeCVPackedData() {
    final int encodeVersion = min(version, 8);

    // Compute the flags
    int flags = (cvFlagsExtra & 0x7C) | (isUnipolar ? 1 : 0) | (isGate ? 2 : 0);

    // Build the packed payload (starting after the version byte)
    final payload = [
      if (encodeVersion >= 4) source & 0x7F, // Source of the CV input
      cvInput & 0x7F, // CV input number
      flags & 0x7F, // Flags for unipolar/gate settings
      volts & 0x7F, // Voltage setting (0-127)
      ...encode16(delta), // Encode 'delta' as 7-bit chunks
    ];

    return Uint8List.fromList(payload);
  }

  Uint8List encodeMIDIPackedData() {
    final int encodeVersion = min(version, 8);
    final effectiveMidiMappingType =
        encodeVersion >= 7 &&
            midiMappingType == MidiMappingType.cc &&
            midiCC == 128
        ? MidiMappingType.channelPressure
        : midiMappingType;

    var adjustedCC =
        effectiveMidiMappingType == MidiMappingType.pitchBend ||
            effectiveMidiMappingType == MidiMappingType.channelPressure
        ? 0
        : midiCC;

    // Compute the flags
    int flags =
        (isMidiEnabled ? 1 : 0) |
        (isMidiSymmetric ? 2 : 0) |
        ((midiChannel & 0xF) << 3) |
        (encodeVersion >= 8 && !midiViewChange ? 4 : 0);

    // Encode midiFlags2 using bit-shift: relative flag (bit 0) and type value (bits 2-6)
    final effectiveIsMidiRelative =
        effectiveMidiMappingType != MidiMappingType.pitchBend &&
        effectiveMidiMappingType != MidiMappingType.channelPressure &&
        isMidiRelative;
    int midiFlags2 =
        (effectiveIsMidiRelative ? 1 : 0) |
        ((unknownMidiMappingType ?? effectiveMidiMappingType.value) << 2) |
        (encodeVersion >= 8 && midiIgnoreWhenBypassed ? 2 : 0);

    // Adjust the CC number and flags if necessary for legacy aftertouch.
    if (encodeVersion < 7 && adjustedCC == 128) {
      adjustedCC = 0;
      flags |= (1 << 2); // Use bit 2 of flags for Aftertouch indication
    }

    // Build the packed payload (starting after the version byte)
    final payload = [
      adjustedCC & 0x7F, // MIDI CC number or Note number
      flags & 0x7F, // Flags
      if (encodeVersion >= 2)
        midiFlags2 & 0x7F, // Flags2 (relative, toggle, is_note)
      ...encode16(midiMin), // Encode 'min' as 7-bit chunks
      ...encode16(midiMax), // Encode 'max' as 7-bit chunks
    ];

    return Uint8List.fromList(payload);
  }

  Uint8List encodeI2CPackedData() {
    final int encodeVersion = min(version, 8);

    var adjustedCC = i2cCC;

    // Compute the flags
    int flags =
        (i2cFlagsExtra & (encodeVersion >= 8 ? 0x78 : 0x7C)) |
        (isI2cEnabled ? 1 : 0) |
        (isI2cSymmetric ? 2 : 0) |
        (encodeVersion >= 8 && i2cIgnoreWhenBypassed ? 4 : 0);

    // Build the packed payload (starting after the version byte)
    final payload = [
      adjustedCC & 0x7F, // I2C control code
      if (encodeVersion >= 3) (adjustedCC >> 7) & 0x7F,
      flags & 0x7F, // Flags
      ...encode16(i2cMin), // Encode 'min' as 7-bit chunks
      ...encode16(i2cMax), // Encode 'max' as 7-bit chunks
    ];

    return Uint8List.fromList(payload);
  }

  // Convert back to Uint8List (excluding the version byte itself)
  Uint8List toBytes() {
    final int encodeVersion = min(version, 8);

    final cvBytes = encodeCVPackedData();
    final midiBytes = encodeMIDIPackedData();
    final i2cBytes = encodeI2CPackedData();

    final allBytes = [...cvBytes, ...midiBytes, ...i2cBytes];

    // Perf page byte only present in version exactly 5
    if (encodeVersion == 5) {
      final clampedIndex = perfPageIndex.clamp(0, 30);
      allBytes.add(clampedIndex & 0x7F);
    }

    return Uint8List.fromList(allBytes);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PackedMappingData) return false;

    return other.source == source &&
        other.cvInput == cvInput &&
        other.isUnipolar == isUnipolar &&
        other.isGate == isGate &&
        other.volts == volts &&
        other.delta == delta &&
        other.midiChannel == midiChannel &&
        other.midiMappingType == midiMappingType &&
        other.midiCC == midiCC &&
        other.isMidiEnabled == isMidiEnabled &&
        other.isMidiSymmetric == isMidiSymmetric &&
        other.isMidiRelative == isMidiRelative &&
        other.midiMin == midiMin &&
        other.midiMax == midiMax &&
        other.i2cCC == i2cCC &&
        other.isI2cEnabled == isI2cEnabled &&
        other.isI2cSymmetric == isI2cSymmetric &&
        other.i2cMin == i2cMin &&
        other.i2cMax == i2cMax &&
        other.perfPageIndex == perfPageIndex &&
        other.midiViewChange == midiViewChange &&
        other.midiIgnoreWhenBypassed == midiIgnoreWhenBypassed &&
        other.i2cIgnoreWhenBypassed == i2cIgnoreWhenBypassed &&
        other.cvFlagsExtra == cvFlagsExtra &&
        other.i2cFlagsExtra == i2cFlagsExtra &&
        other.unknownMidiMappingType == unknownMidiMappingType;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      midiViewChange,
      midiIgnoreWhenBypassed,
      i2cIgnoreWhenBypassed,
      cvFlagsExtra,
      i2cFlagsExtra,
      unknownMidiMappingType,
      source,
      cvInput,
      isUnipolar,
      isGate,
      volts,
      delta,
      midiChannel,
      midiMappingType,
      midiCC,
      isMidiEnabled,
      isMidiSymmetric,
      isMidiRelative,
      midiMin,
      midiMax,
      i2cCC,
      isI2cEnabled,
      isI2cSymmetric,
      i2cMin,
      Object.hash(i2cMax, perfPageIndex),
    ]);
  }

  bool isMapped() {
    return (cvInput > 0 || source > 0) || isMidiEnabled || isI2cEnabled;
  }

  bool isPerformance() {
    return perfPageIndex > 0;
  }

  PackedMappingData copyWith({
    int? source,
    int? cvInput,
    bool? isUnipolar,
    bool? isGate,
    int? volts,
    int? delta,
    int? midiChannel,
    MidiMappingType? midiMappingType,
    int? midiCC,
    bool? isMidiEnabled,
    bool? isMidiSymmetric,
    bool? isMidiRelative,
    int? midiMin,
    int? midiMax,
    int? i2cCC,
    bool? isI2cEnabled,
    bool? isI2cSymmetric,
    int? i2cMin,
    int? i2cMax,
    int? perfPageIndex,
    int? version,
    bool? midiViewChange,
    bool? midiIgnoreWhenBypassed,
    bool? i2cIgnoreWhenBypassed,
    int? cvFlagsExtra,
    int? i2cFlagsExtra,
  }) {
    return PackedMappingData(
      midiViewChange: midiViewChange ?? this.midiViewChange,
      midiIgnoreWhenBypassed:
          midiIgnoreWhenBypassed ?? this.midiIgnoreWhenBypassed,
      i2cIgnoreWhenBypassed:
          i2cIgnoreWhenBypassed ?? this.i2cIgnoreWhenBypassed,
      cvFlagsExtra: cvFlagsExtra ?? this.cvFlagsExtra,
      i2cFlagsExtra: i2cFlagsExtra ?? this.i2cFlagsExtra,
      unknownMidiMappingType: midiMappingType == null
          ? unknownMidiMappingType
          : null,
      source: source ?? this.source,
      cvInput: cvInput ?? this.cvInput,
      isUnipolar: isUnipolar ?? this.isUnipolar,
      isGate: isGate ?? this.isGate,
      volts: volts ?? this.volts,
      delta: delta ?? this.delta,
      midiChannel: midiChannel ?? this.midiChannel,
      midiMappingType: midiMappingType ?? this.midiMappingType,
      midiCC: midiCC ?? this.midiCC,
      isMidiEnabled: isMidiEnabled ?? this.isMidiEnabled,
      isMidiSymmetric: isMidiSymmetric ?? this.isMidiSymmetric,
      isMidiRelative: isMidiRelative ?? this.isMidiRelative,
      midiMin: midiMin ?? this.midiMin,
      midiMax: midiMax ?? this.midiMax,
      i2cCC: i2cCC ?? this.i2cCC,
      isI2cEnabled: isI2cEnabled ?? this.isI2cEnabled,
      isI2cSymmetric: isI2cSymmetric ?? this.isI2cSymmetric,
      i2cMin: i2cMin ?? this.i2cMin,
      i2cMax: i2cMax ?? this.i2cMax,
      perfPageIndex: perfPageIndex ?? this.perfPageIndex,
      version: version ?? this.version,
    );
  }
}
