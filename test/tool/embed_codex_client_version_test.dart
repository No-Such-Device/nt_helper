import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/embed_codex_client_version.dart' as embedder;

void main() {
  test('parses the Codex CLI version', () {
    expect(embedder.parseCodexVersion('codex-cli 0.149.0'), '0.149.0');
    expect(embedder.parseCodexVersion('codex-cli unknown'), isNull);
  });

  test('reads the latest version from Codex metadata', () async {
    final directory = await Directory.systemTemp.createTemp(
      'codex-version-embed-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final versionFile = File('${directory.path}/version.json');
    await versionFile.writeAsString(jsonEncode({'latest_version': '0.150.0'}));

    expect(await embedder.readVersionMetadata(versionFile), '0.150.0');
  });

  test('renders a committed Dart fallback constant', () {
    expect(
      embedder.renderEmbeddedVersion('0.149.0'),
      contains("embeddedCodexClientVersion = '0.149.0'"),
    );
    expect(
      () => embedder.renderEmbeddedVersion('latest'),
      throwsFormatException,
    );
  });
}
