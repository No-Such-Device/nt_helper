import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/preset_browser_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

export 'preset_browser_state.dart';

class PresetBrowserCubit extends Cubit<PresetBrowserState> {
  final IDistingMidiManager midiManager;
  final SharedPreferences prefs;
  final Clock _clock;
  final Duration focusFreshness;
  final Map<String, DateTime> _fetched = {};
  final Map<String, int> _versions = {};
  final Map<String, Future<bool>> _pending = {};
  Future<void> _mutationTail = Future.value();
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
       super(const PresetBrowserState.initial());

  BrowserSnapshot? get _browser => state.view;
  void _emit(BrowserSnapshot browser) {
    if (!isClosed) emit(PresetBrowserState.loaded(browser: browser));
  }

  BrowserFrame _frame(String path) => BrowserFrame(path: path);
  String _clean(String name) =>
      name.endsWith('/') ? name.substring(0, name.length - 1) : name;
  String _join(String base, String name) => p.posix.join(base, _clean(name));
  bool _below(String path, String root) =>
      path == root || path.startsWith('$root/');

  Future<void> loadRootDirectory() async {
    emit(const PresetBrowserState.loading());
    _invalidate({..._fetched.keys, ..._pending.keys});
    _emit(
      BrowserSnapshot(
        panes: [
          for (final _ in PanelPosition.values)
            BrowserPane(stack: [_frame('/')]),
        ],
        sortByDate: prefs.getBool(_sortByDateKey) ?? false,
      ),
    );
    if (!await _read('/')) {
      if (!isClosed) {
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
    final savedPath = prefs.getString(_lastPathKey);
    if (savedPath != null && savedPath != '/' && savedPath.startsWith('/')) {
      await navigateToAbsolutePath(savedPath);
      // An unavailable saved folder must not strand the browser.
      if (_browser?.errors.containsKey(savedPath) == true) {
        await navigateToAbsolutePath('/');
      }
    }
  }

  /// Enter/back always revalidate. Focus/resume only revalidates stale paths.
  /// Concurrent panes displaying the same path share one in-flight request.
  Future<void> focusPane(PanelPosition position) async {
    final browser = _browser;
    if (browser == null) return;
    final path = browser.pane(position).current.path;
    if (browser.activePane != position) {
      _emit(browser.copyWith(activePane: position));
      unawaited(prefs.setString(_lastPathKey, path));
    }
    final fetched = _fetched[path];
    if (fetched == null || _clock.now().difference(fetched) >= focusFreshness) {
      await _refresh(path);
    }
  }

  Future<void> refreshVisiblePanes({bool onlyIfStale = false}) async {
    final browser = _browser;
    if (browser == null) return;
    for (final path in browser.panes.map((pane) => pane.current.path).toSet()) {
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
    if (browser != null) {
      if (position != null && browser.activePane != position) {
        _emit(browser.copyWith(activePane: position));
        unawaited(
          prefs.setString(_lastPathKey, browser.pane(position).current.path),
        );
      }
      await _refresh(browser.pane(position ?? browser.activePane).current.path);
    }
  }

  Future<void> _refresh(String path) async {
    await _read(path);
  }

  Future<bool> _read(String path) {
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
        _publishListing(path, listing);
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

  void _publishListing(String path, DirectoryListing listing) {
    final browser = _browser;
    if (browser == null || isClosed) return;
    final entries = _sort(listing.entries, browser.sortByDate);
    _fetched[path] = _clock.now();
    _emit(
      browser.copyWith(
        listings: {...browser.listings, path: entries},
        errors: {...browser.errors}..remove(path),
        panes: [
          for (final pane in browser.panes)
            pane.copyWith(
              stack: [
                for (final frame in pane.stack)
                  frame.path == path &&
                          !entries.any((e) => e.name == frame.selectedName)
                      ? frame.copyWith(selectedName: null)
                      : frame,
              ],
            ),
        ],
      ),
    );
  }

  void _invalidate(Set<String> roots, {Set<String> subtrees = const {}}) {
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
            ..removeWhere((path, _) => affected.contains(path)),
          refreshing: {...browser.refreshing}..removeAll(affected),
          errors: {...browser.errors}
            ..removeWhere((path, _) => affected.contains(path)),
        ),
      );
    }
  }

  Future<void> _navigate(
    PanelPosition position,
    List<BrowserFrame> stack,
  ) async {
    final browser = _browser;
    if (browser == null || stack.isEmpty) return;
    final panes = [...browser.panes];
    panes[position.index] = BrowserPane(stack: stack);
    _emit(browser.copyWith(panes: panes, activePane: position));
    unawaited(prefs.setString(_lastPathKey, stack.last.path));
    await _refresh(stack.last.path);
  }

  Future<void> navigateToAbsolutePath(
    String path, {
    PanelPosition? panel,
  }) async {
    final browser = _browser;
    if (browser == null) return;
    if (!path.startsWith('/')) throw ArgumentError.value(path, 'path');
    path = p.posix.normalize(path);
    final position = panel ?? browser.activePane;
    final stack = browser.pane(position).stack;
    final index = stack.lastIndexWhere((frame) => frame.path == path);
    await _navigate(
      position,
      index < 0 ? [...stack, _frame(path)] : stack.sublist(0, index + 1),
    );
  }

  Future<void> navigateBack([PanelPosition? panel]) async {
    final browser = _browser;
    if (browser == null) return;
    final position = panel ?? browser.activePane;
    final stack = browser.pane(position).stack;
    if (stack.length > 1) {
      await _navigate(position, stack.sublist(0, stack.length - 1));
    }
  }

  Future<void> selectDirectory(
    DirectoryEntry entry,
    PanelPosition panel,
  ) async {
    if (!entry.isDirectory || _browser == null) return;
    final current = _browser!.pane(panel).current.path;
    await navigateToAbsolutePath(
      entry.name == '..'
          ? p.posix.dirname(current)
          : _join(current, entry.name),
      panel: panel,
    );
  }

  Future<void> selectFile(DirectoryEntry entry, PanelPosition panel) async {
    final browser = _browser;
    if (browser == null || entry.isDirectory) return;
    final pane = browser.pane(panel);
    final panes = [...browser.panes];
    panes[panel.index] = pane.copyWith(
      stack: [
        ...pane.stack.take(pane.stack.length - 1),
        pane.current.copyWith(selectedName: entry.name),
      ],
    );
    _emit(browser.copyWith(panes: panes, activePane: panel));
    if (entry.name.toLowerCase().endsWith('.json')) {
      await addToHistory(_join(pane.current.path, entry.name));
    }
  }

  Future<void> navigateIntoDirectory(DirectoryEntry entry) async {
    if (_browser != null) await selectDirectory(entry, _browser!.activePane);
  }

  Future<void> selectDrillItem(DirectoryEntry entry) async {
    if (_browser != null) await selectFile(entry, _browser!.activePane);
  }

  Future<void> navigateToPathSegment(int index) async {
    final path = getCurrentDirectory();
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (index < -1 || index >= segments.length) return;
    await navigateToAbsolutePath(
      index == -1 ? '/' : '/${segments.take(index + 1).join('/')}',
    );
  }

  String getSelectedPath() {
    final browser = _browser;
    if (browser == null) return '';
    final path = browser.active.current.path;
    if (browser.refreshing.contains(path) || browser.errors.containsKey(path)) {
      return '';
    }
    final selected = browser.selection(browser.activePane);
    return selected == null || selected.isDirectory
        ? ''
        : _join(path, selected.name);
  }

  String getCurrentDirectory() => _browser?.active.current.path ?? '/';
  String getPanelDirectory(PanelPosition panel) =>
      _browser?.pane(panel).current.path ?? '/';
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

  Future<void> clearCache() async =>
      _invalidate({...?_browser?.listings.keys, ..._pending.keys});

  Future<void> _afterMutation(
    String parent, {
    bool parentAlreadyFresh = false,
  }) async {
    final paths = {
      parent,
      ...?_browser?.panes.map((pane) => pane.current.path),
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
  Future<void> _mutate(Future<void> Function() operation) {
    final result = _mutationTail.then((_) {
      if (isClosed) throw StateError('File browser is closed');
      return operation();
    });
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> renameEntry(String fullPath, String newName) =>
      _mutate(() => _renameEntry(fullPath, newName));

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
      _invalidate({parent}, subtrees: {fullPath, newPath});
      await _afterMutation(parent);
      rethrow;
    }
    _invalidate({parent}, subtrees: {fullPath, newPath});
    if (result == null) {
      _renameUncertain(parent, 'Rename was not acknowledged.');
    }
    if (!result.success) {
      await _afterMutation(parent);
      throw StateError(result.message);
    }
    final DirectoryListing? listing;
    try {
      listing = await midiManager.requestDirectoryListing(parent);
    } catch (error) {
      _renameUncertain(
        parent,
        'Rename acknowledged, but read-back failed: $error',
      );
    }
    final renamed = listing?.entries
        .where((e) => _clean(e.name) == newName)
        .firstOrNull;
    if (renamed == null ||
        listing!.entries.any(
          (e) => _clean(e.name) == p.posix.basename(fullPath),
        )) {
      _renameUncertain(
        parent,
        'Rename acknowledged, but the new directory entry could not be verified.',
      );
    }
    String rewrite(String path) => _below(path, fullPath)
        ? '$newPath${path.substring(fullPath.length)}'
        : path;
    await prefs.setStringList(
      _historyKey,
      (prefs.getStringList(_historyKey) ?? []).map(rewrite).toSet().toList(),
    );
    final last = prefs.getString(_lastPathKey);
    if (last != null) await prefs.setString(_lastPathKey, rewrite(last));
    final browser = _browser;
    if (browser == null || isClosed) return;
    _emit(
      browser.copyWith(
        panes: [
          for (final pane in browser.panes)
            pane.copyWith(
              stack: [
                for (final frame in pane.stack)
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
        ],
      ),
    );
    _publishListing(parent, listing);
    await _afterMutation(parent, parentAlreadyFresh: true);
  }

  Never _renameUncertain(String parent, String reason) {
    final message =
        '$reason The file may have changed. Refresh before retrying.';
    final browser = _browser;
    if (browser != null && !isClosed) {
      // Fail closed for this directory without discarding other pane stacks.
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
      _mutate(() => _deleteEntry(fullPath));

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
      _emit(
        browser.copyWith(
          panes: [
            for (final pane in browser.panes)
              _pruneDeleted(pane, fullPath, parent),
          ],
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

  BrowserPane _pruneDeleted(BrowserPane pane, String deleted, String parent) {
    final index = pane.stack.indexWhere((frame) => _below(frame.path, deleted));
    if (index < 0) return pane;
    return pane.copyWith(
      stack: index == 0 ? [_frame(parent)] : pane.stack.sublist(0, index),
    );
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
      });

  Future<Uint8List?> downloadFile(String fullPath) => _retryRead(() async {
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
      } catch (_) {
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
