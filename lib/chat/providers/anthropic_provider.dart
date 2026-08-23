import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/llm_error_handling.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/model_context_window.dart';
import 'package:nt_helper/services/debug_service.dart';

const anthropicLongCacheControl = <String, String>{
  'type': 'ephemeral',
  'ttl': '1h',
};

/// Anthropic Claude Messages API provider.
class AnthropicProvider with LlmErrorHandling implements LlmProvider {
  final String apiKey;
  final String model;
  final http.Client _client;

  static const _baseUrl = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

  AnthropicProvider({
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get displayName => 'Claude ($model)';

  @override
  Future<int?> resolveContextWindowTokens() {
    return AnthropicContextWindowResolver.resolveWithApiKey(
      model: model,
      apiKey: apiKey,
      apiVersion: _apiVersion,
      client: _client,
    );
  }

  @override
  Future<LlmResponse> sendMessages({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': withAnthropicRollingCacheBreakpoint(
        convertMessages(messages),
      ),
      // Automatic caching advances the rolling history breakpoint on every
      // agentic-loop request. Explicit system/tool breakpoints below preserve
      // reusable fallbacks when a turn adds many content blocks.
      'cache_control': anthropicLongCacheControl,
    };

    if (systemPrompt != null) {
      body['system'] = [
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': anthropicLongCacheControl,
        },
      ];
    }

    if (tools.isNotEmpty) {
      final toolsList = tools
          .map(
            (t) => <String, dynamic>{
              'name': t.name,
              'description': t.description,
              'input_schema': {'type': 'object', ...t.inputSchema},
            },
          )
          .toList();
      toolsList.last['cache_control'] = anthropicLongCacheControl;
      body['tools'] = toolsList;
    }

    final response = await _client.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _apiVersion,
      },
      body: jsonEncode(body),
    );

    DebugService().addLocalMessage(
      'Anthropic API response: ${response.statusCode} '
      '(${response.body.length} bytes)',
    );

    throwIfApiError(response, 'Anthropic API');

    try {
      return parseResponse(jsonDecode(response.body));
    } on FormatException catch (e) {
      final preview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      DebugService().addLocalMessage(
        'Anthropic response parse error: $e\nBody: $preview',
      );
      throw LlmApiException(
        'Failed to parse Anthropic response. Check Debug Log for details.',
      );
    }
  }

  List<Map<String, dynamic>> convertMessages(List<LlmMessage> messages) {
    final result = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LlmRole.user:
          if (msg.hasImageAttachments || msg.hasFileAttachments) {
            result.add({
              'role': 'user',
              'content': <dynamic>[
                {'type': 'text', 'text': msg.content ?? ''},
                for (final image in msg.imageAttachments)
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': image.mimeType,
                      'data': image.data,
                    },
                  },
                for (final file in msg.fileAttachments)
                  if (file.textContent == null &&
                      file.mimeType == 'application/pdf')
                    {
                      'type': 'document',
                      'source': {
                        'type': 'base64',
                        'media_type': file.mimeType,
                        'data': file.data,
                      },
                      'title': file.name,
                    },
              ],
            });
          } else {
            result.add({'role': 'user', 'content': msg.content!});
          }
        case LlmRole.assistant:
          if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
            final content = <Map<String, dynamic>>[];
            if (msg.content != null && msg.content!.isNotEmpty) {
              content.add({'type': 'text', 'text': msg.content!});
            }
            for (final tc in msg.toolCalls!) {
              content.add({
                'type': 'tool_use',
                'id': tc.id,
                'name': tc.name,
                'input': tc.arguments,
              });
            }
            result.add({'role': 'assistant', 'content': content});
          } else {
            result.add({'role': 'assistant', 'content': msg.content ?? ''});
          }
        case LlmRole.tool:
          final dynamic toolContent;
          if (msg.hasImage) {
            toolContent = <dynamic>[
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': msg.imageMimeType!,
                  'data': msg.imageBase64!,
                },
              },
              {'type': 'text', 'text': msg.content!},
            ];
          } else {
            toolContent = msg.content!;
          }
          final toolResultBlock = {
            'type': 'tool_result',
            'tool_use_id': msg.toolCallId!,
            'content': toolContent,
          };
          if (result.isNotEmpty && result.last['role'] == 'user') {
            final lastContent = result.last['content'];
            if (lastContent is List<dynamic>) {
              lastContent.add(toolResultBlock);
              continue;
            }
          }
          result.add({
            'role': 'user',
            'content': <dynamic>[toolResultBlock],
          });
      }
    }

    return result;
  }

  LlmResponse parseResponse(Map<String, dynamic> json) {
    final stopReason = json['stop_reason'] as String?;
    final content = json['content'] as List<dynamic>? ?? [];
    final usage = json['usage'] as Map<String, dynamic>?;

    String? textContent;
    final toolCalls = <LlmToolCall>[];

    for (final block in content) {
      final type = block['type'] as String;
      if (type == 'text') {
        textContent = (textContent ?? '') + (block['text'] as String);
      } else if (type == 'tool_use') {
        toolCalls.add(
          LlmToolCall(
            id: block['id'] as String,
            name: block['name'] as String,
            arguments: block['input'] as Map<String, dynamic>,
          ),
        );
      }
    }

    if (usage != null) {
      final cacheCreation = usage['cache_creation_input_tokens'] as int? ?? 0;
      final cacheRead = usage['cache_read_input_tokens'] as int? ?? 0;
      if (cacheCreation > 0 || cacheRead > 0) {
        DebugService().addLocalMessage(
          'Cache: $cacheCreation created, $cacheRead read, '
          '${usage['input_tokens'] ?? 0} uncached input',
        );
      }
    }

    return LlmResponse(
      content: textContent,
      toolCalls: toolCalls,
      isComplete: stopReason != 'tool_use',
      usage: usage != null
          ? LlmUsage(
              inputTokens: usage['input_tokens'] as int? ?? 0,
              outputTokens: usage['output_tokens'] as int? ?? 0,
              cacheCreationInputTokens:
                  usage['cache_creation_input_tokens'] as int? ?? 0,
              cacheReadInputTokens:
                  usage['cache_read_input_tokens'] as int? ?? 0,
            )
          : null,
    );
  }

  @override
  void dispose() {
    _client.close();
  }
}

/// Adds the explicit rolling-history breakpoint used by the Pi harness.
///
/// Anthropic's top-level automatic cache control remains enabled as a forward
/// moving cache. This explicit breakpoint provides the same system, tools,
/// and latest-user-message fallback layout used by Substrate's Pi adapter.
List<Map<String, dynamic>> withAnthropicRollingCacheBreakpoint(
  List<Map<String, dynamic>> messages,
) {
  final result = messages
      .map((message) => Map<String, dynamic>.of(message))
      .toList(growable: false);

  for (var index = result.length - 1; index >= 0; index--) {
    final message = result[index];
    if (message['role'] != 'user') continue;

    final content = message['content'];
    if (content is String) {
      message['content'] = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text': content,
          'cache_control': anthropicLongCacheControl,
        },
      ];
      break;
    }
    if (content is List && content.isNotEmpty) {
      final blocks = List<dynamic>.of(content);
      final last = blocks.last;
      if (last is Map) {
        blocks[blocks.length - 1] = <String, dynamic>{
          ...last.cast<String, dynamic>(),
          'cache_control': anthropicLongCacheControl,
        };
        message['content'] = blocks;
        break;
      }
    }
  }

  return result;
}

class LlmApiException implements Exception {
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  LlmApiException(this.message, {this.statusCode, this.retryAfterSeconds});

  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}
