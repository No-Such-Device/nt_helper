import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';
import 'package:nt_helper/ui/gallery/gallery_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/collection_expansion_panel.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/linkified_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nt_helper/utils/responsive.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/ui/widgets/plugin_cleanup_notice.dart';

bool _isDevicePluginAlgorithm(AlgorithmInfo algorithm) {
  if (algorithm.isPlugin) return true;
  if (algorithm.filename != null && algorithm.filename!.isNotEmpty) return true;
  return algorithm.guid != algorithm.guid.toLowerCase();
}

Set<String>? _getDevicePluginGuidsFromState(DistingState state) {
  if (state is! DistingStateSynchronized || state.offline || state.demo) {
    return null;
  }
  if (state.algorithms.isEmpty) return null;

  return state.algorithms
      .where(_isDevicePluginAlgorithm)
      .map((algorithm) => algorithm.guid)
      .where((guid) => guid.isNotEmpty)
      .toSet();
}

Map<String, String>? _getDevicePluginPathsFromState(DistingState state) {
  if (state is! DistingStateSynchronized || state.offline || state.demo) {
    return null;
  }
  if (state.algorithms.isEmpty) return null;

  final paths = <String, String>{};
  for (final algorithm in state.algorithms) {
    if (!_isDevicePluginAlgorithm(algorithm)) continue;
    final guid = algorithm.guid;
    final filename = algorithm.filename;
    if (guid.isNotEmpty && filename != null && filename.isNotEmpty) {
      paths[guid] = filename;
    }
  }
  return paths;
}

/// Unified Plugin Manager screen — single page with no tabs
class PluginGalleryScreen extends StatelessWidget {
  final DistingCubit distingCubit;
  final AppDatabase database;

  const PluginGalleryScreen({
    super.key,
    required this.distingCubit,
    required this.database,
  });

  @override
  Widget build(BuildContext context) {
    final galleryService = GalleryService(
      settingsService: SettingsService(),
      database: database,
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: distingCubit),
        BlocProvider(
          create: (context) {
            final devicePluginGuids = _getDevicePluginGuidsFromState(
              distingCubit.state,
            );
            final devicePluginPaths = _getDevicePluginPathsFromState(
              distingCubit.state,
            );
            return GalleryCubit(galleryService)..loadGallery(
              devicePluginGuids: devicePluginGuids,
              devicePluginPaths: devicePluginPaths,
            );
          },
        ),
      ],
      child: _PluginGalleryView(
        distingCubit: distingCubit,
        database: database,
        galleryService: galleryService,
      ),
    );
  }
}

class _PluginGalleryView extends StatefulWidget {
  final DistingCubit distingCubit;
  final AppDatabase database;
  final GalleryService galleryService;

  const _PluginGalleryView({
    required this.distingCubit,
    required this.database,
    required this.galleryService,
  });

  @override
  State<_PluginGalleryView> createState() => _PluginGalleryViewState();
}

