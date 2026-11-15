import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

class CollectionExpansionPanel extends StatefulWidget {
  final CollectionExpansion expansion;
  final String pluginId;
  final bool installDisabled;
  final Function(int index) onTogglePlugin;
  final Function(bool selected) onSelectAll;
  final Function(List<CollectionPlugin> selected) onInstall;
  final bool fillHeight;

  const CollectionExpansionPanel({
    super.key,
    required this.expansion,
    required this.pluginId,
    required this.installDisabled,
    required this.onTogglePlugin,
    required this.onSelectAll,
    required this.onInstall,
    this.fillHeight = false,
  });

  @override
  State<CollectionExpansionPanel> createState() =>
      _CollectionExpansionPanelState();
}

class _CollectionExpansionPanelState extends State<CollectionExpansionPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _hasFocusedSearch = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<_IndexedPlugin> get _filteredPlugins {
    final plugins = widget.expansion.plugins;
    final indexed = <_IndexedPlugin>[];
    for (int i = 0; i < plugins.length; i++) {
      final p = plugins[i];
      if (_searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery) ||
          (p.description?.toLowerCase().contains(_searchQuery) ?? false)) {
        indexed.add(_IndexedPlugin(index: i, plugin: p));
      }
    }
    return indexed;
  }

  int get _selectedCount =>
      widget.expansion.plugins.where((p) => p.selected).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.expansion.isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading collection contents...'),
          ],
        ),
      );
    }

    if (widget.expansion.error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to load: ${widget.expansion.error}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    final plugins = widget.expansion.plugins;
    final filtered = _filteredPlugins;
    final showSearch = plugins.length > 5;

    if (showSearch && !_hasFocusedSearch) {
      _hasFocusedSearch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSearch) ...[
            DigitShortcutBlocker(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search in collection...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Selection controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  '$_selectedCount of ${plugins.length} selected',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () {
                  final allSelected = plugins.every((p) => p.selected);
                  widget.onSelectAll(!allSelected);
                },
                child: Text(
                  plugins.every((p) => p.selected)
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Plugin list
          _wrapListView(
            ListView.builder(
              shrinkWrap: !widget.fillHeight,
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final entry = filtered[i];
                final plugin = entry.plugin;
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: CheckboxListTile(
                    value: plugin.selected,
                    onChanged: (_) => widget.onTogglePlugin(entry.index),
                    dense: true,
                    title: Text(plugin.name),
                    subtitle: Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            _getFileTypeIcon(plugin.fileType),
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getFileTypeLabel(plugin.fileType),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (plugin.fileSize != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatFileSize(plugin.fileSize!),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Install button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (widget.installDisabled || _selectedCount == 0)
                  ? null
                  : () {
                      final selected = widget.expansion.plugins
                          .where((p) => p.selected)
                          .toList();
                      widget.onInstall(selected);
                    },
              icon: const Icon(Icons.download, size: 18),
              label: Text(
                _selectedCount > 0
                    ? 'Install Selected ($_selectedCount)'
                    : 'Select plugins to install',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapListView(Widget listView) {
    if (widget.fillHeight) {
      return Expanded(child: listView);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: listView,
    );
  }

  String _getFileTypeLabel(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'o':
        return 'C++ Plugin';
      case 'lua':
        return 'Lua Script';
      case '3pot':
        return 'Preset';
      case 'wav':
        return 'Audio Sample';
      default:
        return '.${fileType.toLowerCase()}';
    }
  }

  IconData _getFileTypeIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'o':
        return Icons.memory;
      case 'lua':
        return Icons.code;
      case '3pot':
        return Icons.tune;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _IndexedPlugin {
  final int index;
  final CollectionPlugin plugin;
  const _IndexedPlugin({required this.index, required this.plugin});
}
