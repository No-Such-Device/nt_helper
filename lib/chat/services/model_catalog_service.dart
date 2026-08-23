import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nt_helper/chat/services/codex_auth_service.dart';

const openAISubscriptionResponsesUrl =
    'https://chatgpt.com/backend-api/codex/responses';
const openAISubscriptionModelsUrl =
    'https://chatgpt.com/backend-api/codex/models';
const openAISubscriptionClientVersion = '0.135.0';

class LlmModelOption {
  final String id;
  final String displayName;
  final int? contextWindowTokens;

  const LlmModelOption({
    required this.id,
    required this.displayName,
    this.contextWindowTokens,
  });
}

class ModelCatalogException implements Exception {
  final String message;

  const ModelCatalogException(this.message);

  @override
  String toString() => message;
}

/// Discovers models available to the signed-in ChatGPT/Codex account.
///
/// This intentionally uses the subscription backend rather than OpenAI's
/// public `/v1/models` API, whose results describe API-key availability.
class OpenAISubscriptionModelCatalog {
  final CodexAuthService authService;
  final http.Client _client;
  final Uri modelsUri;
  final String clientVersion;

  OpenAISubscriptionModelCatalog({
    required this.authService,
    http.Client? client,
    Uri? modelsUri,
    this.clientVersion = openAISubscriptionClientVersion,
  }) : _client = client ?? http.Client(),
       modelsUri = modelsUri ?? Uri.parse(openAISubscriptionModelsUrl);

  Future<List<LlmModelOption>> fetchModels({
    required bool allowAuthRefresh,
  }) async {
    var auth = await authService.loadAuth();
    var response = await _getModels(auth);

    if (response.statusCode == 401 && allowAuthRefresh) {
      auth = await authService.refreshAuth();
      response = await _getModels(auth);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelCatalogException(
        'Could not load subscription models (${response.statusCode}).',
      );
    }

    try {
      return parseModels(jsonDecode(response.body));
    } on FormatException {
      throw const ModelCatalogException(
        'The subscription model list was not valid JSON.',
      );
    }
  }

  Future<http.Response> _getModels(CodexAuthSnapshot auth) {
    final uri = modelsUri.replace(
      queryParameters: {
        ...modelsUri.queryParameters,
        'client_version': clientVersion,
      },
    );
    return _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'version': clientVersion,
            ...auth.authHeaders,
          },
        )
        .timeout(const Duration(seconds: 5));
  }

  static List<LlmModelOption> parseModels(Object? decoded) {
    final rawModels = decoded is Map
        ? decoded['models'] ?? decoded['data']
        : decoded;
    if (rawModels is! List) return const [];

    final models = <LlmModelOption>[];
    final seen = <String>{};
    for (final rawModel in rawModels) {
      if (rawModel is! Map) continue;
      final id = _nonEmptyString(
        rawModel['slug'] ?? rawModel['id'] ?? rawModel['model'],
      );
      final visibility = _nonEmptyString(rawModel['visibility']);
      if (visibility == 'hide' || visibility == 'hidden') continue;
      if (id == null || !seen.add(id)) continue;

      models.add(
        LlmModelOption(
          id: id,
          displayName: _nonEmptyString(rawModel['display_name']) ?? id,
          contextWindowTokens: _positiveInt(
            rawModel['context_window'] ?? rawModel['max_input_tokens'],
          ),
        ),
      );
    }
    return List.unmodifiable(models);
  }

  void dispose() {
    _client.close();
  }
}

/// Discovers models available to an OpenAI API key or compatible endpoint.
class OpenAIModelCatalog {
  final String apiKey;
  final Uri modelsUri;
  final http.Client _client;

  OpenAIModelCatalog({
    required this.apiKey,
    String? baseUrl,
    http.Client? client,
  }) : modelsUri = _openAIModelsUri(baseUrl),
       _client = client ?? http.Client();

  Future<List<LlmModelOption>> fetchModels() async {
    final response = await _client
        .get(
          modelsUri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelCatalogException(
        'Could not load OpenAI API models (${response.statusCode}).',
      );
    }
    try {
      return OpenAISubscriptionModelCatalog.parseModels(
        jsonDecode(response.body),
      );
    } on FormatException {
      throw const ModelCatalogException(
        'The OpenAI API model list was not valid JSON.',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Discovers models available from Anthropic's API for the configured auth.
class AnthropicModelCatalog {
  static const _apiVersion = '2023-06-01';
  static const _subscriptionBetaHeader =
      'claude-code-20250219,oauth-2025-04-20,'
      'fine-grained-tool-streaming-2025-05-14,'
      'interleaved-thinking-2025-05-14';

  final String credential;
  final bool subscriptionAuth;
  final http.Client _client;

  AnthropicModelCatalog({
    required this.credential,
    required this.subscriptionAuth,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<List<LlmModelOption>> fetchModels() async {
    final response = await _client
        .get(
          Uri.parse('https://api.anthropic.com/v1/models?limit=1000'),
          headers: {
            'Accept': 'application/json',
            if (subscriptionAuth) ...{
              'Authorization': 'Bearer $credential',
              'anthropic-beta': _subscriptionBetaHeader,
            } else
              'x-api-key': credential,
            'anthropic-version': _apiVersion,
          },
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelCatalogException(
        'Could not load Anthropic models (${response.statusCode}).',
      );
    }
    try {
      return OpenAISubscriptionModelCatalog.parseModels(
        jsonDecode(response.body),
      );
    } on FormatException {
      throw const ModelCatalogException(
        'The Anthropic model list was not valid JSON.',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

Uri _openAIModelsUri(String? baseUrl) {
  final raw = baseUrl?.trim();
  if (raw == null || raw.isEmpty) {
    return Uri.parse('https://api.openai.com/v1/models');
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const ModelCatalogException('The OpenAI base URL is invalid.');
  }

  var path = uri.path;
  for (final suffix in const ['/chat/completions', '/responses', '/models']) {
    if (path.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  if (path.isEmpty) path = '/';
  if (!path.endsWith('/')) path = '$path/';
  return uri.replace(path: path, query: null, fragment: null).resolve('models');
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _positiveInt(Object? value) {
  final parsed = switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : null;
}
