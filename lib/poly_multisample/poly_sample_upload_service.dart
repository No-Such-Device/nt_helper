import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_apply_service.dart';

typedef PolySampleUploadProgress = void Function(String message);

class PolySampleUploadException implements Exception {
  const PolySampleUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PolySampleUploadFile {
  const PolySampleUploadFile({
    required this.sourcePath,
    required this.targetPath,
    required this.displayName,
  });

  final String sourcePath;
  final String targetPath;
  final String displayName;
}

class PolySampleUploadResult {
  const PolySampleUploadResult({
    required this.filesUploaded,
    required this.bytesUploaded,
    required this.correctedFiles,
    this.failedVerificationFiles = 0,
  });

  final int filesUploaded;
  final int bytesUploaded;
  final int correctedFiles;
  final int failedVerificationFiles;
}

class PolySampleUploadValidationResult {
  const PolySampleUploadValidationResult({
    required this.filesChecked,
    required this.bytesChecked,
    required this.failedFiles,
  });

  final int filesChecked;
  final int bytesChecked;
  final int failedFiles;
}

const int _sysExUploadChunkSize = 512;

class PolySampleUploadService {
  const PolySampleUploadService({
    this._applyService = const PolySampleApplyService(),
  });

  final PolySampleApplyService _applyService;

  List<PolySampleUploadFile> buildUploadFiles({
    required List<PolySampleRegion> regions,
    required String targetFolder,
    p.Context? pathContext,
  }) {
    final paths = pathContext ?? p.context;
    final includeVelocity = regions.any(
      (region) => (region.velocityLayer ?? 1) > 1,
    );
    final includeRoundRobin = regions.any(
      (region) => (region.roundRobin ?? 1) > 1,
    );
    final files = <PolySampleUploadFile>[];
    final targets = <String>{};

    for (final region in regions) {
      final fileName = _applyService.buildTargetFileName(
        region,
        includeVelocity: includeVelocity,
        includeRoundRobin: includeRoundRobin,
        pathContext: paths,
      );
      final targetPath = paths.normalize(paths.join(targetFolder, fileName));
      if (!targets.add(targetPath)) {
        throw PolySampleUploadException(
          'Multiple samples target ${paths.basename(targetPath)}.',
        );
      }
      files.add(
        PolySampleUploadFile(
          sourcePath: region.path,
          targetPath: targetPath,
          displayName: region.displayName,
        ),
      );
    }

    return files;
  }

  Future<PolySampleUploadResult> uploadMountedSd({
    required List<PolySampleRegion> regions,
    required String destinationFolder,
    PolySampleUploadProgress? onProgress,
  }) async {
    final files = buildUploadFiles(
      regions: regions,
      targetFolder: destinationFolder,
    );
    var filesUploaded = 0;
    var bytesUploaded = 0;
    var totalBytes = 0;
    for (final file in files) {
      totalBytes += await File(file.sourcePath).length();
    }
    final progress = _TransferProgress(
      totalBytes: totalBytes,
      onProgress: onProgress,
    );

    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final source = File(file.sourcePath);
      final targetPath = p.normalize(file.targetPath);
      final sourcePath = p.normalize(source.path);
      final sourceLength = await source.length();
      progress.emitCurrent(
        action: 'Uploading',
        displayName: file.displayName,
        fileIndex: index + 1,
        fileCount: files.length,
      );
      if (sourcePath == targetPath) {
        progress.advance(
          bytes: sourceLength,
          action: 'Uploading',
          displayName: file.displayName,
          fileIndex: index + 1,
          fileCount: files.length,
        );
        filesUploaded++;
        bytesUploaded += sourceLength;
        continue;
      }

      final target = File(targetPath);
      final parent = Directory(p.dirname(targetPath));
      await parent.create(recursive: true);
      final tempPath = _uniqueTempPath(targetPath);
      final temp = File(tempPath);
      try {
        await _copyFileWithProgress(
          source,
          temp,
          onBytesCopied: (byteCount) {
            progress.advance(
              bytes: byteCount,
              action: 'Uploading',
              displayName: file.displayName,
              fileIndex: index + 1,
              fileCount: files.length,
            );
          },
        );
        if (await target.exists()) {
          await target.delete();
        }
        await temp.rename(targetPath);
      } catch (_) {
        try {
          if (await temp.exists()) {
            await temp.delete();
          }
        } on FileSystemException {
          // Best-effort cleanup only.
        }
        rethrow;
      }
      filesUploaded++;
      bytesUploaded += sourceLength;
    }

