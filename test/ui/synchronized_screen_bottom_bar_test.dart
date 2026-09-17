import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/cpu_monitor_widget.dart';
import 'package:nt_helper/ui/poly_multisample/poly_samples_screen.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/template_manager/template_manager_screen.dart';
import 'package:nt_helper/ui/widgets/memory_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockPresetsDao extends Mock implements PresetsDao {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

const _memoryFixture = MemoryUsage(
  sram: MemoryPoolUsage(total: 64 * 1024, current: 16 * 1024),
  dram: MemoryPoolUsage(total: 8 * 1024 * 1024, current: 2 * 1024 * 1024),
  dtc: MemoryPoolUsage(total: 4 * 1024, current: 1024),
  itc: MemoryPoolUsage(total: 512, current: 128),
);

void main() {
  group('SynchronizedScreen Bottom Bar Platform Detection Tests', () {
    late MockDistingCubit mockCubit;
    late MockDistingMidiManager mockMidiManager;
    late MockPlatformInteractionService mockPlatformService;
    late MockAppDatabase mockDatabase;
    late MockMetadataDao mockMetadataDao;
    late MockPresetsDao mockPresetsDao;

    setUpAll(() {
      // Initialize MCP server service for tests to avoid initialization error
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({'show_debug_panel': false});
      await SettingsService().init();
      mockCubit = MockDistingCubit();
      mockMidiManager = MockDistingMidiManager();
      mockPlatformService = MockPlatformInteractionService();
      mockDatabase = MockAppDatabase();
      mockMetadataDao = MockMetadataDao();
      mockPresetsDao = MockPresetsDao();
      when(() => mockCubit.checkpoints).thenReturn([]);
      when(
        () => mockCubit.cpuUsageStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.resumeCpuMonitoring()).thenReturn(null);
      when(() => mockCubit.pauseCpuMonitoring()).thenReturn(null);
      when(
        () => mockCubit.displayMemoryState,
      ).thenReturn(const MemoryDisplayState.available(_memoryFixture));
      when(
        () => mockCubit.displayMemoryStateStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.refreshDisplayMemory()).thenAnswer((_) async {});
      when(() => mockCubit.supportsMemoryUsage).thenReturn(false);
      when(() => mockCubit.database).thenReturn(mockDatabase);
      when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
      when(() => mockDatabase.presetsDao).thenReturn(mockPresetsDao);
      when(() => mockPresetsDao.getTemplates()).thenAnswer((_) async => []);

      // Initialize McpServerService with mock cubit
      McpServerService.initialize(distingCubit: mockCubit);
    });

    Widget createTestWidget({
      required bool isMobile,
      required bool isOffline,
      String firmware = '1.10.0',
      bool? supportsMemoryUsage,
    }) {
      // Mock platform service response
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(isMobile);

      // Mock cubit state
      final firmwareVersion = FirmwareVersion(firmware);
      final state = DistingStateSynchronized(
        disting: mockMidiManager,
        distingVersion: firmware,
        firmwareVersion: firmwareVersion,
        presetName: 'Test Preset',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
        offline: isOffline,
      );

      when(() => mockCubit.state).thenReturn(state);
      when(() => mockCubit.stream).thenAnswer((_) => Stream.value(state));
      when(() => mockCubit.supportsMemoryUsage).thenReturn(
        supportsMemoryUsage ?? (!isOffline && firmwareVersion.hasMemoryUsage),
      );

      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: SynchronizedScreen(
            distingVersion: firmware,
            firmwareVersion: firmwareVersion,
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

    testWidgets('uses a geometry-independent bottom bar alongside the FAB', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      expect(
        find.byKey(const ValueKey('main-bottom-action-bar')),
        findsOneWidget,
      );
      expect(find.byType(BottomAppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('Display mode buttons are not in bottom bar when online', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      // Display mode buttons moved to video overlay — not in bottom bar
      expect(find.byTooltip('Parameter View'), findsNothing);
      expect(find.byTooltip('Algorithm UI'), findsNothing);
      expect(find.byTooltip('Overview UI'), findsNothing);
      expect(find.byTooltip('Overview VU Meters'), findsNothing);
      expect(find.byTooltip('View Options'), findsNothing);

      // Quick-action buttons should still be present
      expect(find.byTooltip('File Browser'), findsOneWidget);
      expect(find.byTooltip('Template Manager'), findsOneWidget);
      expect(find.byTooltip('Perform'), findsOneWidget);
      expect(find.byTooltip('Plugin Manager'), findsOneWidget);
    });

    testWidgets(
      'Offline mode does not show "Offline Data" button in bottom bar on desktop',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(isMobile: false, isOffline: true),
        );

        // Offline data button moved to overflow menu only
        expect(find.byTooltip('Offline Data'), findsNothing);

        // Verify desktop display mode buttons are NOT present
        expect(find.byTooltip('Parameter View'), findsNothing);
        expect(find.byTooltip('Algorithm UI'), findsNothing);
        expect(find.byTooltip('Overview UI'), findsNothing);
        expect(find.byTooltip('Overview VU Meters'), findsNothing);

        // Verify mobile button is NOT present
        expect(find.byTooltip('View Options'), findsNothing);
      },
    );

    testWidgets(
      'Offline mode does not show "Offline Data" button in bottom bar on mobile',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(isMobile: true, isOffline: true),
        );

        // Offline data button moved to overflow menu only
        expect(find.byTooltip('Offline Data'), findsNothing);

        // Verify mobile "View Options" button is NOT present
        expect(find.byTooltip('View Options'), findsNothing);

        // Verify desktop display mode buttons are NOT present
        expect(find.byTooltip('Parameter View'), findsNothing);
        expect(find.byTooltip('Algorithm UI'), findsNothing);
        expect(find.byTooltip('Overview UI'), findsNothing);
        expect(find.byTooltip('Overview VU Meters'), findsNothing);
      },
    );

    testWidgets('Quick-action buttons render on both platforms', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      // Quick-action buttons should be present regardless of platform
      expect(find.byTooltip('File Browser'), findsOneWidget);
      expect(find.byTooltip('Template Manager'), findsOneWidget);
      expect(find.byTooltip('Perform'), findsOneWidget);
      expect(find.byTooltip('Plugin Manager'), findsOneWidget);
    });

    testWidgets(
      'memory shortcut follows the CPU width threshold with compact geometry',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final visualSizes = <int, Size>{};
        final targetSizes = <int, Size>{};
        for (final width in [390, 640, 900, 901, 1440]) {
          tester.view.physicalSize = Size(width.toDouble(), 800);
          await tester.pumpWidget(
            createTestWidget(
              isMobile: width < 900,
              isOffline: false,
              firmware: '1.19.0',
            ),
          );
          await tester.pump();

          final shortcut = find.byKey(const ValueKey('bottom-memory-shortcut'));
          expect(tester.takeException(), isNull, reason: 'width $width');
          if (width <= 900) {
            expect(shortcut, findsNothing, reason: 'width $width');
            continue;
          }

          expect(shortcut, findsOneWidget, reason: 'width $width');
          expect(find.byType(CpuMonitorWidget), findsOneWidget);
          final visual = find.byKey(const ValueKey('memory-miniature-visual'));
          final interactionTarget = find.byKey(
            const ValueKey('memory-detail-interaction-target'),
          );
          visualSizes[width] = tester.getSize(visual);
          targetSizes[width] = tester.getSize(interactionTarget);

          final cpuRect = tester.getRect(find.byType(CpuMonitorWidget));
          final shortcutRect = tester.getRect(shortcut);
          final fabRect = tester.getRect(find.byType(FloatingActionButton));
          expect(shortcutRect.left, greaterThanOrEqualTo(cpuRect.right));
          expect(shortcutRect.overlaps(fabRect), isFalse);
        }

        expect(visualSizes, {
          901: const Size(41, 24),
          1440: const Size(41, 24),
        });
        expect(targetSizes, {
          901: const Size(48, 48),
          1440: const Size(48, 48),
        });
      },
    );

    testWidgets(
      'supported live shortcut keeps all device-reported detail in the viewport',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final semantics = tester.ensureSemantics();
        const valueLabels = [
          'SRAM current, 16 KiB',
          'SRAM total, 64 KiB',
          'SRAM free, 48 KiB',
          'DRAM current, 2 MiB',
          'DRAM total, 8 MiB',
          'DRAM free, 6 MiB',
          'DTC current, 1 KiB',
          'DTC total, 4 KiB',
          'DTC free, 3 KiB',
          'ITC current, 128 B',
          'ITC total, 512 B',
          'ITC free, 384 B',
        ];

        for (final width in [901, 1440]) {
          tester.view.physicalSize = Size(width.toDouble(), 800);
          await tester.pumpWidget(
            createTestWidget(
              isMobile: false,
              isOffline: false,
              firmware: '1.19beta',
            ),
          );
          await tester.pump();

          final shortcut = find.byKey(const ValueKey('bottom-memory-shortcut'));
          expect(shortcut, findsOneWidget, reason: 'width $width');
          expect(find.byType(MemoryMiniature), findsOneWidget);
          await tester.tap(shortcut);
          await tester.pump();
          await tester.pump();

          final viewport = Rect.fromLTWH(0, 0, width.toDouble(), 800);
          final presenter = find.byType(MemoryDetailPresenter);
          expect(presenter, findsOneWidget, reason: 'width $width');
          final presenterRect = tester.getRect(presenter);
          expect(
            viewport.contains(presenterRect.topLeft) &&
                viewport.contains(presenterRect.bottomRight),
            isTrue,
            reason:
                'memory presenter $presenterRect must remain inside '
                '$viewport at width $width',
          );
          for (final label in valueLabels) {
            final value = find.bySemanticsLabel(label);
            expect(value, findsOneWidget, reason: 'width $width: $label');
            expect(
              viewport.contains(tester.getTopLeft(value)) &&
                  viewport.contains(tester.getBottomRight(value)),
              isTrue,
              reason: 'width $width: $label must remain in the viewport',
            );
          }

          expect(find.text('Used / total · free shown at right'), findsNothing);
          expect(find.textContaining('fit'), findsNothing);
          expect(find.textContaining('required'), findsNothing);
          verify(() => mockCubit.refreshDisplayMemory()).called(1);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
        semantics.dispose();
      },
    );

    testWidgets('memory shortcut applies live firmware eligibility', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestWidget(
          isMobile: false,
          isOffline: false,
          firmware: '1.18.99',
        ),
      );
      expect(
        find.byKey(const ValueKey('bottom-memory-shortcut')),
        findsNothing,
      );

      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: true, firmware: '1.19.0'),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bottom-memory-shortcut')),
        findsNothing,
      );
    });

    testWidgets('Samples button pushes PolySamplesScreen on desktop', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      expect(find.byTooltip('Samples'), findsOneWidget);
      await tester.tap(find.byTooltip('Samples'));
      await tester.pumpAndSettle();
      expect(find.byType(PolySamplesScreen), findsOneWidget);
    });

    testWidgets('Samples button is absent on mobile', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        createTestWidget(isMobile: true, isOffline: false),
      );

      expect(find.byTooltip('Samples'), findsNothing);
    });

    testWidgets('Template Manager button pushes TemplateManagerScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      await tester.tap(find.byTooltip('Template Manager'));
      await tester.pumpAndSettle();

      expect(find.byType(TemplateManagerScreen), findsOneWidget);
      expect(find.text('Template Manager'), findsOneWidget);
    });

    testWidgets('Mod+T pushes TemplateManagerScreen', (tester) async {
      await tester.pumpWidget(
        createTestWidget(isMobile: false, isOffline: false),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(find.byType(TemplateManagerScreen), findsOneWidget);
      expect(find.text('Template Manager'), findsOneWidget);
    });
  });
}
