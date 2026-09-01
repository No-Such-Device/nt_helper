import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Conditional in-place: Output=None → write to Input bus', () {
    test('attn with Input=5, Output=0 routes real replace output to bus 5', () {
      final slot = _createInputOutputSlot(
        guid: 'attn',
        name: 'Attenuverter',
        inputBus: 5,
        outputBus: 0,
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'attn_t',
      );

      expect(
        routing.outputPorts.length,
        equals(1),
        reason: 'Should preserve the real output port',
      );

      final out = routing.outputPorts.single;
      expect(out.parameterNumber, equals(1));
      expect(out.busValue, equals(5));
      expect(out.outputMode, equals(OutputMode.replace));
      expect(out.modeParameterNumber, isNull);
    });

    test('attn with Input=5, Output=7 produces normal output on bus 7', () {
      final slot = _createInputOutputSlot(
        guid: 'attn',
        name: 'Attenuverter',
        inputBus: 5,
        outputBus: 7,
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'attn_t',
      );

      final out = routing.outputPorts.firstWhere((p) => p.parameterNumber == 1);
      expect(out.busValue, equals(7));
    });

    test(
      'attn with Input=0, Output=0 keeps editable disconnected output port',
      () {
        final slot = _createInputOutputSlot(
          guid: 'attn',
          name: 'Attenuverter',
          inputBus: 0,
          outputBus: 0,
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'attn_t',
        );

        expect(routing.outputPorts.length, equals(1));
        final out = routing.outputPorts.single;
        expect(out.parameterNumber, equals(1));
        expect(out.busValue, equals(0));
      },
    );

    test('vcam (spot-check): Output=None → virtual replace on Input bus', () {
      final slot = _createInputOutputSlot(
        guid: 'vcam',
        name: 'VCA Mixer',
        inputBus: 9,
        outputBus: 0,
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'vcam_t',
      );

      expect(routing.outputPorts.length, equals(1));
      final out = routing.outputPorts.single;
      expect(out.parameterNumber, equals(1));
      expect(out.busValue, equals(9));
      expect(out.outputMode, equals(OutputMode.replace));
    });

    test(
      'algorithm not in conditional-in-place list: Output=0 stays as-is',
      () {
        // 'unkn' is not in _conditionalInPlaceGuids - should keep existing
        // behaviour (output port with busValue=0).
        final slot = _createInputOutputSlot(
          guid: 'unkn',
          name: 'Unknown',
          inputBus: 5,
          outputBus: 0,
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'unkn_t',
        );

        // The disconnected output port should still be present.
        final out = routing.outputPorts.firstWhere(
          (p) => p.parameterNumber == 1,
        );
        expect(out.busValue, equals(0));
      },
    );
  });
}

/// Creates a slot with a single bus Input and a single bus Output parameter.
/// Used to test the "Output = None → write to Input bus" behaviour.
Slot _createInputOutputSlot({
  required String guid,
  required String name,
  required int inputBus,
  required int outputBus,
}) {
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
      defaultValue: inputBus,
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
      defaultValue: outputBus,
      unit: 1,
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
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );
}
