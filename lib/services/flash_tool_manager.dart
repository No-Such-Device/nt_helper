import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/services/github_tls_support.dart';
import 'package:nt_helper/services/startup_log_service.dart';
import 'package:nt_helper/services/tls_certificate_diagnostics.dart';
import 'package:nt_helper/utils/sandbox_utils.dart';
import 'package:nt_helper/utils/build_config.dart';

typedef TrustedHttpClientFactory = Future<http.Client> Function();
typedef TlsDiagnostics = Future<String> Function(Uri uri);

/// Manages the nt-flash tool binary - auto-downloading from GitHub releases
class FlashToolManager {
  final http.Client _httpClient;
  final TrustedHttpClientFactory _trustedClientFactory;
  final TlsDiagnostics _tlsDiagnostics;
  final String _operatingSystem;
  final String _resolvedExecutable;
  final bool _isSandboxed;
  final Directory? _toolDirectoryOverride;

  static const String _githubApiUrl =
      'https://api.github.com/repos/thorinside/nt-flash/releases/latest';
  static const _trustedRootRetryHosts = {
    'api.github.com',
    'github.com',
    'release-assets.githubusercontent.com',
  };

  FlashToolManager({
    http.Client? httpClient,
    TrustedHttpClientFactory? trustedClientFactory,
    TlsDiagnostics? tlsDiagnostics,
    String? operatingSystemOverride,
    String? resolvedExecutableOverride,
    bool? isSandboxedOverride,
    Directory? toolDirectoryOverride,
  }) : _httpClient = httpClient ?? http.Client(),
       _trustedClientFactory =
           trustedClientFactory ?? GitHubTlsSupport.createTrustedClient,
       _tlsDiagnostics = tlsDiagnostics ?? TlsCertificateDiagnostics.inspect,
       _operatingSystem = operatingSystemOverride ?? Platform.operatingSystem,
       _resolvedExecutable =
           resolvedExecutableOverride ?? Platform.resolvedExecutable,
       _isSandboxed =
           isSandboxedOverride ??
           (Platform.isMacOS && SandboxUtils.isSandboxed),
       _toolDirectoryOverride = toolDirectoryOverride;

  /// Get the path to the nt-flash tool
  ///
  /// - Windows builds: Prefer nt-flash.exe bundled beside nt_helper.exe
  /// - Sandboxed macOS builds: Use the bundled helper app
  /// - Other builds: Download to Application Support if needed
  Future<String> getToolPath() async {
    if (_isWindows || (_isMacOS && _isSandboxed)) {
      final bundledPath = _getBundledToolPath();
      if (await _isToolPresent(bundledPath)) {
        return bundledPath;
      }

      // A sandboxed macOS app cannot download and execute a new helper. Windows
      // retains the legacy download path for development and older packages.
      if (_isMacOS && _isSandboxed) {
        throw const FlashToolDownloadException(
          'Bundled nt-flash binary not found. This is a build configuration error.',
        );
      }
    }

    // Non-sandboxed: download on demand
    final toolDir = await _getToolDirectory();
    final binaryName = _getBinaryName();
    final toolPath = path.join(toolDir.path, binaryName);

    if (await _isToolPresent(toolPath)) {
      return toolPath;
    }

    await _downloadTool(toolDir.path, binaryName);
    return toolPath;
  }

  /// Get the platform-specific path to a bundled nt-flash binary.
  ///
  /// The binary is placed in Contents/Helpers/nt-flash.app/Contents/MacOS/nt-flash
  /// as a proper helper bundle during the TestFlight build process.
  String _getBundledToolPath() {
    if (_isWindows) {
      return path.join(path.dirname(_resolvedExecutable), 'nt-flash.exe');
    }

    // Platform.resolvedExecutable is /path/to/App.app/Contents/MacOS/nt_helper
    final exeDir = path.dirname(_resolvedExecutable);
    final contentsDir = path.dirname(exeDir);
    return path.join(
      contentsDir,
      'Helpers',
      'nt-flash.app',
      'Contents',
      'MacOS',
      'nt-flash',
    );
  }

