import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/preset_browser_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sd_card_file_activity.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart'
    show AmbiguousResponseAttributionException;
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

export 'preset_browser_state.dart';

class PresetBrowserCubit extends Cubit<PresetBrowserState> {
  final IDistingMidiManager midiManager;
  final SharedPreferences prefs;
  final Clock _clock;
  final SdCardFileActivity _activity;
  Set<String> _busySeen = {};
  Set<String> _ownedPaths = {};
  bool _singlePaneLayout = false;
  int _navigationVersion = 0;
  final Duration focusFreshness;
  final Map<String, DateTime> _fetched = {};
  final Map<String, int> _versions = {};
  final Map<String, Future<bool>> _pending = {};
  Future<void>? _mutationTail;
  static const _historyKey = 'presetHistory';
  static const _lastPathKey = 'fileBrowserLastPath';
  static const _sortByDateKey = 'fileBrowserSortByDate';
  static const _maxHistoryItems = 20;

  PresetBrowserCubit({
    required this.midiManager,
    required this.prefs,
    Clock? clock,
    this.focusFreshness = const Duration(seconds: 5),
  }) : _clock = clock ?? const Clock(),
       _activity = SdCardFileActivity.forManager(midiManager),
       super(const PresetBrowserState.initial()) {
    _busySeen = _activity.value;
    _activity.addListener(_activityChanged);
  }

  @override
  Future<void> close() {
    _activity.removeListener(_activityChanged);
    return super.close(); // The connection lease outlives an in-flight upload.
  }

  void setSinglePaneLayout(bool value) {
    _singlePaneLayout = value;
  }

  Iterable<String> _visiblePaths(BrowserSnapshot browser) => _singlePaneLayout
      ? [browser.current.path]
      : {
          browser.current.path,
          ...PanelPosition.values.map(browser.path).whereType<String>(),
        };

  void _activityChanged() {
    final released = _busySeen
        .difference(_activity.value)
        .difference(_ownedPaths);
    _busySeen = _activity.value;
    final browser = _browser;
    if (browser == null || isClosed) return;
    _emit(browser);
    if (released.isNotEmpty) {
      final parents = released.map(p.posix.dirname).toSet();
      final visible = _visiblePaths(_browser!).toSet();
      final affected = {
        ..._fetched.keys,
        ..._browser!.listings.keys,
        ...visible,
      }.where((path) => parents.contains(path.toLowerCase())).toSet();
      _invalidate(affected, retainListings: true);
      for (final path in visible) {
        if (parents.contains(path.toLowerCase())) unawaited(_refresh(path));
      }
    }
  }

  void _warn(String message) {
    final browser = _browser;
    if (browser != null) _emit(browser.copyWith(warning: message));
  }

  Future<void> _rememberPath(String path) async {
    try {
      if (!await prefs.setString(_lastPathKey, path)) {
        throw StateError('Preference write rejected');
      }
    } catch (_) {
      _warn(
        'Browser location could not be saved. Device files are unchanged by this warning.',
      );
    }
  }

  BrowserSnapshot? get _browser => state.view;
  void _emit(BrowserSnapshot browser) {
    if (!isClosed) {
      emit(
        PresetBrowserState.loaded(
          browser: browser.copyWith(busyPaths: _activity.value),
        ),
      );
    }
  }

  BrowserFrame _frame(String path) => BrowserFrame(path: path);
  String _clean(String name) =>
      name.endsWith('/') ? name.substring(0, name.length - 1) : name;
  String _join(String base, String name) => p.posix.join(base, _clean(name));
  bool _below(String path, String root) =>
      path == root || path.startsWith('$root/');

