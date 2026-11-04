import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../test_helpers/ipad_firmware.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/services/firmware_version_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

void main() {
  group('iPad package preflight', () {
    for (final fixture in invalidIpadPackages().entries) {
      test('rejects ${fixture.key} before handoff', () {
        expect(
          () => FirmwareVersionService.validateIpadPackage(
            ipadRelease,
            '/package.zip',
            fixture.value,
          ),
          throwsA(isA<FirmwareDownloadException>()),
        );
      });
    }
    test(
      'retains app-local immutable target bytes and hash independently of download',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'nt-package-test',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/download.zip');
        await file.writeAsBytes(ipadPackageBytes());
        final service = FirmwareVersionService();
        addTearDown(service.dispose);
        final prepared = await service.prepareIpadPackage(
          ipadRelease,
          file.path,
        );
        addTearDown(
          () => File(prepared.packagePath).parent.delete(recursive: true),
        );
        await file.writeAsBytes([0]);
        expect(
          File(prepared.packagePath).readAsBytesSync(),
          ipadPackageBytes(),
        );
        expect(prepared.version, '1.19.0');
        expect(prepared.sha256Hash, hasLength(64));
        expect(prepared.loader, ipadImage());
        expect(prepared.application, ipadImage(application: true));
        expect(() => prepared.application[0] = 0, throwsUnsupportedError);
      },
    );
    for (final reply in [
      '1.19.0',
      'v1.19.0',
      '1.19.0\n2026-10-21',
      'v1.19.0\nOct 21 2026',
    ]) {
      test(
        'accepts normal fresh application format ${reply.replaceAll('\n', ' ')}',
        () {
          expect(
            FirmwareVersionService.matchesApplicationVersion(reply, '1.19.0'),
            isTrue,
          );
        },
      );
    }
    for (final reply in <String?>[
      null,
      '',
      '1.18.0',
      'loader 1.19.0',
      '1.19.0beta',
      '11.19.0',
      '1.19.0.1',
      '1.19.0\nloader',
      'Disting NT 1.19.0',
    ]) {
      test('does not infer target from ${reply ?? 'missing reply'}', () {
        expect(
          FirmwareVersionService.matchesApplicationVersion(reply, '1.19.0'),
          isFalse,
        );
      });
    }
  });

  setUpAll(() {
    registerFallbackValue(FakeUri());
  });

  group('FirmwareRelease', () {
    test('displayVersion adds v prefix', () {
      final release = FirmwareRelease(
        version: '1.12.0',
        releaseDate: DateTime(2024, 12, 15),
        changelog: ['Fix 1', 'Fix 2'],
        downloadUrl: 'https://example.com/firmware.zip',
      );
      expect(release.displayVersion, 'v1.12.0');
    });

    test('versionParts parses version correctly', () {
      final release = FirmwareRelease(
        version: '1.12.3',
        releaseDate: DateTime(2024, 12, 15),
        changelog: [],
        downloadUrl: 'https://example.com/firmware.zip',
      );
      expect(release.versionParts, [1, 12, 3]);
    });

    test('compareToVersion returns positive when newer', () {
      final release = FirmwareRelease(
        version: '1.12.0',
        releaseDate: DateTime(2024, 12, 15),
        changelog: [],
        downloadUrl: 'https://example.com/firmware.zip',
      );
      expect(release.compareToVersion('1.11.0'), greaterThan(0));
      expect(release.compareToVersion('1.11.9'), greaterThan(0));
      expect(release.compareToVersion('0.99.99'), greaterThan(0));
    });

    test('compareToVersion returns negative when older', () {
      final release = FirmwareRelease(
        version: '1.11.0',
        releaseDate: DateTime(2024, 12, 15),
        changelog: [],
        downloadUrl: 'https://example.com/firmware.zip',
      );
      expect(release.compareToVersion('1.12.0'), lessThan(0));
      expect(release.compareToVersion('2.0.0'), lessThan(0));
    });

    test('compareToVersion returns zero when equal', () {
      final release = FirmwareRelease(
        version: '1.11.0',
        releaseDate: DateTime(2024, 12, 15),
        changelog: [],
        downloadUrl: 'https://example.com/firmware.zip',
      );
      expect(release.compareToVersion('1.11.0'), equals(0));
    });
  });

  group('FirmwareVersionService', () {
    late FirmwareVersionService service;
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
      service = FirmwareVersionService(httpClient: mockClient);
    });

    tearDown(() {
      service.dispose();
    });

    test('isUpdateAvailable returns true when newer version exists', () {
      final versions = [
        FirmwareRelease(
          version: '1.12.0',
          releaseDate: DateTime(2024, 12, 15),
          changelog: [],
          downloadUrl: 'https://example.com/firmware.zip',
        ),
        FirmwareRelease(
          version: '1.11.0',
          releaseDate: DateTime(2024, 11, 15),
          changelog: [],
          downloadUrl: 'https://example.com/firmware-old.zip',
        ),
      ];
      expect(service.isUpdateAvailable('1.11.0', versions), isTrue);
      expect(service.isUpdateAvailable('1.10.0', versions), isTrue);
    });

    test('isUpdateAvailable returns false when already on latest', () {
      final versions = [
        FirmwareRelease(
          version: '1.12.0',
          releaseDate: DateTime(2024, 12, 15),
          changelog: [],
          downloadUrl: 'https://example.com/firmware.zip',
        ),
      ];
      expect(service.isUpdateAvailable('1.12.0', versions), isFalse);
      expect(service.isUpdateAvailable('1.13.0', versions), isFalse);
    });

    test('isUpdateAvailable returns false for empty list', () {
      expect(service.isUpdateAvailable('1.11.0', []), isFalse);
    });

    test('getLatestVersion returns first (newest) version', () {
      final versions = [
        FirmwareRelease(
          version: '1.12.0',
          releaseDate: DateTime(2024, 12, 15),
          changelog: [],
          downloadUrl: 'https://example.com/firmware.zip',
        ),
        FirmwareRelease(
          version: '1.11.0',
          releaseDate: DateTime(2024, 11, 15),
          changelog: [],
          downloadUrl: 'https://example.com/firmware-old.zip',
        ),
      ];
      final latest = service.getLatestVersion(versions);
      expect(latest?.version, '1.12.0');
    });

    test('getLatestVersion returns null for empty list', () {
      expect(service.getLatestVersion([]), isNull);
    });

    test('clearCache clears cached data', () async {
      // First make a successful request
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(_sampleHtml, 200));

      final result1 = await service.fetchAvailableVersions();
      expect(result1, isNotEmpty);

      // Clear cache
      service.clearCache();

      // Next request should make a new HTTP call
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(_sampleHtml, 200));

      await service.fetchAvailableVersions();

      // Verify two HTTP calls were made (not using cache)
      verify(
        () => mockClient.get(
          any(),
          headers: any(
            named: 'headers',
            that: containsPair('User-Agent', 'nt_helper'),
          ),
        ),
      ).called(2);
    });

    test('fetchAvailableVersions caches results', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(_sampleHtml, 200));

      // Make two calls
      await service.fetchAvailableVersions();
      await service.fetchAvailableVersions();

      // Only one HTTP call should be made (second uses cache)
      verify(
        () => mockClient.get(
          any(),
          headers: any(
            named: 'headers',
            that: containsPair('User-Agent', 'nt_helper'),
          ),
        ),
      ).called(1);
    });

    test('fetchAvailableVersions handles HTTP errors', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('Not Found', 404));

      expect(
        () => service.fetchAvailableVersions(),
        throwsA(isA<FirmwareDownloadException>()),
      );
    });

    test('fetchAvailableVersions parses HTML correctly', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(_sampleHtml, 200));

      final versions = await service.fetchAvailableVersions();

      expect(versions, isNotEmpty);
      expect(versions.first.version, '1.12.0');
      expect(versions.first.downloadUrl, contains('distingNT'));
      expect(versions.first.downloadUrl, endsWith('.zip'));
    });
  });
}

/// Sample HTML that mimics the Expert Sleepers firmware page structure
const _sampleHtml = '''
<!DOCTYPE html>
<html>
<head><title>Disting NT Firmware Updates</title></head>
<body>
<table>
<tr>
<td>1.12.0</td>
<td>15/12/2024</td>
<td><a href="downloads/distingNT_v1_12_0.zip">Download</a></td>
<td>
<ul>
<li>New feature added</li>
<li>Bug fix for audio</li>
</ul>
</td>
</tr>
<tr>
<td>1.11.0</td>
<td>1/11/2024</td>
<td><a href="downloads/distingNT_v1_11_0.zip">Download</a></td>
<td>
<ul>
<li>Previous version changes</li>
</ul>
</td>
</tr>
</table>
</body>
</html>
''';
