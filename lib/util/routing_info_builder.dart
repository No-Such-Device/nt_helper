import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/routing_information.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Builds [RoutingInformation] entries (one per algorithm, sorted by slot
/// index) from routing-editor algorithm/port data.
///
/// `routingInfo` packs bit masks where bit N corresponds to bus N:
/// [0] input buses read, [1] output buses written, [2] output buses written
/// in Replace mode, [3..5] reserved (0). This mirrors the packing the OG
/// signal-flow table and [RoutingAnalyzer] consume.
///
/// Bus identity is encoded as `1 << busNumber`.
List<RoutingInformation> buildRoutingInfoFromEditor(
  List<RoutingAlgorithm> algorithms,
  Map<String, OutputMode> portOutputModes, {
  DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
}) {
  final sorted = List<RoutingAlgorithm>.from(algorithms)
    ..sort((a, b) => a.index.compareTo(b.index));

  return sorted.map((algo) {
    int inputMask = 0;
    int outputMask = 0;
    int replaceMask = 0;
    final inputBuses = <int>{};
    final outputBuses = <int>{};
    final replaceBuses = <int>{};

    for (final port in algo.inputPorts) {
      final bus = port.busValue;
      if (bus != null && deviceIoProfile.contains(bus)) {
        inputBuses.add(bus);
        if (bus < 64) inputMask |= (1 << bus);
      }
    }

    for (final port in algo.outputPorts) {
      final bus = port.busValue;
      final isContextualEs5 =
          algo.algorithm.guid == 'usbf' &&
          deviceIoProfile.contextualEs5Buses.contains(bus);
      if (bus != null && (deviceIoProfile.contains(bus) || isContextualEs5)) {
        outputBuses.add(bus);
        if (bus < 64) outputMask |= (1 << bus);
        final mode = portOutputModes[port.id] ?? port.outputMode;
        if (mode == OutputMode.replace) {
          replaceBuses.add(bus);
          if (bus < 64) replaceMask |= (1 << bus);
        }
      }
    }

    return RoutingInformation(
      algorithmIndex: algo.index,
      routingInfo: [inputMask, outputMask, replaceMask, 0, 0, 0],
      algorithmName: algo.algorithm.name,
      inputBuses: inputBuses,
      outputBuses: outputBuses,
      replaceBuses: replaceBuses,
      mappingBuses: const {},
    );
  }).toList();
}
