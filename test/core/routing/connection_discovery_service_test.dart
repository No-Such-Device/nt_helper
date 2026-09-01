import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart' as core;
import 'package:nt_helper/core/routing/models/routing_state.dart';
import 'package:nt_helper/core/routing/usb_from_algorithm_routing.dart';

/// Minimal fake routing for testing discovery; provides only ports/state.
class _FakeRouting extends AlgorithmRouting {
  final String _id;
  final List<core.Port> _inputs;
  final List<core.Port> _outputs;

  RoutingState _state = const RoutingState();

  _FakeRouting({
    required String id,
    List<core.Port>? inputs,
    List<core.Port>? outputs,
  }) : _id = id,
       _inputs = inputs ?? const [],
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

/// USB From Host test double. ES-5 is intentionally contextual to this routing
/// implementation rather than being a general-purpose bus range.
class _FakeUsbFromRouting extends UsbFromAlgorithmRouting {
  final List<core.Port> _outputs;

  _FakeUsbFromRouting({required String id, required List<core.Port> outputs})
    : _outputs = outputs,
      super(properties: const {}, algorithmUuid: id);

  @override
  List<core.Port> get outputPorts => _outputs;

  @override
  List<core.Port> generateOutputPorts() => _outputs;
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
  group('ConnectionDiscoveryService', () {
    test('physical input bus 2 uses hw path instead of direct algo→algo', () {
      final a = _FakeRouting(id: 'algo_A', outputs: [_outPort('A_out_b2', 2)]);
      final b = _FakeRouting(id: 'algo_B', inputs: [_inPort('B_in_b2', 2)]);

      final conns = ConnectionDiscoveryService.discoverConnections([a, b]);

      // Algorithm output writes to hw_in_2
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 'A_out_b2' &&
              c.destinationPortId == 'hw_in_2' &&
              c.busNumber == 2,
        ),
        isTrue,
      );

      // Hardware input feeds algorithm: hw_in_2 → B_in_b2
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.sourcePortId == 'hw_in_2' &&
              c.destinationPortId == 'B_in_b2' &&
              c.busNumber == 2,
        ),
        isTrue,
      );

