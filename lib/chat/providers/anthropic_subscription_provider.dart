import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart';
import 'package:nt_helper/chat/providers/llm_error_handling.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/model_context_window.dart';
import 'package:nt_helper/services/debug_service.dart';

/// Anthropic subscription auth provider using Claude Code OAuth tokens.
///
/// Uses Bearer token auth instead of x-api-key, with required beta headers
/// for subscription access.
class AnthropicSubscriptionProvider
    with LlmErrorHandling
    implements LlmProvider {
  final String token;
  final String model;
  final http.Client _client;

  static const _baseUrl = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';
  static const _betaHeader =
      'claude-code-20250219,oauth-2025-04-20,'
      'fine-grained-tool-streaming-2025-05-14,'
      'interleaved-thinking-2025-05-14';
  static const _requiredSystemPrefix =
      'You are Claude Code, Anthropic\'s official CLI for Claude.';

  AnthropicSubscriptionProvider({
    required this.token,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  String get displayName => 'Claude Subscription ($model)';

  @override
  Future<int?> resolveContextWindowTokens() {
    return AnthropicContextWindowResolver.resolveWithBearerToken(
      model: model,
      token: token,
      apiVersion: _apiVersion,
      betaHeader: _betaHeader,
      client: _client,
    );
  }

  // Reuse the same message conversion and response parsing from AnthropicProvider
  // by delegating to a temporary instance.
  late final _delegate = AnthropicProvider(apiKey: '', model: model);

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
        _delegate.convertMessages(messages),
      ),
      'cache_control': anthropicLongCacheControl,
    };

    // Prepend required system prefix for subscription auth
    final fullSystemPrompt = systemPrompt != null
        ? '$_requiredSystemPrefix\n\n$systemPrompt'
        : _requiredSystemPrefix;
    body['system'] = [
      {
        'type': 'text',
        'text': fullSystemPrompt,
        'cache_control': anthropicLongCacheControl,
      },
    ];

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
        'Authorization': 'Bearer $token',
        'anthropic-version': _apiVersion,
        'anthropic-beta': _betaHeader,
        'user-agent': 'claude-cli/1.0.0 (external, cli)',
        'x-app': 'cli',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: jsonEncode(body),
    );

    DebugService().addLocalMessage(
      'Anthropic Subscription API response: ${response.statusCode} '
      '(${response.body.length} bytes)',
    );

    throwIfApiError(response, 'Anthropic Subscription API');

    try {
      return _delegate.parseResponse(jsonDecode(response.body));
    } on FormatException catch (e) {
      final preview = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      DebugService().addLocalMessage(
        'Anthropic Subscription response parse error: $e\nBody: $preview',
      );
      throw LlmApiException(
        'Failed to parse Anthropic Subscription response. '
        'Check Debug Log for details.',
      );
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    _client.close();
  }
}
