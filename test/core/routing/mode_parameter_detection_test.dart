import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Mode Parameter Detection Tests', () {
    test('should detect output parameters with matching mode parameters', () {
      // Create a Lua Script-like slot with output parameters that have mode parameters
      final slot = _createLuaScriptSlot();

      // Extract IO parameters
      final ioParams = AlgorithmRouting.extractIOParameters(slot);

      // Verify that outputs with mode parameters are detected
      expect(
        ioParams.containsKey('Gate Out'),
        isTrue,
        reason:
            'Gate Out should be detected as IO parameter (has Gate Out mode)',
      );
      expect(
        ioParams.containsKey('Pitch CV'),
        isTrue,
        reason:
            'Pitch CV should be detected as IO parameter (has Pitch CV mode)',
      );

      // Verify that inputs without mode parameters are also detected if they match bus criteria
      expect(
        ioParams.containsKey('Clock In'),
        isTrue,
        reason: 'Clock In should be detected as IO parameter (bus parameter)',
      );
      expect(
        ioParams.containsKey('Reset'),
        isTrue,
        reason: 'Reset should be detected as IO parameter (bus parameter)',
      );
    });

    test('should correctly identify mode parameters', () {
      final slot = _createLuaScriptSlot();

      // Extract mode parameters
      final modeParams = AlgorithmRouting.extractModeParameters(slot);
      final modeParamsWithNumbers =
          AlgorithmRouting.extractModeParametersWithNumbers(slot);

      // Verify mode parameters are detected
      expect(modeParams.containsKey('Gate Out mode'), isTrue);
      expect(modeParams.containsKey('Pitch CV mode'), isTrue);

      // Verify mode parameters have correct structure
      expect(modeParamsWithNumbers['Gate Out mode'], isNotNull);
      expect(
        modeParamsWithNumbers['Gate Out mode']?.parameterNumber,
        equals(4),
      );
      expect(modeParamsWithNumbers['Pitch CV mode'], isNotNull);
      expect(
        modeParamsWithNumbers['Pitch CV mode']?.parameterNumber,
        equals(6),
      );
    });

    test('should handle algorithms without mode parameters', () {
      // Create a simple algorithm without mode parameters
      final slot = _createSimpleAlgorithmSlot();

      // Extract IO parameters
      final ioParams = AlgorithmRouting.extractIOParameters(slot);

      // Should still detect bus parameters
      expect(ioParams.containsKey('Input'), isTrue);
      expect(ioParams.containsKey('Output'), isTrue);

      // Extract mode parameters
      final modeParams = AlgorithmRouting.extractModeParameters(slot);
      expect(modeParams, isEmpty);
    });

    test('should handle mixed parameter scenarios', () {
      // Create an algorithm with some outputs having modes and some not
      final slot = _createMixedAlgorithmSlot();

      // Extract IO parameters
      final ioParams = AlgorithmRouting.extractIOParameters(slot);

      // Outputs with mode parameters should be detected
      expect(
        ioParams.containsKey('Main Out'),
        isTrue,
        reason: 'Main Out should be detected (has Main Out mode)',
      );

      // Regular bus parameters should also be detected
      expect(
        ioParams.containsKey('Aux Out'),
        isTrue,
        reason: 'Aux Out should be detected as regular bus parameter',
      );
      expect(
        ioParams.containsKey('Input 1'),
        isTrue,
        reason: 'Input 1 should be detected as regular bus parameter',
      );
    });

    test('should create proper routing from Lua Script slot', () {
      final slot = _createLuaScriptSlot();

      // Create routing from slot
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'test_lua_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Should have both inputs and outputs
      expect(
        routing.inputPorts,
        isNotEmpty,
        reason: 'Lua Script should have input ports',
      );
      expect(
        routing.outputPorts,
        isNotEmpty,
        reason: 'Lua Script should have output ports',
      );

      // Check for specific output ports
      final outputNames = routing.outputPorts.map((p) => p.name).toSet();
      expect(
        outputNames.any((name) => name.contains('Gate')),
        isTrue,
        reason: 'Should have a Gate output port',
      );
      expect(
        outputNames.any((name) => name.contains('Pitch')),
        isTrue,
        reason: 'Should have a Pitch output port',
      );
    });

    // Story 7.6: Output Mode Usage Data Tests
    test('should use outputModeMap to identify mode parameters (AC-9)', () {
      final slot = _createSlotWithOutputModeMap();

      // Create routing from slot
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid:
            'test_outputmode_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Find the output port for parameter 10 (controlled by mode parameter 20)
      final output10 = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 10,
        orElse: () => throw Exception('Output parameter 10 not found'),
      );

      // Verify mode parameter number is set from outputModeMap
      expect(
        output10.modeParameterNumber,
        equals(20),
        reason: 'Mode parameter number should be 20 from outputModeMap',
      );

      // Verify output mode is determined from parameter value (default is Add)
      expect(
        output10.outputMode,
        equals(OutputMode.add),
        reason: 'Output mode should be Add (value 0)',
      );
    });

    test('should determine Add mode from parameter value 0 (AC-9)', () {
      final slot = _createSlotWithOutputModeMap(modeValue: 0);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'test_add_${DateTime.now().millisecondsSinceEpoch}',
      );

      final output = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 10,
      );

      expect(output.outputMode, equals(OutputMode.add));
    });

    test('should determine Replace mode from parameter value 1 (AC-9)', () {
      final slot = _createSlotWithOutputModeMap(modeValue: 1);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'test_replace_${DateTime.now().millisecondsSinceEpoch}',
      );

      final output = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 10,
      );

      expect(output.outputMode, equals(OutputMode.replace));
    });

    test('should handle outputs not in outputModeMap (AC-9)', () {
      final slot = _createSlotWithOutputModeMap();

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid:
            'test_uncontrolled_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Parameter 11 is not controlled by any mode parameter
      final output11 = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 11,
      );

      // Should not have mode parameter number
      expect(output11.modeParameterNumber, isNull);
      expect(output11.outputMode, isNull);
    });

    test(
      'should fallback to pattern matching when outputModeMap is empty (AC-6, AC-9)',
      () {
        // Create slot without outputModeMap but with mode parameters
        final slot = _createLuaScriptSlot();

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid:
              'test_fallback_${DateTime.now().millisecondsSinceEpoch}',
        );

        // Should still detect mode parameters via pattern matching in offline mode
        final gateOutput = routing.outputPorts.firstWhere(
          (p) => p.name == 'Gate Out',
          orElse: () => throw Exception('Gate Out not found'),
        );

        // In offline mode with pattern matching, mode should be detected
        expect(
          gateOutput.modeParameterNumber,
          isNotNull,
          reason: 'Should fallback to pattern matching for mode detection',
        );
      },
    );

    // Story 7.6: PolyAlgorithmRouting Tests (AC-7)
    test('should use outputModeMap in PolyAlgorithmRouting (AC-7)', () {
      final slot = _createPolySlotWithOutputModeMap();

      // Create routing from slot - PolyAlgorithmRouting should be selected
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid:
            'test_poly_outputmode_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Find the voice output port for parameter 100 (controlled by mode parameter 200)
      final voiceOutput = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 100,
        orElse: () => throw Exception('Voice output parameter 100 not found'),
      );

      // Verify mode parameter number is set from outputModeMap
      expect(
        voiceOutput.modeParameterNumber,
        equals(200),
        reason:
            'Poly algorithm mode parameter should be 200 from outputModeMap',
      );
    });

    test('should determine Add mode in PolyAlgorithmRouting (AC-7)', () {
      final slot = _createPolySlotWithOutputModeMap(modeValue: 0);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'test_poly_add_${DateTime.now().millisecondsSinceEpoch}',
      );

      final voiceOutput = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 100,
      );

      expect(
        voiceOutput.outputMode,
        equals(OutputMode.add),
        reason: 'Poly algorithm output mode should be Add (value 0)',
      );
    });

    test('should determine Replace mode in PolyAlgorithmRouting (AC-7)', () {
      final slot = _createPolySlotWithOutputModeMap(modeValue: 1);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid:
            'test_poly_replace_${DateTime.now().millisecondsSinceEpoch}',
      );

      final voiceOutput = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 100,
      );

      expect(
        voiceOutput.outputMode,
        equals(OutputMode.replace),
        reason: 'Poly algorithm output mode should be Replace (value 1)',
      );
    });

    test(
      'should fallback to pattern matching in offline PolyAlgorithmRouting (AC-6, AC-7)',
      () {
        // Create poly slot without outputModeMap but with mode parameters
        final slot = _createPolySlotWithoutOutputModeMap();

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid:
              'test_poly_fallback_${DateTime.now().millisecondsSinceEpoch}',
        );

        // Should still detect mode parameters via pattern matching in offline mode
        final pitchOutput = routing.outputPorts.firstWhere(
          (p) => p.name.contains('Pitch'),
          orElse: () => throw Exception('Pitch output not found'),
        );

        // In offline mode with pattern matching, mode should be detected
        expect(
          pitchOutput.modeParameterNumber,
          isNotNull,
          reason:
              'Poly algorithm should fallback to pattern matching for mode detection',
        );
      },
    );
  });
}

