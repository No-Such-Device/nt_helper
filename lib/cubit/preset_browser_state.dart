import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';

part 'preset_browser_state.freezed.dart';

enum PanelPosition { left, center, right }

enum SortMode { alphabetic, date }

@freezed
abstract class BrowserFrame with _$BrowserFrame {
  const factory BrowserFrame({required String path, String? selectedName}) =
      _BrowserFrame;
}

@freezed
abstract class BrowserPane with _$BrowserPane {
  const BrowserPane._();
  const factory BrowserPane({required List<BrowserFrame> stack}) = _BrowserPane;
  BrowserFrame get current => stack.last;
  bool get canGoBack => stack.length > 1;
}

/// Canonical browser state. Frames own navigation/selection; listings are shared
/// by path. Mobile renders the active desktop pane, never a second selection.
@freezed
abstract class BrowserSnapshot with _$BrowserSnapshot {
  const BrowserSnapshot._();
  const factory BrowserSnapshot({
    required List<BrowserPane> panes,
    @Default(PanelPosition.left) PanelPosition activePane,
    @Default(false) bool sortByDate,
    @Default({}) Map<String, List<DirectoryEntry>> listings,
    @Default({}) Set<String> refreshing,
    @Default({}) Map<String, String> errors,
  }) = _BrowserSnapshot;

  BrowserPane pane(PanelPosition position) => panes[position.index];
  BrowserPane get active => pane(activePane);
  List<DirectoryEntry> items(PanelPosition position) =>
      listings[pane(position).current.path] ?? const [];
  DirectoryEntry? selection(PanelPosition position) => items(
    position,
  ).where((e) => e.name == pane(position).current.selectedName).firstOrNull;
}

@freezed
sealed class PresetBrowserState with _$PresetBrowserState {
  const PresetBrowserState._();
  const factory PresetBrowserState.initial() = _Initial;
  const factory PresetBrowserState.loading() = _Loading;
  const factory PresetBrowserState.loaded({required BrowserSnapshot browser}) =
      _Loaded;
  const factory PresetBrowserState.error({
    required String message,
    String? lastPath,
  }) = _Error;

  // Read-only projections for renderers. There is no stored global path/history
  // or mobile drill-down copy that can diverge from the pane stacks.
  BrowserSnapshot? get view => mapOrNull(loaded: (s) => s.browser);
  String get currentPath => view?.active.current.path ?? '/';
  bool get sortByDate => view?.sortByDate ?? false;
  List<String> get navigationHistory =>
      view?.active.stack
          .map((f) => f.path)
          .toList()
          .sublist(0, view!.active.stack.length - 1) ??
      const [];
  List<DirectoryEntry> get leftPanelItems =>
      view?.items(PanelPosition.left) ?? const [];
  List<DirectoryEntry> get centerPanelItems =>
      view?.items(PanelPosition.center) ?? const [];
  List<DirectoryEntry> get rightPanelItems =>
      view?.items(PanelPosition.right) ?? const [];
  DirectoryEntry? get selectedLeftItem => view?.selection(PanelPosition.left);
  DirectoryEntry? get selectedCenterItem =>
      view?.selection(PanelPosition.center);
  DirectoryEntry? get selectedRightItem => view?.selection(PanelPosition.right);
  Map<String, List<DirectoryEntry>>? get directoryCache => view?.listings;
  String? get drillPath => view?.active.current.path;
  List<String>? get breadcrumbs =>
      drillPath?.split('/').where((s) => s.isNotEmpty).toList();
  List<DirectoryEntry>? get currentDrillItems => view?.items(view!.activePane);
  DirectoryEntry? get selectedDrillItem => view?.selection(view!.activePane);
}
