import 'dart:math'; // Added for pow
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';

import 'package:nt_helper/domain/i_disting_midi_manager.dart'
    show AlgorithmVisualStyleWriter, IDistingMidiManager;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:flutter/foundation.dart';
import '../db/daos/presets_dao.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/offline_algorithm_shape_resolver.dart';

/// An implementation of [IDistingMidiManager] that interacts with the
/// cached database instead of a physical MIDI device.
class OfflineDistingMidiManager
    implements IDistingMidiManager, AlgorithmVisualStyleWriter {
  final AppDatabase _database;
  late final MetadataDao _metadataDao;
  late final OfflineAlgorithmShapeResolver _shapeResolver;
  final Map<String, Future<ResolvedAlgorithmShape>> _resolvedShapeCache = {};

  // Internal state for the simulated preset
  int? _loadedPresetId;
  final List<String> _presetAlgorithmGuids = [];
  final List<List<int>> _presetSpecificationValues = [];
  final Map<int, int> _presetSlotIds = {}; // Maps slotIndex -> presetSlotId
  final Map<int, Map<int, int>> _parameterValues = {};
  final Map<int, Map<int, String>> _parameterStringValues = {};
  final Map<int, Map<int, PackedMappingData>> _mappings = {};
  final Map<int, AlgorithmVisualStyle> _visualStyles = {};
  final Map<int, String> _customNames = {};
  final Map<int, String> _defaultNames = {};
  String _presetName = "Offline Preset";

  OfflineDistingMidiManager(this._database) {
    _metadataDao = _database.metadataDao;
    _shapeResolver = OfflineAlgorithmShapeResolver(_metadataDao);
  }

  // Initialize state from loaded preset details
  Future<void> initializeFromDb(FullPresetDetails? details) async {
    _presetAlgorithmGuids.clear();
    _resolvedShapeCache.clear();
    _presetSpecificationValues.clear();
    _presetSlotIds.clear();
    _parameterValues.clear();
    _parameterStringValues.clear();
    _mappings.clear();
    _visualStyles.clear();
    _customNames.clear();
    _defaultNames.clear();
    _loadedPresetId = null;

    if (details == null) {
      _presetName = "Offline Preset";
      return;
    }

    _loadedPresetId = details.preset.id;
    _presetName = details.preset.name;
    for (int i = 0; i < details.slots.length; i++) {
      final slotData = details.slots[i];
      final guid = slotData.algorithm.guid;
      _presetAlgorithmGuids.add(guid);
      _presetSpecificationValues.add(
        List<int>.unmodifiable(slotData.specificationValues),
      );
      _presetSlotIds[i] = slotData.slot.id; // Store presetSlotId

      // Calculate default name with instance number during init
      String baseName = slotData.algorithm.name;
      int instanceCount = 0;
      for (int j = 0; j < i; j++) {
        if (_presetAlgorithmGuids[j] == guid) {
          instanceCount++;
        }
      }
      if (instanceCount > 0) {
        _defaultNames[i] = "$baseName ${instanceCount + 1}";
      } else {
        _defaultNames[i] = baseName;
      }

      _parameterValues[i] = Map.from(slotData.parameterValues);
      _parameterStringValues[i] = Map.from(slotData.parameterStringValues);
      _mappings[i] = Map.from(slotData.mappings);
      if (slotData.slot.customName != null) {
        _customNames[i] = slotData.slot.customName!;
      }
    }
  }

  @override
  void dispose() {
    // No resources to dispose for the offline manager
  }

  // --- Metadata Request Implementations ---

  @override
  Future<int?> requestNumberOfAlgorithms() async {
    try {
      final algorithms = await _metadataDao.getAllAlgorithms();
      return algorithms.length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<OutputModeUsage?> requestOutputModeUsage(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    try {
      // Validate algorithm index
      if (algorithmIndex < 0 ||
          algorithmIndex >= _presetAlgorithmGuids.length) {
        return null;
      }

      final algorithmGuid = _presetAlgorithmGuids[algorithmIndex];
      final snapshot = (await _resolvedShape(
        algorithmIndex,
        algorithmGuid,
      )).snapshot;
      final affectedOutputs = snapshot.outputUsage
          .where((usage) => usage.parameterNumber == parameterNumber)
          .map((usage) => usage.affectedParameterNumber)
          .toList();

      // If no data, return null
      if (affectedOutputs.isEmpty) {
        return null;
      }

      // Construct OutputModeUsage object
      return OutputModeUsage(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        affectedParameterNumbers: affectedOutputs,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AlgorithmInfo?> requestAlgorithmInfo(int algorithmIndex) async {
    try {
      final algorithms = await _metadataDao.getAllAlgorithms();
      if (algorithmIndex < 0 || algorithmIndex >= algorithms.length) {
        return null;
      }
      final entry = algorithms[algorithmIndex];
      final specs =
          await (_metadataDao.select(_metadataDao.specifications)
                ..where((s) => s.algorithmGuid.equals(entry.guid))
                ..orderBy([(s) => OrderingTerm.asc(s.specIndex)]))
              .get();

      return AlgorithmInfo(
        algorithmIndex: algorithmIndex,
        guid: entry.guid,
        name: entry.name,
        specifications: specs
            .map(
              (s) => Specification(
                name: s.name,
                min: s.minValue,
                max: s.maxValue,
                defaultValue: s.defaultValue,
                type: s.type,
              ),
            )
            .toList(),
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Algorithm?> requestAlgorithmGuid(int algorithmIndex) async {
    if (algorithmIndex < 0 || algorithmIndex >= _presetAlgorithmGuids.length) {
      return null;
    }
    final guid = _presetAlgorithmGuids[algorithmIndex];

    try {
      final algoEntry = await (_metadataDao.select(
        _metadataDao.algorithms,
      )..where((a) => a.guid.equals(guid))).getSingleOrNull();

      if (algoEntry != null) {
        // Retrieve pre-calculated default name and custom name
        final defaultName = _defaultNames[algorithmIndex];
        final customName = _customNames[algorithmIndex];

        return Algorithm(
          algorithmIndex: algorithmIndex,
          guid: algoEntry.guid,
          name: customName ?? defaultName ?? "Error: Name Missing",
          specifications: List<int>.from(
            _presetSpecificationValues[algorithmIndex],
          ),
          visualStyle: _visualStyles[algorithmIndex],
        );
      } else {
        return null;
      }
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<ParameterInfo?> requestParameterInfo(
    int algorithmIndex,
    int parameterNumber,
  ) {
    return _runForGuid<ParameterInfo?>(algorithmIndex, (guid) async {
      final snapshot = (await _resolvedShape(algorithmIndex, guid)).snapshot;
      if (parameterNumber >= 0 &&
          parameterNumber < snapshot.parameters.length) {
        final parameter = snapshot.parameters[parameterNumber];
        return ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: parameterNumber,
          min: parameter.min,
          max: parameter.max,
          defaultValue: parameter.defaultValue,
          unit: parameter.rawUnitIndex,
          name: parameter.name,
          powerOfTen: parameter.powerOfTen,
          ioFlags: parameter.ioFlags,
        );
      } else {
        return null;
      }
    }, errorValue: null);
  }

  @override
  Future<ParameterValue?> requestParameterValue(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    final value = _parameterValues[algorithmIndex]?[parameterNumber];

    if (value != null) {
      return ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        value: value,
      );
    } else {
      final paramInfo = await requestParameterInfo(
        algorithmIndex,
        parameterNumber,
      );
      return paramInfo != null
          ? ParameterValue(
              algorithmIndex: algorithmIndex,
              parameterNumber: parameterNumber,
              value: paramInfo.defaultValue,
            )
          : null;
    }
  }

  @override
  Future<AllParameterValues?> requestAllParameterValues(int algorithmIndex) {
    return _runForGuid<AllParameterValues?>(algorithmIndex, (guid) async {
      final numParams = await requestNumberOfParameters(algorithmIndex);
      final count = numParams?.numParameters ?? 0;
      final values = <ParameterValue>[];
      for (int i = 0; i < count; i++) {
        final pValue = await requestParameterValue(algorithmIndex, i);
        if (pValue != null) {
          values.add(pValue);
        } else {
          values.add(
            ParameterValue(
              algorithmIndex: algorithmIndex,
              parameterNumber: i,
              value: 0,
            ),
          );
        }
      }
      return AllParameterValues(algorithmIndex: algorithmIndex, values: values);
    }, errorValue: null);
  }

  @override
  Future<ParameterPages?> requestParameterPages(int algorithmIndex) {
    return _runForGuid<ParameterPages?>(algorithmIndex, (guid) async {
      final snapshot = (await _resolvedShape(algorithmIndex, guid)).snapshot;
      final Map<int, List<int>> itemsByPageIndex = {};
      for (final item in snapshot.pageMemberships) {
        (itemsByPageIndex[item.pageIndex] ??= []).add(item.parameterNumber);
      }
      for (final items in itemsByPageIndex.values) {
        items.sort();
      }
      final pages = snapshot.pages.indexed.map((entry) {
        return ParameterPage(
          name: entry.$2.name,
          parameters: itemsByPageIndex[entry.$1] ?? [],
        );
      }).toList();
      return ParameterPages(algorithmIndex: algorithmIndex, pages: pages);
    }, errorValue: null);
  }

  @override
  Future<ParameterEnumStrings?> requestParameterEnumStrings(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    if (algorithmIndex < 0 || algorithmIndex >= _presetAlgorithmGuids.length) {
      return Future.value(ParameterEnumStrings.filler());
    }
    final String guid = _presetAlgorithmGuids[algorithmIndex];

    try {
      final parameters = (await _resolvedShape(
        algorithmIndex,
        guid,
      )).snapshot.parameters;
      if (parameterNumber >= 0 &&
          parameterNumber < parameters.length &&
          parameters[parameterNumber].enumStrings.isNotEmpty) {
        return ParameterEnumStrings(
          algorithmIndex: algorithmIndex,
          parameterNumber: parameterNumber,
          values: parameters[parameterNumber].enumStrings,
        );
      } else {
        return ParameterEnumStrings.filler();
      }
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      return ParameterEnumStrings.filler();
    }
  }

  @override
  Future<ParameterValueString?> requestParameterValueString(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    final stringValue =
        _parameterStringValues[algorithmIndex]?[parameterNumber];

    if (stringValue != null) {
      return ParameterValueString(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        value: stringValue,
      );
    } else {
      final paramValue = await requestParameterValue(
        algorithmIndex,
        parameterNumber,
      );
      if (paramValue == null) return ParameterValueString.filler();
      final paramInfo = await requestParameterInfo(
        algorithmIndex,
        parameterNumber,
      );
      if (paramInfo == null) return ParameterValueString.filler();
      final unitStrings = await requestUnitStrings() ?? [];
      final unitStr = paramInfo.getUnitString(unitStrings);

      String generatedStringValue;
      if (paramInfo.unit == 1) {
        final enums = await requestParameterEnumStrings(
          algorithmIndex,
          parameterNumber,
        );
        if (enums != null &&
            enums.values.isNotEmpty &&
            paramValue.value >= 0 &&
            paramValue.value < enums.values.length) {
          generatedStringValue = enums.values[paramValue.value];
        } else {
          generatedStringValue = paramValue.value.toString();
        }
      } else if (unitStr != null && unitStr.isNotEmpty) {
        if (paramInfo.powerOfTen != 0) {
          double actualValue =
              paramValue.value / (pow(10, paramInfo.powerOfTen));
          generatedStringValue = "${actualValue.toStringAsFixed(2)}$unitStr";
        } else {
          generatedStringValue = "${paramValue.value}$unitStr";
        }
      } else {
        generatedStringValue = paramValue.value.toString();
      }

      return ParameterValueString(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        value: generatedStringValue,
      );
    }
  }

  @override
  Future<Mapping?> requestMappings(int algorithmIndex, int parameterNumber) {
    final mapping = _mappings[algorithmIndex]?[parameterNumber];
    if (mapping != null) {
      return Future.value(
        Mapping(
          algorithmIndex: algorithmIndex,
          parameterNumber: parameterNumber,
          packedMappingData: mapping,
        ),
      );
    } else {
      return Future.value(Mapping.filler());
    }
  }

  @override
  Future<RoutingInfo?> requestRoutingInformation(int algorithmIndex) {
    // Routing information is not stored or handled in offline mode.
    return Future.value(RoutingInfo.filler());
  }

  @override
  Future<String?> requestPresetName() async {
    return _presetName;
  }

  @override
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  }) async {
    return _presetAlgorithmGuids.length;
  }

  @override
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex) {
    return _runForGuid<NumParameters?>(algorithmIndex, (guid) async {
      final count = (await _resolvedShape(
        algorithmIndex,
        guid,
      )).snapshot.parameters.length;
      return NumParameters(
        algorithmIndex: algorithmIndex,
        numParameters: count,
      );
    }, errorValue: null);
  }

  @override
  Future<String?> requestVersionString() async {
    return "Offline Mode";
  }

  @override
  Future<List<String>?> requestUnitStrings() async {
    try {
      final cachedUnits = await _metadataDao.getOrderedUnitStrings();
      if (cachedUnits != null) {
        return cachedUnits;
      } else {
        return [];
      }
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      return [];
    }
  }

  // --- State Mutation Request Implementations ---

  @override
  Future<void> setParameterValue(
    int algorithmIndex,
    int parameterNumber,
    int value,
  ) async {
    (_parameterValues[algorithmIndex] ??= {})[parameterNumber] = value;
    // Clear the derived string value when the raw value changes
    _parameterStringValues[algorithmIndex]?.remove(parameterNumber);
  }

  @override
  Future<void> setParameterString(
    int algorithmIndex,
    int parameterNumber,
    String value,
  ) async {
    (_parameterStringValues[algorithmIndex] ??= {})[parameterNumber] = value;
  }

  @override
  Future<void> requestSetMapping(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  ) async {
    (_mappings[algorithmIndex] ??= {})[parameterNumber] = data;
  }

  @override
  Future<void> requestSetAlgorithmVisualStyle(
    int algorithmIndex,
    AlgorithmVisualStyle style,
  ) async {
    if (algorithmIndex < 0 || algorithmIndex >= _presetAlgorithmGuids.length) {
      return;
    }
    _visualStyles[algorithmIndex] = style;
  }

  @override
  Future<void> requestSetPresetName(String name) async {
    _presetName = name;
    if (_loadedPresetId == null) return;
    try {
      final presetsDao = _database.presetsDao;
      await presetsDao.updatePresetName(_loadedPresetId!, name);
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<void> requestSavePreset({int option = 0}) async {
    try {
      final FullPresetDetails? presetDetails =
          await _buildPresetDetailsForSave();
      if (presetDetails == null) {
        return;
      }
      final presetsDao = _database.presetsDao;
      final savedPresetId = await presetsDao.saveFullPreset(presetDetails);
      _loadedPresetId = savedPresetId;
      _presetName = presetDetails.preset.name;
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Future<void> requestLoadPreset(String name, bool append) async {}

  @override
  Future<void> requestNewPreset() async {
    _presetAlgorithmGuids.clear();
    _presetSpecificationValues.clear();
    _presetSlotIds.clear();
    _parameterValues.clear();
    _parameterStringValues.clear();
    _mappings.clear();
    _visualStyles.clear();
    _customNames.clear();
    _defaultNames.clear();
    _presetName = "Init";
    _loadedPresetId = null;
  }

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    // Calculate default name before adding
    String baseName = algorithm.name;
    String guid = algorithm.guid;
    int instanceCount = 0;
    for (int i = 0; i < _presetAlgorithmGuids.length; i++) {
      if (_presetAlgorithmGuids[i] == guid) {
        instanceCount++;
      }
    }
    String defaultName = (instanceCount > 0)
        ? "$baseName ${instanceCount + 1}"
        : baseName;

    // Add GUID and initialize state maps
    _presetAlgorithmGuids.add(guid);
    _presetSpecificationValues.add(List<int>.unmodifiable(specifications));
    final slotIndex = _presetAlgorithmGuids.length - 1;
    _defaultNames[slotIndex] = defaultName;
    _parameterValues[slotIndex] = {};
    _parameterStringValues[slotIndex] = {};
    _mappings[slotIndex] = {};
    _visualStyles.remove(slotIndex);
    _customNames.remove(slotIndex);
  }

  @override
  Future<void> requestRemoveAlgorithm(int algorithmIndex) async {
    if (algorithmIndex >= 0 && algorithmIndex < _presetAlgorithmGuids.length) {
      _presetAlgorithmGuids.removeAt(algorithmIndex);
      _presetSpecificationValues.removeAt(algorithmIndex);
      _removeAndShiftState(algorithmIndex);
    } else {}
  }

  @override
  Future<void> requestLoadPlugin(String guid) async {
    // No-op in offline mode
  }

  @override
  Future<void> requestMoveAlgorithmUp(int algorithmIndex) async {
    if (algorithmIndex > 0 && algorithmIndex < _presetAlgorithmGuids.length) {
      final guid = _presetAlgorithmGuids.removeAt(algorithmIndex);
      _presetAlgorithmGuids.insert(algorithmIndex - 1, guid);
      final specifications = _presetSpecificationValues.removeAt(
        algorithmIndex,
      );
      _presetSpecificationValues.insert(algorithmIndex - 1, specifications);
      _shiftStateUp(algorithmIndex);
    } else {}
  }

  @override
  Future<void> requestMoveAlgorithmDown(int algorithmIndex) async {
    if (algorithmIndex >= 0 &&
        algorithmIndex < _presetAlgorithmGuids.length - 1) {
      final guid = _presetAlgorithmGuids.removeAt(algorithmIndex);
      _presetAlgorithmGuids.insert(algorithmIndex + 1, guid);
      final specifications = _presetSpecificationValues.removeAt(
        algorithmIndex,
      );
      _presetSpecificationValues.insert(algorithmIndex + 1, specifications);
      _shiftStateDown(algorithmIndex);
    } else {}
  }

  @override
  Future<void> requestSendSlotName(int algorithmIndex, String newName) async {
    if (algorithmIndex >= 0 && algorithmIndex < _presetAlgorithmGuids.length) {
      _customNames[algorithmIndex] = newName;
    } else {}
  }

  @override
  Future<void> setPerformancePageMapping(
    int slotIndex,
    int parameterNumber,
    int perfPageIndex,
  ) async {
    // Offline mode - persist to database for offline editing
    try {
      // Update in-memory mapping data
      if (!_mappings.containsKey(slotIndex)) {
        _mappings[slotIndex] = {};
      }

      final currentMapping = _mappings[slotIndex]?[parameterNumber];
      final updatedMapping = currentMapping != null
          ? PackedMappingData(
              source: currentMapping.source,
              cvInput: currentMapping.cvInput,
              isUnipolar: currentMapping.isUnipolar,
              isGate: currentMapping.isGate,
              volts: currentMapping.volts,
              delta: currentMapping.delta,
              midiChannel: currentMapping.midiChannel,
              midiMappingType: currentMapping.midiMappingType,
              midiCC: currentMapping.midiCC,
              isMidiEnabled: currentMapping.isMidiEnabled,
              isMidiSymmetric: currentMapping.isMidiSymmetric,
              isMidiRelative: currentMapping.isMidiRelative,
              midiMin: currentMapping.midiMin,
              midiMax: currentMapping.midiMax,
              i2cCC: currentMapping.i2cCC,
              isI2cEnabled: currentMapping.isI2cEnabled,
              isI2cSymmetric: currentMapping.isI2cSymmetric,
              i2cMin: currentMapping.i2cMin,
              i2cMax: currentMapping.i2cMax,
              perfPageIndex: perfPageIndex, // Updated value
              version: currentMapping.version,
            )
          : PackedMappingData(
              source: 0,
              cvInput: 0,
              isUnipolar: false,
              isGate: false,
              volts: 0,
              delta: 0,
              midiChannel: 0,
              midiMappingType: MidiMappingType.cc,
              midiCC: 0,
              isMidiEnabled: false,
              isMidiSymmetric: false,
              isMidiRelative: false,
              midiMin: 0,
              midiMax: 127,
              i2cCC: 0,
              isI2cEnabled: false,
              isI2cSymmetric: false,
              i2cMin: 0,
              i2cMax: 127,
              perfPageIndex: perfPageIndex,
              version: 5, // Current version with perfPageIndex support
            );

      _mappings[slotIndex]![parameterNumber] = updatedMapping;

      // Persist to database if we have a loaded preset
      if (_loadedPresetId != null && _presetSlotIds.containsKey(slotIndex)) {
        final presetSlotId = _presetSlotIds[slotIndex]!;
        final presetsDao = _database.presetsDao;
        await presetsDao.updatePerformancePageIndex(
          presetSlotId: presetSlotId,
          parameterNumber: parameterNumber,
          perfPageIndex: perfPageIndex,
        );
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  @override
  Future<String?> executeLua(String luaScript) async {
    // Lua execution is not supported in offline mode
    throw UnsupportedError('Lua execution is not available in offline mode');
  }

  @override
  Future<String?> installLua(int algorithmIndex, String luaScript) async {
    // Lua installation is not supported in offline mode
    throw UnsupportedError('Lua installation is not available in offline mode');
  }

  // --- Communication/Device Specific Implementations (No-ops/Fillers) ---

  @override
  Future<Uint8List?> encodeTakeScreenshot() async {
    return null;
  }

  @override
  Future<void> requestSetFocus(int algorithmIndex, int parameterNumber) async {}

  @override
  Future<void> requestSetDisplayMode(DisplayMode displayMode) async {}

  @override
  Future<void> requestSetRealTimeClock(int unixTimeSeconds) async {}

  @override
  Future<void> requestWake() async {}

  @override
  Future<void> requestReboot() async {}

  @override
  Future<void> requestEnterBootloader() async {}

  Stream<MidiPacket> get midiDataStream => Stream.empty();

  Future<MidiDevice?> get inputDevice async => null;

  Future<MidiDevice?> get outputDevice async => null;

  // --- Helper Methods ---

  Future<T?> _runForGuid<T>(
    int algorithmIndex,
    Future<T?> Function(String guid) queryRunner, {
    T? errorValue,
  }) async {
    if (algorithmIndex < 0 || algorithmIndex >= _presetAlgorithmGuids.length) {
      return errorValue;
    }
    final guid = _presetAlgorithmGuids[algorithmIndex];
    try {
      return await queryRunner(guid);
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);
      return errorValue;
    }
  }

  Future<ResolvedAlgorithmShape> _resolvedShape(
    int algorithmIndex,
    String guid,
  ) {
    final values = List<int>.unmodifiable(
      _presetSpecificationValues[algorithmIndex],
    );
    final cacheKey = jsonEncode([guid, values]);
    return _resolvedShapeCache.putIfAbsent(
      cacheKey,
      () => _shapeResolver.resolve(guid, values),
    );
  }

  Future<FullPresetDetails?> _buildPresetDetailsForSave() async {
    final PresetEntry presetEntry;
    if (_loadedPresetId != null) {
      presetEntry = PresetEntry(
        id: _loadedPresetId!,
        name: _presetName,
        lastModified: DateTime.now(),
        isTemplate: false,
      );
    } else {
      presetEntry = PresetEntry(
        id: -1,
        name: _presetName,
        lastModified: DateTime.now(),
        isTemplate: false,
      );
    }

    final List<FullPresetSlot> slots = [];
    for (int i = 0; i < _presetAlgorithmGuids.length; i++) {
      final guid = _presetAlgorithmGuids[i];
      final algoEntry = await (_metadataDao.select(
        _metadataDao.algorithms,
      )..where((a) => a.guid.equals(guid))).getSingleOrNull();

      if (algoEntry == null) {
        return null;
      }

      slots.add(
        FullPresetSlot(
          slot: PresetSlotEntry(
            id: -1,
            presetId: presetEntry.id,
            slotIndex: i,
            algorithmGuid: guid,
            customName: _customNames[i],
          ),
          algorithm: algoEntry,
          specificationValues: List<int>.from(_presetSpecificationValues[i]),
          parameterValues: _parameterValues[i] ?? {},
          parameterStringValues: _parameterStringValues[i] ?? {},
          mappings: _mappings[i] ?? {},
        ),
      );
    }
    return FullPresetDetails(preset: presetEntry, slots: slots);
  }

  // --- Internal State Shifting Helpers ---

  void _removeAndShiftState(int removedIndex) {
    _parameterValues.remove(removedIndex);
    _parameterStringValues.remove(removedIndex);
    _mappings.remove(removedIndex);
    _visualStyles.remove(removedIndex);
    _customNames.remove(removedIndex);
    _defaultNames.remove(removedIndex);

    for (int i = removedIndex; i < _presetAlgorithmGuids.length; i++) {
      _parameterValues[i] = _parameterValues.remove(i + 1) ?? {};
      _parameterStringValues[i] = _parameterStringValues.remove(i + 1) ?? {};
      _mappings[i] = _mappings.remove(i + 1) ?? {};
      final movedVisualStyle = _visualStyles.remove(i + 1);
      if (movedVisualStyle != null) {
        _visualStyles[i] = movedVisualStyle;
      } else {
        _visualStyles.remove(i);
      }
      final movedCustomName = _customNames.remove(i + 1);
      if (movedCustomName != null) {
        _customNames[i] = movedCustomName;
      } else {
        _customNames.remove(i);
      }
      final movedDefaultName = _defaultNames.remove(i + 1);
      if (movedDefaultName != null) {
        _defaultNames[i] = movedDefaultName;
      } else {
        _defaultNames.remove(i);
      }
    }
    final lastIndex = _presetAlgorithmGuids.length;
    _parameterValues.remove(lastIndex);
    _parameterStringValues.remove(lastIndex);
    _mappings.remove(lastIndex);
    _visualStyles.remove(lastIndex);
    _customNames.remove(lastIndex);
    _defaultNames.remove(lastIndex);
  }

  void _shiftStateUp(int movedIndex) {
    final movingDefaultName = _defaultNames[movedIndex];
    final otherDefaultName = _defaultNames[movedIndex - 1];
    final movingCustomName = _customNames[movedIndex];
    final otherCustomName = _customNames[movedIndex - 1];
    final movingVisualStyle = _visualStyles[movedIndex];
    final otherVisualStyle = _visualStyles[movedIndex - 1];

    final tempValues = _parameterValues[movedIndex - 1];
    _parameterValues[movedIndex - 1] = _parameterValues[movedIndex] ?? {};
    _parameterValues[movedIndex] = tempValues ?? {};

    final tempStringValues = _parameterStringValues[movedIndex - 1];
    _parameterStringValues[movedIndex - 1] =
        _parameterStringValues[movedIndex] ?? {};
    _parameterStringValues[movedIndex] = tempStringValues ?? {};

    final tempMappings = _mappings[movedIndex - 1];
    _mappings[movedIndex - 1] = _mappings[movedIndex] ?? {};
    _mappings[movedIndex] = tempMappings ?? {};

    if (movingVisualStyle != null) {
      _visualStyles[movedIndex - 1] = movingVisualStyle;
    } else {
      _visualStyles.remove(movedIndex - 1);
    }
    if (otherVisualStyle != null) {
      _visualStyles[movedIndex] = otherVisualStyle;
    } else {
      _visualStyles.remove(movedIndex);
    }

    if (movingDefaultName != null) {
      _defaultNames[movedIndex - 1] = movingDefaultName;
    } else {
      _defaultNames.remove(movedIndex - 1);
    }
    if (otherDefaultName != null) {
      _defaultNames[movedIndex] = otherDefaultName;
    } else {
      _defaultNames.remove(movedIndex);
    }

    if (movingCustomName != null) {
      _customNames[movedIndex - 1] = movingCustomName;
    } else {
      _customNames.remove(movedIndex - 1);
    }
    if (otherCustomName != null) {
      _customNames[movedIndex] = otherCustomName;
    } else {
      _customNames.remove(movedIndex);
    }
  }

  void _shiftStateDown(int movedIndex) {
    final movingDefaultName = _defaultNames[movedIndex];
    final otherDefaultName = _defaultNames[movedIndex + 1];
    final movingCustomName = _customNames[movedIndex];
    final otherCustomName = _customNames[movedIndex + 1];
    final movingVisualStyle = _visualStyles[movedIndex];
    final otherVisualStyle = _visualStyles[movedIndex + 1];

    final tempValues = _parameterValues[movedIndex];
    _parameterValues[movedIndex] = _parameterValues[movedIndex + 1] ?? {};
    _parameterValues[movedIndex + 1] = tempValues ?? {};

    final tempStringValues = _parameterStringValues[movedIndex];
    _parameterStringValues[movedIndex] =
        _parameterStringValues[movedIndex + 1] ?? {};
    _parameterStringValues[movedIndex + 1] = tempStringValues ?? {};

    final tempMappings = _mappings[movedIndex];
    _mappings[movedIndex] = _mappings[movedIndex + 1] ?? {};
    _mappings[movedIndex + 1] = tempMappings ?? {};

    if (movingVisualStyle != null) {
      _visualStyles[movedIndex + 1] = movingVisualStyle;
    } else {
      _visualStyles.remove(movedIndex + 1);
    }
    if (otherVisualStyle != null) {
      _visualStyles[movedIndex] = otherVisualStyle;
    } else {
      _visualStyles.remove(movedIndex);
    }

    if (movingDefaultName != null) {
      _defaultNames[movedIndex + 1] = movingDefaultName;
    } else {
      _defaultNames.remove(movedIndex + 1);
    }
    if (otherDefaultName != null) {
      _defaultNames[movedIndex] = otherDefaultName;
    } else {
      _defaultNames.remove(movedIndex);
    }

    if (movingCustomName != null) {
      _customNames[movedIndex + 1] = movingCustomName;
    } else {
      _customNames.remove(movedIndex + 1);
    }
    if (otherCustomName != null) {
      _customNames[movedIndex] = otherCustomName;
    } else {
      _customNames.remove(movedIndex);
    }
  }

  @override
  Future<FullPresetDetails?> requestCurrentPresetDetails() =>
      _buildPresetDetailsForSave();

  @override
  Future<DirectoryListing?> requestDirectoryListing(String path) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<SdCardStatus?> requestFileDelete(String path) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<Uint8List?> requestFileDownload(String path) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<Uint8List?> requestFileDownloadChunk(
    String path,
    int position,
    int count,
  ) => throw UnsupportedError('Not available in offline mode');

  @override
  Future<SdCardStatus?> requestFileRename(String fromPath, String toPath) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<SdCardStatus?> requestFileUpload(String path, Uint8List data) {
    throw UnsupportedError('SD Card write operations not supported offline.');
  }

  @override
  Future<SdCardStatus?> requestFileUploadChunk(
    String path,
    Uint8List data,
    int position, {
    bool createAlways = false,
  }) {
    throw UnsupportedError('SD Card write operations not supported offline.');
  }

  @override
  Future<SdCardStatus?> requestDirectoryCreate(String path) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<void> requestRescanPlugins() async {
    // No-op in offline mode - rescan not applicable without hardware
  }

  @override
  Future<void> requestRemountSd() async {
    // No-op in offline mode - remount not applicable without hardware
  }

  final List<PerformancePageItem> _perfPageItems = List.generate(
    30,
    (i) => PerformancePageItem.empty(i),
  );

  @override
  Future<PerformancePageItem?> requestPerfPageItem(int itemIndex) async {
    if (itemIndex < 0 || itemIndex >= _perfPageItems.length) return null;
    return _perfPageItems[itemIndex];
  }

  @override
  Future<void> setPerfPageItem(PerformancePageItem item) async {
    if (item.itemIndex >= 0 && item.itemIndex < _perfPageItems.length) {
      _perfPageItems[item.itemIndex] = item;
    }
  }

  @override
  Future<void> requestSclFile(String filePath) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<void> requestKbmFile(String filePath) =>
      throw UnsupportedError('Not available in offline mode');

  @override
  Future<CpuUsage?> requestCpuUsage() async {
    throw UnsupportedError("CPU Usage is not available in offline mode.");
  }

  @override
  Future<void> backupPlugins(
    String backupDirectory, {
    void Function(double progress, String currentFile)? onProgress,
  }) => throw UnsupportedError('Backup not available in offline mode');

  // Diagnostics not available in offline mode
  @override
  Map<String, dynamic>? getSchedulerDiagnostics() => null;

  @override
  Map<String, Map<String, dynamic>>? getRttStatsByMessageType() => null;

  @override
  Map<int, double>? getSlowAlgorithmInfo() => null;

  @override
  void setCcCallback(void Function(int channel, int cc, int value)? callback) {}

  @override
  void clearCcCallback() {}
}
