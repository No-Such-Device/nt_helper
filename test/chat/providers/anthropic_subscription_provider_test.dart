import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_subscription_provider.dart';

void main() {
  test(
    'uses one-hour cache controls across the stable Pi-style prefix',
    () async {
      Map<String, dynamic>? capturedBody;
      final provider = AnthropicSubscriptionProvider(
        token: 'subscription-token',
        model: 'claude-sonnet-4-20250514',
        client: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Done'},
              ],
              'stop_reason': 'end_turn',
              'usage': {'input_tokens': 10, 'output_tokens': 2},
            }),
            200,
          );
        }),
      );
      addTearDown(provider.dispose);

      await provider.sendMessages(
        messages: [LlmMessage.user('Rename this preset')],
        tools: const [
          LlmToolDefinition(
            name: 'rename_preset',
            description: 'Rename without replacing preset contents.',
            inputSchema: {
              'properties': {
                'name': {'type': 'string'},
              },
            },
          ),
        ],
        systemPrompt: 'Stable nt_helper instructions.',
      );

      expect(capturedBody!['cache_control'], {
        'type': 'ephemeral',
        'ttl': '1h',
      });
      final system = capturedBody!['system'] as List<dynamic>;
      expect(system.single['cache_control'], {
        'type': 'ephemeral',
        'ttl': '1h',
      });
      final tools = capturedBody!['tools'] as List<dynamic>;
      expect(tools.single['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
      final messages = capturedBody!['messages'] as List<dynamic>;
      final content = messages.single['content'] as List<dynamic>;
      expect(content.last['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
    },
  );
}