    return PolySampleUploadResult(
      filesUploaded: filesUploaded,
      bytesUploaded: bytesUploaded,
      correctedFiles: 0,
    );
  }

  Future<PolySampleUploadResult> uploadSysEx({
    required IDistingMidiManager manager,
    required List<PolySampleRegion> regions,
    required String hardwareFolder,
    PolySampleUploadProgress? onProgress,
  }) async {
    final files = buildUploadFiles(
      regions: regions,
      targetFolder: hardwareFolder,
      pathContext: p.posix,
    );
    var filesUploaded = 0;
    var bytesUploaded = 0;
    final uploadedFiles = <_UploadedHardwareFile>[];
    var totalBytes = 0;
    for (final file in files) {
      totalBytes += await File(file.sourcePath).length();
    }
    final progress = _TransferProgress(
      totalBytes: totalBytes,
      onProgress: onProgress,
    );

    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      progress.emitCurrent(
        action: 'Uploading',
        displayName: file.displayName,
        fileIndex: index + 1,
        fileCount: files.length,
      );
      await _ensureHardwareParent(manager, file.targetPath);
      final bytes = await File(file.sourcePath).readAsBytes();
      await _uploadHardwareFile(
        manager,
        file.targetPath,
        bytes,
        onChunkTransferred: (byteCount) {
          progress.advance(
            bytes: byteCount,
            action: 'Uploading',
            displayName: file.displayName,
            fileIndex: index + 1,
            fileCount: files.length,
          );
        },
      );
      filesUploaded++;
      bytesUploaded += bytes.length;
      uploadedFiles.add(
        _UploadedHardwareFile(file: file, byteLength: bytes.length),
      );
    }

    final verification = await _verifyHardwareFiles(
      manager,
      uploadedFiles,
      progress,
    );

    return PolySampleUploadResult(
      filesUploaded: filesUploaded,
      bytesUploaded: bytesUploaded,
      correctedFiles: verification.correctedFiles,
      failedVerificationFiles: verification.failedFiles,
    );
  }

  Future<PolySampleUploadValidationResult> validateSysEx({
    required IDistingMidiManager manager,
    required List<PolySampleRegion> regions,
    required String hardwareFolder,
    bool verifyContent = false,
    PolySampleUploadProgress? onProgress,
  }) async {
    final files = buildUploadFiles(
      regions: regions,
      targetFolder: hardwareFolder,
      pathContext: p.posix,
    );
    final uploadedFiles = <_UploadedHardwareFile>[];
    var totalBytes = 0;
    for (final file in files) {
      final byteLength = await File(file.sourcePath).length();
      totalBytes += byteLength;
      uploadedFiles.add(
        _UploadedHardwareFile(file: file, byteLength: byteLength),
      );
    }
    onProgress?.call('Validating ${files.length} uploaded sample(s)...');
    final preflight = await _preflightHardwareFiles(
      manager,
      hardwareFolder,
      uploadedFiles,
    );
    if (preflight.failedFiles > 0) {
      onProgress?.call(
        'Validation found ${preflight.failedFiles} missing or size-mismatched '
        'sample(s) before content checks.',
      );
    }
    if (!verifyContent) {
      return PolySampleUploadValidationResult(
        filesChecked: files.length,
        bytesChecked: totalBytes,
        failedFiles: preflight.failedFiles,
      );
    }
    throw const PolySampleUploadException(
      'SysEx content validation is not supported by the Disting NT SD-card '
      'protocol. File download returns whole files only, so WAV verification '
      'must use mounted SD-card access instead.',
    );
  }
}

class _UploadedHardwareFile {
  const _UploadedHardwareFile({required this.file, required this.byteLength});

  final PolySampleUploadFile file;
  final int byteLength;
}

class _TransferProgress {
  _TransferProgress({required this.totalBytes, required this.onProgress})
    : _stopwatch = Stopwatch()..start();

