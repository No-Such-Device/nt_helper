import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Mixer Send Routing Tests', () {
    // Helper to create a mixer slot with sends
    Slot createMixerSlotWithSends({
      bool hasSends = true,
      int send1Width = 0, // 0 = Mono, 1 = Stereo
      int send2Width = 1, // 0 = Mono, 1 = Stereo
    }) {
      final algorithm = Algorithm(
        algorithmIndex: 0,
        guid: 'mix2',
        name: '8 Mixer/Stereo',
      );

      final routing = RoutingInfo(
        algorithmIndex: 0,
        routingInfo: List.filled(6, 0),
      );

      // Create parameter pages including Send pages
      final pages = ParameterPages(
        algorithmIndex: 0,
        pages: hasSends
            ? [
                ParameterPage(name: 'Common', parameters: [0, 1, 2]),
                ParameterPage(name: 'Per-channel', parameters: [3, 4, 5]),
                ParameterPage(
                  name: 'Send 1',
                  parameters: [10, 11, 12, 13],
                ), // destination, pre/post, width, output mode
                ParameterPage(
                  name: 'Send 2',
                  parameters: [14, 15, 16, 17],
                ), // destination, pre/post, width, output mode
              ]
            : [
                ParameterPage(name: 'Common', parameters: [0, 1, 2]),
                ParameterPage(name: 'Per-channel', parameters: [3, 4, 5]),
              ],
      );

      // Create parameters
      final parameters = <ParameterInfo>[
        // Common audio I/O parameters
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          name: 'Audio input',
          min: 0,
          max: 28,
          defaultValue: 1,
          unit: 1, // bus
          powerOfTen: 0,
          ioFlags: 5, // isInput | isAudio
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 1,
          name: 'Left output',
          min: 0,
          max: 28,
          defaultValue: 13,
          unit: 1, // bus
          powerOfTen: 0,
          ioFlags: 6, // isOutput | isAudio
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 2,
          name: 'Right output',
          min: 0,
          max: 28,
          defaultValue: 14,
          unit: 1, // bus
          powerOfTen: 0,
          ioFlags: 6, // isOutput | isAudio
        ),
        // Per-channel parameters
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 3,
          name: 'Channel 1 gain',
          min: -36,
          max: 12,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 4,
          name: 'Channel 2 gain',
          min: -36,
          max: 12,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 5,
          name: 'Channel 3 gain',
          min: -36,
          max: 12,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
      ];

      // Add send parameters if mixer has sends
      if (hasSends) {
        parameters.addAll([
          // Send 1 parameters
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 10,
            name: 'Send 1 destination',
            min: 0,
            max: 28,
            defaultValue: 15,
            unit: 1, // bus
            powerOfTen: 0,
            ioFlags: 6, // isOutput | isAudio
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 11,
            name: 'Send 1 Pre/post',
            min: 0,
            max: 1,
            defaultValue: 1,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 12,
            name: 'Send 1 width',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 13,
            name: 'Send 1 Output mode',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
            ioFlags: 8, // isOutputMode
          ),
          // Send 2 parameters
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 14,
            name: 'Send 2 destination',
            min: 0,
            max: 28,
            defaultValue: 17,
            unit: 1, // bus
            powerOfTen: 0,
            ioFlags: 6, // isOutput | isAudio
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 15,
            name: 'Send 2 Pre/post',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 16,
            name: 'Send 2 width',
            min: 0,
            max: 1,
            defaultValue: 1,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 17,
            name: 'Send 2 Output mode',
            min: 0,
            max: 1,
            defaultValue: 1,
            unit: 0,
            powerOfTen: 0,
            ioFlags: 8, // isOutputMode
          ),
        ]);
      }

      // Create parameter values
      final values = <ParameterValue>[
        // I/O bus assignments
        ParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 1,
        ), // Audio input on bus 1
        ParameterValue(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: 13,
        ), // Left output on bus 13
        ParameterValue(
          algorithmIndex: 0,
          parameterNumber: 2,
          value: 14,
        ), // Right output on bus 14
      ];

      if (hasSends) {
        values.addAll([
          // Send 1 values
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 10,
            value: 15,
          ), // Send 1 destination = bus 15
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 11,
            value: 1,
          ), // Send 1 Pre/post = Post
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 12,
            value: send1Width,
          ), // Send 1 width
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 13,
            value: 0,
          ), // Send 1 Output mode = Add
          // Send 2 values
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 14,
            value: 17,
          ), // Send 2 destination = bus 17
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 15,
            value: 0,
          ), // Send 2 Pre/post = Pre
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 16,
            value: send2Width,
          ), // Send 2 width
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 17,
            value: 1,
          ), // Send 2 Output mode = Replace
        ]);
      }

      return Slot(
        algorithm: algorithm,
        routing: routing,
        pages: pages,
        parameters: parameters,
        values: values,
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    test('should treat Send destinations as outputs, not inputs', () {
      // Create a mixer with 2 sends
      final slot = createMixerSlotWithSends(
        hasSends: true,
        send1Width: 0, // Mono
        send2Width: 1, // Stereo
      );

      // Create routing from slot
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'mixer_test_1',
      );

      // Get input and output ports
      final inputPorts = routing.inputPorts;
      final outputPorts = routing.outputPorts;

      // CRITICAL ASSERTIONS:
      // Send destinations should NOT appear in inputs
      final sendInputs = inputPorts
          .where(
            (p) =>
                p.name.toLowerCase().contains('send') &&
                p.name.toLowerCase().contains('destination'),
          )
          .toList();
      expect(
        sendInputs,
        isEmpty,
        reason:
            'Send destinations should not appear as inputs, but found: ${sendInputs.map((p) => p.name).join(", ")}',
      );

      // Send outputs SHOULD appear in outputs
      final sendOutputs = outputPorts
          .where((p) => p.name.toLowerCase().contains('send'))
          .toList();
      expect(
        sendOutputs,
        isNotEmpty,
        reason: 'Send outputs should appear in output ports',
      );

      // Verify correct number of send outputs
      // Send 1 is mono (1 port), Send 2 is stereo (2 ports) = 3 total
      expect(
        sendOutputs.length,
        equals(3),
        reason:
            'Should have 3 send outputs: Send 1 (mono) + Send 2 L/R (stereo)',
      );

      // Verify Send 1 (mono) output
      final send1Output = sendOutputs
          .where((p) => p.name.contains('Send 1'))
          .toList();
      expect(
        send1Output,
        hasLength(1),
        reason: 'Send 1 should have 1 mono output',
      );
      expect(
        send1Output.first.busValue,
        equals(15),
        reason: 'Send 1 should use bus 15',
      );
      expect(send1Output.first.direction, equals(PortDirection.output));
      expect(
        send1Output.first.outputMode,
        equals(OutputMode.add),
        reason: 'Send 1 should use Add mode',
      );

      // Verify Send 2 (stereo) outputs
      final send2Outputs = sendOutputs
          .where((p) => p.name.contains('Send 2'))
          .toList();
      expect(
        send2Outputs,
        hasLength(2),
        reason: 'Send 2 should have 2 stereo outputs (L/R)',
      );

      final send2L = send2Outputs.firstWhere(
        (p) => p.name.contains('L'),
        orElse: () => send2Outputs.first,
      );
      final send2R = send2Outputs.firstWhere(
        (p) => p.name.contains('R'),
        orElse: () => send2Outputs.last,
      );

      expect(send2L.busValue, equals(17), reason: 'Send 2 L should use bus 17');
      expect(
        send2R.busValue,
        equals(18),
        reason: 'Send 2 R should use bus 17+1',
      );
      expect(
        send2L.outputMode,
        equals(OutputMode.replace),
        reason: 'Send 2 should use Replace mode',
      );
      expect(
        send2R.outputMode,
        equals(OutputMode.replace),
        reason: 'Send 2 should use Replace mode',
      );

      // Verify normal I/O still works
      expect(inputPorts.any((p) => p.name == 'Audio input'), isTrue);
      expect(outputPorts.any((p) => p.name == 'Left output'), isTrue);
      expect(outputPorts.any((p) => p.name == 'Right output'), isTrue);
    });

    test('should handle mixer with no sends correctly', () {
      // Create a mixer without sends
      final slot = createMixerSlotWithSends(hasSends: false);

      // Create routing from slot
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'mixer_test_2',
      );

      // Get input and output ports
      final inputPorts = routing.inputPorts;
      final outputPorts = routing.outputPorts;

      // Should have no send-related ports
      final sendPorts = [
        ...inputPorts,
        ...outputPorts,
      ].where((p) => p.name.toLowerCase().contains('send')).toList();
      expect(
        sendPorts,
        isEmpty,
        reason: 'Mixer without sends should have no send ports',
      );

      // Should still have normal I/O
      expect(inputPorts.any((p) => p.name == 'Audio input'), isTrue);
      expect(outputPorts.any((p) => p.name == 'Left output'), isTrue);
      expect(outputPorts.any((p) => p.name == 'Right output'), isTrue);
    });

    test('should handle different send width configurations', () {
      // Test all mono sends
      final monoSlot = createMixerSlotWithSends(
        hasSends: true,
        send1Width: 0,
        send2Width: 0,
      );
      final monoRouting = AlgorithmRouting.fromSlot(
        monoSlot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'mixer_test_3',
      );
      final monoSendOutputs = monoRouting.outputPorts
          .where((p) => p.name.toLowerCase().contains('send'))
          .toList();
      expect(
        monoSendOutputs,
        hasLength(2),
        reason: 'Two mono sends = 2 outputs',
      );

      // Test all stereo sends
      final stereoSlot = createMixerSlotWithSends(
        hasSends: true,
        send1Width: 1,
        send2Width: 1,
      );
      final stereoRouting = AlgorithmRouting.fromSlot(
        stereoSlot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'mixer_test_4',
      );
      final stereoSendOutputs = stereoRouting.outputPorts
          .where((p) => p.name.toLowerCase().contains('send'))
          .toList();
      expect(
        stereoSendOutputs,
        hasLength(4),
        reason: 'Two stereo sends = 4 outputs (2 L/R pairs)',
      );
    });

    test('should preserve send metadata correctly', () {
      final slot = createMixerSlotWithSends(
        hasSends: true,
        send1Width: 0,
        send2Width: 1,
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'mixer_test_5',
      );
      final sendOutputs = routing.outputPorts
          .where((p) => p.name.toLowerCase().contains('send'))
          .toList();

      // All send outputs should be audio type
      for (final port in sendOutputs) {
        expect(
          port.type,
          equals(PortType.audio),
          reason: 'Send outputs should be audio type',
        );
        expect(
          port.direction,
          equals(PortDirection.output),
          reason: 'Sends should be outputs',
        );
        expect(
          port.busValue,
          isNotNull,
          reason: 'Send outputs should have bus assignments',
        );
        expect(
          port.outputMode,
          isNotNull,
          reason: 'Send outputs should have output mode',
        );
      }
    });
  });
}
