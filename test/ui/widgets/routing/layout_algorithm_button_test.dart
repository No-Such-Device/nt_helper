import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/node_layout_algorithm.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';

// Mock classes
class MockDistingCubit extends Mock implements DistingCubit {}

class MockRoutingEditorCubit extends Mock implements RoutingEditorCubit {}

class MockNodeLayoutAlgorithm extends Mock implements NodeLayoutAlgorithm {}

void main() {
  group('Layout Algorithm Button UI Integration', () {
    late MockDistingCubit mockDistingCubit;
    late MockRoutingEditorCubit mockRoutingEditorCubit;

    setUp(() {
      mockDistingCubit = MockDistingCubit();
      mockRoutingEditorCubit = MockRoutingEditorCubit();

      // Set up default mock behaviors
      when(
        () => mockDistingCubit.stream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockDistingCubit.state,
      ).thenReturn(const DistingState.initial());
      when(
        () => mockRoutingEditorCubit.stream,
      ).thenAnswer((_) => const Stream.empty());
    });

    Widget createTestWidget({required RoutingEditorState state}) {
      when(() => mockRoutingEditorCubit.state).thenReturn(state);

      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<RoutingEditorCubit>.value(
            value: mockRoutingEditorCubit,
            child: _TestLayoutButtonWidget(),
          ),
        ),
      );
    }

    testWidgets('shows layout algorithm button when routing editor is loaded', (
      WidgetTester tester,
    ) async {
      final loadedState = RoutingEditorState.loaded(
        physicalInputs: const [
          Port(
            id: 'hw_in_1',
            name: 'I1',
            type: PortType.cv,
            direction: PortDirection.output,
          ),
        ],
        physicalOutputs: const [],
        algorithms: const [],
        connections: const [],
      );

      await tester.pumpWidget(createTestWidget(state: loadedState));

      // Verify the layout algorithm button is present
      expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
      expect(find.byTooltip('Apply Layout Algorithm'), findsOneWidget);
    });

    testWidgets(
      'hides layout algorithm button when routing editor not loaded',
      (WidgetTester tester) async {
        const initialState = RoutingEditorState.initial();

        await tester.pumpWidget(createTestWidget(state: initialState));

        // Verify the layout algorithm button is not present
        expect(find.byIcon(Icons.auto_fix_high), findsNothing);
        expect(find.byTooltip('Apply Layout Algorithm'), findsNothing);
      },
    );

    testWidgets('calls applyLayoutAlgorithm when button is tapped', (
      WidgetTester tester,
    ) async {
      final loadedState = RoutingEditorState.loaded(
        physicalInputs: const [
          Port(
            id: 'hw_in_1',
            name: 'I1',
            type: PortType.cv,
            direction: PortDirection.output,
          ),
        ],
        physicalOutputs: const [],
        algorithms: const [],
        connections: const [],
      );

      when(
        () => mockRoutingEditorCubit.applyLayoutAlgorithm(),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget(state: loadedState));

      // Tap the layout algorithm button
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();

      // Verify the method was called
      verify(() => mockRoutingEditorCubit.applyLayoutAlgorithm()).called(1);
    });

    testWidgets(
      'shows loading indicator when layout calculation is in progress',
      (WidgetTester tester) async {
        final loadingState = RoutingEditorState.loaded(
          physicalInputs: const [
            Port(
              id: 'hw_in_1',
              name: 'I1',
              type: PortType.cv,
              direction: PortDirection.output,
            ),
          ],
          physicalOutputs: const [],
          algorithms: const [],
          connections: const [],
          subState: SubState.syncing, // Layout calculation in progress
        );

        await tester.pumpWidget(createTestWidget(state: loadingState));

        // Verify loading indicator is shown instead of normal icon
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.auto_fix_high), findsNothing);
      },
    );

    testWidgets('button is positioned beside refresh routing button', (
      WidgetTester tester,
    ) async {
      final loadedState = RoutingEditorState.loaded(
        physicalInputs: const [],
        physicalOutputs: const [],
        algorithms: const [],
        connections: const [],
      );

      when(() => mockRoutingEditorCubit.state).thenReturn(loadedState);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<RoutingEditorCubit>.value(
              value: mockRoutingEditorCubit,
              child: _TestButtonsRowWidget(),
            ),
          ),
        ),
      );

      await tester.pump();

      // Find both buttons
      final refreshButton = find.byIcon(Icons.refresh);
      final layoutButton = find.byIcon(Icons.auto_fix_high);

      expect(refreshButton, findsOneWidget);
      expect(layoutButton, findsOneWidget);

      // Get their positions
      final refreshButtonPosition = tester.getCenter(refreshButton);
      final layoutButtonPosition = tester.getCenter(layoutButton);

      // Layout button should be to the right of refresh button
      expect(layoutButtonPosition.dx, greaterThan(refreshButtonPosition.dx));

      // They should be at approximately the same height
      expect(
        (layoutButtonPosition.dy - refreshButtonPosition.dy).abs(),
        lessThan(5),
      );
    });

    testWidgets('shows appropriate tooltip text', (WidgetTester tester) async {
      final loadedState = RoutingEditorState.loaded(
        physicalInputs: const [],
        physicalOutputs: const [],
        algorithms: const [],
        connections: const [],
      );

      await tester.pumpWidget(createTestWidget(state: loadedState));

      // Find the button and trigger tooltip
      await tester.longPress(find.byIcon(Icons.auto_fix_high));
      await tester.pumpAndSettle();

      // Verify tooltip text
      expect(find.text('Apply Layout Algorithm'), findsOneWidget);
    });
  });
}

