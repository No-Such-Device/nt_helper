import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:nt_helper/chat/services/conversation_store.dart';

StoredConversation checkpoint(
  String id, {
  String title = 'Saved chat',
  DateTime? updatedAt,
}) => StoredConversation(
  summary: ConversationSummary(
    id: id,
    title: title,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
  ),
  messages: [
    ChatMessage.user(
      'Read this',
      imageAttachments: [
        const ChatImageAttachment(
          data: 'AQID',
          mimeType: 'image/png',
          name: 'image.png',
        ),
      ],
      fileAttachments: [
        const ChatFileAttachment(
          name: 'notes.txt',
          data: 'YWJj',
          mimeType: 'text/plain',
          sizeBytes: 3,
          textContent: 'abc',
        ),
      ],
    ),
    ChatMessage.toolCall(
      toolName: 'show_screen',
      toolCallId: 'call-1',
      arguments: {},
    ),
    ChatMessage.toolResult(
      toolName: 'show_screen',
      toolCallId: 'call-1',
      result: 'screen',
      imageBase64: 'AQID',
      imageMimeType: 'image/png',
    ),
    ChatMessage.assistant('Done'),
    ChatMessage.system('A local note'),
  ],
  history: [
    LlmMessage.user(
      'Read this\nAttached notes.txt:\nabc',
      imageAttachments: [
        const LlmImageAttachment(
          data: 'AQID',
          mimeType: 'image/png',
          name: 'image.png',
        ),
      ],
      fileAttachments: [
        const LlmFileAttachment(
          name: 'manual.pdf',
          data: 'YWJj',
          mimeType: 'application/pdf',
          sizeBytes: 3,
        ),
      ],
    ),
    LlmMessage.assistantWithToolCalls([
      const LlmToolCall(
        id: 'call-1',
        name: 'show_screen',
        arguments: {},
        namespace: 'functions',
      ),
    ], content: 'Looking'),
    LlmMessage.toolResult(
      toolName: 'show_screen',
      toolCallId: 'call-1',
      content: 'screen',
      imageBase64: 'AQID',
      imageMimeType: 'image/png',
    ),
    LlmMessage.assistant('Done'),
  ],
  promptCacheKey: 'session-cache-key',
  inputTokens: 123,
  outputTokens: 45,
  contextTokens: 100,
  contextWindow: 200000,
  references: [
    {'id': 'ref_1', 'tool_name': 'get_data', 'content': 'large result'},
  ],
);

void main() {
  late Directory directory;
  late FileConversationStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nt-chat-store-test-');
    store = FileConversationStore(directory: directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'round trips UI, Genkit transcript, attachments, tool namespaces, references and usage',
    () async {
      final original = checkpoint('first');
      expect(await store.loadActive(), isNull);
      await store.save(original);
      await store.activate('first');
      final restored = (await store.loadActive())!;
      expect(
        restored.messages.map((m) => m.toJson()).toList(),
        original.messages.map((m) => m.toJson()).toList(),
      );
      expect(
        restored.history.map((m) => m.role),
        original.history.map((m) => m.role),
      );
      expect(restored.history.first.imageAttachments.single.data, 'AQID');
      expect(restored.messages.first.fileAttachments.single.textContent, 'abc');
      expect(restored.history.first.content, contains('abc'));
      expect(restored.history.first.fileAttachments.single.name, 'manual.pdf');
      expect(restored.history.first.fileAttachments.single.data, 'YWJj');
      expect(restored.history[1].toolCalls!.single.id, 'call-1');
      expect(restored.history[1].toolCalls!.single.namespace, 'functions');
      expect(restored.history[2].toolCallId, 'call-1');
      expect(restored.history[2].imageBase64, 'AQID');
      expect(restored.history.last.content, 'Done');
      expect(restored.promptCacheKey, 'session-cache-key');
      expect(restored.references, original.references);
      expect(restored.inputTokens, 123);
      expect(restored.outputTokens, 45);
      expect(restored.contextTokens, 100);
      expect(restored.contextWindow, 200000);
      final raw =
          jsonDecode(await File('${directory.path}/first.json').readAsString())
              as Map;
      expect(raw['genkit_state'], isA<Map>());
      expect(raw.containsKey('settings'), isFalse);
      expect(raw.containsKey('system_prompt'), isFalse);
      expect(
        raw.keys.where(
          (k) => '$k'.contains('api_key') || '$k'.contains('auth'),
        ),
        isEmpty,
      );
      expect(
        (await directory.list().toList()).where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test(
    'serialized concurrent saves leave a complete latest record and small sorted summaries',
    () async {
      await Future.wait(
        List.generate(
          6,
          (i) => store.save(
            checkpoint(
              'first',
              title: 'Revision $i',
              updatedAt: DateTime.utc(2026, 1, i + 1),
            ),
          ),
        ),
      );
      await store.save(
        checkpoint('second', updatedAt: DateTime.utc(2026, 2, 1)),
      );
      expect((await store.load('first')).summary.title, 'Revision 5');
      expect((await store.list()).map((s) => s.id), ['second', 'first']);
      final summary = await File(
        '${directory.path}/first.summary.json',
      ).readAsString();
      expect(summary, isNot(contains('AQID')));
      expect(summary.length, lessThan(400));
      await store.activate('second');
      await store.delete('first');
      expect((await store.list()).single.id, 'second');
      expect((await store.loadActive())!.summary.id, 'second');
      expect(await File('${directory.path}/first.json').exists(), isFalse);
    },
  , tags: ['regression']);

  test(
    'overlapping store instances serialize complete record and summary replacements',
    () async {
      final replacement = FileConversationStore(directory: directory);
      await Future.wait(
        List.generate(
          8,
          (i) => (i.isEven ? store : replacement).save(
            checkpoint('shared', title: 'Writer $i'),
          ),
        ),
      );
      final record = await store.load('shared');
      expect((await store.list()).single.title, record.summary.title);
      expect(record.history.last.content, 'Done');
      expect(
        (await directory.list().toList()).where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  , tags: ['regression']);

  test(
    'rejects unsafe IDs and corrupt/unsupported records without overwriting files',
    () async {
      await expectLater(store.load('../escape'), throwsFormatException);
      await expectLater(
        store.save(checkpoint('../escape')),
        throwsFormatException,
      );
      await store.save(checkpoint('first'));
      await store.activate('first');
      const corrupt = '{"version":999,"future":"keep this"}';
      final file = File('${directory.path}/first.json');
      await file.writeAsString(corrupt);
      await expectLater(store.loadActive(), throwsFormatException);
      expect(await file.readAsString(), corrupt);
    },
  , tags: ['regression']);
}
