import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/remote_wire_harness.dart';

class _Memory extends Mock implements MemoryService {}

class _Provider extends Mock implements LlmProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<LlmMessage>[]);
    registerFallbackValue(<LlmToolDefinition>[]);
  });

  for (final closeChat in [false, true]) {
    test('${closeChat ? 'close' : 'cancel'} releases a chat gesture and drops '
        'its later encoder turn', () async {
      SharedPreferences.setMockInitialValues({
        'request_timeout_ms': 1000,
        'inter_message_delay_ms': 0,
      });
      await SettingsService().init();
      final wire = RemoteWireHarness();
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final disting = DistingCubit(
        database,
        midiCommand: wire.midi,
        isWindowsOverride: true,
      );
      disting.emit(
        DistingState.synchronized(
          disting: wire.manager,
          distingVersion: '1.19.0',
          firmwareVersion: FirmwareVersion('1.19.0'),
          presetName: 'Chat remote cleanup',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
        ),
      );
      final registry = ToolRegistry(disting);
      final memory = _Memory();
      when(() => memory.readMemory()).thenAnswer((_) async => '');
      when(() => memory.readDailyLogs()).thenAnswer((_) async => '');
      when(() => memory.saveSessionSnapshot(any())).thenAnswer((_) async {});
      final provider = _Provider();
      when(() => provider.dispose()).thenReturn(null);
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer(
        (_) async => const LlmResponse(
          isComplete: false,
          toolCalls: [
            LlmToolCall(
              id: 'gesture',
              name: 'remote_control',
              arguments: {
                'actions': [
                  {'type': 'push', 'index': 4},
                  {'type': 'wait', 'duration_ms': 1000},
                  {'type': 'encoder_turn', 'index': 0, 'delta': 1},
                ],
              },
            ),
          ],
        ),
      );
      final chat = ChatCubit(
        toolRegistry: registry,
        memoryService: memory,
        providerFactory: (_) => provider,
      );
      addTearDown(() async {
        if (!chat.isClosed) await chat.close();
        await disting.close();
        await wire.close();
        await database.close();
      });
      final pushed = Completer<void>();
      final released = Completer<void>();
      wire.onSend = (packet) {
        if (packet[6] != 0x78) return;
        if (packet[7] == 1 && !pushed.isCompleted) pushed.complete();
        if (packet[7] == 2 && !released.isCompleted) released.complete();
      };
      await chat.sendMessage(
        'hold then turn',
        const ChatSettings(
          provider: LlmProviderType.anthropic,
          anthropicApiKey: 'test-key',
          anthropicModel: 'claude-haiku-4-5-20251001',
        ),
      );
      await pushed.future.timeout(const Duration(seconds: 2));
      if (closeChat) {
        await chat.close();
      } else {
        chat.cancelProcessing();
      }
      await released.future.timeout(const Duration(seconds: 2));
      if (!chat.isClosed) await chat.close();
      expect(wire.remotePackets, [
        remoteFrame([1, 4]),
        remoteFrame([2, 4]),
      ]);
      expect(disting.remoteControlState.heldControls, isEmpty);
      verify(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).called(1);
    }, tags: ['regression']);
  }
}
