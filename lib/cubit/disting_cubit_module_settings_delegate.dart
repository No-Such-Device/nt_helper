part of 'disting_cubit.dart';

final class _ModuleSettingsScope {
  _ModuleSettingsScope(this.id, this.manager, this.firmware);
  final int id;
  final IDistingMidiManager manager;
  final String firmware;
  final cancellation = DistingRequestCancellation();
  ModuleSettingsTransport get transport => manager as ModuleSettingsTransport;
  ModuleSettingsTree? tree;
  Map<int, ModuleSettingEdit> edits = {};
  bool attempted = false;
  bool busy = false;
  bool dirty = false;
  bool actionUncertain = false;
  String message = '';
}

final class _ModuleSettingsDelegate {
  _ModuleSettingsDelegate(this._cubit);
  final DistingCubit _cubit;
  final _states = StreamController<ModuleSettingsState>.broadcast();
  ModuleSettingsState _state = ModuleSettingsState(
    unavailableReason:
        'Connect to a disting NT to read or change module settings.',
  );
  _ModuleSettingsScope? _scope;
  int _sequence = 0;
  bool _disposed = false;
  String? _reason;
  ModuleSettingsState get state {
    _synchronize(_cubit.state);
    return _state;
  }

  Stream<ModuleSettingsState> get stream => _states.stream;

  void onDistingStateWillChange(DistingState next) => _synchronize(next);

  void clearConnection() {
    if (_disposed) return;
    _scope?.cancellation.cancel();
    _scope = null;
    _reason = 'Connect to a disting NT to read or change module settings.';
    _publish();
  }

  void _synchronize(DistingState next) {
    if (_disposed) return;
    final reason = _cubit._connectionDelegate.isTransportDisconnected
        ? 'Connect to a disting NT to read or change module settings.'
        : switch (next) {
            DistingStateSynchronized(demo: true) =>
              'Module settings are unavailable in Demo mode.',
            DistingStateSynchronized(offline: true) =>
              'Connect to a disting NT to read or change module settings.',
            DistingStateSynchronized(:final firmwareVersion)
                when !firmwareVersion.isModuleSettingsCandidate =>
              'NT Settings requires recognized firmware 1.20 or later, with settings protocol support.',
            DistingStateSynchronized(:final disting)
                when disting is! ModuleSettingsTransport =>
              'This connection does not support NT Settings.',
            DistingStateSynchronized() => null,
            _ => 'Connect to a disting NT to read or change module settings.',
          };
    final manager = reason == null && next is DistingStateSynchronized
        ? next.disting
        : null;
    final firmware = next is DistingStateSynchronized
        ? next.firmwareVersion.versionString
        : '';
    final old = _scope;
    if (old != null &&
        (!identical(manager, old.manager) || firmware != old.firmware)) {
      old.cancellation.cancel();
      _scope = null;
    }
    if (manager != null && _scope == null) {
      _scope = _ModuleSettingsScope(++_sequence, manager, firmware);
    }
    if (_reason != reason || !identical(old, _scope)) {
      _reason = reason;
      _publish();
    }
  }

  bool _current(_ModuleSettingsScope scope) =>
      !_disposed &&
      identical(_scope, scope) &&
      !scope.cancellation.isCancelled &&
      _reason == null;

  void _publish() {
    final scope = _scope;
    _state = ModuleSettingsState(
      connectionId: scope?.id ?? _state.connectionId,
      unavailableReason: _reason,
      tree: scope?.tree ?? (_reason != null ? _state.tree : null),
      settings: scope?.edits ?? (_reason != null ? _state.settings : const {}),
      busy: scope?.busy ?? false,
      message: scope?.message ?? '',
      changedOnModule: scope?.dirty ?? false,
      actionUncertain: scope?.actionUncertain ?? false,
    );
    if (!_states.isClosed) _states.add(_state);
  }

