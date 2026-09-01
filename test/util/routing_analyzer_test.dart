import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/routing_information.dart';
import 'package:nt_helper/util/routing_analyzer.dart';

void main() {
  test('reports an explicit bus 64 mapping without a packed mask', () {
    final routing = RoutingInformation(
      algorithmIndex: 0,
      routingInfo: const [0, 0, 0, 0, 0, 0],
      algorithmName: 'Mapped algorithm',
      mappingBuses: const {64},
    );

    final json = RoutingAnalyzer(
      routing: [routing],
      showSignals: false,
      showMappings: true,
      deviceIoProfile: DeviceIoProfile.distingExtended,
    ).generateSlotBusUsageJson();
    final slots = jsonDecode(json) as List<dynamic>;

    expect(slots.single['inputBuses'], [64]);
  });
}