class _PluginGalleryViewState extends State<_PluginGalleryView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Drag and drop state
  bool _isDragOver = false;
  bool _isInstallingFile = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      context.read<GalleryCubit>().applyFilters(
        searchQuery: _searchController.text,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    widget.galleryService.dispose();
    super.dispose();
  }

  Set<String>? _getDevicePluginGuids() {
    return _getDevicePluginGuidsFromState(widget.distingCubit.state);
  }

  Map<String, String>? _getDevicePluginPaths() {
    return _getDevicePluginPathsFromState(widget.distingCubit.state);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GalleryCubit, GalleryState>(
      builder: (context, state) {
        Widget content = Scaffold(
          appBar: _buildAppBar(state),
          body: _buildBody(state),
        );

        // Add drag and drop on desktop
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.linux)) {
          return DropTarget(
            onDragDone: _handleDragDone,
            onDragEntered: _handleDragEntered,
            onDragExited: _handleDragExited,
            child: Stack(
              children: [
                content,
                if (_isDragOver) _buildDragOverlay(),
                if (_isInstallingFile) _buildInstallOverlay(),
              ],
            ),
          );
        }

        return content;
      },
    );
  }

  PreferredSizeWidget _buildAppBar(GalleryState state) {
    final isRefreshing =
        state is GalleryLoading ||
        (state is GalleryLoaded && state.isRefreshing);

    return AppBar(
      title: const Text('Plugin Manager'),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      actions: [
        // Backup
        if (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
          IconButton(
            onPressed: _backupPlugins,
            icon: const Icon(Icons.backup, semanticLabel: 'Backup Plugins'),
            tooltip: 'Backup Plugins',
          ),
        // Install from file
        IconButton(
          onPressed: _installFromFile,
          icon: const Icon(
            Icons.upload_file,
            semanticLabel: 'Install from File',
          ),
          tooltip: 'Install from File',
        ),
        // Reboot
        IconButton(
          onPressed: _confirmReboot,
          icon: const Icon(Icons.restart_alt, semanticLabel: 'Reboot Device'),
          tooltip: 'Reboot Device',
        ),
        // Settings
        IconButton(
          icon: const Icon(Icons.settings, semanticLabel: 'Settings'),
          onPressed: () {
            IDistingMidiManager? midiManager;
            List<AlgorithmInfo>? algorithms;
            final state = widget.distingCubit.state;
            if (state is DistingStateSynchronized && !state.offline) {
              midiManager = widget.distingCubit.requireDisting();
              algorithms = state.algorithms;
            }
            context.showSettingsDialog(
              midiManager: midiManager,
              algorithms: algorithms,
              ccNotificationDiagnostics:
                  widget.distingCubit.ccNotificationDiagnostics,
            );
          },
          tooltip: 'Settings',
        ),
        // Refresh
        IconButton(
          icon: isRefreshing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                )
              : const Icon(Icons.sync, semanticLabel: 'Refresh Gallery'),
          onPressed: isRefreshing
              ? null
              : () => context.read<GalleryCubit>().refreshUpdates(
                  devicePluginGuids: _getDevicePluginGuids(),
                  devicePluginPaths: _getDevicePluginPaths(),
                ),
          tooltip: 'Refresh Gallery',
        ),
      ],
    );
  }

  Widget _buildBody(GalleryState state) {
    if (state is GalleryInitial || state is GalleryLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading gallery...'),
          ],
        ),
      );
    }

    if (state is GalleryError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load gallery',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              state.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.read<GalleryCubit>().loadGallery(
                forceRefresh: true,
                devicePluginGuids: _getDevicePluginGuids(),
                devicePluginPaths: _getDevicePluginPaths(),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state is! GalleryLoaded) return const SizedBox.shrink();

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: _buildSearchAndFilters(state),
          ),
          Expanded(
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: _buildPluginView(state),
            ),
          ),
        ],
      ),
    );
  }

  // --- Search & Filters ---

  Widget _buildSearchAndFilters(GalleryLoaded state) {
    final isMobile = Responsive.isMobile(context);
    final padding = Responsive.getScreenPadding(context);
    final filterSpacing = Responsive.getFilterSpacing(context);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          if (isMobile) ...[
            DigitShortcutBlocker(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search plugins...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            semanticLabel: 'Clear search',
                          ),
                          onPressed: () {
                            _searchController.clear();
                            context.read<GalleryCubit>().clearFilters();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            SizedBox(height: filterSpacing),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryFilter(state),
                  SizedBox(width: filterSpacing),
                  _buildTypeFilter(state),
                  SizedBox(width: filterSpacing),
                  _buildFeaturedFilter(state),
                  if (state.selectedCategory != null ||
                      state.selectedType != null ||
                      state.showFeaturedOnly ||
                      _searchController.text.isNotEmpty) ...[
                    SizedBox(width: filterSpacing),
                    _buildClearFilter(),
                  ],
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: DigitShortcutBlocker(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search plugins...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  semanticLabel: 'Clear search',
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  context.read<GalleryCubit>().clearFilters();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildCategoryFilter(state),
                const SizedBox(width: 8),
                _buildTypeFilter(state),
                const SizedBox(width: 8),
                _buildFeaturedFilter(state),
                const SizedBox(width: 8),
                if (state.selectedCategory != null ||
                    state.selectedType != null ||
                    state.showFeaturedOnly ||
                    _searchController.text.isNotEmpty)
                  _buildClearFilter(),
              ],
            ),
          ],
          SizedBox(height: isMobile ? filterSpacing : 12),
          Row(
            children: [
              Text(
                '${state.filteredPlugins.length} plugin${state.filteredPlugins.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter(GalleryLoaded state) {
    if (state.gallery.categories.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String?>(
      child: Semantics(
        label: 'Category filter: ${state.selectedCategory ?? "All"}',
        hint: 'Double-tap to change category',
        button: true,
        excludeSemantics: true,
        child: Chip(
          avatar: Icon(
            Icons.category,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          label: Text(state.selectedCategory ?? 'Category'),
          deleteIcon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          onDeleted: () {},
        ),
      ),
      onSelected: (value) {
        context.read<GalleryCubit>().applyFilters(category: value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String?>(
          value: null,
          child: Text('All Categories'),
        ),
        ...(state.gallery.categories).map(
          (cat) => PopupMenuItem<String>(
            value: cat.id,
            child: Row(
              children: [
                if (cat.icon != null) ...[
                  ExcludeSemantics(
                    child: Icon(_getIconData(cat.icon!), size: 16),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(cat.name),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilter(GalleryLoaded state) {
    return PopupMenuButton<GalleryPluginType?>(
      child: Semantics(
        label: 'Type filter: ${state.selectedType?.displayName ?? "All"}',
        hint: 'Double-tap to change type',
        button: true,
        excludeSemantics: true,
        child: Chip(
          avatar: Icon(
            Icons.extension,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          label: Text(state.selectedType?.displayName ?? 'Type'),
          deleteIcon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          onDeleted: () {},
        ),
      ),
      onSelected: (value) {
        context.read<GalleryCubit>().applyFilters(type: value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem<GalleryPluginType?>(
          value: null,
          child: Text('All Types'),
        ),
        ...GalleryPluginType.values.map(
          (type) => PopupMenuItem<GalleryPluginType>(
            value: type,
            child: Text(type.displayName),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedFilter(GalleryLoaded state) {
    return FilterChip(
      avatar: Icon(
        Icons.star,
        size: 18,
        color: state.showFeaturedOnly
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      label: const Text('Featured'),
      selected: state.showFeaturedOnly,
      selectedColor: Theme.of(context).colorScheme.primary,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: state.showFeaturedOnly
            ? Theme.of(context).colorScheme.onPrimary
            : null,
      ),
      onSelected: (selected) {
        context.read<GalleryCubit>().applyFilters(featured: selected);
      },
    );
  }

  Widget _buildClearFilter() {
    return ActionChip(
      avatar: Icon(
        Icons.clear,
        size: 18,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      label: const Text('Clear'),
      onPressed: () {
        _searchController.clear();
        context.read<GalleryCubit>().clearFilters();
      },
    );
  }

  // --- Plugin Views ---

  Widget _buildPluginView(GalleryLoaded state) {
    final filteredPlugins = state.filteredPlugins;
    if (filteredPlugins.isEmpty) return _buildEmptyPluginState();

    // Separate into sections
    final pluginsWithUpdates = filteredPlugins
        .where((p) => state.updateInfo[p.id]?.hasUpdate ?? false)
        .toList();

    final installedPlugins = filteredPlugins
        .where(
          (p) =>
              state.updateInfo[p.id] != null &&
              !(state.updateInfo[p.id]?.hasUpdate ?? false),
        )
        .toList();

    final availablePlugins = filteredPlugins
        .where((p) => state.updateInfo[p.id] == null)
        .toList();

    return _buildListView(
      state,
      pluginsWithUpdates,
      installedPlugins,
      availablePlugins,
    );
  }

  Widget _buildEmptyPluginState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No plugins found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, GalleryLoaded state) {
    final showUpdateAll = title == 'Updates Available' && count > 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$title ($count)',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (showUpdateAll)
          FilledButton.tonalIcon(
            onPressed:
                state.installStatuses.values.any(
                  (s) =>
                      s.phase != PluginInstallPhase.completed &&
                      s.phase != PluginInstallPhase.failed,
                )
                ? null
                : () => _updateAllPlugins(state),
            icon: const Icon(Icons.system_update, size: 18),
            label: const Text('Update All'),
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.warning.color,
              foregroundColor: context.appColors.warning.onColor,
            ),
          ),
      ],
    );
  }

  Future<void> _updateAllPlugins(GalleryLoaded state) async {
    final pluginsToUpdate = state.filteredPlugins
        .where((plugin) => state.updateInfo[plugin.id]?.hasUpdate ?? false)
        .toList();

    if (pluginsToUpdate.isEmpty) return;

    for (final plugin in pluginsToUpdate) {
      _doInstallPlugin(plugin);
    }
  }

  Widget _buildListView(
    GalleryLoaded state,
    List<GalleryPlugin> updates,
    List<GalleryPlugin> installed,
    List<GalleryPlugin> available,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (updates.isNotEmpty) ...[
          _buildSectionHeader('Updates Available', updates.length, state),
          const SizedBox(height: 12),
          ...updates.map((p) => _buildPluginListTile(p, state)),
          const SizedBox(height: 24),
        ],
        if (installed.isNotEmpty) ...[
          _buildSectionHeader('Installed', installed.length, state),
          const SizedBox(height: 12),
          ...installed.map((p) => _buildPluginListTile(p, state)),
          const SizedBox(height: 24),
        ],
        if (available.isNotEmpty) ...[
          _buildSectionHeader('Available', available.length, state),
          const SizedBox(height: 12),
          ...available.map((p) => _buildPluginListTile(p, state)),
        ],
      ],
    );
  }

  // --- Plugin List Tile ---

  Widget _buildPluginListTile(GalleryPlugin plugin, GalleryLoaded state) {
    final author = plugin.getAuthor(state.gallery);
    final category = plugin.getCategory(state.gallery);
    final updateInfo = state.updateInfo[plugin.id];
    final hasUpdate = updateInfo?.hasUpdate ?? false;
    final isInstalled = updateInfo != null;
    final installStatus = state.installStatuses[plugin.id];
    final galleryCubit = context.read<GalleryCubit>();

    return Semantics(
      label:
          '${plugin.name}, ${plugin.type.displayName}${hasUpdate
              ? ', update available'
              : isInstalled
              ? ', installed'
              : ''}',
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: (plugin.featured || plugin.isCollection)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plugin.featured)
                            Icon(
                              Icons.star,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          if (plugin.isCollection)
                            Padding(
                              padding: EdgeInsets.only(
                                left: plugin.featured ? 4 : 0,
                              ),
                              child: Icon(
                                Icons.folder_copy,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                            ),
                        ],
                      )
                    : null,
                title: Text(
                  plugin.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (author != null) ...[
                          Icon(
                            Icons.person,
                            size: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            author.name,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            plugin.type.displayName,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondary,
                                ),
                          ),
                        ),
                        if (category != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              category.name,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                        if (updateInfo != null) ...[
                          const SizedBox(width: 6),
                          _buildVersionBadge(updateInfo),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinkifiedText(
                      text: plugin.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 160,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: installStatus != null
                            ? Center(
                                child: _buildInstallProgress(
                                  plugin.id,
                                  installStatus,
                                ),
                              )
                            : Row(
                                key: const ValueKey('trailing_actions'),
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (plugin.formattedLatestVersion.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        plugin.formattedLatestVersion,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  if (plugin.hasReadmeDocumentation)
                                    IconButton(
                                      icon: Icon(
                                        Icons.description_outlined,
                                        semanticLabel: 'View Documentation',
                                        size: 20,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                      tooltip: 'View Documentation',
                                      onPressed: () =>
                                          _showReadmeDialog(plugin),
                                    ),
                                  const SizedBox(width: 4),
                                  _buildListActionButton(
                                    plugin,
                                    hasUpdate,
                                    isInstalled,
                                    galleryCubit,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListActionButton(
    GalleryPlugin plugin,
    bool hasUpdate,
    bool isInstalled,
    GalleryCubit galleryCubit,
  ) {
    if (plugin.isCollection) {
      return IconButton(
        icon: const Icon(Icons.folder_open, semanticLabel: 'Show contents'),
        onPressed: () => _showCollectionDialog(plugin, galleryCubit),
        tooltip: 'Show contents',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    if (hasUpdate) {
      return IconButton(
        icon: const Icon(Icons.update, semanticLabel: 'Update'),
        onPressed: () => _doInstallPlugin(plugin),
        tooltip: 'Update',
        color: context.appColors.warning.color,
      );
    }

    if (isInstalled) {
      return IconButton(
        icon: const Icon(Icons.refresh, semanticLabel: 'Reinstall'),
        onPressed: () => _doInstallPlugin(plugin),
        tooltip: 'Reinstall',
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return IconButton(
      icon: const Icon(Icons.download, semanticLabel: 'Install'),
      onPressed: () => _doInstallPlugin(plugin),
      tooltip: 'Install',
      color: Theme.of(context).colorScheme.primary,
    );
  }

  // --- Install Progress ---

  Widget _buildInstallProgress(String pluginId, PluginInstallStatus status) {
    if (status.phase == PluginInstallPhase.completed) {
      return _CompletionRow(
        key: ValueKey('complete_$pluginId'),
        onAutoDismiss: () =>
            context.read<GalleryCubit>().clearInstallStatus(pluginId),
      );
    }

    if (status.phase == PluginInstallPhase.failed) {
      return _FailureRow(
        key: ValueKey('failed_$pluginId'),
        errorMessage: status.errorMessage,
        onAutoDismiss: () =>
            context.read<GalleryCubit>().clearInstallStatus(pluginId),
      );
    }

    if (status.phase == PluginInstallPhase.queued) {
      return Row(
        key: ValueKey('queued_$pluginId'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Queued',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    // Active install
    final phaseText = switch (status.phase) {
      PluginInstallPhase.downloading => 'Downloading...',
      PluginInstallPhase.extracting => 'Extracting...',
      PluginInstallPhase.installing => 'Installing...',
      _ => '',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: status.progress > 0 ? status.progress : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(phaseText),
            if (status.progress > 0) ...[
              const SizedBox(width: 8),
              Text('${(status.progress * 100).toInt()}%'),
            ],
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: status.progress > 0 ? status.progress : null,
        ),
      ],
    );
  }

  Widget _buildVersionBadge(PluginUpdateInfo info) {
    final isUntracked =
        info.installedVersion == 'unknown' ||
        info.installedVersion == 'user-installed' ||
        info.installedVersion == 'device-detected';

    final label = isUntracked
        ? 'Installed (untracked)'
        : 'Installed ${GalleryService.extractSemver(info.installedVersion)}';

    final color = info.hasUpdate
        ? context.appColors.warning.color
        : Theme.of(context).colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  // --- Install Actions ---

  void _doInstallPlugin(GalleryPlugin plugin) {
    final galleryCubit = context.read<GalleryCubit>();
    final distingCubit = context.read<DistingCubit>();

    galleryCubit.installPlugin(
      plugin,
      distingInstallPlugin:
          (
            fileName,
            fileData, {
            onProgress,
            galleryPluginId,
            galleryPluginVersion,
          }) => distingCubit.installPlugin(
            fileName,
            fileData,
            onProgress: onProgress,
            galleryPluginId: galleryPluginId,
            galleryPluginVersion: galleryPluginVersion,
          ),
      distingInstallSample: (targetPath, fileData, {onProgress}) async {
        return await distingCubit.installSampleFile(
          targetPath,
          fileData,
          onProgress: onProgress,
        );
      },
      onComplete: () {
        if (mounted) {
          galleryCubit.refreshUpdates(
            devicePluginGuids: _getDevicePluginGuids(),
            devicePluginPaths: _getDevicePluginPaths(),
          );
        }
      },
      onCleanupOutcome: _showCleanupOutcome,
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installation failed: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
    );
  }

  void _doInstallCollectionPlugins(
    String pluginId,
    List<CollectionPlugin> selected,
  ) {
    final galleryCubit = context.read<GalleryCubit>();
    final distingCubit = context.read<DistingCubit>();

    galleryCubit.installCollectionPlugins(
      pluginId,
      selected,
      distingInstallPlugin:
          (
            fileName,
            fileData, {
            onProgress,
            galleryPluginId,
            galleryPluginVersion,
          }) => distingCubit.installPlugin(
            fileName,
            fileData,
            onProgress: onProgress,
            galleryPluginId: galleryPluginId,
            galleryPluginVersion: galleryPluginVersion,
          ),
      distingInstallSample: (targetPath, fileData, {onProgress}) async {
        return await distingCubit.installSampleFile(
          targetPath,
          fileData,
          onProgress: onProgress,
        );
      },
      onComplete: () {
        if (mounted) {
          galleryCubit.refreshUpdates(
            devicePluginGuids: _getDevicePluginGuids(),
            devicePluginPaths: _getDevicePluginPaths(),
          );
        }
      },
      onCleanupOutcome: _showCleanupOutcome,
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Installation failed: $error'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
    );
  }

  void _showCleanupOutcome(PluginCleanupOutcome outcome) {
    if (!mounted) return;
    showPluginCleanupNotice(
      ScaffoldMessenger.of(context),
      outcome,
      Theme.of(context).colorScheme,
    );
  }

  // --- AppBar Actions ---

  Future<void> _installFromFile() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux)) {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['lua', '3pot', 'o'],
        );

        if (file != null) {
          final fileName = file.name;

          final fileBytes = await file.readAsBytes();

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Installing Plugin'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Installing "$fileName"...'),
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    const Text('This may take a few moments'),
                  ],
                ),
              ),
            );
          }

          try {
            final cleanupOutcome = await widget.distingCubit.installPlugin(
              fileName,
              fileBytes,
              onProgress: (progress) {},
            );

            if (mounted) {
              Navigator.of(context).pop();
              _showCleanupOutcome(cleanupOutcome);
              context.read<GalleryCubit>().refreshUpdates(
                devicePluginGuids: _getDevicePluginGuids(),
                devicePluginPaths: _getDevicePluginPaths(),
              );
            }
          } catch (e) {
            if (mounted) {
              Navigator.of(context).pop();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Failed to install "$fileName": $e'),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
            }
          }
        }
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'File installation is only available on desktop platforms',
            ),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error selecting file: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  Future<void> _backupPlugins() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    try {
      final backupChoice = await _showBackupOptionsDialog();
      if (backupChoice == null) return;

      String? directoryPath;
      if (backupChoice == 'existing') {
        directoryPath = await FilePicker.getDirectoryPath();
      } else if (backupChoice == 'new') {
        directoryPath = await _createNewBackupDirectory();
      }

      if (directoryPath == null) return;

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _BackupProgressDialog(
            directoryPath: directoryPath!,
            distingCubit: widget.distingCubit,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error setting up backup: $e'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
    }
  }

  Future<String?> _showBackupOptionsDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Backup Location'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('How would you like to organize your backup?'),
            SizedBox(height: 16),
            Text(
              'The backup will maintain the original directory structure:\n'
              '\u2022 programs/lua/\n'
              '\u2022 programs/three_pot/\n'
              '\u2022 programs/plug-ins/',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop('existing'),
            child: const Text('Choose Existing Folder'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('new'),
            child: const Text('Create New Folder'),
          ),
        ],
      ),
    );
  }

  Future<String?> _createNewBackupDirectory() async {
    final parentPath = await FilePicker.getDirectoryPath();
    if (parentPath == null) return null;

    final folderName = await _showCreateFolderDialog();
    if (folderName == null || folderName.trim().isEmpty) return null;

    try {
      final newDirPath = '$parentPath/$folderName';
      final newDir = Directory(newDirPath);

      if (await newDir.exists()) {
        if (!mounted) return null;
        final useExisting = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Directory Already Exists'),
            content: Text(
              'The folder "$folderName" already exists. Use it for the backup?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use Existing'),
              ),
            ],
          ),
        );
        if (useExisting != true) return null;
      } else {
        await newDir.create(recursive: true);
      }

      return newDirPath;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating directory: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return null;
    }
  }

  Future<String?> _showCreateFolderDialog() async {
    final controller = TextEditingController();
    final now = DateTime.now();
    controller.text =
        'Disting_NT_Backup_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Backup Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a name for the new backup folder:'),
            const SizedBox(height: 16),
            DigitShortcutBlocker(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Folder Name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReboot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reboot Disting NT?'),
        content: const Text(
          'This will reboot the Disting NT device. '
          'This is commonly needed after installing plugins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reboot'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.distingCubit.reboot();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Reboot command sent')));
          Navigator.of(context).pop(); // Return to main screen
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reboot failed: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  // --- Collection Dialog ---

  void _showCollectionDialog(GalleryPlugin plugin, GalleryCubit galleryCubit) {
    // Trigger the expansion (download + analyze archive)
    galleryCubit.expandCollection(plugin);

    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: galleryCubit,
        child: BlocBuilder<GalleryCubit, GalleryState>(
          builder: (context, state) {
            final expansion = (state is GalleryLoaded)
                ? state.expandedCollections[plugin.id]
                : null;

            final screenHeight = MediaQuery.of(context).size.height;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 480,
                  maxHeight: screenHeight * 0.5,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title bar with close button
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.folder_open, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plugin.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 20,
                              icon: const Icon(
                                Icons.close,
                                semanticLabel: 'Close',
                              ),
                              onPressed: () {
                                galleryCubit.collapseCollection(plugin.id);
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Content — animates between loading and loaded
                    Flexible(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: expansion == null
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Loading collection contents...'),
                                  ],
                                ),
                              )
                            : CollectionExpansionPanel(
                                expansion: expansion,
                                pluginId: plugin.id,
                                installDisabled: false,
                                fillHeight: true,
                                onTogglePlugin: (index) => context
                                    .read<GalleryCubit>()
                                    .toggleCollectionPlugin(plugin.id, index),
                                onSelectAll: (selected) => context
                                    .read<GalleryCubit>()
                                    .selectAllCollectionPlugins(
                                      plugin.id,
                                      selected,
                                    ),
                                onInstall: (selected) {
                                  Navigator.of(dialogContext).pop();
                                  _doInstallCollectionPlugins(
                                    plugin.id,
                                    selected,
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ).then((_) {
      // Clean up expansion state when dialog closes
      galleryCubit.collapseCollection(plugin.id);
    });
  }

  // --- README ---

  Future<void> _showReadmeDialog(GalleryPlugin plugin) async {
    try {
      String readmeUrl = plugin.repository.url;
      if (!readmeUrl.contains('#readme')) {
        readmeUrl = readmeUrl.endsWith('/')
            ? '$readmeUrl#readme'
            : '$readmeUrl#readme';
      }

      final uri = Uri.parse(readmeUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open $readmeUrl')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening documentation: $e')),
        );
      }
    }
  }

  // --- Drag and Drop ---

  void _handleDragEntered(DropEventDetails details) {
    setState(() => _isDragOver = true);
  }

  void _handleDragExited(DropEventDetails details) {
    setState(() => _isDragOver = false);
  }

  void _handleDragDone(DropDoneDetails details) {
    setState(() => _isDragOver = false);

    final allowedExtensions = {'.lua', '.3pot', '.o'};
    final validFiles = details.files.where((file) {
      final extension = file.path.toLowerCase().split('.').last;
      return allowedExtensions.contains('.$extension');
    }).toList();

    if (validFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please drop valid plugin files (.lua, .3pot, or .o)'),
          backgroundColor: context.appColors.warning.color,
        ),
      );
      return;
    }

    if (validFiles.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please drop only one file at a time'),
          backgroundColor: context.appColors.warning.color,
        ),
      );
      return;
    }

    _installDroppedFile(validFiles.first);
  }

  Future<void> _installDroppedFile(XFile file) async {
    setState(() => _isInstallingFile = true);

    try {
      final fileBytes = await file.readAsBytes();
      final fileName = file.name;

      if (!mounted) return;
      final cleanupOutcome = await context.read<DistingCubit>().installPlugin(
        fileName,
        fileBytes,
        onProgress: (progress) {},
      );

      setState(() => _isInstallingFile = false);
      _showCleanupOutcome(cleanupOutcome);

      if (!mounted) return;
      await context.read<DistingCubit>().rescanPlugins();

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        context.read<GalleryCubit>().refreshUpdates(
          devicePluginGuids: _getDevicePluginGuids(),
          devicePluginPaths: _getDevicePluginPaths(),
        );
      }
    } catch (e) {
      setState(() => _isInstallingFile = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to install "${file.name}": $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Widget _buildDragOverlay() {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Drop plugin files here to install',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Supports .lua, .3pot, and .o files',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstallOverlay() {
    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Installing plugin...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'This may take a few moments',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helpers ---

  IconData _getIconData(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'audio_file':
        return Icons.audio_file;
      case 'graphic_eq':
        return Icons.graphic_eq;
      case 'piano':
        return Icons.piano;
      case 'queue_music':
        return Icons.queue_music;
      case 'tune':
        return Icons.tune;
      case 'extension':
        return Icons.extension;
      default:
        return Icons.category;
    }
  }
}

/// Animated completion indicator — scales in, holds, then fades out and auto-dismisses
class _CompletionRow extends StatefulWidget {
  final VoidCallback onAutoDismiss;
  const _CompletionRow({super.key, required this.onAutoDismiss});

  @override
  State<_CompletionRow> createState() => _CompletionRowState();
}

class _CompletionRowState extends State<_CompletionRow>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final AnimationController _exitController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Enter: elastic scale-in of the check icon
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _enterController,
      curve: Curves.elasticOut,
    );

    // Exit: fade the whole row out
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeIn,
    );

    _enterController.forward();

    // After a 1.5s hold, fade out then dismiss
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _exitController.forward().then((_) {
          if (mounted) widget.onAutoDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: ReverseAnimation(_fadeAnimation),
      child: Row(
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Icon(
              Icons.check_circle,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Installed',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated failure indicator — shows error briefly then fades out
class _FailureRow extends StatefulWidget {
  final String? errorMessage;
  final VoidCallback onAutoDismiss;
  const _FailureRow({
    super.key,
    this.errorMessage,
    required this.onAutoDismiss,
  });

  @override
  State<_FailureRow> createState() => _FailureRowState();
}

class _FailureRowState extends State<_FailureRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeIn,
    );

    // Hold longer for errors so user can read the message
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _exitController.forward().then((_) {
          if (mounted) widget.onAutoDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: ReverseAnimation(_fadeAnimation),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Text(
                'Failed',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Backup progress dialog
class _BackupProgressDialog extends StatefulWidget {
  final String directoryPath;
  final DistingCubit distingCubit;

  const _BackupProgressDialog({
    required this.directoryPath,
    required this.distingCubit,
  });

  @override
  State<_BackupProgressDialog> createState() => _BackupProgressDialogState();
}

class _BackupProgressDialogState extends State<_BackupProgressDialog> {
  double _progress = 0.0;
  String _currentFile = 'Preparing...';
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startBackup();
  }

  Future<void> _startBackup() async {
    try {
      await widget.distingCubit.backupPlugins(
        widget.directoryPath,
        onProgress: (progress, currentFile) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _currentFile = currentFile;
              _isComplete = progress >= 1.0;
            });
          }
        },
      );

      if (mounted && !_isComplete) {
        setState(() {
          _isComplete = true;
          _currentFile = 'Backup completed successfully';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backing Up Plugins'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Backup location: ${widget.directoryPath}'),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 8),
          Text(
            _currentFile,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error: $_error',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_isComplete || _error != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted && _error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Backup failed: $_error'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
            },
            child: const Text('Close'),
          ),
      ],
    );
  }
}
