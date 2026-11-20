import 'dart:convert';
import 'dart:typed_data';

import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

class TemplateShareService {
  static const exportType = 'nt_helper_template';
  static const exportVersion = 2;

  final AppDatabase database;

  TemplateShareService(this.database);

  String encodeTemplate(FullPresetDetails template) {
    final payload = {
      'exportType': exportType,
      'exportVersion': exportVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'template': {
        'name': template.preset.name,
        'category': template.preset.category,
        'templateMetadata': template.preset.templateMetadata,
        'slots': [
          for (final slot in template.slots)
            {
              'slotIndex': slot.slot.slotIndex,
              'algorithm': {
                'guid': slot.algorithm.guid,
                'name': slot.algorithm.name,
                'numSpecifications': slot.algorithm.numSpecifications,
                'pluginFilePath': slot.algorithm.pluginFilePath,
              },
              'customName': slot.slot.customName,
              'specifications': slot.specificationValues,
              'parameterValues': _intKeyMap(slot.parameterValues),
              'parameterStringValues': _intKeyMap(slot.parameterStringValues),
              'mappings': {
                for (final entry in slot.mappings.entries)
                  entry.key.toString(): _encodeMapping(entry.value),
              },
              'routing': slot.routing?.routingInfoJson,
            },
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<int> importTemplate(String jsonText) async {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Template JSON must be an object.');
    }
    if (decoded['exportType'] != exportType) {
      throw const FormatException('Not an NT Helper template JSON file.');
    }
    final rawTemplate = decoded['template'];
    if (rawTemplate is! Map<String, dynamic>) {
      throw const FormatException('Template JSON is missing template data.');
    }

    final name = _requiredString(rawTemplate, 'name');
    final rawSlots = rawTemplate['slots'];
    if (rawSlots is! List || rawSlots.isEmpty) {
      throw const FormatException(
        'Template JSON must contain at least one slot.',
      );
    }

    final slots = <FullPresetSlot>[];
    final algorithms = <String, AlgorithmEntry>{};
    for (var outputIndex = 0; outputIndex < rawSlots.length; outputIndex++) {
      final rawSlot = rawSlots[outputIndex];
      if (rawSlot is! Map<String, dynamic>) {
        throw FormatException('Slot ${outputIndex + 1} is not an object.');
      }
      final rawAlgorithm = rawSlot['algorithm'];
      if (rawAlgorithm is! Map<String, dynamic>) {
        throw FormatException(
          'Slot ${outputIndex + 1} is missing algorithm data.',
        );
      }

      final algorithm = AlgorithmEntry(
        guid: _requiredString(rawAlgorithm, 'guid'),
        name: _requiredString(rawAlgorithm, 'name'),
        numSpecifications: _optionalInt(rawAlgorithm['numSpecifications']) ?? 0,
        pluginFilePath: rawAlgorithm['pluginFilePath'] as String?,
      );
      algorithms[algorithm.guid] = algorithm;

      slots.add(
        FullPresetSlot(
          slot: PresetSlotEntry(
            id: -1,
            presetId: -1,
            slotIndex: outputIndex,
            algorithmGuid: algorithm.guid,
            customName: rawSlot['customName'] as String?,
          ),
          algorithm: algorithm,
          specificationValues: _readSpecificationValues(
            rawSlot['specifications'],
          ),
          parameterValues: _readIntMap(rawSlot['parameterValues']),
          parameterStringValues: _readStringMap(
            rawSlot['parameterStringValues'],
          ),
          mappings: _readMappings(rawSlot['mappings']),
          routing: _readRouting(rawSlot['routing']),
        ),
      );
    }

    await database.metadataDao.upsertAlgorithms(
      algorithms.values.toList(growable: false),
    );
    return database.presetsDao.saveFullPreset(
      FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: name,
          lastModified: DateTime.now(),
          isTemplate: true,
          category: rawTemplate['category'] as String?,
          templateMetadata: rawTemplate['templateMetadata'] as String?,
        ),
        slots: slots,
      ),
      isTemplate: true,
    );
  }

  Map<String, Object?> _intKeyMap(Map<int, Object?> input) {
    return {
      for (final entry in input.entries) entry.key.toString(): entry.value,
    };
  }

  Map<String, Object?> _encodeMapping(PackedMappingData mapping) {
    return {
      'version': mapping.version,
      'midi_view_change': mapping.midiViewChange,
      'midi_ignore_when_bypassed': mapping.midiIgnoreWhenBypassed,
      'i2c_ignore_when_bypassed': mapping.i2cIgnoreWhenBypassed,
      'cv_flags_extra': mapping.cvFlagsExtra,
      'i2c_flags_extra': mapping.i2cFlagsExtra,
      if (mapping.unknownMidiMappingType != null)
        'unknown_midi_type': mapping.unknownMidiMappingType,
      'source': mapping.source,
      'cv_input': mapping.cvInput,
      'is_unipolar': mapping.isUnipolar,
      'is_gate': mapping.isGate,
      'volts': mapping.volts,
      'delta': mapping.delta,
      'midi_channel': mapping.midiChannel,
      'midi_type': _midiTypeToString(mapping.midiMappingType),
      'midi_cc': mapping.midiCC,
      'is_midi_enabled': mapping.isMidiEnabled,
      'is_midi_symmetric': mapping.isMidiSymmetric,
      'is_midi_relative': mapping.isMidiRelative,
      'midi_min': mapping.midiMin,
      'midi_max': mapping.midiMax,
      'i2c_cc': mapping.i2cCC,
      'is_i2c_enabled': mapping.isI2cEnabled,
      'is_i2c_symmetric': mapping.isI2cSymmetric,
      'i2c_min': mapping.i2cMin,
      'i2c_max': mapping.i2cMax,
      'performance_page': mapping.perfPageIndex,
    };
  }

  Map<int, int> _readIntMap(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        int.parse(entry.key.toString()): _requiredInt(entry.value),
    };
  }

