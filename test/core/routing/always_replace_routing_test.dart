import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Always-Replace Output Mode (no mode parameter)', () {
    test('Quantizer outputs default to Replace mode', () {
      final slot = _createSimpleOutputSlot(guid: 'quan', name: 'Quantizer');

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'quan_test',
      );

      expect(routing.outputPorts, isNotEmpty);
      for (final port in routing.outputPorts) {
        expect(
          port.outputMode,
          equals(OutputMode.replace),
          reason:
              'Quantizer output "${port.name}" should be Replace by default',
        );
      }
    });

    test('Auto-calibrator outputs default to Replace mode', () {
      final slot = _createSimpleOutputSlot(
        guid: 'cali',
        name: 'Auto-calibrator',
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'cali_test',
      );

      expect(routing.outputPorts, isNotEmpty);
      for (final port in routing.outputPorts) {
        expect(
          port.outputMode,
          equals(OutputMode.replace),
          reason:
              'Auto-calibrator output "${port.name}" should be Replace by default',
        );
      }
    });

    test(
      'Algorithm not in always-replace list keeps null mode without param',
      () {
        final slot = _createSimpleOutputSlot(
          guid: 'unkn',
          name: 'Unknown algorithm',
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'unkn_test',
        );

        expect(routing.outputPorts, isNotEmpty);
        for (final port in routing.outputPorts) {
          expect(
            port.outputMode,
            isNull,
            reason:
                'Algorithm not in always-replace list should keep null mode '
                'when no mode parameter exists',
          );
        }
      },
    );
  });

  group('defaultOutputMode parameter on createFromSlot', () {
    test('does not override existing outputMode from outputModeMap', () {
      // Output mapped to a mode parameter that is set to Add (0)
      final slot = _createOutputWithModeMapSlot(modeValue: 0);

      final routing = MultiChannelAlgorithmRouting.createFromSlot(
        slot,
        ioParameters: AlgorithmRouting.extractIOParameters(slot),
        modeParameters: AlgorithmRouting.extractModeParameters(slot),
        modeParametersWithNumbers:
            AlgorithmRouting.extractModeParametersWithNumbers(slot),
        algorithmUuid: 'override_test',
        defaultOutputMode: OutputMode.replace,
      );

      final output = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 10,
      );

      expect(
        output.outputMode,
        equals(OutputMode.add),
        reason:
            'defaultOutputMode must not override a mode set by outputModeMap',
      );
    });

    test('does not override existing outputMode from pattern fallback', () {
      // Slot has 'Out mode' parameter but empty outputModeMap → pattern fallback
      final slot = _createOutputWithPatternModeSlot(modeValue: 0);

      final routing = MultiChannelAlgorithmRouting.createFromSlot(
        slot,
        ioParameters: AlgorithmRouting.extractIOParameters(slot),
        modeParameters: AlgorithmRouting.extractModeParameters(slot),
        modeParametersWithNumbers:
            AlgorithmRouting.extractModeParametersWithNumbers(slot),
        algorithmUuid: 'pattern_test',
        defaultOutputMode: OutputMode.replace,
      );

      final output = routing.outputPorts.firstWhere(
        (p) => p.parameterNumber == 10,
      );

      expect(
        output.outputMode,
        equals(OutputMode.add),
        reason:
            'defaultOutputMode must not override a mode set via pattern matching',
      );
    });

    test('null defaultOutputMode preserves existing null-mode behaviour', () {
      final slot = _createSimpleOutputSlot(guid: 'unkn', name: 'Unknown');

      final routing = MultiChannelAlgorithmRouting.createFromSlot(
        slot,
        ioParameters: AlgorithmRouting.extractIOParameters(slot),
        modeParameters: AlgorithmRouting.extractModeParameters(slot),
        modeParametersWithNumbers:
            AlgorithmRouting.extractModeParametersWithNumbers(slot),
        algorithmUuid: 'null_default_test',
      );

      expect(routing.outputPorts, isNotEmpty);
      for (final port in routing.outputPorts) {
        expect(port.outputMode, isNull);
      }
    });

    test('does not affect input ports', () {
      final slot = _createSimpleOutputSlot(guid: 'quan', name: 'Quantizer');

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'input_test',
      );

      expect(routing.inputPorts, isNotEmpty);
      for (final port in routing.inputPorts) {
        expect(
          port.outputMode,
          isNull,
          reason: 'Input ports should never have an outputMode',
        );
      }
    });
  });
}

/// Slot with one input + two outputs, no mode parameter.
Slot _createSimpleOutputSlot({required String guid, required String name}) {
  final algorithm = Algorithm(algorithmIndex: 0, guid: guid, name: name);

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
      defaultValue: 1,
      unit: 1,
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1, // isInput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 28,
      defaultValue: 13,
      unit: 1,
      name: 'CV output',
      powerOfTen: 0,
      ioFlags: 2, // isOutput
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 2,
      min: 0,
      max: 28,
      defaultValue: 14,
      unit: 1,
      name: 'Gate output',
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
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );
}

/// Slot whose output parameter is controlled by a mode parameter via
/// `outputModeMap` (online/connected path).
Slot _createOutputWithModeMapSlot({int modeValue = 0}) {
  final algorithm = Algorithm(algorithmIndex: 0, guid: 'tst1', name: 'Test1');

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
      defaultValue: 1,
      unit: 1,
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 10,
      min: 0,
      max: 28,
      defaultValue: 13,
      unit: 1,
      name: 'Out',
      powerOfTen: 0,
      ioFlags: 2,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 20,
      min: 0,
      max: 1,
      defaultValue: modeValue,
      unit: 1,
      name: 'Out mode',
      powerOfTen: 0,
      ioFlags: 8,
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
      values: const ['Add', 'Replace'],
    ),
  ];

  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: const [],
    valueStrings: const [],
    outputModeMap: const {
      20: [10],
    },
  );
}

/// Slot whose output is matched via pattern matching ('Out mode') with an
/// empty `outputModeMap` (offline/mock path).
Slot _createOutputWithPatternModeSlot({int modeValue = 0}) {
  final algorithm = Algorithm(algorithmIndex: 0, guid: 'tst2', name: 'Test2');

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
      defaultValue: 1,
      unit: 1,
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 10,
      min: 0,
      max: 28,
      defaultValue: 13,
      unit: 1,
      name: 'Out',
      powerOfTen: 0,
      ioFlags: 2,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 20,
      min: 0,
      max: 1,
      defaultValue: modeValue,
      unit: 1,
      name: 'Out mode',
      powerOfTen: 0,
      ioFlags: 8,
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
      values: const ['Add', 'Replace'],
    ),
  ];

  // Empty outputModeMap forces the pattern-matching fallback.
  return Slot(
    algorithm: algorithm,
    routing: routing,
    pages: pages,
    parameters: parameters,
    values: values,
    enums: enums,
    mappings: const [],
    valueStrings: const [],
  );
}
