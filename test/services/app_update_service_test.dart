import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/app_update_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

const _sampleRelease = {
  'tag_name': 'v3.0.0',
  'body': '## What\'s New\n- Feature A\n- Feature B',
  'published_at': '2026-02-01T00:00:00Z',
  'assets': [
    {
      'name': 'nt_helper-3.0.0-macos.zip',
      'browser_download_url':
          'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-macos.zip',
    },
    {
      'name': 'nt_helper-3.0.0-linux.zip',
      'browser_download_url':
          'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-linux.zip',
    },
    {
      'name': 'nt_helper-3.0.0-windows.zip',
      'browser_download_url':
          'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-windows.zip',
    },
    {
      'name': 'nt_helper-3.0.0-windows-setup.exe',
      'browser_download_url':
          'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-windows-setup.exe',
    },
  ],
};

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUri());
  });

  group('AppRelease.fromGitHubJson', () {
    test('parses tag_name with v prefix', () {
      final release = AppRelease.fromGitHubJson(
        Map<String, dynamic>.from(_sampleRelease),
      );
      expect(release.version, '3.0.0');
      expect(release.tagName, 'v3.0.0');
    });

    test('parses tag_name without v prefix', () {
      final json = Map<String, dynamic>.from(_sampleRelease);
      json['tag_name'] = '2.5.0';
      final release = AppRelease.fromGitHubJson(json);
      expect(release.version, '2.5.0');
      expect(release.tagName, '2.5.0');
    });

    test('parses release body', () {
      final release = AppRelease.fromGitHubJson(
        Map<String, dynamic>.from(_sampleRelease),
      );
      expect(release.body, contains('Feature A'));
    });

    test('parses published date', () {
      final release = AppRelease.fromGitHubJson(
        Map<String, dynamic>.from(_sampleRelease),
      );
      expect(release.publishedAt.year, 2026);
      expect(release.publishedAt.month, 2);
    });

    test('parses platform assets', () {
      final release = AppRelease.fromGitHubJson(
        Map<String, dynamic>.from(_sampleRelease),
      );
      expect(release.platformAssets, hasLength(3));
      expect(release.platformAssets['macos'], contains('macos.zip'));
      expect(release.platformAssets['linux'], contains('linux.zip'));
      expect(release.platformAssets['windows'], contains('windows-setup.exe'));
    });

    test('prefers Windows installer asset regardless of asset order', () {
      final zipFirst = Map<String, dynamic>.from(_sampleRelease);
      final zipFirstRelease = AppRelease.fromGitHubJson(zipFirst);
      expect(
        zipFirstRelease.platformAssets['windows'],
        contains('windows-setup.exe'),
      );

      final setupFirst = Map<String, dynamic>.from(_sampleRelease);
      setupFirst['assets'] = [
        {
          'name': 'nt_helper-3.0.0-windows-setup.exe',
          'browser_download_url':
              'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-windows-setup.exe',
        },
        {
          'name': 'nt_helper-3.0.0-windows.zip',
          'browser_download_url':
              'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-windows.zip',
        },
      ];

      final setupFirstRelease = AppRelease.fromGitHubJson(setupFirst);
      expect(
        setupFirstRelease.platformAssets['windows'],
        contains('windows-setup.exe'),
      );
    }, tags: ['regression']);

    test('handles missing assets gracefully', () {
      final json = Map<String, dynamic>.from(_sampleRelease);
      json['assets'] = [];
      final release = AppRelease.fromGitHubJson(json);
      expect(release.platformAssets, isEmpty);
    });

    test('handles null body', () {
      final json = Map<String, dynamic>.from(_sampleRelease);
      json['body'] = null;
      final release = AppRelease.fromGitHubJson(json);
      expect(release.body, '');
    });
  });

  group('AppUpdateService', () {
    late MockHttpClient mockClient;
    late AppUpdateService service;

    setUp(() {
      mockClient = MockHttpClient();
      // Inject a current version older than sample release so update is found
      service = AppUpdateService(
        httpClient: mockClient,
        currentVersion: '2.0.0',
      );
    });

    test('returns null on HTTP error', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response('Not Found', 404));

      final result = await service.checkForUpdate();
      expect(result, isNull);
    });

    test('returns null on network error', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenThrow(Exception('Network error'));

      final result = await service.checkForUpdate();
      expect(result, isNull);
    });

    test('returns release when update is available', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonEncode(_sampleRelease), 200));

      final result = await service.checkForUpdate();
      expect(result, isNotNull);
      expect(result!.version, '3.0.0');
    });

    test('returns null when update lacks current platform asset', () async {
      final windowsService = AppUpdateService(
        httpClient: mockClient,
        currentVersion: '2.0.0',
        platformKey: 'windows',
      );
      final releaseWithoutWindows = Map<String, dynamic>.from(_sampleRelease);
      releaseWithoutWindows['assets'] = [
        {
          'name': 'nt_helper-3.0.0-macos.zip',
          'browser_download_url':
              'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-macos.zip',
        },
        {
          'name': 'nt_helper-3.0.0-linux.zip',
          'browser_download_url':
              'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-linux.zip',
        },
      ];

      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(releaseWithoutWindows), 200),
      );

      final result = await windowsService.checkForUpdate();
      expect(result, isNull);
    });

    test('returns release when update has current platform asset', () async {
      final linuxService = AppUpdateService(
        httpClient: mockClient,
        currentVersion: '2.0.0',
        platformKey: 'linux',
      );

      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonEncode(_sampleRelease), 200));

      final result = await linuxService.checkForUpdate();
      expect(result, isNotNull);
      expect(result!.platformAssets, contains('linux'));
    });

    test('skipVersionCheck still requires current platform asset', () async {
      final windowsService = AppUpdateService(
        httpClient: mockClient,
        currentVersion: '3.0.0',
        platformKey: 'windows',
      );
      final releaseWithoutWindows = Map<String, dynamic>.from(_sampleRelease);
      releaseWithoutWindows['assets'] = [
        {
          'name': 'nt_helper-3.0.0-macos.zip',
          'browser_download_url':
              'https://github.com/thorinside/nt_helper/releases/download/v3.0.0/nt_helper-3.0.0-macos.zip',
        },
      ];

      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(releaseWithoutWindows), 200),
      );

      final result = await windowsService.checkForUpdate(
        skipVersionCheck: true,
      );
      expect(result, isNull);
    });

    test('returns null when already up to date', () async {
      final upToDateService = AppUpdateService(
        httpClient: mockClient,
        currentVersion: '3.0.0',
      );

      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonEncode(_sampleRelease), 200));

      final result = await upToDateService.checkForUpdate();
      expect(result, isNull);
    });

    test('caches result for subsequent calls', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonEncode(_sampleRelease), 200));

      // First call hits API
      await service.checkForUpdate();
      // Second call should use cache
      await service.checkForUpdate();

      verify(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).called(1);
    });

    test('forceRefresh bypasses cache', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonEncode(_sampleRelease), 200));

      await service.checkForUpdate();
      await service.checkForUpdate(forceRefresh: true);

      verify(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).called(2);
    });

    test('findWindowsReleaseRoot finds executable at archive root', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nt-helper-update-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File('${tempDir.path}/nt_helper.exe').writeAsString('exe');

      final releaseRoot = await AppUpdateService.findWindowsReleaseRoot(
        tempDir,
      );

      expect(releaseRoot?.path, tempDir.path);
    });

    test('findWindowsReleaseRoot finds executable in nested archive', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nt-helper-update-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final nestedDir = Directory('${tempDir.path}/Release');
      await nestedDir.create();
      await File('${nestedDir.path}/nt_helper.exe').writeAsString('exe');

      final releaseRoot = await AppUpdateService.findWindowsReleaseRoot(
        tempDir,
      );

      expect(releaseRoot?.path, nestedDir.path);
    });

    test('buildWindowsUpdateScript logs, unblocks, and relaunches', () {
      final script = AppUpdateService.buildWindowsUpdateScript(
        sourceDir: r'C:\Temp\update',
        appDir: r'C:\Program Files\NT Helper',
        exePath: r'C:\Program Files\NT Helper\nt_helper.exe',
        logPath: r'C:\Users\neal\AppData\Roaming\nt_helper_update.log',
        currentPid: 1234,
      );

      expect(script, contains(r'Wait-Process -Id $currentPid -Timeout 30'));
      expect(script, contains('Copy-Item -LiteralPath'));
      expect(script, contains('Unblock-File -ErrorAction SilentlyContinue'));
      expect(script, contains(r'Start-Process -FilePath $exePath'));
      expect(script, contains('Write-UpdateLog'));
      expect(script, contains(r"$appDir = 'C:\Program Files\NT Helper'"));
    });

    test('buildWindowsUpdateScript escapes single quotes in paths', () {
      final script = AppUpdateService.buildWindowsUpdateScript(
        sourceDir: r"C:\Users\Neal's PC\update",
        appDir: r"C:\Users\Neal's PC\NT Helper",
        exePath: r"C:\Users\Neal's PC\NT Helper\nt_helper.exe",
        logPath: r"C:\Users\Neal's PC\update.log",
        currentPid: 1234,
      );

      expect(script, contains(r"$sourceDir = 'C:\Users\Neal''s PC\update'"));
      expect(script, contains(r"$appDir = 'C:\Users\Neal''s PC\NT Helper'"));
    }, tags: ['regression']);

    test('buildWindowsInstallerArguments runs current-user installer', () {
      final arguments = AppUpdateService.buildWindowsInstallerArguments(
        logPath: r'C:\Users\neal\AppData\Roaming\nt_helper_setup.log',
      );

      expect(arguments, contains('/CURRENTUSER'));
      expect(arguments, contains('/CLOSEAPPLICATIONS'));
      expect(
        arguments,
        contains(r'/LOG=C:\Users\neal\AppData\Roaming\nt_helper_setup.log'),
      );
    });
  });
}
