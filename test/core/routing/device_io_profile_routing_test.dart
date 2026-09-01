import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/bus_flow_solver.dart';
import 'package:nt_helper/core/routing/clock_algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/core/routing/poly_algorithm_routing.dart';
import 'package:nt_helper/core/routing/saturator_algorithm_routing.dart';
import 'package:nt_helper/core/routing/services/algorithm_connection_service.dart';
import 'package:nt_helper/core/routing/usb_from_algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/mcp/utils/bus_mapping.dart';
import 'package:nt_helper/models/algorithm_connection.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/physical_port_generator.dart';

void main() {
  final profile = DeviceIoProfile.tryCreate(
    inputBusCount: 4,
    outputBusCount: 3,
    auxBusCount: 5,
  )!;

  group('non-Disting routing contract', () {
    test('generic fallback infers direction from the current profile', () {
      final routing = MultiChannelAlgorithmRouting.createFromSlot(
        _slot(guid: 'plug'),
        deviceIoProfile: profile,
        ioParameters: const {'Before boundary': 4, 'At boundary': 5},
        algorithmUuid: 'generic',
      );

      expect(routing.inputPorts.single.busValue, 4);
      expect(routing.outputPorts.single.busValue, 5);
      expect(routing.deviceIoProfile, profile);
    });

    test('every specialized factory receives the same profile', () {
      final routings = <AlgorithmRouting>[
        AlgorithmRouting.fromSlot(
          _slot(
            guid: 'multi',
            parameters: [_busParameter(0, 'Input', 4, input: true)],
          ),
          deviceIoProfile: profile,
        ),
        AlgorithmRouting.fromSlot(
          _slot(guid: 'pynt'),
          deviceIoProfile: profile,
        ),
        AlgorithmRouting.fromSlot(
          _slot(
            guid: 'usbf',
            parameters: [_busParameter(0, 'Ch1 to', 13, output: true, max: 14)],
          ),
          deviceIoProfile: profile,
        ),
        AlgorithmRouting.fromSlot(
          _slot(
            guid: 'satu',
            parameters: [_busParameter(0, '1:Input', 4, input: true)],
          ),
          deviceIoProfile: profile,
        ),
        AlgorithmRouting.fromSlot(
          _slot(guid: 'clck'),
          deviceIoProfile: profile,
        ),
      ];

      expect(routings[0], isA<MultiChannelAlgorithmRouting>());
      expect(routings[1], isA<PolyAlgorithmRouting>());
      expect(routings[2], isA<UsbFromAlgorithmRouting>());
      expect(routings[3], isA<SaturatorAlgorithmRouting>());
      expect(routings[4], isA<ClockAlgorithmRouting>());
      expect(
        routings.map((routing) => routing.deviceIoProfile),
        everyElement(profile),
      );
    });

    test('physical, Aux, labels, and MCP conversions share the profile', () {
      final writer = AlgorithmRouting.fromSlot(
        _slot(
          guid: 'writer',
          parameters: [
            _busParameter(0, 'Hardware out', 5, output: true),
            _busParameter(1, 'Aux out', 8, output: true),
          ],
        ),
        deviceIoProfile: profile,
        algorithmUuid: 'writer',
      );
      final reader = AlgorithmRouting.fromSlot(
        _slot(
          guid: 'reader',
          algorithmIndex: 1,
          parameters: [
            _busParameter(0, 'Hardware in', 4, input: true, algorithmIndex: 1),
            _busParameter(1, 'Aux in', 8, input: true, algorithmIndex: 1),
          ],
        ),
        deviceIoProfile: profile,
        algorithmUuid: 'reader',
      );

      final connections = ConnectionDiscoveryService.discoverConnections([
        writer,
        reader,
      ], deviceIoProfile: profile);
      expect(
        connections.any(
          (connection) =>
              connection.busNumber == 5 &&
              connection.destinationPortId == 'hw_out_1',
        ),
        isTrue,
      );
      expect(
        connections.any(
          (connection) =>
              connection.busNumber == 4 && connection.sourcePortId == 'hw_in_4',
        ),
        isTrue,
      );
      expect(
        connections.any(
          (connection) =>
              connection.busNumber == 8 &&
              connection.connectionType == ConnectionType.algorithmToAlgorithm,
        ),
        isTrue,
      );

      expect(
        PhysicalPortGenerator.generatePhysicalInputPorts(
          deviceIoProfile: profile,
        ),
        hasLength(4),
      );
      expect(
        PhysicalPortGenerator.generatePhysicalOutputPorts(
          deviceIoProfile: profile,
        ),
        hasLength(3),
      );
      expect(
        BusMapping.busToName(5, deviceIoProfile: profile, includeEs5: false),
        'Output 1',
      );
      expect(
        BusMapping.nameToBus(
          'Aux 5',
          deviceIoProfile: profile,
          includeEs5: false,
        ),
        12,
      );
      expect(
        BusMapping.parseBus(-1, deviceIoProfile: profile, includeEs5: false),
        isNull,
      );
      expect(
        BusMapping.parseBus(13, deviceIoProfile: profile, includeEs5: false),
        isNull,
      );
    });

    test('bus-flow solving seeds only the profile input range', () {
      final solution = BusFlowSolver(const [
        SlotBusUsage(
          id: 'reader',
          index: 0,
          name: 'Reader',
          reads: {4, 8},
          writes: {},
        ),
        SlotBusUsage(
          id: 'writer',
          index: 1,
          name: 'Writer',
          reads: {},
          writes: {8},
        ),
      ], deviceIoProfile: profile).solve();

      expect(solution.order, ['writer', 'reader']);
      expect(
        BusFlowSolver.busOrdersReads(4, deviceIoProfile: profile),
        isFalse,
      );
      expect(BusFlowSolver.busOrdersReads(5, deviceIoProfile: profile), isTrue);
    });

    test('ES-5 is contextual to USB From Host', () {
      final usb = AlgorithmRouting.fromSlot(
        _slot(
          guid: 'usbf',
          parameters: [_busParameter(0, 'Ch1 to', 13, output: true, max: 14)],
        ),
        deviceIoProfile: profile,
        algorithmUuid: 'usb',
      );
      final ordinary = AlgorithmRouting.fromSlot(
        _slot(
          guid: 'ordinary',
          parameters: [_busParameter(0, 'Output', 13, output: true, max: 14)],
        ),
        deviceIoProfile: profile,
        algorithmUuid: 'ordinary',
      );

      final connections = ConnectionDiscoveryService.discoverConnections([
        usb,
        ordinary,
      ], deviceIoProfile: profile);
      expect(
        connections.where(
          (connection) => connection.destinationPortId == 'es5_L',
        ),
        hasLength(1),
      );
      expect(
        connections
            .singleWhere(
              (connection) => connection.destinationPortId == 'es5_L',
            )
            .sourcePortId,
        contains('usb'),
      );
    });

    test(
      'algorithm connection cache and physical targets include the profile',
      () {
        final slots = [
          _slot(
            guid: 'writer',
            parameters: [
              _busParameter(0, 'Physical', 5, output: true),
              _busParameter(1, 'Aux', 8, output: true),
            ],
          ),
          _slot(
            guid: 'reader',
            algorithmIndex: 1,
            parameters: [
              _busParameter(0, 'Aux input', 8, input: true, algorithmIndex: 1),
            ],
          ),
        ];
        final service = AlgorithmConnectionService();

        final connections = service.discoverAlgorithmConnections(
          slots,
          deviceIoProfile: profile,
        );
        expect(
          connections.any(
            (connection) =>
                connection.busNumber == 5 && connection.isPhysicalOutput,
          ),
          isTrue,
        );
        expect(
          connections.any(
            (connection) =>
                connection.busNumber == 8 && !connection.isPhysicalOutput,
          ),
          isTrue,
        );
      },
    );
  });
}

ParameterInfo _busParameter(
  int parameterNumber,
  String name,
  int value, {
  int algorithmIndex = 0,
  bool input = false,
  bool output = false,
  int max = 14,
}) => ParameterInfo(
  algorithmIndex: algorithmIndex,
  parameterNumber: parameterNumber,
  name: name,
  min: 0,
  max: max,
  defaultValue: value,
  unit: 1,
  powerOfTen: 0,
  ioFlags: (input ? 1 : 0) | (output ? 2 : 0),
);

Slot _slot({
  required String guid,
  int algorithmIndex = 0,
  List<ParameterInfo> parameters = const [],
}) => Slot(
  algorithm: Algorithm(algorithmIndex: algorithmIndex, guid: guid, name: guid),
  routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
  parameters: parameters,
  values: [
    for (final parameter in parameters)
      ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameter.parameterNumber,
        value: parameter.defaultValue,
      ),
  ],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
