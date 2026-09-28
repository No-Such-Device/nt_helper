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
    this.pending = false,
  });
  final PatchMap? map;
  final CompanionTable? document;
  final bool busy;
  final String? error;
  final bool applied;
  final bool fromDevice;
  final bool pending;
  bool get editable =>
      map != null && document != null && !busy && error == null;
}

class PatchMapEditorCubit extends Cubit<PatchMapEditorState> {
  PatchMapEditorCubit(
    this.client,
    this.download, {
    this.watchInterval,
    this.companionCacheKey,
    this.retryDelay = const Duration(seconds: 5),
    this.companionCheckInterval = const Duration(minutes: 1),
  }) : super(const PatchMapEditorState());
  final Duration? watchInterval;
  final String? companionCacheKey;
  final _pending = <int, Map<String, Object>>{};
  final _pendingNames = <int, String>{};
  Timer? _editTimer;
  final Duration retryDelay;
  final Duration companionCheckInterval;
  DateTime _nextRetry = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nextCompanionCheck = DateTime.fromMillisecondsSinceEpoch(0);
  bool _synchronizing = false;
  Timer? _watch;
  Future<void>? _refreshing;
  Map<String, int> _observedProperties = const {};

  @override
  Future<void> close() {
    _watch?.cancel();
    _editTimer?.cancel();
    return super.close();
  }

  void setWatching(bool active) {
    _watch?.cancel();
    _watch = null;
    if (active && !isClosed && watchInterval != null) {
      _watch = Timer.periodic(watchInterval!, (_) => synchronize());
    }
  }

  /// Reconcile desired fields against fresh NT state before retrying a write.
  Future<void> synchronize() async {
    if (isClosed || state.busy || _synchronizing) return;
    _synchronizing = true;
    try {
      if (state.map == null || state.error != null) {
        if (DateTime.now().isBefore(_nextRetry)) {
          return;
        }
        await load(refreshCompanion: true);
      } else {
        await refresh();
      }
      if (!isClosed && state.editable) await _flushPending();
    } catch (error) {
      _nextRetry = DateTime.now().add(
        error is PatchMapSyncException && error.status == 3
            ? Duration.zero
            : retryDelay,
      );
      if (!isClosed) {
        _publish(
          PatchMapEditorState(
            map: state.map,
            document: state.document,
            error: error.toString(),
          ),
        );
      }
    } finally {
      _synchronizing = false;
    }
  }

  void queueConnection(int socket, String field, Object value) {
    if (isClosed || state.map == null) return;
    if (!const {'destination', 'colour', 'tag', 'group'}.contains(field)) {
      throw ArgumentError.value(field, 'field');
    }
    if (field == 'destination' &&
        value is String &&
        value.length > PatchMap.maxEditableTextLength &&
        value != state.map!.connections[socket].destination) {
      throw const FormatException('Destination must be at most 32 characters');
    }
    // Validate against the visible row before retaining this desired field.
    PatchConnection.fromJson({
      ...state.map!.connections[socket].toJson(),
      field: value,
    });
    (_pending[socket] ??= {})[field] = value;
    _publish(state);
    _scheduleSync();
  }

  void queueExpanderName(int index, String name) {
    if (isClosed || state.map == null) return;
    PatchExpander(type: state.map!.expanders[index].type, name: name);
    _pendingNames[index] = name;
    _publish(state);
    _scheduleSync();
  }

  void _scheduleSync() {
    _editTimer?.cancel();
    _editTimer = Timer(const Duration(milliseconds: 300), () => synchronize());
  }

  void _publish(PatchMapEditorState next) {
    var map = next.map;
    if (map != null) {
      var current = map;
      for (final entry in _pending.entries) {
        if (entry.key >= current.connections.length) continue;
        current = current.withConnection(
          PatchConnection.fromJson({
            ...current.connections[entry.key].toJson(),
            ...entry.value,
          }),
        );
      }
      for (final entry in _pendingNames.entries) {
        if (entry.key < current.expanders.length) {
          current = current.renameExpander(entry.key, entry.value);
        }
      }
      map = current;
    }
    emit(
      PatchMapEditorState(
        map: map,
        document: next.document,
        busy: next.busy,
        error: next.error,
        applied: next.applied,
        fromDevice: next.fromDevice,
        pending: _pending.isNotEmpty || _pendingNames.isNotEmpty,
      ),
    );
  }

