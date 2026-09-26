import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/plugin_metadata_extractor.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';

part 'gallery_cubit.freezed.dart';
part 'gallery_state.dart';

/// Pending install request stored for queue processing
class _PendingInstall {
  final GalleryPlugin plugin;
  final Function(
    String,
    Uint8List, {
    Function(double)? onProgress,
    String? galleryPluginId,
    String? galleryPluginVersion,
  })
  distingInstallPlugin;
  final SampleInstallCallback? distingInstallSample;
  final VoidCallback? onComplete;
  final Function(String)? onError;
  final void Function(PluginCleanupOutcome)? onCleanupOutcome;
  final List<CollectionPlugin>? selectedPlugins;

  _PendingInstall({
    required this.plugin,
    required this.distingInstallPlugin,
    this.distingInstallSample,
    this.onComplete,
    this.onError,
    this.onCleanupOutcome,
    this.selectedPlugins,
  });
}

class GalleryCubit extends Cubit<GalleryState> {
  final GalleryService _galleryService;

  /// Cache of downloaded collection archives (kept off freezed state — too large)
  final Map<String, List<int>> _archiveCache = {};

  /// Queue of pending installs (processed one at a time)
  final List<_PendingInstall> _installQueue = [];
  bool _isProcessingQueue = false;

  GalleryCubit(this._galleryService) : super(const GalleryState.initial());

  @override
  Future<void> close() {
    _archiveCache.clear();
    _installQueue.clear();
    return super.close();
  }

  Future<void> loadGallery({
    bool forceRefresh = false,
    Set<String>? devicePluginGuids,
    Map<String, String>? devicePluginPaths,
  }) async {
    final currentState = state;

    if (currentState is GalleryLoaded) {
      emit(currentState.copyWith(isRefreshing: true));
      _refreshInBackground(
        devicePluginGuids: devicePluginGuids,
        devicePluginPaths: devicePluginPaths,
        forceRefresh: forceRefresh,
      );
      return;
    }

    // Try cached data first
    if (currentState is! GalleryLoaded) {
      try {
        final cachedGallery = await _galleryService.fetchGallery(
          forceRefresh: false,
        );

        final updateInfo = await _galleryService.compareWithInstalledVersions(
          cachedGallery,
          devicePluginGuids: devicePluginGuids,
          devicePluginPaths: devicePluginPaths,
        );

        emit(
          GalleryState.loaded(
            gallery: cachedGallery,
            filteredPlugins: cachedGallery.plugins,
            selectedCategory: null,
            selectedType: null,
            showFeaturedOnly: false,
            showVerifiedOnly: false,
            searchQuery: '',
            updateInfo: updateInfo,
            isRefreshing: true,
          ),
        );

        _refreshInBackground(
          devicePluginGuids: devicePluginGuids,
          devicePluginPaths: devicePluginPaths,
          forceRefresh: true,
        );
        return;
      } catch (_) {
        // No cached data, fall through
      }
    }

    emit(const GalleryState.loading());

    try {
      final gallery = await _galleryService.fetchGallery(
        forceRefresh: forceRefresh,
      );

      final updateInfo = await _galleryService.compareWithInstalledVersions(
        gallery,
        devicePluginGuids: devicePluginGuids,
        devicePluginPaths: devicePluginPaths,
      );

      emit(
        GalleryState.loaded(
          gallery: gallery,
          filteredPlugins: gallery.plugins,
          selectedCategory: null,
          selectedType: null,
          showFeaturedOnly: false,
          showVerifiedOnly: false,
          searchQuery: '',
          updateInfo: updateInfo,
        ),
      );
    } catch (e) {
      emit(GalleryState.error(e.toString()));
    }
  }

  Future<void> _refreshInBackground({
    Set<String>? devicePluginGuids,
    Map<String, String>? devicePluginPaths,
    bool forceRefresh = true,
  }) async {
    try {
      final gallery = await _galleryService.fetchGallery(
        forceRefresh: forceRefresh,
      );

      final updateInfo = await _galleryService.compareWithInstalledVersions(
        gallery,
        devicePluginGuids: devicePluginGuids,
        devicePluginPaths: devicePluginPaths,
      );

      final currentState = state;
      if (currentState is GalleryLoaded) {
        final filteredPlugins = _galleryService.searchPlugins(
          gallery,
          query: currentState.searchQuery,
          category: currentState.selectedCategory,
          type: currentState.selectedType,
          featured: currentState.showFeaturedOnly ? true : null,
          verified: currentState.showVerifiedOnly ? true : null,
        );

        emit(
          currentState.copyWith(
            gallery: gallery,
            filteredPlugins: filteredPlugins,
            updateInfo: updateInfo,
            isRefreshing: false,
          ),
        );
      } else {
        emit(
          GalleryState.loaded(
            gallery: gallery,
            filteredPlugins: gallery.plugins,
            selectedCategory: null,
            selectedType: null,
            showFeaturedOnly: false,
            showVerifiedOnly: false,
            searchQuery: '',
            updateInfo: updateInfo,
          ),
        );
      }
    } catch (e) {
      final currentState = state;
      if (currentState is GalleryLoaded) {
        emit(currentState.copyWith(isRefreshing: false));
      }
    }
  }