/// Helper function to create a slot with outputModeMap (Story 7.6)
Slot _createSlotWithOutputModeMap({int modeValue = 0}) {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'test',
    name: 'Test Algorithm',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  final parameters = [
    // Input parameter (bus 1)
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28, // Bus parameters have max 27, 28, or 30
      defaultValue: 1,
      unit: 1, // enum
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    // Output parameter 10 - controlled by mode parameter 20 (bus 13)
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 10,
      min: 0,
      max: 28, // Bus parameters have max 27, 28, or 30
      defaultValue: 13,
      unit: 1, // enum
      name: 'Output A',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    // Output parameter 11 - not controlled by any mode parameter (bus 14)
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 11,
      min: 0,
      max: 28, // Bus parameters have max 27, 28, or 30
      defaultValue: 14,
      unit: 1, // enum
      name: 'Output B',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    // Mode parameter 20 - controls output 10
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 20,
      min: 0,
      max: 1,
      defaultValue: modeValue,
      unit: 1, // enum
      name: 'Output A mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
  ];

  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.parameterNumber == 20 ? modeValue : p.defaultValue,
        ),
      )
      .toList();

  final enums = [
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 20,
      values: ['Add', 'Replace'],
    ),
  ];

  // outputModeMap: mode parameter 20 controls output parameter 10
  final outputModeMap = <int, List<int>>{
    20: [10],
  };

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: [],
    valueStrings: [],
    outputModeMap: outputModeMap,
  );
}