  Future<void> _flushPending() async {
    // Capture a pass; edits made while awaiting acknowledgement form the next pass.
    for (final socket in _pending.keys.toList()) {
      if (isClosed || !state.editable) return;
      final fields = Map<String, Object>.of(_pending[socket]!);
      final map = client.snapshot!;
      if (socket >= map.connections.length) {
        throw StateError('The edited socket no longer exists on the NT');
      }
      final actual = map.connections[socket].toJson();
      if (fields.entries.any((e) => actual[e.key] != e.value)) {
        await setConnection(PatchConnection.fromJson({...actual, ...fields}));
      }
      if (isClosed || state.error != null) return;
      for (final field in fields.entries) {
        if (_pending[socket]?[field.key] == field.value) {
          _pending[socket]!.remove(field.key);
        }
      }
      if (_pending[socket]?.isEmpty ?? false) _pending.remove(socket);
      _publish(state);
    }
    for (final index in _pendingNames.keys.toList()) {
      if (isClosed || !state.editable) return;
      final name = _pendingNames[index]!;
      if (client.snapshot!.expanders[index].name != name) {
        await renameExpander(index, name);
      }
      if (isClosed || state.error != null) return;
      if (_pendingNames[index] == name) _pendingNames.remove(index);
      _publish(state);
    }
    if (_pending.isNotEmpty || _pendingNames.isNotEmpty) _scheduleSync();
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
      final checkCompanion =
          _pending.isEmpty &&
          _pendingNames.isEmpty &&
          !DateTime.now().isBefore(_nextCompanionCheck);
      if (!mapChanged && changes.isEmpty && !checkCompanion) return;
      var companion = _companion!;
      if (checkCompanion) {
        _nextCompanionCheck = DateTime.now().add(companionCheckInterval);
        companion = await SdCardCompanion.load(
          download,
          guid: 'ThPh',
          cacheKey: companionCacheKey,
          refresh: true,
        );
      }
      final document = CompanionTable.parse(
        await companion.evaluate(
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
      _companion = companion;
      _observedProperties = client.properties;
      _publish(
        PatchMapEditorState(
          map: map,
          document: document,
          applied: previous.applied,
          fromDevice: true,
        ),
      );
    } catch (error) {
      _nextRetry = DateTime.now().add(
        error is PatchMapSyncException && error.status == 3
            ? Duration.zero
            : retryDelay,
      );
      if (!isClosed) {
        _publish(
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

  Future<void> load({bool refreshCompanion = false}) => _run(() async {
    _companion = null;
    final source = await SdCardCompanion.load(
      download,
      guid: 'ThPh',
      cacheKey: companionCacheKey,
      refresh: refreshCompanion,
    );
    if (isClosed) throw StateError('Editor closed');
    final PatchMap map;
    try {
      map = await client.load();
    } on TimeoutException {
      throw const PatchMapSyncException('Patch Helper is not responding.');
    }
    _companion = source;
    _observedProperties = const {};
    return map;
  }, applied: false);
  Future<void> setConnection(PatchConnection row) =>
      _action({'type': 'set_connection', 'connection': row.toJson()});
  Future<void> chooseAction(String id, int value) async {
    // Recheck the latest document after the dialog, including background Lua changes.
    if (!state.editable ||
        state.pending ||
        state.map!.expanders.length >= PatchMap.maxNewExpanders) {
      return;
    }
    final allowed = state.document!.actions.any(
      (action) => action.id == id && action.choices.containsKey(value),
    );
    if (allowed && id == 'add_expander') await addExpander(value);
  }

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
        throw const PatchMapSyncException('Patch Helper is reconnecting.');
      }
      final action = await _companion!.evaluate(
        _snapshot(state.map!),
        event: event,
      );
      if (isClosed) throw StateError('Editor closed');
      // Each user gesture grants only its own action kind. The companion receives
      // no transport object, file API, or unrestricted parameter-writing function.
      if (action['type'] != event['type'] ||
          (event['type'] == 'add_expander' &&
              action['model'] != event['model'])) {
        throw const FormatException('Companion changed the action kind');
      }
      return switch (action['type']) {
        'set_connection' => client.setConnection(
          PatchConnection.fromJson(_object(action['connection'])),
        ),
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
    _publish(
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
        _publish(
          PatchMapEditorState(map: map, document: document, applied: applied),
        );
      }
    } catch (error) {
      _nextRetry = DateTime.now().add(
        error is PatchMapSyncException && error.status == 3
            ? Duration.zero
            : retryDelay,
      );
      if (!isClosed) {
        _publish(
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
