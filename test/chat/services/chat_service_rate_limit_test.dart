import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/chat_service.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/mcp/tool_registry.dart';

class MockLlmProvider extends Mock implements LlmProvider {}

class MockToolRegistry extends Mock implements ToolRegistry {}

void main() {
  late MockLlmProvider provider;
  late MockToolRegistry toolRegistry;
  late ToolBridgeService toolBridge;
  late ChatService chatService;

  setUpAll(() {
    registerFallbackValue(<LlmMessage>[]);
    registerFallbackValue(<LlmToolDefinition>[]);
  });

  setUp(() {
    provider = MockLlmProvider();
    toolRegistry = MockToolRegistry();
    when(() => toolRegistry.entries).thenReturn(const []);
    toolBridge = ToolBridgeService(toolRegistry);
    chatService = ChatService(
      provider: provider,
      toolBridge: toolBridge,
      systemPrompt: 'test',
    );
  });

  group('Provider-safe tool history', () {
    test('drops orphan results and unmatched calls at the boundary', () {
      final repaired = providerSafeToolHistory([
        LlmMessage.user('start'),
        LlmMessage.toolResult(
          toolCallId: 'orphan',
          toolName: 'show_preset',
          content: '{}',
        ),
        LlmMessage.assistantWithToolCalls(const [
          LlmToolCall(id: 'matched', name: 'show_preset', arguments: {}),
          LlmToolCall(id: 'missing', name: 'show_slot', arguments: {}),
        ], content: 'Checking.'),
        LlmMessage.toolResult(
          toolCallId: 'matched',
          toolName: 'show_preset',
          content: '{"success":true}',
        ),
      ]);

      expect(repaired, hasLength(3));
      expect(repaired[0].role, LlmRole.user);
      expect(repaired[1].content, 'Checking.');
      expect(repaired[1].toolCalls?.map((call) => call.id), ['matched']);
      expect(repaired[2].toolCallId, 'matched');
    });

    test('keeps assistant text when all incomplete calls are removed', () {
      final repaired = providerSafeToolHistory([
        LlmMessage.assistantWithToolCalls(const [
          LlmToolCall(id: 'missing', name: 'show_slot', arguments: {}),
        ], content: 'I will inspect that.'),
      ]);

      expect(repaired, hasLength(1));
      expect(repaired.single.content, 'I will inspect that.');
      expect(repaired.single.toolCalls, isNull);
    });
  });

  group('Tool references', () {
    test('large tool result reference is sent to the next model call', () async {
      const referenceResult =
          '{"success":true,"type":"tool_reference","reference_id":"ref_1","tool_name":"large_tool","total_chars":25004,"instructions":"Use read_reference or search_reference."}';
      when(() => toolRegistry.entries).thenReturn([
        ToolRegistryEntry(
          name: 'large_tool',
          description: 'Returns a large text payload.',
          inputSchema: const {'properties': {}},
          handler: (_) async => 'unused',
        ),
      ]);
      when(
        () => toolRegistry.executeTool('large_tool', any()),
      ).thenAnswer((_) async => referenceResult);

      var callCount = 0;
      List<LlmMessage>? secondCallMessages;
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer((invocation) async {
        callCount++;
        if (callCount == 1) {
          return const LlmResponse(
            isComplete: false,
            toolCalls: [
              LlmToolCall(id: 'tc_large', name: 'large_tool', arguments: {}),
            ],
          );
        }

        secondCallMessages =
            invocation.namedArguments[#messages] as List<LlmMessage>;
        return const LlmResponse(content: 'done', isComplete: true);
      });

      final events = await chatService.runAgenticLoop([
        LlmMessage.user('run the large tool'),
      ]).toList();

      expect(events.whereType<ChatLoopError>(), isEmpty);
      expect(secondCallMessages, isNotNull);
      final toolMessage = secondCallMessages!.singleWhere(
        (message) => message.role == LlmRole.tool,
      );

      expect(toolMessage.content, referenceResult);
      expect(toolMessage.content, contains('"type":"tool_reference"'));
      expect(toolMessage.content, contains('"reference_id":"ref_1"'));
    });
  });

  group('Usage accounting', () {
    test('aggregates cache tokens into final usage and context peak', () async {
      var callCount = 0;
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenAnswer((_) async {
        callCount++;
        return switch (callCount) {
          1 => const LlmResponse(
            isComplete: false,
            toolCalls: [
              LlmToolCall(id: 'tc_small', name: 'small_tool', arguments: {}),
            ],
            usage: LlmUsage(
              inputTokens: 100,
              outputTokens: 10,
              cacheCreationInputTokens: 30,
              cacheReadInputTokens: 20,
            ),
          ),
          _ => const LlmResponse(
            content: 'done',
            isComplete: true,
            usage: LlmUsage(
              inputTokens: 50,
              outputTokens: 5,
              cacheReadInputTokens: 200,
            ),
          ),
        };
      });
      when(() => toolRegistry.entries).thenReturn([
        ToolRegistryEntry(
          name: 'small_tool',
          description: 'Returns a small payload.',
          inputSchema: const {'properties': {}},
          handler: (_) async => 'unused',
        ),
      ]);
      when(
        () => toolRegistry.executeTool('small_tool', any()),
      ).thenAnswer((_) async => '{"success":true}');

      final events = await chatService.runAgenticLoop([
        LlmMessage.user('run the tool'),
      ]).toList();

      final finalMessage = events
          .whereType<ChatLoopAssistantMessage>()
          .singleWhere((event) => event.isFinal);
      final usage = finalMessage.usage;

      expect(usage, isNotNull);
      expect(usage!.inputTokens, 150);
      expect(usage.outputTokens, 15);
      expect(usage.cacheCreationInputTokens, 30);
      expect(usage.cacheReadInputTokens, 220);
      expect(usage.contextInputTokens, 250);
    });
  });

  group('Rate limit retry', () {
    test(
      'single 429 then success yields rate limited event then result',
      () async {
        var callCount = 0;
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw LlmApiException(
              'Rate limit exceeded',
              statusCode: 429,
              retryAfterSeconds: 0,
            );
          }
          return const LlmResponse(
            content: 'Hello!',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 5),
          );
        });

        final events = await chatService.runAgenticLoop([
          LlmMessage.user('Hi'),
        ]).toList();

        final types = events.map((e) => e.runtimeType).toList();
        expect(types, contains(ChatLoopRateLimited));
        expect(types, contains(ChatLoopAssistantMessage));
        expect(types, isNot(contains(ChatLoopError)));
      },
    );

    test(
      'all retries exhausted yields rate limited events then error',
      () async {
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenThrow(
          LlmApiException(
            'Rate limit exceeded',
            statusCode: 429,
            retryAfterSeconds: 0,
          ),
        );

        final events = await chatService.runAgenticLoop([
          LlmMessage.user('Hi'),
        ]).toList();

        final rateLimitEvents = events
            .whereType<ChatLoopRateLimited>()
            .toList();
        final errorEvents = events.whereType<ChatLoopError>().toList();

        expect(rateLimitEvents.length, 4);
        expect(errorEvents.length, 1);
        expect(errorEvents.first.message, contains('Rate limited'));
      },
    );

    test('retry-after header value is used for wait time', () {
      fakeAsync((clock) {
        var callCount = 0;
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw LlmApiException(
              'Rate limit exceeded',
              statusCode: 429,
              retryAfterSeconds: 7,
            );
          }
          return const LlmResponse(
            content: 'Done',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 5),
          );
        });

        final events = <ChatLoopEvent>[];
        chatService.runAgenticLoop([LlmMessage.user('Hi')]).listen(events.add);

        clock.elapse(const Duration(seconds: 10));

        final rateLimitEvent = events.whereType<ChatLoopRateLimited>().first;
        expect(rateLimitEvent.waitSeconds, 7);
      });
    });

    test('non-429 error is not retried', () async {
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenThrow(LlmApiException('Server error', statusCode: 500));

      final events = await chatService.runAgenticLoop([
        LlmMessage.user('Hi'),
      ]).toList();

      final rateLimitEvents = events.whereType<ChatLoopRateLimited>().toList();
      final errorEvents = events.whereType<ChatLoopError>().toList();

      expect(rateLimitEvents, isEmpty);
      expect(errorEvents.length, 1);
      expect(errorEvents.first.message, contains('Server error'));
    });

    test('non-LlmApiException is not retried', () async {
      when(
        () => provider.sendMessages(
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          systemPrompt: any(named: 'systemPrompt'),
        ),
      ).thenThrow(Exception('Network error'));

      final events = await chatService.runAgenticLoop([
        LlmMessage.user('Hi'),
      ]).toList();

      final rateLimitEvents = events.whereType<ChatLoopRateLimited>().toList();
      final errorEvents = events.whereType<ChatLoopError>().toList();

      expect(rateLimitEvents, isEmpty);
      expect(errorEvents.length, 1);
    });

    test('backoff is capped at max seconds', () {
      fakeAsync((clock) {
        var callCount = 0;
        when(
          () => provider.sendMessages(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            systemPrompt: any(named: 'systemPrompt'),
          ),
        ).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw LlmApiException(
              'Rate limit exceeded',
              statusCode: 429,
              retryAfterSeconds: 999,
            );
          }
          return const LlmResponse(
            content: 'Done',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 5),
          );
        });

        final events = <ChatLoopEvent>[];
        chatService.runAgenticLoop([LlmMessage.user('Hi')]).listen(events.add);

        clock.elapse(const Duration(seconds: 35));

        final rateLimitEvent = events.whereType<ChatLoopRateLimited>().first;
        expect(rateLimitEvent.waitSeconds, 30);
      });
    });
  });
}
