import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:nt_helper/services/ipad_firmware_session.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:nt_helper/utils/temp_directory_utils.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/firmware_version.dart';

/// Exception thrown during firmware download operations
class FirmwareDownloadException implements Exception {
  final String message;
  const FirmwareDownloadException(this.message);

  @override
  String toString() => 'FirmwareDownloadException: $message';
}

/// Immutable selected target and package snapshot, retained until verification.
/// The hash records bytes, not vendor authentication.
class PreparedFirmwarePackage {
  final String version;
  final String packagePath;
  final String sha256Hash;
  final Uint8List loader;
  final Uint8List application;

  PreparedFirmwarePackage._(
    this.version,
    this.packagePath,
    List<int> bytes,
    List<int> loader,
    List<int> application,
  ) : sha256Hash = sha256.convert(bytes).toString(),
      loader = Uint8List.fromList(loader).asUnmodifiableView(),
      application = Uint8List.fromList(application).asUnmodifiableView();
}

/// Service for checking firmware versions and downloading updates
class FirmwareVersionService {
  static const String _firmwarePageUrl =
      'https://expert-sleepers.co.uk/distingNTfirmwareupdates.html';
  static const String _baseUrl = 'https://expert-sleepers.co.uk/';

  /// Cached firmware releases for the session
  List<FirmwareRelease>? _cachedReleases;
  DateTime? _lastFetch;
  final Duration _cacheTimeout = const Duration(minutes: 30);

  /// HTTP client (can be injected for testing)
  final http.Client _httpClient;

  FirmwareVersionService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Fetch available firmware versions from Expert Sleepers website
  ///
  /// Results are cached for the session to avoid repeated network requests.
  Future<List<FirmwareRelease>> fetchAvailableVersions({
    bool forceRefresh = false,
  }) async {
    // Return cached data if valid
    if (!forceRefresh &&
        _cachedReleases != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheTimeout) {
      return _cachedReleases!;
    }

    try {
      final response = await _httpClient
          .get(
            Uri.parse(_firmwarePageUrl),
            headers: {'User-Agent': 'nt_helper'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw FirmwareDownloadException(
          'Failed to fetch firmware page: HTTP ${response.statusCode}',
        );
      }

      final releases = _parseHtml(response.body);
      _cachedReleases = releases;
      _lastFetch = DateTime.now();

      return releases;
    } catch (e) {
      if (e is FirmwareDownloadException) rethrow;
      throw FirmwareDownloadException('Network error: $e');
    }
  }

  /// Parse HTML to extract firmware releases
  List<FirmwareRelease> _parseHtml(String htmlContent) {
    final document = html_parser.parse(htmlContent);
    final releases = <FirmwareRelease>[];

    // Find the firmware table - look for table with version info
    final tables = document.querySelectorAll('table');

    for (final table in tables) {
      final rows = table.querySelectorAll('tr');

      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 3) continue;

        // Try to extract version, date, and changelog from cells
        final release = _parseTableRow(cells);
        if (release != null) {
          releases.add(release);
        }
      }
    }

    // Sort by version (newest first)
    releases.sort((a, b) => b.compareToVersion(a.version));

