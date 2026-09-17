import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

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
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/cpu_monitor_widget.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/memory_detail.dart';
import 'package:nt_helper/ui/widgets/wave_cache_troubleshooting_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockPresetsDao extends Mock implements PresetsDao {}

class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

const _firstMemorySample = MemoryUsage(
  sram: MemoryPoolUsage(total: 64 * 1024, current: 16 * 1024),
  dram: MemoryPoolUsage(total: 8 * 1024 * 1024, current: 2 * 1024 * 1024),
  dtc: MemoryPoolUsage(total: 4 * 1024, current: 1024),
  itc: MemoryPoolUsage(total: 512, current: 128),
);

const _secondMemorySample = MemoryUsage(
  sram: MemoryPoolUsage(total: 32 * 1024, current: 8 * 1024),
  dram: MemoryPoolUsage(total: 4 * 1024 * 1024, current: 1024 * 1024),
  dtc: MemoryPoolUsage(total: 8 * 1024, current: 2 * 1024),
  itc: MemoryPoolUsage(total: 1024, current: 256),
);

class _SystemStatusHarness {
  late final _MockDistingCubit cubit;
  late final _MockDistingMidiManager midiManager;
  late final _MockPlatformInteractionService platformService;
  late final StreamController<DistingState> stateController;
  late final StreamController<CpuUsage?> cpuController;
  late final StreamController<MemoryDisplayState> memoryController;

  late DistingState currentState;
  MemoryDisplayState currentMemory = const MemoryDisplayState.unavailable();

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({
      'show_debug_panel': false,
      'cpu_monitor_enabled': true,
    });
    await SettingsService().init();

    cubit = _MockDistingCubit();
    midiManager = _MockDistingMidiManager();
    platformService = _MockPlatformInteractionService();
    stateController = StreamController<DistingState>.broadcast();
    cpuController = StreamController<CpuUsage?>.broadcast();
    memoryController = StreamController<MemoryDisplayState>.broadcast();

    final database = _MockAppDatabase();
    final metadataDao = _MockMetadataDao();
    final presetsDao = _MockPresetsDao();
    when(() => cubit.database).thenReturn(database);
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(() => database.presetsDao).thenReturn(presetsDao);
    when(() => presetsDao.getTemplates()).thenAnswer((_) async => []);

    when(() => cubit.checkpoints).thenReturn([]);
    when(() => cubit.state).thenAnswer((_) => currentState);
    when(() => cubit.stream).thenAnswer((_) => stateController.stream);
    when(() => cubit.cpuUsageStream).thenAnswer((_) => cpuController.stream);
    when(() => cubit.resumeCpuMonitoring()).thenReturn(null);
    when(() => cubit.pauseCpuMonitoring()).thenReturn(null);
    when(() => cubit.displayMemoryState).thenAnswer((_) => currentMemory);
    when(
      () => cubit.displayMemoryStateStream,
    ).thenAnswer((_) => memoryController.stream);
    when(() => cubit.refreshDisplayMemory()).thenAnswer((_) async {});
    when(() => cubit.supportsMemoryUsage).thenAnswer((_) {
      final state = currentState;
      return state is DistingStateSynchronized &&
          !state.offline &&
          !state.demo &&
          state.firmwareVersion.hasMemoryUsage;
    });
    when(() => cubit.requireDisting()).thenReturn(midiManager);
    when(() => cubit.remountSd()).thenAnswer((_) async {});
    when(() => cubit.refreshAlgorithms()).thenReturn(null);
    when(() => cubit.reboot()).thenAnswer((_) async {});
    when(() => cubit.rescanPlugins()).thenAnswer((_) async {});

