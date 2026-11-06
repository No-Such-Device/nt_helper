import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/version_comparison_service.dart';
import 'package:nt_helper/utils/sandbox_utils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:nt_helper/utils/build_config.dart';

enum InstallOutcome { success, needsRestart, error }

class InstallResult {
  final InstallOutcome outcome;
  final String message;
  final String? folderPath;

  const InstallResult({
    required this.outcome,
    required this.message,
    this.folderPath,
  });
}

class AppUpdateService {
  final http.Client _httpClient;
  final String? _currentVersionOverride;
  final String? _platformKeyOverride;
  static const String _githubApiUrl =
      'https://api.github.com/repos/thorinside/nt_helper/releases/latest';

  AppRelease? _cachedRelease;
  DateTime? _lastCheckTime;
  static const _cacheDuration = Duration(hours: 1);

  AppUpdateService({
    http.Client? httpClient,
    String? currentVersion,
    String? platformKey,
  }) : _httpClient = httpClient ?? http.Client(),
       _currentVersionOverride = currentVersion,
       _platformKeyOverride = platformKey;

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  bool get isSupported =>
      !kPlayStoreBuild &&
      _isDesktop &&
      !(Platform.isMacOS && SandboxUtils.isSandboxed);

  /// Close only after all UI using this service has been disposed.
  void dispose() => _httpClient.close();

