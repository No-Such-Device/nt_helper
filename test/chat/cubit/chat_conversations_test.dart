import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/conversation_store.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/mcp/tool_reference_store.dart';
import 'package:nt_helper/mcp/tool_registry.dart';

class _Memory extends Mock implements MemoryService {}

class _Registry extends Mock implements ToolRegistry {}

class _Provider extends LlmProvider {
  final List<String> answers;
  final requests = <List<LlmMessage>>[];
  _Provider(this.answers);
  @override
  String get displayName => 'Offline fixture';
  @override
  Future<int?> resolveContextWindowTokens() async => 200000;
  @override
  void dispose() {}
  @override
  Future<LlmResponse> sendMessages({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
  }) async {
    requests.add(List.of(messages));
    return LlmResponse(
      content: answers.removeAt(0),
      isComplete: true,
      usage: const LlmUsage(inputTokens: 100, outputTokens: 10),
    );
  }
}

class _Store implements ConversationStore {
  final FileConversationStore delegate;
  bool failWrites = false;
  Completer<void>? restoreGate;
  _Store(this.delegate);
  @override
  Future<StoredConversation?> loadActive() async {
    await restoreGate?.future;
    return delegate.loadActive();
  }

  @override
  Future<StoredConversation> load(String id) => delegate.load(id);
  @override
  Future<List<ConversationSummary>> list() => delegate.list();
  @override
  Future<void> save(StoredConversation saved) async {
    if (failWrites) throw const FileSystemException('Simulated full disk');
    await delegate.save(saved);
  }

  @override
  Future<void> activate(String id) => delegate.activate(id);
  @override
  Future<void> delete(String id) => delegate.delete(id);
}