    McpServerService.initialize(distingCubit: cubit);
  }

  Future<void> dispose() async {
    await stateController.close();
    await cpuController.close();
    await memoryController.close();
  }

  DistingState synchronizedState({
    required String firmware,
    bool offline = false,
    bool demo = false,
  }) {
    return DistingState.synchronized(
      disting: midiManager,
      distingVersion: firmware,
      firmwareVersion: FirmwareVersion(firmware),
      presetName: 'Test',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
      offline: offline,
      demo: demo,
    );
  }

  Widget app({
    required double width,
    double height = 800,
    String firmware = '1.19.0',
    bool loading = false,
    bool offline = false,
    double textScale = 1,
  }) {
    currentState = synchronizedState(firmware: firmware, offline: offline);
    when(() => platformService.isMobilePlatform()).thenReturn(width <= 900);
    final firmwareVersion = FirmwareVersion(firmware);

    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: BlocProvider<DistingCubit>.value(
        value: cubit,
        child: SynchronizedScreen(
          distingVersion: firmware,
          firmwareVersion: firmwareVersion,
          slots: const [],
          algorithms: const [],
          units: const [],
          presetName: 'Test',
          screenshot: Uint8List(0),
          loading: loading,
          platformService: platformService,
        ),
      ),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required double width,
    double height = 800,
    String firmware = '1.19.0',
    bool loading = false,
    bool offline = false,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    await tester.pumpWidget(
      app(
        width: width,
        height: height,
        firmware: firmware,
        loading: loading,
        offline: offline,
        textScale: textScale,
      ),
    );
    await tester.pump();
  }

  Future<void> openSystem(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
  }

  void emitState(DistingState state) {
    currentState = state;
    stateController.add(state);
  }

  void emitMemory(MemoryDisplayState state) {
    currentMemory = state;
    memoryController.add(state);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SystemStatusHarness harness;

  setUp(() async {
    harness = _SystemStatusHarness();
    await harness.initialize();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets(
    'System exposes responsive CPU and supported memory at every breakpoint',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();

      for (final width in [390.0, 640.0, 900.0, 901.0, 1440.0]) {
        harness.currentMemory = const MemoryDisplayState.available(
          _firstMemorySample,
        );
        await harness.pumpApp(tester, width: width, firmware: '1.19beta');

        final bottomShortcut = find.byKey(
          const ValueKey('bottom-memory-shortcut'),
        );
        expect(
          bottomShortcut,
          width <= 900 ? findsNothing : findsOneWidget,
          reason: 'bottom shortcut at width $width',
        );
        expect(
          find.byType(CpuMonitorWidget),
          width <= 900 ? findsNothing : findsOneWidget,
          reason: 'bottom CPU at width $width',
        );

        await harness.openSystem(tester);
        expect(
          find.byKey(const ValueKey('system-status-section')),
          findsOneWidget,
          reason: 'width $width',
        );
        expect(find.text('Status'), findsOneWidget, reason: 'width $width');
        expect(
          find.byKey(const ValueKey('system-cpu-status')),
          findsOneWidget,
          reason: 'width $width',
        );
        expect(
          find.byKey(const ValueKey('system-memory-status')),
          findsOneWidget,
          reason: 'width $width',
        );
        expect(
          tester.getSemantics(find.text('System')).flagsCollection.isHeader,
          isTrue,
        );
        expect(
          tester.getSemantics(find.text('Status')).flagsCollection.isHeader,
          isTrue,
        );
        expect(tester.takeException(), isNull, reason: 'width $width');

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      verify(() => harness.cubit.refreshDisplayMemory()).called(5);
      semantics.dispose();
    },
  );

  testWidgets(
    'both openings refresh once and rebuilds, focus, hover and time do not poll',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      harness.currentMemory = const MemoryDisplayState.available(
        _firstMemorySample,
      );
      await harness.pumpApp(tester, width: 901, firmware: '1.19.0');

      final shortcut = find.byKey(const ValueKey('bottom-memory-shortcut'));
      await tester.tap(shortcut);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsOneWidget);
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(shortcut));
      await tester.pump();
      await tester.tap(shortcut);
      await tester.pump();
      harness.stateController.add(harness.currentState);
      await tester.pump();
      await tester.pump(const Duration(hours: 1));
      verifyNever(() => harness.cubit.refreshDisplayMemory());
      await pointer.moveTo(Offset.zero);
      await tester.pump();
      await pointer.removePointer();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tap(shortcut);
      await tester.pump();
      await tester.pump();
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await harness.openSystem(tester);
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);
      harness.stateController.add(harness.currentState);
      await tester.pump();
      await tester.pump(const Duration(hours: 1));
      verifyNever(() => harness.cubit.refreshDisplayMemory());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await harness.openSystem(tester);
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);
    },
  );

  testWidgets(
    'System retains a sample through refresh and timeout but clears it for another device',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();
      harness.currentMemory = const MemoryDisplayState.available(
        _firstMemorySample,
      );
      await harness.pumpApp(tester, width: 640, firmware: '1.19.0');
      await harness.openSystem(tester);

      expect(find.text('16 KiB'), findsOneWidget);
      harness.emitMemory(
        const MemoryDisplayState.refreshing(previousSample: _firstMemorySample),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('16 KiB'), findsOneWidget);
      expect(find.text('Refreshing'), findsOneWidget);
      expect(find.bySemanticsLabel('Refreshing memory values'), findsOneWidget);

      harness.emitMemory(const MemoryDisplayState.unfresh(_firstMemorySample));
      await tester.pump();
      await tester.pump();
      expect(find.text('16 KiB'), findsOneWidget);
      expect(find.text('Unfresh'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Memory values are unfresh because the latest refresh failed',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('failed'), findsNothing);
      expect(harness.cubit.supportsMemoryUsage, isTrue);

      harness.currentMemory = const MemoryDisplayState.unavailable();
      harness.emitState(const DistingState.initial());
      harness.emitMemory(const MemoryDisplayState.unavailable());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('system-memory-status')), findsNothing);

      harness.emitState(harness.synchronizedState(firmware: '1.19.0'));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('system-memory-status')),
        findsOneWidget,
      );
      expect(find.text('Unavailable'), findsAtLeastNWidgets(1));
      expect(find.text('16 KiB'), findsNothing);
      expect(find.text('8 KiB'), findsNothing);
      verify(() => harness.cubit.refreshDisplayMemory()).called(2);

      harness.emitMemory(
        const MemoryDisplayState.available(_secondMemorySample),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('SRAM current, 8 KiB'), findsOneWidget);
      expect(find.text('16 KiB'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'firmware gate hides only memory and keeps CPU and System actions usable',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final firmware in ['1.18.99', '1.18beta']) {
        harness.currentMemory = const MemoryDisplayState.unavailable();
        await harness.pumpApp(tester, width: 1200, firmware: firmware);
        expect(
          find.byKey(const ValueKey('bottom-memory-shortcut')),
          findsNothing,
        );
        await harness.openSystem(tester);
        expect(
          find.byKey(const ValueKey('system-memory-status')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('system-cpu-status')), findsOneWidget);
        expect(find.text('Remount SD Card'), findsOneWidget);
        expect(find.text('Rescan Algorithms'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      verifyNever(() => harness.cubit.refreshDisplayMemory());

      for (final firmware in ['1.19beta', '1.19.0', '1.20.0', '2.0.0']) {
        await harness.pumpApp(tester, width: 1200, firmware: firmware);
        expect(
          find.byKey(const ValueKey('bottom-memory-shortcut')),
          findsOneWidget,
        );
        await harness.openSystem(tester);
        expect(
          find.byKey(const ValueKey('system-memory-status')),
          findsOneWidget,
        );
        expect(find.text('Remount SD Card'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      verify(() => harness.cubit.refreshDisplayMemory()).called(4);
    },
  );

  testWidgets(
    'System keeps CPU stream behavior and original action order and handlers',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      harness.currentMemory = const MemoryDisplayState.available(
        _firstMemorySample,
      );
      await harness.pumpApp(tester, width: 1200, firmware: '1.19.0');
      verify(() => harness.cubit.resumeCpuMonitoring()).called(1);
      clearInteractions(harness.cubit);

      await harness.openSystem(tester);
      harness.cpuController.add(
        CpuUsage(cpu1: 17, cpu2: 29, slotUsages: const []),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Audio thread'), findsOneWidget);
      expect(find.text('Overall CPU'), findsOneWidget);
      expect(find.text('17%'), findsOneWidget);
      expect(find.text('29%'), findsOneWidget);
      verifyNever(() => harness.cubit.resumeCpuMonitoring());
      verifyNever(() => harness.cubit.pauseCpuMonitoring());

      final orderedLabels = [
        'Status',
        'Remount SD Card',
        'Wave Cache Troubleshooting',
        'Reboot Device',
        'Rescan Algorithms',
      ];
      final tops = orderedLabels
          .map((label) => tester.getTopLeft(find.text(label)).dy)
          .toList();
      expect(tops, orderedEquals(tops.toList()..sort()));
      expect(find.text('Close preview'), findsNothing);

      await tester.tap(find.text('Rescan Algorithms'));
      await tester.pumpAndSettle();
      verify(() => harness.cubit.refreshAlgorithms()).called(1);
      verifyNever(() => harness.cubit.rescanPlugins());
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);

      await harness.openSystem(tester);
      await tester.tap(find.text('Remount SD Card'));
      await tester.pumpAndSettle();
      verify(() => harness.cubit.remountSd()).called(1);
      verify(() => harness.cubit.refreshDisplayMemory()).called(1);

      await harness.openSystem(tester);
      await tester.tap(find.text('Reboot Device'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Any unsaved changes will be lost'),
        findsOneWidget,
      );
      verifyNever(() => harness.cubit.reboot());
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await harness.openSystem(tester);
      await tester.tap(find.text('Reboot Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reboot'));
      await tester.pumpAndSettle();
      verify(() => harness.cubit.reboot()).called(1);
      verify(() => harness.cubit.refreshDisplayMemory()).called(2);
    },
  );

  testWidgets('System CPU keeps truthful waiting and settings states', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await harness.pumpApp(tester, width: 640, firmware: '1.19.0');
    await harness.openSystem(tester);
    expect(find.text('Waiting for sample'), findsNWidgets(2));
    expect(find.text('0%'), findsNothing);

    await SettingsService().setCpuMonitorEnabled(false);
    await tester.pump();
    expect(find.text('Monitoring disabled'), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'Wave Cache keeps its gate and opens the existing protected dialog',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await harness.pumpApp(tester, width: 640, firmware: '1.16.9');
      await harness.openSystem(tester);
      final oldWaveOption = tester.widget<SimpleDialogOption>(
        find.ancestor(
          of: find.text('Wave Cache Troubleshooting'),
          matching: find.byType(SimpleDialogOption),
        ),
      );
      expect(oldWaveOption.onPressed, isNull);
      expect(find.text('Requires firmware 1.17 or later'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await harness.pumpApp(tester, width: 640, firmware: '1.19.0');
      await harness.openSystem(tester);
      await tester.tap(find.text('Wave Cache Troubleshooting'));
      await tester.pumpAndSettle();
      expect(find.byType(WaveCacheTroubleshootingDialog), findsOneWidget);
      verify(() => harness.cubit.requireDisting()).called(1);

      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(find.byType(WaveCacheTroubleshootingDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(WaveCacheTroubleshootingDialog), findsNothing);
    },
  );

  testWidgets(
    'large text System scrolls to every action without layout errors',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      harness.currentMemory = const MemoryDisplayState.available(
        _firstMemorySample,
      );
      await harness.pumpApp(
        tester,
        width: 390,
        height: 500,
        firmware: '1.19.0',
      );
      await harness.openSystem(tester);
      await tester.pumpWidget(
        harness.app(width: 390, height: 500, firmware: '1.19.0', textScale: 2),
      );
      await tester.pumpAndSettle();

      final dialogScroll = find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.byType(Scrollable),
      );
      expect(dialogScroll, findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Rescan Algorithms'),
        120,
        scrollable: dialogScroll,
      );
      expect(find.text('Rescan Algorithms'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Rescan Algorithms'));
      await tester.pumpAndSettle();
      verify(() => harness.cubit.refreshAlgorithms()).called(1);
    },
  );

  testWidgets('System remains disabled while loading or offline', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final configuration in [
      (loading: true, offline: false),
      (loading: false, offline: true),
    ]) {
      await harness.pumpApp(
        tester,
        width: 640,
        loading: configuration.loading,
        offline: configuration.offline,
      );
      await tester.tap(find.bySemanticsLabel('More options'));
      await tester.pumpAndSettle();
      final systemItem = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('System'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(systemItem.enabled, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
