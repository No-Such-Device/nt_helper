import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  group('RoutingEditorCubit Connection Validation Tests', () {
    late RoutingEditorCubit routingEditorCubit;
    late MockDistingCubit mockDistingCubit;
    late MockDistingMidiManager mockDistingMidiManager;

    setUp(() {
      mockDistingCubit = MockDistingCubit();
      mockDistingMidiManager = MockDistingMidiManager();

      // Set up stream for listening to state changes
      when(() => mockDistingCubit.stream).thenAnswer(
        (_) => Stream.value(
          DistingState.synchronized(
            disting: mockDistingMidiManager,
            distingVersion: '1.0.0',
            firmwareVersion: FirmwareVersion('1.0.0'),
            presetName: 'Test Preset',
            algorithms: [],
            slots: [],
            unitStrings: [],
          ),
        ),
      );

      // Set up initial state
      when(() => mockDistingCubit.state).thenReturn(
        DistingState.synchronized(
          disting: mockDistingMidiManager,
          distingVersion: '1.0.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          presetName: 'Test Preset',
          algorithms: [],
          slots: [],
          unitStrings: [],
        ),
      );

      routingEditorCubit = RoutingEditorCubit(mockDistingCubit);
    });

    tearDown(() {
      routingEditorCubit.close();
    });

    // Helper function to create a Slot with all required parameters
    Slot createSlot({
      required Algorithm algorithm,
      required List<ParameterInfo> parameters,
      required List<ParameterValue> values,
      int algorithmIndex = 0,
    }) {
      return Slot(
        algorithm: algorithm,
        routing: RoutingInfo(algorithmIndex: algorithmIndex, routingInfo: []),
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: []),
        parameters: parameters,
        values: values,
        enums: const [],
        mappings: const [],
        valueStrings: const [],
      );
    }

    group('Connection Validation Integration', () {
      test(
        'should initialize with correct state when cubit provided',
        () async {
          // The cubit should initialize and start listening to DistingCubit
          expect(routingEditorCubit.state, isA<RoutingEditorState>());

          if (routingEditorCubit.state is! RoutingEditorStateLoaded) {
            await routingEditorCubit.stream.firstWhere(
              (state) => state is RoutingEditorStateLoaded,
            );
          }

          // Should have processed the initial state and be loaded (or loading)
          expect(routingEditorCubit.state, isA<RoutingEditorState>());
        },
      );

      test('should handle synchronized state with slots', () async {
        // Create test slots with algorithms
        final testSlots = [
          createSlot(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Algorithm 1',
            ),
            parameters: [
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: 0,
                name: 'Input Bus',
                min: 0,
                max: 28,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
              ),
            ],
            values: [
              ParameterValue(
                algorithmIndex: 0,
                parameterNumber: 0,
                value: 22, // Input from bus 22 (not a hardware bus)
              ),
            ],
            algorithmIndex: 0,
          ),
          createSlot(
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Algorithm 2',
            ),
            parameters: [
              ParameterInfo(
                algorithmIndex: 1,
                parameterNumber: 0,
                name: 'Output Bus',
                min: 0,
                max: 28,
                defaultValue: 13,
                unit: 1,
                powerOfTen: 0,
              ),
            ],
            values: [
              ParameterValue(
                algorithmIndex: 1,
                parameterNumber: 0,
                value: 22, // Creates backward connection to slot 0
              ),
            ],
            algorithmIndex: 1,
          ),
        ];

        // Emit a new state with test slots
        final testState = DistingState.synchronized(
          disting: mockDistingMidiManager,
          distingVersion: '1.0.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          presetName: 'Test Preset',
          algorithms: [],
          slots: testSlots,
          unitStrings: [],
        );

        when(() => mockDistingCubit.state).thenReturn(testState);
        when(
          () => mockDistingCubit.stream,
        ).thenAnswer((_) => Stream.value(testState));

        // Create a new cubit that will process this state
        final testCubit = RoutingEditorCubit(mockDistingCubit);

        if (testCubit.state is! RoutingEditorStateLoaded) {
          await testCubit.stream.firstWhere(
            (state) => state is RoutingEditorStateLoaded,
          );
        }

        // The cubit should have processed the slots and created routing data
        expect(testCubit.state, isA<RoutingEditorStateLoaded>());

        final loadedState = testCubit.state as RoutingEditorStateLoaded;

        // Should have some connections discovered from the shared bus
        final algorithmConnections = loadedState.connections
            .where(
              (conn) =>
                  conn.connectionType == ConnectionType.algorithmToAlgorithm,
            )
            .toList();

        // With session-aware discovery, backward-only scenarios yield no algo→algo edges
        expect(algorithmConnections.isEmpty, isTrue);

        // With our setup (slot 1 outputs to bus 15, slot 0 inputs from bus 15)
        // this creates a backward edge connection
        final backwardConnections = algorithmConnections
            .where((conn) => conn.isBackwardEdge == true)
            .toList();

        // Backward edges are not visualized in session-aware discovery.
        // Expect none.
        expect(backwardConnections.isEmpty, isTrue);

        testCubit.close();
      });

      test('should handle empty slots gracefully', () async {
        final emptySlots = <Slot>[];

        // Mock the DistingCubit state with empty slots
        when(() => mockDistingCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDistingMidiManager,
            distingVersion: '1.0.0',
            firmwareVersion: FirmwareVersion('1.0.0'),
            presetName: 'Empty Preset',
            algorithms: [],
            slots: emptySlots,
            unitStrings: [],
          ),
        );

        // Create cubit with empty state
        final testCubit = RoutingEditorCubit(mockDistingCubit);

        if (testCubit.state is! RoutingEditorStateLoaded) {
          await testCubit.stream.firstWhere(
            (state) => state is RoutingEditorStateLoaded,
          );
        }

        // Should handle empty slots without crashing
        expect(testCubit.state, isA<RoutingEditorState>());

        if (testCubit.state is RoutingEditorStateLoaded) {
          final loadedState = testCubit.state as RoutingEditorStateLoaded;
          expect(loadedState.connections.isEmpty, isTrue);
        }

        testCubit.close();
      });
    });

    group('Connection Highlighting Integration', () {
      test('should correctly identify backward edge connections', () async {
        // Create slots where slot 1 feeds back to slot 0 (backward edge)
        final testSlots = [
          createSlot(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'test-guid-1',
              name: 'Algorithm 1',
            ),
            parameters: [
              ParameterInfo(
                algorithmIndex: 0,
                parameterNumber: 0,
                name: 'Input Bus',
                min: 0,
                max: 28,
                defaultValue: 0,
                unit: 1,
                powerOfTen: 0,
              ),
            ],
            values: [
              ParameterValue(
                algorithmIndex: 0,
                parameterNumber: 0,
                value: 25, // Input from bus 25 (not a hardware bus)
              ),
            ],
            algorithmIndex: 0,
          ),
          createSlot(
            algorithm: Algorithm(
              algorithmIndex: 1,
              guid: 'test-guid-2',
              name: 'Algorithm 2',
            ),
            parameters: [
              ParameterInfo(
                algorithmIndex: 1,
                parameterNumber: 1,
                name: 'Output Bus',
                min: 0,
                max: 28,
                defaultValue: 13,
                unit: 1,
                powerOfTen: 0,
              ),
            ],
            values: [
              ParameterValue(
                algorithmIndex: 1,
                parameterNumber: 1,
                value:
                    25, // Output to bus 25 (consumed by slot 0 - backward edge!)
              ),
            ],
            algorithmIndex: 1,
          ),
        ];

        // Mock the state with backward edge scenario
        final testState = DistingState.synchronized(
          disting: mockDistingMidiManager,
          distingVersion: '1.0.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          presetName: 'Backward Edge Test',
          algorithms: [],
          slots: testSlots,
          unitStrings: [],
        );

        when(() => mockDistingCubit.state).thenReturn(testState);
        when(
          () => mockDistingCubit.stream,
        ).thenAnswer((_) => Stream.value(testState));

        // Create cubit
        final testCubit = RoutingEditorCubit(mockDistingCubit);

        if (testCubit.state is! RoutingEditorStateLoaded) {
          await testCubit.stream.firstWhere(
            (state) => state is RoutingEditorStateLoaded,
          );
        }

        // Check for backward connections
        if (testCubit.state is RoutingEditorStateLoaded) {
          final loadedState = testCubit.state as RoutingEditorStateLoaded;

          // Backward edges are pruned in session-aware discovery; none expected.
          final backwardConnections = loadedState.connections
              .where((conn) => conn.isBackwardEdge)
              .toList();
          expect(backwardConnections.isEmpty, isTrue);
        }

        testCubit.close();
      });
    });

    group('Cubit Initialization', () {
      test('should initialize correctly without cubit', () {
        final standaloneCubit = RoutingEditorCubit(null);

        // Should initialize with initial state
        expect(standaloneCubit.state, isA<RoutingEditorStateInitial>());

        standaloneCubit.close();
      });

      test('should handle cubit state changes', () async {
        // The cubit should be listening to state changes
        expect(routingEditorCubit.state, isA<RoutingEditorState>());

        // Verify it's set up to listen to the mock
        verify(() => mockDistingCubit.stream).called(1);
        verify(() => mockDistingCubit.state).called(greaterThan(0));
      });
    });
  });
}
