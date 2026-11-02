import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/models/additional_provider_config.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:nt_helper/chat/providers/openai_endpoint.dart';
import 'package:nt_helper/chat/providers/openai_provider.dart';
import 'package:nt_helper/chat/providers/openai_provider_metadata.dart';
import 'package:nt_helper/chat/services/chat_provider_factory.dart';
import 'package:nt_helper/chat/services/chat_service.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/mcp/tool_registry.dart';

class _Registry extends Mock implements ToolRegistry {}

String sse(Map<String, dynamic> delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    })}\n\n';

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));
  test(
    'endpoint roots, full paths and IPv6 normalize without changing host',
    () {
      for (final pair in {
        'http://localhost:1234': 'http://localhost:1234/v1/chat/completions',
        'http://127.0.0.1:11434/v1/':
            'http://127.0.0.1:11434/v1/chat/completions',
        'https://example.test/api/v1':
            'https://example.test/api/v1/chat/completions',
        'http://[::1]:1234/v1/chat/completions':
            'http://[::1]:1234/v1/chat/completions',
      }.entries) {
        expect(chatCompletionsUri(pair.key).toString(), pair.value);
      }
      expect(compatibleModelsUri('http://localhost:1234').path, '/v1/models');
      for (final invalid in [
        'file:///private',
        'https://user:secret@server/v1',
        'https://server/v1?api_key=secret',
        'https://server/#fragment',
      ]) {
        expect(() => chatCompletionsUri(invalid), throwsFormatException);
      }
    },
  );

  for (final type in [
    LlmProviderType.gemini,
    LlmProviderType.openrouter,
    LlmProviderType.local,
  ]) {
    test(
      '${type.name}: Genkit streaming tool/image loop preserves scoped metadata through saved history',
      () async {
        var count = 0;
        final registry = _Registry();
        when(() => registry.entries).thenReturn([
          ToolRegistryEntry(
            name: 'show_screen',
            description: 'Read the screen',
            inputSchema: {'properties': {}},
            handler: (_) async => 'unused',
          ),
        ]);
        when(() => registry.executeTool('show_screen', any())).thenAnswer(
          (_) async => jsonEncode({'type': 'image/png', 'data': 'AQID'}),
        );
        when(() => registry.cancelRemoteControl()).thenAnswer((_) async {});
        final model = 'fixture-${type.name}';
        final endpoint = switch (type) {
          LlmProviderType.gemini => geminiChatUrl,
          LlmProviderType.openrouter => openRouterChatUrl,
          _ => 'http://127.0.0.1:11434/v1/chat/completions',
        };
        final client = MockClient((request) async {
          count++;
          expect(request.url.toString(), endpoint);
          expect(
            request.headers['authorization'],
            type == LlmProviderType.local ? isNull : 'Bearer ${type.name}-key',
          );
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], model);
          expect(body.containsKey('prompt_cache_key'), isFalse);
          expect(body.containsKey('stream_options'), isFalse);
          if (type == LlmProviderType.openrouter) {
            expect(body['provider'], {'require_parameters': true});
          }
          if (count == 1) {
            return http.Response(
              sse({
                    if (type == LlmProviderType.openrouter)
                      'reasoning_details': [
                        {
                          'index': 0,
                          'type': 'reasoning.encrypted',
                          'data': 'partA',
                        },
                      ],
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call-1',
                        'type': 'function',
                        'function': {'name': 'show_screen', 'arguments': '{'},
                        if (type == LlmProviderType.gemini)
                          'extra_content': {
                            'google': {'thought_signature': 'signed-thought'},
                          },
                      },
                    ],
                  }) +
                  sse({
                    if (type == LlmProviderType.openrouter)
                      'reasoning_details': [
                        {
                          'index': 0,
                          'type': 'reasoning.encrypted',
                          'data': 'partB',
                        },
                      ],
                    'tool_calls': [
                      {
                        'index': 0,
                        'function': {'arguments': '}'},
                      },
                    ],
                  }, finish: 'tool_calls'),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }
          final messages = body['messages'] as List;
          final assistant =
              messages.firstWhere((m) => m['tool_calls'] != null) as Map;
          final call = (assistant['tool_calls'] as List).single as Map;
          expect(call['id'], 'call-1');
          if (type == LlmProviderType.gemini) {
            expect(call['extra_content'], {
              'google': {'thought_signature': 'signed-thought'},
            });
          }
          if (type == LlmProviderType.openrouter) {
            expect(
              (assistant['reasoning_details'] as List).single['data'],
              'partApartB',
            );
          }
          final tool = messages.firstWhere((m) => m['role'] == 'tool') as Map;
          expect(tool['tool_call_id'], 'call-1');
          final image = messages.last as Map;
          expect(image['role'], 'user');
          expect(
            (image['content'] as List).last['image_url']['url'],
            'data:image/png;base64,AQID',
          );
          return http.Response(
            sse({'content': 'Screen read.'}, finish: 'stop'),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        });
        final settings = ChatSettings(
          provider: type,
          openaiApiKey: 'do-not-forward-openai',
          anthropicApiKey: 'do-not-forward-claude',
          additionalProviders: {
            type: AdditionalProviderConfig(
              apiKey: type == LlmProviderType.local ? '' : '${type.name}-key',
              model: model,
              baseUrl: defaultLocalBaseUrl,
              contextWindowTokens: 64000,
            ),
          },
        );
        expect(settings.hasApiKey, isTrue);
        final provider =
            createChatProvider(
                  settings,
                  promptCacheKey: 'private-cache-key',
                  client: client,
                )
                as OpenAIProvider;
        addTearDown(provider.dispose);
        expect(await provider.resolveContextWindowTokens(), 64000);
        final chat = ChatService(
          provider: provider,
          toolBridge: ToolBridgeService(registry),
          systemPrompt: 'Only observe.',
        );
        final events = await chat.runAgenticLoop([
          LlmMessage.user('Read the screen'),
        ]).toList();
        expect(count, 2);
        verify(() => registry.executeTool('show_screen', any())).called(1);
        final finalEvent = events.whereType<ChatLoopAssistantMessage>().last;
        expect(finalEvent.content, 'Screen read.');
        expect(finalEvent.isFinal, isTrue);
        final saved = StoredConversation(
          summary: ConversationSummary(
            id: 'fixture',
            title: 'fixture',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          messages: [],
          history: finalEvent.finalHistory!,
          promptCacheKey: 'private-cache-key',
        );
        final json = jsonEncode(saved.toJson());
        expect(json, isNot(contains('do-not-forward-openai')));
        if (type != LlmProviderType.local) {
          expect(json, isNot(contains('${type.name}-key')));
        }
        final restored = StoredConversation.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );
        final history = restored.history.firstWhere(
          (m) => m.toolCalls?.isNotEmpty ?? false,
        );
        final metadata = type == LlmProviderType.gemini
            ? history.toolCalls!.single.providerMetadata
            : history.providerMetadata;
        if (type != LlmProviderType.local) {
          expect(openAIFieldsFor(metadata, endpoint, model), isNotEmpty);
          expect(
            openAIFieldsFor(
              metadata,
              'https://different.test/v1/chat/completions',
              model,
            ),
            isEmpty,
          );
          expect(openAIFieldsFor(metadata, endpoint, 'other-model'), isEmpty);
        }
      },
    , tags: ['regression']);
  }
}