  Future<void> loadRootDirectory() async {
    final savedPath = prefs.getString(_lastPathKey);
    final initialNavigation = _navigationVersion;
    emit(const PresetBrowserState.loading());
    _invalidate({..._fetched.keys, ..._pending.keys});
    _emit(
      BrowserSnapshot(
        stack: [_frame('/')],
        sortByDate: prefs.getBool(_sortByDateKey) ?? false,
      ),
    );
    var rootReady = await _read('/');
    if (!rootReady && _browser?.errors['/'] == null && !isClosed) {
      rootReady = await _read('/');
    }
    if (!rootReady) {
      if (!isClosed && _navigationVersion == initialNavigation) {
        emit(
          PresetBrowserState.error(
            message:
                'Failed to load root directory: ${_browser?.errors['/'] ?? 'No response'}',
            lastPath: '/',
          ),
        );
      }
      return;
    }
    if (savedPath != null &&
        savedPath != '/' &&
        savedPath.startsWith('/') &&
        _navigationVersion == initialNavigation) {
      final restoration = _navigationVersion + 1;
      await navigateToAbsolutePath(savedPath);
      if (_navigationVersion == restoration &&
          _browser?.current.path == savedPath &&
          _browser?.errors.containsKey(savedPath) == true) {
        await navigateToAbsolutePath('/');
      }
    }
  }

  /// Focus changes action context, not the shared hierarchy. Placeholders have
  /// no path and cannot trigger network traffic or become upload targets.
  Future<void> focusPane(PanelPosition position) async {
    final browser = _browser;
    final depth = browser?.depth(position);
    if (browser == null || depth == null) return;
    final path = browser.stack[depth].path;
    if (browser.activeDepth != depth) {
      _emit(browser.copyWith(activeDepth: depth));
    }
    final fetched = _fetched[path];
    if (fetched == null || _clock.now().difference(fetched) >= focusFreshness) {
      await _refresh(path);
    }
  }

  Future<void> refreshVisiblePanes({bool onlyIfStale = false}) async {
    final browser = _browser;
    if (browser == null) return;
    for (final path in _visiblePaths(browser)) {
      // A parent refresh can truncate vanished descendants; don't fetch them.
      if (_browser?.stack.any((frame) => frame.path == path) != true) continue;
      final fetched = _fetched[path];
      if (!onlyIfStale ||
          fetched == null ||
          _clock.now().difference(fetched) >= focusFreshness) {
        await _refresh(path);
      }
    }
  }

  Future<void> refreshPane([PanelPosition? position]) async {
    final browser = _browser;
    if (browser == null) return;
    final depth = position == null
        ? browser.stack.length - 1
        : browser.depth(position);
    if (depth == null) return;
    if (position != null) _emit(browser.copyWith(activeDepth: depth));
    await _refresh(browser.stack[depth].path);
  }

  /// Context menus capture a directory, never a shifting column index.
  Future<void> refreshDirectory(String path) async {
    if (_browser == null) {
      if (path == '/') await loadRootDirectory();
      return;
    }
    if (_browser!.stack.any((frame) => frame.path == path)) {
      await _refresh(path);
    }
  }

  bool isDirectoryReady(String path) {
    final browser = _browser;
    if (browser == null || browser.pendingPath != null) return false;
    final depth = browser.stack.indexWhere((frame) => frame.path == path);
    // A descendant is uncertain too while an ancestor's existence is checked.
    return depth >= 0 &&
        browser.stack
            .take(depth + 1)
            .every(
              (frame) =>
                  _fetched.containsKey(frame.path) &&
                  !browser.refreshing.contains(frame.path) &&
                  !browser.errors.containsKey(frame.path) &&
                  !browser.busyPaths.contains(frame.path.toLowerCase()),
            );
  }

  bool canUseEntry(String path) {
    final parent = p.posix.dirname(path);
    return isDirectoryReady(parent) &&
        !_activity.isBusy(path) &&
        _browser!.listings[parent]?.any(
              (entry) => _join(parent, entry.name) == path,
            ) ==
            true;
  }

  Future<void> _refresh(String path) async {
    await _read(path);
  }

  Future<bool> _read(String path, {void Function(DirectoryListing)? publish}) {
    final pending = _pending[path];
    if (pending != null) return pending;
    final version = _versions[path] ?? 0;
    final browser = _browser;
    if (browser == null || isClosed) return Future.value(false);
    _emit(browser.copyWith(refreshing: {...browser.refreshing, path}));
    late final Future<bool> task;
    task = Future<bool>.microtask(() async {
      try {
        final listing = await midiManager.requestDirectoryListing(path);
        if (isClosed || version != (_versions[path] ?? 0)) return false;
        if (listing == null) throw StateError('No directory listing returned');
        if (publish == null) {
          _publishListing(path, listing);
        } else {
          publish(listing);
        }
        return true;
      } catch (error) {
        if (!isClosed &&
            version == (_versions[path] ?? 0) &&
            _browser != null) {
          _fetched.remove(path);
          _emit(
            _browser!.copyWith(errors: {..._browser!.errors, path: '$error'}),
          );
        }
        return false;
      } finally {
        if (identical(_pending[path], task)) {
          _pending.remove(path);
          final current = _browser;
          if (current != null && !isClosed) {
            _emit(
              current.copyWith(
                refreshing: {...current.refreshing}..remove(path),
              ),
            );
          }
        }
      }
    });
    _pending[path] = task;
    return task;
  }

