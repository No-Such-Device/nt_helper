import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/saturator_algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Saturator Routing Integration', () {
    test(
      'AlgorithmRouting.fromSlot() returns SaturatorAlgorithmRouting for satu guid',
      () {
        final slot = _createSaturatorSlot(
          channelConfigs: [(channel: 1, input: 5, width: 1)],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'satu_integration',
        );

        expect(routing, isA<SaturatorAlgorithmRouting>());
      },
    );

    test('Saturator mono (width=1) creates correct ports and connections', () {
      final slot = _createSaturatorSlot(
        channelConfigs: [(channel: 1, input: 5, width: 1)],
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'satu_mono',
      );

      // Verify ports
      expect(routing.inputPorts.length, equals(1));
      expect(routing.outputPorts.length, equals(1));

      expect(routing.inputPorts[0].name, equals('1:Input'));
      expect(routing.inputPorts[0].busValue, equals(5));

      expect(routing.outputPorts[0].name, equals('1:Output'));
      expect(routing.outputPorts[0].busValue, equals(5));
      expect(routing.outputPorts[0].outputMode, equals(OutputMode.replace));

      // Verify connection discovery
      final connections = ConnectionDiscoveryService.discoverConnections([
        routing,
      ]);

      // Should have hardware input connection for bus 5
      final hwInputConn = connections.where(
        (c) =>
            c.connectionType == ConnectionType.hardwareInput &&
            c.busNumber == 5,
      );
      expect(hwInputConn.isNotEmpty, isTrue);
    });

    test('Saturator with width=3 creates numbered ports', () {
      final slot = _createSaturatorSlot(
        channelConfigs: [(channel: 1, input: 10, width: 3)],
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'satu_width3',
      );

      // Verify 3 input and 3 output ports
      expect(routing.inputPorts.length, equals(3));
      expect(routing.outputPorts.length, equals(3));

      // Verify naming
      expect(routing.inputPorts[0].name, equals('1:Input 1'));
      expect(routing.inputPorts[1].name, equals('1:Input 2'));
      expect(routing.inputPorts[2].name, equals('1:Input 3'));

      // Verify consecutive buses
      expect(routing.inputPorts[0].busValue, equals(10));
      expect(routing.inputPorts[1].busValue, equals(11));
      expect(routing.inputPorts[2].busValue, equals(12));

      // Verify all outputs have replace mode
      for (final output in routing.outputPorts) {
        expect(output.outputMode, equals(OutputMode.replace));
      }
    });

    test('Saturator multi-channel with different widths', () {
      final slot = _createSaturatorSlot(
        channelConfigs: [
          (channel: 1, input: 3, width: 2),
          (channel: 2, input: 8, width: 1),
        ],
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'satu_multi',
      );

      // Total: 2 + 1 = 3 inputs and 3 outputs
      expect(routing.inputPorts.length, equals(3));
      expect(routing.outputPorts.length, equals(3));

      // Channel 1: width=2
      expect(routing.inputPorts[0].name, equals('1:Input 1'));
      expect(routing.inputPorts[0].busValue, equals(3));
      expect(routing.inputPorts[1].name, equals('1:Input 2'));
      expect(routing.inputPorts[1].busValue, equals(4));

      // Channel 2: width=1
      expect(routing.inputPorts[2].name, equals('2:Input'));
      expect(routing.inputPorts[2].busValue, equals(8));
    });

    test(
      'Saturator with input on physical output bus creates correct connection',
      () {
        final slot = _createSaturatorSlot(
          channelConfigs: [
            (channel: 1, input: 15, width: 1),
          ], // Bus 15 = physical output O3
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'satu_phys_out',
        );

        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);

        // Should have connection from hw_out_3 to algorithm input
        final hwConn = connections.firstWhere(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_out_3' &&
              c.busNumber == 15,
          orElse: () =>
              throw Exception('Expected hw_out_3 connection not found'),
        );

        expect(hwConn.destinationPortId, contains('input'));
      },
    );

    test('Saturator end-to-end: factory → ports → connections', () {
      // Create a realistic Saturator configuration:
      // - 2 channels
      // - Channel 1: input on bus 5, width=2 (uses buses 5-6)
      // - Channel 2: input on bus 15 (physical output O3), width=1
      final slot = _createSaturatorSlot(
        channelConfigs: [
          (channel: 1, input: 5, width: 2),
          (channel: 2, input: 15, width: 1),
        ],
      );

      // Step 1: Create routing via factory
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'satu_e2e',
      );

      // Verify correct routing type
      expect(routing, isA<SaturatorAlgorithmRouting>());

      // Verify ports
      expect(routing.inputPorts.length, equals(3)); // 2 + 1
      expect(routing.outputPorts.length, equals(3));

      // Step 3: Discover connections
      final connections = ConnectionDiscoveryService.discoverConnections([
        routing,
      ]);

      // Should have hardware connections for all input buses
      final hwConns = connections
          .where((c) => c.connectionType == ConnectionType.hardwareInput)
          .toList();

      expect(hwConns.length, greaterThanOrEqualTo(3));

      // Verify specific connections
      expect(
        hwConns.any((c) => c.busNumber == 5 && c.sourcePortId == 'hw_in_5'),
        isTrue,
        reason: 'Should have hw_in_5 connection',
      );
      expect(
        hwConns.any((c) => c.busNumber == 6 && c.sourcePortId == 'hw_in_6'),
        isTrue,
        reason: 'Should have hw_in_6 connection',
      );
      expect(
        hwConns.any((c) => c.busNumber == 15 && c.sourcePortId == 'hw_out_3'),
        isTrue,
        reason: 'Should have hw_out_3 connection for physical output as input',
      );
    });
  });
}

Slot _createSaturatorSlot({
  required List<({int channel, int input, int width})> channelConfigs,
  int algorithmIndex = 0,
}) {
  final algorithm = Algorithm(
    algorithmIndex: algorithmIndex,
    guid: 'satu',
    name: 'Saturator',
  );

  final routing = RoutingInfo(
    algorithmIndex: algorithmIndex,
    routingInfo: List.filled(6, 0),
  );

  final pages = ParameterPages(algorithmIndex: algorithmIndex, pages: []);

  final parameters = <ParameterInfo>[];
  final values = <ParameterValue>[];

  int paramNum = 0;

  // Create parameters for each channel
  for (final config in channelConfigs) {
    final channel = config.channel;
    final inputParamNum = paramNum++;
    final widthParamNum = paramNum++;

    // Create Input parameter
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: inputParamNum,
        name: '$channel:Input',
        min: 1,
        max: 28,
        defaultValue: 1,
        unit: 1,
        powerOfTen: 0,
      ),
    );

    // Create Width parameter
    parameters.add(
      ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: widthParamNum,
        name: '$channel:Width',
        min: 1,
        max: 12,
        defaultValue: 1,
        unit: 1,
        powerOfTen: 0,
      ),
    );

    // Create values
    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: inputParamNum,
        value: config.input,
      ),
    );

    values.add(
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: widthParamNum,
        value: config.width,
      ),
    );
  }

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