  /// Get the directory where the tool is stored
  Future<Directory> _getToolDirectory() async {
    final override = _toolDirectoryOverride;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }

    final appSupport = await getApplicationSupportDirectory();
    final toolDir = Directory(path.join(appSupport.path, 'nt-flash'));
    if (!await toolDir.exists()) {
      await toolDir.create(recursive: true);
    }
    return toolDir;
  }

  /// Check if the tool is present and executable (on Unix)
  Future<bool> _isToolPresent(String toolPath) async {
    final file = File(toolPath);
    if (!await file.exists()) {
      return false;
    }

    // On Unix, check executable permission
    if (_isLinux || _isMacOS) {
      final stat = await file.stat();
      // Check if any execute bit is set (owner, group, or other)
      return (stat.mode & 0x49) != 0; // 0x49 = 0111 in octal (execute bits)
    }

    return true;
  }

  /// Get the binary name after extraction
  String _getBinaryName() {
    if (_isWindows) {
      return 'nt-flash.exe';
    }
    return 'nt-flash';
  }

  /// Get the platform keyword used in asset names (macos, windows, linux)
  String _getPlatformKeyword() {
    if (_isMacOS) {
      return 'macos';
    } else if (_isWindows) {
      return 'windows';
    } else if (_isLinux) {
      return 'linux';
    }
    throw UnsupportedError('Platform not supported for firmware updates');
  }

  /// Download and extract the tool from GitHub releases
  Future<void> _downloadTool(String toolDir, String binaryName) async {
    if (kPlayStoreBuild) return;
    // Fetch latest release info from GitHub API
    final releaseResponse = await _getWithTlsFallback(
      Uri.parse(_githubApiUrl),
      headers: {'Accept': 'application/vnd.github.v3+json'},
      purpose: 'fetching nt-flash release metadata',
    );

    if (releaseResponse.statusCode != 200) {
      throw FlashToolDownloadException(
        'Failed to fetch release info: HTTP ${releaseResponse.statusCode}',
      );
    }

    final releaseData =
        jsonDecode(releaseResponse.body) as Map<String, dynamic>;
    final assets = releaseData['assets'] as List<dynamic>?;

    if (assets == null || assets.isEmpty) {
      throw const FlashToolDownloadException('No assets found in release');
    }

    // Find the matching archive asset by platform keyword
    final platformKeyword = _getPlatformKeyword();
    String? downloadUrl;
    String? assetFileName;
    for (final asset in assets) {
      final assetName = asset['name'] as String?;
      if (assetName != null && assetName.contains(platformKeyword)) {
        downloadUrl = asset['browser_download_url'] as String?;
        assetFileName = assetName;
        break;
      }
    }

    if (downloadUrl == null || assetFileName == null) {
      throw FlashToolDownloadException(
        'No $platformKeyword release asset found',
      );
    }

    // Download the archive
    final archiveResponse = await _getWithTlsFallback(
      Uri.parse(downloadUrl),
      purpose: 'downloading the nt-flash archive',
    );

    if (archiveResponse.statusCode != 200) {
      throw FlashToolDownloadException(
        'Failed to download archive: HTTP ${archiveResponse.statusCode}',
      );
    }

    // Extract the binary from the archive
    await _extractBinary(
      archiveResponse.bodyBytes,
      assetFileName,
      toolDir,
      binaryName,
    );

    final toolPath = path.join(toolDir, binaryName);

    // Set executable permission on Unix
    if (_isLinux || _isMacOS) {
      final chmodResult = await Process.run('chmod', ['+x', toolPath]);
      if (chmodResult.exitCode != 0) {
        throw FlashToolDownloadException(
          'Failed to set executable permission: ${chmodResult.stderr}',
        );
      }
    }

    // On macOS, remove quarantine attribute (best effort)
    if (_isMacOS) {
      await _removeQuarantineAttribute(toolPath);
    }
  }

  Future<http.Response> _getWithTlsFallback(
    Uri uri, {
    Map<String, String>? headers,
    required String purpose,
  }) async {
    try {
      return await _httpClient.get(uri, headers: headers);
    } catch (error) {
      if (!TlsCertificateDiagnostics.isTlsFailure(error)) rethrow;

      final diagnostics = await _safeTlsDiagnostics(uri);
      if (!_trustedRootRetryHosts.contains(uri.host)) {
        throw FlashToolDownloadException(
          'TLS certificate verification failed for ${uri.host} while '
          '$purpose. A trusted-root retry is not permitted for this host. '
          '$diagnostics',
        );
      }

      http.Client? trustedClient;
      try {
        trustedClient = await _trustedClientFactory();
        final response = await trustedClient.get(uri, headers: headers);
        StartupLogService.log(
          'FlashToolManager: bundled GitHub roots recovered TLS for '
          '${uri.host}. $diagnostics',
        );
        return response;
      } catch (trustedError) {
        throw FlashToolDownloadException(
          'TLS certificate verification failed for ${uri.host} while '
          '$purpose. The retry with bundled public roots also failed: '
          '$trustedError. $diagnostics',
        );
      } finally {
        trustedClient?.close();
      }
    }
  }

  Future<String> _safeTlsDiagnostics(Uri uri) async {
    try {
      return await _tlsDiagnostics(uri);
    } catch (error) {
      return 'certificateDiagnosticsUnavailable=$error';
    }
  }

  /// Extract the nt-flash binary from a zip or tar.gz archive
  Future<void> _extractBinary(
    List<int> archiveBytes,
    String assetFileName,
    String toolDir,
    String binaryName,
  ) async {
    Archive archive;

    if (assetFileName.endsWith('.zip')) {
      archive = ZipDecoder().decodeBytes(archiveBytes);
    } else if (assetFileName.endsWith('.tar.gz')) {
      final tarBytes = GZipDecoder().decodeBytes(archiveBytes);
      archive = TarDecoder().decodeBytes(tarBytes);
    } else {
      throw FlashToolDownloadException(
        'Unsupported archive format: $assetFileName',
      );
    }

    // Find the nt-flash binary in the archive
    ArchiveFile? binaryFile;
    for (final file in archive) {
      // The binary is named 'nt-flash' (or 'nt-flash.exe' on Windows)
      // It may be in a subdirectory like 'nt-flash-v1.1.0-macos/'
      final fileName = path.basename(file.name);
      if (fileName == binaryName && file.isFile) {
        binaryFile = file;
        break;
      }
    }

    if (binaryFile == null) {
      throw FlashToolDownloadException(
        'Binary $binaryName not found in archive',
      );
    }

    // Write the binary to the tool directory
    final outputPath = path.join(toolDir, binaryName);
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(binaryFile.content as List<int>);
  }

  /// Remove macOS quarantine attribute (best effort - logs warning on failure)
  Future<void> _removeQuarantineAttribute(String toolPath) async {
    try {
      final result = await Process.run('xattr', [
        '-d',
        'com.apple.quarantine',
        toolPath,
      ]);
      if (result.exitCode != 0) {
        // Log warning but don't fail - the attribute might not exist
        // which is fine (exitCode 1 with "No such xattr")
        final stderr = result.stderr.toString().trim();
        if (!stderr.contains('No such xattr')) {
          debugPrint('Warning: Failed to remove quarantine attribute: $stderr');
        }
      }
    } catch (e) {
      // xattr command might not be available, log but don't fail
      debugPrint('Warning: xattr command failed: $e');
    }
  }

  /// Visible for testing - get platform keyword
  static String getPlatformKeywordForTesting({
    required bool isMacOS,
    required bool isWindows,
    required bool isLinux,
  }) {
    if (isMacOS) {
      return 'macos';
    } else if (isWindows) {
      return 'windows';
    } else if (isLinux) {
      return 'linux';
    }
    throw UnsupportedError('Platform not supported for firmware updates');
  }

  /// Visible for testing - get binary name
  static String getBinaryNameForTesting({required bool isWindows}) {
    return isWindows ? 'nt-flash.exe' : 'nt-flash';
  }

  bool get _isWindows => _operatingSystem == 'windows';
  bool get _isMacOS => _operatingSystem == 'macos';
  bool get _isLinux => _operatingSystem == 'linux';
}
