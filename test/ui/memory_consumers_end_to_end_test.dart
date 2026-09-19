import 'dart:convert';

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
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/memory_wire_harness.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockPresetsDao extends Mock implements PresetsDao {}

class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  testWidgets(
    'bottom detail, System, and MCP share serialized fresh injected-wire queries',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 800);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({
        'show_debug_panel': false,
        'cpu_monitor_enabled': false,
        'request_timeout_ms': 1000,
        'inter_message_delay_ms': 0,
      });
      await SettingsService().init();

      final wire = MemoryWireHarness();
      addTearDown(wire.close);
      final database = _MockAppDatabase();
      final metadataDao = _MockMetadataDao();
      final presetsDao = _MockPresetsDao();
      final platform = _MockPlatformInteractionService();
      when(() => database.metadataDao).thenReturn(metadataDao);
      when(() => database.presetsDao).thenReturn(presetsDao);
      when(() => presetsDao.getTemplates()).thenAnswer((_) async => []);
      when(() => platform.isMobilePlatform()).thenReturn(false);

      final cubit = DistingCubit(
        database,
        midiCommand: wire.midi,
        isWindowsOverride: true,
      );
      addTearDown(cubit.close);
      cubit.emit(
        DistingState.synchronized(
          disting: wire.manager,
          distingVersion: '1.19.0',
          firmwareVersion: FirmwareVersion('1.19.0'),
          presetName: 'Unchanged preset',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
        ),
      );
      McpServerService.initialize(distingCubit: cubit);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: SynchronizedScreen(
              distingVersion: '1.19.0',
              firmwareVersion: FirmwareVersion('1.19.0'),
              slots: const [],
              algorithms: const [],
              units: const [],
              presetName: 'Unchanged preset',
              screenshot: Uint8List(0),
              loading: false,
              platformService: platform,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('bottom-memory-shortcut')));
      await tester.pump();
      await tester.pump();
      await _pumpUntilMemoryRequests(tester, wire, 1);

      final mcpCall = ToolRegistry(cubit).executeTool('show_memory', {});
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(
        wire.memoryRequests,
        hasLength(1),
        reason: 'The overlapping MCP consumer must wait for the UI query.',
      );

      wire.injectMemory(
        values: const [
          1000,
          2000,
          3000,
          4000,
          100,
          200,
          300,
          400,
          901,
          902,
          903,
          904,
        ],
      );
      await _pumpUntilAvailable(tester, cubit);
      expect(find.bySemanticsLabel('SRAM current, 0.1 KiB'), findsOneWidget);

      await _pumpUntilMemoryRequests(tester, wire, 2);
      wire.injectMemory(
        values: const [
          1200,
          2400,
          3600,
          4800,
          120,
          240,
          360,
          480,
          921,
          922,
          923,
          924,
        ],
      );
      final mcpResult = jsonDecode(await mcpCall) as Map<String, dynamic>;
      expect(
        cubit.displayMemoryState.sample?.sram.current,
        100,
        reason: 'A fresh-only MCP result must not replace the display sample.',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('More options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('System'));
      await tester.tap(find.text('System'));
      await tester.pump();
      await _pumpUntilMemoryRequests(tester, wire, 3);
      wire.injectMemory(
        values: const [
          1100,
          2200,
          3300,
          4400,
          110,
          220,
          330,
          440,
          911,
          912,
          913,
          914,
        ],
      );
      await _pumpUntilAvailable(tester, cubit, sramCurrent: 110);
      expect(
        find.byKey(const ValueKey('system-memory-status')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('SRAM current, 0.11 KiB'), findsOneWidget);

      expect(mcpResult, {
        'success': true,
        'memory_usage': {
          'sram': {
            'current_bytes': 120,
            'total_bytes': 1200,
            'free_bytes': 1080,
          },
          'dram': {
            'current_bytes': 240,
            'total_bytes': 2400,
            'free_bytes': 2160,
          },
          'dtc': {
            'current_bytes': 360,
            'total_bytes': 3600,
            'free_bytes': 3240,
          },
          'itc': {
            'current_bytes': 480,
            'total_bytes': 4800,
            'free_bytes': 4320,
          },
        },
      });
      expect(wire.memoryRequests, hasLength(3));
      expect(wire.packetsForCommand(0x30), hasLength(3));
      expect(wire.packetsForCommand(0x31), hasLength(3));
      expect(wire.packetsForCommand(0x32), isEmpty);
      expect(wire.packetsForCommand(0x38), isEmpty);
      expect(
        wire.memoryRequests,
        everyElement(
          equals(const [
            0xF0,
            0x00,
            0x21,
            0x27,
            0x6D,
            memoryWireSysExId,
            0x39,
            0x6E,
            0x6F,
            0x74,
            0x65,
            0x03,
            0x7F,
            0x7C,
            0x00,
            0x24,
            0x34,
            0x00,
            0x00,
            0x00,
            0xF7,
          ]),
        ),
      );
      final state = cubit.state as DistingStateSynchronized;
      expect(state.presetName, 'Unchanged preset');
      expect(state.slots, isEmpty);
    },
  );
}

Future<void> _pumpUntilMemoryRequests(
  WidgetTester tester,
  MemoryWireHarness wire,
  int count,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (wire.memoryRequests.length >= count) return;
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Expected $count memory requests, found ${wire.memoryRequests.length}.');
}

Future<void> _pumpUntilAvailable(
  WidgetTester tester,
  DistingCubit cubit, {
  int sramCurrent = 100,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (cubit.displayMemoryState.status == MemoryDisplayStatus.available &&
        cubit.displayMemoryState.sample?.sram.current == sramCurrent) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail(
    'Expected available SRAM current $sramCurrent, found '
    '${cubit.displayMemoryState.status.name} '
    '${cubit.displayMemoryState.sample?.sram.current}.',
  );
}