  int totalBytes;
  int completedBytes = 0;
  final PolySampleUploadProgress? onProgress;
  final Stopwatch _stopwatch;
  final AdaptiveTransferRateEstimator _etaEstimator =
      AdaptiveTransferRateEstimator();
  Duration _lastProgressEmit = Duration.zero;

  void emitCurrent({
    required String action,
    required String displayName,
    required int fileIndex,
    required int fileCount,
  }) {
    if (onProgress == null) return;
    final elapsed = _stopwatch.elapsed;
    _lastProgressEmit = elapsed;
    onProgress?.call(
      _message(
        action: action,
        displayName: displayName,
        fileIndex: fileIndex,
        fileCount: fileCount,
      ),
    );
  }

  void advance({
    required int bytes,
    required String action,
    required String displayName,
    required int fileIndex,
    required int fileCount,
  }) {
    completedBytes += bytes;
    final elapsed = _stopwatch.elapsed;
    _etaEstimator.record(
      completedBytes: completedBytes,
      elapsed: elapsed,
      segmentId: fileIndex,
    );
    final shouldEmit =
        onProgress != null &&
        (completedBytes >= totalBytes ||
            _lastProgressEmit == Duration.zero ||
            elapsed - _lastProgressEmit >= const Duration(seconds: 1));
    if (!shouldEmit) return;
    _lastProgressEmit = elapsed;
    onProgress?.call(
      _message(
        action: action,
        displayName: displayName,
        fileIndex: fileIndex,
        fileCount: fileCount,
      ),
    );
  }

  String _message({
    required String action,
    required String displayName,
    required int fileIndex,
    required int fileCount,
  }) =>
      '$action $fileIndex/$fileCount $displayName '
      '(${_formatBytes(completedBytes)} of ${_formatBytes(totalBytes)}, '
      '${_percent()}, ${_etaText()})';

  String _percent() {
    if (totalBytes <= 0) return '100%';
    final percent = (completedBytes / totalBytes * 100).clamp(0, 100);
    return '${percent.toStringAsFixed(percent < 10 ? 1 : 0)}%';
  }

  String _etaText() {
    final remainingBytes = totalBytes - completedBytes;
    if (remainingBytes <= 0) return 'finishing now';
    final remaining = _etaEstimator.estimate(remainingBytes: remainingBytes);
    if (remaining == null) return 'estimating time remaining';
    return 'about ${_formatDuration(remaining)} remaining';
  }
}

class AdaptiveTransferRateEstimator {
  AdaptiveTransferRateEstimator({
    this.minSampleDuration = const Duration(seconds: 2),
    this.minSampleBytes = 8 * 1024,
    this.maxSampleCount = 120,
    this.minSamplesForOutlierRejection = 5,
    this.outlierTolerance = 0.45,
    this.trimFraction = 0.15,
  }) : assert(minSampleBytes >= 0),
       assert(maxSampleCount > 0),
       assert(minSamplesForOutlierRejection > 0),
       assert(outlierTolerance >= 0),
       assert(trimFraction >= 0 && trimFraction < 0.5);

  final Duration minSampleDuration;
  final int minSampleBytes;
  final int maxSampleCount;
  final int minSamplesForOutlierRejection;
  final double outlierTolerance;
  final double trimFraction;

  int _lastSampleBytes = 0;
  Duration _lastSampleElapsed = Duration.zero;
  int? _lastSegmentId;
  double? _bytesPerMillisecond;
  int _sampleCount = 0;
  final List<_TransferRateSample> _samples = [];

  int get sampleCount => _sampleCount;

  void record({
    required int completedBytes,
    required Duration elapsed,
    int? segmentId,
  }) {
    if (segmentId != null &&
        _lastSegmentId != null &&
        segmentId != _lastSegmentId) {
      _lastSegmentId = segmentId;
      _lastSampleBytes = completedBytes;
      _lastSampleElapsed = elapsed;
      return;
    }
    _lastSegmentId ??= segmentId;

    final deltaBytes = completedBytes - _lastSampleBytes;
    final deltaElapsed = elapsed - _lastSampleElapsed;
    if (deltaBytes <= 0 || deltaElapsed.inMilliseconds <= 0) return;
    if (deltaElapsed < minSampleDuration) return;
    if (deltaBytes < minSampleBytes) return;

    _samples.add(
      _TransferRateSample(
        bytes: deltaBytes,
        milliseconds: deltaElapsed.inMilliseconds,
      ),
    );
    if (_samples.length > maxSampleCount) {
      _samples.removeAt(0);
    }
    _bytesPerMillisecond = _calculateLongRunRate();
    _sampleCount++;
    _lastSampleBytes = completedBytes;
    _lastSampleElapsed = elapsed;
  }

