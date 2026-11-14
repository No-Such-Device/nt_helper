import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/interfaces/impl/preset_file_system_impl.dart';
import 'package:nt_helper/models/package_analysis.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/file_conflict_detector.dart';
import 'package:nt_helper/services/preset_package_analyzer.dart';
import 'package:nt_helper/services/wave_cache_maintenance_service.dart';
import 'package:nt_helper/models/preset_action.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/mobile_drill_down_navigator.dart';
import 'package:nt_helper/ui/widgets/package_install_dialog.dart';
import 'package:nt_helper/ui/widgets/preset_package_dialog.dart';
import 'package:nt_helper/ui/widgets/wave_cache_troubleshooting_dialog.dart';
import 'package:nt_helper/utils/responsive.dart';
import 'package:nt_helper/services/preset_analyzer.dart';

enum _FileAction { refresh, download, upload, newFolder, rename, delete, view }

bool get _supportsDesktopDrop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

class _DeleteSelectedIntent extends Intent {
  const _DeleteSelectedIntent();
}

class PresetBrowserDialog extends StatefulWidget {
  final DistingCubit distingCubit;
  final FirmwareVersion? firmwareVersion;

  const PresetBrowserDialog({
    super.key,
    required this.distingCubit,
    this.firmwareVersion,
  });

  @override
  State<PresetBrowserDialog> createState() => _PresetBrowserDialogState();
}

