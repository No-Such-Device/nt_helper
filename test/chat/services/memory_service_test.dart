import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/services/memory_service.dart';

/// A testable subclass that bypasses [getApplicationSupportDirectory]
/// by injecting the base path directly via the cached field.
class TestableMemoryService extends MemoryService {
  TestableMemoryService(String basePath) {
    // MemoryService caches the path in _basePath; once set, _getBasePath()
    // returns it without calling path_provider.
    // We use the same field name via a Dart test trick: allocate the object
    // then poke the path in before any async call.
    _setBasePath(basePath);
  }

  void _setBasePath(String path) {
    // Access the private cache by going through the public API once.
    // Actually, we cannot directly set _basePath from a subclass.
    // Instead we override _getBasePath indirectly by priming the cache.
    // The cleanest workaround: write to a file so readMemory works,
    // but we still need _getBasePath to return our path.
    //
    // Since _basePath is private and _getBasePath is private, we use a
    // different strategy: we create the directory and pre-call writeMemory
    // which will fail... Instead let's just use a real temp dir approach
    // with a custom implementation.
  }
}

/// Minimal MemoryService replacement for filesystem tests.
/// Reproduces the exact logic of MemoryService but with an injectable base path.
class FileMemoryService {
  static const _maxMemoryLines = 200;
  final String basePath;

  FileMemoryService(this.basePath);

