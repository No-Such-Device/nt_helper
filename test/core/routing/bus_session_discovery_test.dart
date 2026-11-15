import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart' as core;
import 'package:nt_helper/core/routing/models/routing_state.dart';

/// Minimal fake routing for testing discovery; provides only ports/state.
class _FakeRouting extends AlgorithmRouting {
  final String _id;
  final List<core.Port> _inputs;
  final List<core.Port> _outputs;

  RoutingState _state = const RoutingState();

  _FakeRouting({
    required this._id,
    List<core.Port>? inputs,
    List<core.Port>? outputs,
  }) : _inputs = inputs ?? const [],
       _outputs = outputs ?? const [] {
    algorithmUuid = _id;
  }

  @override
  RoutingState get state => _state;

  @override
  List<core.Port> get inputPorts => _inputs;

  @override
  List<core.Port> get outputPorts => _outputs;

  @override
  List<Connection> get connections => const [];

  @override
  List<core.Port> generateInputPorts() => _inputs;

  @override
  List<core.Port> generateOutputPorts() => _outputs;

  @override
  void updateState(RoutingState newState) => _state = newState;
}

core.Port _inPort(
  String id,
  int bus, {
  core.PortType type = core.PortType.audio,
}) {
  return core.Port(
    id: id,
    name: id,
    type: type,
    direction: core.PortDirection.input,
    busValue: bus,
    parameterNumber: 1,
  );
}

core.Port _outPort(
  String id,
  int bus, {
  core.OutputMode? mode,
  core.PortType type = core.PortType.audio,
}) {
  return core.Port(
    id: id,
    name: id,
    type: type,
    direction: core.PortDirection.output,
    busValue: bus,
    parameterNumber: 2,
    outputMode: mode,
  );
}

void main() {
  group('Session-aware discovery', () {
    test('physical input bus uses hw path for algorithm writers', () {
      // Slots 0..3 on bus 1 (physical input).
      // When algorithm outputs write to a physical bus, connections route
      // through the hw_in node instead of direct algo→algo.
      final s0 = _FakeRouting(
        id: 'slot0',
        outputs: [
          _outPort(
            's0_out_b1',
            1 /* hw input bus */,
            mode: core.OutputMode.add,
          ),
        ],
      );
      final s1 = _FakeRouting(id: 'slot1', inputs: [_inPort('s1_in_b1', 1)]);
      final s2 = _FakeRouting(
        id: 'slot2',
        outputs: [_outPort('s2_out_b1', 1, mode: core.OutputMode.replace)],
      );
      final s3 = _FakeRouting(id: 'slot3', inputs: [_inPort('s3_in_b1', 1)]);

      final conns = ConnectionDiscoveryService.discoverConnections([
        s0,
        s1,
        s2,
        s3,
      ]);

      // Algorithm outputs write to hw_in_1
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 's0_out_b1' &&
              c.destinationPortId == 'hw_in_1',
        ),
        isTrue,
      );
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 's2_out_b1' &&
              c.destinationPortId == 'hw_in_1',
        ),
        isTrue,
      );

      // Both readers connect from hw_in_1
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_in_1' &&
              c.destinationPortId == 's1_in_b1',
        ),
        isTrue,
      );
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_in_1' &&
              c.destinationPortId == 's3_in_b1',
        ),
        isTrue,
      );

      // No direct algo→algo on physical input buses
      expect(
        conns.any(
          (c) => c.connectionType == ConnectionType.algorithmToAlgorithm,
        ),
        isFalse,
      );
    });

    test('hardware output shows all writers as connected', () {
      // Bus 18 (hardware output index 6). All writers should get solid
      // connections because multiple Replace writers can all contribute
      // in practice (e.g., step sequencers on different clock cycles).
      final s0 = _FakeRouting(
        id: 'slot0',
        outputs: [_outPort('s0_out_b18', 18, mode: core.OutputMode.add)],
      );
      final s1 = _FakeRouting(id: 'slot1');
      final s2 = _FakeRouting(
        id: 'slot2',
        outputs: [_outPort('s2_out_b18', 18, mode: core.OutputMode.replace)],
      );
      final s3 = _FakeRouting(
        id: 'slot3',
        outputs: [_outPort('s3_out_b18', 18, mode: core.OutputMode.add)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([
        s0,
        s1,
        s2,
        s3,
      ]);

      // All three writers get hardware output connections
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 's0_out_b18' &&
              c.busNumber == 18,
        ),
        isTrue,
      );
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 's2_out_b18' &&
              c.busNumber == 18,
        ),
        isTrue,
      );
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 's3_out_b18' &&
              c.busNumber == 18,
        ),
        isTrue,
      );
    });

    test(
      'algorithm output to physical input bus creates hw_in write connection',
      () {
        // An algorithm output on bus 3 (physical input) should create
        // a connection to hw_in_3, just like output buses create connections
        // to hw_out_N.
        final s0 = _FakeRouting(
          id: 'slot0',
          outputs: [_outPort('s0_out_b3', 3, mode: core.OutputMode.replace)],
        );
        final s1 = _FakeRouting(id: 'slot1', inputs: [_inPort('s1_in_b3', 3)]);

        final conns = ConnectionDiscoveryService.discoverConnections([s0, s1]);

        // Writer → hw_in_3
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.sourcePortId == 's0_out_b3' &&
                c.destinationPortId == 'hw_in_3' &&
                c.busNumber == 3,
          ),
          isTrue,
        );

        // hw_in_3 → reader
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareInput &&
                c.sourcePortId == 'hw_in_3' &&
                c.destinationPortId == 's1_in_b3' &&
                c.busNumber == 3,
          ),
          isTrue,
        );

        // No direct algo→algo
        expect(
          conns.any(
            (c) => c.connectionType == ConnectionType.algorithmToAlgorithm,
          ),
          isFalse,
        );

        // No partial connections (all ports matched)
        expect(conns.any((c) => c.isPartial), isFalse);
      },
    );

    test(
      'physical input bus with only readers still shows hw_in connection',
      () {
        // When there are no algorithm outputs on a physical input bus,
        // the hardware seed (physical jack) still feeds the reader.
        final s0 = _FakeRouting(id: 'slot0', inputs: [_inPort('s0_in_b4', 4)]);

        final conns = ConnectionDiscoveryService.discoverConnections([s0]);

        // hw_in_4 → reader (hardware seed contributes)
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareInput &&
                c.sourcePortId == 'hw_in_4' &&
                c.destinationPortId == 's0_in_b4',
          ),
          isTrue,
        );

        // No write connections (no outputs)
        expect(
          conns.any((c) => c.connectionType == ConnectionType.hardwareOutput),
          isFalse,
        );
      },
    );

    test('aux bus still uses direct algo→algo connections', () {
      // Auxiliary buses (21+) should still use direct algorithm-to-algorithm
      // connections, not route through hardware nodes.
      final s0 = _FakeRouting(
        id: 'slot0',
        outputs: [_outPort('s0_out_b25', 25)],
      );
      final s1 = _FakeRouting(id: 'slot1', inputs: [_inPort('s1_in_b25', 25)]);

      final conns = ConnectionDiscoveryService.discoverConnections([s0, s1]);

      // Direct algo→algo
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.sourcePortId == 's0_out_b25' &&
              c.destinationPortId == 's1_in_b25',
        ),
        isTrue,
      );

      // No hardware connections on aux buses
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput ||
              c.connectionType == ConnectionType.hardwareOutput,
        ),
        isFalse,
      );
    });
  });
}
