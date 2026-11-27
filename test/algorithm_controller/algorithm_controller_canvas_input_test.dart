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