  void _publishListing(
    String path,
    DirectoryListing listing, {
    BrowserSnapshot Function(BrowserSnapshot)? transform,
  }) {
    final current = _browser;
    final browser = current == null
        ? null
        : transform?.call(current) ?? current;
    if (browser == null || isClosed) return;
    final entries = _sort(listing.entries, browser.sortByDate);
    _fetched[path] = _clock.now();
    final stack = _reconcile(browser.stack, path, entries, browser.pendingPath);
    _emit(
      browser.copyWith(
        listings: {...browser.listings, path: entries},
        errors: {...browser.errors}..remove(path),
        stack: stack,
        pendingPath:
            stack.length < browser.stack.length &&
                browser.pendingPath != null &&
                _below(browser.pendingPath!, browser.stack[stack.length].path)
            ? null
            : browser.pendingPath,
        activeDepth: browser.activeDepth.clamp(0, stack.length - 1),
      ),
    );
  }

  List<BrowserFrame> _reconcile(
    List<BrowserFrame> stack,
    String path,
    List<DirectoryEntry> entries,
    String? pendingPath,
  ) {
    final index = stack.indexWhere((frame) => frame.path == path);
    if (index < 0) return stack;
    final selected = entries
        .where((entry) => entry.name == stack[index].selectedName)
        .firstOrNull;
    final updated = [...stack];
    if (selected == null) {
      updated[index] = updated[index].copyWith(selectedName: null);
    }
    if (index + 1 < stack.length &&
        (selected == null ||
            !selected.isDirectory ||
            _join(path, selected.name) != stack[index + 1].path)) {
      // Prune the removed committed branch, but do not cancel a newer intent
      // to open an unrelated sibling that is still being hydrated.
      if (pendingPath == null || _below(pendingPath, stack[index + 1].path)) {
        _navigationVersion++;
      }
      return updated.sublist(0, index + 1);
    }
    return updated;
  }

  void _invalidate(
    Set<String> roots, {
    Set<String> subtrees = const {},
    // Freshness is revoked independently of presentation: keep the last
    // snapshot until a verified read can replace it, never flash an empty list.
    bool retainListings = true,
  }) {
    final browser = _browser;
    final paths = {
      ..._fetched.keys,
      ..._pending.keys,
      ...?_browser?.listings.keys,
      ...?_browser?.errors.keys,
      ...roots,
      ...subtrees,
    };
    final affected = paths
        .where(
          (path) =>
              roots.contains(path) ||
              subtrees.any((root) => _below(path, root)),
        )
        .toSet();
    for (final path in affected) {
      _versions[path] = (_versions[path] ?? 0) + 1;
      _pending.remove(path); // Old requests may finish, but cannot publish.
      _fetched.remove(path);
    }
    if (browser != null) {
      _emit(
        browser.copyWith(
          listings: {...browser.listings}
            ..removeWhere(
              (path, _) => affected.contains(path) && !retainListings,
            ),
          refreshing: {...browser.refreshing}..removeAll(affected),
          errors: {...browser.errors}
            ..removeWhere((path, _) => affected.contains(path)),
        ),
      );
    }
  }

