import 'dart:convert';
import 'dart:io';

import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:path/path.dart' as p;

/// Reads transport capabilities from Codex's cached model catalog.
///
/// In particular, newer Codex models can opt into Responses Lite. Keeping
/// this model-driven avoids coupling nt_helper to specific model names.
class CodexModelMetadataService {
  final String modelsCachePath;

  CodexModelMetadataService({String? modelsCachePath})
    : modelsCachePath =
          modelsCachePath ??
          modelsCachePathForAuthFile(CodexAuthService.defaultAuthFilePath());

  factory CodexModelMetadataService.forAuthFile(String authFilePath) {
    return CodexModelMetadataService(
      modelsCachePath: modelsCachePathForAuthFile(authFilePath),
    );
  }

  static String modelsCachePathForAuthFile(String authFilePath) {
    return p.join(p.dirname(authFilePath), 'models_cache.json');
  }

  Future<bool> useResponsesLite(String model) async {
    try {
      final file = File(modelsCachePath);
      if (!await file.exists()) {
        throw CodexModelMetadataException(
          'Codex model metadata was not found at $modelsCachePath. '
          'Open Codex once to refresh it, then try again.',
        );
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw CodexModelMetadataException(
          'Codex model metadata at $modelsCachePath is not a JSON object.',
        );
      }
      final models = decoded['models'];
      if (models is! List) {
        throw CodexModelMetadataException(
          'Codex model metadata at $modelsCachePath has no model list.',
        );
      }

      for (final candidate in models) {
        if (candidate is! Map) continue;
        if (candidate['slug'] != model && candidate['id'] != model) continue;
        return candidate['use_responses_lite'] == true;
      }

      // Manual model IDs remain supported. Unknown models use the standard
      // Responses contract because no Codex metadata opts them into Lite.
      return false;
    } on CodexModelMetadataException {
      rethrow;
    } on FormatException catch (error) {
      throw CodexModelMetadataException(
        'Codex model metadata at $modelsCachePath is not valid JSON: '
        '${error.message}',
      );
    } on FileSystemException catch (error) {
      throw CodexModelMetadataException(
        'Could not read Codex model metadata at $modelsCachePath: '
        '${error.message}',
      );
    }
  }
}

class CodexModelMetadataException implements Exception {
  final String message;

  const CodexModelMetadataException(this.message);

  @override
  String toString() => message;
}
