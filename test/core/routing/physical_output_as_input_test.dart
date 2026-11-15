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

void main() {
  group('Physical Output as Input Source', () {
    test('creates hardware input connection for algorithm input on bus 15 (physical output O3)', () {
      // Algorithm with input on bus 15 (physical output O3)
      final algo = _FakeRouting(
        id: 'test_algo',
        inputs: [_inPort('test_in', 15)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([algo]);

      // Should create connection from hw_out_3 to algorithm input
      final hwConn = conns.firstWhere(
        (c) =>
            c.connectionType == ConnectionType.hardwareInput &&
            c.sourcePortId == 'hw_out_3' &&
            c.destinationPortId == 'test_in',
        orElse: () =>
            throw Exception('Expected hardware input connection not found'),
      );

      expect(hwConn.busNumber, equals(15));
      expect(hwConn.connectionType, equals(ConnectionType.hardwareInput));
    });

    test(
      'creates hardware input connection for bus 13 (physical output O1)',
      () {
        final algo = _FakeRouting(
          id: 'test_algo',
          inputs: [_inPort('test_in', 13)],
        );

        final conns = ConnectionDiscoveryService.discoverConnections([algo]);

        final hwConn = conns.firstWhere(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_out_1',
          orElse: () =>
              throw Exception('Expected hw_out_1 connection not found'),
        );

        expect(hwConn.busNumber, equals(13));
      },
    );

    test(
      'creates hardware input connection for bus 20 (physical output O8)',
      () {
        final algo = _FakeRouting(
          id: 'test_algo',
          inputs: [_inPort('test_in', 20)],
        );

        final conns = ConnectionDiscoveryService.discoverConnections([algo]);

        final hwConn = conns.firstWhere(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_out_8',
          orElse: () =>
              throw Exception('Expected hw_out_8 connection not found'),
        );

        expect(hwConn.busNumber, equals(20));
      },
    );

    test('still creates hardware input connections for buses 1-12 (regression test)', () {
      final algo = _FakeRouting(
        id: 'test_algo',
        inputs: [_inPort('in_1', 1), _inPort('in_5', 5), _inPort('in_12', 12)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([algo]);

      // Should have hardware input connections for buses 1, 5, 12
      final hwConns = conns
          .where((c) => c.connectionType == ConnectionType.hardwareInput)
          .toList();

      expect(hwConns.length, greaterThanOrEqualTo(3));

      // Verify specific connections
      expect(
        hwConns.any((c) => c.sourcePortId == 'hw_in_1' && c.busNumber == 1),
        isTrue,
        reason: 'Should have hw_in_1 connection',
      );
      expect(
        hwConns.any((c) => c.sourcePortId == 'hw_in_5' && c.busNumber == 5),
        isTrue,
        reason: 'Should have hw_in_5 connection',
      );
      expect(
        hwConns.any((c) => c.sourcePortId == 'hw_in_12' && c.busNumber == 12),
        isTrue,
        reason: 'Should have hw_in_12 connection',
      );
    });

    test('does NOT create hardware connection for aux bus 21', () {
      final algo = _FakeRouting(
        id: 'test_algo',
        inputs: [_inPort('test_in', 21)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([algo]);

      // Should NOT have any hardware input connection for bus 21
      final hwConns = conns.where(
        (c) =>
            c.connectionType == ConnectionType.hardwareInput &&
            c.busNumber == 21,
      );

      expect(
        hwConns.isEmpty,
        isTrue,
        reason: 'Aux bus 21 should not create hardware connection',
      );
    });

    test('does NOT create hardware connection for aux bus 28', () {
      final algo = _FakeRouting(
        id: 'test_algo',
        inputs: [_inPort('test_in', 28)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([algo]);

      final hwConns = conns.where(
        (c) =>
            c.connectionType == ConnectionType.hardwareInput &&
            c.busNumber == 28,
      );

      expect(
        hwConns.isEmpty,
        isTrue,
        reason: 'Aux bus 28 should not create hardware connection',
      );
    });
  });
}