  Future<void> _navigateStack(List<BrowserFrame> stack) async {
    final browser = _browser;
    if (browser == null || stack.isEmpty) return;
    final version = ++_navigationVersion;
    // Keep the committed hierarchy and its correctly labelled contents until
    // every destination column is ready. Never publish a new path with [] as
    // a stand-in for an unanswered listing (or show its predecessor's contents).
    _emit(browser.copyWith(pendingPath: stack.last.path));
    final paths = [
      for (var i = 0; i + 1 < stack.length; i++)
        if (!_fetched.containsKey(stack[i].path) ||
            browser.listings[stack[i].path]?.any(
                  (entry) =>
                      entry.isDirectory &&
                      _join(stack[i].path, entry.name) == stack[i + 1].path,
                ) !=
                true)
          stack[i].path,
      stack.last.path,
    ];
    for (final path in paths) {
      if (isClosed || _navigationVersion != version) return;
      if (!await _read(path)) {
        if (!isClosed && _navigationVersion == version) {
          _emit(_browser!.copyWith(pendingPath: null));
          _warn(
            'Could not open ${stack.last.path}: ${_browser?.errors[path] ?? 'listing superseded'}',
          );
        }
        return;
      }
    }
    if (isClosed || _navigationVersion != version) return;
    final current = _browser!;
    // A concurrent parent refresh may have removed the requested branch.
    final confirmed = [...stack];
    for (var i = 0; i + 1 < stack.length; i++) {
      if (current.listings[stack[i].path]?.any(
            (entry) =>
                entry.isDirectory &&
                _join(stack[i].path, entry.name) == stack[i + 1].path,
          ) !=
          true) {
        _emit(current.copyWith(pendingPath: null));
        _warn(
          'Could not open ${stack.last.path}: parent entry is unavailable.',
        );
        return;
      }
      final directory = current.listings[stack[i].path]!.firstWhere(
        (entry) =>
            entry.isDirectory &&
            _join(stack[i].path, entry.name) == stack[i + 1].path,
      );
      confirmed[i] = stack[i].copyWith(selectedName: directory.name);
    }
    _emit(
      current.copyWith(
        stack: confirmed,
        activeDepth: confirmed.length - 1,
        pendingPath: null,
      ),
    );
    unawaited(_rememberPath(stack.last.path));
  }

  Future<void> navigateToAbsolutePath(String path) async {
    final browser = _browser;
    if (browser == null) return;
    if (!path.startsWith('/')) throw ArgumentError.value(path, 'path');
    path = p.posix.normalize(path);
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    final paths = [
      '/',
      for (var i = 1; i <= parts.length; i++) '/${parts.take(i).join('/')}',
    ];
    final stack = <BrowserFrame>[];
    for (var i = 0; i < paths.length; i++) {
      final old = browser.stack
          .where((frame) => frame.path == paths[i])
          .firstOrNull;
      final selectedName = i + 1 < paths.length
          ? browser.listings[paths[i]]
                    ?.where(
                      (entry) =>
                          entry.isDirectory && _clean(entry.name) == parts[i],
                    )
                    .firstOrNull
                    ?.name ??
                '${parts[i]}/'
          : old?.selectedName;
      stack.add(BrowserFrame(path: paths[i], selectedName: selectedName));
    }
    await _navigateStack(stack);
  }

  Future<void> navigateBack() async {
    final browser = _browser;
    if (browser != null && browser.canGoBack) {
      await _navigateStack(browser.stack.sublist(0, browser.stack.length - 1));
    }
  }

  Future<void> selectDirectory(
    DirectoryEntry entry,
    PanelPosition panel,
  ) async {
    final browser = _browser;
    final depth = browser?.depth(panel);
    if (browser == null || depth == null || !entry.isDirectory) return;
    if (entry.name == '..') {
      await navigateToAbsolutePath(p.posix.dirname(browser.stack[depth].path));
      return;
    }
    final stack = browser.stack.take(depth + 1).toList();
    stack[depth] = stack[depth].copyWith(selectedName: entry.name);
    stack.add(_frame(_join(stack[depth].path, entry.name)));
    await _navigateStack(stack);
  }

  Future<void> selectFile(DirectoryEntry entry, PanelPosition panel) async {
    final browser = _browser;
    final depth = browser?.depth(panel);
    if (browser == null || depth == null || entry.isDirectory) return;
    final stack = browser.stack.take(depth + 1).toList();
    stack[depth] = stack[depth].copyWith(selectedName: entry.name);
    _navigationVersion++;
    _emit(
      browser.copyWith(stack: stack, activeDepth: depth, pendingPath: null),
    );
    unawaited(_rememberPath(stack.last.path));
    if (entry.name.toLowerCase().endsWith('.json')) {
      await addToHistory(_join(stack.last.path, entry.name));
    }
  }

