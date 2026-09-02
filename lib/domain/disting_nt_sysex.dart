import 'package:nt_helper/models/packed_mapping_data.dart';
import 'dart:typed_data';

/// The MIDI SysEx reference for Expert Sleepers.
const List<int> kExpertSleepersManufacturerId = [0x00, 0x21, 0x27];

/// The byte that identifies this is a disting NT message.
const int kDistingNTPrefix = 0x6D;

/// Start and end markers for SysEx messages.
const int kSysExStart = 0xF0;
const int kSysExEnd = 0xF7;

abstract class HasAlgorithmIndex {
  int get algorithmIndex;
}

abstract class HasParameterNumber {
  int get parameterNumber;
}

enum DisplayMode {
  parameters(0),
  algorithmUI(1),
  overview(2),
  overviewVUs(3);

  final int value;

  const DisplayMode(this.value);
}

class Specification {
  final String name;
  final int min;
  final int max;
  final int defaultValue;
  final int type;

  Specification({
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'min': min,
    'max': max,
    'defaultValue': defaultValue,
    'type': type,
  };

  factory Specification.fromJson(Map<String, dynamic> json) => Specification(
    name: json['name'] as String,
    min: json['min'] as int,
    max: json['max'] as int,
    defaultValue: json['defaultValue'] as int,
    type: json['type'] as int,
  );

  int get safeDefaultValue {
    if (defaultValue >= min && defaultValue <= max) {
      return defaultValue;
    }
    return ((min + max) ~/ 2).clamp(min, max);
  }

  @override
  String toString() {
    return "Specification: min=$min, max=$max, defaultValue=$defaultValue, type=$type";
  }
}

class NumParameters implements HasAlgorithmIndex {
  @override
  final int algorithmIndex;
  final int numParameters;

  NumParameters({required this.algorithmIndex, required this.numParameters});

  @override
  String toString() {
    return "NumParameters: index=$algorithmIndex numParameters=$numParameters";
  }
}

class ParameterInfo implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber;
  final int min;
  final int max;
  final int defaultValue;
  final int unit;
  final String name;
  final int powerOfTen;
  final int ioFlags;

  ParameterInfo({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.unit,
    required this.name,
    required this.powerOfTen,
    this.ioFlags = 0,
  });

  /// I/O flag helper getters
  /// Bit 0: Parameter is an input
  bool get isInput => (ioFlags & 1) != 0;

  /// Bit 1: Parameter is an output
  bool get isOutput => (ioFlags & 2) != 0;

  /// Bit 2: Audio signal (true) vs CV signal (false)
  bool get isAudio => (ioFlags & 4) != 0;

  /// Bit 3: Parameter controls output mode
  bool get isOutputMode => (ioFlags & 8) != 0;

  /// Factory constructor for default `filler` instance
  factory ParameterInfo.filler() {
    return ParameterInfo(
      algorithmIndex: -1,
      parameterNumber: -1,
      min: 0,
      max: 0,
      defaultValue: 0,
      unit: 0,
      name: '',
      powerOfTen: 0,
    );
  }

  @override
  String toString() {
    return "ParameterInfo: min=$min, max=$max, defaultValue=$defaultValue, unit=$unit, name=$name, powerOfTen=$powerOfTen, ioFlags=$ioFlags";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;

    return other is ParameterInfo &&
        other.algorithmIndex == algorithmIndex &&
        other.parameterNumber == parameterNumber &&
        other.min == min &&
        other.max == max &&
        other.defaultValue == defaultValue &&
        other.unit == unit &&
        other.name == name &&
        other.powerOfTen == powerOfTen &&
        other.ioFlags == ioFlags;
  }

  @override
  int get hashCode => Object.hash(
    algorithmIndex,
    parameterNumber,
    min,
    max,
    defaultValue,
    unit,
    name,
    powerOfTen,
    ioFlags,
  );

  String? getUnitString(List<String> units) {
    if (unit <= 0 || unit > units.length) return null;
    return units[unit - 1];
  }
}

class ParameterValue implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber;
  final int value;
  final bool isDisabled;

  ParameterValue({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.value,
    this.isDisabled = false,
  });

  /// Factory constructor for default `filler` instance
  factory ParameterValue.filler() {
    return ParameterValue(algorithmIndex: -1, parameterNumber: -1, value: 0);
  }

  @override
  String toString() {
    return "ParameterValue(algorithmIndex=$algorithmIndex, parameterNumber=$parameterNumber, value=$value, isDisabled=$isDisabled)";
  }

  /// Override == operator for equality comparison
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is! ParameterValue) return false;

    return algorithmIndex == other.algorithmIndex &&
        parameterNumber == other.parameterNumber &&
        value == other.value &&
        isDisabled == other.isDisabled;
  }

  /// Override hashCode for using instances in hash-based collections
  @override
  int get hashCode =>
      Object.hash(algorithmIndex, parameterNumber, value, isDisabled);
}

