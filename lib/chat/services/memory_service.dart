import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:path_provider/path_provider.dart';

/// File I/O service for persistent chat memory.
///
/// Manages three storage components:
/// - `memory.md`: Semantic memory (200-line cap)
/// - `daily/YYYY-MM-DD.md`: Daily logs (append-only)
/// - `sessions/YYYY-MM-DDTHH-mm-ss.md`: Session snapshots
///
/// All public methods fail silently if the storage directory cannot be
/// resolved, logging errors to the debug console.
class MemoryService {
  static const _maxMemoryLines = 200;

  String? _basePath;
  bool _unavailable = false;

  Future<String?> _getBasePath() async {
    if (_basePath != null) return _basePath;
    if (_unavailable) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      _basePath = '${dir.path}/chat_memory';
      return _basePath;
    } catch (e) {
      debugPrint('MemoryService: unable to resolve storage directory: $e');
      _unavailable = true;
      return null;
    }
  }

  /// Read semantic memory. Returns empty string if file doesn't exist or
  /// storage is unavailable.
  Future<String> readMemory() async {
    final base = await _getBasePath();
    if (base == null) return '';
    try {
      final file = File('$base/memory.md');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (e) {
      debugPrint('MemoryService: failed to read memory: $e');
      return '';
    }
  }

  /// Write semantic memory, enforcing a 200-line cap (keeps last 200 lines).
  Future<void> writeMemory(String content) async {
    final base = await _getBasePath();
    if (base == null) return;
    try {
      final dir = Directory(base);
      if (!await dir.exists()) await dir.create(recursive: true);

      var lines = content.split('\n');
      // A trailing newline produces an empty string at the end of the list;
      // strip it so it doesn't count toward the 200-line cap.
      final hasTrailingNewline =
          lines.isNotEmpty && lines.last.isEmpty && content.endsWith('\n');
      if (hasTrailingNewline) lines = lines.sublist(0, lines.length - 1);

      final capped = lines.length > _maxMemoryLines
          ? lines.sublist(lines.length - _maxMemoryLines).join('\n')
          : lines.join('\n');

      await File('$base/memory.md').writeAsString(capped);
    } catch (e) {
      debugPrint('MemoryService: failed to write memory: $e');
    }
  }

  /// Append a timestamped entry to today's daily log.
  Future<void> appendDailyLog(String entry) async {
    final base = await _getBasePath();
    if (base == null) return;
    try {
      final dailyDir = Directory('$base/daily');
      if (!await dailyDir.exists()) await dailyDir.create(recursive: true);

      final now = DateTime.now();
      final filename = _dateString(now);
      final file = File('$base/daily/$filename.md');

      final timestamp =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final line = '- [$timestamp] $entry\n';

      await file.writeAsString(line, mode: FileMode.append);
    } catch (e) {
      debugPrint('MemoryService: failed to append daily log: $e');
    }
  }

  /// Read today's and yesterday's daily logs with date headers.
  /// Returns empty string for missing files or if storage is unavailable.
  Future<String> readDailyLogs() async {
    final base = await _getBasePath();
    if (base == null) return '';
    try {
      final now = DateTime.now();
      final today = _dateString(now);
      final yesterday = _dateString(now.subtract(const Duration(days: 1)));

      final buffer = StringBuffer();

      final yesterdayFile = File('$base/daily/$yesterday.md');
      if (await yesterdayFile.exists()) {
        buffer.writeln('### $yesterday');
        buffer.writeln(await yesterdayFile.readAsString());
      }

      final todayFile = File('$base/daily/$today.md');
      if (await todayFile.exists()) {
        buffer.writeln('### $today');
        buffer.writeln(await todayFile.readAsString());
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('MemoryService: failed to read daily logs: $e');
      return '';
    }
  }

  /// Save a session snapshot with the last 15 user/assistant messages.
  Future<void> saveSessionSnapshot(List<LlmMessage> messages) async {
    final filtered = messages
        .where((m) => m.role == LlmRole.user || m.role == LlmRole.assistant)
        .toList();
    if (filtered.isEmpty) return;

    final base = await _getBasePath();
    if (base == null) return;
    try {
      final last15 = filtered.length > 15
          ? filtered.sublist(filtered.length - 15)
          : filtered;

      final sessionsDir = Directory('$base/sessions');
      if (!await sessionsDir.exists()) {
        await sessionsDir.create(recursive: true);
      }

      final now = DateTime.now();
      final filename =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          'T${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';

      final buffer = StringBuffer();
      for (final msg in last15) {
        final prefix = msg.role == LlmRole.user ? 'User' : 'Assistant';
        buffer.writeln('$prefix: ${msg.content ?? '(empty)'}');
        buffer.writeln();
      }

      await File(
        '$base/sessions/$filename.md',
      ).writeAsString(buffer.toString());
    } catch (e) {
      debugPrint('MemoryService: failed to save session snapshot: $e');
    }
  }

  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
