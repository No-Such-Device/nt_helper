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

/// One root-to-current hierarchy. The three desktop columns are a sliding
/// viewport over these frames, never independent navigation roots/histories.
@freezed
abstract class BrowserSnapshot with _$BrowserSnapshot {
  const BrowserSnapshot._();
  const factory BrowserSnapshot({
    required List<BrowserFrame> stack,
    @Default(0) int activeDepth,
    @Default(false) bool sortByDate,
    @Default({}) Map<String, List<DirectoryEntry>> listings,
    @Default({}) Set<String> refreshing,
    @Default({}) Map<String, String> errors,
    @Default({}) Set<String> busyPaths,
    String? warning,
  }) = _BrowserSnapshot;

  int get viewportStart => stack.length > 3 ? stack.length - 3 : 0;
  bool get canGoBack => stack.length > 1;
  BrowserFrame get current => stack.last;
  BrowserFrame get focused => stack[activeDepth.clamp(0, stack.length - 1)];
  PanelPosition get activePane =>
      PanelPosition.values[(activeDepth - viewportStart).clamp(0, 2)];
  int? depth(PanelPosition position) {
    final index = viewportStart + position.index;
    return index < stack.length ? index : null;
  }

  BrowserFrame? frame(PanelPosition position) {
    final index = depth(position);
    return index == null ? null : stack[index];
  }

  String? path(PanelPosition position) => frame(position)?.path;
  List<DirectoryEntry> entriesAt(int depth) =>
      listings[stack[depth].path] ?? const [];
  List<DirectoryEntry> items(PanelPosition position) {
    final index = depth(position);
    return index == null ? const [] : entriesAt(index);
  }

  DirectoryEntry? selectedAt(int depth) => entriesAt(
    depth,
  ).where((e) => e.name == stack[depth].selectedName).firstOrNull;
  DirectoryEntry? selection(PanelPosition position) {
    final index = depth(position);
    return index == null ? null : selectedAt(index);
  }
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
  // or mobile drill-down copy that can diverge from the shared hierarchy.
  BrowserSnapshot? get view => mapOrNull(loaded: (s) => s.browser);
  String get currentPath => view?.current.path ?? '/';
  bool get sortByDate => view?.sortByDate ?? false;
  List<String> get navigationHistory =>
      view?.stack.take(view!.stack.length - 1).map((f) => f.path).toList() ??
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
  String? get drillPath => view?.current.path;
  List<String>? get breadcrumbs =>
      drillPath?.split('/').where((s) => s.isNotEmpty).toList();
  List<DirectoryEntry>? get currentDrillItems =>
      view?.entriesAt(view!.stack.length - 1);
  DirectoryEntry? get selectedDrillItem =>
      view?.selectedAt(view!.stack.length - 1);
}
