import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/disting_cubit.dart' show Slot;
import 'package:nt_helper/domain/disting_nt_sysex.dart' show ParameterInfo;
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/widgets/file_parameter_editor.dart';

/// Modes for different types of file/string parameter selection
enum FileSelectionMode {
  /// Select folder only (e.g., sample folder selection)
  folderOnly,

  /// Select file only (e.g., sample file within folder)
  fileOnly,

  /// Direct file selection (e.g., script files)
  directFile,

  /// Folder then file hierarchy (e.g., samples workflow)
  folderThenFile,

  /// Free text input (e.g., mixer channel names)
  textInput,
}

/// Parameter unit scheme based on firmware version
/// The unit numbers changed in firmware 1.13.0
enum ParameterUnitScheme {
  /// Legacy firmware (≤1.12): 13=file paths, 14=file/folder, 17=text input
  legacy,

  /// Modern firmware (≥1.13): 16=hasStrings, 17=confirm, 18=text input
  /// Based on kNT_parameterUnit enum from firmware
  modern,
}

/// Unit constants for each firmware scheme
class ParameterUnits {
  // Common across all firmware versions
  static const int enum_ =
      1; // kNT_unitEnum - enumStrings must also be provided

  // Legacy firmware (≤1.12)
  static const int legacyFilePath = 13;
  static const int legacyFileFolder = 14;
  static const int legacyTextInput = 17;

  // Modern firmware (≥1.13) - matches kNT_parameterUnit enum
  static const int modernVolts = 13;
  static const int modernBPM = 14;
  static const int modernDegrees = 15;
  static const int modernHasStrings =
      16; // Calls the algorithm's parameterString() callback
  static const int modernConfirm =
      17; // Confirms changes and calls parameterString()
  static const int modernTextInput =
      18; // Factory text input, including mixer channel names

  /// Get the unit scheme for a given firmware version
  static ParameterUnitScheme schemeFor(FirmwareVersion? version) {
    if (version == null) return ParameterUnitScheme.modern;
    // 1.13.0 and above use modern scheme
    if (version.major > 1 || (version.major == 1 && version.minor >= 13)) {
      return ParameterUnitScheme.modern;
    }
    return ParameterUnitScheme.legacy;
  }

  /// Check if a unit is a string-type unit that should hide the unit display
  static bool isStringTypeUnit(int unit, ParameterUnitScheme scheme) {
    switch (scheme) {
      case ParameterUnitScheme.legacy:
        return unit == legacyFilePath ||
            unit == legacyFileFolder ||
            unit == legacyTextInput;
      case ParameterUnitScheme.modern:
        return unit == modernHasStrings ||
            unit == modernConfirm ||
            unit == modernTextInput;
    }
  }

  /// Check if a unit is a BPM unit that should use the BPM editor
  /// Modern firmware (≥1.13): unit 14 = kNT_unitBPM
  /// Legacy firmware (≤1.12): detected via unit string containing "BPM"
  static bool isBpmUnit(
    int unit,
    String? unitString,
    ParameterUnitScheme scheme,
  ) {
    switch (scheme) {
      case ParameterUnitScheme.legacy:
        // Legacy firmware: check the unit string
        return unitString?.toUpperCase().contains('BPM') ?? false;
      case ParameterUnitScheme.modern:
        // Modern firmware: unit 14 = BPM
        return unit == modernBPM;
    }
  }
}

/// Rule definition for parameter editor selection
class ParameterEditorRule {
  /// Algorithm GUID to match (null = any algorithm)
  final String? algorithmGuid;

  /// Parameter name pattern to match (supports regex)
  final String? parameterNamePattern;

  /// Unit types to match (null = any unit)
  final List<int>? units;

  /// Base directory for file selection
  final String? baseDirectory;

  /// File selection mode
  final FileSelectionMode mode;

  /// Directories to exclude from selection
  final List<String> excludeDirs;

  /// File extensions to filter (null = all files)
  final List<String>? allowedExtensions;

  /// Description for debugging/logging
  final String description;

  /// Whether to search subdirectories recursively
  final bool recursive;

  /// Default folder to select (relative to baseDirectory)
  final String? defaultFolder;

  /// Match the NT's recursive /samples folder numbering.
  final bool ntSampleFolderEnumeration;

  /// Whether the parameter range is the exact live folder catalogue size.
  /// Some built-in algorithms expose a fixed dynamic ceiling (for example
  /// 0-999), so range validation must only be enabled for contracts that
  /// report the discovered catalogue count.
  final bool ntSampleFolderCountFromRange;

  /// Optional label for a value-0 sentinel before real file entries.
  final String? zeroValueSentinelLabel;