class _PresetBrowserDialogState extends State<PresetBrowserDialog>
    with WidgetsBindingObserver {
  bool _isDragOver = false;
  bool _isInstallingPackage = false;
  double? _uploadProgress;

  PackageAnalysis? _currentAnalysis;
  Uint8List? _currentPackageData;

  bool get _supportsWaveCacheTroubleshooting {
    return widget.firmwareVersion?.hasWaveCacheListing ?? false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<PresetBrowserCubit>().loadRootDirectory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        context.read<PresetBrowserCubit>().refreshVisiblePanes(
          onlyIfStale: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    context.read<PresetBrowserCubit>().setSinglePaneLayout(isMobile);

    Widget content = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.delete):
            const _DeleteSelectedIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _DeleteSelectedIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DeleteSelectedIntent: CallbackAction<_DeleteSelectedIntent>(
            onInvoke: (_) {
              _deleteSelectedItem();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            key: const Key('preset-browser-dialog'),
            title: Row(
              key: const Key('preset-browser-toolbar'),
              children: [
                const Expanded(child: Text('File Browser')),
                BlocBuilder<PresetBrowserCubit, PresetBrowserState>(
                  builder: (context, state) {
                    final browser = state.view;
                    final directory = state.currentPath;
                    return Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.create_new_folder,
                            semanticLabel: 'New folder in $directory',
                          ),
                          tooltip: 'New folder in $directory',
                          onPressed: browser == null
                              ? null
                              : () => _createFolderAction(directory),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            semanticLabel: 'Back',
                          ),
                          tooltip: 'Back',
                          onPressed: browser?.canGoBack == true
                              ? () => context
                                    .read<PresetBrowserCubit>()
                                    .navigateBack()
                              : null,
                        ),
                        IconButton(
                          icon: Icon(
                            state.sortByDate
                                ? Icons.date_range
                                : Icons.sort_by_alpha,
                            semanticLabel: state.sortByDate
                                ? 'Sort by date'
                                : 'Sort alphabetically',
                          ),
                          tooltip: state.sortByDate
                              ? 'Sort by date'
                              : 'Sort alphabetically',
                          onPressed: browser == null
                              ? null
                              : () => context
                                    .read<PresetBrowserCubit>()
                                    .toggleSortMode(),
                        ),
                      ],
                    );
                  },
                ),
                if (isMobile)
                  IconButton(
                    icon: const Icon(
                      Icons.troubleshoot,
                      semanticLabel: 'Wave cache troubleshooting',
                    ),
                    onPressed: _supportsWaveCacheTroubleshooting
                        ? _showWaveCacheTroubleshooting
                        : null,
                    tooltip: _supportsWaveCacheTroubleshooting
                        ? 'Wave cache troubleshooting'
                        : 'Wave cache troubleshooting requires firmware 1.17 or later',
                  )
                else
                  TextButton.icon(
                    onPressed: _supportsWaveCacheTroubleshooting
                        ? _showWaveCacheTroubleshooting
                        : null,
                    icon: const Icon(Icons.troubleshoot),
                    label: const Text('Wave cache'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, semanticLabel: 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile
                  ? MediaQuery.of(context).size.width * 0.95
                  : MediaQuery.of(context).size.width * 0.8,
              height: isMobile
                  ? MediaQuery.of(context).size.height * 0.7
                  : MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  if (!isMobile)
                    SizedBox(
                      key: const Key('preset-browser-breadcrumbs'),
                      height: 40,
                      child:
                          BlocBuilder<PresetBrowserCubit, PresetBrowserState>(
                            builder: (context, state) =>
                                _buildDesktopBreadcrumbs(context, state),
                          ),
                    ),
                  Expanded(
                    child: ClipRect(
                      child:
                          BlocBuilder<PresetBrowserCubit, PresetBrowserState>(
                            builder: (context, state) {
                              final browser =
                                  state.view ??
                                  BrowserSnapshot(
                                    stack: const [BrowserFrame(path: '/')],
                                    refreshing:
                                        state.mapOrNull(
                                              initial: (_) => true,
                                              loading: (_) => true,
                                            ) ==
                                            true
                                        ? {'/'}
                                        : {},
                                  );
                              final enabled = state.view != null;
                              return isMobile
                                  ? MobileDrillDownNavigator(
                                      items: browser.entriesAt(
                                        browser.stack.length - 1,
                                      ),
                                      selectedItem: browser.selectedAt(
                                        browser.stack.length - 1,
                                      ),
                                      breadcrumbs: _getBreadcrumbsFromPath(
                                        browser.current.path,
                                      ),
                                      onItemTap: _handleMobileItemTap,
                                      onBreadcrumbTap: _handleBreadcrumbTap,
                                      onRefresh: _handleRefresh,
                                      refreshing:
                                          browser.refreshing.contains(
                                            browser.current.path,
                                          ) ||
                                          browser.busyPaths.any(
                                            (busy) =>
                                                p.posix.dirname(busy) ==
                                                browser.current.path
                                                    .toLowerCase(),
                                          ),
                                      error:
                                          browser.errors[browser.current.path],
                                      onLongPress: (entry) =>
                                          _showContextMenuAtCenter(
                                            entry,
                                            browser.current.path,
                                          ),
                                    )
                                  : ThreePanelNavigator(
                                      browser: browser,
                                      onPaneFocused: (panel) => unawaited(
                                        context
                                            .read<PresetBrowserCubit>()
                                            .focusPane(panel),
                                      ),
                                      onPaneBack: (_) => unawaited(
                                        context
                                            .read<PresetBrowserCubit>()
                                            .navigateBack(),
                                      ),
                                      onItemSelected: _handleItemSelected,
                                      onContextMenu: _handleContextMenu,
                                      onDirectoryContextMenu:
                                          (position, path) => _showContextMenu(
                                            null,
                                            position,
                                            path,
                                          ),
                                      onFilesDropped: _handlePanelDrop,
                                      dropEnabled:
                                          enabled &&
                                          !_isInstallingPackage &&
                                          _currentAnalysis == null,
                                    );
                            },
                          ),
                    ),
                  ),
                  SizedBox(
                    key: const Key('preset-browser-status'),
                    height: 32,
                    child: BlocBuilder<PresetBrowserCubit, PresetBrowserState>(
                      builder: (context, state) {
                        final browser = state.view;
                        final error =
                            state.mapOrNull(error: (error) => error.message) ??
                            browser?.errors[browser.focused.path];
                        final message =
                            error ??
                            (browser?.pendingPath == null
                                ? ''
                                : 'Opening ${browser!.pendingPath}…');
                        return Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Tooltip(
                                  message: message,
                                  child: Text(
                                    message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: state.view != null || error == null
                                  ? null
                                  : TextButton(
                                      onPressed: () => context
                                          .read<PresetBrowserCubit>()
                                          .loadRootDirectory(),
                                      child: const Text('Retry'),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: 8,
                    child: _uploadProgress == null
                        ? null
                        : LinearProgressIndicator(
                            value: _uploadProgress,
                            minHeight: 2,
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              BlocBuilder<PresetBrowserCubit, PresetBrowserState>(
                builder: (context, state) {
                  final selectedPath = context
                      .read<PresetBrowserCubit>()
                      .getSelectedPath();
                  final isPresetFile =
                      selectedPath.isNotEmpty &&
                      selectedPath.toLowerCase().endsWith('.json');
                  final isMobile = Responsive.isMobile(context);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMobile) ...[
                        OutlinedButton(
                          onPressed: isPresetFile
                              ? () async {
                                  if (context
                                          .read<PresetBrowserCubit>()
                                          .getSelectedPath() !=
                                      selectedPath) {
                                    return;
                                  }
                                  Navigator.of(context).pop();

                                  Map<String, String>? pluginPaths;
                                  final state = widget.distingCubit.state;
                                  if (state is DistingStateSynchronized) {
                                    // Use the full algorithm library, not just the
                                    // currently-loaded slots. The preset being
                                    // exported may reference plugins that aren't
                                    // currently in any slot — those still need
                                    // their filenames resolved for packaging.
                                    pluginPaths =
                                        PresetAnalyzer.extractPluginPaths(
                                          state.algorithms,
                                        );
                                  }

                                  await showDialog<void>(
                                    context: context,
                                    builder: (dialogContext) =>
                                        PresetPackageDialog(
                                          presetFilePath: selectedPath,
                                          fileSystem: PresetFileSystemImpl(
                                            widget.distingCubit
                                                .requireDisting(),
                                          ),
                                          pluginPaths: pluginPaths,
                                        ),
                                  );
                                }
                              : null,
                          child: const Text('Export'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton(
                        onPressed: isPresetFile
                            ? () {
                                if (context
                                        .read<PresetBrowserCubit>()
                                        .getSelectedPath() !=
                                    selectedPath) {
                                  return;
                                }
                                Navigator.of(context).pop({
                                  'sdCardPath': selectedPath,
                                  'action': PresetAction.load,
                                  'displayName': selectedPath.split('/').last,
                                });
                              }
                            : null,
                        child: const Text('Load'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    content = BlocListener<PresetBrowserCubit, PresetBrowserState>(
      listenWhen: (before, after) =>
          before.view?.warning != after.view?.warning,
      listener: (context, state) {
        final warning = state.view?.warning;
        if (warning != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(warning)));
        }
      },
      child: content,
    );

    if (_supportsDesktopDrop && isMobile) {
      return DropTarget(
        onDragDone: _handleDragDone,
        onDragEntered: _handleDragEntered,
        onDragExited: _handleDragExited,
        child: Stack(
          children: [
            content,
            if (_isDragOver) _buildDragOverlay(),
            if (_isInstallingPackage) _buildInstallOverlay(),
          ],
        ),
      );
    }

    if (_supportsDesktopDrop) {
      return Stack(
        children: [content, if (_isInstallingPackage) _buildInstallOverlay()],
      );
    }

    return content;
  }

  Future<void> _showWaveCacheTroubleshooting() async {
    final remountRequested = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaveCacheTroubleshootingDialog(
        service: WaveCacheMaintenanceService(
          widget.distingCubit.requireDisting(),
        ),
      ),
    );
    if (remountRequested == true && mounted) {
      Navigator.of(context).pop();
    } else if (mounted) {
      // This child tool can change device files outside the browser cubit.
      await context.read<PresetBrowserCubit>().refreshVisiblePanes();
    }
  }

  Widget _buildDesktopBreadcrumbs(
    BuildContext context,
    PresetBrowserState loaded,
  ) {
    final currentPath = loaded.currentPath;
    final breadcrumbs = _getBreadcrumbsFromPath(currentPath);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Semantics(
              label: 'Navigate to root',
              button: true,
              child: InkWell(
                onTap: () {
                  context.read<PresetBrowserCubit>().navigateToAbsolutePath(
                    '/',
                  );
                },
                child: Tooltip(
                  message: 'Go to root',
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
            ),
            ...breadcrumbs.asMap().entries.map((entry) {
              final index = entry.key;
              final segment = entry.value;
              final isLast = index == breadcrumbs.length - 1;
              final pathUpTo = '/${breadcrumbs.take(index + 1).join('/')}';

              return Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Tooltip(
                    message: pathUpTo,
                    child: InkWell(
                      onTap: isLast
                          ? null
                          : () {
                              context
                                  .read<PresetBrowserCubit>()
                                  .navigateToAbsolutePath(pathUpTo);
                            },
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
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.primary,
                          ),
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
    );
  }

  List<String> _getBreadcrumbsFromPath(String path) {
    if (path == '/' || path.isEmpty) return [];
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }

  void _handleItemSelected(DirectoryEntry item, PanelPosition position) {
    final cubit = context.read<PresetBrowserCubit>();

    if (item.isDirectory) {
      cubit.selectDirectory(item, position);
    } else {
      cubit.selectFile(item, position);
    }
  }

  void _handleMobileItemTap(DirectoryEntry item) {
    final cubit = context.read<PresetBrowserCubit>();

    if (item.isDirectory) {
      cubit.navigateIntoDirectory(item);
    } else {
      cubit.selectDrillItem(item);
    }
  }

  void _handleBreadcrumbTap(int index) {
    final cubit = context.read<PresetBrowserCubit>();

    if (index == -1) {
      cubit.navigateToAbsolutePath('/');
    } else {
      cubit.navigateToPathSegment(index);
    }
  }

  Future<void> _handleRefresh() =>
      context.read<PresetBrowserCubit>().refreshPane();

  void _handleContextMenu(
    DirectoryEntry entry,
    Offset position,
    String panelPath,
  ) {
    if (entry.name == '..') return;
    _showContextMenu(entry, position, panelPath);
  }

  void _showContextMenuAtCenter(DirectoryEntry entry, String panelPath) {
    if (entry.name == '..') return;
    final box = context.findRenderObject() as RenderBox;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    _showContextMenu(entry, center, panelPath);
  }

  void _showContextMenu(
    DirectoryEntry? entry,
    Offset position,
    String panelPath,
  ) {
    final cubit = context.read<PresetBrowserCubit>();
    final entryPath = entry == null
        ? panelPath
        : cubit.getEntryPath(entry, panelPath);
    final isFile = entry != null && !entry.isDirectory;
    final isTextFile = entry != null && _isTextFile(entry.name);

    final entryReady = entry != null && cubit.canUseEntry(entryPath);
    final targetDir = entry?.isDirectory == true ? entryPath : panelPath;
    final directoryReady =
        cubit.isDirectoryReady(panelPath) &&
        (entry?.isDirectory != true || entryReady);
    final items = <PopupMenuEntry<_FileAction>>[
      const PopupMenuItem(
        value: _FileAction.refresh,
        child: ListTile(
          leading: Icon(Icons.refresh),
          title: Text('Refresh'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      const PopupMenuDivider(),
    ];

    if (isTextFile) {
      items.add(
        PopupMenuItem(
          enabled: entryReady,
          value: _FileAction.view,
          child: ListTile(
            leading: Icon(Icons.visibility),
            title: Text('View'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }

    if (isFile) {
      items.add(
        PopupMenuItem(
          enabled: entryReady,
          value: _FileAction.download,
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Download'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }

    items.addAll([
      PopupMenuItem(
        enabled: directoryReady,
        value: _FileAction.upload,
        child: ListTile(
          leading: Icon(Icons.upload),
          title: Text('Upload Here'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        enabled: directoryReady,
        value: _FileAction.newFolder,
        child: ListTile(
          leading: Icon(Icons.create_new_folder),
          title: Text('New Folder'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      if (entry != null)
        PopupMenuItem(
          enabled: entryReady,
          value: _FileAction.rename,
          child: ListTile(
            leading: Icon(Icons.edit),
            title: Text('Rename'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      if (entry != null)
        PopupMenuItem(
          enabled: entryReady,
          value: _FileAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ]);

    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    showMenu<_FileAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((action) {
      if (action == null || !mounted) return;
      if (action == _FileAction.refresh) {
        unawaited(cubit.refreshDirectory(panelPath));
        return;
      }
      // A menu may remain open across a refresh, upload, or branch change.
      if (!cubit.isDirectoryReady(panelPath) ||
          (entry != null && !cubit.canUseEntry(entryPath))) {
        return;
      }
      switch (action) {
        case _FileAction.refresh:
          break;
        case _FileAction.download:
          if (entry != null) _downloadFile(entryPath, entry.name);
        case _FileAction.upload:
          _uploadFileAction(targetDir);
        case _FileAction.newFolder:
          _createFolderAction(targetDir);
        case _FileAction.rename:
          if (entry != null) _renameAction(entryPath, entry.name);
        case _FileAction.delete:
          if (entry != null) _deleteAction(entryPath, entry.name);
        case _FileAction.view:
          if (entry != null) _viewTextFile(entryPath, entry.name);
      }
    });
  }

  bool _isTextFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.txt') || lower.endsWith('.md');
  }

  Future<void> _downloadFile(String path, String fileName) async {
    final cubit = context.read<PresetBrowserCubit>();

    try {
      final data = await cubit.downloadFile(path);
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download file'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      final result = await FilePicker.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: fileName,
        bytes: data,
      );

      if (result != null && mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Downloaded $fileName',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _uploadFileAction(String targetDirectory) async {
    final cubit = context.read<PresetBrowserCubit>();
    final file = await FilePicker.pickFile();
    if (file == null) return;

    final bytes = await file.readAsBytes();

    try {
      setState(() => _uploadProgress = 0);
      await cubit.uploadFile(
        targetDirectory,
        file.name,
        bytes,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      if (mounted) {
        setState(() => _uploadProgress = null);
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Uploaded ${file.name}',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadProgress = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _createFolderAction(String parentDirectory) async {
    final cubit = context.read<PresetBrowserCubit>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Semantics(header: true, child: const Text('New Folder')),
        content: DigitShortcutBlocker(
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder name',
              hintText: 'Enter folder name',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    try {
      await cubit.createDirectory(parentDirectory, name.trim());
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Created folder ${name.trim()}',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create folder: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _renameAction(String fullPath, String currentName) async {
    final cubit = context.read<PresetBrowserCubit>();
    final cleanName = currentName.endsWith('/')
        ? currentName.substring(0, currentName.length - 1)
        : currentName;
    final controller = TextEditingController(text: cleanName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Semantics(header: true, child: const Text('Rename')),
        content: DigitShortcutBlocker(
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New name'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == cleanName ||
        !mounted ||
        !cubit.canUseEntry(fullPath)) {
      return;
    }

    try {
      await cubit.renameEntry(fullPath, newName.trim());
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Renamed to ${newName.trim()}',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rename failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteAction(String fullPath, String name) async {
    final cubit = context.read<PresetBrowserCubit>();
    final cleanName = name.endsWith('/')
        ? name.substring(0, name.length - 1)
        : name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Semantics(header: true, child: const Text('Delete')),
        content: Text('Delete "$cleanName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || !cubit.canUseEntry(fullPath)) return;

    try {
      await cubit.deleteEntry(fullPath);
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Deleted $cleanName',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _deleteSelectedItem() {
    final cubit = context.read<PresetBrowserCubit>();
    final selectedPath = cubit.getSelectedPath();
    if (selectedPath.isEmpty) return;

    final name = selectedPath.split('/').last;
    _deleteAction(selectedPath, name);
  }

  Future<void> _viewTextFile(String path, String fileName) async {
    final cubit = context.read<PresetBrowserCubit>();

    try {
      final data = await cubit.downloadFile(path);
      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to download file for preview'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      final text = utf8.decode(data, allowMalformed: true);
      final isMarkdown = fileName.toLowerCase().endsWith('.md');

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Semantics(header: true, child: Text(fileName)),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.6,
            height: MediaQuery.of(context).size.height * 0.5,
            child: isMarkdown
                ? Markdown(data: text)
                : SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to view file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Drag and drop handlers
  void _handleDragEntered(DropEventDetails details) {
    setState(() {
      _isDragOver = true;
    });
  }

  void _handleDragExited(DropEventDetails details) {
    setState(() {
      _isDragOver = false;
    });
  }

  void _handleDragDone(DropDoneDetails details) {
    setState(() {
      _isDragOver = false;
    });

    _handleDroppedFiles(details.files.cast<XFile>());
  }

  void _handlePanelDrop(List<XFile> files, String targetDirectory) {
    _handleDroppedFiles(files, targetDirectory: targetDirectory);
  }

  void _handleDroppedFiles(List<XFile> files, {String? targetDirectory}) {
    if (_isInstallingPackage || _currentAnalysis != null) return;

    if (files.isEmpty) return;

    if (files.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please drop only one file at a time'),
          backgroundColor: context.appColors.warning.color,
        ),
      );
      return;
    }

    final file = files.first;
    final lowerPath = file.path.toLowerCase();

    if (lowerPath.endsWith('.zip')) {
      _processPackageFile(file);
    } else {
      _uploadDroppedFile(file, targetDirectory: targetDirectory);
    }
  }

  Future<void> _uploadDroppedFile(XFile file, {String? targetDirectory}) async {
    final cubit = context.read<PresetBrowserCubit>();
    final bytes = await file.readAsBytes();
    final fileName = file.path.split('/').last.split('\\').last;
    final targetDir = targetDirectory ?? cubit.getCurrentDirectory();

    try {
      setState(() => _uploadProgress = 0);
      await cubit.uploadFile(
        targetDir,
        fileName,
        bytes,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      if (mounted) {
        setState(() => _uploadProgress = null);
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Uploaded $fileName',
          TextDirection.ltr,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadProgress = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _processPackageFile(XFile file) async {
    if (_isInstallingPackage || _currentAnalysis != null) return;

    setState(() {
      _isInstallingPackage = true;
    });

    try {
      final fileBytes = await file.readAsBytes();
      if (!mounted) return;

      final isValid = await PresetPackageAnalyzer.isValidPackage(fileBytes);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _isInstallingPackage = false;
        });
        _showValidationErrorDialog(
          'Invalid Package Format',
          'The dropped file is not a valid preset package. Please ensure it contains a manifest.json file and a root/ directory with the preset files.',
        );
        return;
      }

      final analysis = await PresetPackageAnalyzer.analyzePackage(fileBytes);
      if (!mounted) return;
      if (!analysis.isValid) {
        setState(() {
          _isInstallingPackage = false;
        });
        _showValidationErrorDialog(
          'Package Analysis Failed',
          analysis.errorMessage ?? 'Unable to analyze the package contents.',
        );
        return;
      }

      setState(() {
        _currentAnalysis = analysis;
        _currentPackageData = fileBytes;
      });

      final conflictDetector = FileConflictDetector(widget.distingCubit);
      final analysisWithConflicts = await conflictDetector.detectConflicts(
        analysis,
      );
      if (!mounted) return;

      setState(() {
        _currentAnalysis = analysisWithConflicts;
      });

      if (!mounted) return;

      final installed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PackageInstallDialog(
          analysis: _currentAnalysis!,
          packageData: _currentPackageData!,
          distingCubit: widget.distingCubit,
          onInstall: () {
            Navigator.of(dialogContext).pop(true);
          },
          onCancel: () {
            Navigator.of(dialogContext).pop(false);
          },
        ),
      );

      if (!mounted) return;

      setState(() {
        _currentAnalysis = null;
        _currentPackageData = null;
        _isInstallingPackage = false;
      });

      if (installed == true && mounted) {
        Navigator.of(context).pop();
      } else if (mounted) {
        // A cancelled/failed installer may have written part of a package.
        await context.read<PresetBrowserCubit>().refreshVisiblePanes();
      }
    } catch (e, stackTrace) {
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _currentAnalysis = null;
        _currentPackageData = null;
        _isInstallingPackage = false;
      });

      _showValidationErrorDialog(
        'Package Processing Error',
        'An unexpected error occurred while processing the package:\n\n$e',
      );
    } finally {
      if (mounted && _isInstallingPackage) {
        setState(() {
          _isInstallingPackage = false;
        });
      }
    }
  }

  void _showValidationErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDragOverlay() {
    return Positioned.fill(
      child: Container(
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
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Drop file to upload',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstallOverlay() {
    return Positioned.fill(
      child: Container(
        color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.5),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class ThreePanelNavigator extends StatefulWidget {
  final BrowserSnapshot browser;
  final void Function(DirectoryEntry, PanelPosition) onItemSelected;
  final void Function(PanelPosition)? onPaneFocused;
  final void Function(PanelPosition)? onPaneBack;
  final Function(DirectoryEntry, Offset, String panelPath)? onContextMenu;
  final void Function(Offset, String)? onDirectoryContextMenu;
  final void Function(List<XFile>, String)? onFilesDropped;
  final bool dropEnabled;

  const ThreePanelNavigator({
    super.key,
    required this.browser,
    required this.onItemSelected,
    this.onPaneFocused,
    this.onPaneBack,
    this.onContextMenu,
    this.onDirectoryContextMenu,
    this.onFilesDropped,
    this.dropEnabled = true,
  });

  @override
  State<ThreePanelNavigator> createState() => _ThreePanelNavigatorState();
}

class _ThreePanelNavigatorState extends State<ThreePanelNavigator> {
  final _focusNodes = [for (final _ in PanelPosition.values) FocusNode()];
  final Map<String, double> _locationOffsets = {};
  final Map<String, String?> _locationCursors = {};
  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final position in PanelPosition.values) ...[
        if (position != PanelPosition.left) const VerticalDivider(width: 1),
        Expanded(child: _pane(context, position)),
      ],
    ],
  );

  Widget _pane(BuildContext context, PanelPosition position) {
    final directory = widget.browser.path(position);
    final path = directory ?? '';
    final available = directory != null;
    final label = '${position.name} pane';
    return Focus(
      onFocusChange: (focused) {
        if (focused && available) widget.onPaneFocused?.call(position);
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            HardwareKeyboard.instance.isAltPressed) {
          widget.onPaneBack?.call(position);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: available ? '$label: $path' : '$label: unused column',
        selected: widget.browser.activePane == position,
        liveRegion: true,
        value:
            widget.browser.errors[path] ??
            (widget.browser.refreshing.contains(path)
                ? 'Refreshing; file actions unavailable'
                : null),
        child: Listener(
          onPointerDown: (_) {
            if (available) widget.onPaneFocused?.call(position);
          },
          child: DirectoryPanel(
            renamedPaths: widget.browser.renamedPaths,
            locationOffsets: _locationOffsets,
            locationCursors: _locationCursors,
            items: widget.browser.items(position),
            selectedItem: widget.browser.selection(position),
            onItemTap: (item) => widget.onItemSelected(item, position),
            position: position,
            currentPath: path,
            dropTargetDirectory: directory,
            onContextMenu: widget.onContextMenu,
            onDirectoryContextMenu: widget.onDirectoryContextMenu,
            onFilesDropped: widget.onFilesDropped,
            dropEnabled: widget.dropEnabled,
            focusNode: _focusNodes[position.index],
            onFocused: available
                ? () => widget.onPaneFocused?.call(position)
                : null,
            onBack: () => widget.onPaneBack?.call(position),
            onDirectoryOpened: () {
              final depth = widget.browser.depth(position);
              if (depth == null) return;
              final next = (depth + 1).clamp(0, 2);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusNodes[next].requestFocus();
              });
            },
          ),
        ),
      ),
    );
  }
}

IconData _getFileIcon(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.scl') || lower.endsWith('.kbm')) return Icons.tune;
  if (lower.endsWith('.wav') || lower.endsWith('.aif')) return Icons.graphic_eq;
  if (lower.endsWith('.lua') ||
      lower.endsWith('.3pot') ||
      lower.endsWith('.o')) {
    return Icons.code;
  }
  if (lower.endsWith('.zip')) return Icons.folder_zip;
  if (lower.endsWith('.json')) return Icons.music_note;
  return Icons.insert_drive_file;
}

class DirectoryPanel extends StatefulWidget {
  final List<DirectoryEntry> items;
  final Map<String, String> renamedPaths;
  final DirectoryEntry? selectedItem;
  final Function(DirectoryEntry) onItemTap;
  final PanelPosition position;
  final String currentPath;
  final String? dropTargetDirectory;
  final Function(DirectoryEntry, Offset, String panelPath)? onContextMenu;
  final void Function(Offset, String)? onDirectoryContextMenu;
  final void Function(List<XFile> files, String targetDirectory)?
  onFilesDropped;
  final bool dropEnabled;
  final FocusNode? focusNode;
  final Map<String, double>? locationOffsets;
  final Map<String, String?>? locationCursors;
  final VoidCallback? onFocused;
  final VoidCallback? onBack;
  final VoidCallback? onDirectoryOpened;

  const DirectoryPanel({
    super.key,
    required this.items,
    this.renamedPaths = const {},
    required this.selectedItem,
    required this.onItemTap,
    required this.position,
    required this.currentPath,
    this.dropTargetDirectory,
    this.onContextMenu,
    this.onDirectoryContextMenu,
    this.onFilesDropped,
    this.dropEnabled = true,
    this.focusNode,
    this.locationOffsets,
    this.locationCursors,
    this.onFocused,
    this.onBack,
    this.onDirectoryOpened,
  });

  @override
  State<DirectoryPanel> createState() => _DirectoryPanelState();
}

class _DirectoryPanelState extends State<DirectoryPanel> {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());
  late ScrollController _scrollController;
  int _focusedIndex = 0;
  final Map<String, double> _localOffsets = {};
  final Map<String, String?> _localCursors = {};
  Map<String, double> get _scrollOffsets =>
      widget.locationOffsets ?? _localOffsets;
  Map<String, String?> get _cursorNames =>
      widget.locationCursors ?? _localCursors;
  bool _keyboardModality = false;
  bool get _showKeyboardFocus =>
      _keyboardModality &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  void _pointerModality(PointerEvent event) {
    if (_keyboardModality &&
        (event is PointerDownEvent || event is PointerHoverEvent)) {
      setState(() => _keyboardModality = false);
    }
  }

  bool _keyModality(KeyEvent event) {
    if (event is KeyDownEvent &&
        (_focusNode.hasFocus || event.logicalKey == LogicalKeyboardKey.tab)) {
      if (!_keyboardModality) setState(() => _keyboardModality = true);
    }
    return false; // Modality observation must never consume navigation/clicks.
  }

  String _identity(String path, Map<String, String> aliases) {
    final ordered = aliases.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (var pass = 0; pass <= aliases.length; pass++) {
      final before = path;
      for (final alias in ordered) {
        if (path == alias.value || path.startsWith('${alias.value}/')) {
          path = '${alias.key}${path.substring(alias.value.length)}';
          break;
        }
      }
      if (path == before) break;
    }
    return path;
  }

  String _rebase(String path) {
    final ordered = widget.renamedPaths.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (var pass = 0; pass <= ordered.length; pass++) {
      final before = path;
      for (final alias in ordered) {
        if (path == alias.key || path.startsWith('${alias.key}/')) {
          path = '${alias.value}${path.substring(alias.key.length)}';
          break;
        }
      }
      if (path == before) break;
    }
    return path;
  }

  String _entryPath(String directory, String name) => p.posix.join(
    directory,
    name.endsWith('/') ? name.substring(0, name.length - 1) : name,
  );

  ScrollController _controller(double offset) =>
      ScrollController(initialScrollOffset: offset, keepScrollOffset: false)
        ..addListener(_rememberOffset);

  void _highlightChanged(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  bool _isDragOver = false;

  @override
  void initState() {
    super.initState();
    _focusedIndex = widget.items.indexWhere(
      (item) =>
          item.name ==
          (_cursorNames[widget.currentPath] ?? widget.selectedItem?.name),
    );
    if (_focusedIndex < 0 && widget.items.isNotEmpty) _focusedIndex = 0;
    _scrollController = _controller(
      _scrollOffsets[widget.currentPath] ??
          _scrollOffsets[_identity(widget.currentPath, widget.renamedPaths)] ??
          0,
    );
    _focusNode.addListener(_onFocusChange);
    FocusManager.instance.addHighlightModeListener(_highlightChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointerModality);
    HardwareKeyboard.instance.addHandler(_keyModality);
  }

  void _rememberOffset() {
    if (_scrollController.hasClients) {
      _scrollOffsets[widget.currentPath] = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointerModality);
    HardwareKeyboard.instance.removeHandler(_keyModality);
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);
    _focusNode.removeListener(_onFocusChange);
    _ownedFocusNode?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DirectoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _focusNode.addListener(_onFocusChange);
    }
    final oldCursor =
        _focusedIndex >= 0 && _focusedIndex < oldWidget.items.length
        ? oldWidget.items[_focusedIndex].name
        : null;
    final sameLocation =
        _identity(widget.currentPath, widget.renamedPaths) ==
        _identity(oldWidget.currentPath, oldWidget.renamedPaths);
    if (sameLocation) {
      final fullCursor = oldCursor == null
          ? null
          : _rebase(_entryPath(oldWidget.currentPath, oldCursor));
      final name = fullCursor == null
          ? widget.selectedItem?.name
          : p.posix.basename(fullCursor);
      // Directory entry names may have a trailing slash; compare paths.
      if (widget.currentPath != oldWidget.currentPath &&
          _scrollController.hasClients) {
        _scrollOffsets[widget.currentPath] = _scrollController.offset;
      }
      _focusedIndex = widget.items.indexWhere(
        (entry) =>
            _entryPath(widget.currentPath, entry.name) ==
            _entryPath(widget.currentPath, name ?? ''),
      );
      if (_focusedIndex < 0) {
        _focusedIndex = widget.items.indexWhere(
          (entry) => entry.name == widget.selectedItem?.name,
        );
      }
    } else {
      if (_scrollController.hasClients) {
        _scrollOffsets[oldWidget.currentPath] = _scrollController.offset;
      }
      _cursorNames[oldWidget.currentPath] = oldCursor;
      final previous = _scrollController..removeListener(_rememberOffset);
      // New location + correct offset are laid out together, not corrected by
      // a post-frame jump which can first paint an empty/scrolled-out viewport.
      _scrollController = _controller(
        _scrollOffsets[widget.currentPath] ??
            _scrollOffsets[_identity(
              widget.currentPath,
              widget.renamedPaths,
            )] ??
            0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      final name =
          _cursorNames[widget.currentPath] ?? widget.selectedItem?.name;
      _focusedIndex = widget.items.indexWhere((entry) => entry.name == name);
    }
    if (_focusedIndex < 0 && widget.items.isNotEmpty) _focusedIndex = 0;
    _cursorNames[widget.currentPath] = _focusedIndex >= 0
        ? widget.items[_focusedIndex].name
        : null;
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocused?.call();
      if (_showKeyboardFocus) _announceCurrentItem();
    }
    setState(() {});
  }

  void _announceCurrentItem() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.items.length) return;
    final item = widget.items[_focusedIndex];
    final label = _semanticLabel(item);
    SemanticsService.sendAnnouncement(
      View.of(context),
      label,
      TextDirection.ltr,
    );
  }

  String _semanticLabel(DirectoryEntry item) {
    String displayName = item.name;
    if (displayName.endsWith('/')) {
      displayName = displayName.substring(0, displayName.length - 1);
    }
    if (item.isDirectory) return 'Folder: $displayName';
    final fileInfo = _formatFileInfo(item);
    return 'File: $displayName, $fileInfo';
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        HardwareKeyboard.instance.isAltPressed &&
        widget.onBack != null) {
      widget.onBack!();
      return KeyEventResult.handled;
    }
    if (widget.items.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < widget.items.length - 1) {
        setState(() {
          _focusedIndex++;
        });
        _cursorNames[widget.currentPath] = widget.items[_focusedIndex].name;
        _scrollToFocused();
        _announceCurrentItem();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() {
          _focusedIndex--;
        });
        _cursorNames[widget.currentPath] = widget.items[_focusedIndex].name;
        _scrollToFocused();
        _announceCurrentItem();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (_focusedIndex >= 0 && _focusedIndex < widget.items.length) {
        final item = widget.items[_focusedIndex];
        widget.onItemTap(item);
        if (item.isDirectory) widget.onDirectoryOpened?.call();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      setState(() {
        _focusedIndex = 0;
      });
      _scrollToFocused();
      _announceCurrentItem();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      setState(() {
        _focusedIndex = widget.items.length - 1;
      });
      _scrollToFocused();
      _announceCurrentItem();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToFocused() {
    if (!_scrollController.hasClients) return;
    // Use approximate item height for smooth scrolling
    const itemHeight = 52.0;
    final targetOffset = _focusedIndex * itemHeight;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final panelLabel = switch (widget.position) {
      PanelPosition.left => 'Left panel',
      PanelPosition.center => 'Center panel',
      PanelPosition.right => 'Right panel',
    };

    Widget panel;

    panel = Semantics(
      label: '$panelLabel, ${widget.items.length} items',
      child: FocusTraversalGroup(
        descendantsAreTraversable: false,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: _showKeyboardFocus && _focusNode.hasFocus
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              width: _showKeyboardFocus && _focusNode.hasFocus ? 2.0 : 0.5,
            ),
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: ListView.builder(
              key: ValueKey(_identity(widget.currentPath, widget.renamedPaths)),
              controller: _scrollController,
              itemCount: widget.items.length,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final index = widget.items.indexWhere(
                  (item) =>
                      _entryPath(widget.currentPath, item.name) == key.value,
                );
                return index < 0 ? null : index;
              },
              itemBuilder: (context, index) => _buildItem(context, index),
            ),
          ),
        ),
      ),
    );

    // A real directory owns its blank space. Child row gestures win the
    // gesture arena, keeping folder-entry actions targeted inside that folder.
    if (widget.onDirectoryContextMenu != null &&
        widget.dropTargetDirectory != null) {
      panel = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) => widget.onDirectoryContextMenu!(
          details.globalPosition,
          widget.dropTargetDirectory!,
        ),
        onLongPressEnd: (details) => widget.onDirectoryContextMenu!(
          details.globalPosition,
          widget.dropTargetDirectory!,
        ),
        child: panel,
      );
    }

    if (_supportsDesktopDrop &&
        widget.dropEnabled &&
        widget.dropTargetDirectory != null &&
        widget.onFilesDropped != null) {
      panel = DropTarget(
        onDragEntered: (_) => setState(() => _isDragOver = true),
        onDragExited: (_) => setState(() => _isDragOver = false),
        onDragDone: (details) {
          setState(() => _isDragOver = false);
          widget.onFilesDropped!(
            details.files.cast<XFile>(),
            widget.dropTargetDirectory!,
          );
        },
        enable: widget.dropEnabled,
        child: Stack(
          children: [panel, if (_isDragOver) _buildPanelDragOverlay(context)],
        ),
      );
    }

    return Listener(
      onPointerDown: (_) => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: panel,
      ),
    );
  }

  Widget _buildPanelDragOverlay(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Semantics(
          label: 'Drop file into ${widget.dropTargetDirectory}',
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: ExcludeSemantics(
                    child: Text(
                      'Drop into ${widget.dropTargetDirectory}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = widget.items[index];
    final isSelected = item == widget.selectedItem;
    final isKeyboardFocused =
        _showKeyboardFocus && _focusNode.hasFocus && index == _focusedIndex;

    String displayName = item.name;
    if (displayName.endsWith('/')) {
      displayName = displayName.substring(0, displayName.length - 1);
    }

    final isParentDir = item.name == '..';

    final icon = isParentDir
        ? Icons.folder_open
        : item.isDirectory
        ? Icons.folder
        : _getFileIcon(item.name);

    final isJsonPreset =
        !item.isDirectory && item.name.toLowerCase().endsWith('.json');

    final iconColor = isParentDir
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)
        : item.isDirectory
        ? Theme.of(context).colorScheme.primary
        : isJsonPreset
        ? Theme.of(context).colorScheme.tertiary
        : Theme.of(context).colorScheme.secondary;

    final fileInfo = !item.isDirectory ? _formatFileInfo(item) : null;

    Widget tile = Container(
      foregroundDecoration: isKeyboardFocused
          ? BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: ExcludeFocus(
        child: ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: fileInfo != null
              ? Text(
                  fileInfo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                )
              : null,
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
          onTap: () {
            setState(() {
              _focusedIndex = index;
            });
            _cursorNames[widget.currentPath] = item.name;
            widget.onItemTap(item);
          },
          dense: true,
        ),
      ),
    );

    if (!isParentDir && widget.onContextMenu != null) {
      tile = GestureDetector(
        onSecondaryTapUp: (details) {
          setState(() => _focusedIndex = index);
          _cursorNames[widget.currentPath] = item.name;
          widget.onContextMenu!(
            item,
            details.globalPosition,
            widget.currentPath,
          );
        },
        onLongPressEnd: (details) {
          widget.onContextMenu!(
            item,
            details.globalPosition,
            widget.currentPath,
          );
        },
        child: tile,
      );
    }

    return KeyedSubtree(
      key: ValueKey(_entryPath(widget.currentPath, item.name)),
      child: tile,
    );
  }

  static String _formatFileInfo(DirectoryEntry entry) {
    final size = _formatFileSize(entry.size);
    final dateTime = _formatFatDateTime(entry.date, entry.time);
    if (dateTime != null) return '$size · $dateTime';
    return size;
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
}
