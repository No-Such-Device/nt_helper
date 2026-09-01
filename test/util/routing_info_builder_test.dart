import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/util/routing_analyzer.dart';
import 'package:nt_helper/util/routing_info_builder.dart';

RoutingAlgorithm _algo({
  required String id,
  required int index,
  required String name,
  List<int?> inputBuses = const [],
  List<({int? bus, OutputMode mode})> outputs = const [],
}) {
  return RoutingAlgorithm(
    id: id,
    index: index,
    algorithm: Algorithm(algorithmIndex: index, guid: id, name: name),
    inputPorts: [
      for (var i = 0; i < inputBuses.length; i++)
        Port(
          id: '${id}_in_$i',
          name: 'In$i',
          type: PortType.audio,
          direction: PortDirection.input,
          busValue: inputBuses[i],
        ),
    ],
    outputPorts: [
      for (var i = 0; i < outputs.length; i++)
        Port(
          id: '${id}_out_$i',
          name: 'Out$i',
          type: PortType.audio,
          direction: PortDirection.output,
          busValue: outputs[i].bus,
          outputMode: outputs[i].mode,
        ),
    ],
  );
}

void main() {
  group('buildRoutingInfoFromEditor', () {
    test('returns empty for no algorithms', () {
      expect(buildRoutingInfoFromEditor([], {}), isEmpty);
    });

    test('packs input/output/replace masks by bus number', () {
      final info = buildRoutingInfoFromEditor([
        _algo(
          id: 'a',
          index: 0,
          name: 'A',
          inputBuses: [3],
          outputs: [(bus: 13, mode: OutputMode.add)],
        ),
      ], {});

      expect(info, hasLength(1));
      expect(info[0].routingInfo[0], 1 << 3, reason: 'input mask');
      expect(info[0].routingInfo[1], 1 << 13, reason: 'output mask');
      expect(info[0].routingInfo[2], 0, reason: 'replace mask (add mode)');
      expect(info[0].algorithmName, 'A');
      expect(info[0].algorithmIndex, 0);
    });

    test('marks replace mode in the replace mask', () {
      final info = buildRoutingInfoFromEditor([
        _algo(
          id: 'a',
          index: 0,
          name: 'A',
          outputs: [(bus: 21, mode: OutputMode.replace)],
        ),
      ], {});

      expect(info[0].routingInfo[1], 1 << 21);
      expect(info[0].routingInfo[2], 1 << 21);
    });

    test('portOutputModes overrides the port outputMode', () {
      final info = buildRoutingInfoFromEditor(
        [
          _algo(
            id: 'a',
            index: 0,
            name: 'A',
            outputs: [(bus: 21, mode: OutputMode.add)],
          ),
        ],
        {'a_out_0': OutputMode.replace},
      );

      expect(info[0].routingInfo[2], 1 << 21, reason: 'override -> replace');
    });

    test('ignores bus 0 and null bus assignments', () {
      final info = buildRoutingInfoFromEditor([
        _algo(
          id: 'a',
          index: 0,
          name: 'A',
          inputBuses: [0, null],
          outputs: [(bus: 0, mode: OutputMode.add)],
        ),
      ], {});

      expect(info[0].routingInfo[0], 0);
      expect(info[0].routingInfo[1], 0);
    });

    test('sorts algorithms by slot index', () {
      final info = buildRoutingInfoFromEditor([
        _algo(id: 'b', index: 2, name: 'B'),
        _algo(id: 'a', index: 0, name: 'A'),
        _algo(id: 'c', index: 1, name: 'C'),
      ], {});

      expect(info.map((e) => e.algorithmName).toList(), ['A', 'C', 'B']);
    });

    test('preserves bus 64 for routing analysis', () {
      final info = buildRoutingInfoFromEditor(
        [
          _algo(
            id: 'a',
            index: 0,
            name: 'A',
            outputs: [(bus: 64, mode: OutputMode.add)],
          ),
        ],
        {},
        deviceIoProfile: DeviceIoProfile.distingExtended,
      );

      final usage = RoutingAnalyzer(
        routing: info,
        deviceIoProfile: DeviceIoProfile.distingExtended,
      ).generateSlotBusUsageJson();

      expect(usage, contains('"outputBuses":[64]'));
    });

    test('preserves contextual USB From Host buses for routing analysis', () {
      final info = buildRoutingInfoFromEditor(
        [
          _algo(
            id: 'usbf',
            index: 0,
            name: 'USB From Host',
            outputs: [(bus: 65, mode: OutputMode.add)],
          ),
        ],
        {},
        deviceIoProfile: DeviceIoProfile.distingExtended,
      );

      final usage = RoutingAnalyzer(
        routing: info,
        deviceIoProfile: DeviceIoProfile.distingExtended,
      ).generateSlotBusUsageJson();

      expect(usage, contains('"outputBuses":[65]'));
    });
  });
}
