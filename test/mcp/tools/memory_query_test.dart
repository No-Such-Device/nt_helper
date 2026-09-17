import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/services/disting_controller.dart';

class _MockDistingController extends Mock implements DistingController {}

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late _MockDistingController controller;
  late _MockDistingCubit cubit;
  late _MockDistingMidiManager midiManager;
  late MCPAlgorithmTools tools;

  DistingState synchronizedState({
    String firmware = '1.19.0',
    bool offline = false,
    bool demo = false,
  }) {
    return DistingState.synchronized(
      disting: midiManager,
      distingVersion: firmware,
      firmwareVersion: FirmwareVersion(firmware),
      presetName: 'Memory test',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
      offline: offline,
      demo: demo,
    );
  }

  setUp(() {
    controller = _MockDistingController();
    cubit = _MockDistingCubit();
    midiManager = _MockDistingMidiManager();
    tools = MCPAlgorithmTools(controller, cubit);
    when(() => cubit.state).thenReturn(const DistingState.initial());
  });

  test(
    'returns only fresh pool current, total, and derived free bytes',
    () async {
      const sample = MemoryUsage(
        sram: MemoryPoolUsage(total: 100, current: 25),
        dram: MemoryPoolUsage(total: 0, current: 0),
        dtc: MemoryPoolUsage(total: 20, current: 30),
        itc: MemoryPoolUsage(total: 4294967295, current: 1),
      );
      when(() => cubit.state).thenReturn(synchronizedState());
      when(
        () => cubit.requestFreshMemoryUsage(),
      ).thenAnswer((_) async => sample);

      final result = jsonDecode(await tools.showMemory());

      expect(result, {
        'success': true,
        'memory_usage': {
          'sram': {'current_bytes': 25, 'total_bytes': 100, 'free_bytes': 75},
          'dram': {'current_bytes': 0, 'total_bytes': 0, 'free_bytes': 0},
          'dtc': {'current_bytes': 30, 'total_bytes': 20, 'free_bytes': -10},
          'itc': {
            'current_bytes': 1,
            'total_bytes': 4294967295,
            'free_bytes': 4294967294,
          },
        },
      });
      verify(() => cubit.requestFreshMemoryUsage()).called(1);
    },
  );

  test('ToolRegistry dispatches show_memory through the fresh query', () async {
    const sample = MemoryUsage(
      sram: MemoryPoolUsage(total: 10, current: 1),
      dram: MemoryPoolUsage(total: 20, current: 2),
      dtc: MemoryPoolUsage(total: 30, current: 3),
      itc: MemoryPoolUsage(total: 40, current: 4),
    );
    when(() => cubit.state).thenReturn(synchronizedState());
    when(() => cubit.requestFreshMemoryUsage()).thenAnswer((_) async => sample);
    final registry = ToolRegistry(cubit);

    final entry = registry.findByName('show_memory');
    final result = jsonDecode(await registry.executeTool('show_memory', {}));

    expect(entry, isNotNull);
    expect(entry!.inputSchema, {'properties': <String, dynamic>{}});
    expect(result['success'], isTrue);
    expect(result['memory_usage']['sram']['current_bytes'], 1);
    verify(() => cubit.requestFreshMemoryUsage()).called(1);
  });

  test(
    'reports disconnected, offline, and unsupported states explicitly',
    () async {
      final disconnected = jsonDecode(await tools.showMemory());
      expect(disconnected, {
        'success': false,
        'error_code': 'disconnected',
        'error': 'No synchronized Disting NT is connected.',
      });

      when(() => cubit.state).thenReturn(synchronizedState(offline: true));
      final offline = jsonDecode(await tools.showMemory());
      expect(offline['success'], isFalse);
      expect(offline['error_code'], 'unavailable');
      expect(offline['error'], contains('physical connection'));

      when(() => cubit.state).thenReturn(synchronizedState(demo: true));
      final demo = jsonDecode(await tools.showMemory());
      expect(demo['success'], isFalse);
      expect(demo['error_code'], 'unavailable');
      expect(demo['error'], contains('physical connection'));

      when(() => cubit.state).thenReturn(synchronizedState(firmware: '1.18.9'));
      final unsupported = jsonDecode(await tools.showMemory());
      expect(unsupported['success'], isFalse);
      expect(unsupported['error_code'], 'unsupported');
      expect(unsupported['error'], contains('1.19'));

      verifyNever(() => cubit.requestFreshMemoryUsage());
    },
  );

  test(
    'reports fresh timeout instead of returning populated display cache',
    () async {
      const cached = MemoryUsage(
        sram: MemoryPoolUsage(total: 100, current: 10),
        dram: MemoryPoolUsage(total: 200, current: 20),
        dtc: MemoryPoolUsage(total: 300, current: 30),
        itc: MemoryPoolUsage(total: 400, current: 40),
      );
      when(() => cubit.state).thenReturn(synchronizedState());
      when(
        () => cubit.displayMemoryState,
      ).thenReturn(const MemoryDisplayState.available(cached));
      when(
        () => cubit.requestFreshMemoryUsage(),
      ).thenThrow(TimeoutException('fresh response timed out'));

      final result = jsonDecode(await tools.showMemory());

      expect(result['success'], isFalse);
      expect(result['error_code'], 'timeout');
      expect(result['error'], contains('fresh response timed out'));
      expect(result, isNot(contains('memory_usage')));
    },
  );

  test(
    'reports malformed and unavailable fresh responses explicitly',
    () async {
      when(() => cubit.state).thenReturn(synchronizedState());
      when(
        () => cubit.requestFreshMemoryUsage(),
      ).thenThrow(const FormatException('0x39 response was malformed'));

      final malformed = jsonDecode(await tools.showMemory());
      expect(malformed['success'], isFalse);
      expect(malformed['error_code'], 'malformed_response');
      expect(malformed['error'], contains('malformed'));

      reset(cubit);
      when(() => cubit.state).thenReturn(synchronizedState());
      when(
        () => cubit.requestFreshMemoryUsage(),
      ).thenThrow(StateError('The device did not return a memory sample.'));

      final unavailable = jsonDecode(await tools.showMemory());
      expect(unavailable['success'], isFalse);
      expect(unavailable['error_code'], 'unavailable');
      expect(unavailable['error'], contains('did not return'));
    },
  );
}