  Duration? estimate({required int remainingBytes}) {
    if (remainingBytes <= 0) return Duration.zero;
    final rate = _bytesPerMillisecond;
    if (rate == null || rate <= 0) return null;
    return Duration(milliseconds: (remainingBytes / rate).round());
  }

  double? _calculateLongRunRate() {
    if (_samples.isEmpty) return null;
    var usable = List<_TransferRateSample>.of(_samples);
    if (usable.length >= minSamplesForOutlierRejection) {
      usable = _withoutOutliers(usable);
    }
    if (usable.length >= 8 && trimFraction > 0) {
      usable.sort((a, b) => a.rate.compareTo(b.rate));
      final trimCount = (usable.length * trimFraction).floor();
      if (trimCount > 0 && trimCount * 2 < usable.length) {
        usable = usable.sublist(trimCount, usable.length - trimCount);
      }
    }
    return _weightedRate(usable);
  }

  List<_TransferRateSample> _withoutOutliers(
    List<_TransferRateSample> samples,
  ) {
    final rates = samples.map((sample) => sample.rate).toList()..sort();
    final median = _median(rates);
    final deviations = rates.map((rate) => (rate - median).abs()).toList()
      ..sort();
    final mad = _median(deviations);
    final tolerance = _maxDouble(median * outlierTolerance, mad * 3);
    final filtered = samples
        .where((sample) => (sample.rate - median).abs() <= tolerance)
        .toList();
    return filtered.isEmpty ? samples : filtered;
  }

  double _weightedRate(List<_TransferRateSample> samples) {
    var bytes = 0;
    var milliseconds = 0;
    for (final sample in samples) {
      bytes += sample.bytes;
      milliseconds += sample.milliseconds;
    }
    return bytes / milliseconds;
  }
}

class _TransferRateSample {
  const _TransferRateSample({required this.bytes, required this.milliseconds});

  final int bytes;
  final int milliseconds;

  double get rate => bytes / milliseconds;
}

double _median(List<double> sortedValues) {
  final length = sortedValues.length;
  if (length == 0) return 0;
  final middle = length ~/ 2;
  if (length.isOdd) return sortedValues[middle];
  return (sortedValues[middle - 1] + sortedValues[middle]) / 2;
}

double _maxDouble(double a, double b) {
  return a > b ? a : b;
}

class _HardwareVerificationResult {
  const _HardwareVerificationResult({
    required this.correctedFiles,
    required this.failedFiles,
  });

  final int correctedFiles;
  final int failedFiles;
}

class _HardwarePreflightResult {
  const _HardwarePreflightResult({required this.failedFiles});

  final int failedFiles;
}

Future<_HardwarePreflightResult> _preflightHardwareFiles(
  IDistingMidiManager manager,
  String hardwareFolder,
  List<_UploadedHardwareFile> files,
) async {
  final listing = await manager.requestDirectoryListing(hardwareFolder);
  if (listing == null) {
    return _HardwarePreflightResult(failedFiles: files.length);
  }

  final entriesByName = <String, DirectoryEntry>{};
  for (final entry in listing.entries) {
    if (!entry.isDirectory) {
      entriesByName[_entryName(entry)] = entry;
    }
  }

  var failedFiles = 0;
  for (final file in files) {
    final entry = entriesByName[p.posix.basename(file.file.targetPath)];
    if (entry == null || entry.size != file.byteLength) {
      failedFiles++;
    }
  }
  return _HardwarePreflightResult(failedFiles: failedFiles);
}

Future<_HardwareVerificationResult> _verifyHardwareFiles(
  IDistingMidiManager manager,
  List<_UploadedHardwareFile> files,
  _TransferProgress progress,
) async {
  if (files.isEmpty) {
    return const _HardwareVerificationResult(correctedFiles: 0, failedFiles: 0);
  }

  progress.onProgress?.call('Verifying uploaded sample names and sizes...');
  final hardwareFolder = p.posix.dirname(files.first.file.targetPath);
  final preflight = await _preflightHardwareFiles(
    manager,
    hardwareFolder,
    files,
  );
  return _HardwareVerificationResult(
    correctedFiles: 0,
    failedFiles: preflight.failedFiles,
  );
}

