import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  group('ParameterViewRow Tooltip Removal', () {
    late MockDistingCubit mockCubit;

    setUp(() {
      mockCubit = MockDistingCubit();
      when(() => mockCubit.scheduleParameterRefresh(any())).thenReturn(null);
      when(() => mockCubit.disting()).thenReturn(null);
      when(
        () => mockCubit.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      ).thenAnswer((_) async {});
    });

    Widget createTestWidget({
      required bool isDisabled,
      String parameterName = 'Test Parameter',
    }) {
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: Scaffold(
            body: ParameterViewRow(
              name: parameterName,
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
                    name: parameterName,
                    unit: 0,
                    min: 0,
                    max: 100,
                    defaultValue: 50,
                    powerOfTen: 0,
                  ),
                ],
                values: [
                  ParameterValue(
                    algorithmIndex: 0,
                    parameterNumber: 0,
                    value: 50,
                    isDisabled: isDisabled,
                  ),
                ],
                enums: [ParameterEnumStrings.filler()],
                mappings: [Mapping.filler()],
                valueStrings: [ParameterValueString.filler()],
              ),
              isDisabled: isDisabled,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'disabled parameter does not show disabled explanation tooltip',
      (WidgetTester tester) async {
        await tester.pumpWidget(createTestWidget(isDisabled: true));

        // Search for Tooltip with disabled message - should not exist
        // Note: MappingEditButton has its own tooltip which is unrelated
        final disabledTooltipFinder = find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message ==
                  'This parameter is disabled by the current configuration',
        );
        expect(disabledTooltipFinder, findsNothing);
      },
    );

    testWidgets('disabled parameter maintains 0.5 opacity appearance', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget(isDisabled: true));

      // Find the Opacity widget that wraps the row content
      expect(find.byType(Opacity), findsWidgets);

      // Get the Opacity widget and verify it has 0.5 opacity
      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsWidgets);

      // Verify one of the Opacity widgets has 0.5 opacity
      bool foundCorrectOpacity = false;
      for (var element in opacityFinder.evaluate()) {
        final widget = element.widget as Opacity;
        if (widget.opacity == 0.5) {
          foundCorrectOpacity = true;
          break;
        }
      }
      expect(
        foundCorrectOpacity,
        isTrue,
        reason: 'Should have Opacity widget with 0.5 opacity',
      );
    });

    testWidgets('disabled parameter has IgnorePointer set to true', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createTestWidget(isDisabled: true));

      // Find IgnorePointer widgets
      final ignorePointerFinder = find.byType(IgnorePointer);
      expect(ignorePointerFinder, findsWidgets);

      // Verify one IgnorePointer widget has ignoring=true
      bool foundCorrectIgnorePointer = false;
      for (var element in ignorePointerFinder.evaluate()) {
        final widget = element.widget as IgnorePointer;
        if (widget.ignoring == true) {
          foundCorrectIgnorePointer = true;
          break;
        }
      }
      expect(
        foundCorrectIgnorePointer,
        isTrue,
        reason: 'Should have IgnorePointer widget with ignoring=true',
      );
    });

    testWidgets('parameter name is displayed correctly when disabled', (
      WidgetTester tester,
    ) async {
      const testName = 'Frequency Parameter';
      await tester.pumpWidget(
        createTestWidget(isDisabled: true, parameterName: testName),
      );

      // Verify parameter name is still displayed
      expect(find.text(testName), findsWidgets);
    });
  });
}