    return releases;
  }

  /// Parse a single table row to extract firmware release info
  FirmwareRelease? _parseTableRow(List<dynamic> cells) {
    String? version;
    DateTime? releaseDate;
    String? downloadUrl;
    final changelog = <String>[];

    for (final cell in cells) {
      final text = cell.text.trim();

      // Check for version number (X.Y.Z format)
      if (version == null && _isVersionString(text)) {
        version = text;
        continue;
      }

      // Check for date (DD/MM/YYYY format)
      if (releaseDate == null) {
        final date = _parseDate(text);
        if (date != null) {
          releaseDate = date;
          continue;
        }
      }

      // Check for download link
      if (downloadUrl == null) {
        final links = cell.querySelectorAll('a');
        for (final link in links) {
          final href = link.attributes['href'];
          if (href != null &&
              href.endsWith('.zip') &&
              href.contains('distingNT')) {
            downloadUrl = _resolveUrl(href);
            break;
          }
        }
      }

      // Extract changelog items from lists
      final listItems = cell.querySelectorAll('li');
      for (final item in listItems) {
        final itemText = item.text.trim();
        if (itemText.isNotEmpty) {
          changelog.add(itemText);
        }
      }
    }

    // Require at minimum version and download URL
    if (version == null || downloadUrl == null) {
      return null;
    }

    return FirmwareRelease(
      version: version,
      releaseDate: releaseDate ?? DateTime.now(),
      changelog: changelog,
      downloadUrl: downloadUrl,
    );
  }

  /// Check if a string looks like a version number (X.Y.Z)
  bool _isVersionString(String text) {
    final versionRegex = RegExp(r'^\d+\.\d+\.\d+$');
    return versionRegex.hasMatch(text);
  }

  /// Parse date in DD/MM/YYYY or D/M/YYYY format
  DateTime? _parseDate(String text) {
    // Try DD/MM/YYYY or D/M/YYYY format
    final dateRegex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
    final match = dateRegex.firstMatch(text);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      try {
        return DateTime(year, month, day);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Resolve relative URL to absolute URL
  String _resolveUrl(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return '$_baseUrl$href';
  }

  /// Get the latest available firmware version
  FirmwareRelease? getLatestVersion(List<FirmwareRelease> versions) {
    if (versions.isEmpty) return null;
    // Versions are already sorted newest first
    return versions.first;
  }

  /// Check if an update is available compared to current version
  ///
  /// [currentVersion] - The currently installed firmware version (e.g., "1.11.0")
  /// [available] - List of available firmware releases
  bool isUpdateAvailable(
    String currentVersion,
    List<FirmwareRelease> available,
  ) {
    final latest = getLatestVersion(available);
    if (latest == null) return false;

    // Use FirmwareVersion class for robust comparison
    // It uses regex to extract numeric parts, handling versions like "1.13.0beta"
    final currentFw = FirmwareVersion(currentVersion);
    final latestFw = FirmwareVersion(latest.version);

    // Update available if latest is greater than current
    return latestFw.isGreaterThan(currentFw);
  }

  /// Download firmware package to temp directory
  ///
  /// Returns the path to the downloaded .zip file.
  /// Emits progress through [onProgress] callback (0.0 to 1.0).
  Future<String> downloadFirmware(
    FirmwareRelease version, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await TempDirectoryUtils.getWritableTempDirectory();
    final fileName = 'distingNT_${version.version}.zip';
    final filePath = path.join(tempDir.path, fileName);

    try {
      final request = http.Request('GET', Uri.parse(version.downloadUrl))
        ..headers['User-Agent'] = 'nt_helper';
      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        throw FirmwareDownloadException(
          'Download failed: HTTP ${response.statusCode}',
        );
      }

      final file = File(filePath);
      final sink = file.openWrite();
      final contentLength = response.contentLength ?? 0;
      int bytesReceived = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(bytesReceived / contentLength);
        }
      }

      await sink.close();

      // Verify the ZIP is valid
      await _verifyZip(filePath);

      return filePath;
    } catch (e) {
      // Clean up partial download on failure
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      if (e is FirmwareDownloadException) rethrow;
      throw FirmwareDownloadException('Download error: $e');
    }
  }

  /// Verify that the downloaded ZIP is valid by attempting to list its entries.
  ///
  /// Expert Sleepers firmware packages contain:
  /// - bootable_images/disting_NT.bin - the firmware binary
  /// - write_image_mac.sh / write_image_win.bat / write_image_lnx.sh - flash scripts
  /// - MANIFEST.json - package manifest
  Future<void> _verifyZip(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      if (archive.isEmpty) {
        throw FirmwareDownloadException('ZIP archive is empty');
      }

      // Check for expected firmware file (disting_NT.bin in bootable_images/)
      final hasFirmware = archive.any(
        (file) =>
            file.name.toLowerCase().contains('disting') &&
            file.name.toLowerCase().endsWith('.bin'),
      );
      if (!hasFirmware) {
        throw FirmwareDownloadException(
          'ZIP does not contain expected firmware file (disting_NT.bin)',
        );
      }
    } catch (e) {
      if (e is FirmwareDownloadException) rethrow;
      throw FirmwareDownloadException(
        'ZIP verification failed: corrupted archive',
      );
    }
  }

  /// Accept only the known unsigned NT recipe. Addresses are fixed by the
  /// native API, never supplied by package scripts or caller metadata.
  static PreparedFirmwarePackage validateIpadPackage(
    FirmwareRelease release,
    String packagePath,
    List<int> bytes, {
    bool allowLocalFile = false,
  }) {
    const loaderName = 'bootable_images/unsigned_MIMXRT1060_flashloader.bin';
    const appName = 'bootable_images/disting_NT.bin';
    const limits = {
      'MANIFEST.json': 16384,
      loaderName: MethodChannelIpadFirmwareSession.maxLoader,
      appName: MethodChannelIpadFirmwareSession.maxApplication,
    };
    void reject() => throw const FirmwareDownloadException(
      'Unsupported or invalid unsigned MIMXRT1060 firmware package',
    );
    final validVersion =
        RegExp(r'^\d+\.\d+\.\d+$').hasMatch(release.version) ||
        (allowLocalFile &&
            (release.version == 'local' ||
                RegExp(
                  r'^\d+\.\d+\.\d+(?:[-.]?beta\d*)$',
                ).hasMatch(release.version)));
    if (!validVersion || bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      reject();
    }
    try {
      // Inspect original directory entries: Archive coalesces duplicate names.
      final directory = ZipDirectory()..read(InputMemoryStream(bytes));
      final names = <String>{};
      var total = 0;
      for (final entry in directory.fileHeaders) {
        final name = entry.filename;
        final parts = name.split('/');
        if (name.isEmpty ||
            name.startsWith('/') ||
            name.contains('\\') ||
            name.contains(':') ||
            name.contains('\u0000') ||
            parts.any((p) => p == '..' || p == '.') ||
            !names.add(name) ||
            ((entry.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
            entry.generalPurposeBitFlag & 1 != 0 ||
            entry.uncompressedSize < 0 ||
            entry.uncompressedSize > (limits[name] ?? 8 * 1024 * 1024) ||
            entry.file?.filename != name ||
            entry.file?.uncompressedSize != entry.uncompressedSize) {
          reject();
        }
        total += entry.uncompressedSize;
        if (total > 32 * 1024 * 1024) reject();
      }
      if (!names.containsAll(limits.keys)) reject();
      final archive = ZipDecoder().decodeBytes(bytes);
      Uint8List member(String name) {
        final file = archive.find(name)!;
        final data = file.readBytes();
        if (!file.isFile ||
            data == null ||
            data.isEmpty ||
            data.length != file.size ||
            data.length > limits[name]! ||
            getCrc32(data) != file.crc32) {
          reject();
        }
        return data!;
      }

      final manifest = jsonDecode(utf8.decode(member('MANIFEST.json')));
      if (manifest is! Map ||
          manifest['processor'] != 'MIMXRT1060' ||
          manifest['mfp_type'] != 'write_script' ||
          manifest['provisioning_type'] != 'disabled' ||
          manifest['boot_type'] != 'unsigned' ||
          manifest['life_cycle'] != 'open_develop' ||
          manifest['app_firmware'] != appName) {
        reject();
      }
      final connection = manifest['connection'];
      if (connection is! Map ||
          connection['connection_type'] != 'usb' ||
          connection['usb_hid'] is! Map ||
          connection['usb_hid']['usbVid_int'] != '0x1FC9' ||
          connection['usb_hid']['usbPid_int'] != '0x0135') {
        reject();
      }
      final loader = member(loaderName);
      final application = member(appName);
      void checkImage(
        Uint8List image,
        int base,
        int limit, {
        required bool flash,
      }) {
        if (image.length < 44 || image.length > limit - base) reject();
        final data = ByteData.sublistView(image);
        int word(int offset) => data.getUint32(offset, Endian.little);
        // Known unsigned IVT + boot-data format. Never derive native addresses
        // from these fields; reject unsupported pointers and image recipes.
        final entry = word(4) & ~1;
        final bootOffset = word(16) - base;
        if (word(0) != 0x402000d1 ||
            word(8) != 0 ||
            word(12) != 0 ||
            word(20) != base ||
            word(24) != 0 ||
            word(28) != 0 ||
            word(4) & 1 != 1 ||
            entry < base ||
            entry - base >= image.length ||
            bootOffset < 32 ||
            bootOffset > image.length - 12) {
          reject();
        }
        final prefix = flash ? 0x1000 : 0;
        if (word(bootOffset) != base - prefix ||
            word(bootOffset + 4) != image.length + prefix ||
            word(bootOffset + 8) != 0) {
          reject();
        }
      }

      checkImage(loader, 0x20001c00, 0x20020000, flash: false);
      checkImage(application, 0x60001000, 0x60800000, flash: true);
      // Subtraction-first bounds avoid overflowing end-address calculations.
      if (loader.length > 0x20020000 - 0x20001c00 ||
          application.length > 0x60800000 - 0x60001000 ||
          application.length > 0x800000 - 0x1000) {
        reject();
      }
      final eraseLength =
          ((application.length + 0x1000 + 0xfff) ~/ 0x1000) * 0x1000;
      if (eraseLength > 0x800000) reject();
      return PreparedFirmwarePackage._(
        release.version,
        packagePath,
        bytes,
        loader,
        application,
      );
    } on FirmwareDownloadException {
      rethrow;
    } catch (_) {
      reject();
      rethrow;
    }
  }

  /// Snapshot in a unique app-local directory before any MIDI handoff.
  Future<PreparedFirmwarePackage> prepareIpadPackage(
    FirmwareRelease release,
    String downloadedPath,
  ) async {
    final bytes = await File(downloadedPath).readAsBytes();
    return prepareIpadPackageBytes(release, bytes);
  }

  /// Validate and snapshot local or downloaded bytes before USB ownership changes.
  Future<PreparedFirmwarePackage> prepareIpadPackageBytes(
    FirmwareRelease release,
    List<int> bytes, {
    bool allowLocalFile = false,
  }) async {
    validateIpadPackage(release, '', bytes, allowLocalFile: allowLocalFile);
    final root = await TempDirectoryUtils.getWritableTempDirectory();
    final directory = await root.createTemp('nt-firmware-session-');
    final snapshot = File(path.join(directory.path, 'package.zip'));
    try {
      await snapshot.writeAsBytes(bytes, flush: true);
      return validateIpadPackage(
        release,
        snapshot.path,
        bytes,
        allowLocalFile: allowLocalFile,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  /// Match only normal application reply formatting, never numeric substrings.
  static bool matchesApplicationVersion(String? reply, String expected) {
    if (reply == null) return false;
    final match = RegExp(r'^v?(\d+\.\d+\.\d+(?:[-.]?beta\d*)?)$');
    // Normal NT responses append a newline-separated build date.
    final version = reply.trim().split('\n');
    if (version.length > 2) return false;
    if (version.length == 2 &&
        !RegExp(
          r'^(?:\d{4}-\d{2}-\d{2}|[A-Z][a-z]{2} +\d{1,2} +\d{4})$',
        ).hasMatch(version[1].trim())) {
      return false;
    }
    return match.firstMatch(version.first.trim())?.group(1) == expected;
  }

  /// Delete a downloaded firmware package
  Future<void> deleteFirmwarePackage(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Silently ignore deletion errors - file may already be gone
    }
  }

  /// Clear cached firmware release data
  void clearCache() {
    _cachedReleases = null;
    _lastFetch = null;
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
  }
}
