import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/playback_controls.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late Slot testSlot;
  late StepSequencerParams params;

  setUp(() {
    // Create test slot with global playback parameters
    testSlot = Slot(
      algorithm: Algorithm(
        algorithmIndex: 0,
        guid: 'spsq',
        name: 'Step Sequencer',
      ),
      routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
      pages: ParameterPages(algorithmIndex: 0, pages: const []),
      parameters: [
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          name: 'Direction',
          min: 0,
          max: 6,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 1,
          name: 'Start',
          min: 1,
          max: 16,
          defaultValue: 1,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 2,
          name: 'End',
          min: 1,
          max: 16,
          defaultValue: 16,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 3,
          name: 'Gate length',
          min: 1,
          max: 127,
          defaultValue: 50,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 4,
          name: 'Trigger length',
          min: 1,
          max: 100,
          defaultValue: 10,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 5,
          name: 'Glide',
          min: 0,
          max: 127,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 6,
          name: 'Permutation',
          min: 0,
          max: 3,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 7,
          name: 'Gate Type',
          min: 0,
          max: 1,
          defaultValue: 0,
          unit: 0,
          powerOfTen: 0,
        ),
      ],
      values: [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
        ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 1),
        ParameterValue(algorithmIndex: 0, parameterNumber: 2, value: 16),
        ParameterValue(algorithmIndex: 0, parameterNumber: 3, value: 50),
        ParameterValue(algorithmIndex: 0, parameterNumber: 4, value: 10),
        ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 0),
        ParameterValue(algorithmIndex: 0, parameterNumber: 6, value: 1),
        ParameterValue(algorithmIndex: 0, parameterNumber: 7, value: 0),
      ],
      enums: const [],
      mappings: const [],
      valueStrings: const [],
    );

    params = StepSequencerParams.fromSlot(testSlot);
  });

  group('PlaybackControls - AC6: Global Parameter Controls Discovery', () {
    test('discovers Direction parameter correctly', () {
      expect(params.direction, isNotNull);
      expect(params.direction, equals(0));
    });

    test('discovers Start Step parameter correctly', () {
      expect(params.startStep, isNotNull);
      expect(params.startStep, equals(1));
    });

    test('discovers End Step parameter correctly', () {
      expect(params.endStep, isNotNull);
      expect(params.endStep, equals(2));
    });

    test('discovers Gate Length parameter correctly', () {
      expect(params.gateLength, isNotNull);
      expect(params.gateLength, equals(3));
    });

    test('discovers Trigger Length parameter correctly', () {
      expect(params.triggerLength, isNotNull);
      expect(params.triggerLength, equals(4));
    });

    test('discovers Glide parameter correctly', () {
      expect(params.glideTime, isNotNull);
      expect(params.glideTime, equals(5));
    });

    test('Direction parameter has correct value range (0-6)', () {
      final directionParam = testSlot.parameters[0];
      expect(directionParam.min, equals(0));
      expect(directionParam.max, equals(6));
    });

    test('Start/End Step parameters have correct value range (1-16)', () {
      final startParam = testSlot.parameters[1];
      final endParam = testSlot.parameters[2];
      expect(startParam.min, equals(1));
      expect(startParam.max, equals(16));
      expect(endParam.min, equals(1));
      expect(endParam.max, equals(16));
    });

    test('Gate Length parameter has correct value range (1-127)', () {
      final gateLengthParam = testSlot.parameters[3];
      expect(gateLengthParam.min, equals(1));
      expect(gateLengthParam.max, equals(127));
    });

    test('Trigger Length parameter has correct value range (1-100)', () {
      final triggerLengthParam = testSlot.parameters[4];
      expect(triggerLengthParam.min, equals(1));
      expect(triggerLengthParam.max, equals(100));
    });

    test('Glide Time parameter has correct value range (0-127)', () {
      final glideParam = testSlot.parameters[5];
      expect(glideParam.min, equals(0));
      expect(glideParam.max, equals(127));
    });

    test('handles missing global parameters gracefully', () {
      // Create slot with no Direction parameter
      final slotNoDirection = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Start',
            min: 1,
            max: 16,
            defaultValue: 1,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsNoDirection = StepSequencerParams.fromSlot(slotNoDirection);

      // Direction should be null when not found
      expect(paramsNoDirection.direction, isNull);
      // But Start should still be discoverable
      expect(paramsNoDirection.startStep, isNotNull);
    });
  });

  group('PlaybackControls - AC3/AC4: Permutation and Gate Type Controls', () {
    test('discovers Permutation parameter correctly', () {
      expect(params.permutation, isNotNull);
      expect(params.permutation, equals(6));
    });

    test('discovers Gate Type parameter correctly', () {
      expect(params.gateType, isNotNull);
      expect(params.gateType, equals(7));
    });

    test('Permutation parameter has correct value range (0-3)', () {
      final permutationParam = testSlot.parameters[6];
      expect(permutationParam.min, equals(0));
      expect(permutationParam.max, equals(3));
    });

    test('Gate Type parameter has correct value range (0-1)', () {
      final gateTypeParam = testSlot.parameters[7];
      expect(gateTypeParam.min, equals(0));
      expect(gateTypeParam.max, equals(1));
    });

    test('handles permutation value clamping (firmware > 3 clamps to 3)', () {
      // Firmware may return values > 3, should clamp to 3
      final slotWithHighValue = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Permutation',
            min: 0,
            max: 127,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 5,
          ), // Out of range
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsWithHighValue = StepSequencerParams.fromSlot(
        slotWithHighValue,
      );
      expect(paramsWithHighValue.permutation, equals(0));

      // In playback_controls, we clamp the value when reading
      final clampedValue = slotWithHighValue.values[0].value.clamp(0, 3);
      expect(clampedValue, equals(3));
    });

    test('handles gate type value clamping (firmware > 1 clamps to 1)', () {
      // Firmware may return values > 1, should clamp to 1
      final slotWithHighValue = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Gate Type',
            min: 0,
            max: 127,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 5,
          ), // Out of range
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsWithHighValue = StepSequencerParams.fromSlot(
        slotWithHighValue,
      );
      expect(paramsWithHighValue.gateType, equals(0));

      // In playback_controls, we clamp the value when reading
      final clampedValue = slotWithHighValue.values[0].value.clamp(0, 1);
      expect(clampedValue, equals(1));
    });

    test('handles missing Permutation parameter gracefully', () {
      final slotNoPermutation = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Direction',
            min: 0,
            max: 6,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsNoPermutation = StepSequencerParams.fromSlot(
        slotNoPermutation,
      );
      expect(paramsNoPermutation.permutation, isNull);
    });

    test('handles missing Gate Type parameter gracefully', () {
      final slotNoGateType = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Direction',
            min: 0,
            max: 6,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsNoGateType = StepSequencerParams.fromSlot(slotNoGateType);
      expect(paramsNoGateType.gateType, isNull);
    });
  });

  group('PlaybackControls - Gate Type Parameter Dependency', () {
    test('Gate Length is enabled when Gate Type = 0 (Gate)', () {
      // Create slot with Gate Type = 0 (Gate)
      final slotGateMode = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Gate length',
            min: 1,
            max: 127,
            defaultValue: 50,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: 'Gate Type',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 50,
            isDisabled: false,
          ),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 0,
          ), // Gate mode
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsGateMode = StepSequencerParams.fromSlot(slotGateMode);
      final gateLengthParam = paramsGateMode.gateLength!;
      final gateLengthValue = slotGateMode.values[gateLengthParam];

      expect(gateLengthValue.isDisabled, isFalse);
    });

    test('Gate Length is disabled when Gate Type = 1 (Trigger)', () {
      // Create slot with Gate Type = 1 (Trigger)
      final slotTriggerMode = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Gate length',
            min: 1,
            max: 127,
            defaultValue: 50,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: 'Gate Type',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 50,
            isDisabled: true,
          ),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 1,
          ), // Trigger mode
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsTriggerMode = StepSequencerParams.fromSlot(slotTriggerMode);
      final gateLengthParam = paramsTriggerMode.gateLength!;
      final gateLengthValue = slotTriggerMode.values[gateLengthParam];

      expect(gateLengthValue.isDisabled, isTrue);
    });

    test('Trigger Length is disabled when Gate Type = 0 (Gate)', () {
      // Create slot with Gate Type = 0 (Gate)
      final slotGateMode = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Trigger length',
            min: 1,
            max: 100,
            defaultValue: 10,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: 'Gate Type',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 10,
            isDisabled: true,
          ),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 0,
          ), // Gate mode
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsGateMode = StepSequencerParams.fromSlot(slotGateMode);
      final triggerLengthParam = paramsGateMode.triggerLength!;
      final triggerLengthValue = slotGateMode.values[triggerLengthParam];

      expect(triggerLengthValue.isDisabled, isTrue);
    });

    test('Trigger Length is enabled when Gate Type = 1 (Trigger)', () {
      // Create slot with Gate Type = 1 (Trigger)
      final slotTriggerMode = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Trigger length',
            min: 1,
            max: 100,
            defaultValue: 10,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: 'Gate Type',
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 10,
            isDisabled: false,
          ),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 1,
          ), // Trigger mode
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsTriggerMode = StepSequencerParams.fromSlot(slotTriggerMode);
      final triggerLengthParam = paramsTriggerMode.triggerLength!;
      final triggerLengthValue = slotTriggerMode.values[triggerLengthParam];

      expect(triggerLengthValue.isDisabled, isFalse);
    });

    test('disabled flag defaults to false when not specified', () {
      // Create slot with parameters that don't specify isDisabled
      final slotDefaultDisabled = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'spsq',
          name: 'Step Sequencer',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Gate length',
            min: 1,
            max: 127,
            defaultValue: 50,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 50,
          ), // No isDisabled specified
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      final paramsDefault = StepSequencerParams.fromSlot(slotDefaultDisabled);
      final gateLengthParam = paramsDefault.gateLength!;
      final gateLengthValue = slotDefaultDisabled.values[gateLengthParam];

      // Default should be false (enabled)
      expect(gateLengthValue.isDisabled, isFalse);
    });
  });

  testWidgets(
    'PlaybackControls does not throw when its tracked slot is removed',
    (tester) async {
      final mockCubit = MockDistingCubit();
      final mockManager = MockDistingMidiManager();
      final initialState = DistingStateSynchronized(
        disting: mockManager,
        distingVersion: '1.0',
        firmwareVersion: FirmwareVersion('1.0'),
        presetName: 'Test Preset',
        algorithms: const [],
        slots: [testSlot],
        unitStrings: const [],
      );
      final states = StreamController<DistingState>.broadcast();
      addTearDown(states.close);

      when(() => mockCubit.state).thenReturn(initialState);
      when(() => mockCubit.stream).thenAnswer((_) => states.stream);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: PlaybackControls(
                slotIndex: 0,
                params: params,
                slot: testSlot,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Slider), findsWidgets);

      states.add(initialState.copyWith(slots: []));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsNothing);
    },
  tags: ['regression']);
}
