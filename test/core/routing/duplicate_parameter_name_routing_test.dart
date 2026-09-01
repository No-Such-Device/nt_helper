import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('duplicate parameter name routing', () {
    test(
      'preserves mixer channel inputs that share the same parameter names',
      () {
        final routing = AlgorithmRouting.fromSlot(
          _createMixerSlotWithChannels(),
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );

        expect(
          routing.inputPorts.map((p) => p.busValue),
          containsAll(<int>[11, 12, 10, 9]),
        );
        expect(
          routing.inputPorts.map((p) => p.parameterNumber),
          containsAll(<int>[10, 11, 20, 21, 30, 31]),
        );
        expect(
          routing.inputPorts.map((p) => p.name),
          containsAll(<String>[
            'Channel 1: From:Input left/mono',
            'Channel 1: From:Input right',
            'Channel 2: From:Input left/mono',
            'Channel 3: From:Input left/mono',
          ]),
        );
      },
    );

    test(
      'discovers hardware input connections for duplicated mixer inputs',
      () {
        final routing = AlgorithmRouting.fromSlot(
          _createMixerSlotWithChannels(),
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'mixer_1',
        );

        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);
        final hardwareInputs = connections
            .where((c) => c.connectionType == ConnectionType.hardwareInput)
            .toList();

        expect(
          hardwareInputs.map((c) => c.busNumber),
          containsAll(<int>[11, 12, 10, 9]),
        );
        expect(
          hardwareInputs
              .where((c) => c.busNumber == 11 || c.busNumber == 12)
              .map((c) => c.algorithmId)
              .toSet(),
          equals({'mixer_1'}),
        );
      },
    );
  });
}

Slot _createMixerSlotWithChannels() {
  const algorithmIndex = 0;
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: algorithmIndex,
      guid: 'mixs',
      name: 'Mixer Stereo',
    ),
    routing: RoutingInfo(
      algorithmIndex: algorithmIndex,
      routingInfo: List.filled(6, 0),
    ),
    pages: ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: [
        ParameterPage(name: 'Channel 1', parameters: [10, 11]),
        ParameterPage(name: 'Channel 2', parameters: [20, 21]),
        ParameterPage(name: 'Channel 3', parameters: [30, 31]),
      ],
    ),
    parameters: [
      _inputParameter(10, 'From:Input left/mono'),
      _inputParameter(11, 'From:Input right'),
      _inputParameter(20, 'From:Input left/mono'),
      _inputParameter(21, 'From:Input right'),
      _inputParameter(30, 'From:Input left/mono'),
      _inputParameter(31, 'From:Input right'),
    ],
    values: [
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 10,
        value: 11,
      ),
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 11,
        value: 12,
      ),
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 20,
        value: 10,
      ),
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 21,
        value: 0,
      ),
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 30,
        value: 9,
      ),
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: 31,
        value: 0,
      ),
    ],
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );
}

ParameterInfo _inputParameter(int parameterNumber, String name) {
  const algorithmIndex = 0;
  return ParameterInfo(
    algorithmIndex: algorithmIndex,
    parameterNumber: parameterNumber,
    name: name,
    min: 0,
    max: 64,
    defaultValue: 0,
    unit: 1,
    powerOfTen: 0,
    ioFlags: 5, // isInput | isAudio
  );
}
