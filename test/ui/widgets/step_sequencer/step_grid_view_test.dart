import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_column_widget.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_grid_view.dart';

// Mock classes
class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late MockDistingCubit mockCubit;
  late MockDistingMidiManager mockManager;
  late Slot testSlot;
  late DistingStateSynchronized initialState;

  setUp(() {
    mockCubit = MockDistingCubit();
    mockManager = MockDistingMidiManager();

    // Create test slot with parameters
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
        ParameterValue(algorithmIndex: 0, parameterNumber: 2, value: 0),
        ParameterValue(algorithmIndex: 0, parameterNumber: 3, value: 0),
      ],
      enums: const [],
      mappings: const [],
      valueStrings: const [],
    );

    initialState = DistingStateSynchronized(
      disting: mockManager,
      distingVersion: '1.0',
      firmwareVersion: FirmwareVersion('1.0'),
      presetName: 'Test Preset',
      algorithms: [],
      slots: [testSlot],
      unitStrings: [],
      loading: false,
      offline: false,
      demo: false,
    );

    when(() => mockCubit.state).thenReturn(initialState);
    when(() => mockCubit.stream).thenAnswer((_) => Stream.value(initialState));
  });

  Widget makeTestableWidget(Widget child) {
    return BlocProvider<DistingCubit>.value(
      value: mockCubit,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('StepGridView', () {
    testWidgets('Drag gesture is enabled for Pitch mode', (tester) async {
      // State is already set in setUp, but we can override if needed

      await tester.pumpWidget(
        makeTestableWidget(
          StepGridView(
            slot: testSlot,
            slotIndex: 0,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      // Find the GestureDetector that handles drag
      // We look for a GestureDetector that has onPanStart set
      final gestureDetectorFinder = find.byWidgetPredicate((widget) {
        if (widget is GestureDetector) {
          return widget.onPanStart != null;
        }
        return false;
      });

      // Should find at least one GestureDetector with onPanStart
      expect(gestureDetectorFinder, findsWidgets);
    });

    testWidgets('Drag gesture is DISABLED for Pattern mode', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepGridView(
            slot: testSlot,
            slotIndex: 0,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pattern,
          ),
        ),
      );

      // In StepGridView, the GestureDetector wrapping the SingleChildScrollView should have null callbacks
      final singleChildScrollView = find.byType(SingleChildScrollView);
      final gestureDetector = find
          .ancestor(
            of: singleChildScrollView,
            matching: find.byType(GestureDetector),
          )
          .first;

      final widget = tester.widget<GestureDetector>(gestureDetector);
      expect(
        widget.onPanStart,
        isNull,
        reason: 'onPanStart should be null in Pattern mode',
      );
      expect(
        widget.onPanUpdate,
        isNull,
        reason: 'onPanUpdate should be null in Pattern mode',
      );
      expect(
        widget.onPanEnd,
        isNull,
        reason: 'onPanEnd should be null in Pattern mode',
      );
    });

    testWidgets('Drag gesture is DISABLED for Ties mode', (tester) async {
      await tester.pumpWidget(
        makeTestableWidget(
          StepGridView(
            slot: testSlot,
            slotIndex: 0,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.ties,
          ),
        ),
      );

      final singleChildScrollView = find.byType(SingleChildScrollView);
      final gestureDetector = find
          .ancestor(
            of: singleChildScrollView,
            matching: find.byType(GestureDetector),
          )
          .first;

      final widget = tester.widget<GestureDetector>(gestureDetector);
      expect(
        widget.onPanStart,
        isNull,
        reason: 'onPanStart should be null in Ties mode',
      );
    });

    testWidgets('does not throw when its tracked slot is removed', (
      tester,
    ) async {
      final states = StreamController<DistingState>.broadcast();
      addTearDown(states.close);
      when(() => mockCubit.stream).thenAnswer((_) => states.stream);

      await tester.pumpWidget(
        makeTestableWidget(
          StepGridView(
            slot: testSlot,
            slotIndex: 0,
            snapEnabled: false,
            selectedScale: 'Major',
            rootNote: 0,
            activeParameter: StepParameter.pitch,
          ),
        ),
      );

      states.add(initialState.copyWith(slots: []));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(StepColumnWidget), findsNothing);
    }, tags: ['regression']);
  });
}