  Map<int, String> _readStringMap(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        int.parse(entry.key.toString()): entry.value.toString(),
    };
  }

  Map<int, PackedMappingData> _readMappings(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        int.parse(entry.key.toString()): _decodeMapping(entry.value),
    };
  }

  PackedMappingData _decodeMapping(Object? value) {
    if (value is Map<String, dynamic>) {
      return _decodeMappingObject(value);
    }
    if (value is Map) {
      return _decodeMappingObject(Map<String, dynamic>.from(value));
    }
    if (value is String) {
      final bytes = base64Decode(value);
      if (bytes.length < 2) {
        throw const FormatException('Mapping payload is too short.');
      }
      return PackedMappingData.fromBytes(
        bytes.first,
        Uint8List.fromList(bytes.sublist(1)),
      );
    }
    throw const FormatException('Mapping payload must be an object.');
  }

  PackedMappingData _decodeMappingObject(Map<String, dynamic> value) {
    final midiType = _midiTypeFromString(value['midi_type'] as String?);
    return PackedMappingData(
      version: _optionalInt(value['version']) ?? 6,
      midiViewChange: value['midi_view_change'] as bool? ?? true,
      midiIgnoreWhenBypassed:
          value['midi_ignore_when_bypassed'] as bool? ?? false,
      i2cIgnoreWhenBypassed:
          value['i2c_ignore_when_bypassed'] as bool? ?? false,
      cvFlagsExtra: _optionalInt(value['cv_flags_extra']) ?? 0,
      i2cFlagsExtra: _optionalInt(value['i2c_flags_extra']) ?? 0,
      unknownMidiMappingType: _optionalInt(value['unknown_midi_type']),
      source: _optionalInt(value['source']) ?? 0,
      cvInput: _optionalInt(value['cv_input']) ?? 0,
      isUnipolar: value['is_unipolar'] as bool? ?? false,
      isGate: value['is_gate'] as bool? ?? false,
      volts: _optionalInt(value['volts']) ?? 0,
      delta: _optionalInt(value['delta']) ?? 0,
      midiChannel: _optionalInt(value['midi_channel']) ?? 0,
      midiMappingType: midiType,
      midiCC: _isExpressiveMidiType(midiType)
          ? 0
          : _optionalInt(value['midi_cc']) ?? 0,
      isMidiEnabled: value['is_midi_enabled'] as bool? ?? false,
      isMidiSymmetric: value['is_midi_symmetric'] as bool? ?? false,
      isMidiRelative: _isExpressiveMidiType(midiType)
          ? false
          : value['is_midi_relative'] as bool? ?? false,
      midiMin: _optionalInt(value['midi_min']) ?? 0,
      midiMax: _optionalInt(value['midi_max']) ?? 0,
      i2cCC: _optionalInt(value['i2c_cc']) ?? 0,
      isI2cEnabled: value['is_i2c_enabled'] as bool? ?? false,
      isI2cSymmetric: value['is_i2c_symmetric'] as bool? ?? false,
      i2cMin: _optionalInt(value['i2c_min']) ?? 0,
      i2cMax: _optionalInt(value['i2c_max']) ?? 0,
      perfPageIndex: _optionalInt(value['performance_page']) ?? 0,
    );
  }

  String _midiTypeToString(MidiMappingType type) {
    return switch (type) {
      MidiMappingType.cc => 'cc',
      MidiMappingType.noteMomentary => 'note_momentary',
      MidiMappingType.noteToggle => 'note_toggle',
      MidiMappingType.cc14BitLow => 'cc_14bit_low',
      MidiMappingType.cc14BitHigh => 'cc_14bit_high',
      MidiMappingType.pitchBend => 'pitch_bend',
      MidiMappingType.channelPressure => 'channel_pressure',
    };
  }

  MidiMappingType _midiTypeFromString(String? value) {
    return switch (value) {
      null || 'cc' => MidiMappingType.cc,
      'note_momentary' => MidiMappingType.noteMomentary,
      'note_toggle' => MidiMappingType.noteToggle,
      'cc_14bit_low' => MidiMappingType.cc14BitLow,
      'cc_14bit_high' => MidiMappingType.cc14BitHigh,
      'pitch_bend' => MidiMappingType.pitchBend,
      'channel_pressure' => MidiMappingType.channelPressure,
      _ => throw FormatException('Unknown MIDI mapping type "$value".'),
    };
  }

  bool _isExpressiveMidiType(MidiMappingType type) {
    return type == MidiMappingType.pitchBend ||
        type == MidiMappingType.channelPressure;
  }

  PresetRoutingEntry? _readRouting(Object? value) {
    if (value == null) return null;
    if (value is! List) {
      throw const FormatException('Routing payload must be a list.');
    }
    return PresetRoutingEntry(
      presetSlotId: -1,
      routingInfoJson: [for (final item in value) _requiredInt(item)],
    );
  }

  List<int> _readSpecificationValues(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Specifications payload must be a list.');
    }
    return List<int>.unmodifiable(
      value.map((item) {
        if (item is! int) {
          throw FormatException(
            'Specification values must be integers, got "$item".',
          );
        }
        return item;
      }),
    );
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Missing required string field "$key".');
  }

  int _requiredInt(Object? value) {
    final parsed = _optionalInt(value);
    if (parsed == null) {
      throw FormatException('Expected integer, got "$value".');
    }
    return parsed;
  }

  int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