  const ParameterEditorRule({
    this.algorithmGuid,
    this.parameterNamePattern,
    this.units,
    this.baseDirectory,
    required this.mode,
    this.excludeDirs = const [],
    this.allowedExtensions,
    required this.description,
    this.recursive = false,
    this.defaultFolder,
    this.ntSampleFolderEnumeration = false,
    this.ntSampleFolderCountFromRange = false,
    this.zeroValueSentinelLabel,
  });

  /// Check if this rule matches the given parameter
  bool matches({
    required String algorithmGuid,
    required String parameterName,
    required int unit,
  }) {
    // Check algorithm GUID
    if (this.algorithmGuid != null && this.algorithmGuid != algorithmGuid) {
      return false;
    }

    // Check unit
    if (units != null && !units!.contains(unit)) {
      return false;
    }

    // Check parameter name pattern
    if (parameterNamePattern != null) {
      final regex = RegExp(parameterNamePattern!);
      if (!regex.hasMatch(parameterName)) {
        return false;
      }
    }

    return true;
  }
}

/// Registry for finding appropriate parameter editors based on algorithm and parameter context
class ParameterEditorRegistry {
  /// Current unit scheme (set when connecting to device)
  static ParameterUnitScheme _currentScheme = ParameterUnitScheme.modern;

  /// Set the unit scheme based on firmware version
  static void setFirmwareVersion(FirmwareVersion? version) {
    _currentScheme = ParameterUnits.schemeFor(version);
  }

  /// Get current scheme (for testing)
  static ParameterUnitScheme get currentScheme => _currentScheme;

  /// All file/string parameter units across both firmware schemes
  static const _fileUnits = [
    ParameterUnits.legacyFilePath,
    ParameterUnits.legacyFileFolder,
    ParameterUnits.modernHasStrings,
    ParameterUnits.modernConfirm,
  ];

  /// Units for folder-based parameters
  static const _folderUnits = [
    ParameterUnits.legacyFileFolder,
    ParameterUnits.modernHasStrings,
  ];

  /// Units used by sample selectors. Modern NT sample parameters use Confirm,
  /// while older and built-in algorithms may still expose HasStrings.
  static const _sampleUnits = [
    ParameterUnits.legacyFileFolder,
    ParameterUnits.modernHasStrings,
    ParameterUnits.modernConfirm,
  ];

  /// Units for path-based parameters (programs, convolver)
  static const _pathUnits = [
    ParameterUnits.legacyFilePath,
    ParameterUnits.modernConfirm,
  ];

  /// Units for text input
  static const _textUnits = [
    ParameterUnits.legacyTextInput,
    ParameterUnits.modernTextInput,
  ];

  static const _ntSampleCatalogueFolderRule = ParameterEditorRule(
    parameterNamePattern: r'^Folder$',
    units: [ParameterUnits.modernHasStrings],
    baseDirectory: '/samples',
    mode: FileSelectionMode.folderOnly,
    description: 'NT sample catalogue folder selection',
    ntSampleFolderEnumeration: true,
    ntSampleFolderCountFromRange: true,
  );

  static const _ntSampleCatalogueSampleRule = ParameterEditorRule(
    parameterNamePattern: r'^Sample$',
    units: [ParameterUnits.modernConfirm],
    baseDirectory: '/samples',
    mode: FileSelectionMode.fileOnly,
    allowedExtensions: ['.wav', '.aif', '.aiff'],
    description: 'NT sample catalogue file selection',
    ntSampleFolderEnumeration: true,
    ntSampleFolderCountFromRange: true,
  );

