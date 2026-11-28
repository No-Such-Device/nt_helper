import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/clock_algorithm_routing.dart';
import 'package:nt_helper/core/routing/saturator_algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

import '../../test_helpers/cv_routing_fixture.dart';

/// The firmware writes a channel's custom name into that channel's parameter
/// names, so "1:Input" becomes "Grov:Input" after a rename. Channel-aware code
/// must not depend on the prefix being a number.
void main() {
  group('prefix-agnostic channel identity', () {
    test('hardcoded inputs match a renamed channel prefix', () {
      expect(AlgorithmRouting.isHardcodedInput('logi', '1:Input X'), isTrue);
      expect(AlgorithmRouting.isHardcodedInput('logi', 'Grov:Input X'), isTrue);
      expect(AlgorithmRouting.isHardcodedInput('logi', 'Grov:Input Y'), isTrue);
      expect(
        AlgorithmRouting.isHardcodedInput('musw', 'CH2:In control source'),
        isTrue,
      );
      expect(AlgorithmRouting.isHardcodedInput('logi', 'Grov:Gain'), isFalse);
    });

    test('channel prefixes are collected in parameter order', () {
      final slot = _saturatorSlot(const ['Grov', 'CH2']);

      expect(AlgorithmRouting.channelPrefixes(slot), ['Grov:', 'CH2:']);
    });

    test('saturator keeps renamed channels as ports', () {
      final routing = SaturatorAlgorithmRouting.createFromSlot(
        _saturatorSlot(const ['Grov', 'CH2']),
        ioParameters: const {},
        algorithmUuid: 'satu_test',
      );

      expect(routing.inputPorts.map((port) => port.name), [
        'Grov:Input',
        'CH2:Input',
      ]);
      expect(routing.inputPorts.map((port) => port.parameterNumber), [0, 2]);
      expect(routing.inputPorts.map((port) => port.busValue), [5, 7]);
      expect(routing.outputPorts.map((port) => port.name), [
        'Grov:Output',
        'CH2:Output',
      ]);
    });

    test('ES-5 clock routing keeps renamed channels', () {
      List<String> portSignature(ClockAlgorithmRouting routing) => [
        for (final port in routing.outputPorts)
          '${port.name}|${port.channelNumber}|${port.busValue}',
      ];

      final numeric = ClockAlgorithmRouting.createFromSlot(
        _clockSlot(const ['1', '2']),
        ioParameters: const {},
        algorithmUuid: 'clck_test',
      );
      final renamed = ClockAlgorithmRouting.createFromSlot(
        _clockSlot(const ['Grov', 'CH2']),
        ioParameters: const {},
        algorithmUuid: 'clck_test',
      );

      expect(renamed.outputPorts, isNotEmpty);
      expect(portSignature(renamed), portSignature(numeric));
    });

    test('modulation labels strip a renamed channel prefix', () {
      final modulation = cvProjection([
        cvSlot(
          0,
          pageName: 'Channel 1',
          cvNames: const ['Grov:Gain'],
          cvBuses: const [5],
        ),
      ]).single;

      // The page already names the channel, so the parameter's own prefix is
      // dropped instead of being repeated ("Channel 1: Grov:Gain").
      expect(modulation.parameterName, 'Channel 1: Gain');
    });
  });
}

/// Two Saturator channels, each with an Input and Width parameter.
Slot _saturatorSlot(List<String> prefixes) {
  const algorithmIndex = 0;
  final parameters = <ParameterInfo>[];
  final values = <ParameterValue>[];

  for (var index = 0; index < prefixes.length; index++) {
    final prefix = prefixes[index];
    final inputParamNum = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: inputParamNum,
        name: '$prefix:Input',
        min: 1,
        max: 28,
        defaultValue: 1,
        unit: 1,
        powerOfTen: 0,
      ),
    );
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: inputParamNum,
        value: 5 + index * 2,
      ),
    );

    final widthParamNum = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: widthParamNum,
        name: '$prefix:Width',
        min: 1,
        max: 12,
        defaultValue: 1,
        unit: 1,
        powerOfTen: 0,
      ),
    );
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: widthParamNum,
        value: 1,
      ),
    );
  }

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: algorithmIndex,
      guid: 'satu',
      name: 'Saturator',
    ),
    routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: const []),
    pages: ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
    parameters: parameters,
    values: values,
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );
}

/// A two-channel Clock slot where channel 1 routes to ES-5 and channel 2 to a
/// normal output bus.
Slot _clockSlot(List<String> prefixes) {
  const algorithmIndex = 0;
  final parameters = <ParameterInfo>[];
  final values = <ParameterValue>[];

  for (var index = 0; index < prefixes.length; index++) {
    final prefix = prefixes[index];
    final expanderValue = index == 0 ? 1 : 0;
    final es5OutputValue = index == 0 ? 1 : 0;
    final outputValue = index == 0 ? 13 : 14;

    final expanderNum = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: expanderNum,
        name: '$prefix:ES-5 Expander',
        min: 0,
        max: 6,
        defaultValue: 0,
        unit: 1,
        powerOfTen: 0,
      ),
    );
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: expanderNum,
        value: expanderValue,
      ),
    );

    final es5OutputNum = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: es5OutputNum,
        name: '$prefix:ES-5 Output',
        min: 1,
        max: 8,
        defaultValue: 1,
        unit: 1,
        powerOfTen: 0,
      ),
    );
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: es5OutputNum,
        value: es5OutputValue,
      ),
    );

    final outputNum = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: outputNum,
        name: '$prefix:Output',
        min: 1,
        max: 28,
        defaultValue: 13,
        unit: 1,
        powerOfTen: 0,
      ),
    );
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: outputNum,
        value: outputValue,
      ),
    );
  }

  return Slot(
    algorithm: Algorithm(
      algorithmIndex: algorithmIndex,
      guid: 'clck',
      name: 'Clock',
    ),
    routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: const []),
    pages: ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
    parameters: parameters,
    values: values,
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );
}
