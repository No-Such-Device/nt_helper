import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/services/local_file_tools.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('local file tools', () {
    late Directory tempDir;
    late SettingsService settings;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nt_helper_tools_');
      await File('${tempDir.path}/notes.txt').writeAsString('hello modular\n');
      await Directory('${tempDir.path}/nested').create();
      await File(
        '${tempDir.path}/nested/patch.txt',
      ).writeAsString('clock cv\n');
      await File('${tempDir.path}/manual.pdf').writeAsString(_simplePdfText);
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('registers root-id tools', () {
      final entries = <ToolRegistryEntry>[];

      registerLocalFileTools(entries, actor: FileRootActor.chat);

      final names = entries.map((entry) => entry.name).toSet();
      expect(names, localFileToolNames);
      expect(names, isNot(contains('write_workspace_file')));
      expect(names, isNot(contains('list_uploaded_files')));
    });

    test('lists and reads files with chat read permission', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.read}),
      ]);
      final entries = _entriesFor(FileRootActor.chat);

      final listResult = await _call(entries, 'list_files', {'root_id': 'sd'});
      final readResult = await _call(entries, 'read_file', {
        'root_id': 'sd',
        'path': 'notes.txt',
      });

      expect(listResult['success'], isTrue);
      expect(
        (listResult['entries'] as List).map((entry) => entry['path']),
        contains('notes.txt'),
      );
      expect(readResult['success'], isTrue);
      expect(readResult['content'], 'hello modular\n');
    });

    test('reads text files larger than the old 200k ceiling', () async {
      final content = '${List.filled(25000, '0123456789').join()}\n';
      await File('${tempDir.path}/large.txt').writeAsString(content);
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.read}),
      ]);

      final readResult = await _call(
        _entriesFor(FileRootActor.chat),
        'read_file',
        {'root_id': 'sd', 'path': 'large.txt'},
      );

      expect(readResult['success'], isTrue);
      expect(readResult['encoding'], 'utf8');
      expect(readResult['content'], content);
    }, tags: ['regression']);

    test('extracts readable text from PDFs', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.read}),
      ]);

      final readResult = await _call(
        _entriesFor(FileRootActor.chat),
        'read_file',
        {'root_id': 'sd', 'path': 'manual.pdf'},
      );

      expect(readResult['success'], isTrue);
      expect(readResult['encoding'], 'pdf_text');
      expect(readResult['content'], contains('Disting NT manual'));
    });

    test(
      'reports truncated PDF text using original extracted length',
      () async {
        final longText = List.filled(120010, 'A').join();
        await File(
          '${tempDir.path}/large_manual.pdf',
        ).writeAsString(_pdfWithLiteralText(longText));
        await _setRoots(settings, [
          _root(path: tempDir.path, chat: {FileRootPermission.read}),
        ]);

        final readResult = await _call(
          _entriesFor(FileRootActor.chat),
          'read_file',
          {'root_id': 'sd', 'path': 'large_manual.pdf'},
        );

        expect(readResult['success'], isTrue);
        expect(readResult['content_chars'], longText.length);
        expect(readResult['truncated'], isTrue);
        expect(readResult['message'], contains('PDF text was truncated'));
        expect(readResult['content'], contains('[truncated:'));
      },
    );

    test('omits missing roots from listing but keeps stale-id error', () async {
      final missingPath = '${tempDir.path}/unmounted';
      await _setRoots(settings, [
        _root(
          id: 'mounted',
          label: 'Mounted',
          path: tempDir.path,
          chat: {FileRootPermission.read},
        ),
        _root(
          id: 'stale',
          label: 'Stale SD',
          path: missingPath,
          chat: {FileRootPermission.read},
        ),
      ]);
      final entries = _entriesFor(FileRootActor.chat);

      final rootsResult = await _call(entries, 'list_allowed_roots', {});
      final listResult = await _call(entries, 'list_files', {
        'root_id': 'stale',
      });

      expect(rootsResult['success'], isTrue);
      expect(
        (rootsResult['roots'] as List).map((entry) => entry['id']),
        contains('mounted'),
      );
      expect(
        (rootsResult['roots'] as List).map((entry) => entry['id']),
        isNot(contains('stale')),
      );
      expect(listResult['success'], isFalse);
      expect(listResult['error'], 'root_not_found_on_disk');
    }, tags: ['regression']);

    test('enforces search permission separately from read', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.read}),
      ]);

      final result = await _call(
        _entriesFor(FileRootActor.chat),
        'search_files',
        {'root_id': 'sd', 'query': 'clock'},
      );

      expect(result['success'], isFalse);
      expect(result['error'], 'permission_denied');
      expect(result['permission'], 'search');
    });

    test('searches text files with search permission', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.search}),
      ]);

      final result = await _call(
        _entriesFor(FileRootActor.chat),
        'search_files',
        {'root_id': 'sd', 'query': 'clock'},
      );

      expect(result['success'], isTrue);
      expect(result['matches'], hasLength(1));
      expect(result['matches'][0]['path'], 'nested/patch.txt');
    });

    test('enforces chat and MCP ACLs independently', () async {
      await _setRoots(settings, [
        _root(
          path: tempDir.path,
          chat: {FileRootPermission.read},
          mcp: {FileRootPermission.search},
        ),
      ]);

      final chatRead = await _call(
        _entriesFor(FileRootActor.chat),
        'read_file',
        {'root_id': 'sd', 'path': 'notes.txt'},
      );
      final mcpRead = await _call(_entriesFor(FileRootActor.mcp), 'read_file', {
        'root_id': 'sd',
        'path': 'notes.txt',
      });
      final mcpSearch = await _call(
        _entriesFor(FileRootActor.mcp),
        'search_files',
        {'root_id': 'sd', 'query': 'hello'},
      );

      expect(chatRead['success'], isTrue);
      expect(mcpRead['success'], isFalse);
      expect(mcpRead['error'], 'permission_denied');
      expect(mcpSearch['success'], isTrue);
    });

    test('writes UTF-8 text only with write permission', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.write}),
      ]);

      final writeResult =
          await _call(_entriesFor(FileRootActor.chat), 'write_file', {
            'root_id': 'sd',
            'path': 'generated/out.txt',
            'content': 'saved text\n',
            'create_parents': true,
          });

      expect(writeResult['success'], isTrue);
      expect(
        await File('${tempDir.path}/generated/out.txt').readAsString(),
        'saved text\n',
      );
    });

    test('requires explicit overwrite for existing files', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.write}),
      ]);
      final entries = _entriesFor(FileRootActor.chat);

      final withoutOverwrite = await _call(entries, 'write_file', {
        'root_id': 'sd',
        'path': 'notes.txt',
        'content': 'replace\n',
      });
      final withOverwrite = await _call(entries, 'write_file', {
        'root_id': 'sd',
        'path': 'notes.txt',
        'content': 'replace\n',
        'overwrite': true,
      });

      expect(withoutOverwrite['success'], isFalse);
      expect(withoutOverwrite['error'], 'file_exists');
      expect(withOverwrite['success'], isTrue);
      expect(
        await File('${tempDir.path}/notes.txt').readAsString(),
        'replace\n',
      );
    });

    test('rejects path escape and absolute paths', () async {
      await _setRoots(settings, [
        _root(path: tempDir.path, chat: {FileRootPermission.read}),
      ]);
      final entries = _entriesFor(FileRootActor.chat);

      final dotDot = await _call(entries, 'read_file', {
        'root_id': 'sd',
        'path': '../secret.txt',
      });
      final absolute = await _call(entries, 'read_file', {
        'root_id': 'sd',
        'path': '${tempDir.path}/notes.txt',
      });

      expect(dotDot['success'], isFalse);
      expect(dotDot['error'], 'path_outside_allowed_root');
      expect(absolute['success'], isFalse);
      expect(absolute['error'], 'absolute_path_not_allowed');
    });

    test('rejects symlink escapes', () async {
      final outside = await Directory.systemTemp.createTemp(
        'nt_helper_outside_',
      );
      try {
        await File('${outside.path}/secret.txt').writeAsString('secret');
        await Link('${tempDir.path}/escape').create(outside.path);
        await Link(
          '${tempDir.path}/secret-link.txt',
        ).create('${outside.path}/secret.txt');
        await _setRoots(settings, [
          _root(
            path: tempDir.path,
            chat: {
              FileRootPermission.read,
              FileRootPermission.write,
              FileRootPermission.search,
            },
          ),
        ]);

        final readResult = await _call(
          _entriesFor(FileRootActor.chat),
          'read_file',
          {'root_id': 'sd', 'path': 'escape/secret.txt'},
        );
        final symlinkFileRead = await _call(
          _entriesFor(FileRootActor.chat),
          'read_file',
          {'root_id': 'sd', 'path': 'secret-link.txt'},
        );
        final writeResult = await _call(
          _entriesFor(FileRootActor.chat),
          'write_file',
          {'root_id': 'sd', 'path': 'escape/new.txt', 'content': 'nope'},
        );
        final symlinkFileWrite = await _call(
          _entriesFor(FileRootActor.chat),
          'write_file',
          {'root_id': 'sd', 'path': 'secret-link.txt', 'content': 'nope'},
        );
        final searchResult = await _call(
          _entriesFor(FileRootActor.chat),
          'search_files',
          {'root_id': 'sd', 'query': 'secret'},
        );
        final listResult = await _call(
          _entriesFor(FileRootActor.chat),
          'list_files',
          {'root_id': 'sd', 'recursive': true},
        );

        expect(readResult['success'], isFalse);
        expect(readResult['error'], 'path_outside_allowed_root');
        expect(symlinkFileRead['success'], isFalse);
        expect(symlinkFileRead['error'], 'path_outside_allowed_root');
        expect(writeResult['success'], isFalse);
        expect(writeResult['error'], 'path_outside_allowed_root');
        expect(symlinkFileWrite['success'], isFalse);
        expect(symlinkFileWrite['error'], 'path_outside_allowed_root');
        expect(searchResult['success'], isTrue);
        expect(searchResult['matches'], isEmpty);
        expect(listResult['success'], isTrue);
        expect(
          (listResult['entries'] as List).map((entry) => entry['path']),
          isNot(contains('secret-link.txt')),
        );
      } finally {
        if (await outside.exists()) {
          await outside.delete(recursive: true);
        }
      }
    }, tags: ['regression']);
  });
}

