import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart' show CancellationToken;
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/mcp/tool_registry.dart';

class _Memory extends Mock implements MemoryService {}

class _Registry extends Mock implements ToolRegistry {}

typedef _Step =
    Future<LlmResponse> Function(
      List<LlmMessage>,
      void Function(String),
      CancellationToken?,
    );

class _Provider implements StreamingLlmProvider {
  final List<_Step> steps;
  final requests = <List<LlmMessage>>[];
  _Provider(this.steps);
  @override
  String get displayName => 'Scripted streaming provider';
  @override
  Future<int?> resolveContextWindowTokens() async => 200000;
  @override
  void dispose() {}
  @override
  Future<LlmResponse> sendMessages({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
  }) => sendMessagesStreaming(
    messages: messages,
    tools: tools,
    systemPrompt: systemPrompt,
    onTextDelta: (_) {},
  );
  @override
  Future<LlmResponse> sendMessagesStreaming({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
    required void Function(String) onTextDelta,
    CancellationToken? cancel,
  }) {
    requests.add(List.of(messages));
    return steps.removeAt(0)(messages, onTextDelta, cancel);
  }
}

void main() {
  const settings = ChatSettings(anthropicApiKey: 'test');
  setUpAll(() {
    registerFallbackValue(<LlmMessage>[]);
  });
  late _Registry registry;
  late _Memory memory;
  setUp(() {
    registry = _Registry();
    memory = _Memory();
    when(() => registry.entries).thenReturn([]);
    when(() => registry.cancelRemoteControl()).thenAnswer((_) async {});
    when(() => registry.dispose()).thenAnswer((_) async {});
    when(() => memory.readMemory()).thenAnswer((_) async => '');
    when(() => memory.readDailyLogs()).thenAnswer((_) async => '');
    when(() => memory.saveSessionSnapshot(any())).thenAnswer((_) async {});
  });

  for (final cancelRun in [false, true]) {
    test(
      '${cancelRun ? 'cancelled' : 'failed'} turn retains executed tool facts without replay',
      () async {
        when(() => registry.entries).thenReturn([
          ToolRegistryEntry(
            name: 'set_test_value',
            description: 'Simulated mutation',
            inputSchema: {'properties': {}},
            handler: (_) async => 'unused',
          ),
        ]);
        when(
          () => registry.executeTool('set_test_value', any()),
        ).thenAnswer((_) async => '{"success":true,"value":7}');
        final started = Completer<void>();
        final provider = _Provider([
          (messages, emit, cancel) async => const LlmResponse(
            isComplete: false,
            toolCalls: [
              LlmToolCall(
                id: 'mutation1',
                name: 'set_test_value',
                arguments: {},
              ),
            ],
          ),
          (messages, emit, cancel) async {
            started.complete();
            if (cancelRun) {
              await cancel!.whenCancelled;
              cancel.throwIfCancelled();
            }
            throw StateError('model transport failed after the tool ran');
          },
          (messages, emit, cancel) async {
            expect(
              messages.where((m) => m.role == LlmRole.tool).single.content,
              contains('"value":7'),
            );
            return const LlmResponse(
              content: 'The earlier tool already ran.',
              isComplete: true,
            );
          },
        ]);
        final cubit = ChatCubit(
          toolRegistry: registry,
          memoryService: memory,
          providerFactory: (_) => provider,
        );
        addTearDown(cubit.close);
        final failed = cancelRun
            ? null
            : cubit.stream.firstWhere((s) => s is ChatReady && !s.isProcessing);
        await cubit.sendMessage('Set the test value', settings);
        await started.future;
        if (cancelRun) {
          cubit.cancelProcessing();
        } else {
          await failed;
        }
        final done = cubit.stream.firstWhere(
          (s) => s is ChatReady && !s.isProcessing,
        );
        await cubit.sendMessage('What already happened?', settings);
        await done;
        verify(() => registry.executeTool('set_test_value', any())).called(1);
        expect(
          (cubit.state as ChatReady).messages.last.content,
          'The earlier tool already ran.',
        );
      },
    , tags: ['regression']);
  }

  test(
    'live deltas update one stable assistant bubble and finalization does not duplicate it',
    () async {
      final first = Completer<void>();
      final finish = Completer<void>();
      final provider = _Provider([
        (messages, emit, cancel) async {
          emit('The screen ');
          first.complete();
          await finish.future;
          emit('is empty.');
          return const LlmResponse(
            content: 'The screen is empty.',
            isComplete: true,
            usage: LlmUsage(inputTokens: 10, outputTokens: 4),
          );
        },
        (messages, emit, cancel) async {
          expect(
            messages.where((m) => m.role == LlmRole.assistant).single.content,
            'The screen is empty.',
          );
          emit('Follow-up');
          return const LlmResponse(content: 'Follow-up', isComplete: true);
        },
      ]);
      final cubit = ChatCubit(
        toolRegistry: registry,
        memoryService: memory,
        providerFactory: (_) => provider,
      );
      addTearDown(cubit.close);
      await cubit.sendMessage('Look at the screen', settings);
      await first.future;
      await Future<void>.delayed(Duration.zero);
      final partial = cubit.state as ChatReady;
      expect(partial.isProcessing, isTrue);
      expect(partial.messages.last.content, 'The screen ');
      final id = partial.messages.last.id;
      final done = cubit.stream.firstWhere(
        (s) => s is ChatReady && !s.isProcessing,
      );
      finish.complete();
      await done;
      final completed = cubit.state as ChatReady;
      final assistant = completed.messages
          .where((m) => m.role == ChatMessageRole.assistant)
          .single;
      expect(assistant.id, id);
      expect(assistant.content, 'The screen is empty.');
      expect(completed.totalInputTokens, 10);
      final followup = cubit.stream.firstWhere(
        (s) => s is ChatReady && !s.isProcessing,
      );
      await cubit.sendMessage('Continue', settings);
      await followup;
      expect(
        (cubit.state as ChatReady).messages
            .where((m) => m.role == ChatMessageRole.assistant)
            .length,
        2,
      );
    },
  , tags: ['regression']);

  test(
    'Stop cancels in-flight model and late output cannot contaminate the next turn',
    () async {
      final started = Completer<void>();
      final cancelled = Completer<void>();
      final provider = _Provider([
        (messages, emit, cancel) async {
          emit('Partial');
          started.complete();
          await cancel!.whenCancelled;
          cancelled.complete();
          cancel.throwIfCancelled();
          return const LlmResponse(content: 'late', isComplete: true);
        },
        (messages, emit, cancel) async {
          expect(
            messages.where((m) => m.role == LlmRole.user).single.content,
            'New request',
          );
          emit('Fresh');
          return const LlmResponse(content: 'Fresh', isComplete: true);
        },
      ]);
      final cubit = ChatCubit(
        toolRegistry: registry,
        memoryService: memory,
        providerFactory: (_) => provider,
      );
      addTearDown(cubit.close);
      await cubit.sendMessage('Old request', settings);
      await started.future;
      cubit.cancelProcessing();
      await cancelled.future.timeout(const Duration(seconds: 2));
      final done = cubit.stream.firstWhere(
        (s) => s is ChatReady && !s.isProcessing,
      );
      await cubit.sendMessage('New request', settings);
      await done;
      expect((cubit.state as ChatReady).messages.last.content, 'Fresh');
      expect(
        (cubit.state as ChatReady).messages.any((m) => m.content == 'late'),
        isFalse,
      );
      verify(
        () => registry.cancelRemoteControl(),
      ).called(greaterThanOrEqualTo(1));
    },
  , tags: ['regression']);
}
