import 'dart:convert';
import 'dart:io';

const _generatedRelativePath = 'lib/chat/services/codex_client_version.g.dart';
final _validVersion = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');
final _versionInText = RegExp(r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b');

Future<void> main() async {
  final repoRoot = File.fromUri(Platform.script).parent.parent;
  final outputFile = File('${repoRoot.path}/$_generatedRelativePath');
  final discovery = await discoverCodexVersion();
  final version = discovery?.version ?? await readEmbeddedVersion(outputFile);

  if (version == null) {
    stderr.writeln(
      'Could not discover a Codex client version and no embedded fallback '
      'exists.',
    );
    exitCode = 1;
    return;
  }

  final contents = renderEmbeddedVersion(version);
  if (await outputFile.exists() &&
      await outputFile.readAsString() == contents) {
    stdout.writeln(
      'Codex client version $version is already embedded'
      '${discovery == null ? '' : ' (${discovery.source})'}.',
    );
    return;
  }

  await outputFile.writeAsString(contents);
  stdout.writeln(
    'Embedded Codex client version $version'
    '${discovery == null ? '' : ' from ${discovery.source}'}.',
  );
}

Future<CodexVersionDiscovery?> discoverCodexVersion() async {
  for (final file in candidateVersionFiles()) {
    final version = await readVersionMetadata(file);
    if (version != null) {
      return CodexVersionDiscovery(version: version, source: file.path);
    }
  }

  try {
    final result = await Process.run('codex', const [
      '--version',
    ], runInShell: Platform.isWindows);
    if (result.exitCode == 0) {
      final version = parseCodexVersion('${result.stdout}\n${result.stderr}');
      if (version != null) {
        return CodexVersionDiscovery(
          version: version,
          source: 'codex --version',
        );
      }
    }
  } on ProcessException {
    // A release machine without the Codex CLI keeps the committed fallback.
  }

  return null;
}

List<File> candidateVersionFiles() {
  final paths = <String>{};
  final codexHome = Platform.environment['CODEX_HOME'];
  if (codexHome != null && codexHome.isNotEmpty) {
    paths.add('$codexHome${Platform.pathSeparator}version.json');
  }

  final home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    paths.add(
      '$home${Platform.pathSeparator}.codex'
      '${Platform.pathSeparator}version.json',
    );
  }

  return paths.map(File.new).toList(growable: false);
}

Future<String?> readVersionMetadata(File file) async {
  try {
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    final version = decoded['latest_version'];
    if (version is! String) return null;
    final trimmed = version.trim();
    return _validVersion.hasMatch(trimmed) ? trimmed : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

String? parseCodexVersion(String output) {
  final version = _versionInText.firstMatch(output)?.group(1);
  return version != null && _validVersion.hasMatch(version) ? version : null;
}

Future<String?> readEmbeddedVersion(File file) async {
  try {
    if (!await file.exists()) return null;
    final match = RegExp(
      r"embeddedCodexClientVersion = '([^']+)'",
    ).firstMatch(await file.readAsString());
    final version = match?.group(1);
    return version != null && _validVersion.hasMatch(version) ? version : null;
  } on FileSystemException {
    return null;
  }
}

String renderEmbeddedVersion(String version) {
  if (!_validVersion.hasMatch(version)) {
    throw FormatException('Invalid Codex client version: $version');
  }
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Run `dart run tool/embed_codex_client_version.dart` to refresh it.

const embeddedCodexClientVersion = '$version';
''';
}

class CodexVersionDiscovery {
  final String version;
  final String source;

  const CodexVersionDiscovery({required this.version, required this.source});
}
