import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Algorithms with No Ports Tests', () {
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

    group('AlgorithmRouting', () {
      test('should detect bus parameters with firmware 1.15 max == 64', () {
        // Firmware 1.15 reports max == 64 for bus assignment parameters
        final slot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'vcam',
            name: 'VCA Mono',
          ),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              name: 'Audio input',
              min: 1,
              max: 64,
              defaultValue: 1,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 5, // isInput | isAudio
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 1,
              name: 'Audio output',
              min: 0,
              max: 64,
              defaultValue: 0,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 6, // isOutput | isAudio
            ),
          ],
          values: [
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
            ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 13),
          ],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );

        expect(routing.inputPorts, isNotEmpty);
        expect(routing.outputPorts, isNotEmpty);
      });

      test('should detect bus parameters with old firmware max == 28', () {
        final slot = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'vcam',
            name: 'VCA Mono',
          ),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              name: 'Audio input',
              min: 1,
              max: 28,
              defaultValue: 1,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 5, // isInput | isAudio
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 1,
              name: 'Audio output',
              min: 0,
              max: 28,
              defaultValue: 0,
              unit: 1,
              powerOfTen: 0,
              ioFlags: 6, // isOutput | isAudio
            ),
          ],
          values: [
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
            ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 13),
          ],
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );

        expect(routing.inputPorts, isNotEmpty);
        expect(routing.outputPorts, isNotEmpty);
      });

      test('should allow algorithms with no ports to return empty lists', () {
        // Create a slot with no routing parameters (like the 'note' algorithm)
        final slot = createSlot(
          algorithm: Algorithm(algorithmIndex: 0, guid: 'note', name: 'Note'),
          parameters: [
            // Only non-routing parameters (not enum types with bus values)
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              name: 'Note text',
              min: 0,
              max: 255,
              defaultValue: 0,
              unit: 0, // Not an enum (unit != 1)
              powerOfTen: 0,
            ),
          ],
        );

        // Create routing from slot
        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );

        // Verify no ports are generated (no fallback ports)
        expect(routing.inputPorts, isEmpty);
        expect(routing.outputPorts, isEmpty);
      });

      test(
        'should not generate fallback ports when IO parameters are empty',
        () {
          // Create a slot with parameters but none are routing parameters
          final slot = createSlot(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test_no_io',
              name: 'Test No IO',
            ),
            parameters: [
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: 0,
                name: 'Level',
                min: 0,
                max: 100,
                defaultValue: 50,
                unit: 0, // Not an enum
                powerOfTen: 0,
              ),
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: 1,
                name: 'Rate',
                min: 1,
                max: 1000,
                defaultValue: 100,
                unit: 2, // Hz unit, not an enum
                powerOfTen: 0,
              ),
            ],
          );

          // Create routing from slot
          final routing = AlgorithmRouting.fromSlot(
            slot,
            deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          );

          // Verify no fallback ports are generated
          expect(routing.inputPorts, isEmpty);
          expect(routing.outputPorts, isEmpty);
        },
      );
    });

    group('MultiChannelAlgorithmRouting', () {
      test(
        'should return empty port lists when no routing parameters exist',
        () {
          final config = MultiChannelAlgorithmConfig(
            channelCount: 1,
            algorithmProperties: {
              'algorithmGuid': 'note',
              'algorithmName': 'Note',
              'inputs': [], // Empty inputs
              'outputs': [], // Empty outputs
            },
          );

          final routing = MultiChannelAlgorithmRouting(config: config);

          // Verify no ports are generated
          expect(routing.inputPorts, isEmpty);
          expect(routing.outputPorts, isEmpty);
        },
      );

      test(
        'should not generate default Main 1 ports when inputs/outputs are empty',
        () {
          // Create slot with no routing parameters
          final slot = createSlot(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test_empty',
              name: 'Test Empty',
            ),
            parameters: [],
          );

          // Extract IO parameters (should be empty)
          final ioParameters = AlgorithmRouting.extractIOParameters(slot);
          expect(ioParameters, isEmpty);

          // Create routing from slot
          final routing = MultiChannelAlgorithmRouting.createFromSlot(
            slot,
            ioParameters: ioParameters,
          );

          // Verify no fallback ports are generated
          expect(routing.inputPorts, isEmpty);
          expect(routing.outputPorts, isEmpty);
        },
      );
    });

    group('RoutingEditorCubit Filtering', () {
      test('should filter out algorithms with no ports from visualization', () {
        // Create slots
        final slotWithPorts = createSlot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'algo1',
            name: 'Algorithm 1',
          ),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              name: 'Audio input',
              min: 0,
              max: 28,
              defaultValue: 0,
              unit: 1, // Enum type (routing parameter)
              powerOfTen: 0,
              ioFlags: 5, // isInput | isAudio
            ),
          ],
        );

        final slotWithoutPorts = createSlot(
          algorithm: Algorithm(algorithmIndex: 0, guid: 'note', name: 'Note'),
          parameters: [],
        );

        // Test that algorithms with ports are included
        final routingWithPorts = AlgorithmRouting.fromSlot(
          slotWithPorts,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );
        final hasPorts =
            routingWithPorts.inputPorts.isNotEmpty ||
            routingWithPorts.outputPorts.isNotEmpty;
        expect(hasPorts, isTrue);

        // Test that algorithms without ports are excluded
        final routingWithoutPorts = AlgorithmRouting.fromSlot(
          slotWithoutPorts,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        );
        final hasNoPorts =
            routingWithoutPorts.inputPorts.isEmpty &&
            routingWithoutPorts.outputPorts.isEmpty;
        expect(hasNoPorts, isTrue);
      });
    });
  });
}