  Future<void> load({bool force = false}) async {
    _synchronize(_cubit.state);
    final scope = _scope;
    if (scope == null || scope.busy || scope.attempted && !force) return;
    if (force &&
        scope.tree != null &&
        !scope.actionUncertain &&
        scope.edits.values.any((e) => e.needsRefresh)) {
      await _recoverValues(scope);
      return;
    }
    scope.attempted = true;
    scope.busy = true;
    scope.message = 'Reading module settings…';
    _publish();
    try {
      final tree = await scope.transport.discoverModuleSettings(
        scope.cancellation,
      );
      final edits = <int, ModuleSettingEdit>{};
      for (final id in tree.settingIds) {
        if (!_current(scope)) return;
        final info = await scope.transport.requestModuleSettingInfo(
          id,
          scope.cancellation,
        );
        if (!_current(scope)) return;
        final value = await scope.transport.requestModuleSettingValue(
          id,
          scope.cancellation,
        );
        final previous = scope.edits[id];
        // Keep drafts only when the setting's wire contract is unchanged.
        final compatible =
            previous != null &&
            previous.info.name == info.name &&
            previous.info.type == info.type &&
            previous.info.min == info.min &&
            previous.info.max == info.max &&
            previous.info.unit == info.unit &&
            previous.info.maxLength == info.maxLength &&
            previous.info.flags == info.flags &&
            listEquals(previous.info.enums, info.enums);
        edits[id] = ModuleSettingEdit(
          info: info,
          observed: value,
          draft: compatible ? previous.draft : null,
          error: compatible && previous.draft != null
              ? info.validate(previous.draft!)
              : null,
        );
      }
      if (!_current(scope)) return;
      scope.tree = tree;
      scope.edits = edits;
      scope.actionUncertain = false;
      scope.message = '';
    } catch (error) {
      if (!_current(scope)) return;
      scope.actionUncertain = true;
      scope.message = 'Settings unavailable. Refresh or reconnect. $error';
    } finally {
      if (_current(scope)) {
        scope.busy = false;
        _publish();
      }
    }
  }

  Future<void> _recoverValues(_ModuleSettingsScope scope) async {
    scope.busy = true;
    scope.message = 'Reading module settings…';
    _publish();
    try {
      for (final id in scope.tree!.settingIds) {
        if (!_current(scope)) return;
        final previous = scope.edits[id]!;
        try {
          final value = await scope.transport.requestModuleSettingValue(
            id,
            scope.cancellation,
          );
          if (!_current(scope)) return;
          final draft = previous.draft?.sameValue(value) == true
              ? null
              : previous.draft;
          scope.edits = {
            ...scope.edits,
            id: ModuleSettingEdit(
              info: previous.info,
              observed: value,
              draft: draft,
              error: draft == null ? null : previous.info.validate(draft),
            ),
          };
        } catch (error) {
          if (!_current(scope)) return;
          scope.edits = {
            ...scope.edits,
            id: ModuleSettingEdit(
              info: previous.info,
              observed: previous.observed,
              draft: previous.draft,
              error: 'Refresh failed. $error',
              uncertain: previous.uncertain,
              refreshRequired: true,
            ),
          };
        }
      }
      scope.message = scope.edits.values.any((e) => e.needsRefresh)
          ? 'Some settings could not be read.'
          : '';
    } finally {
      if (_current(scope)) {
        scope.busy = false;
        _publish();
      }
    }
  }

  void edit(int id, ModuleSettingValue value) {
    final snapshot = state;
    final scope = _scope;
    final previous = scope?.edits[id];
    if (!snapshot.ready ||
        scope == null ||
        previous == null ||
        !previous.info.writable ||
        previous.needsRefresh) {
      return;
    }
    scope.edits = {
      ...scope.edits,
      id: ModuleSettingEdit(
        info: previous.info,
        observed: previous.observed,
        draft: value.sameValue(previous.observed) ? null : value,
        error: previous.info.validate(value),
        uncertain: previous.uncertain,
        refreshRequired: previous.refreshRequired,
      ),
    };
    _publish();
  }