  Future<void> navigateIntoDirectory(DirectoryEntry entry) async {
    if (_browser != null) {
      await selectDirectory(
        entry,
        PanelPosition.values[_browser!.stack.length -
            1 -
            _browser!.viewportStart],
      );
    }
  }

  Future<void> selectDrillItem(DirectoryEntry entry) async {
    if (_browser != null) {
      await selectFile(
        entry,
        PanelPosition.values[_browser!.stack.length -
            1 -
            _browser!.viewportStart],
      );
    }
  }

  Future<void> navigateToPathSegment(int index) async {
    final stack = _browser?.stack;
    if (stack == null || index < -1 || index >= stack.length - 1) return;
    await _navigateStack(stack.take(index + 2).toList());
  }

  String getSelectedPath() {
    final browser = _browser;
    if (browser == null) return '';
    final path = browser.focused.path;
    if (!isDirectoryReady(path)) return '';
    final selected = browser.selectedAt(browser.activeDepth);
    if (selected == null || selected.isDirectory) return '';
    final fullPath = _join(path, selected.name);
    return _activity.isBusy(fullPath) ? '' : fullPath;
  }

  String getCurrentDirectory() => _browser?.current.path ?? '/';
  String getPanelDirectory(PanelPosition panel) => _browser?.path(panel) ?? '';
  String getSelectedDirectoryPath() => getCurrentDirectory();
  String getEntryPath(DirectoryEntry entry, String panelDirectory) =>
      _join(panelDirectory, entry.name);

  void toggleSortMode() {
    final browser = _browser;
    if (browser == null) return;
    final byDate = !browser.sortByDate;
    unawaited(prefs.setBool(_sortByDateKey, byDate));
    _emit(
      browser.copyWith(
        sortByDate: byDate,
        listings: {
          for (final entry in browser.listings.entries)
            entry.key: _sort(entry.value, byDate),
        },
      ),
    );
  }