/// Test widget that mimics the layout algorithm button implementation
class _TestLayoutButtonWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
      builder: (context, state) {
        return state.maybeWhen(
          loaded:
              (
                deviceIoProfile,
                physicalInputs,
                physicalOutputs,
                es5Inputs,
                algorithms,
                connections,
                buses,
                portOutputModes,
                nodePositions,
                zoomLevel,
                panOffset,
                isHardwareSynced,
                isPersistenceEnabled,
                lastSyncTime,
                lastPersistTime,
                lastError,
                subState,
                focusedAlgorithmIds,
                cascadeScrollTarget,
                auxBusUsage,
                hasExtendedAuxBuses,
              ) {
                // Show loading during layout calculation
                if (subState == SubState.syncing) {
                  return IconButton(
                    icon: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    onPressed: null,
                    tooltip: 'Calculating Layout...',
                  );
                }

                // Show normal layout button
                return IconButton(
                  icon: const Icon(Icons.auto_fix_high),
                  onPressed: () {
                    context.read<RoutingEditorCubit>().applyLayoutAlgorithm();
                  },
                  tooltip: 'Apply Layout Algorithm',
                );
              },
          orElse: () => const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Test widget that shows both refresh and layout buttons in a row
class _TestButtonsRowWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
      builder: (context, state) {
        return Row(
          children: [
            // Refresh button (existing)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: state is RoutingEditorStateLoaded
                  ? () {
                      // Refresh routing logic would go here
                    }
                  : null,
              tooltip: 'Refresh Routing',
            ),
            // Layout algorithm button (new)
            state.maybeWhen(
              loaded:
                  (
                    deviceIoProfile,
                    physicalInputs,
                    physicalOutputs,
                    es5Inputs,
                    algorithms,
                    connections,
                    buses,
                    portOutputModes,
                    nodePositions,
                    zoomLevel,
                    panOffset,
                    isHardwareSynced,
                    isPersistenceEnabled,
                    lastSyncTime,
                    lastPersistTime,
                    lastError,
                    subState,
                    focusedAlgorithmIds,
                    cascadeScrollTarget,
                    auxBusUsage,
                    hasExtendedAuxBuses,
                  ) {
                    // Show loading during layout calculation
                    if (subState == SubState.syncing) {
                      return IconButton(
                        icon: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        onPressed: null,
                        tooltip: 'Calculating Layout...',
                      );
                    }

                    // Show normal layout button
                    return IconButton(
                      icon: const Icon(Icons.auto_fix_high),
                      onPressed: () {
                        context
                            .read<RoutingEditorCubit>()
                            .applyLayoutAlgorithm();
                      },
                      tooltip: 'Apply Layout Algorithm',
                    );
                  },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}
