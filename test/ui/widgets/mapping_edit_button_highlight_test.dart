import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/widgets/mapping_edit_button.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';

class MockDistingCubit extends Mock implements DistingCubit {
  @override
  Stream<DistingState> get stream => const Stream.empty();
}

class MockMidiListenerCubit extends Mock implements MidiListenerCubit {
  @override
  Stream<MidiListenerState> get stream => const Stream.empty();
}

void main() {
  late MockDistingCubit mockDistingCubit;
  late MockMidiListenerCubit mockMidiListenerCubit;

  setUp(() {
    mockDistingCubit = MockDistingCubit();
    mockMidiListenerCubit = MockMidiListenerCubit();

    when(() => mockDistingCubit.state).thenReturn(const DistingStateInitial());
    when(
      () => mockDistingCubit.scheduleParameterRefresh(any()),
    ).thenReturn(null);
    when(() => mockDistingCubit.disting()).thenReturn(null);
  });

  ParameterViewRow createParameterViewRow() {
    return ParameterViewRow(
      name: 'Test Parameter',
      min: 0,
      max: 100,
      defaultValue: 50,
      parameterNumber: 0,
      algorithmIndex: 0,
      initialValue: 50,
      slot: Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'test-guid',
          name: 'Test',
        ),
        routing: RoutingInfo.filler(),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
        parameters: [
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 0,
            name: 'Test Parameter',
            unit: 0,
            min: 0,
            max: 100,
            defaultValue: 50,
            powerOfTen: 0,
          ),
        ],
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 50),
        ],
        enums: [ParameterEnumStrings.filler()],
        mappings: [Mapping.filler()],
        valueStrings: [ParameterValueString.filler()],
      ),
    );
  }

  Widget createTestWidget() {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ).copyWith(tertiary: Colors.orange),
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<DistingCubit>.value(value: mockDistingCubit),
          BlocProvider<MidiListenerCubit>.value(value: mockMidiListenerCubit),
        ],
        child: Scaffold(
          body: MappingEditButton(parameterViewRow: createParameterViewRow()),
        ),
      ),
    );
  }

  BoxDecoration? findHighlightDecoration(WidgetTester tester) {
    final containerFinder = find.descendant(
      of: find.byType(MappingEditButton),
      matching: find.byType(Container),
    );
    expect(containerFinder, findsWidgets);

    for (final element in containerFinder.evaluate()) {
      final container = element.widget as Container;
      if (container.decoration is BoxDecoration) {
        return container.decoration as BoxDecoration;
      }
    }
    return null;
  }

  group('MappingEditButton highlight', () {
    testWidgets('has no highlight border by default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      final decoration = findHighlightDecoration(tester);
      expect(decoration, isNotNull);
      expect(decoration!.border, isNotNull);
      final border = decoration.border! as Border;
      expect(border.top.color, Colors.transparent);
      expect(border.top.width, 2.0);
    });

    testWidgets('shows orange border when bottom sheet is open', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      // Tap the mapping icon button to open the bottom sheet
      await tester.tap(find.byType(IconButton));
      // Pump one frame to process the setState(_isEditing = true)
      await tester.pump();

      final decoration = findHighlightDecoration(tester);
      expect(decoration, isNotNull);
      expect(decoration!.border, isNotNull);

      final border = decoration.border! as Border;
      expect(border.top.color, Colors.orange);
      expect(border.top.width, 2.0);
    });

    testWidgets('highlight clears when bottom sheet is dismissed', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      // Tap the mapping icon button to open the bottom sheet
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      // Verify border is present
      var decoration = findHighlightDecoration(tester);
      expect(decoration?.border, isNotNull);

      // Dismiss the bottom sheet by popping the route
      final navigatorState = tester.state<NavigatorState>(
        find.byType(Navigator),
      );
      navigatorState.pop();
      await tester.pumpAndSettle();

      // Verify border is transparent
      decoration = findHighlightDecoration(tester);
      expect(decoration, isNotNull);
      expect(decoration!.border, isNotNull);
      final clearedBorder = decoration.border! as Border;
      expect(clearedBorder.top.color, Colors.transparent);
      expect(clearedBorder.top.width, 2.0);
    });

    testWidgets('layout size is stable across highlight states', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget());

      final sizeBefore = tester.getSize(find.byType(MappingEditButton));

      // Tap to open bottom sheet (triggers _isEditing = true)
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      final sizeAfter = tester.getSize(find.byType(MappingEditButton));

      expect(sizeAfter, sizeBefore);
    }, tags: ['regression']);
  });
}
