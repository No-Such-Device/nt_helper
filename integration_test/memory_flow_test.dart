import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

final class _MockDistingCubit extends Mock implements DistingCubit {}

final class _MockDistingMidiManager extends Mock
    implements IDistingMidiManager {}

final class _MockAppDatabase extends Mock implements AppDatabase {}

final class _MockMetadataDao extends Mock implements MetadataDao {}

final class _MockPresetsDao extends Mock implements PresetsDao {}

final class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

const _memorySample = MemoryUsage(
  sram: MemoryPoolUsage(total: 64 * 1024, current: 16 * 1024),
  dram: MemoryPoolUsage(total: 8 * 1024 * 1024, current: 2 * 1024 * 1024),
  dtc: MemoryPoolUsage(total: 4 * 1024, current: 1024),
  itc: MemoryPoolUsage(total: 512, current: 128),
);

final class _MemoryFlowHarness {
  late final _MockDistingCubit cubit;
  late final _MockDistingMidiManager midiManager;
  late final _MockPlatformInteractionService platformService;
  late final StreamController<DistingState> stateController;
  late final StreamController<CpuUsage?> cpuController;
  late final StreamController<MemoryDisplayState> memoryController;

  late DistingState currentState;
  MemoryDisplayState memoryState = const MemoryDisplayState.available(
    _memorySample,
  );
  int refreshCalls = 0;

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
    when(() => cubit.displayMemoryState).thenAnswer((_) => memoryState);
    when(
      () => cubit.displayMemoryStateStream,
    ).thenAnswer((_) => memoryController.stream);
    when(() => cubit.refreshDisplayMemory()).thenAnswer((_) async {
      refreshCalls++;
    });
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
    when(
      () => platformService.isMobilePlatform(),
    ).thenReturn(Platform.isAndroid || Platform.isIOS);

