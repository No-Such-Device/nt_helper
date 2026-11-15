import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class ConversationStore {
  Future<StoredConversation?> loadActive();
  Future<StoredConversation> load(String id);
  Future<List<ConversationSummary>> list();
  Future<void> save(StoredConversation conversation);
  Future<void> activate(String id);
  Future<void> delete(String id);
}

/// Passive local checkpoints only. This store has no model/tool dependencies and
/// never resumes a task. Small sidecars let the picker list chats without loading
/// every screenshot/attachment. Writes are serialized and replace via rename.
class FileConversationStore implements ConversationStore {
  FileConversationStore({this._directory});
  Directory? _directory;
  Future<void> _tail = Future.value();
  Future<Directory>? _rootDirectory;
  // Screen disposal is asynchronous: a replacement Cubit/store can be opened
  // before the previous one finishes its final save. Share disk serialization.
  static final _diskTails = <String, Future<void>>{};

  Future<Directory> _root() => _rootDirectory ??= _createRoot();

  Future<Directory> _createRoot() async {
    final root = _directory ??= Directory(
      '${(await getApplicationSupportDirectory()).path}/chat_conversations',
    );
    try {
      await root.create(recursive: true);
      return root;
    } catch (_) {
      _rootDirectory = null;
      rethrow;
    }
  }

  String _safeId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException('Invalid conversation ID');
    }
    return id;
  }

  Future<T> _serialized<T>(Future<T> Function() work) {
    final next = _tail.then((_) async {
      final key = (await _root()).absolute.path;
      final previous = _diskTails[key] ?? Future<void>.value();
      final operation = previous.then((_) => work());
      final settled = operation.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      _diskTails[key] = settled;
      unawaited(
        settled.then((_) {
          if (identical(_diskTails[key], settled)) _diskTails.remove(key);
        }),
      );
      return operation;
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _write(File file, Object value) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }

  Future<StoredConversation> _load(Directory root, String id) async {
    final json = jsonDecode(
      await File('${root.path}/${_safeId(id)}.json').readAsString(),
    );
    final conversation = StoredConversation.fromJson(
      Map<String, dynamic>.from(json as Map),
    );
    if (conversation.summary.id != id) {
      throw const FormatException('Conversation identity mismatch');
    }
    return conversation;
  }

  @override
  Future<StoredConversation?> loadActive() => _serialized(() async {
    final root = await _root();
    final pointer = File('${root.path}/active.json');
    if (!await pointer.exists()) return null;
    final json = jsonDecode(await pointer.readAsString()) as Map;
    return _load(root, json['id'] as String);
  });
  @override
  Future<StoredConversation> load(String id) =>
      _serialized(() async => _load(await _root(), id));
  @override
  Future<List<ConversationSummary>> list() => _serialized(() async {
    final root = await _root();
    final result = <ConversationSummary>[];
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.summary.json')) continue;
      final json = jsonDecode(await entity.readAsString()) as Map;
      final summary = ConversationSummary.fromJson(
        Map<String, dynamic>.from(json),
      );
      _safeId(summary.id);
      // Keep the active empty draft restorable, but do not clutter history
      // with chats that have never been used. Legacy counts may be unknown.
      if (summary.messageCount != 0) result.add(summary);
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  });
  @override
  Future<void> save(StoredConversation conversation) => _serialized(() async {
    final root = await _root();
    final id = _safeId(conversation.summary.id);
    await _write(File('${root.path}/$id.json'), conversation.toJson());
    await _write(
      File('${root.path}/$id.summary.json'),
      conversation.summary.toJson(),
    );
  });
  @override
  Future<void> activate(String id) => _serialized(() async {
    final root = await _root();
    final safeId = _safeId(id);
    if (!await File('${root.path}/$safeId.json').exists()) {
      throw const FormatException('Conversation is not saved');
    }
    await _write(File('${root.path}/active.json'), {'id': safeId});
  });
  @override
  Future<void> delete(String id) => _serialized(() async {
    final root = await _root();
    final safeId = _safeId(id);
    // Callers activate the replacement first when deleting the current chat.
    for (final suffix in [
      '.json',
      '.summary.json',
      '.json.tmp',
      '.summary.json.tmp',
    ]) {
      final file = File('${root.path}/$safeId$suffix');
      if (await file.exists()) await file.delete();
    }
  });
}
