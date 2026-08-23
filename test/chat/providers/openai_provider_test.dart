import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart'
    show LlmApiException;
import 'package:nt_helper/chat/providers/openai_provider.dart';

void main() {
  group('OpenAIProvider parsing', () {
    test('sends a stable prompt cache key to the official API', () async {
      Map<String, dynamic>? capturedBody;
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5.6',
        promptCacheKey: 'chat-session-123',
        client: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
          );
        }),
      );

      await provider.sendMessages(
        messages: [LlmMessage.user('Hi')],
        tools: const [],
      );

      expect(capturedBody!['prompt_cache_key'], 'chat-session-123');
    });

    test(
      'does not send OpenAI-only cache fields to compatible proxies',
      () async {
        Map<String, dynamic>? capturedBody;
        final provider = OpenAIProvider(
          apiKey: 'test-key',
          model: 'local-model',
          baseUrl: 'http://localhost:1234/v1/chat/completions',
          promptCacheKey: 'chat-session-123',
          client: MockClient((request) async {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'ok'},
                    'finish_reason': 'stop',
                  },
                ],
              }),
              200,
            );
          }),
        );

        await provider.sendMessages(
          messages: [LlmMessage.user('Hi')],
          tools: const [],
        );

        expect(capturedBody!.containsKey('prompt_cache_key'), isFalse);
      },
    );

    test('parses prompt cache read and write telemetry', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5.6',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'ok'},
                  'finish_reason': 'stop',
                },
              ],
              'usage': {
                'prompt_tokens': 2500,
                'completion_tokens': 10,
                'prompt_tokens_details': {
                  'cached_tokens': 2000,
                  'cache_write_tokens': 400,
                },
              },
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hi')],
        tools: const [],
      );

      expect(response.usage?.cacheReadInputTokens, 2000);
      expect(response.usage?.cacheCreationInputTokens, 400);
      expect(response.usage?.contextInputTokens, 2500);
    });

    test('accepts tool arguments returned as an object', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'search_algorithms',
                          'arguments': {'query': 'lfo'},
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
              'usage': {'prompt_tokens': 12, 'completion_tokens': 5},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Find LFO algorithms')],
        tools: const [],
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls, hasLength(1));
      expect(response.toolCalls.single.name, 'search_algorithms');
      expect(response.toolCalls.single.arguments, {'query': 'lfo'});
      expect(response.isComplete, isFalse);
    });

    test('concatenates text when content is returned as parts array', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': [
                      {'type': 'text', 'text': 'Hello '},
                      {'type': 'text', 'text': 'world'},
                    ],
                  },
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 3, 'completion_tokens': 2},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Say hello')],
        tools: const [],
      );

      expect(response.content, 'Hello world');
      expect(response.hasToolCalls, isFalse);
      expect(response.isComplete, isTrue);
    });

    test('treats non-object decoded tool arguments as empty object', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_2',
                        'type': 'function',
                        'function': {'name': 'show_preset', 'arguments': '[]'},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Show preset')],
        tools: const [],
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.single.arguments, isEmpty);
    });

    test('treats null tool arguments as empty map', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_3',
                        'type': 'function',
                        'function': {'name': 'show_preset', 'arguments': null},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Show preset')],
        tools: const [],
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.single.arguments, isEmpty);
    });

    test('treats empty string tool arguments as empty map', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'tool_calls': [
                      {
                        'id': 'call_4',
                        'type': 'function',
                        'function': {'name': 'show_preset', 'arguments': ''},
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Show preset')],
        tools: const [],
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.single.arguments, isEmpty);
    });

    test('returns null content when content is null', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'call_5',
                        'type': 'function',
                        'function': {
                          'name': 'search_algorithms',
                          'arguments': '{"query":"lfo"}',
                        },
                      },
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
              'usage': {'prompt_tokens': 10, 'completion_tokens': 3},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Find LFO')],
        tools: const [],
      );

      expect(response.content, isNull);
      expect(response.hasToolCalls, isTrue);
    });

    test('returns empty string content when content is empty string', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': ''},
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 5, 'completion_tokens': 0},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.content, '');
    });

    test('extracts text from content returned as Map with text key', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': {'type': 'text', 'text': 'Hello from map'},
                  },
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 5, 'completion_tokens': 3},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.content, 'Hello from map');
    });

    test('returns null content when content is Map without text key', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': {'type': 'image', 'url': 'http://example.com'},
                  },
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': 5, 'completion_tokens': 1},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.content, isNull);
    });

    test('converts non-String Map keys in tool arguments to strings', () async {
      final rawJson =
          '{"choices":[{"message":{"role":"assistant",'
          '"tool_calls":[{"id":"call_6","type":"function",'
          '"function":{"name":"search_algorithms",'
          '"arguments":{"query":"lfo"}}}]},'
          '"finish_reason":"tool_calls"}],'
          '"usage":{"prompt_tokens":10,"completion_tokens":3}}';

      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(rawJson, 200);
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Find LFO')],
        tools: const [],
      );

      expect(response.hasToolCalls, isTrue);
      expect(response.toolCalls.single.arguments, isA<Map<String, dynamic>>());
      expect(response.toolCalls.single.arguments['query'], 'lfo');
    });

    test('throws LlmApiException on non-200 status', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Rate limit exceeded', 'type': 'rate_limit'},
            }),
            429,
          );
        }),
      );

      expect(
        () => provider.sendMessages(
          messages: [LlmMessage.user('Hello')],
          tools: const [],
        ),
        throwsA(
          isA<LlmApiException>()
              .having(
                (e) => e.message,
                'message',
                contains('Rate limit exceeded'),
              )
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.isRateLimited, 'isRateLimited', true),
        ),
      );
    });

    test('throws LlmApiException on malformed JSON response body', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response('not valid json {{{', 200);
        }),
      );

      expect(
        () => provider.sendMessages(
          messages: [LlmMessage.user('Hello')],
          tools: const [],
        ),
        throwsA(
          isA<LlmApiException>().having(
            (e) => e.message,
            'message',
            contains('Failed to parse OpenAI response body'),
          ),
        ),
      );
    });

    test('handles null choices key gracefully', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'id': 'chatcmpl-xxx',
              'object': 'chat.completion',
              'choices': null,
              'usage': {'prompt_tokens': 5, 'completion_tokens': 0},
            }),
            200,
          );
        }),
      );

      // Should not throw TypeError — should either return a valid response
      // or throw LlmApiException.
      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.isComplete, isTrue);
    });

    test('handles missing choices key gracefully', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'id': 'chatcmpl-xxx',
              'object': 'chat.completion',
              'usage': {'prompt_tokens': 5, 'completion_tokens': 0},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.isComplete, isTrue);
    });

    test('handles usage values returned as strings from proxies', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Hello!'},
                  'finish_reason': 'stop',
                },
              ],
              'usage': {'prompt_tokens': '42', 'completion_tokens': '7'},
            }),
            200,
          );
        }),
      );

      // Should not throw TypeError — proxy usage values may be strings.
      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.content, 'Hello!');
      expect(response.usage, isNotNull);
      expect(response.usage!.inputTokens, 42);
      expect(response.usage!.outputTokens, 7);
    });

    test('handles empty choices array', () async {
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'gpt-5-nano',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [],
              'usage': {'prompt_tokens': 5, 'completion_tokens': 0},
            }),
            200,
          );
        }),
      );

      final response = await provider.sendMessages(
        messages: [LlmMessage.user('Hello')],
        tools: const [],
      );

      expect(response.isComplete, isTrue);
      expect(response.content, isNull);
    });
  });
}