/// Helper function to create a Lua Script-like slot with mode parameters
Slot _createLuaScriptSlot() {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'lua ',
    name: 'Lua Script',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  // Define parameters like in a typical Lua Script
  final parameters = [
    // Input parameters (no mode)
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Clock In',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Reset',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    // Output parameters with mode
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 2,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Gate Out',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 3,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Pitch CV',
      powerOfTen: 0,
      ioFlags: 6, // isOutput | isAudio
    ),
    // Mode parameters
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 4,
      min: 0,
      max: 1,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Gate Out mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 6,
      min: 0,
      max: 1,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Pitch CV mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
  ];

  // Create values (all defaults)
  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.defaultValue,
        ),
      )
      .toList();

  // Create enums for mode parameters
  final enums = [
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 4,
      values: ['Add', 'Replace'],
    ),
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 6,
      values: ['Add', 'Replace'],
    ),
  ];

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: [],
    valueStrings: [],
  );
}

/// Helper function to create a simple algorithm slot without mode parameters
Slot _createSimpleAlgorithmSlot() {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'simp',
    name: 'Simple Algorithm',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  final parameters = [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Output',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
  ];

  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.defaultValue,
        ),
      )
      .toList();

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: [],
    mappings: [],
    valueStrings: [],
  );
}

/// Helper function to create a mixed algorithm slot with some outputs having modes
Slot _createMixedAlgorithmSlot() {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'mixd',
    name: 'Mixed Algorithm',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  final parameters = [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Input 1',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Main Out',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 2,
      min: 0,
      max: 1,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Main Out mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 3,
      min: 0,
      max: 28,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Aux Out',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
  ];

  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.defaultValue,
        ),
      )
      .toList();

  final enums = [
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 2,
      values: ['Add', 'Replace'],
    ),
  ];

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: [],
    valueStrings: [],
  );
}

/// Helper function to create a poly algorithm slot with outputModeMap (Story 7.6 AC-7)
Slot _createPolySlotWithOutputModeMap({int modeValue = 0}) {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'pycv', // Poly CV algorithm
    name: 'Poly CV',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  final parameters = [
    // Gate inputs for poly voices
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28,
      defaultValue: 1,
      unit: 1, // enum
      name: 'Gate input 1',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    // Voice output parameters
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 100,
      min: 0,
      max: 28,
      defaultValue: 13,
      unit: 1, // enum
      name: 'Voice output',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    // Mode parameter 200 controls output 100
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 200,
      min: 0,
      max: 1,
      defaultValue: modeValue,
      unit: 1, // enum
      name: 'Voice output mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
  ];

  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.parameterNumber == 200 ? modeValue : p.defaultValue,
        ),
      )
      .toList();

  final enums = [
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 200,
      values: ['Add', 'Replace'],
    ),
  ];

  // outputModeMap: mode parameter 200 controls output parameter 100
  final outputModeMap = <int, List<int>>{
    200: [100],
  };

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: [],
    valueStrings: [],
    outputModeMap: outputModeMap,
  );
}

/// Helper function to create a poly algorithm slot without outputModeMap (offline mode)
Slot _createPolySlotWithoutOutputModeMap() {
  final algorithm = Algorithm(
    algorithmIndex: 0,
    guid: 'pycv', // Poly CV algorithm
    name: 'Poly CV',
  );

  final routing = RoutingInfo(
    algorithmIndex: 0,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: 0, pages: []);

  final parameters = [
    // Gate inputs for poly voices
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 28,
      defaultValue: 1,
      unit: 1, // enum
      name: 'Gate input 1',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    // Voice output parameters
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 100,
      min: 0,
      max: 28,
      defaultValue: 13,
      unit: 1, // enum
      name: 'Pitch output',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    // Mode parameter - uses pattern matching in offline mode
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 200,
      min: 0,
      max: 1,
      defaultValue: 0,
      unit: 1, // enum
      name: 'Pitch output mode',
      powerOfTen: 0,
      ioFlags: 8, // isOutputMode
    ),
  ];

  final values = parameters
      .map(
        (p) => ParameterValue(
          algorithmIndex: 0,
          parameterNumber: p.parameterNumber,
          value: p.defaultValue,
        ),
      )
      .toList();

  final enums = [
    ParameterEnumStrings(
      algorithmIndex: 0,
      parameterNumber: 200,
      values: ['Add', 'Replace'],
    ),
  ];

  // No outputModeMap - will fall back to pattern matching
  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: [],
    valueStrings: [],
  );
}
