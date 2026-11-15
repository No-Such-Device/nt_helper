import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  group('SynchronizedScreen dirty indicator', () {
    late MockDistingCubit mockCubit;
    late MockDistingMidiManager mockMidiManager;
    late MockPlatformInteractionService mockPlatformService;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() {
      mockCubit = MockDistingCubit();
      mockMidiManager = MockDistingMidiManager();
      mockPlatformService = MockPlatformInteractionService();
      when(() => mockCubit.checkpoints).thenReturn([]);
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(false);
      McpServerService.initialize(distingCubit: mockCubit);
    });

    Widget buildScreen({required bool isDirty, String name = 'My Preset'}) {
      final state = DistingStateSynchronized(
        disting: mockMidiManager,
        distingVersion: '1.10.0',
        firmwareVersion: FirmwareVersion('1.10.0'),
        presetName: name,
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
        offline: true,
        isDirty: isDirty,
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
            presetName: name,
            isDirty: isDirty,
            screenshot: Uint8List(0),
            loading: false,
            platformService: mockPlatformService,
          ),
        ),
      );
    }

    testWidgets('clean state shows preset name without asterisk', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(isDirty: false));
      // The preset name should appear; no asterisk after it.
      expect(find.text('My Preset'), findsWidgets);
      expect(find.text('My Preset *'), findsNothing);
    });

    testWidgets('dirty state shows preset name followed by asterisk', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(isDirty: true));
      expect(find.text('My Preset *'), findsWidgets);
    });

    testWidgets('semantic label includes "unsaved changes" only when dirty', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen(isDirty: false));
      expect(
        find.bySemanticsLabel(RegExp(r'^Preset: My Preset$')),
        findsWidgets,
      );
      expect(find.bySemanticsLabel(RegExp('unsaved changes')), findsNothing);

      await tester.pumpWidget(buildScreen(isDirty: true));
      expect(find.bySemanticsLabel(RegExp('unsaved changes')), findsWidgets);
    });
  });
}
