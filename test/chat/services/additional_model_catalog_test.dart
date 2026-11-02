import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nt_helper/chat/models/additional_provider_config.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/providers/openai_endpoint.dart';
import 'package:nt_helper/chat/services/gemini_model_catalog.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Gemini discovery paginates, authenticates in headers, filters generation models and preserves context limits',
    () async {
      var requests = 0;
      final catalog = GeminiModelCatalog(
        apiKey: 'google-key',
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'generativelanguage.googleapis.com');
          expect(request.url.path, '/v1beta/models');
          expect(request.url.toString(), isNot(contains('google-key')));
          expect(request.headers['x-goog-api-key'], 'google-key');
          expect(request.headers['authorization'], isNull);
          return http.Response(
            jsonEncode(
              requests == 1
                  ? {
                      'models': [
                        {
                          'name': 'models/gemini-a',
                          'displayName': 'Gemini A',
                          'inputTokenLimit': 1000000,
                          'supportedGenerationMethods': ['generateContent'],
                        },
                        {
                          'name': 'models/embedding',
                          'supportedGenerationMethods': ['embedContent'],
                        },
                      ],
                      'nextPageToken': 'next',
                    }
                  : {
                      'models': [
                        {
                          'name': 'models/gemini-a',
                          'supportedGenerationMethods': ['generateContent'],
                        },
                        {
                          'name': 'models/gemini-b',
                          'inputTokenLimit': 200000,
                          'supportedGenerationMethods': ['generateContent'],
                        },
                      ],
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(catalog.dispose);
      final models = await catalog.fetchModels();
      expect(requests, 2);
      expect(models.map((m) => m.id), ['gemini-a', 'gemini-b']);
      expect(models.first.displayName, 'Gemini A');
      expect(models.first.contextWindowTokens, 1000000);
    },
  );
  test(
    'Gemini rejects cyclic pagination and reports HTTP errors without echoing credentials',
    () async {
      var requests = 0;
      final cyclic = GeminiModelCatalog(
        apiKey: 'private-key',
        client: MockClient((_) async {
          requests++;
          return http.Response('{"models":[],"nextPageToken":"same"}', 200);
        }),
      );
      addTearDown(cyclic.dispose);
      await expectLater(
        cyclic.fetchModels(),
        throwsA(isA<ModelCatalogException>()),
      );
      expect(requests, 2);
      final denied = GeminiModelCatalog(
        apiKey: 'private-key',
        client: MockClient((_) async => http.Response('private-key', 401)),
      );
      addTearDown(denied.dispose);
      await expectLater(
        denied.fetchModels(),
        throwsA(
          isA<ModelCatalogException>().having(
            (e) => e.message,
            'safe error',
            allOf(contains('401'), isNot(contains('private-key'))),
          ),
        ),
      );
    },
  tags: ['regression']);
  test(
    'OpenRouter catalog keeps declared tool-capable models, names and context lengths',
    () async {
      final catalog = OpenAIModelCatalog(
        apiKey: 'router-key',
        baseUrl: openRouterChatUrl,
        providerLabel: 'OpenRouter',
        requireTools: true,
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://openrouter.ai/api/v1/models');
          expect(request.headers['authorization'], 'Bearer router-key');
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'vendor/chat',
                  'name': 'Chat model',
                  'context_length': 131072,
                  'supported_parameters': ['tools', 'temperature'],
                },
                {
                  'id': 'vendor/text-only',
                  'supported_parameters': ['temperature'],
                },
                {'id': 'vendor/unknown'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(catalog.dispose);
      final models = await catalog.fetchModels();
      expect(models.map((m) => m.id), ['vendor/chat', 'vendor/unknown']);
      expect(models.first.displayName, 'Chat model');
      expect(models.first.contextWindowTokens, 131072);
    },
  );
  test(
    'local model discovery does not invent an Authorization header',
    () async {
      final catalog = OpenAIModelCatalog(
        apiKey: '',
        baseUrl: chatCompletionsUri('http://localhost:1234').toString(),
        client: MockClient((request) async {
          expect(request.url.toString(), 'http://localhost:1234/v1/models');
          expect(request.headers['authorization'], isNull);
          return http.Response('{"data":[{"id":"local-model"}]}', 200);
        }),
      );
      addTearDown(catalog.dispose);
      expect((await catalog.fetchModels()).single.id, 'local-model');
    },
  tags: ['regression']);
  test(
    'provider settings round trip independently without altering legacy auth or endpoint',
    () async {
      SharedPreferences.setMockInitialValues({
        'anthropic_api_key': 'claude-token',
        'openai_api_key': 'openai-key',
        'openai_base_url': 'http://legacy:1234/v1/chat/completions',
      });
      final settings = SettingsService();
      await settings.init();
      final configs = {
        LlmProviderType.gemini: const AdditionalProviderConfig(
          apiKey: 'gemini-key',
          model: 'gemini-model',
          contextWindowTokens: 1000000,
        ),
        LlmProviderType.openrouter: const AdditionalProviderConfig(
          apiKey: 'router-key',
          model: 'vendor/model',
        ),
        LlmProviderType.local: const AdditionalProviderConfig(
          model: 'local-model',
          baseUrl: defaultLocalBaseUrl,
          contextWindowTokens: 8192,
        ),
      };
      expect(await settings.setAdditionalChatProviders(configs), isTrue);
      for (final type in configs.keys) {
        await settings.setChatLlmProvider(type);
        expect(settings.chatLlmProvider, type);
        expect(
          settings.additionalChatProviders[type]!.toJson(),
          configs[type]!.toJson(),
        );
        expect(
          ChatSettings(
            provider: type,
            additionalProviders: settings.additionalChatProviders,
          ).hasApiKey,
          isTrue,
        );
      }
      expect(settings.anthropicApiKey, 'claude-token');
      expect(settings.openaiApiKey, 'openai-key');
      expect(settings.openaiBaseUrl, 'http://legacy:1234/v1/chat/completions');
      expect(
        const ChatSettings(provider: LlmProviderType.local).hasApiKey,
        isFalse,
      );
      expect(
        const ChatSettings(
          provider: LlmProviderType.gemini,
          openaiApiKey: 'not-google',
        ).hasApiKey,
        isFalse,
      );
      await settings.resetToDefaults();
      expect(settings.additionalChatProviders, isEmpty);
    },
  );
}
