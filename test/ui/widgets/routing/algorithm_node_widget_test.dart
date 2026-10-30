import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/widgets/routing/algorithm_node_widget.dart';
import 'package:nt_helper/ui/widgets/routing/port_widget.dart';

class MockDistingCubit extends Mock implements DistingCubit {
  @override
  Stream<DistingState> get stream => const Stream.empty();
}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockMidiListenerCubit extends Mock implements MidiListenerCubit {}

/// Helper to build an [AlgorithmNodeWidget] wrapped in the required providers.
Widget _buildTestWidget({
  required MockDistingCubit cubit,
  String algorithmName = 'Test Algorithm',
  int slotNumber = 1,
  List<String> inputLabels = const [],
  List<String> outputLabels = const [],
  List<String>? inputPortIds,
  List<String>? outputPortIds,
  List<int>? outputChannelNumbers,
  Set<String>? connectedPorts,
  Map<int, bool>? es5ChannelToggles,
  Map<int, int>? es5ExpanderParameterNumbers,
}) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<DistingCubit>.value(
        value: cubit,
        child: AlgorithmNodeWidget(
          algorithmName: algorithmName,
          slotNumber: slotNumber,
          position: const Offset(100, 100),
          inputLabels: inputLabels,
          outputLabels: outputLabels,
          inputPortIds: inputPortIds,
          outputPortIds: outputPortIds,
          outputChannelNumbers: outputChannelNumbers,
          connectedPorts: connectedPorts,
          es5ChannelToggles: es5ChannelToggles,
          es5ExpanderParameterNumbers: es5ExpanderParameterNumbers,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // Register fallback value for PackedMappingData used with any() matcher
    registerFallbackValue(PackedMappingData.filler());
  });

  group('AlgorithmNodeWidget port hit testing', () {
    for (final isInput in [true, false]) {
      for (final area in ['top padding', 'bottom padding', 'label gap']) {
        testWidgets(
          '${isInput ? 'input' : 'output'} $area starts a cable drag, not a node drag',
          (tester) async {
            final cubit = MockDistingCubit();
            when(() => cubit.state).thenReturn(DistingStateInitial());
            final cableStarts = <String>[];
            final cableUpdates = <String>[];
            final cableEnds = <String>[];
            final nodePositions = <Offset>[];
            var nodeStarts = 0;

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: BlocProvider<DistingCubit>.value(
                    value: cubit,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: AlgorithmNodeWidget(
                        algorithmName: 'Test Algorithm',
                        slotNumber: 1,
                        position: const Offset(100, 100),
                        inputLabels: isInput ? ['Input'] : [],
                        inputPortIds: isInput ? ['port'] : [],
                        outputLabels: isInput ? [] : ['Output'],
                        outputPortIds: isInput ? [] : ['port'],
                        onDragStart: () => nodeStarts++,
                        onPositionChanged: nodePositions.add,
                        onPortDragStart: cableStarts.add,
                        onPortDragUpdate: (id, _) => cableUpdates.add(id),
                        onPortDragEnd: (id, _) => cableEnds.add(id),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final port = find.byType(PortWidget);
            final portRect = tester.getRect(port);
            final nodeRect = tester.getRect(find.byType(AlgorithmNodeWidget));
            final dotRect = tester.getRect(
              find.descendant(of: port, matching: find.byType(Container)),
            );
            final start = switch (area) {
              'top padding' => Offset(dotRect.center.dx, portRect.top + 1),
              'bottom padding' => Offset(
                dotRect.center.dx,
                portRect.bottom - 1,
              ),
              _ => Offset(
                isInput ? dotRect.right + 2 : dotRect.left - 2,
                dotRect.center.dy,
              ),
            };
            expect(portRect.contains(start), isTrue);
            expect(dotRect.contains(start), isFalse);

            // A touch beginning inside the port's existing row must not fall
            // through to the surrounding node's pan recognizer.
            await tester.dragFrom(start, const Offset(60, 40));
            await tester.pumpAndSettle();

            expect(cableStarts, ['port']);
            expect(cableUpdates, isNotEmpty);
            expect(cableUpdates.every((id) => id == 'port'), isTrue);
            expect(cableEnds, ['port']);
            expect(nodeStarts, 0);
            expect(nodePositions, isEmpty);
            expect(tester.getRect(port), portRect);
            expect(tester.getRect(find.byType(AlgorithmNodeWidget)), nodeRect);

            // The fix must not disable intentional node movement elsewhere.
            await tester.dragFrom(
              tester.getCenter(find.text('#1 Test Algorithm')),
              const Offset(60, 40),
            );
            await tester.pumpAndSettle();
            expect(nodeStarts, 1);
            expect(nodePositions, isNotEmpty);
            expect(cableStarts, ['port']);
          },
        );
      }
    }
  });

  group('AlgorithmNodeWidget Mapping Tests', () {
    late MockDistingCubit mockCubit;
    late MockDistingMidiManager mockManager;

    setUp(() {
      mockCubit = MockDistingCubit();
      mockManager = MockDistingMidiManager();
    });

    testWidgets('should show mapping icon when slot has mapped parameters', (
      tester,
    ) async {
      // Create a mapped parameter data (not filler = mapped)
      final mappedData = PackedMappingData(
        source: 1,
        cvInput: 0,
        isUnipolar: true,
        isGate: false,
        volts: 5,
        delta: 1,
        midiChannel: 1,
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
        i2cMax: 127,
        perfPageIndex: 0,
        version: 1,
      );

      // Create a slot with a mapped parameter
      final mappedSlot = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'test',
          name: 'Test Algorithm',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            min: 0,
            max: 100,
            defaultValue: 50,
            unit: 0,
            name: 'Test Param',
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
        ],
        enums: [
          ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 0,
            values: const [],
          ),
        ],
        mappings: [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: mappedData,
          ),
        ],
        valueStrings: [
          ParameterValueString(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: '50',
          ),
        ],
      );

      final state = DistingStateSynchronized(
        disting: mockManager,
        distingVersion: 'v1.0',
        firmwareVersion: FirmwareVersion('1.0.0'),
        presetName: 'Test Preset',
        algorithms: [],
        slots: [mappedSlot],
        unitStrings: const [],
      );

      when(() => mockCubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<DistingCubit>.value(
              value: mockCubit,
              child: AlgorithmNodeWidget(
                algorithmName: 'Test Algorithm',
                slotNumber: 1,
                position: const Offset(100, 100),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the mapping icon in the title bar
      final mappingIcon = find.descendant(
        of: find.byType(AlgorithmNodeWidget),
        matching: find.byIcon(Icons.map_sharp),
      );

      expect(mappingIcon, findsOneWidget);

      // Verify the icon is inside a container with the correct background color
      final container = tester.widget<Container>(
        find.ancestor(of: mappingIcon, matching: find.byType(Container)).first,
      );
      expect(container.decoration, isNotNull);
    });

    testWidgets(
      'should show mapped parameter menu items when slot has mappings',
      (tester) async {
        // Create multiple mapped parameters
        final mappedData1 = PackedMappingData(
          source: 1,
          cvInput: 0,
          isUnipolar: true,
          isGate: false,
          volts: 5,
          delta: 1,
          midiChannel: 1,
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
          i2cMax: 127,
          perfPageIndex: 0,
          version: 1,
        );

        final mappedData2 = PackedMappingData(
          source: 2,
          cvInput: 1,
          isUnipolar: false,
          isGate: false,
          volts: 10,
          delta: 2,
          midiChannel: 2,
          midiMappingType: MidiMappingType.cc,
          midiCC: 2,
          isMidiEnabled: true,
          isMidiSymmetric: false,
          isMidiRelative: false,
          midiMin: 0,
          midiMax: 127,
          i2cCC: 0,
          isI2cEnabled: false,
          isI2cSymmetric: false,
          i2cMin: 0,
          i2cMax: 127,
          perfPageIndex: 0,
          version: 1,
        );

        // Create a slot with mapped parameters
        final mappedSlot = Slot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'test',
            name: 'Test Algorithm',
          ),
          routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
          pages: ParameterPages(algorithmIndex: 0, pages: const []),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              min: 0,
              max: 100,
              defaultValue: 50,
              unit: 0,
              name: 'Frequency',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 1,
              min: 0,
              max: 100,
              defaultValue: 75,
              unit: 0,
              name: 'Resonance',
              powerOfTen: 0,
            ),
          ],
          values: [
            ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
            ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 75),
          ],
          enums: [
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: 0,
              values: const [],
            ),
            ParameterEnumStrings(
              algorithmIndex: 0,
              parameterNumber: 1,
              values: const [],
            ),
          ],
          mappings: [
            Mapping(
              algorithmIndex: 0,
              parameterNumber: 0,
              packedMappingData: mappedData1,
            ),
            Mapping(
              algorithmIndex: 0,
              parameterNumber: 1,
              packedMappingData: mappedData2,
            ),
          ],
          valueStrings: [
            ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: '50',
            ),
            ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: 1,
              value: '75',
            ),
          ],
        );

        final state = DistingStateSynchronized(
          disting: mockManager,
          distingVersion: 'v1.0',
          firmwareVersion: FirmwareVersion('1.0.0'),
          presetName: 'Test Preset',
          algorithms: [],
          slots: [mappedSlot],
          unitStrings: const [],
        );

        when(() => mockCubit.state).thenReturn(state);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<DistingCubit>.value(
                value: mockCubit,
                child: AlgorithmNodeWidget(
                  algorithmName: 'Test Algorithm',
                  slotNumber: 1,
                  position: const Offset(100, 100),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap the popup menu button
        final popupMenuButton = find.byIcon(Icons.more_vert);
        await tester.tap(popupMenuButton);
        await tester.pumpAndSettle();

        // Verify mapped parameter items are present
        expect(find.text('Frequency'), findsOneWidget);
        expect(find.text('Resonance'), findsOneWidget);

        // Verify mapping icons are present for each mapped parameter
        final mappingIcons = find.byIcon(Icons.map_sharp);
        expect(
          mappingIcons,
          findsAtLeast(2),
        ); // At least 2 in menu items (plus title bar icon)

        // Verify dividers are present (one after mapped params, one before delete)
        expect(find.byType(PopupMenuDivider), findsNWidgets(2));

        // Verify delete item is still present at the bottom
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets('should not show mapping icon when no parameters are mapped', (
      tester,
    ) async {
      // Create a slot with no mapped parameters
      final unmappedSlot = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'test',
          name: 'Test Algorithm',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
        pages: ParameterPages(algorithmIndex: 0, pages: const []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            min: 0,
            max: 100,
            defaultValue: 50,
            unit: 0,
            name: 'Test Param',
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
        ],
        enums: [
          ParameterEnumStrings(
            algorithmIndex: 0,
            parameterNumber: 0,
            values: const [],
          ),
        ],
        mappings: [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData:
                PackedMappingData.filler(), // Filler = not mapped
          ),
        ],
        valueStrings: [
          ParameterValueString(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: '50',
          ),
        ],
      );

      final state = DistingStateSynchronized(
        disting: mockManager,
        distingVersion: 'v1.0',
        firmwareVersion: FirmwareVersion('1.0.0'),
        presetName: 'Test Preset',
        algorithms: [],
        slots: [unmappedSlot],
        unitStrings: const [],
      );

      when(() => mockCubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<DistingCubit>.value(
              value: mockCubit,
              child: AlgorithmNodeWidget(
                algorithmName: 'Test Algorithm',
                slotNumber: 1,
                position: const Offset(100, 100),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the mapping icon in the title bar
      final mappingIcon = find.descendant(
        of: find.byType(AlgorithmNodeWidget),
        matching: find.byIcon(Icons.map_sharp),
      );

      expect(mappingIcon, findsNothing); // Should not find mapping icon
    });
  });

  group('AlgorithmNodeWidget Collapse Toggle Tests', () {
    late MockDistingCubit mockCubit;

    setUp(() {
      mockCubit = MockDistingCubit();

      // Default: no mappings (DistingStateInitial has no slots)
      when(() => mockCubit.state).thenReturn(DistingStateInitial());
    });

    testWidgets('toggle not shown when <= 5 unconnected ports', (tester) async {
      // 3 inputs + 2 outputs = 5 unconnected — threshold is >5
      await tester.pumpWidget(
        _buildTestWidget(
          cubit: mockCubit,
          inputLabels: ['In 1', 'In 2', 'In 3'],
          outputLabels: ['Out 1', 'Out 2'],
          inputPortIds: ['i1', 'i2', 'i3'],
          outputPortIds: ['o1', 'o2'],
          connectedPorts: {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.unfold_less), findsNothing);
      expect(find.byIcon(Icons.unfold_more), findsNothing);
    });

    testWidgets('toggle shown when > 5 unconnected ports', (tester) async {
      // 4 inputs + 4 outputs = 8 total, 1 connected → 7 unconnected
      await tester.pumpWidget(
        _buildTestWidget(
          cubit: mockCubit,
          inputLabels: ['In 1', 'In 2', 'In 3', 'In 4'],
          outputLabels: ['Out 1', 'Out 2', 'Out 3', 'Out 4'],
          inputPortIds: ['i1', 'i2', 'i3', 'i4'],
          outputPortIds: ['o1', 'o2', 'o3', 'o4'],
          connectedPorts: {'i1'},
        ),
      );
      await tester.pumpAndSettle();

      // Should show the unfold_less icon (collapse affordance)
      expect(find.byIcon(Icons.unfold_less), findsOneWidget);
    });

    testWidgets(
      'tapping toggle hides unconnected ports and shows hidden count',
      (tester) async {
        // 4 inputs + 4 outputs, 2 connected → 6 unconnected
        await tester.pumpWidget(
          _buildTestWidget(
            cubit: mockCubit,
            inputLabels: ['In 1', 'In 2', 'In 3', 'In 4'],
            outputLabels: ['Out 1', 'Out 2', 'Out 3', 'Out 4'],
            inputPortIds: ['i1', 'i2', 'i3', 'i4'],
            outputPortIds: ['o1', 'o2', 'o3', 'o4'],
            connectedPorts: {'i1', 'o2'},
          ),
        );
        await tester.pumpAndSettle();

        // All 8 ports visible before collapse
        expect(find.byType(PortWidget), findsNWidgets(8));

        // Tap the collapse toggle
        await tester.tap(find.byIcon(Icons.unfold_less));
        await tester.pumpAndSettle();

        // Only 2 connected ports visible
        expect(find.byType(PortWidget), findsNWidgets(2));

        // Should now show unfold_more icon and the hidden count
        expect(find.byIcon(Icons.unfold_more), findsOneWidget);
        expect(find.text('+6 hidden'), findsOneWidget);
      },
    );

    testWidgets('tapping toggle again restores all ports', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          cubit: mockCubit,
          inputLabels: ['In 1', 'In 2', 'In 3', 'In 4'],
          outputLabels: ['Out 1', 'Out 2', 'Out 3', 'Out 4'],
          inputPortIds: ['i1', 'i2', 'i3', 'i4'],
          outputPortIds: ['o1', 'o2', 'o3', 'o4'],
          connectedPorts: {'i1', 'o2'},
        ),
      );
      await tester.pumpAndSettle();

      // Collapse
      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.pumpAndSettle();
      expect(find.byType(PortWidget), findsNWidgets(2));

      // Expand
      await tester.tap(find.byIcon(Icons.unfold_more));
      await tester.pumpAndSettle();

      // All 8 ports visible again
      expect(find.byType(PortWidget), findsNWidgets(8));
      expect(find.byIcon(Icons.unfold_less), findsOneWidget);
      expect(find.text('+6 hidden'), findsNothing);
    });

    testWidgets(
      'ES-5 channel numbers stay aligned with correct outputs after collapse',
      (tester) async {
        // 1 input + 6 outputs with ES-5 toggles on channels 1-6
        // Only output 'o3' (channel 3) is connected → 6 unconnected > 5 threshold
        await tester.pumpWidget(
          _buildTestWidget(
            cubit: mockCubit,
            inputLabels: ['Clock'],
            inputPortIds: ['clk'],
            outputLabels: ['Ch 1', 'Ch 2', 'Ch 3', 'Ch 4', 'Ch 5', 'Ch 6'],
            outputPortIds: ['o1', 'o2', 'o3', 'o4', 'o5', 'o6'],
            outputChannelNumbers: [1, 2, 3, 4, 5, 6],
            connectedPorts: {'o3'},
            es5ChannelToggles: {
              1: false,
              2: false,
              3: true,
              4: false,
              5: false,
              6: false,
            },
            es5ExpanderParameterNumbers: {
              1: 10,
              2: 11,
              3: 12,
              4: 13,
              5: 14,
              6: 15,
            },
          ),
        );
        await tester.pumpAndSettle();

        // All 7 ports visible (1 input + 6 outputs)
        expect(find.byType(PortWidget), findsNWidgets(7));

        // Collapse — only 'o3' (Ch 3) should remain
        await tester.tap(find.byIcon(Icons.unfold_less));
        await tester.pumpAndSettle();

        expect(find.byType(PortWidget), findsNWidgets(1));
        // The visible port should be 'Ch 3'
        expect(find.text('Ch 3'), findsOneWidget);
        // The ES-5 toggle icon should still be present for the connected channel
        expect(find.byIcon(Icons.output), findsOneWidget);
      },
    );
  });
}
