import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/firmware_version.dart';

void main() {
  group('FirmwareVersion.hasPerfPageItems', () {
    test('returns false for v1.15', () {
      final version = FirmwareVersion('1.15');
      expect(version.hasPerfPageItems, false);
    });

    test('returns true for v1.16', () {
      final version = FirmwareVersion('1.16');
      expect(version.hasPerfPageItems, true);
    });

    test('returns true for v1.17', () {
      final version = FirmwareVersion('1.17');
      expect(version.hasPerfPageItems, true);
    });

    test('returns true for v2.0', () {
      final version = FirmwareVersion('2.0');
      expect(version.hasPerfPageItems, true);
    });

    test('returns false for v1.0', () {
      final version = FirmwareVersion('1.0');
      expect(version.hasPerfPageItems, false);
    });

    test('returns false for v0.99', () {
      final version = FirmwareVersion('0.99');
      expect(version.hasPerfPageItems, false);
    });
  });

  group('FirmwareVersion.hasExpressiveMidiMapping', () {
    test('returns false before v1.17', () {
      expect(FirmwareVersion('1.16.9').hasExpressiveMidiMapping, false);
    });

    test('returns true for v1.17 beta strings', () {
      expect(FirmwareVersion('1.17.0-beta').hasExpressiveMidiMapping, true);
    });

    test('returns true for v1.17 release', () {
      expect(FirmwareVersion('1.17.0').hasExpressiveMidiMapping, true);
    });

    test('returns true for v2.0', () {
      expect(FirmwareVersion('2.0').hasExpressiveMidiMapping, true);
    });
  });

  group('FirmwareVersion.hasWaveCacheListing', () {
    test('is false before firmware 1.17', () {
      expect(FirmwareVersion('1.16.9').hasWaveCacheListing, false);
    });

    test('is true for firmware 1.17 and newer', () {
      expect(FirmwareVersion('1.17.0').hasWaveCacheListing, true);
      expect(FirmwareVersion('2.0').hasWaveCacheListing, true);
    });
  });

  group('FirmwareVersion.hasAlgorithmVisualStyle', () {
    test('is false before firmware 1.18', () {
      expect(FirmwareVersion('1.17.9').hasAlgorithmVisualStyle, false);
    });

    test('is true for 1.18 beta and newer firmware', () {
      expect(FirmwareVersion('1.18.0beta').hasAlgorithmVisualStyle, true);
      expect(FirmwareVersion('2.0').hasAlgorithmVisualStyle, true);
    });
  });
}