  Future<AppRelease?> checkForUpdate({
    bool forceRefresh = false,
    bool skipVersionCheck = false,
  }) async {
    if (!isSupported) return null;

    if (!forceRefresh &&
        _cachedRelease != null &&
        _lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedRelease;
    }

    try {
      final response = await _httpClient
          .get(
            Uri.parse(_githubApiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final release = AppRelease.fromGitHubJson(json);

      final currentVersion =
          _currentVersionOverride ?? (await PackageInfo.fromPlatform()).version;

      _lastCheckTime = DateTime.now();

      final hasUpdate =
          skipVersionCheck ||
          VersionComparisonService.hasUpdate(currentVersion, release.version);
      final hasPlatformAsset = release.platformAssets.containsKey(
        _getPlatformKeyword(),
      );

      if (hasUpdate && hasPlatformAsset) {
        _cachedRelease = release;
        return release;
      }

      _cachedRelease = null;
      return null;
    } catch (e) {
      debugPrint('App update check failed: $e');
      return null;
    }
  }

  Future<String> downloadUpdate(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    if (kPlayStoreBuild) {
      throw UnsupportedError('Not available on Play Store build');
    }
    final platformKey = _getPlatformKeyword();
    final url = release.platformAssets[platformKey];
    if (url == null) {
      throw Exception('No download available for $platformKey');
    }

    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await _httpClient.send(request);

    final contentLength = streamedResponse.contentLength ?? 0;
    final bytes = <int>[];
    var received = 0;

    await for (final chunk in streamedResponse.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      if (contentLength > 0 && onProgress != null) {
        onProgress(received / contentLength);
      }
    }

    final tempDir = await _getUpdateDirectory();
    final downloadPath = path.join(
      tempDir.path,
      'nt_helper_update_${release.version}${_downloadExtension(url)}',
    );
    await File(downloadPath).writeAsBytes(bytes);
    return downloadPath;
  }

  Future<InstallResult> installUpdate(String updatePath) async {
    try {
      if (Platform.isWindows &&
          path.extension(updatePath).toLowerCase() == '.exe') {
        return await _installWindowsInstaller(updatePath);
      }

      final tempDir = await _getUpdateDirectory();
      final extractDir = Directory(
        path.join(tempDir.path, 'nt_helper_update_extracted'),
      );
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      if (Platform.isMacOS) {
        // Use ditto to extract on macOS — preserves code signatures,
        // notarization tickets, symlinks, and file permissions.
        final result = await Process.run('ditto', [
          '-x',
          '-k',
          updatePath,
          extractDir.path,
        ]);
        if (result.exitCode != 0) {
          return InstallResult(
            outcome: InstallOutcome.error,
            message: 'Failed to extract update: ${result.stderr}',
          );
        }
        return await _installMacOS(extractDir);
      }

      // Non-macOS: use Dart archive package
      final zipBytes = await File(updatePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      for (final file in archive) {
        final filePath = path.join(extractDir.path, file.name);
        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      if (Platform.isLinux) {
        return await _installLinux(extractDir);
      } else if (Platform.isWindows) {
        return await _installWindows(extractDir);
      }

      return const InstallResult(
        outcome: InstallOutcome.error,
        message: 'Platform not supported for auto-update',
      );
    } catch (e) {
      return InstallResult(
        outcome: InstallOutcome.error,
        message: 'Install failed: $e',
      );
    }
  }

  Future<InstallResult> _installMacOS(Directory extractDir) async {
    final exePath = Platform.resolvedExecutable;
    // Go up 3 levels: MacOS -> Contents -> App.app
    final appBundlePath = path.dirname(path.dirname(path.dirname(exePath)));

    // Find the .app in the extracted directory
    final entities = await extractDir.list().toList();
    Directory? sourceApp;
    for (final entity in entities) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        sourceApp = entity;
        break;
      }
    }

    if (sourceApp == null) {
      return const InstallResult(
        outcome: InstallOutcome.error,
        message: 'Could not find .app bundle in update archive',
      );
    }

    final targetDir = path.dirname(appBundlePath);

    if (_canWriteTo(targetDir)) {
      final result = await Process.run('ditto', [
        sourceApp.path,
        path.join(targetDir, path.basename(sourceApp.path)),
      ]);
      if (result.exitCode == 0) {
        await _removeQuarantineAttribute(appBundlePath);
        return const InstallResult(
          outcome: InstallOutcome.needsRestart,
          message: 'Update installed. Restart to use the new version.',
        );
      }
    }

    // Fallback: copy to ~/Downloads
    return _fallbackToDownloads(sourceApp.path, path.basename(sourceApp.path));
  }

  Future<InstallResult> _installLinux(Directory extractDir) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = path.dirname(exePath);

    if (_canWriteTo(appDir)) {
      final result = await Process.run('cp', [
        '-Rf',
        '${extractDir.path}/.',
        appDir,
      ]);
      if (result.exitCode == 0) {
        await Process.run('chmod', ['+x', exePath]);
        return const InstallResult(
          outcome: InstallOutcome.needsRestart,
          message: 'Update installed. Restart to use the new version.',
        );
      }
    }

    // Fallback: copy to ~/Downloads
    return _fallbackToDownloads(extractDir.path, 'nt_helper');
  }

  Future<InstallResult> _installWindows(Directory extractDir) async {
    final releaseRoot = await findWindowsReleaseRoot(extractDir);
    if (releaseRoot == null) {
      return const InstallResult(
        outcome: InstallOutcome.error,
        message: 'Could not find nt_helper.exe in update archive',
      );
    }

    final exePath = Platform.resolvedExecutable;
    final appDir = path.dirname(exePath);
    final currentPid = pid;

    if (!_canWriteTo(appDir)) {
      return _fallbackToDownloads(releaseRoot.path, 'nt_helper');
    }

    final tempDir = await _getUpdateDirectory();
    final logPath = path.join(tempDir.path, 'nt_helper_update.log');
    final scriptPath = path.join(tempDir.path, 'nt_helper_update.ps1');
    final scriptContent = buildWindowsUpdateScript(
      sourceDir: releaseRoot.path,
      appDir: appDir,
      exePath: exePath,
      logPath: logPath,
      currentPid: currentPid,
    );
    await File(scriptPath).writeAsString(scriptContent);

    await Process.start('powershell.exe', [
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
    ], mode: ProcessStartMode.detached);

    exit(0);
  }

  Future<InstallResult> _installWindowsInstaller(String installerPath) async {
    await _unblockWindowsFile(installerPath);

    final tempDir = await _getUpdateDirectory();
    final logPath = path.join(tempDir.path, 'nt_helper_setup.log');
    await Process.start(
      installerPath,
      buildWindowsInstallerArguments(logPath: logPath),
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }

  @visibleForTesting
  static List<String> buildWindowsInstallerArguments({
    required String logPath,
  }) {
    return ['/CURRENTUSER', '/CLOSEAPPLICATIONS', '/LOG=$logPath'];
  }

  @visibleForTesting
  static Future<Directory?> findWindowsReleaseRoot(Directory extractDir) async {
    final rootExe = File(path.join(extractDir.path, 'nt_helper.exe'));
    if (await rootExe.exists()) {
      return extractDir;
    }

    await for (final entity in extractDir.list(recursive: true)) {
      if (entity is File &&
          path.basename(entity.path).toLowerCase() == 'nt_helper.exe') {
        return entity.parent;
      }
    }

    return null;
  }

  @visibleForTesting
  static String buildWindowsUpdateScript({
    required String sourceDir,
    required String appDir,
    required String exePath,
    required String logPath,
    required int currentPid,
  }) {
    final sourceDirLiteral = _powerShellSingleQuoted(sourceDir);
    final appDirLiteral = _powerShellSingleQuoted(appDir);
    final exePathLiteral = _powerShellSingleQuoted(exePath);
    final logPathLiteral = _powerShellSingleQuoted(logPath);

    return '''
\$ErrorActionPreference = 'Stop'
\$ProgressPreference = 'SilentlyContinue'
\$sourceDir = $sourceDirLiteral
\$appDir = $appDirLiteral
\$exePath = $exePathLiteral
\$logPath = $logPathLiteral
\$currentPid = $currentPid

function Write-UpdateLog {
  param([string]\$Message)
  \$timestamp = Get-Date -Format o
  Add-Content -LiteralPath \$logPath -Value "\$timestamp \$Message"
}

function Copy-ReleaseFiles {
  Get-ChildItem -LiteralPath \$sourceDir -Force | ForEach-Object {
    Copy-Item -LiteralPath \$_.FullName -Destination \$appDir -Recurse -Force
  }
}

try {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent \$logPath) | Out-Null
  Write-UpdateLog "Starting NT Helper update. source=\$sourceDir target=\$appDir pid=\$currentPid"

  \$runningProcess = Get-Process -Id \$currentPid -ErrorAction SilentlyContinue
  if (\$null -ne \$runningProcess) {
    Wait-Process -Id \$currentPid -Timeout 30 -ErrorAction SilentlyContinue
  }

  \$deadline = (Get-Date).AddSeconds(45)
  while (\$true) {
    try {
      Copy-ReleaseFiles
      if (Test-Path -LiteralPath \$exePath) {
        Get-ChildItem -LiteralPath \$appDir -Recurse -File -Force |
          Unblock-File -ErrorAction SilentlyContinue
        Write-UpdateLog 'Copy completed; relaunching NT Helper.'
        Start-Process -FilePath \$exePath -WorkingDirectory \$appDir
        exit 0
      }
      throw "Updated executable not found at \$exePath"
    } catch {
      Write-UpdateLog "Copy attempt failed: \$_"
      if ((Get-Date) -ge \$deadline) {
        throw "Timed out applying update: \$_"
      }
      Start-Sleep -Seconds 1
    }
  }
} catch {
  Write-UpdateLog "Update failed: \$_"
  exit 1
}
''';
  }

  static String _powerShellSingleQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  Future<void> _removeQuarantineAttribute(String appPath) async {
    try {
      await Process.run('xattr', ['-rd', 'com.apple.quarantine', appPath]);
    } catch (e) {
      debugPrint('Warning: Failed to remove quarantine attribute: $e');
    }
  }

  Future<void> _unblockWindowsFile(String filePath) async {
    try {
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Unblock-File -LiteralPath ${_powerShellSingleQuoted(filePath)}',
      ]);
    } catch (e) {
      debugPrint('Warning: Failed to unblock Windows file: $e');
    }
  }

