import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart'
    show LlmApiException;
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/model_context_window.dart';
import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:nt_helper/services/debug_service.dart';

class OpenAISubscriptionProvider implements LlmProvider {
  final String model;
  final bool allowAuthRefresh;
  final String promptCacheKey;
  final CodexAuthService authService;
  final http.Client _client;

  static const _baseUrl = 'https://chatgpt.com/backend-api/codex/responses';
  static const _clientVersion = '0.135.0';

  OpenAISubscriptionProvider({
    required this.model,
    required this.allowAuthRefresh,
    this.promptCacheKey = 'nt_helper_chat',
    CodexAuthService? authService,
    http.Client? client,
  }) : authService = authService ?? CodexAuthService(client: client),
       _client = client ?? http.Client();

  @override
  String get displayName => 'OpenAI Subscription ($model)';

  @override
  Future<int?> resolveContextWindowTokens() async {
    try {
      final auth = await authService.loadAuth();
      return OpenAIContextWindowResolver.resolveSubscription(
        model: model,
        headers: {'version': _clientVersion, ...auth.authHeaders},
        client: _client,
        clientVersion: _clientVersion,
        baseUrl: _baseUrl,
      );
    } on Object {
      return OpenAIContextWindowResolver.inferSubscription(model);
    }
  }

  @override
  Future<LlmResponse> sendMessages({
    required List<LlmMessage> messages,
    required List<LlmToolDefinition> tools,
    String? systemPrompt,
  }) async {
    var auth = await authService.loadAuth();
    var response = await _sendRequest(auth, messages, tools, systemPrompt);

    if (response.statusCode == 401 && allowAuthRefresh) {
      auth = await authService.refreshAuth();
      response = await _sendRequest(auth, messages, tools, systemPrompt);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      _throwResponseError(response.statusCode, body);
    }

    DebugService().addLocalMessage(
      'OpenAI Subscription API response: ${response.statusCode}',
    );

    return _parseEventStream(response.stream);
  }

  Future<http.StreamedResponse> _sendRequest(
    CodexAuthSnapshot auth,
    List<LlmMessage> messages,
    List<LlmToolDefinition> tools,
    String? systemPrompt,
  ) async {
    final request = http.Request('POST', Uri.parse(_baseUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'version': _clientVersion,
      ...auth.authHeaders,
    });
    request.body = jsonEncode({
      'model': model,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'instructions': systemPrompt,
      'input': _convertMessages(messages),
      'tools': _convertTools(tools),
      'tool_choice': 'auto',
      'parallel_tool_calls': false,
      'reasoning': null,
      'store': false,
      'stream': true,
      'include': const <String>[],
      'prompt_cache_key': promptCacheKey,
    });
    return _client.send(request);
  }