      // No direct algo→algo on physical input buses
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.busNumber == 2,
        ),
        isFalse,
      );
    });

    test('physical output bus 18 uses hw path instead of direct algo→algo', () {
      final a = _FakeRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b18', 18)],
      );
      final b = _FakeRouting(id: 'algo_B', inputs: [_inPort('B_in_b18', 18)]);

      final conns = ConnectionDiscoveryService.discoverConnections([a, b]);

      // Hardware output connection: A_out_b18 → hw_out_6 (bus 18 ⇒ 18-12 = 6)
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 18 &&
              c.destinationPortId == 'hw_out_6',
        ),
        isTrue,
      );

      // Physical output as input: hw_out_6 → B_in_b18
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.busNumber == 18 &&
              c.sourcePortId == 'hw_out_6' &&
              c.destinationPortId == 'B_in_b18',
        ),
        isTrue,
      );

      // No direct algo→algo on physical output buses
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.busNumber == 18,
        ),
        isFalse,
      );
    });

    test('aux bus 25 yields only algo→algo (no hardware edges)', () {
      final a = _FakeRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b25', 25)],
      );
      final b = _FakeRouting(id: 'algo_B', inputs: [_inPort('B_in_b25', 25)]);

      final conns = ConnectionDiscoveryService.discoverConnections([a, b]);

      // Algo→algo present
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.busNumber == 25,
        ),
        isTrue,
      );

      // No hardware input/output edges on aux
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.busNumber == 25,
        ),
        isFalse,
      );
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 25,
        ),
        isFalse,
      );
    });

    test('ES-5 bus 29 creates connection to es5_L port', () {
      final a = _FakeUsbFromRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b29', 29)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([a]);

      // Hardware output connection from A_out_b29 to es5_L
      final es5Conn = conns.firstWhere(
        (c) =>
            c.connectionType == ConnectionType.hardwareOutput &&
            c.busNumber == 29 &&
            c.destinationPortId == 'es5_L',
      );

      expect(es5Conn.sourcePortId, 'A_out_b29');
      expect(es5Conn.signalType, SignalType.audio);
      expect(es5Conn.isOutput, isTrue);
    });

    test('ES-5 bus 30 creates connection to es5_R port', () {
      final a = _FakeUsbFromRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b30', 30)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([a]);

      // Hardware output connection from A_out_b30 to es5_R
      final es5Conn = conns.firstWhere(
        (c) =>
            c.connectionType == ConnectionType.hardwareOutput &&
            c.busNumber == 30 &&
            c.destinationPortId == 'es5_R',
      );

      expect(es5Conn.sourcePortId, 'A_out_b30');
      expect(es5Conn.signalType, SignalType.audio);
      expect(es5Conn.isOutput, isTrue);
    });

    test(
      'mixed USB outputs (ES-5 and standard) create correct connections',
      () {
        final usbFromHost = _FakeUsbFromRouting(
          id: 'usb_from_host',
          outputs: [
            _outPort('usb_ch1', 13), // Standard output 1
            _outPort('usb_ch2', 29), // ES-5 L
            _outPort('usb_ch3', 30), // ES-5 R
            _outPort('usb_ch4', 14), // Standard output 2
          ],
        );

        final conns = ConnectionDiscoveryService.discoverConnections([
          usbFromHost,
        ]);

        // Standard output to hw_out_1 (bus 13)
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.busNumber == 13 &&
                c.destinationPortId == 'hw_out_1',
          ),
          isTrue,
        );

        // ES-5 L connection (bus 29)
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.busNumber == 29 &&
                c.destinationPortId == 'es5_L' &&
                c.signalType == SignalType.audio,
          ),
          isTrue,
        );

        // ES-5 R connection (bus 30)
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.busNumber == 30 &&
                c.destinationPortId == 'es5_R' &&
                c.signalType == SignalType.audio,
          ),
          isTrue,
        );

        // Standard output to hw_out_2 (bus 14)
        expect(
          conns.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.busNumber == 14 &&
                c.destinationPortId == 'hw_out_2',
          ),
          isTrue,
        );
      },
    );

    test('firmware 1.15+: bus 65 creates ES-5 L, bus 29 becomes aux', () {
      final usbFromHost = _FakeUsbFromRouting(
        id: 'usb_from_host',
        outputs: [
          _outPort('usb_ch1', 65), // ES-5 L on 1.15+
          _outPort('usb_ch2', 66), // ES-5 R on 1.15+
        ],
      );
      final auxAlgo = _FakeRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b29', 29)], // Aux 9 on 1.15+
      );

      final conns = ConnectionDiscoveryService.discoverConnections([
        auxAlgo,
        usbFromHost,
      ], hasExtendedAuxBuses: true);

      // Bus 65 should create ES-5 L hardware output connection
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 65 &&
              c.destinationPortId == 'es5_L' &&
              c.signalType == SignalType.audio,
        ),
        isTrue,
      );

      // Bus 66 should create ES-5 R hardware output connection
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 66 &&
              c.destinationPortId == 'es5_R' &&
              c.signalType == SignalType.audio,
        ),
        isTrue,
      );

      // Bus 29 should NOT create ES-5 connection on 1.15+ (it's aux now)
      expect(
        conns.any((c) => c.destinationPortId == 'es5_L' && c.busNumber == 29),
        isFalse,
      );

      // Bus 29 should be treated as aux (partial connection, not hardware output)
      expect(
        conns.any(
          (c) =>
              c.busNumber == 29 &&
              c.connectionType == ConnectionType.hardwareOutput &&
              c.destinationPortId.startsWith('es5_'),
        ),
        isFalse,
      );
    });

    test('legacy firmware: bus 29 creates ES-5 L, bus 65 is not ES-5', () {
      final a = _FakeUsbFromRouting(
        id: 'algo_A',
        outputs: [_outPort('A_out_b29', 29)],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([
        a,
      ], hasExtendedAuxBuses: false);

      // Bus 29 should create ES-5 L connection on legacy firmware
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 29 &&
              c.destinationPortId == 'es5_L',
        ),
        isTrue,
      );
    });

    test('ES-5 connections do not affect standard output routing', () {
      final a = _FakeRouting(
        id: 'algo_A',
        outputs: [
          _outPort('A_out_b13', 13), // Standard
          _outPort('A_out_b20', 20), // Standard
        ],
      );

      final conns = ConnectionDiscoveryService.discoverConnections([a]);

      // Verify standard outputs still work correctly
      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 13 &&
              c.destinationPortId == 'hw_out_1',
        ),
        isTrue,
      );

      expect(
        conns.any(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.busNumber == 20 &&
              c.destinationPortId == 'hw_out_8',
        ),
        isTrue,
      );

      // No ES-5 connections should exist
      expect(
        conns.any(
          (c) =>
              c.destinationPortId == 'es5_L' || c.destinationPortId == 'es5_R',
        ),
        isFalse,
      );
    });

    group('backward-edge discovery', () {
      test(
        'Replace + backward: writer in higher slot produces single backward edge',
        () {
          // Reader in slot 0, writer in slot 1 on aux bus 25 (non-physical).
          // Writer uses Replace mode. Bus values persist across audio frames,
          // so the reader sees the writer's value one block later — this is
          // a backward edge regardless of OutputMode.
          final reader = _FakeRouting(
            id: 'algo_reader',
            inputs: [_inPort('reader_in_b25', 25)],
          );
          final writer = _FakeRouting(
            id: 'algo_writer',
            outputs: [
              _outPort('writer_out_b25', 25, mode: core.OutputMode.replace),
            ],
          );

          final conns = ConnectionDiscoveryService.discoverConnections([
            reader,
            writer,
          ]);

          final backwardConns = conns
              .where(
                (c) =>
                    c.connectionType == ConnectionType.algorithmToAlgorithm &&
                    c.sourcePortId == 'writer_out_b25' &&
                    c.destinationPortId == 'reader_in_b25',
              )
              .toList();

          expect(backwardConns, hasLength(1));
          final edge = backwardConns.single;
          expect(edge.isBackwardEdge, isTrue);
          expect(edge.isPartial, isFalse);
          expect(edge.outputMode, core.OutputMode.replace);
          expect(edge.busNumber, 25);

          // No partial chip connections should exist for either port.
          expect(
            conns.any(
              (c) =>
                  c.isPartial &&
                  (c.sourcePortId == 'writer_out_b25' ||
                      c.destinationPortId == 'writer_out_b25' ||
                      c.sourcePortId == 'reader_in_b25' ||
                      c.destinationPortId == 'reader_in_b25'),
            ),
            isFalse,
          );
        },
      );

      test(
        'Add + backward: writer in higher slot produces single backward edge',
        () {
          // Same topology as the Replace case, but writer uses Add. This
          // case worked before the fix — it locks in non-regression.
          final reader = _FakeRouting(
            id: 'algo_reader',
            inputs: [_inPort('reader_in_b25', 25)],
          );
          final writer = _FakeRouting(
            id: 'algo_writer',
            outputs: [
              _outPort('writer_out_b25', 25, mode: core.OutputMode.add),
            ],
          );

          final conns = ConnectionDiscoveryService.discoverConnections([
            reader,
            writer,
          ]);

          final backwardConns = conns
              .where(
                (c) =>
                    c.connectionType == ConnectionType.algorithmToAlgorithm &&
                    c.sourcePortId == 'writer_out_b25' &&
                    c.destinationPortId == 'reader_in_b25',
              )
              .toList();

          expect(backwardConns, hasLength(1));
          final edge = backwardConns.single;
          expect(edge.isBackwardEdge, isTrue);
          expect(edge.isPartial, isFalse);
          expect(edge.outputMode, core.OutputMode.add);
        },
      );

      test(
        'self-write: same-algorithm in/out on same bus is not connected',
        () {
          // A single algorithm with both an input port and an output port on
          // bus 25. The output.algorithmId == input.algorithmId guard must
          // skip the pair, even with the backward-edge guard relaxed.
          final self = _FakeRouting(
            id: 'algo_self',
            inputs: [_inPort('self_in_b25', 25)],
            outputs: [
              _outPort('self_out_b25', 25, mode: core.OutputMode.replace),
            ],
          );

          final conns = ConnectionDiscoveryService.discoverConnections([self]);

          expect(
            conns.any(
              (c) =>
                  c.connectionType == ConnectionType.algorithmToAlgorithm &&
                  c.sourcePortId == 'self_out_b25' &&
                  c.destinationPortId == 'self_in_b25',
            ),
            isFalse,
          );
        },
      );

      test('Replace + forward: writer in lower slot produces forward edge', () {
        // Routings list [writer, reader]: writer.algorithmIndex == 0,
        // reader.algorithmIndex == 1. Writer uses Replace. Confirms the
        // fix didn't accidentally re-classify forward connections.
        final writer = _FakeRouting(
          id: 'algo_writer',
          outputs: [
            _outPort('writer_out_b25', 25, mode: core.OutputMode.replace),
          ],
        );
        final reader = _FakeRouting(
          id: 'algo_reader',
          inputs: [_inPort('reader_in_b25', 25)],
        );

        final conns = ConnectionDiscoveryService.discoverConnections([
          writer,
          reader,
        ]);

        final forwardConns = conns
            .where(
              (c) =>
                  c.connectionType == ConnectionType.algorithmToAlgorithm &&
                  c.sourcePortId == 'writer_out_b25' &&
                  c.destinationPortId == 'reader_in_b25',
            )
            .toList();

        expect(forwardConns, hasLength(1));
        final edge = forwardConns.single;
        expect(edge.isBackwardEdge, isFalse);
        expect(edge.isPartial, isFalse);
        expect(edge.outputMode, core.OutputMode.replace);
      });

      test(
        'multiple Replace writers in higher slots produce one backward edge per writer',
        () {
          // Reader in slot 0, two Replace writers in slots 1 and 2 on bus 25.
          // Discovery is per (writer, reader) pair — matches dd7811d's
          // original behavior. A future contribution-aware filter on the
          // backward branch would be a deliberate, test-visible change.
          final reader = _FakeRouting(
            id: 'algo_reader',
            inputs: [_inPort('reader_in_b25', 25)],
          );
          final writer1 = _FakeRouting(
            id: 'algo_writer1',
            outputs: [
              _outPort('writer1_out_b25', 25, mode: core.OutputMode.replace),
            ],
          );
          final writer2 = _FakeRouting(
            id: 'algo_writer2',
            outputs: [
              _outPort('writer2_out_b25', 25, mode: core.OutputMode.replace),
            ],
          );

          final conns = ConnectionDiscoveryService.discoverConnections([
            reader,
            writer1,
            writer2,
          ]);

          final backwardConns = conns
              .where(
                (c) =>
                    c.connectionType == ConnectionType.algorithmToAlgorithm &&
                    c.destinationPortId == 'reader_in_b25' &&
                    c.isBackwardEdge,
              )
              .toList();

          expect(backwardConns, hasLength(2));
          for (final edge in backwardConns) {
            expect(edge.isPartial, isFalse);
            expect(edge.outputMode, core.OutputMode.replace);
          }
          expect(backwardConns.map((c) => c.sourcePortId).toSet(), {
            'writer1_out_b25',
            'writer2_out_b25',
          });
        },
      );
    });
  });
}
