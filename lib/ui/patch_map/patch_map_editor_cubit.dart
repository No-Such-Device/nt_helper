import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';
import 'package:nt_helper/algorithm_controller/sd_card_companion.dart';
import 'package:nt_helper/algorithm_controller/companion_table.dart';

class PatchMapEditorState {
  const PatchMapEditorState({
    this.map,
    this.document,
    this.busy = false,
    this.error,
    this.applied = false,
  });
  final PatchMap? map;
  final CompanionTable? document;
  final bool busy;
  final String? error;
  final bool applied;
  bool get editable =>
      map != null && document != null && !busy && error == null;
}

class PatchMapEditorCubit extends Cubit<PatchMapEditorState> {
  PatchMapEditorCubit(this.client, this.download)
    : super(const PatchMapEditorState());
  final PatchMapClient client;
  final Future<Uint8List?> Function(String) download;
  SdCardCompanion? _companion;

  Future<void> load() => _run(() async {
    _companion = null;
    final source = await SdCardCompanion.load(download, guid: 'ThPh');
    if (isClosed) throw StateError('Editor closed');
    final map = await client.load();
    _companion = source;
    return map;
  }, applied: false);
  Future<void> setConnection(PatchConnection row) =>
      _action({'type': 'set_connection', 'connection': row.toJson()});
  Future<void> setTitle(String title) =>
      _action({'type': 'set_title', 'title': title});
  Future<void> addExpander(int type) =>
      _action({'type': 'add_expander', 'model': type});
  Future<void> renameExpander(int index, String name) =>
      _action({'type': 'rename_expander', 'index': index, 'name': name});
  Future<void> moveExpander(int from, int to) =>
      _action({'type': 'move_expander', 'from': from, 'to': to});

  Map<String, Object?> _snapshot(PatchMap map) => {
    ...map.toJson(),
    'expanders': [for (final e in map.expanders) e.toJson()],
  };

  Future<void> _action(Map<String, Object?> event) {
    if (!state.editable) return Future.value();
    return _run(() async {
      if (_companion == null || !client.ready || state.map == null) {
        throw const PatchMapSyncException(
          'Reload the companion and map before editing.',
        );
      }
      final action = await _companion!.evaluate(
        _snapshot(state.map!),
        event: event,
      );
      if (isClosed) throw StateError('Editor closed');
      // Each user gesture grants only its own action kind. The companion receives
      // no transport object, file API, or unrestricted parameter-writing function.
      if (action['type'] != event['type']) {
        throw const FormatException('Companion changed the action kind');
      }
      return switch (action['type']) {
        'set_connection' => client.setConnection(
          PatchConnection.fromJson(_object(action['connection'])),
        ),
        'set_title' => client.setTitle(_string(action['title'])),
        'add_expander' => client.addExpander(_integer(action['model'])),
        'rename_expander' => client.renameExpander(
          _integer(action['index']),
          _string(action['name']),
        ),
        'move_expander' => client.moveExpander(
          _integer(action['from']),
          _integer(action['to']),
        ),
        _ => throw const FormatException('Unsupported companion action'),
      };
    });
  }

  Future<void> _run(
    Future<PatchMap> Function() action, {
    bool applied = true,
  }) async {
    if (isClosed || state.busy) return;
    final previous = state;
    emit(
      PatchMapEditorState(
        map: previous.map,
        document: previous.document,
        busy: true,
        applied: previous.applied,
      ),
    );
    try {
      final map = await action();
      final document = CompanionTable.parse(
        await _companion!.evaluate(_snapshot(map)),
        map,
      );
      if (!isClosed) {
        emit(
          PatchMapEditorState(map: map, document: document, applied: applied),
        );
      }
    } catch (error) {
      if (!isClosed) {
        emit(
          PatchMapEditorState(
            map: previous.map,
            document: previous.document,
            error: error.toString(),
            applied: previous.applied,
          ),
        );
      }
    }
  }

  static int _integer(Object? value) {
    if (value is! int) {
      throw const FormatException('Expected integer action value');
    }
    return value;
  }

  static String _string(Object? value) {
    if (value is! String) {
      throw const FormatException('Expected text action value');
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected connection action');
    }
    return value;
  }
}
