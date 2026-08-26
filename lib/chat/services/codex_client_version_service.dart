import 'dart:convert';
import 'dart:io';

import 'package:nt_helper/chat/services/codex_auth_service.dart';
import 'package:nt_helper/chat/services/codex_client_version.g.dart';
import 'package:path/path.dart' as p;

/// Resolves the Codex protocol version that nt_helper should advertise.
///
/// Codex may write its current available client version to version.json beside
/// auth.json. When that cache is unavailable, nt_helper uses the latest client
/// version known at build time so a platform-specific cache layout cannot
/// prevent subscription requests.
class CodexClientVersionService {
  static const latestKnownVersion = embeddedCodexClientVersion;

  static final _validVersion = RegExp(
    r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$',
  );

  final String versionFilePath;
  final String? fallbackVersion;

  CodexClientVersionService({
    String? versionFilePath,
    this.fallbackVersion = latestKnownVersion,
  }) : versionFilePath =
           versionFilePath ??
           versionFilePathForAuthFile(CodexAuthService.defaultAuthFilePath());

  factory CodexClientVersionService.forAuthFile(String authFilePath) {
    return CodexClientVersionService(
      versionFilePath: versionFilePathForAuthFile(authFilePath),
    );
  }

  static String versionFilePathForAuthFile(String authFilePath) {
    return p.join(p.dirname(authFilePath), 'version.json');
  }

  Future<String> resolve() async {
    try {
      final file = File(versionFilePath);
      if (!await file.exists()) {
        throw CodexClientVersionException(
          'Codex version metadata was not found at $versionFilePath. '
          'Open Codex once to refresh it, then try again.',
        );
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw CodexClientVersionException(
          'Codex version metadata at $versionFilePath is not a JSON object.',
        );
      }
      final rawVersion = decoded['latest_version'];
      if (rawVersion is! String) {
        throw CodexClientVersionException(
          'Codex version metadata at $versionFilePath has no latest_version.',
        );
      }
      final version = rawVersion.trim();
      if (!_validVersion.hasMatch(version)) {
        throw CodexClientVersionException(
          'Codex version metadata at $versionFilePath has an invalid '
          'latest_version.',
        );
      }
      return version;
    } on CodexClientVersionException catch (error) {
      return _fallbackOrThrow(error);
    } on FormatException catch (error) {
      return _fallbackOrThrow(
        CodexClientVersionException(
          'Codex version metadata at $versionFilePath is not valid JSON: '
          '${error.message}',
        ),
      );
    } on FileSystemException catch (error) {
      return _fallbackOrThrow(
        CodexClientVersionException(
          'Could not read Codex version metadata at $versionFilePath: '
          '${error.message}',
        ),
      );
    }
  }

  String _fallbackOrThrow(CodexClientVersionException error) {
    final fallback = fallbackVersion?.trim();
    if (fallback != null && _validVersion.hasMatch(fallback)) {
      return fallback;
    }
    throw error;
  }
}

class CodexClientVersionException implements Exception {
  final String message;

  const CodexClientVersionException(this.message);

  @override
  String toString() => message;
}