  /// Unified rules for all firmware versions
  static final List<ParameterEditorRule> _rules = [
    // Poly Multisample - NT enumerates folders recursively under /samples.
    ParameterEditorRule(
      algorithmGuid: 'pymu',
      parameterNamePattern: r'^Folder$',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      description: 'Poly Multisample folder selection',
      ntSampleFolderEnumeration: true,
    ),
    ParameterEditorRule(
      algorithmGuid: 'pymu',
      parameterNamePattern: r'^Sample$',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Poly Multisample sample selection',
      ntSampleFolderEnumeration: true,
      zeroValueSentinelLabel: 'Multisample',
    ),
    ParameterEditorRule(
      algorithmGuid: 'pyms',
      parameterNamePattern: r'^Folder$',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      description: 'Poly Multisample legacy folder selection',
      ntSampleFolderEnumeration: true,
    ),
    ParameterEditorRule(
      algorithmGuid: 'pyms',
      parameterNamePattern: r'^Sample$',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Poly Multisample legacy sample selection',
      ntSampleFolderEnumeration: true,
      zeroValueSentinelLabel: 'Multisample',
    ),

    // Qualified sample parameters following the current NT sample-player
    // contract. The unit gates keep arbitrary string-valued parameters out.
    ParameterEditorRule(
      parameterNamePattern: r'^(Kick|Snare|Perc|Hat|Crash) sample$',
      units: [ParameterUnits.modernConfirm],
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Role sample selection with None sentinel',
      ntSampleFolderEnumeration: true,
      zeroValueSentinelLabel: 'None',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'^.+ [Ff]older$',
      units: [ParameterUnits.modernHasStrings],
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      description: 'Qualified sample folder selection',
      ntSampleFolderEnumeration: true,
    ),
    ParameterEditorRule(
      parameterNamePattern: r'^.+ [Ss]ample$',
      units: [ParameterUnits.modernConfirm],
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Qualified sample file selection',
      ntSampleFolderEnumeration: true,
    ),

    // Sample player - Folder selection
    ParameterEditorRule(
      algorithmGuid: 'samp',
      parameterNamePattern: r'.*:Folder',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      description: 'Sample player folder selection',
    ),
    ParameterEditorRule(
      algorithmGuid: 'samp',
      parameterNamePattern: r'.*:Sample',
      units: _sampleUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Sample player file selection',
    ),

    // Generic folder/sample
    ParameterEditorRule(
      parameterNamePattern: r'^Folder$',
      units: _folderUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      description: 'Generic folder selection',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'^Sample$',
      units: _sampleUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Generic sample selection',
    ),

    // Convolver
    ParameterEditorRule(
      algorithmGuid: 'conv',
      parameterNamePattern: r'Folder',
      units: _fileUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.folderOnly,
      defaultFolder: 'impulses',
      description: 'Convolver impulse folder selection',
    ),
    ParameterEditorRule(
      algorithmGuid: 'conv',
      parameterNamePattern: r'Sample',
      units: _fileUnits,
      baseDirectory: '/samples',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.wav', '.aif', '.aiff'],
      description: 'Convolver impulse file selection',
    ),

    // Lua Script
    ParameterEditorRule(
      algorithmGuid: 'lua ',
      parameterNamePattern: r'Program',
      units: _pathUnits,
      baseDirectory: '/programs/lua',
      mode: FileSelectionMode.directFile,
      excludeDirs: ['libs'],
      allowedExtensions: ['.lua'],
      description: 'Lua script program selection',
    ),

    // Three Pot
    ParameterEditorRule(
      algorithmGuid: 'spin',
      parameterNamePattern: r'Program',
      units: _pathUnits,
      baseDirectory: '/programs/three_pot',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.3pot'],
      recursive: true,
      description: 'Three Pot program selection',
    ),

    // Wavetable
    ParameterEditorRule(
      algorithmGuid: 'vcot',
      parameterNamePattern: r'.*[Ww]avetable.*',
      units: [..._fileUnits, ParameterUnits.enum_],
      baseDirectory: '/wavetables',
      mode: FileSelectionMode.folderOnly,
      description: 'VCO Wavetable folder selection',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'.*[Ww]avetable.*',
      units: [..._fileUnits, ParameterUnits.enum_],
      baseDirectory: '/wavetables',
      mode: FileSelectionMode.folderOnly,
      description: 'Wavetable folder selection',
    ),

    // Multisample
    ParameterEditorRule(
      parameterNamePattern: r'.*[Mm]ultisample.*',
      units: _folderUnits,
      baseDirectory: '/multisamples',
      mode: FileSelectionMode.folderOnly,
      description: 'Multisample folder selection',
    ),

    // Tuner files
    ParameterEditorRule(
      parameterNamePattern: r'.*\.scl',
      units: _fileUnits,
      baseDirectory: '/scl',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.scl'],
      description: 'Scala scale file selection',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'.*\.kbm',
      units: _fileUnits,
      baseDirectory: '/scl',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.kbm'],
      description: 'Scala keyboard mapping file selection',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'.*\.syx',
      units: _fileUnits,
      baseDirectory: '/mts',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.syx'],
      description: 'MTS tuning file selection',
    ),

    // Community plugin tuning files
    ParameterEditorRule(
      parameterNamePattern: r'(?:Scl|Scale)\s*[Ff]ile',
      units: _fileUnits,
      baseDirectory: '/scl',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.scl'],
      description: 'Community plugin scala file selection',
    ),
    ParameterEditorRule(
      parameterNamePattern: r'(?:Kbm|Keyboard mapping)\s*[Ff]ile',
      units: _fileUnits,
      baseDirectory: '/scl',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.kbm'],
      description: 'Community plugin keyboard mapping file selection',
    ),

    // Poly FM
    ParameterEditorRule(
      algorithmGuid: 'pyfm',
      parameterNamePattern: r'Bank',
      units: _folderUnits,
      baseDirectory: '/FMSYX',
      mode: FileSelectionMode.directFile,
      allowedExtensions: ['.syx'],
      recursive: false,
      description: 'Poly FM bank selection',
    ),

    // MIDI Player
    ParameterEditorRule(
      algorithmGuid: 'midp',
      parameterNamePattern: r'Folder',
      units: _fileUnits,
      baseDirectory: '/MIDI',
      mode: FileSelectionMode.folderOnly,
      description: 'MIDI Player folder selection',
    ),
    ParameterEditorRule(
      algorithmGuid: 'midp',
      parameterNamePattern: r'File',
      units: _fileUnits,
      baseDirectory: '/MIDI',
      mode: FileSelectionMode.fileOnly,
      allowedExtensions: ['.mid', '.midi'],
      description: 'MIDI Player file selection',
    ),

    // Text input
    ParameterEditorRule(
      parameterNamePattern: r'.*[Nn]ame.*',
      units: _textUnits,
      mode: FileSelectionMode.textInput,
      description: 'Editable text parameter',
    ),
    ParameterEditorRule(
      units: _textUnits,
      mode: FileSelectionMode.textInput,
      description: 'Generic text input parameter',
    ),
  ];