    McpServerService.initialize(distingCubit: cubit);
  }

  DistingState synchronizedState(String firmware) {
    return DistingState.synchronized(
      disting: midiManager,
      distingVersion: firmware,
      firmwareVersion: FirmwareVersion(firmware),
      presetName: 'Memory matrix',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
    );
  }

  Widget app({String firmware = '1.19.0', double textScale = 1}) {
    currentState = synchronizedState(firmware);
    return MaterialApp(
      key: ValueKey('memory-app-$firmware-$textScale'),
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
          firmwareVersion: FirmwareVersion(firmware),
          slots: const [],
          algorithms: const [],
          units: const [],
          presetName: 'Memory matrix',
          screenshot: Uint8List(0),
          loading: false,
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
    double textScale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, height);
    await tester.pumpWidget(app(firmware: firmware, textScale: textScale));
    await tester.pump();
  }

  Future<void> openSystem(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('System'));
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
  }

  void emitMemory(MemoryDisplayState state) {
    memoryState = state;
    memoryController.add(state);
  }

  Future<void> dispose() async {
    await stateController.close();
    await cpuController.close();
    await memoryController.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtime = Platform.operatingSystem;
  late _MemoryFlowHarness harness;

  setUp(() async {
    _expectSupportedNativeRuntime();
    harness = _MemoryFlowHarness();
    await harness.initialize();
  });

  tearDown(() => harness.dispose());

  testWidgets(
    '$runtime runtime covers responsive, large-text and semantic matrix',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();

      for (final width in [390.0, 640.0, 900.0, 901.0, 1440.0]) {
        await harness.pumpApp(
          tester,
          width: width,
          height: width == 390 ? 500 : 800,
          firmware: '1.19beta',
          textScale: width == 390 ? 2 : 1,
        );

        final shortcut = find.byKey(const ValueKey('bottom-memory-shortcut'));
        expect(
          shortcut,
          width <= 900 ? findsNothing : findsOneWidget,
          reason: 'memory shortcut at $width logical pixels',
        );
        expect(
          find.byType(CpuMonitorWidget),
          width <= 900 ? findsNothing : findsOneWidget,
          reason: 'CPU visibility at $width logical pixels',
        );

        await harness.openSystem(tester);
        expect(find.byKey(const ValueKey('system-status-section')), findsOne);
        expect(find.byKey(const ValueKey('system-memory-status')), findsOne);
        expect(
          tester.getSemantics(find.text('System')).flagsCollection.isHeader,
          isTrue,
        );
        expect(
          tester.getSemantics(find.text('Status')).flagsCollection.isHeader,
          isTrue,
        );
        expect(find.bySemanticsLabel('SRAM current, 16 KiB'), findsOne);
        expect(find.bySemanticsLabel('SRAM total, 64 KiB'), findsOne);
        expect(find.bySemanticsLabel('SRAM free, 48 KiB'), findsOne);
        expect(find.bySemanticsLabel('DRAM current, 2 MiB'), findsOne);
        expect(find.bySemanticsLabel('DTC total, 4 KiB'), findsOne);
        expect(find.bySemanticsLabel('ITC free, 384 B'), findsOne);
        expect(tester.takeException(), isNull, reason: 'width $width');

        if (width == 390) {
          final dialogScroll = find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.byType(Scrollable),
          );
          expect(dialogScroll, findsOne);
          for (final action in const [
            'Remount SD Card',
            'Wave Cache Troubleshooting',
            'Reboot Device',
            'Rescan Algorithms',
          ]) {
            await tester.scrollUntilVisible(
              find.text(action),
              120,
              scrollable: dialogScroll,
            );
            expect(find.text(action), findsOne, reason: action);
            expect(tester.takeException(), isNull, reason: action);
          }
        }

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      await harness.pumpApp(tester, width: 1200, firmware: '1.18.99');
      expect(
        find.byKey(const ValueKey('bottom-memory-shortcut')),
        findsNothing,
      );
      await harness.openSystem(tester);
      expect(find.byKey(const ValueKey('system-memory-status')), findsNothing);
      expect(find.byKey(const ValueKey('system-cpu-status')), findsOne);
      expect(find.text('Remount SD Card'), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await harness.pumpApp(tester, width: 1200, firmware: '1.19beta');
      expect(find.byKey(const ValueKey('bottom-memory-shortcut')), findsOne);
      await harness.openSystem(tester);
      expect(find.byKey(const ValueKey('system-memory-status')), findsOne);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    '$runtime interaction modes and native modal focus remain accessible',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final semantics = tester.ensureSemantics();
      await harness.pumpApp(tester, width: 1440);

      final shortcut = find.bySemanticsLabel('Show memory details');
      final target = find.byKey(
        const ValueKey('memory-detail-interaction-target'),
      );
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));

      var expectedRefreshCalls = 0;
      if (!Platform.isAndroid && !Platform.isIOS) {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(shortcut));
        await tester.pump();
        await tester.pump();
        expect(find.byType(MemoryDetailPresenter), findsOne);
        expect(harness.refreshCalls, ++expectedRefreshCalls);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(find.byType(MemoryDetailPresenter), findsNothing);
        await mouse.removePointer();
      }

      await _tabToFocusedSemantics(tester, shortcut);
      expect(find.byType(MemoryDetailPresenter), findsOne);
      expect(harness.refreshCalls, ++expectedRefreshCalls);
      final decoration = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(MemoryDetailOpener),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .singleWhere((value) => value.border != null);
      expect(
        (decoration.border! as Border).top.color,
        Theme.of(tester.element(shortcut)).colorScheme.primary,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsOne);
      expect(find.bySemanticsLabel('DRAM total, 8 MiB'), findsOne);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(shortcut);
      await tester.pump();
      await tester.pump();
      expect(find.byType(MemoryDetailPresenter), findsOne);
      expect(harness.refreshCalls, expectedRefreshCalls + 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      final moreOptions = find.bySemanticsLabel('More options');
      await tester.tap(moreOptions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      final dialog = tester.element(find.byType(SimpleDialog));
      for (var index = 0; index < 8; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _isWithin(FocusManager.instance.primaryFocus?.context, dialog),
          isTrue,
          reason: 'Tab focus must remain in the System modal',
        );
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        _isWithin(FocusManager.instance.primaryFocus?.context, dialog),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(_semanticsIsFocused(tester, moreOptions), isTrue);
      semantics.dispose();
    },
  );

  testWidgets('$runtime System preserves unfresh, CPU and action safeguards', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    harness.memoryState = const MemoryDisplayState.unfresh(_memorySample);
    await harness.pumpApp(tester, width: 390, height: 500, textScale: 2);
    await harness.openSystem(tester);

    harness.cpuController.add(
      CpuUsage(cpu1: 17, cpu2: 29, slotUsages: const []),
    );
    await tester.pump();
    expect(find.text('17%'), findsOne);
    expect(find.text('29%'), findsOne);
    expect(find.text('Unfresh'), findsOne);
    expect(
      find.bySemanticsLabel(
        'Memory values are unfresh because the latest refresh failed',
      ),
      findsOne,
    );
    expect(find.textContaining('warning', findRichText: true), findsNothing);
    expect(harness.refreshCalls, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.refreshCalls, 1, reason: 'memory must not poll');

    await _tapSystemAction(tester, 'Remount SD Card');
    verify(() => harness.cubit.remountSd()).called(1);

    await harness.openSystem(tester);
    await _tapSystemAction(tester, 'Wave Cache Troubleshooting');
    expect(find.byType(WaveCacheTroubleshootingDialog), findsOne);
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(find.byType(WaveCacheTroubleshootingDialog), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await harness.openSystem(tester);
    await _tapSystemAction(tester, 'Reboot Device');
    expect(find.textContaining('Any unsaved changes will be lost'), findsOne);
    verifyNever(() => harness.cubit.reboot());
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await harness.openSystem(tester);
    await _tapSystemAction(tester, 'Reboot Device');
    await tester.tap(find.text('Reboot'));
    await tester.pumpAndSettle();
    verify(() => harness.cubit.reboot()).called(1);

    await harness.openSystem(tester);
    await _tapSystemAction(tester, 'Rescan Algorithms');
    verify(() => harness.cubit.refreshAlgorithms()).called(1);
    verifyNever(() => harness.cubit.rescanPlugins());
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

void _expectSupportedNativeRuntime() {
  expect(
    Platform.operatingSystem,
    isIn(const ['android', 'ios', 'linux', 'macos', 'windows']),
  );
  final expectedTarget = switch (Platform.operatingSystem) {
    'android' => TargetPlatform.android,
    'ios' => TargetPlatform.iOS,
    'linux' => TargetPlatform.linux,
    'macos' => TargetPlatform.macOS,
    'windows' => TargetPlatform.windows,
    _ => throw StateError('Unsupported runtime: ${Platform.operatingSystem}'),
  };
  expect(defaultTargetPlatform, expectedTarget);
}

Future<void> _tabToFocusedSemantics(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_semanticsIsFocused(tester, target)) return;
  }
  fail('Tab traversal did not reach the memory detail control.');
}

bool _semanticsIsFocused(WidgetTester tester, Finder finder) {
  return tester
          .getSemantics(finder)
          .getSemanticsData()
          .flagsCollection
          .isFocused ==
      Tristate.isTrue;
}

bool _isWithin(BuildContext? context, Element ancestor) {
  if (context is! Element) return false;
  if (identical(context, ancestor)) return true;

  var found = false;
  context.visitAncestorElements((element) {
    found = identical(element, ancestor);
    return !found;
  });
  return found;
}

Future<void> _tapSystemAction(WidgetTester tester, String label) async {
  final dialogScroll = find.descendant(
    of: find.byType(SimpleDialog),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text(label),
    120,
    scrollable: dialogScroll,
  );
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}
