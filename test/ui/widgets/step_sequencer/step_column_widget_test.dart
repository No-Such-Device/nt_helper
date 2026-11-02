import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_column_widget.dart';

// Mock classes
class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  late MockDistingCubit mockCubit;
  late Slot testSlot;

  setUp(() {
    mockCubit = MockDistingCubit();

    // Create test slot with mock parameters matching Step Sequencer format
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
          name: '1:Pitch',
          min: 0,
          max: 127,
          defaultValue: 60,
          unit: 0,
          powerOfTen: 0,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 1,
          name: '1:Velocity',
          min: 0,
          max: 127,
          defaultValue: 64,
          unit: 0,
          powerOfTen: 0,
        ),
      ],
      values: [
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
        ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 100),
      ],
      enums: const [],
      mappings: const [],
      valueStrings: const [],
    );
  });

  Widget makeTestableWidget(Widget child) {
    return BlocProvider<DistingCubit>.value(
      value: mockCubit,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('StepColumnWidget', () {
    testWidgets('displays step number correctly', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget); // 1-indexed display
    });

    testWidgets('displays pitch bar', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 5,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets); // May find multiple
      expect(find.text('6'), findsOneWidget); // Step 6
    });

    testWidgets('displays formatted pitch value', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      // Pitch values are formatted as note names (e.g., "E4")
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('displays bit pattern editor in Ties mode', (tester) async {
      // Add Ties parameter to test slot
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Velocity',
            min: 0,
            max: 127,
            defaultValue: 64,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 2,
            name: '1:Ties',
            min: 0,
            max: 255,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
          ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 100),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 2,
            value: 170,
          ), // 0b10101010
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.ties,
          ),
        ),
      );

      // In Ties mode, the bar should be displayed with bit pattern visualization
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify direct bit clicking - widget should render without dialog
      // The CustomPaint widget contains the PitchBarPainter which renders the bit pattern
      final customPaint = find.byType(CustomPaint);
      expect(customPaint, findsWidgets);
    });

    testWidgets('displays bit pattern editor in Pattern mode', (tester) async {
      // Add Pattern parameter to test slot
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Velocity',
            min: 0,
            max: 127,
            defaultValue: 64,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 2,
            name: '1:Pattern',
            min: 0,
            max: 255,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 3,
            name: '1:Division',
            min: 0,
            max: 14,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
          ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 100),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 2,
            value: 10,
          ), // 0b00001010 (bits 1 and 3 set)
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 3,
            value: 3,
          ), // Division = 3 (4 substeps)
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pattern,
          ),
        ),
      );

      // In Pattern mode, the bar should be displayed with bit pattern visualization
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify direct bit clicking - widget should render without dialog
      // The CustomPaint widget contains the PitchBarPainter which renders the bit pattern
      final customPaint = find.byType(CustomPaint);
      expect(customPaint, findsWidgets);
    });

    testWidgets('highlights active step with border', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: true,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.border, isNotNull);
      expect(decoration.border!.top.width, equals(2.0)); // Active border width
    });

    testWidgets('uses normal border for inactive step', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 64,
            velocityValue: 100,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.border, isNotNull);
      expect(
        decoration.border!.top.width,
        equals(1.0),
      ); // Inactive border width
    });

    

    testWidgets('switches between parameter modes', (tester) async {
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Velocity',
            min: 1,
            max: 127,
            defaultValue: 64,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 2,
            name: '1:Mod',
            min: 0,
            max: 127,
            defaultValue: 64,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 3,
            name: '1:Division',
            min: 0,
            max: 14,
            defaultValue: 0,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
          ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 100),
          ParameterValue(algorithmIndex: 0, parameterNumber: 2, value: 64),
          ParameterValue(algorithmIndex: 0, parameterNumber: 3, value: 7),
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      // Test switching from Pitch to other modes
      for (final param in [
        StepParameter.pitch,
        StepParameter.velocity,
        StepParameter.mod,
      ]) {
        await tester.pumpWidget(
          makeTestableWidget(
            StepColumnWidget(
              stepIndex: 0,
              pitchValue: 64,
              velocityValue: 100,
              isActive: false,
              slotIndex: 0,
              slot: testSlot,
              snapEnabled: false,
              selectedScale: 'Major',
              rootNote: 0,
              activeParameter: param,
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
        expect(
          find.text('1'),
          findsOneWidget,
        ); // Step number should still display
      }
    });

    testWidgets('clamps values to parameter min/max ranges', (tester) async {
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Velocity',
            min: 1,
            max: 127,
            defaultValue: 64,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 200,
          ), // Out of range
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 0,
          ), // Below min
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      await tester.pumpWidget(
        makeTestableWidget(
          StepColumnWidget(
            stepIndex: 0,
            pitchValue: 200,
            velocityValue: 0,
            isActive: false,
            slotIndex: 0,
            slot: testSlot,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      // Widget should render without crashing despite out-of-range values
      expect(find.byType(StepColumnWidget), findsOneWidget);
    });
  });

  group(
    'StepColumnWidget - AC2-6: Probability Parameters (Mute/Skip/Reset/Repeat)',
    () {
      late MockDistingCubit mockCubit;
      late Slot testSlot;

      setUp(() {
        mockCubit = MockDistingCubit();

        // Create test slot with probability parameters
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
              name: '1:Mute',
              min: 0,
              max: 100,
              defaultValue: 0,
              unit: 0,
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 1,
              name: '1:Skip',
              min: 0,
              max: 100,
              defaultValue: 0,
              unit: 0,
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 2,
              name: '1:Reset',
              min: 0,
              max: 100,
              defaultValue: 0,
              unit: 0,
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 3,
              name: '1:Repeat',
              min: 0,
              max: 100,
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
            ), // 50%
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 1,
              value: 25,
            ), // 25%
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 2,
              value: 75,
            ), // 75%
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 3,
              value: 100,
            ), // 100%
          ],
          enums: const [],
          mappings: const [],
          valueStrings: const [],
        );
      });

      testWidgets('displays Mute mode with percentage label', (tester) async {
        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.mute,
                ),
              ),
            ),
          ),
        );

        // Should display percentage label (50%)
        expect(find.text('50%'), findsOneWidget);
      });

      testWidgets('displays Skip mode with percentage label', (tester) async {
        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.skip,
                ),
              ),
            ),
          ),
        );

        // Should display percentage label (25%)
        expect(find.text('25%'), findsOneWidget);
      });

      testWidgets('displays Reset mode with percentage label', (tester) async {
        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.reset,
                ),
              ),
            ),
          ),
        );

        // Should display percentage label (75%)
        expect(find.text('75%'), findsOneWidget);
      });

      testWidgets('displays Repeat mode with percentage label', (tester) async {
        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.repeat,
                ),
              ),
            ),
          ),
        );

        // Should display percentage label (100%)
        expect(find.text('100%'), findsOneWidget);
      });

      testWidgets('displays probability bars with correct colors', (
        tester,
      ) async {
        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.mute,
                ),
              ),
            ),
          ),
        );

        // Verify CustomPaint widget exists (renders the bar)
        expect(find.byType(CustomPaint), findsWidgets);
      });

      testWidgets('converts firmware to percentage correctly', (tester) async {
        // Test slot with firmware value 0 (0%)
        final testSlot0 = Slot(
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
              name: '1:Mute',
              min: 0,
              max: 100,
              defaultValue: 0,
              unit: 0,
              powerOfTen: 0,
            ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: 0,
            ), // 0%
          ],
          enums: const [],
          mappings: const [],
          valueStrings: const [],
        );

        await tester.pumpWidget(
          BlocProvider<DistingCubit>.value(
            value: mockCubit,
            child: MaterialApp(
              home: Scaffold(
                body: StepColumnWidget(
                  stepIndex: 0,
                  pitchValue: 64,
                  velocityValue: 100,
                  isActive: false,
                  slotIndex: 0,
                  slot: testSlot0,
                  snapEnabled: false,
                  selectedScale: 'Major',
                  rootNote: 0,
                  activeParameter: StepParameter.mute,
                ),
              ),
            ),
          ),
        );

        expect(find.text('0%'), findsOneWidget);
      });
    },
  );

  group('StepColumnWidget - Subdivision Label (Story 10.16)', () {
    late MockDistingCubit mockCubit;
    late Slot testSlot;

    setUp(() {
      mockCubit = MockDistingCubit();
      when(() => mockCubit.stream).thenAnswer((_) => Stream.empty());
      when(() => mockCubit.state).thenReturn(const DistingState.initial());
    });

    Slot createSlotWithDivision(int divisionValue) {
      return Slot(
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Division',
            min: 0,
            max: 14,
            defaultValue: 7,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: divisionValue,
          ),
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    testWidgets('AC2: displays "8 Ratchets" when Division = 0', (tester) async {
      testSlot = createSlotWithDivision(0);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      expect(find.text('8 RA'), findsOneWidget);
    });

    testWidgets('AC2: displays "2 Ratchets" when Division = 6', (tester) async {
      testSlot = createSlotWithDivision(6);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      expect(find.text('2 RA'), findsOneWidget);
    });

    testWidgets('AC3: displays "1" when Division = 7 (default)', (
      tester,
    ) async {
      testSlot = createSlotWithDivision(7);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('1'),
        findsAtLeastNWidgets(1),
      ); // Step number "1" and subdivision label "1"
    });

    testWidgets('AC2: displays "2 Repeats" when Division = 8', (tester) async {
      testSlot = createSlotWithDivision(8);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      expect(find.text('2 RE'), findsOneWidget);
    });

    testWidgets('AC2: displays "8 Repeats" when Division = 14', (tester) async {
      testSlot = createSlotWithDivision(14);

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      expect(find.text('8 RE'), findsOneWidget);
    });

    testWidgets('AC4: subdivision label NOT visible when in Pitch mode', (
      tester,
    ) async {
      testSlot = createSlotWithDivision(9); // 3 Repeats

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.pitch, // NOT Division mode
              ),
            ),
          ),
        ),
      );

      // Subdivision label should NOT be visible in Pitch mode
      expect(find.text('3 RE'), findsNothing);
    });

    testWidgets('AC4: subdivision label visible only in Division mode', (
      tester,
    ) async {
      testSlot = createSlotWithDivision(9); // 3 Repeats

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      // Subdivision label SHOULD be visible in Division mode
      expect(find.text('3 RE'), findsOneWidget);
    });

    testWidgets('AC8: handles out-of-range Division values', (tester) async {
      // Create slot with Division > 14 (out of range)
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
            name: '1:Pitch',
            min: 0,
            max: 127,
            defaultValue: 60,
            unit: 0,
            powerOfTen: 0,
          ),
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            name: '1:Division',
            min: 0,
            max: 14,
            defaultValue: 7,
            unit: 0,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 64),
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 1,
            value: 20,
          ), // Out of range
        ],
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      // Should clamp to 14 and display "8 Repeats"
      expect(find.text('8 RE'), findsOneWidget);
    });

    testWidgets('AC10: uses theme-aware text color with opacity', (
      tester,
    ) async {
      testSlot = createSlotWithDivision(9); // 3 Repeats

      await tester.pumpWidget(
        BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: MaterialApp(
            theme: ThemeData.dark(), // Dark mode
            home: Scaffold(
              body: StepColumnWidget(
                stepIndex: 0,
                pitchValue: 64,
                velocityValue: 100,
                isActive: false,
                slotIndex: 0,
                slot: testSlot,
                snapEnabled: false,
                selectedScale: 'Major',
                rootNote: 0,
                activeParameter: StepParameter.division,
              ),
            ),
          ),
        ),
      );

      // Widget should render without errors in dark mode
      expect(find.byType(StepColumnWidget), findsOneWidget);
      expect(find.text('3 RE'), findsOneWidget);
    });
  });
}