  /// Find appropriate parameter editor for the given context
  /// Returns null if no special editor is needed (falls back to default slider/+- editor)
  static Widget? findEditorFor({
    required Slot slot,
    required ParameterInfo parameterInfo,
    required int parameterNumber,
    required int currentValue,
    required Function(int) onValueChanged,
  }) {
    final algorithmGuid = slot.algorithm.guid;
    final parameterName = parameterInfo.name;
    final unit = parameterInfo.unit;

    // An exact Folder/HasStrings + Sample/Confirm pair is the NT sample
    // catalogue contract used by current sample-based algorithms. The pair is
    // important: either unit alone is also used for unrelated strings/actions.
    final pairedCatalogueRule = _pairedNtSampleCatalogueRule(
      slot,
      parameterInfo,
    );
    if (pairedCatalogueRule != null) {
      return FileParameterEditor(
        slot: slot,
        parameterInfo: parameterInfo,
        parameterNumber: parameterNumber,
        currentValue: currentValue,
        onValueChanged: onValueChanged,
        rule: pairedCatalogueRule,
      );
    }

    // Find first matching rule
    for (final rule in _rules) {
      if (rule.matches(
        algorithmGuid: algorithmGuid,
        parameterName: parameterName,
        unit: unit,
      )) {
        // Return appropriate editor widget based on rule
        return FileParameterEditor(
          slot: slot,
          parameterInfo: parameterInfo,
          parameterNumber: parameterNumber,
          currentValue: currentValue,
          onValueChanged: onValueChanged,
          rule: rule,
        );
      }
    }

    return null; // No special editor needed
  }

  static ParameterEditorRule? _pairedNtSampleCatalogueRule(
    Slot slot,
    ParameterInfo parameterInfo,
  ) {
    final hasFolder = slot.parameters.any(
      (parameter) =>
          parameter.name == 'Folder' &&
          parameter.unit == ParameterUnits.modernHasStrings,
    );
    final hasSample = slot.parameters.any(
      (parameter) =>
          parameter.name == 'Sample' &&
          parameter.unit == ParameterUnits.modernConfirm,
    );
    if (!hasFolder || !hasSample) return null;

    if (parameterInfo.name == 'Folder' &&
        parameterInfo.unit == ParameterUnits.modernHasStrings) {
      return _ntSampleCatalogueFolderRule;
    }
    if (parameterInfo.name == 'Sample' &&
        parameterInfo.unit == ParameterUnits.modernConfirm) {
      return _ntSampleCatalogueSampleRule;
    }
    return null;
  }

  /// Check if a unit is a string-type unit that should hide the unit display
  static bool isStringTypeUnit(int unit) {
    return ParameterUnits.isStringTypeUnit(unit, _currentScheme);
  }

  /// Check if a unit is a BPM unit that should use the BPM editor
  /// For modern firmware, only unit number is needed.
  /// For legacy firmware, the unit string is checked for "BPM".
  static bool isBpmUnit(int unit, {String? unitString}) {
    return ParameterUnits.isBpmUnit(unit, unitString, _currentScheme);
  }

  /// Get all registered rules (for debugging/testing)
  static List<ParameterEditorRule> get rules => List.unmodifiable(_rules);
}
