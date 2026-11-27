import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_canvas_input.dart';

void main() {
  group('canvas hit geometry and deterministic ordering', () {
    test(
      'excludes background, out-of-bounds, disabled, and invalid targets',
      () {
        const targets = [
          AlgorithmControllerCanvasTarget(
            id: 'invalid-radius',
            label: 'Invalid radius',
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'invalid-rect',
            label: 'Invalid rect',
            hitArea: AlgorithmControllerCanvasRectHitArea(
              x: 0.0,
              y: 0.0,
              width: -0.2,
              height: 0.5,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'invalid-nan',
            label: 'NaN circle',
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: double.nan,
              y: 0.5,
              radius: 0.1,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'disabled',
            label: 'Disabled',
            enabled: false,
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.2,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'valid-circle',
            label: 'Valid circle',
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.1,
            ),
          ),
        ];

        const size = Size(400, 200);
        expect(
          hitTestCanvasTargets(
            targets,
            const Offset(200, 100),
            size,
          ).map((target) => target.id),
          ['valid-circle'],
        );
        expect(
          hitTestCanvasTargets(targets, const Offset(10, 10), size),
          isEmpty,
        );
        expect(
          hitTestCanvasTargets(targets, const Offset(-5, 100), size),
          isEmpty,
        );
        expect(
          hitTestCanvasTargets(targets, const Offset(405, 100), size),
          isEmpty,
        );
        expect(canvasHitAreaBounds(targets.first.hitArea, size), Rect.zero);
      },
    );

    test(
      'orders overlapping targets deterministically by order then index',
      () {
        const targets = [
          AlgorithmControllerCanvasTarget(
            id: 'unordered-first',
            label: 'Unordered first',
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.2,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'order-2',
            label: 'Order 2',
            order: 2,
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.2,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'order-1',
            label: 'Order 1',
            order: 1,
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.2,
            ),
          ),
          AlgorithmControllerCanvasTarget(
            id: 'order-2-second',
            label: 'Order 2 second',
            order: 2,
            hitArea: AlgorithmControllerCanvasCircleHitArea(
              x: 0.5,
              y: 0.5,
              radius: 0.2,
            ),
          ),
        ];

        final hits = hitTestCanvasTargets(
          targets,
          const Offset(200, 100),
          const Size(400, 200),
        );
        expect(hits.map((target) => target.id), [
          'order-1',
          'order-2',
          'order-2-second',
          'unordered-first',
        ]);
      },
    );
  });

  group('canvas axis and wheel quantization and validation', () {
    test('maps, clamps, inverts, and quantizes axis bindings', () {
      final slot = _syntheticSlot(xValue: 50, yValue: 0);
      const xAxis = AlgorithmControllerCanvasAxisBinding(
        parameterNumber: 1,
        from: 0.1,
        to: 0.9,
        step: 5,
      );
      const yAxis = AlgorithmControllerCanvasAxisBinding(
        parameterNumber: 2,
        from: 0.1,
        to: 0.9,
        step: 10,
        invert: true,
      );

      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: xAxis,
          normalizedCoordinate: 0,
        ),
        0,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: xAxis,
          normalizedCoordinate: 0.5,
        ),
        50,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: xAxis,
          normalizedCoordinate: 0.53,
        ),
        55,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: xAxis,
          normalizedCoordinate: 1.5,
        ),
        100,
      );

      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: yAxis,
          normalizedCoordinate: 0.1,
        ),
        100,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: yAxis,
          normalizedCoordinate: 0.9,
        ),
        -100,
      );
    });

    test('rejects missing, disabled, constant, or I/O descriptors', () {
      final slot = _syntheticSlot(
        xDisabled: true,
        yMin: 10,
        yMax: 10,
        qIoFlags: 1,
      );

      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: const AlgorithmControllerCanvasAxisBinding(parameterNumber: 99),
          normalizedCoordinate: 0.5,
        ),
        isNull,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: const AlgorithmControllerCanvasAxisBinding(parameterNumber: 1),
          normalizedCoordinate: 0.5,
        ),
        isNull,
      );
      expect(
        resolveCanvasAxisValue(
          slot: slot,
          axis: const AlgorithmControllerCanvasAxisBinding(parameterNumber: 2),
          normalizedCoordinate: 0.5,
        ),
        isNull,
      );
      expect(
        resolveCanvasWheelValue(
          slot: slot,
          wheel: const AlgorithmControllerCanvasWheelBinding(
            parameterNumber: 3,
          ),
          scrollDelta: const Offset(0, -120),
        ),
        isNull,
      );
    });

    test('computes wheel steps, clamping, and unchanged no-op detection', () {
      final slot = _syntheticSlot(qValue: 100);
      const wheel = AlgorithmControllerCanvasWheelBinding(
        parameterNumber: 3,
        step: 5,
      );

      final atMax = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, -120),
      );
      expect(atMax, isNotNull);
      expect(atMax!.nextValue, 100);
      expect(atMax.changed, isFalse);

      final steppedDown = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, 120),
      );
      expect(steppedDown, isNotNull);
      expect(steppedDown!.nextValue, 95);
      expect(steppedDown.changed, isTrue);

      final zeroDelta = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(40, 0),
      );
      expect(zeroDelta, isNull);

      final diagonalHorizontal = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(120, -120),
      );
      expect(diagonalHorizontal, isNull);
    });

    test('W1: treats discrete vertical wheel events at or above 40 logical px as one step with no carry, and accumulates sub-floor fragments', () {
      final slot = _syntheticSlot(qValue: 50);
      const wheel = AlgorithmControllerCanvasWheelBinding(
        parameterNumber: 3,
        step: 1,
      );

      // Parameterized embedder-derived samples (macOS ~40, Linux ~53,
      // Windows ~66.7-100) plus a large coalesced/accelerated sample (240):
      // each single event takes exactly one step with zero leftover fraction.
      for (final magnitude in const [40.0, 53.0, 66.7, 100.0, 240.0]) {
        final up = resolveCanvasWheelValue(
          slot: slot,
          wheel: wheel,
          scrollDelta: Offset(0, -magnitude),
        );
        expect(up, isNotNull, reason: 'up -$magnitude');
        expect(up!.changed, isTrue, reason: 'up -$magnitude');
        expect(up.stepCount, 1, reason: 'up -$magnitude');
        expect(up.nextValue, 51, reason: 'up -$magnitude');
        expect(up.remainingDy, 0.0, reason: 'up -$magnitude');

        final down = resolveCanvasWheelValue(
          slot: slot,
          wheel: wheel,
          scrollDelta: Offset(0, magnitude),
        );
        expect(down, isNotNull, reason: 'down +$magnitude');
        expect(down!.changed, isTrue, reason: 'down +$magnitude');
        expect(down.stepCount, 1, reason: 'down +$magnitude');
        expect(down.nextValue, 49, reason: 'down +$magnitude');
        expect(down.remainingDy, 0.0, reason: 'down +$magnitude');

        // A discrete event also discards any earlier sub-floor carry.
        final withCarry = resolveCanvasWheelValue(
          slot: slot,
          wheel: wheel,
          scrollDelta: Offset(0, -magnitude),
          priorAccumulatedDy: -30.0,
        )!;
        expect(withCarry.changed, isTrue, reason: 'carry -$magnitude');
        expect(withCarry.stepCount, 1, reason: 'carry -$magnitude');
        expect(withCarry.nextValue, 51, reason: 'carry -$magnitude');
        expect(withCarry.remainingDy, 0.0, reason: 'carry -$magnitude');
      }

      // Sub-floor fragments (4 x -10): zero change on first 3, one step on #4.
      var acc = 0.0;
      for (var i = 0; i < 3; i++) {
        final res = resolveCanvasWheelValue(
          slot: slot,
          wheel: wheel,
          scrollDelta: const Offset(0, -10),
          priorAccumulatedDy: acc,
        )!;
        expect(res.changed, isFalse);
        expect(res.stepCount, 0);
        acc = res.remainingDy;
      }
      expect(acc, closeTo(-30.0, 1e-6));

      final fourth = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, -10),
        priorAccumulatedDy: acc,
      )!;
      expect(fourth.changed, isTrue);
      expect(fourth.stepCount, 1);
      expect(fourth.nextValue, 51);
      expect(fourth.remainingDy, 0.0);

      // Sub-floor overshoot keeps only the unused sub-floor fraction.
      final part1 = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, -25),
      )!;
      expect(part1.changed, isFalse);
      expect(part1.remainingDy, closeTo(-25.0, 1e-6));

      final part2 = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, -25),
        priorAccumulatedDy: part1.remainingDy,
      )!;
      expect(part2.changed, isTrue);
      expect(part2.stepCount, 1);
      expect(part2.nextValue, 51);
      expect(part2.remainingDy, closeTo(-10.0, 1e-6));

      final part3 = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, -30),
        priorAccumulatedDy: part2.remainingDy,
        currentValueOverride: part2.nextValue,
      )!;
      expect(part3.changed, isTrue);
      expect(part3.stepCount, 1);
      expect(part3.nextValue, 52);
      expect(part3.remainingDy, 0.0);
    });

    test('handles wheel direction reversal, invert, step scaling, and at-limit reset under the 40-logical-px floor', () {
      final slot = _syntheticSlot(qValue: 50);
      const wheel = AlgorithmControllerCanvasWheelBinding(
        parameterNumber: 3,
        step: 1,
      );

      // Direction reversal clears opposite-direction sub-floor carry.
      final reversedSubFloor = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, 25),
        priorAccumulatedDy: -30.0,
        currentValueOverride: 52,
      )!;
      expect(reversedSubFloor.changed, isFalse);
      expect(reversedSubFloor.remainingDy, closeTo(25.0, 1e-6));

      final reversedComplete = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, 15),
        priorAccumulatedDy: reversedSubFloor.remainingDy,
        currentValueOverride: 52,
      )!;
      expect(reversedComplete.changed, isTrue);
      expect(reversedComplete.nextValue, 51);
      expect(reversedComplete.remainingDy, 0.0);

      // Reversal with a discrete event clears opposite carry and steps once.
      final reversedDiscrete = resolveCanvasWheelValue(
        slot: slot,
        wheel: wheel,
        scrollDelta: const Offset(0, 40),
        priorAccumulatedDy: -30.0,
        currentValueOverride: 52,
      )!;
      expect(reversedDiscrete.changed, isTrue);
      expect(reversedDiscrete.stepCount, 1);
      expect(reversedDiscrete.nextValue, 51);
      expect(reversedDiscrete.remainingDy, 0.0);

      // Configured step > 1 still steps once per discrete event (even for large delta).
      final stepped = resolveCanvasWheelValue(
        slot: slot,
        wheel: const AlgorithmControllerCanvasWheelBinding(
          parameterNumber: 3,
          step: 5,
        ),
        scrollDelta: const Offset(0, -100),
      )!;
      expect(stepped.changed, isTrue);
      expect(stepped.stepCount, 1);
      expect(stepped.nextValue, 55);
      expect(stepped.remainingDy, 0.0);

      // Inverted wheel reverses direction.
      final inverted = resolveCanvasWheelValue(
        slot: slot,
        wheel: const AlgorithmControllerCanvasWheelBinding(
          parameterNumber: 3,
          step: 5,
          invert: true,
        ),
        scrollDelta: const Offset(0, -40),
      )!;
      expect(inverted.changed, isTrue);
      expect(inverted.nextValue, 45);
      expect(inverted.remainingDy, 0.0);

      // At-limit clears accumulation immediately without writing.
      final atLimit = resolveCanvasWheelValue(
        slot: _syntheticSlot(qValue: 100),
        wheel: wheel,
        scrollDelta: const Offset(0, -10),
        priorAccumulatedDy: -25.0,
      )!;
      expect(atLimit.changed, isFalse);
      expect(atLimit.remainingDy, 0.0);

      // Stepping into max via sub-floor carry clears over-limit remainder.
      final hitMax = resolveCanvasWheelValue(
        slot: _syntheticSlot(qValue: 98),
        wheel: const AlgorithmControllerCanvasWheelBinding(
          parameterNumber: 3,
          step: 5,
        ),
        scrollDelta: const Offset(0, -25),
        priorAccumulatedDy: -25.0,
      )!;
      expect(hitMax.changed, isTrue);
      expect(hitMax.nextValue, 100);
      expect(hitMax.remainingDy, 0.0);
    });

    test('formats canvas parameter values with device strings, enums, scaling/units, and rejects I/O', () {
      final slot = Slot(
        algorithm: Algorithm(algorithmIndex: 1, guid: 'test', name: 'Test'),
        routing: RoutingInfo.filler(),
        pages: ParameterPages(algorithmIndex: 1, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 1,
            parameterNumber: 1,
            min: -100,
            max: 100,
            defaultValue: 0,
            unit: 2,
            name: 'Gain',
            powerOfTen: -1,
          ),
          ParameterInfo(
            algorithmIndex: 1,
            parameterNumber: 2,
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: 1,
            name: 'Mode',
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 1,
            parameterNumber: 3,
            min: 0,
            max: 100,
            defaultValue: 50,
            unit: 0,
            name: 'IO Param',
            powerOfTen: 0,
            ioFlags: 1,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 1, parameterNumber: 1, value: 35),
          ParameterValue(algorithmIndex: 1, parameterNumber: 2, value: 1),
          ParameterValue(algorithmIndex: 1, parameterNumber: 3, value: 50),
        ],
        enums: [
          ParameterEnumStrings(
            algorithmIndex: 1,
            parameterNumber: 1,
            values: const [],
          ),
          ParameterEnumStrings(
            algorithmIndex: 1,
            parameterNumber: 2,
            values: const ['Off', 'Peak'],
          ),
          ParameterEnumStrings(
            algorithmIndex: 1,
            parameterNumber: 3,
            values: const [],
          ),
        ],
        mappings: [Mapping.filler(), Mapping.filler(), Mapping.filler()],
        valueStrings: [
          ParameterValueString(
            algorithmIndex: 1,
            parameterNumber: 1,
            value: '+3.5 dB',
          ),
          ParameterValueString(
            algorithmIndex: 1,
            parameterNumber: 2,
            value: '',
          ),
          ParameterValueString(
            algorithmIndex: 1,
            parameterNumber: 3,
            value: '',
          ),
        ],
      );

      expect(
        formatCanvasParameterValue(
          slot: slot,
          parameterNumber: 1,
          value: 35,
          units: const ['%', 'dB'],
        ),
        '+3.5 dB',
      );
      expect(
        formatCanvasParameterValue(
          slot: slot,
          parameterNumber: 1,
          value: 40,
          units: const ['%', 'dB'],
        ),
        '4.0 dB',
      );
      expect(
        formatCanvasParameterValue(slot: slot, parameterNumber: 2, value: 1),
        'Peak',
      );
      expect(
        formatCanvasParameterValue(slot: slot, parameterNumber: 3, value: 50),
        isNull,
      );
      expect(
        formatCanvasParameterValue(slot: slot, parameterNumber: 99, value: 10),
        isNull,
      );
    });
  });
}