  List<Map<String, dynamic>> _convertMessages(List<LlmMessage> messages) {
    final result = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case LlmRole.user:
          result.add({
            'type': 'message',
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': msg.content ?? ''},
              for (final image in msg.imageAttachments)
                {
                  'type': 'input_image',
                  'image_url': 'data:${image.mimeType};base64,${image.data}',
                },
              for (final file in msg.fileAttachments)
                if (file.textContent == null &&
                    _isCodexFileInput(file.mimeType))
                  {
                    'type': 'input_file',
                    'filename': file.name,
                    'file_data': 'data:${file.mimeType};base64,${file.data}',
                  },
            ],
          });
          break;
        case LlmRole.assistant:
          final content = msg.content;
          if (content != null && content.isNotEmpty) {
            result.add({
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': content},
              ],
            });
          }
          for (final toolCall in msg.toolCalls ?? const <LlmToolCall>[]) {
            result.add({
              'type': 'function_call',
              'name': toolCall.name,
              'arguments': jsonEncode(toolCall.arguments),
              'call_id': toolCall.id,
            });
          }
          break;
        case LlmRole.tool:
          result.add({
            'type': 'function_call_output',
            'call_id': msg.toolCallId,
            'output': msg.content ?? '',
          });
          if (msg.hasImage) {
            result.add({
              'type': 'message',
              'role': 'user',
              'content': [
                {
                  'type': 'input_text',
                  'text':
                      'Here is the screenshot from the ${msg.toolName} tool:',
                },
                {
                  'type': 'input_image',
                  'image_url':
                      'data:${msg.imageMimeType};base64,${msg.imageBase64}',
                },
              ],
            });
          }
          break;
      }
    }

    return result;
  }

  List<Map<String, dynamic>> _convertTools(List<LlmToolDefinition> tools) {
    return tools
        .map(
          (tool) => {
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': {'type': 'object', ...tool.inputSchema},
          },
        )
        .toList();
  }

  bool _isCodexFileInput(String mimeType) {
    return mimeType == 'application/pdf';
  }

  Future<LlmResponse> _parseEventStream(Stream<List<int>> stream) async {
    final textBuffer = StringBuffer();
    final toolCalls = <LlmToolCall>[];
    LlmUsage? usage;
    var sawTextDelta = false;

    await for (final data in _sseData(stream)) {
      if (data == '[DONE]') break;
      final event = jsonDecode(data) as Map<String, dynamic>;
      final type = event['type'] as String?;

      switch (type) {
        case 'response.output_text.delta':
          final delta = event['delta'];
          if (delta is String) {
            sawTextDelta = true;
            textBuffer.write(delta);
          }
          break;
        case 'response.output_item.done':
          final item = event['item'];
          if (item is Map<String, dynamic>) {
            _parseDoneItem(item, toolCalls, textBuffer, sawTextDelta);
          }
          break;
        case 'response.completed':
          usage = _parseUsage(event['response']);
          break;
        case 'response.failed':
          throw LlmApiException(_responseFailureMessage(event));
      }
    }

    final content = textBuffer.toString();
    return LlmResponse(
      content: content.isEmpty ? null : content,
      toolCalls: toolCalls,
      isComplete: toolCalls.isEmpty,
      usage: usage,
    );
  }

  void _parseDoneItem(
    Map<String, dynamic> item,
    List<LlmToolCall> toolCalls,
    StringBuffer textBuffer,
    bool sawTextDelta,
  ) {
    switch (item['type']) {
      case 'function_call':
        final name = item['name'];
        final callId = item['call_id'];
        if (name is String && callId is String) {
          toolCalls.add(
            LlmToolCall(
              id: callId,
              name: name,
              arguments: _parseArguments(item['arguments']),
            ),
          );
        }
        break;
      case 'message':
        if (!sawTextDelta) {
          for (final text in _contentTexts(item['content'])) {
            textBuffer.write(text);
          }
        }
        break;
    }
  }

  static Map<String, dynamic> _parseArguments(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return const {};
  }

  static Iterable<String> _contentTexts(Object? rawContent) sync* {
    if (rawContent is! List) return;
    for (final part in rawContent) {
      if (part is! Map) continue;
      final text = part['text'];
      if (text is String) yield text;
    }
  }

  static LlmUsage? _parseUsage(Object? rawResponse) {
    if (rawResponse is! Map) return null;
    final usage = rawResponse['usage'];
    if (usage is! Map) return null;
    final inputTokens = _intField(usage['input_tokens']);
    final inputTokenDetails = usage['input_tokens_details'] as Map?;
    return LlmUsage(
      inputTokens: inputTokens,
      outputTokens: _intField(usage['output_tokens']),
      cacheCreationInputTokens: _intField(
        inputTokenDetails?['cache_write_tokens'],
      ),
      cacheReadInputTokens: _intField(inputTokenDetails?['cached_tokens']),
      // OpenAI's input_tokens already includes cached tokens.
      peakInputTokens: inputTokens,
    );
  }

  static int _intField(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Stream<String> _sseData(Stream<List<int>> stream) async* {
    final lines = stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final dataLines = <String>[];

    await for (final line in lines) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          yield dataLines.join('\n');
          dataLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isNotEmpty) yield dataLines.join('\n');
  }

  Never _throwResponseError(int statusCode, String body) {
    String message = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        message =
            decoded['error']?['message'] as String? ??
            decoded['detail'] as String? ??
            body;
      }
    } on FormatException {
      // Keep raw body.
    }
    throw LlmApiException(
      'OpenAI Subscription API error ($statusCode): $message',
      statusCode: statusCode,
    );
  }

  String _responseFailureMessage(Map<String, dynamic> event) {
    final response = event['response'];
    if (response is Map<String, dynamic>) {
      final error = response['error'];
      if (error is Map<String, dynamic>) {
        return error['message'] as String? ?? 'OpenAI Subscription failed.';
      }
    }
    return 'OpenAI Subscription failed.';
  }

  @override
  void dispose() {
    _client.close();
    authService.dispose();
  }
}