  bool _canWriteTo(String dirPath) {
    try {
      final testFile = File(path.join(dirPath, '.nt_helper_write_test'));
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<InstallResult> _fallbackToDownloads(
    String sourcePath,
    String name,
  ) async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final downloadsDir = Directory(path.join(home, 'Downloads'));

    if (!await downloadsDir.exists()) {
      return const InstallResult(
        outcome: InstallOutcome.error,
        message: 'Cannot find Downloads folder.',
      );
    }

    final destPath = path.join(downloadsDir.path, name);

    // Remove existing if present
    final existing = Directory(destPath);
    if (await existing.exists()) {
      await existing.delete(recursive: true);
    }

    if (Platform.isWindows) {
      try {
        await _copyFileOrDirectory(sourcePath, destPath);
      } catch (e) {
        return InstallResult(
          outcome: InstallOutcome.error,
          message: 'Failed to copy update to Downloads: $e',
        );
      }
    } else {
      final copyResult = Platform.isMacOS
          ? await Process.run('ditto', [sourcePath, destPath])
          : await Process.run('cp', ['-Rf', sourcePath, destPath]);
      if (copyResult.exitCode != 0) {
        return const InstallResult(
          outcome: InstallOutcome.error,
          message: 'Failed to copy update to Downloads.',
        );
      }
    }

    if (Platform.isMacOS) {
      await _removeQuarantineAttribute(destPath);
    }

    return InstallResult(
      outcome: InstallOutcome.success,
      message:
          'Update saved to ~/Downloads/$name. Install it manually from there.',
      folderPath: downloadsDir.path,
    );
  }

  Future<void> _copyFileOrDirectory(String sourcePath, String destPath) async {
    final sourceType = await FileSystemEntity.type(sourcePath);
    if (sourceType == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(sourcePath), Directory(destPath));
    } else if (sourceType == FileSystemEntityType.file) {
      await File(destPath).parent.create(recursive: true);
      await File(sourcePath).copy(destPath);
    } else {
      throw FileSystemException('Source does not exist', sourcePath);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final childDestination = path.join(
        destination.path,
        path.basename(entity.path),
      );
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(childDestination));
      } else if (entity is File) {
        await File(childDestination).parent.create(recursive: true);
        await entity.copy(childDestination);
      }
    }
  }

  Future<Directory> _getUpdateDirectory() async {
    final appSupport = await getApplicationSupportDirectory();
    final updateDir = Directory(path.join(appSupport.path, 'app-update'));
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }
    return updateDir;
  }

  /// Launches a platform-specific script that waits for this process to exit,
  /// then relaunches the app. Calls `exit(0)` after launching the script.
  static Future<void> relaunchApp() async {
    final currentPid = pid;
    final tempDir = await getApplicationSupportDirectory();
    final updateDir = Directory(path.join(tempDir.path, 'app-update'));
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    if (Platform.isMacOS) {
      final exePath = Platform.resolvedExecutable;
      // Go up 3 levels: MacOS -> Contents -> App.app
      final appBundlePath = path.dirname(path.dirname(path.dirname(exePath)));
      final scriptPath = path.join(updateDir.path, 'relaunch.sh');
      await File(scriptPath).writeAsString('''
#!/bin/bash
while kill -0 $currentPid 2>/dev/null; do sleep 0.2; done
sleep 0.5
open "$appBundlePath"
''');
      await Process.run('chmod', ['+x', scriptPath]);
      await Process.start('/bin/bash', [
        scriptPath,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      final exePath = Platform.resolvedExecutable;
      final scriptPath = path.join(updateDir.path, 'relaunch.sh');
      await File(scriptPath).writeAsString('''
#!/bin/bash
while kill -0 $currentPid 2>/dev/null; do sleep 0.2; done
sleep 0.5
nohup "$exePath" &>/dev/null &
''');
      await Process.run('chmod', ['+x', scriptPath]);
      await Process.start('/bin/bash', [
        scriptPath,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      final scriptPath = path.join(updateDir.path, 'relaunch.ps1');
      await File(scriptPath).writeAsString('''
Start-Sleep -Seconds 2
try { Wait-Process -Id $currentPid -Timeout 10 -ErrorAction SilentlyContinue } catch {}
Start-Process "$exePath"
''');
      await Process.start('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
      ], mode: ProcessStartMode.detached);
    }

    exit(0);
  }

  String _getPlatformKeyword() {
    if (_platformKeyOverride != null) return _platformKeyOverride;
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    throw UnsupportedError('Platform not supported for app updates');
  }

  String _downloadExtension(String url) {
    final uri = Uri.tryParse(url);
    final filename = uri == null ? '' : path.basename(uri.path);
    final extension = path.extension(filename).toLowerCase();
    if (extension == '.exe') return '.exe';
    return '.zip';
  }
}
