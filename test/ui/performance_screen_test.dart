import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/performance_screen.dart';
import 'package:nt_helper/ui/widgets/performance/hardware_preview_widget.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late MockDistingCubit mockCubit;

  setUp(() {
    mockCubit = MockDistingCubit();
    when(() => mockCubit.refreshPerfPageItems()).thenAnswer((_) async {});
  });

  Widget createTestWidget({required Widget child, double width = 800}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 600)),
        child: BlocProvider<DistingCubit>.value(value: mockCubit, child: child),
      ),
    );
  }

  MappedParameter createMappedParameter({
    required int perfPageIndex,
    required String algorithmName,
    required int algorithmIndex,
    required String parameterName,
    required int parameterNumber,
  }) {
    return MappedParameter(
      parameter: ParameterInfo(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        name: parameterName,
        unit: 0,
        min: 0,
        max: 100,
        defaultValue: 50,
        powerOfTen: 0,
      ),
      value: ParameterValue(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        value: 50,
      ),
      enums: ParameterEnumStrings(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        values: const [],
      ),
      valueString: ParameterValueString(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        value: '50',
      ),
      mapping: Mapping(
        algorithmIndex: algorithmIndex,
        parameterNumber: parameterNumber,
        packedMappingData: PackedMappingData(
          source: 0,
          cvInput: 0,
          isUnipolar: false,
          isGate: false,
          volts: 0,
          delta: 0,
          midiChannel: 0,
          midiMappingType: MidiMappingType.cc,
          midiCC: 1,
          isMidiEnabled: true,
          isMidiSymmetric: false,
          isMidiRelative: false,
          midiMin: 0,
          midiMax: 127,
          i2cCC: 0,
          isI2cEnabled: false,
          isI2cSymmetric: false,
          i2cMin: 0,
          i2cMax: 0,
          perfPageIndex: perfPageIndex,
          version: 5,
        ),
      ),
      algorithm: Algorithm(
        algorithmIndex: algorithmIndex,
        guid: 'test-guid-$algorithmIndex',
        name: algorithmName,
      ),
    );
  }

  Slot createSlotFromMappedParameters(List<MappedParameter> params) {
    if (params.isEmpty) {
      return Slot(
        algorithm: Algorithm(algorithmIndex: 0, guid: 'empty', name: 'Empty'),
        routing: RoutingInfo.filler(),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
        parameters: [],
        values: [],
        enums: [],
        mappings: [],
        valueStrings: [],
      );
    }

    final algorithmIndex = params.first.parameter.algorithmIndex;
    final maxParamNum = params
        .map((p) => p.parameter.parameterNumber)
        .reduce((a, b) => a > b ? a : b);
    final arraySize = maxParamNum + 1;

    final parameters = List<ParameterInfo>.filled(
      arraySize,
      ParameterInfo.filler(),
    );
    final values = List<ParameterValue>.filled(
      arraySize,
      ParameterValue.filler(),
    );
    final enums = List<ParameterEnumStrings>.filled(
      arraySize,
      ParameterEnumStrings.filler(),
    );
    final mappings = List<Mapping>.filled(arraySize, Mapping.filler());
    final valueStrings = List<ParameterValueString>.filled(
      arraySize,
      ParameterValueString.filler(),
    );

    for (final param in params) {
      final paramNum = param.parameter.parameterNumber;
      parameters[paramNum] = param.parameter;
      values[paramNum] = param.value;
      enums[paramNum] = param.enums;
      mappings[paramNum] = param.mapping;
      valueStrings[paramNum] = param.valueString;
    }

    final paramNums = params.map((p) => p.parameter.parameterNumber).toList()
      ..sort();
    final parameterPages = ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: [ParameterPage(name: 'Page 1', parameters: paramNums)],
    );

    return Slot(
      algorithm: params.first.algorithm,
      routing: RoutingInfo.filler(),
      pages: parameterPages,
      parameters: parameters,
      values: values,
      enums: enums,
      mappings: mappings,
      valueStrings: valueStrings,
    );
  }

  group('PerformanceScreen', () {
    testWidgets('displays empty state when no parameters assigned', (
      tester,
    ) async {
      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: [])),
      );

      expect(find.text('No performance parameters assigned'), findsOneWidget);
      expect(
        find.text('Assign parameters in the property editor'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.music_note_outlined), findsOneWidget);
    });

    testWidgets('displays mode toggle and parameter list', (tester) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 1',
          parameterNumber: 0,
        ),
        createMappedParameter(
          perfPageIndex: 2,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 2',
          parameterNumber: 1,
        ),
      ];

      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [createSlotFromMappedParameters(params)],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: [])),
      );
      await tester.pumpAndSettle();

      // Should show mode toggle
      expect(find.text('Condensed'), findsOneWidget);
      expect(find.text('As Indexed'), findsOneWidget);

      // Should show both parameters
      expect(find.text('Param 1'), findsAtLeast(1));
      expect(find.text('Param 2'), findsAtLeast(1));
    });

    testWidgets('shows hardware preview on wide screens', (tester) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 1',
          parameterNumber: 0,
        ),
      ];

      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [createSlotFromMappedParameters(params)],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: []), width: 800),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HardwarePreviewWidget), findsOneWidget);
    });

    testWidgets('hides hardware preview on narrow screens', (tester) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 1',
          parameterNumber: 0,
        ),
      ];

      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [createSlotFromMappedParameters(params)],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: []), width: 500),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HardwarePreviewWidget), findsNothing);
    });

    testWidgets('mode toggle switches between condensed and as-indexed', (
      tester,
    ) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 1',
          parameterNumber: 0,
        ),
      ];

      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [createSlotFromMappedParameters(params)],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: [])),
      );
      await tester.pumpAndSettle();

      // Starts in condensed mode - should have drag handles
      expect(find.byIcon(Icons.drag_handle), findsWidgets);

      // Switch to as-indexed mode
      await tester.tap(find.text('As Indexed'));
      await tester.pumpAndSettle();

      // Should show dropdown instead of drag handles
      expect(find.byType(DropdownButton<int>), findsWidgets);
    });

    testWidgets('displays polling controls', (tester) async {
      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.startPollingMappedParameters()).thenReturn(null);
      when(() => mockCubit.stopPollingMappedParameters()).thenReturn(null);

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: [])),
      );

      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_circle_fill));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
      verify(() => mockCubit.startPollingMappedParameters()).called(1);
    });

    testWidgets('shows remove button for each parameter', (tester) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Test Algo',
          algorithmIndex: 0,
          parameterName: 'Param 1',
          parameterNumber: 0,
        ),
      ];

      when(() => mockCubit.state).thenReturn(
        DistingStateSynchronized(
          disting: MockDistingMidiManager(),
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          slots: [createSlotFromMappedParameters(params)],
          algorithms: const [],
          unitStrings: const [],
          presetName: 'Test',
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.setPerformancePageMapping(any(), any(), any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
        createTestWidget(child: const PerformanceScreen(units: [])),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      verify(() => mockCubit.setPerformancePageMapping(0, 0, 0)).called(1);
    });
  });

  group('HardwarePreviewWidget', () {
    testWidgets('condensed mode groups parameters into pages of 3', (
      tester,
    ) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P1',
          parameterNumber: 0,
        ),
        createMappedParameter(
          perfPageIndex: 2,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P2',
          parameterNumber: 1,
        ),
        createMappedParameter(
          perfPageIndex: 3,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P3',
          parameterNumber: 2,
        ),
        createMappedParameter(
          perfPageIndex: 4,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P4',
          parameterNumber: 3,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardwarePreviewWidget(
              parameters: params,
              layoutMode: PerformanceLayoutMode.condensed,
            ),
          ),
        ),
      );

      // Should show 2 pages (3 + 1)
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);

      // All parameter names visible
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
      expect(find.text('P3'), findsOneWidget);
      expect(find.text('P4'), findsOneWidget);
    });

    testWidgets('as-indexed mode shows gaps for missing indices', (
      tester,
    ) async {
      final params = [
        createMappedParameter(
          perfPageIndex: 1,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P1',
          parameterNumber: 0,
        ),
        createMappedParameter(
          perfPageIndex: 4,
          algorithmName: 'Algo',
          algorithmIndex: 0,
          parameterName: 'P4',
          parameterNumber: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardwarePreviewWidget(
              parameters: params,
              layoutMode: PerformanceLayoutMode.asIndexed,
            ),
          ),
        ),
      );

      // Page 1 has P1 at index 1, gaps at 2 and 3
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('P1'), findsOneWidget);

      // Page 2 has P4 at index 4, gaps at 5 and 6
      // But page 2 should exist since index 4 is on page 2
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('P4'), findsOneWidget);

      // Empty slots shown as ---
      expect(find.text('---'), findsAtLeast(1));
    });

    testWidgets('shows empty state with no parameters', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HardwarePreviewWidget(
              parameters: const [],
              layoutMode: PerformanceLayoutMode.condensed,
            ),
          ),
        ),
      );

      expect(find.text('No parameters assigned'), findsOneWidget);
    });
  });
}
