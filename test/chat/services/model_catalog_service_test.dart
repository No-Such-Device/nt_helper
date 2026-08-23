import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';

class _FakeAuthService extends CodexAuthService {
  final CodexAuthSnapshot snapshot;

  _FakeAuthService(this.snapshot) : super(authFilePath: 'unused');

  @override
  Future<CodexAuthSnapshot> loadAuth() async => snapshot;

  @override
  void dispose() {}
}

void main() {
  group('OpenAI subscription model catalog', () {
    test('parses visible models in server order', () {
      final models = OpenAISubscriptionModelCatalog.parseModels({
        'models': [
          {
            'slug': 'gpt-current',
            'display_name': 'GPT Current',
            'context_window': 272000,
          },
          {'slug': 'internal-model', 'visibility': 'hide'},
          {'slug': 'gpt-current', 'display_name': 'Duplicate'},
          {'id': 'gpt-next', 'max_input_tokens': '400000'},
        ],
      });

      expect(models.map((model) => model.id), ['gpt-current', 'gpt-next']);
      expect(models.first.displayName, 'GPT Current');
      expect(models.first.contextWindowTokens, 272000);
      expect(models.last.contextWindowTokens, 400000);
    });

    test('uses Codex subscription endpoint and account auth', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'models': [
              {'slug': 'gpt-subscription'},
            ],
          }),
          200,
        );
      });
      final auth = _FakeAuthService(
        const CodexAuthSnapshot(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          accountId: 'account-id',
        ),
      );
      final catalog = OpenAISubscriptionModelCatalog(
        authService: auth,
        client: client,
        modelsUri: Uri.parse('https://example.test/backend-api/codex/models'),
      );
      addTearDown(catalog.dispose);

      final models = await catalog.fetchModels(allowAuthRefresh: false);

      expect(models.single.id, 'gpt-subscription');
      expect(
        captured.url.toString(),
        'https://example.test/backend-api/codex/models?client_version=0.135.0',
      );
      expect(captured.headers['Authorization'], 'Bearer access-token');
      expect(captured.headers['ChatGPT-Account-ID'], 'account-id');
      expect(captured.headers['version'], '0.135.0');
    });
  });

  group('OpenAI API model catalog', () {
    test('discovers models beside a custom chat completions URL', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'local-model'},
            ],
          }),
          200,
        );
      });
      final catalog = OpenAIModelCatalog(
        apiKey: 'local-key',
        baseUrl: 'http://localhost:1234/v1/chat/completions',
        client: client,
      );
      addTearDown(catalog.dispose);

      final models = await catalog.fetchModels();

      expect(captured.url.toString(), 'http://localhost:1234/v1/models');
      expect(captured.headers['Authorization'], 'Bearer local-key');
      expect(models.single.id, 'local-model');
    });
  });

  group('Anthropic model catalog', () {
    test('uses the models endpoint with API key auth', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'claude-current',
                'display_name': 'Claude Current',
                'max_input_tokens': 200000,
              },
            ],
          }),
          200,
        );
      });
      final catalog = AnthropicModelCatalog(
        credential: 'anthropic-key',
        subscriptionAuth: false,
        client: client,
      );
      addTearDown(catalog.dispose);

      final models = await catalog.fetchModels();

      expect(
        captured.url.toString(),
        'https://api.anthropic.com/v1/models?limit=1000',
      );
      expect(captured.headers['x-api-key'], 'anthropic-key');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(models.single.id, 'claude-current');
      expect(models.single.displayName, 'Claude Current');
    });
  });
}