  void applyFilters({
    String? searchQuery,
    String? category,
    GalleryPluginType? type,
    bool? featured,
    bool? verified,
  }) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final newSearchQuery = searchQuery ?? currentState.searchQuery;
    final newCategory = category ?? currentState.selectedCategory;
    final newType = type ?? currentState.selectedType;
    final newFeatured = featured ?? currentState.showFeaturedOnly;
    final newVerified = verified ?? currentState.showVerifiedOnly;

    final filteredPlugins = _galleryService.searchPlugins(
      currentState.gallery,
      query: newSearchQuery,
      category: newCategory,
      type: newType,
      featured: newFeatured ? true : null,
      verified: newVerified ? true : null,
    );

    emit(
      currentState.copyWith(
        filteredPlugins: filteredPlugins,
        searchQuery: newSearchQuery,
        selectedCategory: newCategory,
        selectedType: newType,
        showFeaturedOnly: newFeatured,
        showVerifiedOnly: newVerified,
      ),
    );
  }

  void clearFilters() {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    emit(
      currentState.copyWith(
        filteredPlugins: currentState.gallery.plugins,
        searchQuery: '',
        selectedCategory: null,
        selectedType: null,
        showFeaturedOnly: false,
        showVerifiedOnly: false,
      ),
    );
  }

  /// Get a reference to the gallery service for direct access to download methods
  GalleryService get galleryService => _galleryService;

  // --- Direct Install Methods ---

  /// True if any plugin is currently being installed
  bool get isInstalling {
    final currentState = state;
    if (currentState is! GalleryLoaded) return false;

    return currentState.installStatuses.values.any(
      (s) =>
          s.phase == PluginInstallPhase.downloading ||
          s.phase == PluginInstallPhase.extracting ||
          s.phase == PluginInstallPhase.installing,
    );
  }

  /// Queue a single plugin for installation
  void installPlugin(
    GalleryPlugin plugin, {
    required Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin,
    SampleInstallCallback? distingInstallSample,
    VoidCallback? onComplete,
    Function(String error)? onError,
    void Function(PluginCleanupOutcome outcome)? onCleanupOutcome,
  }) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    _installQueue.add(
      _PendingInstall(
        plugin: plugin,
        distingInstallPlugin: distingInstallPlugin,
        distingInstallSample: distingInstallSample,
        onComplete: onComplete,
        onError: onError,
        onCleanupOutcome: onCleanupOutcome,
      ),
    );

    _updateInstallStatus(
      plugin.id,
      const PluginInstallStatus(phase: PluginInstallPhase.queued),
    );

    _processQueue();
  }

  /// Queue selected sub-plugins from a collection for installation
  void installCollectionPlugins(
    String pluginId,
    List<CollectionPlugin> selected, {
    required Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin,
    SampleInstallCallback? distingInstallSample,
    VoidCallback? onComplete,
    Function(String error)? onError,
    void Function(PluginCleanupOutcome outcome)? onCleanupOutcome,
  }) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final plugin = currentState.gallery.plugins.firstWhere(
      (p) => p.id == pluginId,
    );

    _installQueue.add(
      _PendingInstall(
        plugin: plugin,
        distingInstallPlugin: distingInstallPlugin,
        distingInstallSample: distingInstallSample,
        onComplete: onComplete,
        onError: onError,
        onCleanupOutcome: onCleanupOutcome,
        selectedPlugins: selected,
      ),
    );

    _updateInstallStatus(
      pluginId,
      const PluginInstallStatus(phase: PluginInstallPhase.queued),
    );

    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_installQueue.isNotEmpty) {
      final pending = _installQueue.removeAt(0);
      final pluginId = pending.plugin.id;

      _updateInstallStatus(
        pluginId,
        const PluginInstallStatus(phase: PluginInstallPhase.downloading),
      );

      try {
        final cachedBytes = _archiveCache[pluginId];

        await _galleryService.installPlugin(
          pending.plugin,
          distingInstallPlugin: pending.distingInstallPlugin,
          distingInstallSample: pending.distingInstallSample,
          cachedArchiveBytes: cachedBytes,
          selectedPlugins: pending.selectedPlugins,
          onCleanupOutcome: pending.onCleanupOutcome,
          onProgress: (phase, progress) {
            _updateInstallStatus(
              pluginId,
              PluginInstallStatus(phase: phase, progress: progress),
            );
          },
        );

        _updateInstallStatus(
          pluginId,
          const PluginInstallStatus(
            phase: PluginInstallPhase.completed,
            progress: 1.0,
          ),
        );
        pending.onComplete?.call();
      } catch (e) {
        _updateInstallStatus(
          pluginId,
          PluginInstallStatus(
            phase: PluginInstallPhase.failed,
            errorMessage: e.toString(),
          ),
        );
        pending.onError?.call(e.toString());
      }
    }

    _isProcessingQueue = false;
  }

  /// Expand a collection inline — download archive, extract metadata
  Future<void> expandCollection(GalleryPlugin plugin) async {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    // Mark as loading
    final expanded = Map<String, CollectionExpansion>.from(
      currentState.expandedCollections,
    );
    expanded[plugin.id] = const CollectionExpansion(
      plugins: [],
      isLoading: true,
    );
    emit(currentState.copyWith(expandedCollections: expanded));

    try {
      final archiveBytes = await _galleryService.downloadPluginArchive(
        plugin,
        'latest',
      );

      // Cache for later install
      _archiveCache[plugin.id] = archiveBytes;

      final availablePlugins =
          await PluginMetadataExtractor.extractPluginsFromArchive(
            archiveBytes,
            plugin,
          );

      // Select all installable plugins by default
      final pluginsWithSelection = availablePlugins
          .map(
            (p) => p.copyWith(
              selected: const [
                '.o',
                '.lua',
                '.3pot',
              ].contains('.${p.fileType}'),
            ),
          )
          .toList();

      final refreshedState = state;
      if (refreshedState is! GalleryLoaded) return;

      final refreshedExpanded = Map<String, CollectionExpansion>.from(
        refreshedState.expandedCollections,
      );
      refreshedExpanded[plugin.id] = CollectionExpansion(
        plugins: pluginsWithSelection,
      );
      emit(refreshedState.copyWith(expandedCollections: refreshedExpanded));
    } catch (e) {
      final refreshedState = state;
      if (refreshedState is! GalleryLoaded) return;

      final refreshedExpanded = Map<String, CollectionExpansion>.from(
        refreshedState.expandedCollections,
      );
      refreshedExpanded[plugin.id] = CollectionExpansion(
        plugins: [],
        error: e.toString(),
      );
      emit(refreshedState.copyWith(expandedCollections: refreshedExpanded));
    }
  }

  /// Collapse a collection and clear its archive cache
  void collapseCollection(String pluginId) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    _archiveCache.remove(pluginId);

    final expanded = Map<String, CollectionExpansion>.from(
      currentState.expandedCollections,
    );
    expanded.remove(pluginId);
    emit(currentState.copyWith(expandedCollections: expanded));
  }

  /// Toggle a single collection plugin checkbox
  void toggleCollectionPlugin(String pluginId, int index) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final expansion = currentState.expandedCollections[pluginId];
    if (expansion == null) return;

    final updatedPlugins = List<CollectionPlugin>.from(expansion.plugins);
    updatedPlugins[index] = updatedPlugins[index].copyWith(
      selected: !updatedPlugins[index].selected,
    );

    final expanded = Map<String, CollectionExpansion>.from(
      currentState.expandedCollections,
    );
    expanded[pluginId] = expansion.copyWith(plugins: updatedPlugins);
    emit(currentState.copyWith(expandedCollections: expanded));
  }

  /// Toggle all collection plugins selected/deselected
  void selectAllCollectionPlugins(String pluginId, bool selected) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final expansion = currentState.expandedCollections[pluginId];
    if (expansion == null) return;

    final updatedPlugins = expansion.plugins
        .map((p) => p.copyWith(selected: selected))
        .toList();

    final expanded = Map<String, CollectionExpansion>.from(
      currentState.expandedCollections,
    );
    expanded[pluginId] = expansion.copyWith(plugins: updatedPlugins);
    emit(currentState.copyWith(expandedCollections: expanded));
  }

  /// Clear a completed/failed install status
  void clearInstallStatus(String pluginId) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final statuses = Map<String, PluginInstallStatus>.from(
      currentState.installStatuses,
    );
    statuses.remove(pluginId);
    emit(currentState.copyWith(installStatuses: statuses));
  }

  void _updateInstallStatus(String pluginId, PluginInstallStatus status) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return;

    final statuses = Map<String, PluginInstallStatus>.from(
      currentState.installStatuses,
    );
    statuses[pluginId] = status;
    emit(currentState.copyWith(installStatuses: statuses));
  }

  // --- Update Management Methods ---

  Future<void> refreshUpdates({
    Set<String>? devicePluginGuids,
    Map<String, String>? devicePluginPaths,
  }) async {
    await loadGallery(
      forceRefresh: true,
      devicePluginGuids: devicePluginGuids,
      devicePluginPaths: devicePluginPaths,
    );
  }

  PluginUpdateInfo? getPluginUpdateInfo(String pluginId) {
    final currentState = state;
    if (currentState is! GalleryLoaded) return null;

    return currentState.updateInfo[pluginId];
  }

  bool get hasUpdatesAvailable {
    final currentState = state;
    if (currentState is! GalleryLoaded) return false;

    return currentState.updateInfo.values.any((info) => info.updateAvailable);
  }

  int get updateCount {
    final currentState = state;
    if (currentState is! GalleryLoaded) return 0;

    return currentState.updateInfo.values
        .where((info) => info.updateAvailable)
        .length;
  }
}