  void discardDrafts() {
    final snapshot = state;
    final scope = _scope;
    if (!snapshot.ready || scope == null) return;
    scope.edits = {
      for (final e in scope.edits.entries)
        e.key: ModuleSettingEdit(
          info: e.value.info,
          observed: e.value.observed,
          uncertain: e.value.uncertain,
          refreshRequired: e.value.refreshRequired,
          error: e.value.needsRefresh ? e.value.error : null,
        ),
    };
    _publish();
  }

  Future<void> applyGroup(int groupId) async {
    final snapshot = state;
    final scope = _scope;
    if (scope == null || !snapshot.canApplyGroup(groupId)) return;
    final ids =
        scope.tree?.groups[groupId]?.children
            .where((c) => !c.isGroup)
            .map((c) => c.id)
            .where(
              (id) =>
                  scope.edits[id]!.changed && !scope.edits[id]!.needsRefresh,
            )
            .toList() ??
        [];
    if (ids.isEmpty ||
        ids.any(
          (id) =>
              scope.edits[id]!.info.validate(scope.edits[id]!.displayed) !=
              null,
        )) {
      return;
    }
    scope.busy = true;
    scope.message = 'Applying changes and reading them back…';
    _publish();
    try {
      for (final id in ids) {
        if (!_current(scope)) return;
        final before = scope.edits[id]!;
        try {
          final observed = await scope.transport.writeModuleSetting(
            id,
            before.displayed,
            scope.cancellation,
          );
          if (!_current(scope)) return;
          scope.dirty = true;
          final matches = observed.sameValue(before.displayed);
          scope.edits = {
            ...scope.edits,
            id: ModuleSettingEdit(
              info: before.info,
              observed: observed,
              draft: matches ? null : before.draft,
              error: matches ? null : 'Requested value was not confirmed. Refresh before applying again.',
              uncertain: !matches,
            ),
          };
          if (!matches) break;
        } catch (error) {
          if (!_current(scope)) return;
          final mayHaveSent =
              error is! ModuleSettingWriteException ||
              error.mutationMayHaveOccurred;
          if (mayHaveSent) scope.dirty = true;
          scope.edits = {
            ...scope.edits,
            id: ModuleSettingEdit(
              info: before.info,
              observed: before.observed,
              draft: before.draft,
              error: '$error',
              uncertain: mayHaveSent,
              refreshRequired: true,
            ),
          };
          break;
        }
      }
      if (_current(scope)) {
        scope.message = scope.edits.values.any((s) => s.needsRefresh)
            ? 'Some settings await refresh; they are not resent.'
            : 'Values confirmed. Not committed to flash.';
      }
    } finally {
      if (_current(scope)) {
        scope.busy = false;
        _publish();
      }
    }
  }

  Future<void> action(int action) async {
    final snapshot = state;
    final scope = _scope;
    if (scope == null || !snapshot.canCommit || action != 0 && action != 2) {
      return;
    }
    scope.busy = true;
    scope.message = action == 0
        ? 'Sending commit to flash…'
        : 'Sending revert to saved…';
    _publish();
    try {
      await scope.transport.sendModuleSettingsAction(
        action,
        scope.cancellation,
      );
      if (!_current(scope)) return;
      scope.dirty = false;
      scope.actionUncertain = action == 2;
      scope.message = action == 0
          ? 'Commit sent. Flash persistence is not acknowledged by the module.'
          : 'Revert sent. Refresh to read settings; MIDI may have changed.';
    } catch (error) {
      if (!_current(scope)) return;
      scope.actionUncertain = true;
      scope.message =
          'Action not confirmed. $error Refresh or reconnect before more writes.';
    } finally {
      if (_current(scope)) {
        scope.busy = false;
        _publish();
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _scope?.cancellation.cancel();
    _scope = null;
    await _states.close();
  }
}
