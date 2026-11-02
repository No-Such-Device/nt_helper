import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genkit/genkit.dart' show CancellationController;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/openai_provider.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart';
import 'package:nt_helper/chat/providers/anthropic_subscription_provider.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/provider_streaming.dart';

class _Client extends http.BaseClient {
  final frames = StreamController<List<int>>();
  final sent = Completer<http.AbortableRequest>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.complete(request as http.AbortableRequest);
    return http.StreamedResponse(
      frames.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void frame(Map<String, dynamic> event) =>
      frames.add(utf8.encode('data: ${jsonEncode(event)}\r\n\r\n'));
  @override
  void close() {
    unawaited(frames.close());
  }
}

void main() {
  test(
    'cancelling a real HTTP stream completes the provider request promptly',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = IOClient(HttpClient());
      final cancel = CancellationController();
      final sawDelta = Completer<void>();
      final openResponses = <HttpResponse>[];
      server.listen((request) async {
        await request.drain<void>();
        final response = request.response;
        response.bufferOutput = false;
        openResponses.add(response);
        unawaited(response.done.then<void>((_) {}, onError: (Object _) {}));
        response.headers.set('content-type', 'text/event-stream');
        response.write(
          'data: {"choices":[{"index":0,"delta":{"content":"partial"}}]}\n\n',
        );
        try {
          await response.flush();
        } catch (_) {
          /* Client cancelled. */
        }
      });
      final provider = OpenAIProvider(
        apiKey: 'test',
        model: 'test',
        baseUrl: 'http://127.0.0.1:${server.port}/chat',
        client: client,
      );
      try {
        final work = provider.sendMessagesStreaming(
          messages: [LlmMessage.user('hello')],
          tools: [],
          cancel: cancel.token,
          onTextDelta: (_) {
            if (!sawDelta.isCompleted) sawDelta.complete();
          },
        );
        // Install the error handler before cancellation can reject the request.
        final stopped = expectLater(work, throwsA(anything));
        await Future.any([
          sawDelta.future,
          work.then<void>(
            (_) => throw StateError('Stream completed before first delta'),
            onError: (Object e) =>
                throw StateError('Request failed before first delta: $e'),
          ),
        ]).timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw StateError('No first HTTP delta received'),
        );
        cancel.cancel('test stop');
        await stopped.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw StateError('HTTP abort did not complete'),
        );
      } finally {
        provider.dispose();
        for (final response in openResponses) {
          try {
            await response.close();
          } catch (_) {}
        }
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    },
  , tags: ['regression']);

  test(
    'OpenAI emits real text deltas before completion and assembles fragmented tools',
    () async {
      final client = _Client();
      final provider = OpenAIProvider(
        apiKey: 'test-key',
        model: 'test-model',
        client: client,
      );
      addTearDown(provider.dispose);
      final deltas = <String>[];
      final first = Completer<void>();
      var completed = false;
      final response = provider
          .sendMessagesStreaming(
            messages: [LlmMessage.user('inspect')],
            tools: [],
            onTextDelta: (delta) {
              deltas.add(delta);
              if (!first.isCompleted) first.complete();
            },
          )
          .then((value) {
            completed = true;
            return value;
          });
      final request = await client.sent.future;
      expect(jsonDecode(request.body)['stream'], isTrue);
      expect(request.headers['Authorization'], 'Bearer test-key');
      client.frame({
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Hello\u2028'},
          },
        ],
      });
      await first.future;
      expect(completed, isFalse);
      client.frame({
        'choices': [
          {
            'index': 0,
            'delta': {
              'content': 'world',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'c1',
                  'function': {'name': 'remote_state', 'arguments': '{"a":'},
                },
              ],
            },
          },
        ],
      });
      client.frame({
        'choices': [
          {
            'index': 0,
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '1}'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });
      client.frame({
        'choices': [],
        'usage': {
          'prompt_tokens': 20,
          'completion_tokens': 4,
          'prompt_tokens_details': {'cached_tokens': 8},
        },
      });
      client.frames.add(utf8.encode('data: [DONE]\n\n'));
      await client.frames.close();
      final result = await response;
      expect(deltas.join(), 'Hello\u2028world');
      expect(result.toolCalls.single.id, 'c1');
      expect(result.toolCalls.single.arguments, {'a': 1});
      expect(result.usage!.cacheReadInputTokens, 8);
      expect(result.usage!.contextInputTokens, 20);
    },
  , tags: ['regression']);

  for (final subscription in [false, true]) {
    test(
      'Anthropic ${subscription ? 'subscription' : 'API'} streams text/tools and preserves authentication',
      () async {
        final client = _Client();
        final StreamingLlmProvider provider = subscription
            ? AnthropicSubscriptionProvider(
                token: 'subscription-token',
                model: 'test-model',
                client: client,
              )
            : AnthropicProvider(
                apiKey: 'api-key',
                model: 'test-model',
                client: client,
              );
        addTearDown(provider.dispose);
        final first = Completer<void>();
        final deltas = <String>[];
        final future = provider.sendMessagesStreaming(
          messages: [LlmMessage.user('inspect')],
          tools: [],
          onTextDelta: (delta) {
            deltas.add(delta);
            if (!first.isCompleted) first.complete();
          },
        );
        final request = await client.sent.future;
        final body = jsonDecode(request.body);
        expect(body['stream'], isTrue);
        expect(body['cache_control']['ttl'], '1h');
        if (subscription) {
          expect(request.headers['Authorization'], 'Bearer subscription-token');
          expect(
            request.headers['anthropic-beta'],
            contains('oauth-2025-04-20'),
          );
          expect(body['system'][0]['text'], contains('You are Claude Code'));
        } else {
          expect(request.headers['x-api-key'], 'api-key');
        }
        client.frame({
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 12, 'cache_read_input_tokens': 8},
          },
        });
        client.frame({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        });
        client.frame({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Inspecting'},
        });
        await first.future;
        expect(deltas, ['Inspecting']);
        client.frame({
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'call1',
            'name': 'show_screen',
            'input': {},
          },
        });
        client.frame({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"foo":'},
        });
        client.frame({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '2}'},
        });
        client.frame({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 5},
        });
        client.frame({'type': 'message_stop'});
        await client.frames.close();
        final result = await future;
        expect(result.content, 'Inspecting');
        expect(result.toolCalls.single.arguments, {'foo': 2});
        expect(result.usage!.contextInputTokens, 20);
      },
    );
  }

  test('request cancellation reaches HTTP abortTrigger', () async {
    final client = _Client();
    final cancel = CancellationController();
    final future = sendStreamingRequest(
      client: client,
      url: Uri.parse('https://test.invalid'),
      headers: {},
      body: {},
      cancel: cancel.token,
    );
    final request = await client.sent.future;
    final response = await future;
    final drained = response.stream.drain<void>();
    cancel.cancel();
    await request.abortTrigger;
    await client.frames.close();
    await drained;
  });

  test(
    'premature stream EOF is a failure, not a successful blank answer',
    () async {
      final response = http.StreamedResponse(
        Stream.value(
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
      await expectLater(
        readOpenAIStream(
          response,
          onTextDelta: (_) {},
          parseJson: (_) => throw StateError('unexpected JSON'),
        ),
        throwsA(isA<LlmApiException>()),
      );
    },
  , tags: ['regression']);
}
