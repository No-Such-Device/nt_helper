import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:nt_helper/models/sd_card_file_system.dart';

class MobileDrillDownNavigator extends StatelessWidget {
  final List<DirectoryEntry> items;
  final DirectoryEntry? selectedItem;
  final List<String> breadcrumbs;
  final Function(DirectoryEntry) onItemTap;
  final Function(int) onBreadcrumbTap;
  final Future<void> Function() onRefresh;
  final bool refreshing;
  final String? error;
  final Function(DirectoryEntry)? onLongPress;

  const MobileDrillDownNavigator({
    super.key,
    required this.items,
    this.selectedItem,
    required this.breadcrumbs,
    required this.onItemTap,
    required this.onBreadcrumbTap,
    required this.onRefresh,
    this.refreshing = false,
    this.error,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Breadcrumb navigation
        SizedBox(
          height: 40,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Root icon/button
                  Semantics(
                    label: 'Navigate to root',
                    button: true,
                    child: InkWell(
                      onTap: () => onBreadcrumbTap(-1),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.home,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  // Breadcrumb segments
                  ...breadcrumbs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final segment = entry.value;
                    final isLast = index == breadcrumbs.length - 1;

                    return Row(
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        InkWell(
                          onTap: isLast ? null : () => onBreadcrumbTap(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 8.0,
                            ),
                            child: Text(
                              segment,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isLast
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isLast
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),

        SizedBox(
          height: 40,
          child: Semantics(
            liveRegion: true,
            label:
                error ??
                (refreshing ? 'Refreshing directory' : 'Directory ready'),
            child: Align(
              alignment: Alignment.centerRight,
              child: refreshing
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: error == null
                          ? 'Refresh directory'
                          : 'Retry: $error',
                      onPressed: () => onRefresh(),
                      icon: Icon(
                        error == null ? Icons.refresh : Icons.error_outline,
                      ),
                    ),
            ),
          ),
        ),

        // Directory listing
        Expanded(
          child: ClipRect(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Text(
                            'Empty directory',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = item == selectedItem;

                        String displayName = item.name;
                        if (displayName.endsWith('/')) {
                          displayName = displayName.substring(
                            0,
                            displayName.length - 1,
                          );
                        }

                        final isJsonPreset =
                            !item.isDirectory &&
                            item.name.toLowerCase().endsWith('.json');
                        final isParentDir = item.name == '..';

                        final icon = isParentDir
                            ? Icons.folder_open
                            : item.isDirectory
                            ? Icons.folder
                            : _getFileIcon(item.name);

                        final iconColor = isParentDir
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.7)
                            : item.isDirectory
                            ? Theme.of(context).colorScheme.primary
                            : isJsonPreset
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.secondary;

                        final fileInfo = !item.isDirectory
                            ? _formatFileInfo(item)
                            : null;

                        final semanticLabel = item.isDirectory
                            ? 'Folder: $displayName'
                            : 'File: $displayName, $fileInfo';

                        Widget tile = ListTile(
                          leading: ExcludeSemantics(
                            child: Icon(icon, size: 28, color: iconColor),
                          ),
                          title: Semantics(
                            label: semanticLabel,
                            excludeSemantics: true,
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          subtitle: fileInfo != null
                              ? ExcludeSemantics(
                                  child: Text(
                                    fileInfo,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                )
                              : null,
                          trailing: item.isDirectory
                              ? ExcludeSemantics(
                                  child: Icon(
                                    Icons.chevron_right,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          selected: isSelected,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          onTap: () => onItemTap(item),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 4.0,
                          ),
                          minVerticalPadding: 8.0,
                        );

                        if (!isParentDir && onLongPress != null) {
                          tile = GestureDetector(
                            onLongPress: () => onLongPress!(item),
                            child: tile,
                          );
                        }

                        return tile;
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatFileInfo(DirectoryEntry entry) {
    final size = _formatFileSize(entry.size);
    final dateTime = _formatFatDateTime(entry.date, entry.time);
    if (dateTime != null) return '$size · $dateTime';
    return size;
  }

  static String? _formatFatDateTime(int fatDate, int fatTime) {
    if (fatDate == 0) return null;
    final day = fatDate & 0x1F;
    final month = (fatDate >> 5) & 0x0F;
    final year = ((fatDate >> 9) & 0x7F) + 1980;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final hour = (fatTime >> 11) & 0x1F;
    final minute = (fatTime >> 5) & 0x3F;
    final dt = DateTime(year, month, day, hour, minute);
    return DateFormat.yMMMd().add_jm().format(dt);
  }

  static IconData _getFileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.scl') || lower.endsWith('.kbm')) return Icons.tune;
    if (lower.endsWith('.wav') || lower.endsWith('.aif')) {
      return Icons.graphic_eq;
    }
    if (lower.endsWith('.lua') ||
        lower.endsWith('.3pot') ||
        lower.endsWith('.o')) {
      return Icons.code;
    }
    if (lower.endsWith('.zip')) return Icons.folder_zip;
    if (lower.endsWith('.json')) return Icons.music_note;
    return Icons.insert_drive_file;
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
