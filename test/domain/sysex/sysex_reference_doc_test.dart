import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SYSEX_REFERENCE mapping versions', () {
    test('documents current mapping data and performance page versions', () {
      final reference = File('docs/SYSEX_REFERENCE.md').readAsStringSync();

      expect(reference, contains('**Mapping version** is currently `8`.'));
      expect(
        reference,
        contains(
          '`mappingVersion` | Performance page mapping protocol version (`5`)',
        ),
      );
    });
  });
}