Slot _syntheticSlot({
  int xValue = 50,
  int yValue = 0,
  int qValue = 50,
  bool xDisabled = false,
  int yMin = -100,
  int yMax = 100,
  int qIoFlags = 0,
}) {
  return Slot(
    algorithm: Algorithm(algorithmIndex: 1, guid: 'test', name: 'Synthetic'),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(algorithmIndex: 1, pages: const []),
    parameters: [
      ParameterInfo(
        algorithmIndex: 1,
        parameterNumber: 1,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'X',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 1,
        parameterNumber: 2,
        min: yMin,
        max: yMax,
        defaultValue: 0,
        unit: 0,
        name: 'Y',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 1,
        parameterNumber: 3,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Q',
        powerOfTen: 0,
        ioFlags: qIoFlags,
      ),
    ],
    values: [
      ParameterValue(
        algorithmIndex: 1,
        parameterNumber: 1,
        value: xValue,
        isDisabled: xDisabled,
      ),
      ParameterValue(algorithmIndex: 1, parameterNumber: 2, value: yValue),
      ParameterValue(algorithmIndex: 1, parameterNumber: 3, value: qValue),
    ],
    enums: [
      ParameterEnumStrings(
        algorithmIndex: 1,
        parameterNumber: 1,
        values: const [],
      ),
      ParameterEnumStrings(
        algorithmIndex: 1,
        parameterNumber: 2,
        values: const [],
      ),
      ParameterEnumStrings(
        algorithmIndex: 1,
        parameterNumber: 3,
        values: const [],
      ),
    ],
    mappings: [Mapping.filler(), Mapping.filler(), Mapping.filler()],
    valueStrings: [
      ParameterValueString(algorithmIndex: 1, parameterNumber: 1, value: ''),
      ParameterValueString(algorithmIndex: 1, parameterNumber: 2, value: ''),
      ParameterValueString(algorithmIndex: 1, parameterNumber: 3, value: ''),
    ],
  );
}
