import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/ui/widgets/routing/connection_painter.dart'
    as painter;
import 'package:nt_helper/ui/widgets/routing/interactive_connection_widget.dart';

@GenerateMocks([RoutingEditorCubit, PlatformInteractionService])
import 'interactive_connection_widget_test.mocks.dart';

void main() {
  provideDummy<RoutingEditorState>(const RoutingEditorState.initial());

  group('InteractiveConnectionWidget', () {
    late MockRoutingEditorCubit mockCubit;
    late MockPlatformInteractionService mockPlatformService;
    late Connection testConnection;

    setUp(() {
      mockCubit = MockRoutingEditorCubit();
      mockPlatformService = MockPlatformInteractionService();
      testConnection = const Connection(
        id: 'test-connection',
        sourcePortId: 'source-port',
        destinationPortId: 'dest-port',
        connectionType: ConnectionType.algorithmToAlgorithm,
      );
    });

    Widget createWidget({PlatformInteractionService? platformService}) {
      return MaterialApp(
        home: Scaffold(
          body: InteractiveConnectionWidget(
            connection: testConnection,
            routingEditorCubit: mockCubit,
            platformService: platformService ?? mockPlatformService,
            child: Container(
              width: 100,
              height: 50,
              color: Colors.blue,
              child: const Text('Connection'),
            ),
          ),
        ),
      );
    }

    group('Desktop platform behavior', () {
      setUp(() {
        when(mockPlatformService.supportsHoverInteractions()).thenReturn(true);
        when(mockPlatformService.shouldUseTouchInteractions())
            .thenReturn(false);
        when(mockPlatformService.getMinimumTouchTargetSize()).thenReturn(44.0);
      });

      testWidgets('wraps child with GestureDetector for desktop interaction', (
        tester,
      ) async {
        await tester.pumpWidget(createWidget());

        // Should have GestureDetector for tap detection
        expect(find.byType(GestureDetector), findsAtLeastNWidgets(1));
        expect(find.text('Connection'), findsOneWidget);
      });
    });

    group('Mobile platform behavior', () {
      setUp(() {
        when(mockPlatformService.supportsHoverInteractions()).thenReturn(false);
        when(mockPlatformService.shouldUseTouchInteractions()).thenReturn(true);
        when(mockPlatformService.getMinimumTouchTargetSize()).thenReturn(44.0);
      });

      testWidgets('shows confirmation dialog on tap', (tester) async {
        await tester.pumpWidget(createWidget());

        // Tap the widget
        await tester.tap(find.byType(InteractiveConnectionWidget));
        await tester.pumpAndSettle();

        // Should show confirmation dialog
        expect(find.text('Delete Connection'), findsOneWidget);
        expect(
          find.text('Are you sure you want to delete this connection?'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      });

      testWidgets('deletes connection when confirmed in dialog', (
        tester,
      ) async {
        when(mockCubit.deleteConnectionWithSmartBusLogic(any))
            .thenAnswer((_) async {});

        await tester.pumpWidget(createWidget());

        // Tap the widget to show dialog
        await tester.tap(find.byType(InteractiveConnectionWidget));
        await tester.pumpAndSettle();

        // Tap Delete in dialog
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        verify(mockCubit.deleteConnectionWithSmartBusLogic('test-connection'))
            .called(1);
      });

      testWidgets('does not delete when cancelled in dialog', (tester) async {
        await tester.pumpWidget(createWidget());

        // Tap the widget to show dialog
        await tester.tap(find.byType(InteractiveConnectionWidget));
        await tester.pumpAndSettle();

        // Tap Cancel in dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        verifyNever(mockCubit.deleteConnectionWithSmartBusLogic(any));
      });

      testWidgets('shows confirmation dialog on long press', (tester) async {
        await tester.pumpWidget(createWidget());

        // Long press the widget
        await tester.longPress(find.byType(InteractiveConnectionWidget));
        await tester.pumpAndSettle();

        // Should show confirmation dialog
        expect(find.text('Delete Connection'), findsOneWidget);
      });
    });

    group('Platform detection fallback', () {
      testWidgets('uses real PlatformInteractionService when none provided', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InteractiveConnectionWidget(
                connection: testConnection,
                routingEditorCubit: mockCubit,
                // No platformService provided - should use default
                child: const Text('Connection'),
              ),
            ),
          ),
        );

        // Widget should build successfully
        expect(find.text('Connection'), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('announces add and replace connection modes', (tester) async {
        when(mockPlatformService.supportsHoverInteractions()).thenReturn(false);
        when(mockCubit.state).thenReturn(const RoutingEditorState.initial());

        Future<void> pumpMode(OutputMode mode) async {
          final connection = testConnection.copyWith(busLabel: 'A1');
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: InteractiveConnectionWidget(
                  connection: connection,
                  routingEditorCubit: mockCubit,
                  platformService: mockPlatformService,
                  size: const Size(200, 100),
                  connectionData: painter.ConnectionData(
                    connection: connection,
                    sourcePosition: Offset.zero,
                    destinationPosition: const Offset(100, 0),
                    busLabel: 'A1',
                    outputMode: mode,
                  ),
                ),
              ),
            ),
          );
        }

        await pumpMode(OutputMode.add);
        expect(
          find.bySemanticsLabel(
            'Connection from source-port to dest-port, on bus A1, Add mode',
          ),
          findsOneWidget,
        );

        await pumpMode(OutputMode.replace);
        expect(
          find.bySemanticsLabel(
            'Connection from source-port to dest-port, on bus A1, Replace mode',
          ),
          findsOneWidget,
        );
      });
    });
  });
}
