import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/usb_from_algorithm_routing.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/ui/widgets/routing/bus_label_formatter.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('ES-5 Bus Values Tests', () {
    // Helper function to create test slots
    Slot createSlot({
      required Algorithm algorithm,
      required List<ParameterInfo> parameters,
      List<ParameterValue> values = const [],
      List<ParameterEnumStrings> enums = const [],
      int algorithmIndex = 0,
    }) {
      return Slot(
        algorithm: algorithm,
        routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: []),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: []),
        parameters: parameters,
        values: values,
        enums: enums,
        mappings: const [],
        valueStrings: const [],
      );
    }

    group('ConnectionDiscoveryService', () {
      test('should handle ES-5 L bus value (29)', () {
        // Create USB Audio algorithm outputting to ES-5 L
        final usbSlot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'usbf',
            name: 'USB Audio (From Host)',
          ),
          parameters: [
            for (int i = 1; i <= 8; i++)
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: i - 1,
                name: 'Ch$i to',
                min: 0,
                max: 30,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
                ioFlags: 2, // isOutput
              ),
            for (int i = 1; i <= 8; i++)
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: i + 7,
                name: 'Ch$i mode',
                min: 0,
                max: 1,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
                ioFlags: 8, // isOutputMode
              ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: 29,
            ), // Ch1 to ES-5 L
          ],
        );

        final ioParameters = UsbFromAlgorithmRouting.extractIOParameters(
          usbSlot,
        );
        final usbRouting = UsbFromAlgorithmRouting.createFromSlot(
          usbSlot,
          ioParameters: ioParameters,
          algorithmUuid: 'usb_1',
        );

        // Discover connections
        final connections = ConnectionDiscoveryService.discoverConnections([
          usbRouting,
        ]);

        // Should create a hardware output connection for ES-5 L
        expect(connections, isNotEmpty);

        final es5Connection = connections.first;
        expect(
          es5Connection.connectionType,
          equals(ConnectionType.hardwareOutput),
        );
        expect(es5Connection.busNumber, equals(29));
      });

      test('should handle ES-5 R bus value (30)', () {
        // Create USB Audio algorithm outputting to ES-5 R
        final usbSlot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'usbf',
            name: 'USB Audio (From Host)',
          ),
          parameters: [
            for (int i = 1; i <= 8; i++)
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: i - 1,
                name: 'Ch$i to',
                min: 0,
                max: 30,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
                ioFlags: 2, // isOutput
              ),
            for (int i = 1; i <= 8; i++)
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: i + 7,
                name: 'Ch$i mode',
                min: 0,
                max: 1,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
                ioFlags: 8, // isOutputMode
              ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 1,
              value: 30,
            ), // Ch2 to ES-5 R
          ],
        );

        final ioParameters = UsbFromAlgorithmRouting.extractIOParameters(
          usbSlot,
        );
        final usbRouting = UsbFromAlgorithmRouting.createFromSlot(
          usbSlot,
          ioParameters: ioParameters,
          algorithmUuid: 'usb_2',
        );

        // Discover connections
        final connections = ConnectionDiscoveryService.discoverConnections([
          usbRouting,
        ]);

        // Should create a hardware output connection for ES-5 R
        expect(connections, isNotEmpty);

        final es5Connection = connections.first;
        expect(
          es5Connection.connectionType,
          equals(ConnectionType.hardwareOutput),
        );
        expect(es5Connection.busNumber, equals(30));
      });

      test('should not expose ES-5 as a general algorithm bus', () {
        // Create an algorithm outputting to ES-5 L
        final outputSlot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'test_out',
            name: 'Test Output',
          ),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              name: 'Audio output',
              min: 0,
              max: 30,
              defaultValue: 29,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 6, // isOutput | isAudio
            ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: 29,
            ), // ES-5 L
          ],
        );

        // Create an algorithm inputting from ES-5 L
        final inputSlot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 1,
            guid: 'test_in',
            name: 'Test Input',
          ),
          parameters: [
            ParameterInfo(
              algorithmIndex: 1,
              parameterNumber: 0,
              name: 'Audio input',
              min: 0,
              max: 30,
              defaultValue: 29,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 5, // isInput | isAudio
            ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 1,
              parameterNumber: 0,
              value: 29,
            ), // ES-5 L
          ],
        );

        final outputRouting = MultiChannelAlgorithmRouting.createFromSlot(
          outputSlot,
          ioParameters: {'Audio output': 29},
          algorithmUuid: 'out_1',
        );

        final inputRouting = MultiChannelAlgorithmRouting.createFromSlot(
          inputSlot,
          ioParameters: {'Audio input': 29},
          algorithmUuid: 'in_1',
        );

        // Discover connections
        final connections = ConnectionDiscoveryService.discoverConnections([
          outputRouting,
          inputRouting,
        ]);

        // ES-5 choices belong only to USB From Host. Other algorithms cannot
        // use the values as a private algorithm-to-algorithm bus.
        final algoConnections = connections
            .where(
              (c) => c.connectionType == ConnectionType.algorithmToAlgorithm,
            )
            .toList();

        expect(algoConnections, isEmpty);
      });
    });

    group('BusLabelFormatter', () {
      test('should format ES-5 L correctly', () {
        // Note: This test assumes BusLabelFormatter is updated to handle buses 29-30
        // The actual implementation might need updating
        expect(BusLabelFormatter.formatBusValue(29), equals('ES-5 L'));
      });

      test('should format ES-5 R correctly', () {
        expect(BusLabelFormatter.formatBusValue(30), equals('ES-5 R'));
      });
    });
  });
}
