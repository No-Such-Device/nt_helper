import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/add_algorithm_screen.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/shortcut_help_overlay.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  late MockDistingCubit mockCubit;
  late MockDistingMidiManager mockMidiManager;
  late MockPlatformInteractionService mockPlatformService;
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() async {
    await database.close();
  });

  setUp(() {
    mockCubit = MockDistingCubit();
    mockMidiManager = MockDistingMidiManager();
    mockPlatformService = MockPlatformInteractionService();
    when(() => mockCubit.checkpoints).thenReturn([]);
    McpServerService.initialize(distingCubit: mockCubit);
  });

  Widget createTestWidget() {
    when(() => mockPlatformService.isMobilePlatform()).thenReturn(false);

    final state = DistingStateSynchronized(
      disting: mockMidiManager,
      distingVersion: '1.10.0',
      firmwareVersion: FirmwareVersion('1.10.0'),
      presetName: 'Test Preset',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
      offline: false,
    );

    when(() => mockCubit.state).thenReturn(state);
    when(() => mockCubit.stream).thenAnswer((_) => Stream.value(state));

    return MaterialApp(
      home: BlocProvider<DistingCubit>.value(
        value: mockCubit,
        child: SynchronizedScreen(
          distingVersion: '1.10.0',
          firmwareVersion: FirmwareVersion('1.10.0'),
          slots: const [],
          algorithms: const [],
          units: const [],
          presetName: 'Test Preset',
          screenshot: Uint8List(0),
          loading: false,
          platformService: mockPlatformService,
        ),
      ),
    );
  }

  group('Shortcut re-entrancy guards', () {
    testWidgets('Cmd+/ does not open multiple shortcut help dialogs', (
      tester,
    ) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Press Cmd+/ twice rapidly
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      // Should find exactly one ShortcutHelpOverlay dialog
      expect(find.byType(ShortcutHelpOverlay), findsOneWidget);
      expect(
        find.text('${Platform.isMacOS ? 'Cmd' : 'Ctrl'}+T'),
        findsOneWidget,
      );
    }, tags: ['regression']);

    testWidgets(
      'Cmd+/ can reopen shortcut help after previous dialog is dismissed',
      (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Open the help dialog
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pumpAndSettle();

        expect(find.byType(ShortcutHelpOverlay), findsOneWidget);

        // Dismiss the dialog by tapping the close button inside it
        await tester.tap(
          find.descendant(
            of: find.byType(ShortcutHelpOverlay),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(ShortcutHelpOverlay), findsNothing);

        // Open it again - should work
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.slash);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pumpAndSettle();

        expect(find.byType(ShortcutHelpOverlay), findsOneWidget);
      },
    tags: ['regression']);

    testWidgets('add FAB stays disabled until verification completes', (
      tester,
    ) async {
      final verification = Completer<void>();
      final algorithm = AlgorithmInfo(
        algorithmIndex: 0,
        name: 'Test Algorithm',
        guid: 'test',
        specifications: const [],
      );
      when(
        () => mockCubit.onAlgorithmSelected(
          algorithm,
          const <int>[],
          addBypassed: false,
        ),
      ).thenAnswer((_) => verification.future);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byType(AddAlgorithmScreen))).pop({
        'algorithm': algorithm,
        'specValues': const <int>[],
        'addBypassed': false,
      });
      await tester.pump();

      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      verify(
        () => mockCubit.onAlgorithmSelected(
          algorithm,
          const <int>[],
          addBypassed: false,
        ),
      ).called(1);

      verification.complete();
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
    });
  });
}