const _simplePdfText = '''
%PDF-1.4
1 0 obj
<< /Type /Page /Contents 2 0 R >>
endobj
2 0 obj
<< /Length 44 >>
stream
BT
/F1 12 Tf
72 720 Td
(Disting NT manual) Tj
ET
endstream
endobj
trailer
<< /Root 1 0 R >>
%%EOF
''';

String _pdfWithLiteralText(String text) =>
    '''
%PDF-1.4
1 0 obj
<< /Type /Page /Contents 2 0 R >>
endobj
2 0 obj
<< /Length ${text.length + 32} >>
stream
BT
/F1 12 Tf
72 720 Td
($text) Tj
ET
endstream
endobj
trailer
<< /Root 1 0 R >>
%%EOF
''';

List<ToolRegistryEntry> _entriesFor(FileRootActor actor) {
  final entries = <ToolRegistryEntry>[];
  registerLocalFileTools(entries, actor: actor);
  return entries;
}

Future<Map<String, dynamic>> _call(
  List<ToolRegistryEntry> entries,
  String name,
  Map<String, dynamic> args,
) async {
  final entry = entries.singleWhere((entry) => entry.name == name);
  return jsonDecode(await entry.handler(args)) as Map<String, dynamic>;
}

Future<void> _setRoots(
  SettingsService settings,
  List<AllowedFileRoot> roots,
) async {
  final saved = await settings.setAllowedFileRoots(roots);
  expect(saved, isTrue);
}

AllowedFileRoot _root({
  String id = 'sd',
  String label = 'SD Card',
  required String path,
  Set<FileRootPermission> chat = const {},
  Set<FileRootPermission> mcp = const {},
}) {
  return AllowedFileRoot(
    id: id,
    label: label,
    path: path,
    acl: {FileRootActor.chat: chat, FileRootActor.mcp: mcp},
  );
}