String _entryName(DirectoryEntry entry) =>
    entry.name.replaceAll(RegExp(r'/+$'), '');

Future<void> _uploadHardwareFile(
  IDistingMidiManager manager,
  String path,
  Uint8List bytes, {
  void Function(int byteCount)? onChunkTransferred,
}) async {
  if (bytes.isEmpty) {
    await _requireSuccess(
      manager.requestFileUploadChunk(path, Uint8List(0), 0, createAlways: true),
      'upload chunk at 0 for $path',
    );
    return;
  }

  for (var position = 0; position < bytes.length;) {
    final nextPosition = position + _sysExUploadChunkSize < bytes.length
        ? position + _sysExUploadChunkSize
        : bytes.length;
    final chunk = bytes.sublist(position, nextPosition);
    await _requireSuccess(
      manager.requestFileUploadChunk(
        path,
        chunk,
        position,
        createAlways: position == 0,
      ),
      'upload chunk at $position for $path',
    );
    onChunkTransferred?.call(chunk.length);
    position = nextPosition;
  }
}

Future<void> _ensureHardwareParent(
  IDistingMidiManager manager,
  String path,
) async {
  final parent = p.posix.dirname(path);
  if (parent == '.' || parent == '/' || parent.isEmpty) return;
  final segments = parent.split('/').where((segment) => segment.isNotEmpty);
  var current = '';
  for (final segment in segments) {
    current = current.isEmpty ? '/$segment' : p.posix.join(current, segment);
    if (_knownHardwareRoots.contains(current)) continue;
    final status = await manager.requestDirectoryCreate(current);
    if (status != null && status.success) continue;
    if (await _hardwareDirectoryExists(manager, current)) continue;
    throw PolySampleUploadException(
      'Hardware mkdir $current failed: ${status?.message ?? 'no response'}',
    );
  }
}

const _knownHardwareRoots = {'/samples', '/multisamples'};

Future<bool> _hardwareDirectoryExists(
  IDistingMidiManager manager,
  String path,
) async {
  final parent = p.posix.dirname(path);
  final name = p.posix.basename(path);
  final listing = await manager.requestDirectoryListing(parent);
  if (listing == null) return false;
  for (final entry in listing.entries) {
    if (!entry.isDirectory) continue;
    final entryName = entry.name.replaceAll(RegExp(r'/+$'), '');
    if (entryName == name) return true;
  }
  return false;
}

Future<void> _requireSuccess(
  Future<SdCardStatus?> future,
  String operation,
) async {
  final status = await future;
  if (status == null || !status.success) {
    throw PolySampleUploadException(
      'Hardware $operation failed: ${status?.message ?? 'no response'}',
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
}

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = duration.inMinutes;
  final remainingSeconds = seconds % 60;
  if (minutes < 60) return '${minutes}m ${remainingSeconds}s';
  final hours = duration.inHours;
  final remainingMinutes = minutes % 60;
  return '${hours}h ${remainingMinutes}m';
}

String _uniqueTempPath(String targetPath) {
  final directory = p.dirname(targetPath);
  final basename = p.basename(targetPath);
  for (var attempt = 0; attempt < 1000; attempt++) {
    final suffix = DateTime.now().microsecondsSinceEpoch + attempt;
    final candidate = p.join(directory, '.$basename.poly-upload-tmp-$suffix');
    if (!File(candidate).existsSync()) return candidate;
  }
  final fallback = DateTime.now().millisecondsSinceEpoch;
  return p.join(directory, '.$basename.poly-upload-tmp-$fallback');
}

Future<void> _copyFileWithProgress(
  File source,
  File target, {
  void Function(int byteCount)? onBytesCopied,
}) async {
  final sink = target.openWrite();
  var closed = false;
  try {
    await for (final chunk in source.openRead()) {
      sink.add(chunk);
      onBytesCopied?.call(chunk.length);
    }
    await sink.close();
    closed = true;
  } catch (_) {
    if (!closed) {
      await sink.close();
    }
    rethrow;
  }
}