class ParameterEnumStrings implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber;
  final List<String> values;

  ParameterEnumStrings({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.values,
  });

  factory ParameterEnumStrings.filler() {
    return ParameterEnumStrings(
      algorithmIndex: -1,
      parameterNumber: -1,
      values: List.empty(),
    );
  }

  @override
  String toString() {
    return "ParameterEnumStrings(algorithmIndex: $algorithmIndex, parameterNumber: $parameterNumber, values: $values)";
  }
}

class ParameterValueString implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber;
  final String value;

  ParameterValueString({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.value,
  });

  factory ParameterValueString.filler() {
    return ParameterValueString(
      algorithmIndex: -1,
      parameterNumber: -1,
      value: '',
    );
  }

  @override
  String toString() {
    return "ParameterValueString(algorithmIndex: $algorithmIndex, parameterNumber: $parameterNumber, value: $value)";
  }
}

class AllParameterValues implements HasAlgorithmIndex {
  @override
  final int algorithmIndex;
  final List<ParameterValue> values;

  AllParameterValues({required this.algorithmIndex, required this.values});

  @override
  String toString() {
    return "AllParameterValues: index=$algorithmIndex values=$values";
  }
}

class Mapping implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber;
  final PackedMappingData packedMappingData;

  const Mapping({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.packedMappingData,
  });

  factory Mapping.filler() {
    return Mapping(
      algorithmIndex: -1,
      parameterNumber: -1,
      packedMappingData: PackedMappingData.filler(),
    );
  }
}

class ParameterPage {
  final String name;
  final List<int> parameters;

  ParameterPage({required this.name, required this.parameters});
}

class ParameterPages implements HasAlgorithmIndex {
  @override
  final int algorithmIndex;
  final List<ParameterPage> pages;

  ParameterPages({required this.algorithmIndex, required this.pages});
}

class AlgorithmInfo {
  final int algorithmIndex;
  final String name;
  final String guid;
  final List<Specification> specifications;
  final bool isPlugin;
  final bool isLoaded;
  final String? filename; // Path to the algorithm file (for plugins)

  AlgorithmInfo({
    required this.algorithmIndex,
    required this.name,
    required this.guid,
    required this.specifications,
    this.isPlugin = false,
    this.isLoaded = true,
    this.filename,
  });

  int get numSpecifications {
    return specifications.length;
  }

  Map<String, dynamic> toJson() => {
    'algorithmIndex': algorithmIndex,
    'name': name,
    'guid': guid,
    'specifications': specifications.map((s) => s.toJson()).toList(),
    'isPlugin': isPlugin,
    'isLoaded': isLoaded,
    'filename': filename,
  };

  factory AlgorithmInfo.fromJson(Map<String, dynamic> json) => AlgorithmInfo(
    algorithmIndex: json['algorithmIndex'] as int,
    name: json['name'] as String,
    guid: json['guid'] as String,
    specifications: (json['specifications'] as List)
        .map((s) => Specification.fromJson(s as Map<String, dynamic>))
        .toList(),
    isPlugin: json['isPlugin'] as bool? ?? false,
    isLoaded: json['isLoaded'] as bool? ?? true,
    filename: json['filename'] as String?,
  );

  @override
  String toString() {
    return "AlgorithmInfo: name=$name, guid=$guid, specs=$specifications, isPlugin=$isPlugin, isLoaded=$isLoaded, filename=$filename";
  }
}

enum AlgorithmVisualBracket {
  none(0),
  open(1),
  close(2),
  line(3),
  openAndClose(4);

  final int value;

  const AlgorithmVisualBracket(this.value);

  static AlgorithmVisualBracket? tryFromValue(int value) {
    for (final bracket in values) {
      if (bracket.value == value) return bracket;
    }
    return null;
  }
}

/// Controls how an algorithm is drawn in the disting NT overview.
///
/// Firmware 1.18 introduced version 1 of this payload. Indents are measured
/// in the module's overview-layout units and are limited to 0-15.
class AlgorithmVisualStyle {
  static const int currentVersion = 1;

