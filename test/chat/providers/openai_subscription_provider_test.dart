import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/openai_subscription_provider.dart';
import 'package:nt_helper/chat/services/codex_auth_service.dart';

class _FakeAuthService extends CodexAuthService {
  int refreshCount = 0;
  CodexAuthSnapshot snapshot;

  _FakeAuthService(this.snapshot) : super(authFilePath: 'unused');

  @override
  Future<CodexAuthSnapshot> loadAuth() async => snapshot;

  @override
  Future<CodexAuthSnapshot> refreshAuth() async {
    refreshCount++;
    snapshot = const CodexAuthSnapshot(
      accessToken: 'new-token',
      refreshToken: 'new-refresh',
      accountId: 'new-account',
    );
    return snapshot;
  }

  @override
  void dispose() {}
}

class _QueueClient extends http.BaseClient {
  final List<http.StreamedResponse Function(http.BaseRequest request)>
  responses;
  final requests = <http.Request>[];

  _QueueClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    return responses.removeAt(0)(request);
  }
}

void main() {
  group('OpenAISubscriptionProvider', () {
    test('resolves context window from Codex models endpoint', () async {
      final auth = _FakeAuthService(
        const CodexAuthSnapshot(
          accessToken: 'token',
          refreshToken: 'refresh',
          accountId: 'account',
        ),
      );
      final client = _QueueClient([
        (_) => _jsonResponse({
          'models': [
            {'slug': 'gpt-5.5', 'context_window': 272000},
          ],
        }),
      ]);
      final provider = OpenAISubscriptionProvider(
        model: 'gpt-5.5',
        allowAuthRefresh: false,
        authService: auth,
        client: client,
      );
      addTearDown(provider.dispose);

      final contextWindow = await provider.resolveContextWindowTokens();

      expect(contextWindow, 272000);
      expect(client.requests.single.method, 'GET');
      expect(
        client.requests.single.url.toString(),
        'https://chatgpt.com/backend-api/codex/models?model=gpt-5.5&client_version=0.135.0',
      );
      expect(client.requests.single.headers['Authorization'], 'Bearer token');
      expect(client.requests.single.headers['ChatGPT-Account-ID'], 'account');
    });

    test('parses text, tool calls, and usage from Responses SSE', () async {
      final auth = _FakeAuthService(
        const CodexAuthSnapshot(
          accessToken: 'token',
          refreshToken: 'refresh',
          accountId: 'account',
        ),
      );
      final client = _QueueClient([
        (_) => _sseResponse([
          {'type': 'response.output_text.delta', 'delta': 'thinking '},
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'function_call',
              'call_id': 'call_1',
              'name': 'show_preset',
              'arguments': '{"slot":1}',
            },
          },
          {
            'type': 'response.completed',
            'response': {
              'usage': {
                'input_tokens': 10,
                'output_tokens': 2,
                'input_tokens_details': {
                  'cached_tokens': 8,
                  'cache_write_tokens': 1,
                },
              },
            },
          },
        ]),
      ]);
      final provider = OpenAISubscriptionProvider(
        model: 'gpt-5.4-mini',
        allowAuthRefresh: false,
        promptCacheKey: 'chat-session-123',
        authService: auth,
        client: client,
      );
      addTearDown(provider.dispose);

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('hello')],
        tools: const [
          LlmToolDefinition(
            name: 'show_preset',
            description: 'Show preset',
            inputSchema: {
              'properties': {
                'slot': {'type': 'integer'},
              },
            },
          ),
        ],
      );

      expect(response.content, 'thinking ');
      expect(response.isComplete, isFalse);
      expect(response.toolCalls, hasLength(1));
      expect(response.toolCalls.single.id, 'call_1');
      expect(response.toolCalls.single.name, 'show_preset');
      expect(response.toolCalls.single.arguments, {'slot': 1});
      expect(response.usage?.inputTokens, 10);
      expect(response.usage?.outputTokens, 2);
      expect(response.usage?.cacheReadInputTokens, 8);
      expect(response.usage?.cacheCreationInputTokens, 1);
      expect(response.usage?.contextInputTokens, 10);

      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-5.4-mini');
      expect(body['stream'], isTrue);
      expect(body['prompt_cache_key'], 'chat-session-123');
      expect((body['tools'] as List).single['type'], 'function');
      expect(client.requests.single.headers['Authorization'], 'Bearer token');
      expect(client.requests.single.headers['ChatGPT-Account-ID'], 'account');
    });

    test('refreshes on 401 and retries once when allowed', () async {
      final auth = _FakeAuthService(
        const CodexAuthSnapshot(
          accessToken: 'old-token',
          refreshToken: 'old-refresh',
          accountId: 'old-account',
        ),
      );
      final client = _QueueClient([
        (_) => _textResponse(401, '{"error":{"message":"expired"}}'),
        (_) => _sseResponse([
          {'type': 'response.output_text.delta', 'delta': 'ok'},
          {
            'type': 'response.completed',
            'response': {
              'usage': {'input_tokens': 1, 'output_tokens': 1},
            },
          },
        ]),
      ]);
      final provider = OpenAISubscriptionProvider(
        model: 'gpt-5.4-mini',
        allowAuthRefresh: true,
        authService: auth,
        client: client,
      );
      addTearDown(provider.dispose);

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('hello')],
        tools: const [],
      );

      expect(response.content, 'ok');
      expect(auth.refreshCount, 1);
      expect(client.requests, hasLength(2));
      expect(
        client.requests.first.headers['Authorization'],
        'Bearer old-token',
      );
      expect(client.requests.last.headers['Authorization'], 'Bearer new-token');
    });

    test(
      'sends PDFs as input files but leaves text attachments inline',
      () async {
        final auth = _FakeAuthService(
          const CodexAuthSnapshot(
            accessToken: 'token',
            refreshToken: 'refresh',
            accountId: 'account',
          ),
        );
        final client = _QueueClient([
          (_) => _sseResponse([
            {'type': 'response.output_text.delta', 'delta': 'ok'},
          ]),
        ]);
        final provider = OpenAISubscriptionProvider(
          model: 'gpt-5.4-mini',
          allowAuthRefresh: false,
          authService: auth,
          client: client,
        );
        addTearDown(provider.dispose);

        await provider.sendMessages(
          messages: [
            LlmMessage.user(
              '--- Attached file: notes.txt ---\nhello\n'
              '--- Attached file: extracted.pdf ---\nmanual text',
              fileAttachments: const [
                LlmFileAttachment(
                  name: 'notes.txt',
                  data: 'aGVsbG8=',
                  mimeType: 'text/plain',
                  sizeBytes: 5,
                  textContent: 'hello',
                ),
                LlmFileAttachment(
                  name: 'manual.pdf',
                  data: 'JVBERi0xLjQ=',
                  mimeType: 'application/pdf',
                  sizeBytes: 8,
                ),
                LlmFileAttachment(
                  name: 'extracted.pdf',
                  data: 'JVBERi0xLjQ=',
                  mimeType: 'application/pdf',
                  sizeBytes: 8,
                  textContent: 'manual text',
                ),
              ],
            ),
          ],
          tools: const [],
        );

        final body =
            jsonDecode(client.requests.single.body) as Map<String, dynamic>;
        final input = body['input'] as List<dynamic>;
        final content = input.single['content'] as List<dynamic>;
        final inputFiles = content
            .whereType<Map<String, dynamic>>()
            .where((part) => part['type'] == 'input_file')
            .toList();

        expect(inputFiles, hasLength(1));
        expect(inputFiles.single['filename'], 'manual.pdf');
        expect(
          inputFiles.map((file) => file['filename']),
          isNot(contains('extracted.pdf')),
        );
        expect(
          content.whereType<Map<String, dynamic>>().singleWhere(
            (part) => part['type'] == 'input_text',
          )['text'],
          contains('notes.txt'),
        );
      },
    );
  });
}

http.StreamedResponse _sseResponse(List<Map<String, dynamic>> events) {
  final body = events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();
  return _textResponse(200, body);
}

http.StreamedResponse _jsonResponse(Map<String, dynamic> body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

http.StreamedResponse _textResponse(int statusCode, String body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: const {'content-type': 'text/event-stream'},
  );
}
