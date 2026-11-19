import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/firmware_version.dart';

void main() {
  group('FirmwareVersion.hasParameterIoMetadata', () {
    for (final version in [
      '1.12',
      '1.12.0',
      'v1.12.0',
      '1.12.1',
      '1.13.0',
      '2.0',
      '1.12beta',
      '1.12.0beta',
      '1.12.0-beta.2',
      ' v1.12.0\r\nDec 2 2025 ',
    ]) {
      test('admits recognized firmware 1.12 or later "$version"', () {
        expect(FirmwareVersion(version).hasParameterIoMetadata, isTrue);
      });
    }

    for (final version in [
      '1.11.0',
      '1.11.99beta',
      '1.10.0',
      '',
      'unknown',
      'Offline Mode',
      'custom 1.12.0',
      '2026-11-19',
      '1.12.0.1',
      '1.12.0-rc.1',
      '1.12.0-alpha',
      '1.12.0garbage',
      '1.11.0\nNov 19 2026',
      '\n1.12.0',
    ]) {
      test('rejects older or unrecognized firmware "$version"', () {
        expect(FirmwareVersion(version).hasParameterIoMetadata, isFalse);
      });
    }
  });
}
