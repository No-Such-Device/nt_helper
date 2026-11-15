import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/utils/temp_directory_utils.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/utils/sandbox_utils.dart';

/// Bridge to spawn and communicate with the nt-flash tool
class FlashToolBridge {
  final FlashToolManager _toolManager;
  Process? _process;
  IOSink? _logSink;
  File? _currentLogFile;

  FlashToolBridge({required this._toolManager});

  /// Flash firmware to the device
  /// Returns a stream of progress updates
  Stream<FlashProgress> flash(String firmwarePath) async* {
    final toolPath = await _toolManager.getToolPath();
    final logFile = await _createLogFile();
    _currentLogFile = logFile;
    _logSink = logFile.openWrite();

    final controller = StreamController<FlashProgress>();

    // On Linux, use pkexec to run with elevated privileges
    final String executable;
    final List<String> args;
    if (Platform.isLinux) {
      executable = 'pkexec';
      args = [toolPath, '--machine', firmwarePath];
    } else {
      executable = toolPath;
      args = ['--machine', firmwarePath];
    }

    // Set TMPDIR to sandbox-accessible temp directory on macOS
    Map<String, String>? environment;
    if (Platform.isMacOS && SandboxUtils.isSandboxed) {
      final tempDir = await TempDirectoryUtils.getWritableTempDirectory();
      environment = {...Platform.environment, 'TMPDIR': tempDir.path};
    }

    try {
      _process = await Process.start(
        executable,
        args,
        environment: environment,
      );
    } on ProcessException catch (e) {
      // Handle sandbox restrictions - "Operation not permitted" on macOS
      if (Platform.isMacOS &&
          (e.message.contains('Operation not permitted') || e.errorCode == 1)) {
        final isSandboxed = SandboxUtils.isSandboxed;
        final message = isSandboxed
            ? 'Unable to execute flash tool in sandboxed environment. '
                  'The bundled nt-flash binary may be missing or improperly signed.'
            : 'Unable to execute flash tool. Permission denied.';
        controller.add(
          FlashProgress(
            stage: FlashStage.complete,
            percent: 0,
            message: message,
            isError: true,
            isSandboxError: isSandboxed,
          ),
        );
        controller.close();
        return;
      }
      rethrow;
    }

    // Handle stdout
    _process!.stdout
        .transform(const SystemEncoding().decoder)
        .listen(
          (data) {
            _logSink?.writeln(data);
            for (final line in data.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final progress = _parseMachineOutput(trimmed);
              if (progress != null) {
                controller.add(progress);
              }
            }
          },
          onError: (error) {
            _logSink?.writeln('STDOUT ERROR: $error');
          },
        );

    // Handle stderr
    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      _logSink?.writeln('STDERR: $data');
    });

    // Handle process exit
    _process!.exitCode.then((exitCode) {
      _logSink?.writeln('EXIT CODE: $exitCode');
      _logSink?.close();
      _logSink = null;

      if (exitCode != 0 && !controller.isClosed) {
        String message = 'Flash failed with exit code $exitCode';
        if (exitCode == 6 && Platform.isMacOS) {
          message +=
              '. This may indicate the nt-flash binary is incompatible '
              'with your macOS version.';
        }
        controller.add(
          FlashProgress(
            stage: FlashStage.complete,
            percent: 0,
            message: message,
            isError: true,
          ),
        );
      }
      controller.close();
      _process = null;
    });

    yield* controller.stream;
  }

  /// Cancel the current flash operation
  Future<void> cancel() async {
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    if (_logSink != null) {
      await _logSink!.close();
      _logSink = null;
    }
  }

  /// Create a timestamped log file
  Future<File> _createLogFile() async {
    final appSupport = await getApplicationSupportDirectory();
    final logsDir = Directory(path.join(appSupport.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }

    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final logPath = path.join(logsDir.path, 'firmware_$timestamp.log');
    return File(logPath);
  }

  /// Parse machine-readable output from nt-flash
  FlashProgress? _parseMachineOutput(String line) =>
      _parseMachineOutputStatic(line);

  /// Get the most recent log lines from the current or last flash session
  Future<List<String>> getRecentLogLines(int count) async {
    if (_currentLogFile == null) {
      return ['(No flash log available - error occurred before flash started)'];
    }

    // Flush the log sink if still open
    await _logSink?.flush();

    try {
      if (!await _currentLogFile!.exists()) {
        return ['(Log file not found)'];
      }

      final lines = await _currentLogFile!.readAsLines();
      if (lines.isEmpty) {
        return ['(Log file is empty)'];
      }
      if (lines.length <= count) return lines;
      return lines.sublist(lines.length - count);
    } catch (e) {
      return ['Error reading log: $e'];
    }
  }

  /// Visible for testing
  static FlashProgress? parseMachineOutputForTesting(String line) {
    return _parseMachineOutputStatic(line);
  }

  /// Static parsing implementation for both instance and test use
  static FlashProgress? _parseMachineOutputStatic(String line) {
    final parts = line.split(':');
    if (parts.isEmpty) return null;

    final type = parts[0];

    switch (type) {
      case 'STATUS':
        if (parts.length >= 4) {
          final stage = FlashStage.fromMachineValue(parts[1]);
          final percent = int.tryParse(parts[2]) ?? 0;
          final message = parts.sublist(3).join(':');
          if (stage != null) {
            return FlashProgress(
              stage: stage,
              percent: percent,
              message: message,
            );
          }
        }
        break;

      case 'PROGRESS':
        if (parts.length >= 3) {
          final stage = FlashStage.fromMachineValue(parts[1]);
          final percent = int.tryParse(parts[2]) ?? 0;
          if (stage != null) {
            return FlashProgress(stage: stage, percent: percent, message: '');
          }
        }
        break;

      case 'ERROR':
        final message = parts.length > 1
            ? parts.sublist(1).join(':')
            : 'Unknown error';
        return FlashProgress(
          stage: FlashStage.complete,
          percent: 0,
          message: message,
          isError: true,
        );
    }

    return null;
  }
}
