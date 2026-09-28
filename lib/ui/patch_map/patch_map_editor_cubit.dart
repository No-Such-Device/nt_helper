import 'dart:typed_data';
import 'dart:async';
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
    this.fromDevice = false,
  });
  final PatchMap? map;
  final CompanionTable? document;
  final bool busy;
  final String? error;
  final bool applied;
  final bool fromDevice;
  bool get editable =>
      map != null && document != null && !busy && error == null;
}

class PatchMapEditorCubit extends Cubit<PatchMapEditorState> {
  PatchMapEditorCubit(
    this.client,
    this.download, {
    this.watchInterval,
    this.hasUnsentEdits,
  }) : super(const PatchMapEditorState());
  final Duration? watchInterval;
  final bool Function()? hasUnsentEdits;
  Timer? _watch;
  Future<void>? _refreshing;
  Map<String, int> _observedProperties = const {};

  @override
  Future<void> close() {
    _watch?.cancel();
    return super.close();
  }

  void setWatching(bool active) {
    _watch?.cancel();
    _watch = null;
    if (active && !isClosed && watchInterval != null) {
      _watch = Timer.periodic(watchInterval!, (_) => refresh());
    }
  }

  Future<void> refresh() {
    if (isClosed || !state.editable || _refreshing != null) {
      return Future.value();
    }
    final work = _refresh();
    _refreshing = work;
    return work.whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final previous = state;
    try {
      final map = await client.refresh();
      if (isClosed) return;
      final mapChanged = !identical(previous.map, map);
      final changes = <String, Object?>{
        for (final entry in client.properties.entries)
          if (_observedProperties[entry.key] != entry.value)
            entry.key: {
              'previous': _observedProperties[entry.key],
              'value': entry.value,
            },
      };
      if (!mapChanged && changes.isEmpty) return;
      if (mapChanged && (hasUnsentEdits?.call() ?? false)) {
        throw const PatchMapSyncException(
          'The map changed on the NT. Your unsent edits are retained. Reload to use the NT version.',
        );
      }
      final document = CompanionTable.parse(
        await _companion!.evaluate(
          _snapshot(map),
          change: {
            'type': 'nt_changed',
            'properties': changes,
            'map_changed': mapChanged,
          },
        ),
        map,
      );
      if (isClosed) return;
      if (mapChanged && (hasUnsentEdits?.call() ?? false)) {
        throw const PatchMapSyncException(
          'The map changed on the NT. Your unsent edits are retained. Reload to use the NT version.',
        );
      }
      _observedProperties = client.properties;
      emit(
        PatchMapEditorState(
          map: map,
          document: document,
          applied: previous.applied,
          fromDevice: true,
        ),
      );
    } catch (error) {
      if (!isClosed) {
        emit(
          PatchMapEditorState(
            map: previous.map,
            document: previous.document,
            applied: previous.applied,
            error: error.toString(),
            fromDevice: true,
          ),
        );
      }
    }
  }

  final PatchMapClient client;
  final Future<Uint8List?> Function(String) download;
  SdCardCompanion? _companion;

  Future<void> load() => _run(() async {
    _companion = null;
    final source = await SdCardCompanion.load(download, guid: 'ThPh');
    if (isClosed) throw StateError('Editor closed');
    final map = await client.load();
    _companion = source;
    _observedProperties = const {};
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
    'properties': client.properties,
    'revision': client.revision,
    'expanders': [for (final e in map.expanders) e.toJson()],
  };

  Future<void> _action(Map<String, Object?> event) async {
    await _refreshing;
    if (isClosed || !state.editable) return Future.value();
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
    await _refreshing;
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
