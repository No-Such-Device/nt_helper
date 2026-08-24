import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/services/codex_client_version_service.dart';

void main() {
  group('CodexClientVersionService', () {
    test('reads the latest version from Codex version metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-version-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final versionFile = File('${directory.path}/version.json');
      await versionFile.writeAsString(
        jsonEncode({
          'latest_version': '0.149.0',
          'last_checked_at': '2026-08-24T00:02:54.181446Z',
          'dismissed_version': null,
        }),
      );
      final service = CodexClientVersionService(
        versionFilePath: versionFile.path,
      );

      expect(await service.resolve(), '0.149.0');
    });

    test('reports when version metadata is unavailable', () async {
      final service = CodexClientVersionService(
        versionFilePath: '/missing/codex/version.json',
      );

      await expectLater(
        service.resolve(),
        throwsA(
          isA<CodexClientVersionException>().having(
            (error) => error.message,
            'message',
            contains('Open Codex once'),
          ),
        ),
      );
    });

    test('rejects malformed version metadata', () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-version-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final versionFile = File('${directory.path}/version.json');
      await versionFile.writeAsString(jsonEncode({'latest_version': 'latest'}));
      final service = CodexClientVersionService(
        versionFilePath: versionFile.path,
      );

      await expectLater(
        service.resolve(),
        throwsA(isA<CodexClientVersionException>()),
      );
    });
  });
}
