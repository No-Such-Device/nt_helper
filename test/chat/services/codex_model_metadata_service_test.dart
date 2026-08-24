import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/services/codex_model_metadata_service.dart';

void main() {
  group('CodexModelMetadataService', () {
    test('reads Responses Lite capability by model', () async {
      final directory = await Directory.systemTemp.createTemp(
        'codex-model-metadata-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cache = File('${directory.path}/models_cache.json');
      await cache.writeAsString(
        jsonEncode({
          'models': [
            {'slug': 'lite-model', 'use_responses_lite': true},
            {'slug': 'standard-model', 'use_responses_lite': false},
          ],
        }),
      );
      final service = CodexModelMetadataService(modelsCachePath: cache.path);

      expect(await service.useResponsesLite('lite-model'), isTrue);
      expect(await service.useResponsesLite('standard-model'), isFalse);
      expect(await service.useResponsesLite('future-model'), isFalse);
    });

    test('reports unavailable model metadata', () async {
      final service = CodexModelMetadataService(
        modelsCachePath: '/missing/codex/models_cache.json',
      );

      await expectLater(
        service.useResponsesLite('lite-model'),
        throwsA(
          isA<CodexModelMetadataException>().having(
            (error) => error.message,
            'message',
            contains('Open Codex once'),
          ),
        ),
      );
    });
  });
}
