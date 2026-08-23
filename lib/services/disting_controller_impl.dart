import 'dart:typed_data'; // Added for Uint8List
import 'package:collection/collection.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        ParameterInfo,
        ParameterValue,
        ParameterEnumStrings,
        Mapping;
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';
import 'package:nt_helper/models/packed_mapping_data.dart'
    show PackedMappingData;

class DistingControllerImpl implements DistingController {
  final DistingCubit _distingCubit;
  static const int maxSlots = DistingLimits.maxPresetSlots;

  DistingControllerImpl(this._distingCubit);

  /// Helper to get the synchronized state or throw if not available.
  DistingStateSynchronized _getSynchronizedState() {
    final state = _distingCubit.state;
    if (state is DistingStateSynchronized) {
      return state;
    } else {
      throw StateError(
        'Disting is not in a synchronized state. Current state: ${state.runtimeType}',
      );
    }
  }

  /// Helper to get the underlying MIDI manager.
  IDistingMidiManager _getManager() {
    return _distingCubit.requireDisting();
  }

  /// Helper to validate a slot index.
  void _validateSlotIndex(int index) {
    if (index < 0 || index >= maxSlots) {
      throw ArgumentError(
        'Invalid slot index: $index. Must be between 0 and ${DistingLimits.maxPresetSlotIndex}.',
      );
    }
  }

  /// Helper to validate a hardware parameter number within a slot.
  void _validateParameterNumber(
    int slotIndex,
    int parameterNumber,
    DistingStateSynchronized state,
  ) {
    _validateSlotIndex(slotIndex);

    final Slot slotData = state.slots[slotIndex];
    final idx = slotData.parameters.indexWhere(
      (p) => p.parameterNumber == parameterNumber,
    );

    if (idx == -1) {
      final available = slotData.parameters
          .map((p) => p.parameterNumber)
          .toList();
      throw ArgumentError(
        'Parameter number $parameterNumber not found in slot $slotIndex. Available: $available',
      );
    }
  }

  /// Find the array index for a hardware parameter number within a slot.
  int _findParameterArrayIndex(Slot slotData, int parameterNumber) {
    final idx = slotData.parameters.indexWhere(
      (p) => p.parameterNumber == parameterNumber,
    );
    if (idx == -1) {
      final available = slotData.parameters
          .map((p) => p.parameterNumber)
          .toList();
      throw ArgumentError(
        'Parameter number $parameterNumber not found. Available: $available',
      );
    }
    return idx;
  }

  @override
  Future<String> getCurrentPresetName() async {
    return _getSynchronizedState().presetName;
  }

  @override
  Future<void> setPresetName(String name) async {
    _getSynchronizedState();
    await _distingCubit.renamePresetAndSave(name);
  }