  final int version;
  final int leftIndent;
  final int rightIndent;
  final bool lineAbove;
  final bool lineBelow;
  final AlgorithmVisualBracket bracket;

  const AlgorithmVisualStyle({
    this.version = currentVersion,
    this.leftIndent = 0,
    this.rightIndent = 0,
    this.lineAbove = false,
    this.lineBelow = false,
    this.bracket = AlgorithmVisualBracket.none,
  }) : assert(leftIndent >= 0 && leftIndent <= 15),
       assert(rightIndent >= 0 && rightIndent <= 15);

  bool get isDecorated =>
      leftIndent != 0 ||
      rightIndent != 0 ||
      lineAbove ||
      lineBelow ||
      bracket != AlgorithmVisualBracket.none;

  static AlgorithmVisualStyle? tryParse(List<int> data, int offset) {
    if (offset < 0 || data.length < offset + 6) return null;
    if (data[offset] != currentVersion) return null;

    final leftIndent = data[offset + 1];
    final rightIndent = data[offset + 2];
    final bracket = AlgorithmVisualBracket.tryFromValue(data[offset + 5]);
    if (leftIndent > 15 || rightIndent > 15 || bracket == null) return null;

    return AlgorithmVisualStyle(
      leftIndent: leftIndent,
      rightIndent: rightIndent,
      lineAbove: data[offset + 3] != 0,
      lineBelow: data[offset + 4] != 0,
      bracket: bracket,
    );
  }

  List<int> encodePayload() => [
    version,
    leftIndent,
    rightIndent,
    lineAbove ? 1 : 0,
    lineBelow ? 1 : 0,
    bracket.value,
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlgorithmVisualStyle &&
          version == other.version &&
          leftIndent == other.leftIndent &&
          rightIndent == other.rightIndent &&
          lineAbove == other.lineAbove &&
          lineBelow == other.lineBelow &&
          bracket == other.bracket;

  @override
  int get hashCode => Object.hash(
    version,
    leftIndent,
    rightIndent,
    lineAbove,
    lineBelow,
    bracket,
  );
}

class Algorithm {
  final int algorithmIndex;
  final String guid;
  final String name;
  final List<int> specifications;
  final AlgorithmVisualStyle? visualStyle;

  Algorithm({
    required this.algorithmIndex,
    required this.guid,
    required this.name,
    this.specifications = const [],
    this.visualStyle,
  });

  Algorithm copyWith({
    int? algorithmIndex,
    String? name,
    List<int>? specifications,
    AlgorithmVisualStyle? visualStyle,
  }) {
    return Algorithm(
      algorithmIndex: algorithmIndex ?? this.algorithmIndex,
      guid: guid,
      name: name ?? this.name,
      specifications: specifications ?? this.specifications,
      visualStyle: visualStyle ?? this.visualStyle,
    );
  }
}

class RoutingInfo implements HasAlgorithmIndex {
  @override
  final int algorithmIndex;
  final List<int> routingInfo;

  RoutingInfo({required this.algorithmIndex, required this.routingInfo});

  factory RoutingInfo.filler() {
    return RoutingInfo(algorithmIndex: -1, routingInfo: List.filled(6, 0));
  }
}

/// Output mode usage data returned by SysEx 0x55 response.
/// Describes which parameters are affected by an output mode control parameter.
class OutputModeUsage implements HasAlgorithmIndex, HasParameterNumber {
  @override
  final int algorithmIndex;
  @override
  final int parameterNumber; // The source parameter (mode control)
  final List<int>
  affectedParameterNumbers; // Parameters controlled by this mode

  OutputModeUsage({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.affectedParameterNumbers,
  });

  @override
  String toString() {
    return "OutputModeUsage(algorithmIndex=$algorithmIndex, parameterNumber=$parameterNumber, affectedParameters=$affectedParameterNumbers)";
  }
}

/// Enum of all known 'Sent SysEx messages' (requests)
enum DistingNTRequestMessageType {
  // Sent messages (going TO the disting)
  takeScreenshot(0x01),
  setRealTimeClock(0x04),
  wake(0x07),
  executeLua(0x08),
  installLua(0x09),
  sclFile(0x11),
  kbmFile(0x12),
  setDisplayMode(0x20),
  requestVersionString(0x22),
  requestNumAlgorithms(0x30),
  requestAlgorithmInfo(0x31),
  addAlgorithm(0x32),
  removeAlgorithm(0x33),
  loadPreset(0x34),
  newPreset(0x35),
  savePreset(0x36),
  moveAlgorithm(0x37),
  loadPlugin(0x38),
  requestAlgorithm(0x40),
  requestPresetName(0x41),
  requestNumParameters(0x42),
  requestParameterInfo(0x43),
  requestAllParameterValues(0x44),
  requestParameterValue(0x45),
  setParameterValue(0x46),
  setPresetName(0x47),
  requestUnitStrings(0x48),
  requestEnumStrings(0x49),
  setFocus(0x4A),
  requestMappings(0x4B),
  setMapping(0x4D),
  setMidiMapping(0x4E),
  setI2CMapping(0x4F),
  requestParameterValueString(0x50),
  setSlotName(0x51),
  requestParameterPages(0x52),
  setParameterString(0x53),