  List<DirectoryEntry> _sort(List<DirectoryEntry> entries, bool byDate) =>
      [...entries.where((e) => e.name != '..')]..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        if (byDate) {
          final date = b.date.compareTo(a.date);
          if (date != 0) return date;
          final time = b.time.compareTo(a.time);
          if (time != 0) return time;
        }
        return _clean(
          a.name,
        ).toLowerCase().compareTo(_clean(b.name).toLowerCase());
      });

  Future<List<String>> loadRecentPresets() async =>
      prefs.getStringList(_historyKey) ?? [];
  Future<void> addToHistory(String path) async {
    final history = prefs.getStringList(_historyKey) ?? [];
    await prefs.setStringList(
      _historyKey,
      [
        path,
        ...history.where((item) => item != path),
      ].take(_maxHistoryItems).toList(),
    );
  }

  Future<void> clearCache() async => _invalidate({
    ...?_browser?.listings.keys,
    ..._pending.keys,
  }, retainListings: false);

  Future<void> _afterMutation(
    String parent, {
    bool parentAlreadyFresh = false,
  }) async {
    final paths = {
      parent,
      ...(_browser == null ? <String>[] : _visiblePaths(_browser!)),
    };
    for (final path in paths) {
      if ((path == parent && !parentAlreadyFresh) ||
          !_fetched.containsKey(path)) {
        await _refresh(path);
      }
    }
  }

  // Wire requests are sequential already; serialize whole mutation workflows
  // too, so a later mutation cannot overtake an earlier verification/read-back.
  Future<void> _mutate(
    Future<void> Function() operation, {
    Set<String> touched = const {},
  }) {
    Future<void> run() async {
      if (isClosed) throw StateError('File browser is closed');
      try {
        await _activity.hold(touched, () async {
          // Mark only leases actually acquired, and retain ownership through
          // hold's release notification (not through a failed acquisition).
          _ownedPaths = touched
              .map(
                (path) => p.posix
                    .normalize(path.startsWith('/') ? path : '/$path')
                    .toLowerCase(),
              )
              .toSet();
          await operation();
        });
      } finally {
        _ownedPaths = {};
      }
    }

    // Acquire the first lease immediately, before the first chunk can truncate.
    final previous = _mutationTail;
    final result = previous == null
        ? Future<void>.sync(run)
        : previous.then((_) => run());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> renameEntry(String fullPath, String newName) => _mutate(
    () => _renameEntry(fullPath, newName),
    touched: {fullPath, _join(p.posix.dirname(fullPath), newName)},
  );

  Future<void> _renameEntry(String fullPath, String newName) async {
    if (newName.isEmpty ||
        newName == '.' ||
        newName == '..' ||
        newName.contains('/') ||
        newName.contains('\\') ||
        newName.codeUnits.any((c) => c < 32 || c > 126)) {
      throw ArgumentError.value(newName, 'newName', 'Invalid filename');
    }
    final parent = p.posix.dirname(fullPath);
    final newPath = _join(parent, newName);
    if (newPath == fullPath) return;
    SdCardStatus? result;
    try {
      result = await midiManager.requestFileRename(fullPath, newPath);
    } catch (_) {
      _invalidate(
        {parent},
        subtrees: {fullPath, newPath},
        retainListings: true,
      );
      await _afterMutation(parent);
      rethrow;
    }
    _invalidate({parent}, subtrees: {fullPath, newPath}, retainListings: true);
    if (result == null) {
      _renameUncertain(parent, 'Rename was not acknowledged.');
    }
    if (!result.success) {
      await _afterMutation(parent);
      throw StateError(result.message);
    }
    String rewrite(String path) => _below(path, fullPath)
        ? '$newPath${path.substring(fullPath.length)}'
        : path;
    final verified = await _read(
      parent,
      publish: (listing) {
        final renamed = listing.entries
            .where((e) => _clean(e.name) == newName)
            .firstOrNull;
        if (renamed == null ||
            listing.entries.any(
              (e) => _clean(e.name) == p.posix.basename(fullPath),
            )) {
          throw StateError('The new directory entry could not be verified.');
        }
        // Atomic with publication, before selection reconciliation and preferences.
        _publishListing(
          parent,
          listing,
          transform: (browser) => browser.copyWith(
            // A directory rename changes its address, not its descendants'
            // contents. Rebase their last snapshots as stale instead of
            // dropping them and painting blank columns before verification.
            listings: {
              for (final cached in browser.listings.entries)
                if (!_below(cached.key, newPath))
                  rewrite(cached.key): cached.value,
            },
            renamedPaths: {
              for (final alias in browser.renamedPaths.entries)
                alias.key: rewrite(alias.value),
              fullPath: newPath,
            },
            stack: [
              for (final frame in browser.stack)
                frame.copyWith(
                  path: rewrite(frame.path),
                  selectedName:
                      frame.selectedName != null &&
                          _join(frame.path, frame.selectedName!) == fullPath
                      ? renamed.name
                      : frame.selectedName,
                ),
            ],
          ),
        );
      },
    );
    if (!verified) {
      _renameUncertain(
        parent,
        'Rename acknowledged, but read-back failed: ${_browser?.errors[parent] ?? 'verification superseded'}',
      );
    }
    await _afterMutation(parent, parentAlreadyFresh: true);
    // Ancillary persistence cannot roll back authoritative device/view state.
    try {
      if (!await prefs.setStringList(
        _historyKey,
        (prefs.getStringList(_historyKey) ?? []).map(rewrite).toSet().toList(),
      )) {
        throw StateError('Preference write rejected');
      }
      final last = prefs.getString(_lastPathKey);
      if (last != null && !await prefs.setString(_lastPathKey, rewrite(last))) {
        throw StateError('Preference write rejected');
      }
    } catch (_) {
      _warn(
        'Renamed on the device, but recent history/location could not be saved.',
      );
    }
  }

  Never _renameUncertain(String parent, String reason) {
    final message =
        '$reason The file may have changed. Refresh before retrying.';
    final browser = _browser;
    if (browser != null && !isClosed) {
      // Fail closed for this directory without discarding the shared ancestry.
      _emit(browser.copyWith(errors: {...browser.errors, parent: message}));
    }
    throw StateError(message);
  }

  Future<void> _checkStatus(Future<SdCardStatus?> operation) async {
    final status = await operation;
    if (status == null || !status.success) {
      throw StateError(status?.message ?? 'No response');
    }
  }

  Future<void> deleteEntry(String fullPath) =>
      _mutate(() => _deleteEntry(fullPath), touched: {fullPath});

  Future<void> _deleteEntry(String fullPath) async {
    final parent = p.posix.dirname(fullPath);
    try {
      await _checkStatus(midiManager.requestFileDelete(fullPath));
    } catch (_) {
      _invalidate({parent}, subtrees: {fullPath});
      await _afterMutation(parent);
      rethrow;
    }
    _invalidate({parent}, subtrees: {fullPath});
    final browser = _browser;
    if (browser != null) {
      final survivors = browser.stack
          .takeWhile((frame) => !_below(frame.path, fullPath))
          .toList();
      final pendingWasDeleted =
          browser.pendingPath != null && _below(browser.pendingPath!, fullPath);
      // A completed mutation may overlap an already-started navigation. Keep
      // an unrelated latest intent alive; explicitly clear a deleted target.
      if (browser.pendingPath == null || pendingWasDeleted) {
        _navigationVersion++;
      }
      _emit(
        browser.copyWith(
          pendingPath: pendingWasDeleted ? null : browser.pendingPath,
          stack: survivors.isEmpty ? [_frame('/')] : survivors,
          activeDepth: browser.activeDepth.clamp(
            0,
            survivors.isEmpty ? 0 : survivors.length - 1,
          ),
        ),
      );
    }
    await prefs.setStringList(
      _historyKey,
      (prefs.getStringList(_historyKey) ?? [])
          .where((path) => !_below(path, fullPath))
          .toList(),
    );
    final lastPath = prefs.getString(_lastPathKey);
    if (lastPath != null && _below(lastPath, fullPath)) {
      await prefs.setString(_lastPathKey, getCurrentDirectory());
    }
    await _afterMutation(parent);
  }

  Future<void> createDirectory(String parentPath, String name) =>
      _mutate(() async {
        try {
          await _checkStatus(
            midiManager.requestDirectoryCreate(_join(parentPath, name)),
          );
        } finally {
          _invalidate({parentPath});
          await _afterMutation(parentPath);
        }
      }, touched: {_join(parentPath, name)});

  Future<Uint8List?> downloadFile(String fullPath) => _retryRead(() async {
    _activity.requireAvailable(fullPath);
    final data = await midiManager.requestFileDownload(fullPath);
    if (data == null) throw StateError('No response');
    return data;
  });

  // Keep the existing bounded download recovery, but never replay mutations.
  Future<T> _retryRead<T>(Future<T> Function() read) async {
    final watch = Stopwatch()..start();
    var delay = const Duration(milliseconds: 500);
    while (true) {
      if (isClosed) throw StateError('File browser is closed');
      try {
        return await read();
      } catch (error) {
        if (error is AmbiguousResponseAttributionException ||
            error is SdCardFileBusyException) {
          rethrow;
        }
        if (isClosed || watch.elapsed + delay >= const Duration(seconds: 30)) {
          rethrow;
        }
        await Future<void>.delayed(delay);
        delay = delay * 2;
        if (delay > const Duration(seconds: 4)) {
          delay = const Duration(seconds: 4);
        }
      }
    }
  }

  Future<void> uploadFile(
    String targetDirectory,
    String fileName,
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) => _mutate(
    () => _uploadFile(targetDirectory, fileName, data, onProgress: onProgress),
    touched: {_join(targetDirectory, fileName)},
  );

  Future<void> _uploadFile(
    String targetDirectory,
    String fileName,
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    final target = _join(targetDirectory, fileName);
    // Keep uploads bounded to the protocol's 512-byte file-data chunks.
    try {
      for (
        var offset = 0;
        offset < data.length || (offset == 0 && data.isEmpty);
        offset += 512
      ) {
        final end = (offset + 512).clamp(0, data.length);
        await _checkStatus(
          midiManager.requestFileUploadChunk(
            target,
            data.sublist(offset, end),
            offset,
            createAlways: offset == 0,
          ),
        );
        onProgress?.call(data.isEmpty ? 1 : end / data.length);
        if (end < data.length) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    } finally {
      _invalidate({targetDirectory});
      await _afterMutation(targetDirectory);
    }
  }
}
