import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart'
    show LlmApiException;
import 'package:nt_helper/chat/providers/llm_error_handling.dart';
import 'package:nt_helper/chat/providers/model_context_window.dart';
import 'package:nt_helper/services/debug_service.dart';

/// OpenAI Chat Completions API provider.
class OpenAIProvider with LlmErrorHandling implements LlmProvider {
  final String apiKey;
  final String model;
  final String baseUrl;
  final String? promptCacheKey;
  final http.Client _client;

  static const _defaultBaseUrl = 'https://api.openai.com/v1/chat/completions';

  OpenAIProvider({
    required this.apiKey,
    required this.model,
    String? baseUrl,
    this.promptCacheKey,
    http.Client? client,
  }) : baseUrl = baseUrl ?? _defaultBaseUrl,
       _client = client ?? http.Client();

  @override
  String get displayName => 'OpenAI ($model)';

  @override
  Future<int?> resolveContextWindowTokens() {
    return OpenAIContextWindowResolver.resolve(
      model: model,
      baseUrl: baseUrl,
      apiKey: apiKey,
      client: _client,
    );
  }

  @override
  Future<LlmResponse> sendMessages({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
  }) async {
    final apiMessages = <Map<String, dynamic>>[];

    if (systemPrompt != null) {
      apiMessages.add({'role': 'system', 'content': systemPrompt});
    }

    apiMessages.addAll(_convertMessages(messages));

    final body = <String, dynamic>{'model': model, 'messages': apiMessages};

    if (promptCacheKey != null && _isOfficialOpenAIEndpoint) {
      body['prompt_cache_key'] = promptCacheKey;
    }

    if (tools.isNotEmpty) {
      body['tools'] = tools
          .map(
            (t) => {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': {'type': 'object', ...t.inputSchema},
              },
            },
          )
          .toList();
    }

    final response = await _client.post(
      Uri.parse(baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );

    DebugService().addLocalMessage(
      'OpenAI API response: ${response.statusCode} '
      '(${response.body.length} bytes) from $baseUrl',
    );

    throwIfApiError(response, 'OpenAI API');

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(response.body.trim()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      final preview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      DebugService().addLocalMessage(
        'OpenAI response body parse error: $e\nBody: $preview',
      );
      throw LlmApiException(
        'Failed to parse OpenAI response body. Check Debug Log for details.',
      );
    }

    try {
      return _parseResponse(parsed);
    } on Object catch (e) {
      final raw = jsonEncode(parsed);
      final preview = raw.length > 500 ? '${raw.substring(0, 500)}...' : raw;
      DebugService().addLocalMessage(
        'OpenAI response content error: $e\nRaw: $preview',
      );
      throw LlmApiException(
        'Failed to parse OpenAI response content (likely malformed tool call arguments): $e',
      );
    }
  }

  List<Map<String, dynamic>> _convertMessages(List<LlmMessage> messages) {
    final result = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LlmRole.user:
          if (msg.hasImageAttachments) {
            result.add({
              'role': 'user',
              'content': <dynamic>[
                {'type': 'text', 'text': msg.content ?? ''},
                for (final image in msg.imageAttachments)
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:${image.mimeType};base64,${image.data}',
                    },
                  },
              ],
            });
          } else {
            result.add({'role': 'user', 'content': msg.content!});
          }
        case LlmRole.assistant:
          if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
            final apiMsg = <String, dynamic>{'role': 'assistant'};
            if (msg.content != null && msg.content!.isNotEmpty) {
              apiMsg['content'] = msg.content!;
            }
            apiMsg['tool_calls'] = msg.toolCalls!
                .map(
                  (tc) => {
                    'id': tc.id,
                    'type': 'function',
                    'function': {
                      'name': tc.name,
                      'arguments': jsonEncode(tc.arguments),
                    },
                  },
                )
                .toList();
            result.add(apiMsg);
          } else {
            result.add({'role': 'assistant', 'content': msg.content ?? ''});
          }
        case LlmRole.tool:
          result.add({
            'role': 'tool',
            'tool_call_id': msg.toolCallId!,
            'content': msg.content!,
          });
          if (msg.hasImage) {
            result.add({
              'role': 'user',
              'content': <dynamic>[
                {
                  'type': 'text',
                  'text':
                      'Here is the screenshot from the ${msg.toolName} tool:',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url':
                        'data:${msg.imageMimeType};base64,${msg.imageBase64}',
                  },
                },
              ],
            });
          }
      }
    }

    return result;
  }

  LlmResponse _parseResponse(Map<String, dynamic> json) {
    final rawChoices = json['choices'];
    final choices = rawChoices is List<dynamic> ? rawChoices : <dynamic>[];
    if (choices.isEmpty) {
      return const LlmResponse(isComplete: true);
    }

    final choice = choices[0] as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String?;
    final usage = json['usage'] as Map<String, dynamic>?;
    final promptTokenDetails = usage?['prompt_tokens_details'] as Map?;
    final promptTokens = usage != null
        ? _parseIntField(usage['prompt_tokens'])
        : 0;

    final textContent = _parseTextContent(message['content']);
    final toolCalls = <LlmToolCall>[];

    final rawToolCalls = message['tool_calls'] as List<dynamic>?;
    if (rawToolCalls != null) {
      for (final tc in rawToolCalls) {
        final function = tc['function'] as Map<String, dynamic>;
        final args = _parseToolArguments(function['arguments']);
        toolCalls.add(
          LlmToolCall(
            id: tc['id'] as String,
            name: function['name'] as String,
            arguments: args,
          ),
        );
      }
    }

    return LlmResponse(
      content: textContent,
      toolCalls: toolCalls,
      isComplete: finishReason != 'tool_calls',
      usage: usage != null
          ? LlmUsage(
              inputTokens: promptTokens,
              outputTokens: _parseIntField(usage['completion_tokens']),
              cacheCreationInputTokens: _parseIntField(
                promptTokenDetails?['cache_write_tokens'],
              ),
              cacheReadInputTokens: _parseIntField(
                promptTokenDetails?['cached_tokens'],
              ),
              // OpenAI's prompt_tokens already includes cached tokens.
              peakInputTokens: promptTokens,
            )
          : null,
    );
  }

  bool get _isOfficialOpenAIEndpoint {
    return Uri.tryParse(baseUrl)?.host == 'api.openai.com';
  }

  /// Parse a field that should be an int but may arrive as a String from
  /// some OpenAI-compatible proxies.
  static int _parseIntField(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String? _parseTextContent(dynamic rawContent) {
    if (rawContent == null) return null;
    if (rawContent is String) return rawContent;

    // Some OpenAI-compatible proxies return content as parts.
    if (rawContent is List<dynamic>) {
      final buffer = StringBuffer();
      for (final part in rawContent) {
        if (part is! Map) continue;
        final text = part['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
      final combined = buffer.toString();
      return combined.isEmpty ? null : combined;
    }

    if (rawContent is Map<String, dynamic>) {
      final text = rawContent['text'];
      return text is String ? text : null;
    }

    return null;
  }

  static Map<String, dynamic> _parseToolArguments(dynamic rawArguments) {
    if (rawArguments == null) return {};
    if (rawArguments is Map<String, dynamic>) return rawArguments;
    if (rawArguments is Map) {
      return rawArguments.map((key, value) => MapEntry(key.toString(), value));
    }

    if (rawArguments is String) {
      final trimmed = rawArguments.trim();
      if (trimmed.isEmpty) return {};
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return {};
    }

    return {};
  }

  @override
  void dispose() {
    _client.close();
  }
}