  @override
  Future<Algorithm?> getAlgorithmInSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) {
      return null;
    }
    return state.slots[slotIndex].algorithm;
  }

  @override
  Future<List<ParameterInfo>> getParametersForSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) {
      return const <ParameterInfo>[];
    }
    final Slot slot = state.slots[slotIndex];
    return slot.parameters;
  }

  @override
  Future<AlgorithmShapeSnapshot?> getAlgorithmShapeForSlot(
    int slotIndex,
  ) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) return null;
    final slot = state.slots[slotIndex];
    if (slot.algorithm.guid.isEmpty) return null;

    final enumsByParameter = <int, List<String>>{
      for (final entry in slot.enums)
        if (entry.parameterNumber >= 0) entry.parameterNumber: entry.values,
    };
    // The regular synchronized view fetches enums only for parameters that
    // appear on a device page. Hardware metadata validation needs the raw
    // shape for hidden parameters too, so fill those gaps directly from NT.
    for (final parameter in slot.parameters) {
      if (parameter.unit != 1 ||
          (enumsByParameter[parameter.parameterNumber]?.isNotEmpty ?? false)) {
        continue;
      }
      final response = await state.disting.requestParameterEnumStrings(
        slot.algorithm.algorithmIndex,
        parameter.parameterNumber,
      );
      if (response != null) {
        enumsByParameter[parameter.parameterNumber] = response.values;
      }
    }
    return AlgorithmShapeSnapshot(
      specificationValues: slot.algorithm.specifications,
      parameters: [
        for (final parameter in slot.parameters)
          ShapeParameterAtom(
            name: parameter.name,
            min: parameter.min,
            max: parameter.max,
            defaultValue: parameter.defaultValue,
            rawUnitIndex: parameter.unit,
            powerOfTen: parameter.powerOfTen,
            ioFlags: parameter.ioFlags,
            enumStrings:
                enumsByParameter[parameter.parameterNumber] ?? const [],
          ),
      ],
      pages: [
        for (final page in slot.pages.pages) ShapePageAtom(name: page.name),
      ],
      pageMemberships: [
        for (final (pageIndex, page) in slot.pages.pages.indexed)
          for (final parameterNumber in page.parameters)
            ShapePageMembershipAtom(
              pageIndex: pageIndex,
              parameterNumber: parameterNumber,
            ),
      ],
      outputUsage: [
        for (final entry in slot.outputModeMap.entries)
          for (final affectedParameterNumber in entry.value)
            ShapeOutputUsageAtom(
              parameterNumber: entry.key,
              affectedParameterNumber: affectedParameterNumber,
            ),
      ],
    );
  }

  @override
  Future<void> addAlgorithm(Algorithm algorithm) async {
    final state = _getSynchronizedState();
    final algorithmInfo = state.algorithms.firstWhereOrNull(
      (info) => info.guid == algorithm.guid,
    );

    if (algorithmInfo == null) {
      throw ArgumentError(
        'Algorithm with GUID ${algorithm.guid} not found in the list of available algorithms.',
      );
    }
    // Use specifications from Algorithm if provided, otherwise use defaults
    final specs = algorithm.specifications.isNotEmpty
        ? algorithm.specifications
        : algorithmInfo.specifications.map((s) => s.defaultValue).toList();
    await _distingCubit.onAlgorithmSelected(algorithmInfo, specs);
  }

  @override
  Future<void> clearSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) {
      return;
    }
    final slot = state.slots[slotIndex];
    if (slot.algorithm.guid.isEmpty) {
      return;
    }

    await _distingCubit.onRemoveAlgorithm(slot.algorithm.algorithmIndex);
  }

  @override
  Future<void> moveAlgorithmUp(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    await _distingCubit.moveAlgorithmUp(slotIndex);
  }

  @override
  Future<void> moveAlgorithmDown(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    await _distingCubit.moveAlgorithmDown(slotIndex);
  }

  @override
  Future<void> updateParameterValue(
    int slotIndex,
    int parameterNumber,
    dynamic value,
  ) async {
    final state = _getSynchronizedState();
    _validateParameterNumber(slotIndex, parameterNumber, state);

    final Slot slotData = state.slots[slotIndex];
    final ParameterInfo paramInfo = slotData.parameters.firstWhere(
      (p) => p.parameterNumber == parameterNumber,
    );

    final int intValue;
    if (value is int) {
      intValue = value;
    } else if (value is double) {
      intValue = value.round();
    } else if (value is String) {
      intValue =
          int.tryParse(value) ??
          (throw ArgumentError('Cannot parse String "$value" to int.'));
    } else {
      throw ArgumentError(
        'Invalid value type: ${value.runtimeType}. Expected int, double, or parsable String.',
      );
    }

    if (intValue < paramInfo.min || intValue > paramInfo.max) {
      throw ArgumentError(
        'Value $intValue for parameter "${paramInfo.name}" (parameter $parameterNumber) in slot $slotIndex is out of range (min: ${paramInfo.min}, max: ${paramInfo.max}).',
      );
    }

    await _distingCubit.updateParameterValue(
      algorithmIndex: slotData.algorithm.algorithmIndex,
      parameterNumber: parameterNumber,
      value: intValue,
      userIsChangingTheValue: false,
    );
  }

  @override
  Future<void> updateParameterString(
    int slotIndex,
    int parameterNumber,
    String value,
  ) async {
    final state = _getSynchronizedState();
    _validateParameterNumber(slotIndex, parameterNumber, state);

    final Slot slotData = state.slots[slotIndex];

    await _distingCubit.updateParameterString(
      algorithmIndex: slotData.algorithm.algorithmIndex,
      parameterNumber: parameterNumber,
      value: value,
    );
  }

  @override
  Future<Map<int, Algorithm?>> getAllSlots() async {
    final state = _getSynchronizedState();
    final Map<int, Algorithm?> slotAlgorithms = {};
    for (int i = 0; i < state.slots.length; i++) {
      slotAlgorithms[i] = state.slots[i].algorithm;
    }
    return slotAlgorithms;
  }

  @override
  Future<ParameterValue?> getParameterValue(
    int slotIndex,
    int parameterNumber,
  ) async {
    final state = _getSynchronizedState();
    _validateParameterNumber(slotIndex, parameterNumber, state);

    final Slot slotData = state.slots[slotIndex];
    final Algorithm algorithm = slotData.algorithm;

    final int actualAlgorithmIndex = algorithm.algorithmIndex;

    try {
      final ParameterValue? paramValueResponse = await _getManager()
          .requestParameterValue(actualAlgorithmIndex, parameterNumber);
      return paramValueResponse;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<String?> getParameterStringValue(
    int slotIndex,
    int parameterNumber,
  ) async {
    final state = _getSynchronizedState();
    _validateParameterNumber(slotIndex, parameterNumber, state);

    final Slot slotData = state.slots[slotIndex];

    try {
      final idx = _findParameterArrayIndex(slotData, parameterNumber);
      if (idx < slotData.valueStrings.length) {
        return slotData.valueStrings[idx].value;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> setSlotName(int slotIndex, String name) async {
    final state = _getSynchronizedState();
    _validateSlotIndex(slotIndex);
    if (slotIndex >= state.slots.length) {
      throw ArgumentError('Slot $slotIndex is empty.');
    }

    final Slot slotData = state.slots[slotIndex];
    if (slotData.algorithm.guid.isEmpty) {
      throw ArgumentError('Slot $slotIndex is empty.');
    }

    final int actualAlgorithmIndex = slotData.algorithm.algorithmIndex;

    _distingCubit.renameSlot(actualAlgorithmIndex, name);
  }

  @override
  Future<String?> getSlotName(int slotIndex) async {
    final state = _getSynchronizedState();
    _validateSlotIndex(slotIndex);
    if (slotIndex >= state.slots.length) {
      return null;
    }

    final Slot slotData = state.slots[slotIndex];

    // Check if slot is empty
    if (slotData.algorithm.guid.isEmpty) {
      return null;
    }

    // Return the custom name if set, otherwise return the algorithm's default name
    // The actual implementation may need to check for custom names stored in the state
    // For now, return the algorithm name as a placeholder
    return slotData.algorithm.name.isNotEmpty ? slotData.algorithm.name : null;
  }

  @override
  Future<void> newPreset() async {
    await _distingCubit.newPreset();
  }

  @override
  Future<void> savePreset() async {
    _getSynchronizedState();
    await _distingCubit.savePreset();
  }

  @override
  Future<void> flushParameterQueue() async {
    await _distingCubit.flushParameterQueue();
  }

  @override
  Future<Uint8List?> getModuleScreenshot() async {
    // Assuming DistingCubit has a method like getHardwareScreenshot
    // that handles connection checks and returns null if unavailable.
    try {
      // _getSynchronizedState(); // Determine if sync state is strictly needed for a screenshot
      return await _distingCubit.getHardwareScreenshot();
    } catch (e) {
      return null; // Ensure null is returned on any error
    }
  }

  @override
  Future<void> refreshSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    _getSynchronizedState();
    await _distingCubit.refreshSlot(slotIndex);
  }

  @override
  Future<CpuUsage?> getCpuUsage() async {
    try {
      _getSynchronizedState(); // Ensure we're in sync state
      return await _getManager().requestCpuUsage();
    } catch (e) {
      return null; // Return null on any error
    }
  }

  @override
  Future<ParameterEnumStrings?> getParameterEnumStrings(
    int slotIndex,
    int parameterNumber,
  ) async {
    try {
      final state = _getSynchronizedState();
      _validateParameterNumber(slotIndex, parameterNumber, state);

      final slot = state.slots[slotIndex];

      // Find enum data for this parameter
      final enums = slot.enums
          .where((e) => e.parameterNumber == parameterNumber)
          .firstOrNull;
      return enums;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<Mapping?> getParameterMapping(
    int slotIndex,
    int parameterNumber,
  ) async {
    try {
      final state = _getSynchronizedState();
      _validateParameterNumber(slotIndex, parameterNumber, state);

      final slot = state.slots[slotIndex];

      final idx = _findParameterArrayIndex(slot, parameterNumber);
      if (idx < slot.mappings.length) {
        return slot.mappings[idx];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  bool get isSynchronized => _distingCubit.state is DistingStateSynchronized;

  @override
  Future<List<ParameterValue>> getValuesForSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) {
      return const <ParameterValue>[];
    }
    return state.slots[slotIndex].values;
  }

  @override
  Future<List<Mapping>> getMappingsForSlot(int slotIndex) async {
    _validateSlotIndex(slotIndex);
    final state = _getSynchronizedState();
    if (slotIndex >= state.slots.length) {
      return const <Mapping>[];
    }
    return state.slots[slotIndex].mappings;
  }

  @override
  Future<void> saveMapping(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData mapping,
  ) async {
    await _distingCubit.saveMapping(algorithmIndex, parameterNumber, mapping);
  }

  @override
  Future<void> refresh() async {
    await _distingCubit.refresh();
  }
}
