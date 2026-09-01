import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('ES-5 Routing Integration', () {
    late RoutingEditorCubit routingEditorCubit;

    setUp(() {
      routingEditorCubit = RoutingEditorCubit(null);
    });

    tearDown(() {
      routingEditorCubit.close();
    });

    // Helper function to create USB From Host test slot
    Slot createUsbFromHostSlot({
      required List<({int channel, int busValue})> channelConfigs,
      int algorithmIndex = 0,
    }) {
      final pages = <ParameterPage>[];
      final parameters = <ParameterInfo>[];
      final values = <ParameterValue>[];

      for (int i = 0; i < channelConfigs.length && i < 8; i++) {
        final channel = i + 1;
        final config = channelConfigs[i];
        final toParamNum = i * 2;
        final modeParamNum = i * 2 + 1;

        parameters.addAll([
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: toParamNum,
            name: 'Ch$channel to',
            min: 0,
            max: 30,
            defaultValue: 0,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: modeParamNum,
            name: 'Ch$channel mode',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 1,
            powerOfTen: 0,
          ),
        ]);

        values.addAll([
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: toParamNum,
            value: config.busValue,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: modeParamNum,
            value: 0, // Add mode
          ),
        ]);
      }

      return Slot(
        algorithm: Algorithm(
          algorithmIndex: algorithmIndex,
          guid: 'usbf',
          name: 'USB Audio (From Host)',
        ),
        routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: []),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: pages),
        parameters: parameters,
        values: values,
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    // Helper function to create ES-5 direct output algorithm slot (Clock/Euclidean)
    Slot createEs5DirectOutputSlot({
      required String guid,
      required String name,
      required int channelCount,
      required List<({int channel, int es5Expander, int es5Output, int output})>
      channelConfigs,
      int algorithmIndex = 0,
    }) {
      final pages = <ParameterPage>[];
      final parameters = <ParameterInfo>[];
      final values = <ParameterValue>[];

      int paramNum = 0;

      for (int channel = 1; channel <= channelCount; channel++) {
        final es5ExpanderParamNum = paramNum++;
        final es5OutputParamNum = paramNum++;
        final outputParamNum = paramNum++;

        parameters.addAll([
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: es5ExpanderParamNum,
            name: '$channel:ES-5 Expander',
            min: 0,
            max: 6,
            defaultValue: 0,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: es5OutputParamNum,
            name: '$channel:ES-5 Output',
            min: 1,
            max: 8,
            defaultValue: channel,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: outputParamNum,
            name: '$channel:Output',
            min: 1,
            max: 28,
            defaultValue: 13,
            unit: 1,
            powerOfTen: 0,
          ),
        ]);

        final config = channelConfigs.firstWhere(
          (c) => c.channel == channel,
          orElse: () => (
            channel: channel,
            es5Expander: 0,
            es5Output: channel,
            output: 13,
          ),
        );

        values.addAll([
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: es5ExpanderParamNum,
            value: config.es5Expander,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: es5OutputParamNum,
            value: config.es5Output,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: outputParamNum,
            value: config.output,
          ),
        ]);
      }

      return Slot(
        algorithm: Algorithm(
          algorithmIndex: algorithmIndex,
          guid: guid,
          name: name,
        ),
        routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: []),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: pages),
        parameters: parameters,
        values: values,
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    // Helper function to create Clock test slot
    Slot createClockSlot({
      required int channelCount,
      required List<({int channel, int es5Expander, int es5Output, int output})>
      channelConfigs,
      int algorithmIndex = 0,
    }) {
      return createEs5DirectOutputSlot(
        guid: 'clck',
        name: 'Clock',
        channelCount: channelCount,
        channelConfigs: channelConfigs,
        algorithmIndex: algorithmIndex,
      );
    }

    // Helper function to create Euclidean test slot
    Slot createEuclideanSlot({
      required int channelCount,
      required List<({int channel, int es5Expander, int es5Output, int output})>
      channelConfigs,
      int algorithmIndex = 0,
    }) {
      return createEs5DirectOutputSlot(
        guid: 'eucp',
        name: 'Euclidean',
        channelCount: channelCount,
        channelConfigs: channelConfigs,
        algorithmIndex: algorithmIndex,
      );
    }

    // Helper function to create ES-5 Encoder test slot
    Slot createEs5EncoderSlot({
      required List<int> enabledChannels,
      int algorithmIndex = 0,
    }) {
      final pages = <ParameterPage>[];
      final parameters = <ParameterInfo>[];
      final values = <ParameterValue>[];

      for (int channel = 1; channel <= 8; channel++) {
        final pageParams = <int>[];
        final enableParamNum = (channel - 1) * 4;
        final inputParamNum = (channel - 1) * 4 + 1;
        final expanderParamNum = (channel - 1) * 4 + 2;
        final outputParamNum = (channel - 1) * 4 + 3;

        pageParams.addAll([
          enableParamNum,
          inputParamNum,
          expanderParamNum,
          outputParamNum,
        ]);

        pages.add(
          ParameterPage(name: 'Channel $channel', parameters: pageParams),
        );

        parameters.addAll([
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: enableParamNum,
            name: 'Enable',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: inputParamNum,
            name: 'Input',
            min: 1,
            max: 28,
            defaultValue: 1,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: expanderParamNum,
            name: 'Expander',
            min: 1,
            max: 6,
            defaultValue: 1,
            unit: 1,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: algorithmIndex,
            parameterNumber: outputParamNum,
            name: 'Output',
            min: 1,
            max: 8,
            defaultValue: channel,
            unit: 1,
            powerOfTen: 0,
          ),
        ]);

        final isEnabled = enabledChannels.contains(channel);
        values.addAll([
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: enableParamNum,
            value: isEnabled ? 1 : 0,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: inputParamNum,
            value: channel,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: expanderParamNum,
            value: 1,
          ),
          ParameterValue(
            algorithmIndex: algorithmIndex,
            parameterNumber: outputParamNum,
            value: channel,
          ),
        ]);
      }

      return Slot(
        algorithm: Algorithm(
          algorithmIndex: algorithmIndex,
          guid: 'es5e',
          name: 'ES-5 Encoder',
        ),
        routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: []),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: pages),
        parameters: parameters,
        values: values,
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    group('USB From Host to ES-5 L/R', () {
      test('connects Ch1 to ES-5 L and Ch2 to ES-5 R', () {
        final slot = createUsbFromHostSlot(
          channelConfigs: [
            (channel: 1, busValue: 29), // ES-5 L
            (channel: 2, busValue: 30), // ES-5 R
            (channel: 3, busValue: 0), // None
            (channel: 4, busValue: 0), // None
            (channel: 5, busValue: 0), // None
            (channel: 6, busValue: 0), // None
            (channel: 7, busValue: 0), // None
            (channel: 8, busValue: 0), // None
          ],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'usb_test',
        );
        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);

        // Verify ES-5 L connection
        final es5LConn = connections.where(
          (c) => c.destinationPortId == 'es5_L',
        );
        expect(es5LConn.length, equals(1));
        expect(es5LConn.first.signalType, equals(SignalType.audio));

        // Verify ES-5 R connection
        final es5RConn = connections.where(
          (c) => c.destinationPortId == 'es5_R',
        );
        expect(es5RConn.length, equals(1));
        expect(es5RConn.first.signalType, equals(SignalType.audio));
      });

      test('ES-5 node appears when USB From Host is present', () {
        final slot = createUsbFromHostSlot(
          channelConfigs: [
            (channel: 1, busValue: 29),
            (channel: 2, busValue: 30),
            (channel: 3, busValue: 0),
            (channel: 4, busValue: 0),
            (channel: 5, busValue: 0),
            (channel: 6, busValue: 0),
            (channel: 7, busValue: 0),
            (channel: 8, busValue: 0),
          ],
        );

        expect(routingEditorCubit.shouldShowEs5Node([slot]), isTrue);
      });
    });

    group('Clock with ES-5 Direct Output', () {
      test('Ch1 connects to ES-5 port 3, Ch2 to bus 15', () {
        final slot = createClockSlot(
          channelCount: 2,
          channelConfigs: [
            (channel: 1, es5Expander: 1, es5Output: 3, output: 13),
            (channel: 2, es5Expander: 0, es5Output: 2, output: 15),
          ],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'clock_test',
        );
        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);

        // Ch1 should connect directly to ES-5 port 3
        final es5Conn = connections.where(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.destinationPortId == 'es5_3',
        );
        expect(es5Conn.length, equals(1));
        expect(es5Conn.first.signalType, equals(SignalType.gate));

        // Ch2 should connect to hardware output 3 (bus 15)
        final hwConn = connections.where(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.destinationPortId == 'hw_out_3',
        );
        expect(hwConn.length, equals(1));
      });

      test('ES-5 node appears when Clock with ES-5 parameters is present', () {
        final slot = createClockSlot(
          channelCount: 1,
          channelConfigs: [
            (channel: 1, es5Expander: 1, es5Output: 1, output: 13),
          ],
        );

        expect(routingEditorCubit.shouldShowEs5Node([slot]), isTrue);
      });
    });

    group('Euclidean with ES-5 Direct Output', () {
      test('routes identically to Clock', () {
        final slot = createEuclideanSlot(
          channelCount: 2,
          channelConfigs: [
            (channel: 1, es5Expander: 1, es5Output: 4, output: 13),
            (channel: 2, es5Expander: 0, es5Output: 2, output: 14),
          ],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'euclidean_test',
        );
        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);

        // Ch1 should connect to ES-5 port 4
        final es5Conn = connections.where(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.destinationPortId == 'es5_4',
        );
        expect(es5Conn.length, equals(1));

        // Ch2 should connect to hardware output
        final hwConn = connections.where(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.destinationPortId == 'hw_out_2',
        );
        expect(hwConn.length, equals(1));
      });

      test('ES-5 node appears when Euclidean is present', () {
        final slot = createEuclideanSlot(
          channelCount: 1,
          channelConfigs: [
            (channel: 1, es5Expander: 0, es5Output: 1, output: 13),
          ],
        );

        expect(routingEditorCubit.shouldShowEs5Node([slot]), isTrue);
      });
    });

    group('ES-5 Encoder Input Mirroring', () {
      test('enabled channels mirror to corresponding ES-5 ports', () {
        final slot = createEs5EncoderSlot(enabledChannels: [1, 3, 5]);

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'es5e_test',
        );
        final connections = ConnectionDiscoveryService.discoverConnections([
          routing,
        ]);

        final mirrorConnections = connections.where(
          (c) =>
              c.connectionType == ConnectionType.algorithmToAlgorithm &&
              c.description == 'ES-5 Encoder mirror connection',
        );

        expect(mirrorConnections.length, equals(3));

        // Verify connections to ES-5 ports
        expect(
          mirrorConnections.any((c) => c.destinationPortId == 'es5_1'),
          isTrue,
        );
        expect(
          mirrorConnections.any((c) => c.destinationPortId == 'es5_3'),
          isTrue,
        );
        expect(
          mirrorConnections.any((c) => c.destinationPortId == 'es5_5'),
          isTrue,
        );

        // Verify disabled channels have no mirror connections
        expect(
          mirrorConnections.any((c) => c.destinationPortId == 'es5_2'),
          isFalse,
        );
        expect(
          mirrorConnections.any((c) => c.destinationPortId == 'es5_4'),
          isFalse,
        );
      });

      test('ES-5 node appears when ES-5 Encoder is present', () {
        final slot = createEs5EncoderSlot(enabledChannels: [1]);

        expect(routingEditorCubit.shouldShowEs5Node([slot]), isTrue);
      });
    });

    group('ES-5 Node Conditional Display', () {
      test('ES-5 node does not appear when no ES-5 algorithms present', () {
        final slot = Slot(
          algorithm: Algorithm(algorithmIndex: 0, guid: 'poly', name: 'Poly'),
          routing: RoutingInfo(algorithmIndex: 0, routingInfo: []),
          pages: ParameterPages(algorithmIndex: 0, pages: []),
          parameters: const [],
          values: const [],
          enums: const [],
          mappings: const [],
          valueStrings: const [],
        );

        expect(routingEditorCubit.shouldShowEs5Node([slot]), isFalse);
      });

      test('ES-5 node appears when USB From Host is added', () {
        final usbSlot = createUsbFromHostSlot(
          channelConfigs: [
            (channel: 1, busValue: 29),
            (channel: 2, busValue: 30),
            (channel: 3, busValue: 0),
            (channel: 4, busValue: 0),
            (channel: 5, busValue: 0),
            (channel: 6, busValue: 0),
            (channel: 7, busValue: 0),
            (channel: 8, busValue: 0),
          ],
        );

        expect(routingEditorCubit.shouldShowEs5Node([usbSlot]), isTrue);
      });

      test('ES-5 node disappears when all ES-5 algorithms removed', () {
        final polySlot = Slot(
          algorithm: Algorithm(algorithmIndex: 0, guid: 'poly', name: 'Poly'),
          routing: RoutingInfo(algorithmIndex: 0, routingInfo: []),
          pages: ParameterPages(algorithmIndex: 0, pages: []),
          parameters: const [],
          values: const [],
          enums: const [],
          mappings: const [],
          valueStrings: const [],
        );

        expect(routingEditorCubit.shouldShowEs5Node([polySlot]), isFalse);
      });
    });

    group('Mixed ES-5 Algorithms', () {
      test('multiple ES-5 algorithms coexist without conflicts', () {
        final usbSlot = createUsbFromHostSlot(
          algorithmIndex: 0,
          channelConfigs: [
            (channel: 1, busValue: 29),
            (channel: 2, busValue: 30),
            (channel: 3, busValue: 0),
            (channel: 4, busValue: 0),
            (channel: 5, busValue: 0),
            (channel: 6, busValue: 0),
            (channel: 7, busValue: 0),
            (channel: 8, busValue: 0),
          ],
        );

        final clockSlot = createClockSlot(
          algorithmIndex: 1,
          channelCount: 2,
          channelConfigs: [
            (channel: 1, es5Expander: 1, es5Output: 1, output: 13),
            (channel: 2, es5Expander: 1, es5Output: 2, output: 14),
          ],
        );

        final euclideanSlot = createEuclideanSlot(
          algorithmIndex: 2,
          channelCount: 2,
          channelConfigs: [
            (channel: 1, es5Expander: 1, es5Output: 3, output: 13),
            (channel: 2, es5Expander: 0, es5Output: 2, output: 15),
          ],
        );

        final es5EncoderSlot = createEs5EncoderSlot(
          algorithmIndex: 3,
          enabledChannels: [4, 5],
        );

        final slots = [usbSlot, clockSlot, euclideanSlot, es5EncoderSlot];
        final routings = [
          AlgorithmRouting.fromSlot(
            usbSlot,
            deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
            algorithmUuid: 'usb_test',
          ),
          AlgorithmRouting.fromSlot(
            clockSlot,
            deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
            algorithmUuid: 'clock_test',
          ),
          AlgorithmRouting.fromSlot(
            euclideanSlot,
            deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
            algorithmUuid: 'euclidean_test',
          ),
          AlgorithmRouting.fromSlot(
            es5EncoderSlot,
            deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
            algorithmUuid: 'es5e_test',
          ),
        ];
        final connections = ConnectionDiscoveryService.discoverConnections(
          routings,
        );

        // Verify USB connections (L/R)
        expect(connections.any((c) => c.destinationPortId == 'es5_L'), isTrue);
        expect(connections.any((c) => c.destinationPortId == 'es5_R'), isTrue);

        // Verify Clock connections (ports 1, 2)
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.algorithmToAlgorithm &&
                c.destinationPortId == 'es5_1' &&
                c.description == 'ES-5 direct connection',
          ),
          isTrue,
        );
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.algorithmToAlgorithm &&
                c.destinationPortId == 'es5_2' &&
                c.description == 'ES-5 direct connection',
          ),
          isTrue,
        );

        // Verify Euclidean connections (port 3, and hw output)
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.algorithmToAlgorithm &&
                c.destinationPortId == 'es5_3' &&
                c.description == 'ES-5 direct connection',
          ),
          isTrue,
        );
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.hardwareOutput &&
                c.destinationPortId == 'hw_out_3',
          ),
          isTrue,
        );

        // Verify ES-5 Encoder mirror connections (ports 4, 5)
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.algorithmToAlgorithm &&
                c.destinationPortId == 'es5_4' &&
                c.description == 'ES-5 Encoder mirror connection',
          ),
          isTrue,
        );
        expect(
          connections.any(
            (c) =>
                c.connectionType == ConnectionType.algorithmToAlgorithm &&
                c.destinationPortId == 'es5_5' &&
                c.description == 'ES-5 Encoder mirror connection',
          ),
          isTrue,
        );

        // Verify ES-5 node should be displayed
        expect(routingEditorCubit.shouldShowEs5Node(slots), isTrue);
      });
    });
  });
}
