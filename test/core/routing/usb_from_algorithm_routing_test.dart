import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/usb_from_algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('UsbFromAlgorithmRouting', () {
    Slot createTestSlot() {
      return Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'usbf',
          name: 'USB Audio (From Host)',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: []),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
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
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 13),
          ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 14),
          ParameterValue(algorithmIndex: 0, parameterNumber: 8, value: 1),
        ],
        enums: [
          for (int i = 0; i < 8; i++)
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: i,
              values: ['None', 'Input 1', 'Output 1'],
            ),
          for (int i = 8; i < 16; i++)
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: i,
              values: ['Add', 'Replace'],
            ),
        ],
        mappings: const [],
        valueStrings: const [],
      );
    }

    test('extracts correct number of io and mode parameters', () {
      final slot = createTestSlot();
      final ioParams = AlgorithmRouting.extractIOParameters(slot);
      final modeParams = AlgorithmRouting.extractModeParametersWithNumbers(
        slot,
      );

      expect(ioParams.length, 8);
      expect(modeParams.length, 8);
    });

    test('should be created by factory and have correct ports', () {
      final slot = createTestSlot();
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
      );

      expect(routing, isA<UsbFromAlgorithmRouting>());
      expect(routing.inputPorts, isEmpty);
      expect(routing.outputPorts, hasLength(8));

      final port1 = routing.outputPorts[0];
      expect(port1.name, equals('USB Channel 1'));
      expect(port1.busValue, equals(13));
      expect(port1.outputMode, equals(OutputMode.replace));

      final port2 = routing.outputPorts[1];
      expect(port2.name, equals('USB Channel 2'));
      expect(port2.busValue, equals(14));
      expect(port2.outputMode, equals(OutputMode.add));
    });

    test('handles spaced channel param names and different max values', () {
      // Variant where parameter names are 'Ch 1 to' and 'Ch 1 mode', and max is 31
      final slot = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'usbf',
          name: 'USB Audio (From Host)',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: []),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
        parameters: [
          for (int i = 1; i <= 8; i++)
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: i - 1,
              name: 'Ch $i to',
              min: 0,
              max: 31,
              defaultValue: 0,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 2, // isOutput
            ),
          for (int i = 1; i <= 8; i++)
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: i + 7,
              name: 'Ch $i mode',
              min: 0,
              max: 1,
              defaultValue: 0,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 8, // isOutputMode
            ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 13),
          ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 14),
          ParameterValue(algorithmIndex: 0, parameterNumber: 8, value: 1),
        ],
        enums: [
          for (int i = 0; i < 8; i++)
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: i,
              values: ['None', 'Input 1', 'Output 1'],
            ),
          for (int i = 8; i < 16; i++)
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: i,
              values: ['Add', 'Replace'],
            ),
        ],
        mappings: const [],
        valueStrings: const [],
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
      );

      expect(routing, isA<UsbFromAlgorithmRouting>());
      expect(routing.inputPorts, isEmpty);
      expect(routing.outputPorts, hasLength(8));

      final port1 = routing.outputPorts[0];
      expect(port1.name, equals('USB Channel 1'));
      expect(port1.busValue, equals(13));
      expect(port1.outputMode, equals(OutputMode.replace));
    });
  });
}