void main() {
  const settings = ChatSettings(anthropicApiKey: 'not-a-real-key');
  late Directory directory;
  late _Store store;
  late _Memory memory;
  late _Registry registry;
  late ToolReferenceStore references;
  setUpAll(() {
    registerFallbackValue(<LlmMessage>[]);
    registerFallbackValue(<Map<String, dynamic>>[]);
    registerFallbackValue(<String, dynamic>{});
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'nt-chat-lifecycle-test-',
    );
    store = _Store(FileConversationStore(directory: directory));
    references = ToolReferenceStore();
    memory = _Memory();
    registry = _Registry();
    when(() => registry.entries).thenReturn([]);
    when(() => registry.cancelRemoteControl()).thenAnswer((_) async {});
    when(() => registry.dispose()).thenAnswer((_) async {});
    when(
      () => registry.exportReferenceSnapshot(),
    ).thenAnswer((_) => references.exportSnapshot());
    when(() => registry.restoreReferenceSnapshot(any())).thenAnswer((call) {
      references.restoreSnapshot(
        call.positionalArguments.single as List<Map<String, dynamic>>,
      );
    });
    when(() => memory.readMemory()).thenAnswer((_) async => '');
    when(() => memory.readDailyLogs()).thenAnswer((_) async => '');
    when(() => memory.saveSessionSnapshot(any())).thenAnswer((_) async {});
  });
  tearDown(() => directory.delete(recursive: true));

  ChatCubit create(_Provider provider, {void Function()? onFactory}) =>
      ChatCubit(
        toolRegistry: registry,
        memoryService: memory,
        conversationStore: store,
        providerFactory: (_) {
          onFactory?.call();
          return provider;
        },
      );
  Future<void> turn(ChatCubit cubit, String question, String answer) async {
    final done = cubit.stream.firstWhere(
      (s) =>
          s is ChatReady &&
          !s.isProcessing &&
          !s.isLoadingHistory &&
          s.messages.lastOrNull?.content == answer,
    );
    await cubit.sendMessage(question, settings);
    await done;
  }

  Future<void> seed({bool interrupted = false}) async {
    await store.save(
      StoredConversation(
        summary: ConversationSummary(
          id: 'saved',
          title: 'Saved fixture',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        messages: [
          ChatMessage.user('Set the value'),
          if (interrupted) ...[
            ChatMessage.toolCall(
              toolName: 'set_value',
              toolCallId: 'known',
              arguments: {'value': 7},
            ),
            ChatMessage.toolResult(
              toolName: 'set_value',
              toolCallId: 'known',
              result: '{"value":7,"success":true}',
            ),
            ChatMessage.toolCall(
              toolName: 'remote_control',
              toolCallId: 'uncertain',
              arguments: {'button': 1},
            ),
          ] else
            ChatMessage.assistant('Original answer'),
        ],
        history: [
          LlmMessage.user('Set the value'),
          if (interrupted)
            LlmMessage.assistantWithToolCalls([
              const LlmToolCall(
                id: 'known',
                name: 'set_value',
                arguments: {'value': 7},
              ),
              const LlmToolCall(
                id: 'uncertain',
                name: 'remote_control',
                arguments: {'button': 1},
              ),
            ])
          else
            LlmMessage.assistant('Original answer'),
        ],
        references: [
          {
            'id': 'ref_saved',
            'tool_name': 'get_data',
            'content': 'Saved large data',
          },
        ],
        promptCacheKey: 'saved-cache-key',
        interrupted: interrupted,
      ),
    );
    await store.activate('saved');
  }

  test(
    'saves final answer and restores exact UI IDs plus model context without a provider request',
    () async {
      final first = create(_Provider(['Answer A']));
      await first.historyReady;
      expect(await first.listConversations(), isEmpty);
      await turn(first, 'Question A', 'Answer A');
      final before = (first.state as ChatReady).messages
          .map((m) => m.toJson())
          .toList();
      final id = (first.state as ChatReady).conversationId;
      await first.close();
      final saved = (await store.loadActive())!;
      expect(saved.history.last.content, 'Answer A');
      expect(saved.interrupted, isFalse);
      expect(saved.summary.id, id);
      expect(saved.inputTokens, 100);
      var factories = 0;
      final provider = _Provider(['Answer B']);
      final restored = create(provider, onFactory: () => factories++);
      await restored.historyReady;
      expect(factories, 0);
      expect(provider.requests, isEmpty);
      expect(
        (restored.state as ChatReady).messages.map((m) => m.toJson()).toList(),
        before,
      );
      await turn(restored, 'Question B', 'Answer B');
      expect(
        provider.requests.single.map((m) => m.content),
        containsAllInOrder(['Question A', 'Answer A', 'Question B']),
      );
      verifyNever(() => registry.executeTool(any(), any()));
      await restored.close();
      expect((await store.loadActive())!.promptCacheKey, saved.promptCacheKey);
      expect((await store.loadActive())!.history.last.content, 'Answer B');
    },
  tags: ['regression']);

  test(
    'New chat archives, changes session key, and switching restores isolated history without replay',
    () async {
      var factories = 0;
      final provider = _Provider(['First answer', 'Second answer']);
      final cubit = create(provider, onFactory: () => factories++);
      await cubit.historyReady;
      await turn(cubit, 'First question', 'First answer');
      final firstId = (cubit.state as ChatReady).conversationId!;
      await cubit.newChat();
      final secondId = (cubit.state as ChatReady).conversationId!;
      expect(secondId, isNot(firstId));
      expect((cubit.state as ChatReady).messages, isEmpty);
      final firstKey = (await store.load(firstId)).promptCacheKey;
      expect((await store.load(secondId)).promptCacheKey, isNot(firstKey));
      await cubit.newChat(); // Avoid accumulating extra empty chats.
      expect((cubit.state as ChatReady).conversationId, secondId);
      await turn(cubit, 'Second question', 'Second answer');
      expect(provider.requests.last.map((m) => m.content), ['Second question']);
      await cubit.openConversation(firstId);
      expect(factories, 2);
      expect((cubit.state as ChatReady).messages.map((m) => m.content), [
        'First question',
        'First answer',
      ]);
      expect(
        (await cubit.listConversations()).map((s) => s.id),
        containsAll([firstId, secondId]),
      );
      expect(
        (await store.load(secondId)).history.last.content,
        'Second answer',
      );
      verifyNever(() => registry.executeTool(any(), any()));
      await cubit.close();
      expect((await store.loadActive())!.summary.id, firstId);
    },
  );

  test(
    'interrupted checkpoint is passive, retains receipts/references and labels unknown delivery',
    () async {
      await seed(interrupted: true);
      var factories = 0;
      final provider = _Provider(['I remember the recorded outcome.']);
      final cubit = create(provider, onFactory: () => factories++);
      await cubit.historyReady;
      expect(factories, 0);
      verifyNever(() => memory.readMemory());
      verifyNever(() => registry.executeTool(any(), any()));
      final state = cubit.state as ChatReady;
      expect(state.isProcessing, isFalse);
      expect(
        state.messages.last.content,
        contains('No commands were replayed'),
      );
      expect(
        state.messages
            .where(
              (m) =>
                  m.toolCallId == 'uncertain' &&
                  m.role == ChatMessageRole.toolResult,
            )
            .single
            .content,
        contains('"delivery":"unknown"'),
      );
      expect(
        await references.readReference({'reference_id': 'ref_saved'}),
        contains('Saved large data'),
      );
      await turn(
        cubit,
        'What was recorded?',
        'I remember the recorded outcome.',
      );
      expect(
        provider.requests.single.map((m) => m.content).join('\n'),
        contains('"value\\":7'),
      );
      expect(
        provider.requests.single.any((m) => m.toolCalls?.isNotEmpty ?? false),
        isFalse,
      );
      verifyNever(() => registry.executeTool(any(), any()));
      await cubit.close();
      final again = create(_Provider([]));
      await again.historyReady;
      expect(
        (again.state as ChatReady).messages
            .where(
              (m) =>
                  m.role == ChatMessageRole.system &&
                  m.content.contains('No commands were replayed'),
            )
            .length,
        1,
      );
      await again.close();
    },
  tags: ['regression']);

  test(
    'Clear chat deletes current checkpoint and makes an empty replacement active',
    () async {
      await seed();
      final cubit = create(_Provider([]));
      await cubit.historyReady;
      await cubit.clearChat();
      expect((cubit.state as ChatReady).messages, isEmpty);
      expect((await store.loadActive())!.summary.id, isNot('saved'));
      expect(await File('${directory.path}/saved.json').exists(), isFalse);
      expect(
        await File('${directory.path}/saved.summary.json').exists(),
        isFalse,
      );
      await cubit.close();
    },
  );

  test(
    'corrupt record is kept, blocked from accidental overwrite, and New chat recovers explicitly',
    () async {
      await seed();
      const original = '{broken saved history';
      final file = File('${directory.path}/saved.json');
      await file.writeAsString(original);
      var factories = 0;
      final cubit = create(_Provider([]), onFactory: () => factories++);
      await cubit.historyReady;
      expect((cubit.state as ChatReady).historyError, isNotNull);
      await cubit.sendMessage('Do not overwrite', settings);
      expect(factories, 0);
      expect(await file.readAsString(), original);
      await cubit.newChat();
      expect((cubit.state as ChatReady).historyError, isNull);
      expect((await store.loadActive())!.summary.id, isNot('saved'));
      expect(await file.readAsString(), original);
      await cubit.close();
    },
  tags: ['regression']);

  test(
    'save failure is visible, does not discard chat on New chat, and can be retried',
    () async {
      store.failWrites = true;
      final cubit = create(_Provider(['Still visible']));
      await cubit.historyReady;
      await turn(cubit, 'My unsaved question', 'Still visible');
      final id = (cubit.state as ChatReady).conversationId;
      await cubit.newChat();
      expect((cubit.state as ChatReady).conversationId, id);
      expect((cubit.state as ChatReady).messages.last.content, 'Still visible');
      expect((cubit.state as ChatReady).historyError, isNotNull);
      store.failWrites = false;
      await cubit.newChat();
      expect((cubit.state as ChatReady).historyError, isNull);
      expect((cubit.state as ChatReady).conversationId, isNot(id));
      expect((await store.load(id!)).history.last.content, 'Still visible');
      await cubit.close();
    },
  tags: ['regression']);

  test(
    'an old Cubit closing does not reactivate its chat over the newly selected one',
    () async {
      await seed();
      final previous = create(_Provider([]));
      await previous.historyReady;
      final replacement = create(_Provider([]));
      await replacement.historyReady;
      await replacement.newChat();
      final newId = (replacement.state as ChatReady).conversationId;
      await previous.close();
      expect((await store.loadActive())!.summary.id, newId);
      await replacement.close();
    },
  tags: ['regression']);

  test(
    'closing while restoration is pending cannot start a queued send or replace the active chat',
    () async {
      await seed();
      store.restoreGate = Completer<void>();
      var factories = 0;
      final cubit = create(_Provider([]), onFactory: () => factories++);
      final queuedSend = cubit.sendMessage('Queued during restore', settings);
      final closing = cubit.close();
      store.restoreGate!.complete();
      await closing;
      await queuedSend;
      expect(factories, 0);
      expect((await store.loadActive())!.summary.id, 'saved');
      expect(
        (await store.loadActive())!.history.last.content,
        'Original answer',
      );
      verifyNever(() => registry.executeTool(any(), any()));
    },
  tags: ['regression']);
}
