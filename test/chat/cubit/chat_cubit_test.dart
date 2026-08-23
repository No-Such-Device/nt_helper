import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockToolRegistry extends Mock implements ToolRegistry {}

class MockMemoryService extends Mock implements MemoryService {}

class MockLlmProvider extends Mock implements LlmProvider {}

class FakeLlmMessage extends Fake implements LlmMessage {}

const _settings = ChatSettings(
  provider: LlmProviderType.anthropic,
  anthropicApiKey: 'test-key',
  anthropicModel: 'claude-haiku-4-5-20251001',
);

const _openAiSettings = ChatSettings(
  provider: LlmProviderType.openai,
  openaiApiKey: 'test-key',
  openaiModel: 'gpt-5-nano',
);

void main() {
  late MockToolRegistry toolRegistry;
  late MockMemoryService memoryService;

  setUpAll(() {
    registerFallbackValue(<LlmMessage>[]);
    registerFallbackValue(<LlmToolDefinition>[]);
    registerFallbackValue(FakeLlmMessage());
  });

  setUp(() {
    toolRegistry = MockToolRegistry();
    memoryService = MockMemoryService();

    when(() => toolRegistry.entries).thenReturn(const []);
    when(() => toolRegistry.findByName(any())).thenReturn(null);
    when(
      () => toolRegistry.executeTool(any(), any()),
    ).thenAnswer((_) async => '{"success":true}');
    when(
      () => toolRegistry.storeReferenceIfLarge(
        toolName: any(named: 'toolName'),
        result: any(named: 'result'),
      ),
    ).thenAnswer((invocation) => invocation.namedArguments[#result] as String);
    when(() => memoryService.readMemory()).thenAnswer((_) async => '');
    when(() => memoryService.readDailyLogs()).thenAnswer((_) async => '');
    when(
      () => memoryService.saveSessionSnapshot(any()),
    ).thenAnswer((_) async {});
  });

  group('Attachment validation', () {
    blocTest<ChatCubit, ChatState>(
      'rejects provider-unsupported binary file attachments before sending',
      build: () {
        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => throw StateError('provider should not run'),
        );
      },
      act: (cubit) async {
        await cubit.sendMessage(
          'read this',
          _openAiSettings,
          fileAttachments: const [
            ChatFileAttachment(
              name: 'manual.pdf',
              data: 'JVBERi0xLjQ=',
              mimeType: 'application/pdf',
              sizeBytes: 8,
            ),
          ],
        );
      },
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', true)
            .having((s) => s.messages, 'messages', hasLength(1))
            .having(
              (s) => s.messages.single.fileAttachments.single.name,
              'file attachment',
              'manual.pdf',
            ),
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', false)
            .having((s) => s.messages, 'messages', hasLength(2))
            .having(
              (s) => s.messages.last.content,
              'validation message',
              contains('Unsupported attachment for OpenAI API: manual.pdf'),
            ),
      ],
    );

    test('does not persist attachments into a legacy uploads folder', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nt_helper_chat_uploads_',
      );
      try {
        SharedPreferences.setMockInitialValues({
          'chat_local_directory': tempDir.path,
        });
        await SettingsService().init();
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(content: 'ok', isComplete: true),
        );
        final cubit = ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );

        await cubit.sendMessage(
          'look',
          _settings,
          imageAttachments: const [
            ChatImageAttachment(
              data: 'AQID',
              mimeType: 'image/png',
              name: 'clip.png',
            ),
          ],
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(await Directory('${tempDir.path}/uploads').exists(), isFalse);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    blocTest<ChatCubit, ChatState>(
      'uses plural placeholder text for multiple image-only attachments',
      build: () {
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(content: 'ok', isComplete: true),
        );
        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
      },
      act: (cubit) async {
        await cubit.sendMessage(
          '',
          _settings,
          imageAttachments: const [
            ChatImageAttachment(
              data: 'AQID',
              mimeType: 'image/png',
              name: 'one.png',
            ),
            ChatImageAttachment(
              data: 'BAUG',
              mimeType: 'image/png',
              name: 'two.png',
            ),
          ],
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', true)
            .having(
              (s) => s.messages.single.content,
              'content',
              'Attached images.',
            ),
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', false)
            .having((s) => s.messages.last.content, 'assistant response', 'ok'),
      ],
    );

    test('stores large text attachments as searchable references', () async {
      final provider = MockLlmProvider();
      when(() => provider.dispose()).thenReturn(null);
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer(
        (_) async => const LlmResponse(content: 'ok', isComplete: true),
      );
      when(
        () => toolRegistry.storeReferenceIfLarge(
          toolName: 'attachment:manual.pdf',
          result: any(named: 'result'),
        ),
      ).thenReturn(
        '{"success":true,"type":"tool_reference","reference_id":"ref_manual",'
        '"tool_name":"attachment:manual.pdf","total_chars":25000,'
        '"instructions":"Use read_reference or search_reference."}',
      );
      final cubit = ChatCubit(
        toolRegistry: toolRegistry,
        memoryService: memoryService,
        providerFactory: (_) => provider,
      );

      await cubit.sendMessage(
        'read this',
        _settings,
        fileAttachments: [
          ChatFileAttachment(
            name: 'manual.pdf',
            data: 'JVBERi0xLjQ=',
            mimeType: 'application/pdf',
            sizeBytes: 8,
            textContent: List.filled(25000, 'A').join(),
          ),
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final captured = verify(
        () => provider.sendMessages(
          messages: captureAny(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).captured;
      final sentMessages = captured.last as List<LlmMessage>;
      final userMessage = sentMessages.firstWhere(
        (message) => message.role == LlmRole.user,
      );
      expect(userMessage.content, contains('"type":"tool_reference"'));
      expect(userMessage.content, contains('"reference_id":"ref_manual"'));
      expect(userMessage.content, isNot(contains('AAAAAAAAAA')));
      verify(
        () => toolRegistry.storeReferenceIfLarge(
          toolName: 'attachment:manual.pdf',
          result: any(named: 'result'),
        ),
      ).called(1);
    });
  });

  group('Bug 1: permanent thinking spinner — onDone without isFinal', () {
    blocTest<ChatCubit, ChatState>(
      'resets isProcessing when stream completes without isFinal',
      build: () {
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenThrow(Exception('network error'));

        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('hello', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', true)
            .having((s) => s.messages, 'messages', hasLength(1)),
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', false)
            .having(
              (s) => s.messages.last.role,
              'last message role',
              ChatMessageRole.assistant,
            )
            .having(
              (s) => s.messages.last.content,
              'last message content',
              contains('Error'),
            ),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'resets isProcessing when stream ends after ChatLoopError event',
      build: () {
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenThrow(Exception('API unreachable'));

        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('test message', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      verify: (cubit) {
        final s = cubit.state;
        expect(s, isA<ChatReady>());
        expect((s as ChatReady).isProcessing, isFalse);
      },
    );

    blocTest<ChatCubit, ChatState>(
      'resets isProcessing when provider returns final response normally',
      build: () {
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(
            content: 'Hello!',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 5),
          ),
        );

        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('hi', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      verify: (cubit) {
        final s = cubit.state as ChatReady;
        expect(s.isProcessing, isFalse);
        expect(
          s.messages.any(
            (m) => m.role == ChatMessageRole.assistant && m.content == 'Hello!',
          ),
          isTrue,
        );
      },
    );
  });

  group('Bug 2: isProcessing stuck on exception during sendMessage', () {
    blocTest<ChatCubit, ChatState>(
      'resets isProcessing when providerFactory throws',
      build: () {
        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => throw Exception('provider creation failed'),
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('hello', _settings);
      },
      expect: () => [
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', true)
            .having((s) => s.messages, 'messages', hasLength(1)),
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', false)
            .having(
              (s) => s.messages.last.content,
              'error message',
              contains('provider creation failed'),
            ),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'resets isProcessing when memory bootstrap throws',
      build: () {
        when(
          () => memoryService.readMemory(),
        ).thenThrow(Exception('filesystem error'));

        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);

        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('hello', _settings);
      },
      expect: () => [
        isA<ChatReady>().having((s) => s.isProcessing, 'isProcessing', true),
        isA<ChatReady>()
            .having((s) => s.isProcessing, 'isProcessing', false)
            .having(
              (s) => s.messages.last.content,
              'error message',
              contains('filesystem error'),
            ),
      ],
    );

    blocTest<ChatCubit, ChatState>(
      'shows error message to user when exception occurs',
      build: () {
        return ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => throw Exception('boom'),
        );
      },
      act: (cubit) async {
        await cubit.sendMessage('test', _settings);
      },
      verify: (cubit) {
        final s = cubit.state as ChatReady;
        expect(s.isProcessing, isFalse);
        final errorMessages = s.messages.where(
          (m) =>
              m.role == ChatMessageRole.assistant &&
              m.content.contains('Error'),
        );
        expect(errorMessages, isNotEmpty);
      },
    );
  });

  group('Bug 3: cancelProcessing after completed loop wipes history', () {
    test(
      'cancelProcessing after successful loop preserves conversation history',
      () async {
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(
            content: 'Hello!',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 5),
          ),
        );

        final cubit = ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
        addTearDown(cubit.close);

        // Send a message and let the loop complete
        await cubit.sendMessage('hello', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        final stateBeforeCancel = cubit.state as ChatReady;
        expect(stateBeforeCancel.isProcessing, isFalse);
        expect(stateBeforeCancel.messages, hasLength(2)); // user + assistant

        // Cancel after loop already completed — should be a no-op
        cubit.cancelProcessing();

        // Send another message — it should work, proving history wasn't wiped
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(
            content: 'Second response',
            isComplete: true,
            usage: LlmUsage(inputTokens: 15, outputTokens: 8),
          ),
        );

        await cubit.sendMessage('second message', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // The LLM should have received the full conversation history
        // (user + assistant from first turn, plus user from second turn).
        // If cancelProcessing wiped the internal history, the LLM would only
        // see the second user message.
        final captured = verify(
          () => provider.sendMessages(
            messages: captureAny(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).captured;

        // The second sendMessage call's messages should include the first turn.
        // captured contains one list per invocation. The second invocation (index 1)
        // is the one from the agentic loop's second call.
        // But sendMessages is called once per loop iteration, and our mock returns
        // a final response immediately. So the second call to sendMessages is from
        // the second sendMessage(). The messages passed should be:
        // user("hello"), assistant("Hello!"), user("second message")
        final secondCallMessages = captured.last as List<LlmMessage>;
        expect(
          secondCallMessages.length,
          greaterThanOrEqualTo(3),
          reason:
              'Expected at least 3 messages: '
              '${secondCallMessages.map((m) => '${m.role.name}:${m.content}').join(', ')}',
        );
        // First-turn user message should be present
        expect(secondCallMessages[0].content, 'hello');
        // First-turn assistant response should be present
        expect(secondCallMessages[1].content, 'Hello!');
        // Second-turn user message should be present
        expect(secondCallMessages[2].content, 'second message');
      },
    );
  });

  group('Bug 4: cancelProcessing resets state', () {
    test('cancelProcessing resets isProcessing to false', () async {
      final completer = Completer<LlmResponse>();
      final provider = MockLlmProvider();
      when(() => provider.dispose()).thenReturn(null);
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer((_) => completer.future);

      final cubit = ChatCubit(
        toolRegistry: toolRegistry,
        memoryService: memoryService,
        providerFactory: (_) => provider,
      );
      addTearDown(cubit.close);

      unawaited(cubit.sendMessage('hello', _settings));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((cubit.state as ChatReady).isProcessing, isTrue);

      cubit.cancelProcessing();

      final s = cubit.state as ChatReady;
      expect(s.isProcessing, isFalse);
      expect(s.currentToolName, isNull);

      completer.complete(const LlmResponse(content: 'late', isComplete: true));
    });

    test('cancelProcessing clears currentToolName', () async {
      final completer = Completer<LlmResponse>();
      final provider = MockLlmProvider();
      when(() => provider.dispose()).thenReturn(null);
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer((_) => completer.future);

      final cubit = ChatCubit(
        toolRegistry: toolRegistry,
        memoryService: memoryService,
        providerFactory: (_) => provider,
      );
      addTearDown(cubit.close);

      unawaited(cubit.sendMessage('hello', _settings));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      cubit.cancelProcessing();

      final s = cubit.state as ChatReady;
      expect(s.currentToolName, isNull);

      completer.complete(const LlmResponse(content: 'late', isComplete: true));
    });
  });

  group('Bug 5: compaction trim breaks message role ordering', () {
    test('after compaction, history sent to provider starts with user message '
        'even when trim boundary falls mid-tool-sequence', () async {
      int callCount = 0;

      final provider = MockLlmProvider();
      when(() => provider.dispose()).thenReturn(null);
      when(
        () => provider.resolveContextWindowTokens(),
      ).thenAnswer((_) async => 200000);
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        switch (callCount) {
          case 1:
            // Turn 1, iteration 1: return tool calls to build up history
            return const LlmResponse(
              isComplete: false,
              toolCalls: [
                LlmToolCall(id: 'tc1', name: 'fake_tool', arguments: {}),
                LlmToolCall(id: 'tc2', name: 'fake_tool', arguments: {}),
                LlmToolCall(id: 'tc3', name: 'fake_tool', arguments: {}),
              ],
            );
          case 2:
            // Turn 1, iteration 2: more tool calls
            return const LlmResponse(
              isComplete: false,
              toolCalls: [
                LlmToolCall(id: 'tc4', name: 'fake_tool', arguments: {}),
                LlmToolCall(id: 'tc5', name: 'fake_tool', arguments: {}),
                LlmToolCall(id: 'tc6', name: 'fake_tool', arguments: {}),
              ],
            );
          case 3:
            // Turn 1, iteration 3: final response with high tokens to trigger
            // compaction (85% of the provider's 200000 token window).
            return const LlmResponse(
              content: 'Done with tools.',
              isComplete: true,
              usage: LlmUsage(inputTokens: 171000, outputTokens: 500),
            );
          case 4:
            // Compaction loop: simple final response
            return const LlmResponse(
              content: 'Context saved.',
              isComplete: true,
              usage: LlmUsage(inputTokens: 100, outputTokens: 50),
            );
          default:
            // Turn 2 actual message: final response
            return const LlmResponse(
              content: 'Second turn response.',
              isComplete: true,
              usage: LlmUsage(inputTokens: 100, outputTokens: 50),
            );
        }
      });

      final cubit = ChatCubit(
        toolRegistry: toolRegistry,
        memoryService: memoryService,
        providerFactory: (_) => provider,
      );
      addTearDown(cubit.close);

      // Turn 1: builds up tool call history and triggers _needsCompaction
      await cubit.sendMessage('hello', _settings);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect((cubit.state as ChatReady).isProcessing, isFalse);

      // Turn 2: triggers compaction, then sends the real message.
      // Before the fix, the trim could leave orphaned tool messages at the
      // start of history, causing OpenAI to reject with 400.
      await cubit.sendMessage('second question', _settings);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect((cubit.state as ChatReady).isProcessing, isFalse);

      // Verify the last sendMessages call got a history starting with user
      final captured = verify(
        () => provider.sendMessages(
          messages: captureAny(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).captured;

      // The last captured messages list is from the post-compaction real call
      final lastMessages = captured.last as List<LlmMessage>;
      expect(
        lastMessages.first.role,
        equals(LlmRole.user),
        reason:
            'After compaction trim, history must start with a user message. '
            'Got: ${lastMessages.map((m) => m.role.name).join(', ')}',
      );
    });

    test(
      'recomputes compaction need after resolving the next provider window',
      () async {
        final firstProvider = MockLlmProvider();
        final secondProvider = MockLlmProvider();
        when(() => firstProvider.dispose()).thenReturn(null);
        when(() => secondProvider.dispose()).thenReturn(null);
        when(
          () => firstProvider.resolveContextWindowTokens(),
        ).thenAnswer((_) async => 1000);
        when(
          () => secondProvider.resolveContextWindowTokens(),
        ).thenAnswer((_) async => 2000);
        when(
          () => firstProvider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(
            content: 'near the small window',
            isComplete: true,
            usage: LlmUsage(inputTokens: 900, outputTokens: 10),
          ),
        );
        when(
          () => secondProvider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer(
          (_) async => const LlmResponse(
            content: 'fits the larger window',
            isComplete: true,
            usage: LlmUsage(inputTokens: 950, outputTokens: 10),
          ),
        );

        final providers = [firstProvider, secondProvider];
        var providerIndex = 0;
        final cubit = ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => providers[providerIndex++],
        );
        addTearDown(cubit.close);

        await cubit.sendMessage('first', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect((cubit.state as ChatReady).isProcessing, isFalse);

        await cubit.sendMessage('second', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        verify(
          () => secondProvider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).called(1);
        expect((cubit.state as ChatReady).contextWindowTokens, 2000);
      },
    );

    test('keeps existing history when automatic compaction fails', () async {
      final firstProvider = MockLlmProvider();
      final compactionProvider = MockLlmProvider();
      when(() => firstProvider.dispose()).thenReturn(null);
      when(() => compactionProvider.dispose()).thenReturn(null);
      when(
        () => firstProvider.resolveContextWindowTokens(),
      ).thenAnswer((_) async => 1000);
      when(
        () => compactionProvider.resolveContextWindowTokens(),
      ).thenAnswer((_) async => 1000);
      when(
        () => firstProvider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer(
        (_) async => const LlmResponse(
          content: 'near the limit',
          isComplete: true,
          usage: LlmUsage(inputTokens: 900, outputTokens: 10),
        ),
      );
      when(
        () => compactionProvider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenThrow(Exception('compaction API down'));

      final providers = [firstProvider, compactionProvider];
      var providerIndex = 0;
      final cubit = ChatCubit(
        toolRegistry: toolRegistry,
        memoryService: memoryService,
        providerFactory: (_) => providers[providerIndex++],
      );
      addTearDown(cubit.close);

      await cubit.sendMessage('first', _settings);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(cubit.contextSummary.messageCount, 2);

      await cubit.sendMessage('second', _settings);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final state = cubit.state as ChatReady;
      expect(state.isProcessing, isFalse);
      expect(state.messages.last.content, contains('Compaction failed'));
      expect(cubit.contextSummary.messageCount, 2);
    });
  });

  group('Prompt cache prefix stability', () {
    test(
      'keeps the bootstrapped system prompt byte-stable across turns',
      () async {
        var readMemoryCalls = 0;
        when(() => memoryService.readMemory()).thenAnswer((_) async {
          readMemoryCalls++;
          return 'old memory';
        });

        final memoryWriteTool = ToolRegistryEntry(
          name: 'memory_write',
          description: 'Write memory.',
          inputSchema: const {'properties': {}},
          handler: (_) async => '{"success":true}',
        );
        when(() => toolRegistry.entries).thenReturn([memoryWriteTool]);
        when(
          () => toolRegistry.executeTool('memory_write', any()),
        ).thenAnswer((_) async => '{"success":true}');

        var providerCallCount = 0;
        String? firstTurnSystemPrompt;
        String? secondTurnSystemPrompt;
        String? firstTurnToolPrefix;
        String? secondTurnToolPrefix;
        final provider = MockLlmProvider();
        when(() => provider.dispose()).thenReturn(null);
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer((invocation) async {
          providerCallCount++;
          switch (providerCallCount) {
            case 1:
              firstTurnSystemPrompt =
                  invocation.namedArguments[#systemPrompt] as String?;
              firstTurnToolPrefix = jsonEncode(
                (invocation.namedArguments[#tools] as List<LlmToolDefinition>)
                    .map(
                      (tool) => {
                        'name': tool.name,
                        'description': tool.description,
                        'input_schema': tool.inputSchema,
                      },
                    )
                    .toList(),
              );
              return const LlmResponse(
                isComplete: false,
                toolCalls: [
                  LlmToolCall(
                    id: 'memory_call',
                    name: 'memory_write',
                    arguments: {'content': 'updated memory'},
                  ),
                ],
              );
            case 2:
              return const LlmResponse(
                content: 'saved',
                isComplete: true,
                usage: LlmUsage(inputTokens: 10, outputTokens: 5),
              );
            default:
              secondTurnSystemPrompt =
                  invocation.namedArguments[#systemPrompt] as String?;
              secondTurnToolPrefix = jsonEncode(
                (invocation.namedArguments[#tools] as List<LlmToolDefinition>)
                    .map(
                      (tool) => {
                        'name': tool.name,
                        'description': tool.description,
                        'input_schema': tool.inputSchema,
                      },
                    )
                    .toList(),
              );
              return const LlmResponse(
                content: 'using memory',
                isComplete: true,
                usage: LlmUsage(inputTokens: 10, outputTokens: 5),
              );
          }
        });

        final cubit = ChatCubit(
          toolRegistry: toolRegistry,
          memoryService: memoryService,
          providerFactory: (_) => provider,
        );
        addTearDown(cubit.close);

        await cubit.sendMessage('remember this', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(providerCallCount, 2);
        expect(readMemoryCalls, 1);

        await cubit.sendMessage('what do you remember?', _settings);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(providerCallCount, 3);
        expect(secondTurnSystemPrompt, firstTurnSystemPrompt);
        expect(secondTurnSystemPrompt, contains('old memory'));
        expect(secondTurnToolPrefix, firstTurnToolPrefix);
        expect(readMemoryCalls, 1);
      },
    );
  });
}
