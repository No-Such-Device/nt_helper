import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/firmware_version.dart';

void main() {
  test(
    'bypass-aware mapping gate admits the announced 1.20 beta numeric line',
    () {
      for (final version in [
        '1.20',
        'v1.20.0',
        '1.20beta',
        '1.20.0beta',
        '1.20.0-beta',
        '1.20.0-beta.2',
        '1.20.1',
        '1.21beta',
        '2.0',
        '1.20beta\nNov 19 2026',
      ]) {
        expect(
          FirmwareVersion(version).hasBypassAwareMappings,
          isTrue,
          reason: version,
        );
      }
    },
  );
  test(
    'bypass-aware mapping gate rejects old, unknown and malformed versions',
    () {
      for (final version in [
        '',
        'unknown',
        'Offline Mode',
        '1.12.0',
        '1.19.99beta',
        '1.19\nNov 20 2026',
        'unknown 1.20',
        '1.20rc1',
        '1.20.0-dev',
        '2026',
      ]) {
        expect(
          FirmwareVersion(version).hasBypassAwareMappings,
          isFalse,
          reason: version,
        );
      }
    },
  );
}