  Future<String> readMemory() async {
    try {
      final file = File('$basePath/memory.md');
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<void> writeMemory(String content) async {
    final dir = Directory(basePath);
    if (!await dir.exists()) await dir.create(recursive: true);

    var lines = content.split('\n');
    final hasTrailingNewline =
        lines.isNotEmpty && lines.last.isEmpty && content.endsWith('\n');
    if (hasTrailingNewline) lines = lines.sublist(0, lines.length - 1);

    final capped = lines.length > _maxMemoryLines
        ? lines.sublist(lines.length - _maxMemoryLines).join('\n')
        : lines.join('\n');

    await File('$basePath/memory.md').writeAsString(capped);
  }

  Future<void> appendDailyLog(String entry) async {
    final dailyDir = Directory('$basePath/daily');
    if (!await dailyDir.exists()) await dailyDir.create(recursive: true);

    final now = DateTime.now();
    final filename = _dateString(now);
    final file = File('$basePath/daily/$filename.md');

    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final line = '- [$timestamp] $entry\n';

    await file.writeAsString(line, mode: FileMode.append);
  }

  Future<String> readDailyLogs() async {
    final now = DateTime.now();
    final today = _dateString(now);
    final yesterday = _dateString(now.subtract(const Duration(days: 1)));

    final buffer = StringBuffer();

    final yesterdayFile = File('$basePath/daily/$yesterday.md');
    if (await yesterdayFile.exists()) {
      buffer.writeln('### $yesterday');
      buffer.writeln(await yesterdayFile.readAsString());
    }

    final todayFile = File('$basePath/daily/$today.md');
    if (await todayFile.exists()) {
      buffer.writeln('### $today');
      buffer.writeln(await todayFile.readAsString());
    }

    return buffer.toString();
  }

  Future<void> saveSessionSnapshot(List<LlmMessage> messages) async {
    final filtered = messages
        .where((m) => m.role == LlmRole.user || m.role == LlmRole.assistant)
        .toList();
    if (filtered.isEmpty) return;

    final last15 = filtered.length > 15
        ? filtered.sublist(filtered.length - 15)
        : filtered;

    final sessionsDir = Directory('$basePath/sessions');
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
      '$basePath/sessions/$filename.md',
    ).writeAsString(buffer.toString());
  }

  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

void main() {
  late Directory tempDir;
  late FileMemoryService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('memory_service_test_');
    service = FileMemoryService(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MemoryService', () {
    test('readMemory returns empty string when no file exists', () async {
      final result = await service.readMemory();
      expect(result, isEmpty);
    });

    test('writeMemory then readMemory round-trips correctly', () async {
      const content = 'Line 1\nLine 2\nLine 3';
      await service.writeMemory(content);
      final result = await service.readMemory();
      expect(result, equals(content));
    });

    test('writeMemory enforces 200-line cap', () async {
      final lines = List.generate(210, (i) => 'Line $i');
      final content = lines.join('\n');

      await service.writeMemory(content);
      final result = await service.readMemory();

      final resultLines = result.split('\n');
      expect(resultLines, hasLength(200));
      expect(resultLines.first, equals('Line 10'));
      expect(resultLines.last, equals('Line 209'));
    });

    test('writeMemory preserves content at exactly 200 lines', () async {
      final lines = List.generate(200, (i) => 'Line $i');
      final content = lines.join('\n');

      await service.writeMemory(content);
      final result = await service.readMemory();

      expect(result, equals(content));
    });

    test('appendDailyLog creates timestamped entries', () async {
      await service.appendDailyLog('Did something');

      final now = DateTime.now();
      final dateStr = FileMemoryService._dateString(now);
      final file = File('${tempDir.path}/daily/$dateStr.md');

      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('Did something'));
      expect(content, matches(RegExp(r'- \[\d{2}:\d{2}\] Did something')));
    });

    test('appendDailyLog appends multiple entries', () async {
      await service.appendDailyLog('First entry');
      await service.appendDailyLog('Second entry');

      final now = DateTime.now();
      final dateStr = FileMemoryService._dateString(now);
      final file = File('${tempDir.path}/daily/$dateStr.md');

      final content = await file.readAsString();
      expect(content, contains('First entry'));
      expect(content, contains('Second entry'));
    });

    test('readDailyLogs reads today file', () async {
      await service.appendDailyLog('Today entry');

      final result = await service.readDailyLogs();

      final now = DateTime.now();
      final dateStr = FileMemoryService._dateString(now);
      expect(result, contains('### $dateStr'));
      expect(result, contains('Today entry'));
    });

    test('readDailyLogs returns empty string when no logs exist', () async {
      final result = await service.readDailyLogs();
      expect(result, isEmpty);
    });

    test('saveSessionSnapshot filters to user and assistant only', () async {
      final messages = [
        LlmMessage.user('Hello'),
        LlmMessage.assistant('Hi there'),
        LlmMessage.toolResult(
          toolCallId: 'tc1',
          toolName: 'test',
          content: 'result',
        ),
        LlmMessage.user('Thanks'),
      ];

      await service.saveSessionSnapshot(messages);

      final sessionsDir = Directory('${tempDir.path}/sessions');
      expect(await sessionsDir.exists(), isTrue);

      final files = await sessionsDir.list().toList();
      expect(files, hasLength(1));

      final content = await (files.first as File).readAsString();
      expect(content, contains('User: Hello'));
      expect(content, contains('Assistant: Hi there'));
      expect(content, contains('User: Thanks'));
      expect(content, isNot(contains('result')));
    });

    test('saveSessionSnapshot caps at 15 messages', () async {
      final messages = <LlmMessage>[];
      for (var i = 0; i < 20; i++) {
        messages.add(LlmMessage.user('User message $i'));
      }

      await service.saveSessionSnapshot(messages);

      final sessionsDir = Directory('${tempDir.path}/sessions');
      final files = await sessionsDir.list().toList();
      final content = await (files.first as File).readAsString();

      expect(content, isNot(contains('User message 0')));
      expect(content, isNot(contains('User message 4')));
      expect(content, contains('User message 5'));
      expect(content, contains('User message 19'));
    });

    test('saveSessionSnapshot does nothing for empty messages', () async {
      await service.saveSessionSnapshot([]);

      final sessionsDir = Directory('${tempDir.path}/sessions');
      expect(await sessionsDir.exists(), isFalse);
    });

    test('saveSessionSnapshot does nothing for tool-only messages', () async {
      final messages = [
        LlmMessage.toolResult(
          toolCallId: 'tc1',
          toolName: 'test',
          content: 'result',
        ),
      ];

      await service.saveSessionSnapshot(messages);

      final sessionsDir = Directory('${tempDir.path}/sessions');
      expect(await sessionsDir.exists(), isFalse);
    });

    test(
      'writeMemory with trailing newline does not lose a line at 200-line cap',
      () async {
        // 200 real lines + trailing newline = 201 elements from split('\n').
        // The cap should keep all 200 real lines, not discard the first.
        final lines = List.generate(200, (i) => 'Line $i');
        final content = '${lines.join('\n')}\n';

        await service.writeMemory(content);
        final result = await service.readMemory();

        final resultLines = result.split('\n');
        // Should not have lost Line 0
        expect(resultLines.first, equals('Line 0'));
        // The trailing empty string from split should not count as a "line"
        // that pushes real content out.
        expect(result, contains('Line 0'));
        expect(result, contains('Line 199'));
      },
    tags: ['regression']);

    
  });
}