  /// Legacy pre-1.16 performance-page mapping command.
  setPerformancePageMapping(0x54),

  /// Firmware 1.18+ reuses 0x54 for algorithm overview styling.
  setAlgorithmVisualStyle(0x54),

  /// Request output mode usage for a parameter (SysEx 0x55)
  requestOutputModeUsage(0x55),

  /// Request performance page item (SysEx 0x57, firmware v1.16+)
  requestPerfPageItem(0x57),

  /// Set performance page item (SysEx 0x58, firmware v1.16+)
  setPerfPageItem(0x58),
  requestNumAlgorithmsInPreset(0x60),
  requestRouting(0x61),
  requestCpuUsage(0x62),
  sdCardOperation(0x7A),
  reboot(0x7F),

  // Unknown/unsupported
  unknown(0xFF);

  final int value;

  const DistingNTRequestMessageType(this.value);

  /// Retrieve the enum variant from a raw message byte, if known.
  static DistingNTRequestMessageType fromByte(int b) {
    for (final t in DistingNTRequestMessageType.values) {
      if (t.value == b) return t;
    }
    return DistingNTRequestMessageType.unknown;
  }
}

/// Enum of all known 'Received
/// SysEx messages' (responses)
enum DistingNTRespMessageType {
  // Sent messages (coming FROM the disting)
  // (Some are the same IDs, but used as a response.)
  respLuaOutput(0x09),
  respNumAlgorithms(0x30),
  respAlgorithmInfo(0x31),
  respMessage(0x32),
  respScreenshot(0x33),
  respAlgorithm(0x40),
  respPresetName(0x41),
  respNumParameters(0x42),
  respParameterInfo(0x43),
  respAllParameterValues(0x44),
  respParameterValue(0x45),
  respUnitStrings(0x48),
  respEnumStrings(0x49),
  respMapping(0x4B),
  respParameterValueString(0x50),
  respParameterPages(0x52),

  /// Response to output mode usage query (SysEx 0x55)
  /// Returns list of parameters affected by an output mode control parameter
  respOutputModeUsage(0x55),

  /// Response to performance page item request (SysEx 0x57, firmware v1.16+)
  respPerfPageItem(0x57),
  respNumAlgorithmsInPreset(0x60),
  respRouting(0x61),
  respCpuUsage(0x62),

  // SD Card responses (virtual, mapped from 0x7A by the parser)
  respDirectoryListing(0x7A),
  respFileChunk(0x7C),
  respSdStatus(0x7D),

  // Unknown/unsupported
  unknown(0xFF);

  final int value;

  const DistingNTRespMessageType(this.value);

  /// Retrieve the enum variant from a raw message byte, if known.
  static DistingNTRespMessageType fromByte(int b) {
    for (final t in DistingNTRespMessageType.values) {
      if (t.value == b) return t;
    }
    return DistingNTRespMessageType.unknown;
  }
}

class DistingNTSysExMessage {
  final DistingNTRespMessageType messageType;
  final Uint8List payload;

  const DistingNTSysExMessage({
    required this.messageType,
    required this.payload,
  });

  factory DistingNTSysExMessage.fromResponse(
    DistingNTRespMessageType responseMessageType,
    Uint8List response,
  ) {
    final messageType = responseMessageType;
    // In the original, the payload started from index 6 (0x7A).
    // Now, it should start from index 9 (after 0x7A, status, and command).
    // And it should end before the checksum and the F7 byte.
    // The Javascript `data.slice(9, -1)` means it goes from index 9 up to
    // (but not including) the last element. The last element in the raw MIDI message is 0xF7.
    // The element before 0xF7 is the checksum. So, -1 excludes F7, and the checksum is
    // also excluded.
    final payload = Uint8List.fromList(
      response.sublist(9, response.length - 1),
    );

    return DistingNTSysExMessage(messageType: messageType, payload: payload);
  }
}
