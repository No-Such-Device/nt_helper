import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/openai_subscription_provider.dart';
import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:nt_helper/chat/services/codex_client_version_service.dart';
import 'package:nt_helper/chat/services/codex_model_metadata_service.dart';

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

class _FakeCodexClientVersionService extends CodexClientVersionService {
  _FakeCodexClientVersionService()
    : super(versionFilePath: '/unused/version.json');

  @override
  Future<String> resolve() async => '9.8.7';
}

class _FakeCodexModelMetadataService extends CodexModelMetadataService {
  final bool lite;

  _FakeCodexModelMetadataService({required this.lite})
    : super(modelsCachePath: '/unused/models_cache.json');

  @override
  Future<bool> useResponsesLite(String model) async => lite;
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
    for (final lite in [false, true]) {
      test(
        'streams Codex ${lite ? 'Responses Lite' : 'Responses'} without losing auth or cache identity',
        () async {
          final frames = StreamController<List<int>>();
          final requestSent = Completer<void>();
          final firstDelta = Completer<void>();
          final auth = _FakeAuthService(
            const CodexAuthSnapshot(
              accessToken: 'token',
              refreshToken: 'refresh',
              accountId: 'account',
            ),
          );
          final client = _QueueClient([
            (_) {
              requestSent.complete();
              return http.StreamedResponse(
                frames.stream,
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            },
          ]);
          final provider = OpenAISubscriptionProvider(
            model: 'gpt-5.5',
            allowAuthRefresh: false,
            authService: auth,
            clientVersionService: _FakeCodexClientVersionService(),
            modelMetadataService: _FakeCodexModelMetadataService(lite: lite),
            client: client,
            promptCacheKey: 'stable-session',
          );
          addTearDown(provider.dispose);
          var completed = false;
          final deltas = <String>[];
          final work = provider
              .sendMessagesStreaming(
                messages: [LlmMessage.user('inspect')],
                tools: [],
                systemPrompt: 'NT assistant',
                onTextDelta: (delta) {
                  deltas.add(delta);
                  if (!firstDelta.isCompleted) firstDelta.complete();
                },
              )
              .then((result) {
                completed = true;
                return result;
              });
          await requestSent.future;
          void frame(Map<String, dynamic> event) =>
              frames.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
          frame({'type': 'response.output_text.delta', 'delta': 'Inspecting'});
          await firstDelta.future;
          expect(completed, isFalse);
          frame({
            'type': 'response.output_item.done',
            'item': {
              'type': 'function_call',
              'name': 'show_screen',
              'namespace': 'functions',
              'call_id': 'c1',
              'arguments': '{}',
            },
          });
          frame({
            'type': 'response.completed',
            'response': {
              'usage': {'input_tokens': 12, 'output_tokens': 3},
            },
          });
          await frames.close();
          final result = await work;
          expect(deltas, ['Inspecting']);
          expect(result.toolCalls.single.namespace, 'functions');
          expect(result.usage!.inputTokens, 12);
          final request = client.requests.single;
          expect(request.headers['Authorization'], 'Bearer token');
          expect(request.headers['ChatGPT-Account-ID'], 'account');
          final body = jsonDecode(request.body);
          expect(body['prompt_cache_key'], 'stable-session');
          expect(body['parallel_tool_calls'], false);
          if (lite) {
            expect(body['input'][0]['type'], 'additional_tools');
            expect(
              request.headers['x-openai-internal-codex-responses-lite'],
              'true',
            );
          } else {
            expect(body['instructions'], 'NT assistant');
          }
        },
      );
    }

    test(
      'unsupported subscription models explain how to choose an available model',
      () async {
        final auth = _FakeAuthService(
          const CodexAuthSnapshot(
            accessToken: 'token',
            refreshToken: 'refresh',
            accountId: 'account',
          ),
        );
        final client = _QueueClient([
          (_) => _textResponse(
            400,
            jsonEncode({
              'error': {
                'message': 'This model is not supported for this account.',
              },
            }),
          ),
        ]);
        final provider = OpenAISubscriptionProvider(
          model: 'unavailable',
          allowAuthRefresh: false,
          authService: auth,
          clientVersionService: _FakeCodexClientVersionService(),
          modelMetadataService: _FakeCodexModelMetadataService(lite: false),
          client: client,
        );
        addTearDown(provider.dispose);
        await expectLater(
          provider.sendMessages(
            messages: [LlmMessage.user('hello')],
            tools: [],
          ),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('Open Chat settings') &&
                  error.toString().contains('subscription model list'),
            ),
          ),
        );
      },
    );

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
        clientVersionService: _FakeCodexClientVersionService(),
        modelMetadataService: _FakeCodexModelMetadataService(lite: false),
        client: client,
      );
      addTearDown(provider.dispose);

      final contextWindow = await provider.resolveContextWindowTokens();

      expect(contextWindow, 272000);
      expect(client.requests.single.method, 'GET');
      expect(
        client.requests.single.url.toString(),
        'https://chatgpt.com/backend-api/codex/models?model=gpt-5.5&client_version=9.8.7',
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
        clientVersionService: _FakeCodexClientVersionService(),
        modelMetadataService: _FakeCodexModelMetadataService(lite: false),
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
      expect(client.requests.single.headers['version'], '9.8.7');
      expect(
        client
            .requests
            .single
            .headers['x-openai-internal-codex-responses-lite'],
        isNull,
      );
    });

    test(
      'uses the model-driven Responses Lite contract for gpt-5.6-sol',
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
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'function_call',
                'call_id': 'call_lite',
                'namespace': 'functions',
                'name': 'show_preset',
                'arguments': '{"slot":1}',
              },
            },
          ]),
          (_) => _sseResponse([
            {'type': 'response.output_text.delta', 'delta': 'done'},
          ]),
        ]);
        final provider = OpenAISubscriptionProvider(
          model: 'gpt-5.6-sol',
          allowAuthRefresh: false,
          promptCacheKey: 'chat-session-123',
          authService: auth,
          clientVersionService: _FakeCodexClientVersionService(),
          modelMetadataService: _FakeCodexModelMetadataService(lite: true),
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
          systemPrompt: 'Stable nt_helper instructions.',
        );

        final request = client.requests.single;
        expect(
          request.headers['x-openai-internal-codex-responses-lite'],
          'true',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, isNot(contains('instructions')));
        expect(body, isNot(contains('tools')));
        expect(body['reasoning'], {'context': 'all_turns'});
        final input = body['input'] as List<dynamic>;
        expect(input.first['type'], 'additional_tools');
        expect(input.first['role'], 'developer');
        final namespace = input.first['tools'].single as Map<String, dynamic>;
        expect(namespace['type'], 'namespace');
        expect(namespace['name'], 'functions');
        expect(namespace['tools'].single['name'], 'show_preset');
        expect(input[1]['role'], 'developer');
        expect(
          input[1]['content'].single['text'],
          'Stable nt_helper instructions.',
        );
        expect(input[2]['role'], 'user');
        expect(response.toolCalls.single.name, 'show_preset');
        expect(response.toolCalls.single.namespace, 'functions');
        expect(response.toolCalls.single.arguments, {'slot': 1});

        await provider.sendMessages(
          messages: [
            LlmMessage.user('hello'),
            LlmMessage.assistantWithToolCalls(response.toolCalls),
            LlmMessage.toolResult(
              toolCallId: 'call_lite',
              toolName: 'show_preset',
              content: '{"name":"test"}',
            ),
          ],
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
          systemPrompt: 'Stable nt_helper instructions.',
        );

        final nextBody =
            jsonDecode(client.requests.last.body) as Map<String, dynamic>;
        final nextInput = nextBody['input'] as List<dynamic>;
        final priorCall = nextInput.singleWhere(
          (item) => item['type'] == 'function_call',
        );
        expect(priorCall['namespace'], 'functions');
      },
    , tags: ['regression']);

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
        clientVersionService: _FakeCodexClientVersionService(),
        modelMetadataService: _FakeCodexModelMetadataService(lite: false),
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
          clientVersionService: _FakeCodexClientVersionService(),
          modelMetadataService: _FakeCodexModelMetadataService(lite: false),
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
    , tags: ['regression']);
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
