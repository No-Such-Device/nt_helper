import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/chat/ui/chat_panel.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/algorithm_clipboard_service.dart';
import 'package:nt_helper/ui/add_algorithm_screen.dart';
import 'package:nt_helper/constants.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show AlgorithmInfo, DisplayMode;

import 'package:nt_helper/ui/widgets/floating_video_overlay.dart';
import 'package:nt_helper/cubit/video_frame_cubit.dart';
import 'package:nt_helper/models/preset_action.dart';
import 'package:nt_helper/ui/widgets/preset_browser_dialog.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';

import 'package:nt_helper/ui/performance_screen.dart';
import 'package:nt_helper/ui/widgets/rename_preset_dialog.dart';
import 'package:nt_helper/ui/widgets/rename_slot_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/consolidate_buses_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_controller.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/core/routing/bus_flow_solver.dart';
import 'package:nt_helper/core/routing/node_layout_algorithm.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';
import 'package:nt_helper/services/wave_cache_maintenance_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

import 'package:nt_helper/ui/cpu_monitor_widget.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_page.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/poly_multisample/poly_samples_screen.dart';
import 'package:nt_helper/ui/plugin_gallery_screen.dart';
import 'package:nt_helper/ui/ntx_8cv/ntx_8cv_screen.dart';
import 'package:nt_helper/ui/template_manager/current_preset_template_source.dart';
import 'package:nt_helper/ui/template_manager/template_manager_screen.dart';
import 'package:nt_helper/ui/widgets/shortcut_help_overlay.dart';
import 'package:nt_helper/ui/widgets/shift_click_gesture_recognizer.dart';
import 'package:nt_helper/ui/widgets/clipboard_selectable_tab.dart';

import 'package:nt_helper/util/extensions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/widgets/algorithm_list_view.dart';
import 'package:nt_helper/ui/widgets/algorithm_decoration_button.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/disting_version.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:nt_helper/ui/widgets/mcp_status_indicator.dart';
import 'package:nt_helper/ui/widgets/debug_panel.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/services/debug_service.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';
import 'package:nt_helper/ui/widgets/app_update_banner.dart';
import 'package:nt_helper/ui/widgets/app_update_dialog.dart';
import 'package:nt_helper/ui/widgets/contextual_help_bar.dart';
import 'package:nt_helper/ui/widgets/wave_cache_troubleshooting_dialog.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/app_update_service.dart';
import 'package:nt_helper/utils/build_config.dart';

enum EditMode { parameters, routing, both }

typedef _AlgorithmControllerSectionsEntry = ({
  String guid,
  AlgorithmControllerSectionController controller,
});

/// Help text for algorithm name interactions
const String _algorithmNameHelpText =
    'Double-click: Focus algorithm UI  •  Long-press: Rename algorithm';

class SynchronizedScreen extends StatefulWidget {
  final List<Slot> slots;
  final List<AlgorithmInfo> algorithms;
  final List<String> units;
  final String presetName;
  final bool isDirty;
  final String distingVersion;
  final FirmwareVersion firmwareVersion;
  final Uint8List? screenshot;
  final bool loading;
  final PlatformInteractionService? platformService;

  const SynchronizedScreen({
    super.key,
    required this.slots,
    required this.algorithms,
    required this.units,
    required this.presetName,
    this.isDirty = false,
    required this.distingVersion,
    required this.firmwareVersion,
    required this.screenshot,
    required this.loading,
    this.platformService,
  });

  @override
  State<SynchronizedScreen> createState() => _SynchronizedScreenState();
}

class _SynchronizedScreenState extends State<SynchronizedScreen>
    with TickerProviderStateMixin {
  late final PlatformInteractionService _platformService;
  final RoutingEditorController _editorController = RoutingEditorController();
  final KeyBindingService _keyBindingService = KeyBindingService();
  RoutingEditorViewMode _routingViewMode = RoutingEditorViewMode.canvas;
  final FocusNode _screenFocusNode = FocusNode();
  late int _selectedIndex;
  late TabController _tabController;
  EditMode _currentMode = EditMode.parameters;
  double _splitDividerPosition = SettingsService.defaultSplitDividerPosition;
  bool _showDebugPanel = true;
  bool _showContextualHelp = true;
  SlotEditorMode _parameterEditorMode = SlotEditorMode.standard;
  String? _contextualHelpText;
  AppRelease? _availableAppUpdate;
  AppUpdateService? _appUpdateService;
  RoutingEditorCubit? _routingEditorCubit;
  late final Widget _cachedRoutingCanvas = _buildRoutingCanvas();

  Widget _buildKeyedRoutingCanvas(RoutingEditorViewMode mode) {
    return KeyedSubtree(key: ValueKey(mode), child: _cachedRoutingCanvas);
  }

  StreamSubscription<RoutingEditorState>? _routingFocusSub;
  bool _isSyncingSelection = false;
  bool _isAddAlgorithmOpen = false;
  bool _isBrowsePresetsOpen = false;
  bool _isShortcutHelpOpen = false;
  bool _isTemplateManagerOpen = false;
  bool _showChatPanel = false;
  bool _chatFocusRequested = false;
  double _chatPanelWidth = 360;
  ChatCubit? _chatCubit;
  final SectionParameterController _sectionController =
      SectionParameterController();
  final _algorithmControllerSections =
      <int, _AlgorithmControllerSectionsEntry>{};

  /// Slot indices selected via shift-click for the algorithm clipboard (Mod+C).
  /// A [ValueNotifier] so individual tab indicators can rebuild without
  /// tearing down the in-flight tap gesture that toggled them. Persisted
  /// across slot-list rebuilds until copied or cleared. Desktop-only.
  final ValueNotifier<Set<int>> _clipboardSelection = ValueNotifier<Set<int>>(
    <int>{},
  );

  @override
  void initState() {
    super.initState();
    _platformService = widget.platformService ?? PlatformInteractionService();
    _selectedIndex = 0;
    _tabController = TabController(length: widget.slots.length, vsync: this);
    _tabController.addListener(_handleTabSelection);

    // Initialize debug service in debug mode
    if (kDebugMode) {
      DebugService().initialize();
      _showDebugPanel = SettingsService().showDebugPanel;
    }

    // Initialize contextual help setting
    final settings = SettingsService();
    _showContextualHelp = settings.showContextualHelp;
    settings.contextualHelpEnabledNotifier.addListener(
      _handleContextualHelpSettingChanged,
    );

    // Initialize split divider position
    _splitDividerPosition = SettingsService().splitDividerPosition;

    // Initialize chat panel width
    _chatPanelWidth = SettingsService().chatPanelWidth;

    // Re-acquire focus when it drifts outside the screen's subtree
    // (e.g. after an inline text editor is removed from the tree)
    _screenFocusNode.addListener(_reclaimFocusIfLost);

    // Check for app updates on desktop
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      _checkForAppUpdate();
    }

    // Determine the new_valid_index based on the current _selectedIndex and the new slots length.
    int newValidIndex = _selectedIndex;

    if (widget.slots.isEmpty) {
      newValidIndex = 0;
    } else {
      if (newValidIndex >= widget.slots.length) {
        newValidIndex = widget.slots.length - 1;
      }
      // Ensure index is not negative (shouldn't happen with current logic elsewhere but good safeguard)
      if (newValidIndex < 0) {
        newValidIndex = 0;
      }
    }

    // If the state variable _selectedIndex needs to be updated for other parts of the UI or internal logic.
    if (_selectedIndex != newValidIndex) {
      setState(() {
        _selectedIndex = newValidIndex;
      });
    }

    // Set the TabController's index to the new_valid_index that was just calculated.
    _tabController.index = newValidIndex;
  }

  void _reclaimFocusIfLost() {
    if (!_screenFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_reclaimFocusAfterFrame());
      });
    }
  }

  Future<void> _reclaimFocusAfterFrame() async {
    if (!mounted || _screenFocusNode.hasFocus) return;

    // Don't steal focus when a dialog/bottom sheet/pushed screen is active
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    // Don't steal focus from text fields (e.g. in non-route overlays)
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
        null) {
      return;
    }

    if (Platform.isWindows) {
      final mainWindowFocused = await windowManager.isFocused();
      if (!mainWindowFocused) {
        if (kDebugMode) {
          debugPrint(
            '[VIDEO_POPUP_DART] SynchronizedScreen focus reclaim skipped: '
            'main window is not focused',
          );
        }
        return;
      }
    }

    if (mounted && !_screenFocusNode.hasFocus) {
      _screenFocusNode.requestFocus();
    }
  }

  void _handleContextualHelpSettingChanged() {
    final enabled = SettingsService().contextualHelpEnabledNotifier.value;
    if (!mounted || _showContextualHelp == enabled) return;
    setState(() {
      _showContextualHelp = enabled;
      if (!enabled) {
        _contextualHelpText = null;
      }
    });
  }

  @override
  void dispose() {
    SettingsService().contextualHelpEnabledNotifier.removeListener(
      _handleContextualHelpSettingChanged,
    );
    _screenFocusNode.removeListener(_reclaimFocusIfLost);
    _screenFocusNode.dispose();
    _routingFocusSub?.cancel();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _routingEditorCubit?.close();
    _chatCubit?.close();
    _sectionController.dispose();
    for (final entry in _algorithmControllerSections.values) {
      entry.controller.dispose();
    }
    _algorithmControllerSections.clear();
    _clipboardSelection.dispose();
    super.dispose();
  }

  ChatCubit _getOrCreateChatCubit(DistingCubit distingCubit) {
    if (_chatCubit != null) return _chatCubit!;
    final memoryService = MemoryService();
    return _chatCubit = ChatCubit(
      toolRegistry: ToolRegistry(distingCubit, memoryService: memoryService),
      memoryService: memoryService,
    );
  }

  void _toggleChatPanel() {
    setState(() {
      _showChatPanel = !_showChatPanel;
      _chatFocusRequested = _showChatPanel;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      _showChatPanel ? 'Chat panel opened' : 'Chat panel closed',
      TextDirection.ltr,
    );
    if (_chatFocusRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _chatFocusRequested = false);
      });
    }
  }

  @override
  void didUpdateWidget(SynchronizedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _discardStaleAlgorithmControllerSections();
    if (widget.slots.length != oldWidget.slots.length) {
      _tabController.dispose();
      _tabController = TabController(length: widget.slots.length, vsync: this);
      _tabController.addListener(_handleTabSelection);
      // Clamp selectedIndex into valid range [0, slots.length-1] (or 0 if no slots).
      final int maxIndex = widget.slots.isEmpty ? 0 : widget.slots.length - 1;
      int newIndex = _selectedIndex.clamp(0, maxIndex);
      // Drop any clipboard selection entries that no longer map to a slot.
      if (widget.slots.isEmpty) {
        _clipboardSelection.value = <int>{};
      } else {
        final next = _clipboardSelection.value
            .where((i) => i < widget.slots.length)
            .toSet();
        if (next.length != _clipboardSelection.value.length) {
          _clipboardSelection.value = next;
        }
      }
      if (newIndex != _selectedIndex) {
        setState(() {
          _selectedIndex = newIndex;
        });
      }
      _tabController.index = newIndex;
    }
  }

  AlgorithmControllerSectionController _algorithmControllerSectionsFor(
    int slotIndex,
    Slot slot,
  ) {
    final existing = _algorithmControllerSections[slotIndex];
    if (existing != null && existing.guid == slot.algorithm.guid) {
      return existing.controller;
    }
    if (existing != null) {
      _algorithmControllerSections.remove(slotIndex);
      _disposeAlgorithmControllerSectionsAfterFrame(existing.controller);
    }

    final controller = AlgorithmControllerSectionController(
      initiallyCollapsed: SettingsService().startPagesCollapsed,
    );
    _algorithmControllerSections[slotIndex] = (
      guid: slot.algorithm.guid,
      controller: controller,
    );
    return controller;
  }

  void _discardStaleAlgorithmControllerSections() {
    final staleIndices = _algorithmControllerSections.entries
        .where(
          (entry) =>
              entry.key >= widget.slots.length ||
              widget.slots[entry.key].algorithm.guid != entry.value.guid,
        )
        .map((entry) => entry.key)
        .toList();
    for (final slotIndex in staleIndices) {
      final removed = _algorithmControllerSections.remove(slotIndex);
      if (removed != null) {
        _disposeAlgorithmControllerSectionsAfterFrame(removed.controller);
      }
    }
  }

  void _disposeAlgorithmControllerSectionsAfterFrame(
    AlgorithmControllerSectionController controller,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  void _handleTabSelection() {
    if (_tabController.index != _selectedIndex) {
      setState(() {
        _selectedIndex = _tabController.index;
      });
      _syncSelectionToRouting(_selectedIndex);
      if (!_tabController.indexIsChanging &&
          _selectedIndex < widget.slots.length) {
        final slot = widget.slots[_selectedIndex];
        final name = slot.algorithm.name;
        SemanticsService.sendAnnouncement(
          WidgetsBinding.instance.platformDispatcher.views.first,
          'Slot ${_selectedIndex + 1}: $name',
          TextDirection.ltr,
        );
      }
    }
  }

  Future<void> _checkForAppUpdate() async {
    _appUpdateService ??= AppUpdateService();
    final release = await _appUpdateService!.checkForUpdate();
    if (!mounted || release == null) return;

    final settings = SettingsService();
    final dismissed = settings.dismissedUpdateVersion;
    if (dismissed == release.version) return;

    setState(() => _availableAppUpdate = release);
  }

  void _dismissAppUpdate() {
    final version = _availableAppUpdate?.version;
    if (version != null) {
      SettingsService().setDismissedUpdateVersion(version);
    }
    setState(() => _availableAppUpdate = null);
  }

  void _showAppUpdateDialog(AppRelease release) {
    _appUpdateService ??= AppUpdateService();
    showDialog(
      context: context,
      builder: (ctx) =>
          AppUpdateDialog(release: release, updateService: _appUpdateService!),
    );
  }

  RoutingEditorCubit _getOrCreateRoutingCubit(DistingCubit distingCubit) {
    if (_routingEditorCubit == null) {
      _routingEditorCubit = RoutingEditorCubit(distingCubit);
      _routingEditorCubit!.injectLayoutAlgorithm(NodeLayoutAlgorithm());
      _routingFocusSub = _routingEditorCubit!.stream.listen(
        _onRoutingStateChanged,
      );
    }
    return _routingEditorCubit!;
  }

  void _onRoutingStateChanged(RoutingEditorState routingState) {
    if (_isSyncingSelection) return;
    if (routingState is! RoutingEditorStateLoaded) return;

    final focusedIds = routingState.focusedAlgorithmIds;
    if (focusedIds.length != 1) return;

    final focusedId = focusedIds.first;
    final algorithm = routingState.algorithms
        .where((a) => a.id == focusedId)
        .firstOrNull;
    if (algorithm == null) return;

    final slotIndex = algorithm.index;
    if (slotIndex == _selectedIndex) return;
    if (slotIndex < 0 || slotIndex >= widget.slots.length) return;

    _isSyncingSelection = true;
    setState(() {
      _selectedIndex = slotIndex;
      _tabController.animateTo(slotIndex);
    });
    _isSyncingSelection = false;
  }

  static final _digitKeyToPageIndex = {
    LogicalKeyboardKey.digit1: 0,
    LogicalKeyboardKey.digit2: 1,
    LogicalKeyboardKey.digit3: 2,
    LogicalKeyboardKey.digit4: 3,
    LogicalKeyboardKey.digit5: 4,
    LogicalKeyboardKey.digit6: 5,
    LogicalKeyboardKey.digit7: 6,
    LogicalKeyboardKey.digit8: 7,
    LogicalKeyboardKey.digit9: 8,
    LogicalKeyboardKey.digit0: 9,
  };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (_isTextEditingFocused()) return KeyEventResult.ignored;

    // Only handle bare digit keys (no modifiers held)
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final hasModifier = pressed.any(
      (k) =>
          k == LogicalKeyboardKey.controlLeft ||
          k == LogicalKeyboardKey.controlRight ||
          k == LogicalKeyboardKey.metaLeft ||
          k == LogicalKeyboardKey.metaRight ||
          k == LogicalKeyboardKey.altLeft ||
          k == LogicalKeyboardKey.altRight,
    );
    if (hasModifier) return KeyEventResult.ignored;

    final pageIndex = _digitKeyToPageIndex[event.logicalKey];
    if (pageIndex != null && _currentMode != EditMode.routing) {
      _sectionController.goToPage(_selectedIndex, pageIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isTextEditingFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _syncSelectionToRouting(int slotIndex) {
    if (_isSyncingSelection) return;
    _isSyncingSelection = true;
    _routingEditorCubit?.setFocusedAlgorithmBySlotIndex(slotIndex);
    _isSyncingSelection = false;
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;
    final effectiveRoutingViewMode = MediaQuery.of(context).accessibleNavigation
        ? RoutingEditorViewMode.list
        : _routingViewMode;
    final cubit = context.read<DistingCubit>();
    final routingCubit = _getOrCreateRoutingCubit(cubit);

    final isOffline = switch (cubit.state) {
      DistingStateSynchronized(offline: final o) => o,
      _ => false,
    };

    Widget scaffold;

    // Fall back to single mode if split-screen conditions aren't met
    final screenWidth = MediaQuery.of(context).size.width;
    if (_currentMode == EditMode.both && !_canShowSplitScreen(screenWidth)) {
      _currentMode = EditMode.parameters;
    }

    final workspaceIndex = _currentMode == EditMode.routing ? 1 : 0;

    // Use a conditional widget based on screen width
    if (isWideScreen && widget.slots.isNotEmpty) {
      // Wide screen layout with vertical list
      scaffold = Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: _buildAppBar(context, isWideScreen),
        body: Column(
          children: [
            Expanded(
              child: _currentMode == EditMode.both
                  ? _buildSplitView()
                  : IndexedStack(
                      index: workspaceIndex,
                      children: [
                        _buildWideScreenBody(),
                        _buildKeyedRoutingCanvas(effectiveRoutingViewMode),
                      ],
                    ),
            ),
            AppUpdateBanner(
              release: _availableAppUpdate,
              onWhatsNew: () {
                if (_availableAppUpdate != null) {
                  _showAppUpdateDialog(_availableAppUpdate!);
                }
              },
              onDismiss: _dismissAppUpdate,
            ),
            if (_showContextualHelp)
              ContextualHelpBar(helpText: _contextualHelpText),
            if (kDebugMode && _showDebugPanel)
              DebugPanel(
                onDismiss: () {
                  setState(() {
                    _showDebugPanel = false;
                  });
                  SettingsService().setShowDebugPanel(false);
                },
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
        floatingActionButton: _buildFloatingActionButton(),
        bottomNavigationBar: _buildBottomAppBar(),
      );
    } else {
      // Default layout with TabBar
      scaffold = Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: _buildAppBar(context, isWideScreen),
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: workspaceIndex,
                children: [
                  _buildBody(),
                  _buildKeyedRoutingCanvas(effectiveRoutingViewMode),
                ],
              ),
            ),
            AppUpdateBanner(
              release: _availableAppUpdate,
              onWhatsNew: () {
                if (_availableAppUpdate != null) {
                  _showAppUpdateDialog(_availableAppUpdate!);
                }
              },
              onDismiss: _dismissAppUpdate,
            ),
            if (_showContextualHelp)
              ContextualHelpBar(helpText: _contextualHelpText),
            if (kDebugMode && _showDebugPanel)
              DebugPanel(
                onDismiss: () {
                  setState(() {
                    _showDebugPanel = false;
                  });
                  SettingsService().setShowDebugPanel(false);
                },
              ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
        floatingActionButton: _buildFloatingActionButton(),
        bottomNavigationBar: _buildBottomAppBar(),
      );
    }

    return Shortcuts(
      shortcuts: _keyBindingService.globalShortcuts,
      child: Actions(
        actions: _keyBindingService.buildGlobalActions(
          onSavePreset: () {
            cubit.savePreset();
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Preset saved',
              TextDirection.ltr,
            );
          },
          onNewPreset: () => _handleNewPresetShortcut(cubit),
          onBrowsePresets: () =>
              widget.loading || isOffline ? null : _handleBrowsePresets(cubit),
          onAddAlgorithm: () => _handleAddAlgorithmShortcut(cubit),
          onRefresh: () {
            if (!widget.loading && !isOffline) {
              cubit.refresh();
              SemanticsService.sendAnnouncement(
                View.of(context),
                'Refreshing',
                TextDirection.ltr,
              );
            }
          },
          onShowShortcutHelp: () => _handleShowShortcutHelp(),
          onOpenTemplateManager: () => _handleOpenTemplateManagerShortcut(),
          onCopyAlgorithms: () => _handleCopyAlgorithmsToClipboard(cubit),
          onPasteAlgorithms: () => _handlePasteAlgorithmsFromClipboard(cubit),
          onClearAlgorithmSelection: _handleClearAlgorithmSelection,
          onSwitchToParameters: () {
            setState(() => _currentMode = EditMode.parameters);
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Switched to Parameters mode',
              TextDirection.ltr,
            );
          },
          onSwitchToRouting: () {
            setState(() => _currentMode = EditMode.routing);
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Switched to Routing mode',
              TextDirection.ltr,
            );
          },
          onSwitchToBoth: () {
            final screenWidth = MediaQuery.of(context).size.width;
            if (_canShowSplitScreen(screenWidth)) {
              setState(() => _currentMode = EditMode.both);
              SemanticsService.sendAnnouncement(
                View.of(context),
                'Switched to Split View mode',
                TextDirection.ltr,
              );
            }
          },
          onPreviousSlot: () {
            if (widget.slots.isNotEmpty && _selectedIndex > 0) {
              final newIndex = _selectedIndex - 1;
              setState(() {
                _selectedIndex = newIndex;
                _tabController.animateTo(newIndex);
              });
              _syncSelectionToRouting(newIndex);
              SemanticsService.sendAnnouncement(
                View.of(context),
                'Slot ${newIndex + 1}: ${widget.slots[newIndex].algorithm.name} selected',
                TextDirection.ltr,
              );
            }
          },
          onNextSlot: () {
            if (widget.slots.isNotEmpty &&
                _selectedIndex < widget.slots.length - 1) {
              final newIndex = _selectedIndex + 1;
              setState(() {
                _selectedIndex = newIndex;
                _tabController.animateTo(newIndex);
              });
              _syncSelectionToRouting(newIndex);
              SemanticsService.sendAnnouncement(
                View.of(context),
                'Slot ${newIndex + 1}: ${widget.slots[newIndex].algorithm.name} selected',
                TextDirection.ltr,
              );
            }
          },
          onToggleChat: _toggleChatPanel,
        ),
        child: Focus(
          focusNode: _screenFocusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: BlocProvider.value(
            value: routingCubit,
            child: _showChatPanel
                ? BlocProvider.value(
                    value: _getOrCreateChatCubit(cubit),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxChatWidth = (constraints.maxWidth * 0.5).clamp(
                          280.0,
                          800.0,
                        );
                        final clampedWidth = _chatPanelWidth.clamp(
                          280.0,
                          maxChatWidth,
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: FocusTraversalGroup(child: scaffold),
                            ),
                            Semantics(
                              label: 'Chat panel resize handle',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeColumn,
                                child: GestureDetector(
                                  onHorizontalDragUpdate: (details) {
                                    setState(() {
                                      _chatPanelWidth =
                                          (_chatPanelWidth - details.delta.dx)
                                              .clamp(280.0, maxChatWidth);
                                    });
                                  },
                                  onHorizontalDragEnd: (_) {
                                    SettingsService().setChatPanelWidth(
                                      _chatPanelWidth,
                                    );
                                  },
                                  child: Container(
                                    width: 4,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: clampedWidth,
                              child: FocusTraversalGroup(
                                child: ChatPanel(
                                  requestInputFocus: _chatFocusRequested,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                : scaffold,
          ),
        ),
      ),
    );
  }

  Future<void> _handleShowShortcutHelp() async {
    if (_isShortcutHelpOpen) return;
    _isShortcutHelpOpen = true;
    try {
      await showDialog(
        context: context,
        builder: (_) => const ShortcutHelpOverlay(),
      );
    } finally {
      _isShortcutHelpOpen = false;
    }
  }

  void _handleNewPresetShortcut(DistingCubit cubit) {
    if (widget.loading) return;
    cubit.newPreset();
    SemanticsService.sendAnnouncement(
      View.of(context),
      'New preset created',
      TextDirection.ltr,
    );
  }

  Future<void> _handleAddAlgorithmShortcut(DistingCubit cubit) async {
    if (_isAddAlgorithmOpen) return;
    setState(() {
      _isAddAlgorithmOpen = true;
    });
    try {
      final view = View.of(context);
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BlocProvider.value(
            value: cubit,
            child: const AddAlgorithmScreen(),
          ),
        ),
      );

      if (result != null && result is Map) {
        try {
          await cubit.onAlgorithmSelected(
            result['algorithm'],
            result['specValues'],
            addBypassed: result['addBypassed'] == true,
          );
          SemanticsService.sendAnnouncement(
            view,
            'Algorithm added',
            TextDirection.ltr,
          );
        } on AlgorithmAddFailedException {
          _showAlgorithmAddFailedNotification();
        } on AlgorithmAddBypassFailedException {
          _showAlgorithmAddBypassFailedNotification();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAddAlgorithmOpen = false;
        });
      } else {
        _isAddAlgorithmOpen = false;
      }
    }
  }

  void _showAlgorithmAddFailedNotification() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(algorithmAddFailedMessage),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      algorithmAddFailedMessage,
      TextDirection.ltr,
    );
  }

  void _showAlgorithmAddBypassFailedNotification() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(algorithmAddBypassFailedMessage),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      algorithmAddBypassFailedMessage,
      TextDirection.ltr,
    );
  }

  Future<void> _handleBrowsePresets(DistingCubit cubit) async {
    if (_isBrowsePresetsOpen) return;
    _isBrowsePresetsOpen = true;
    try {
      final currentState = cubit.state;
      if (currentState is DistingStateSynchronized && context.mounted) {
        final midiManager = cubit.disting();
        if (midiManager != null) {
          final prefs = await SharedPreferences.getInstance();
          if (!mounted) return;
          final presetInfo = await showDialog(
            context: context,
            builder: (context) => BlocProvider(
              create: (context) =>
                  PresetBrowserCubit(midiManager: midiManager, prefs: prefs),
              child: PresetBrowserDialog(
                distingCubit: cubit,
                firmwareVersion: currentState.firmwareVersion,
              ),
            ),
          );
          if (presetInfo != null && presetInfo is Map) {
            final sdCardPath = presetInfo['sdCardPath'];
            final action = presetInfo['action'] as PresetAction?;
            if (sdCardPath != null && sdCardPath.isNotEmpty && action != null) {
              switch (action) {
                case PresetAction.load:
                  cubit.loadPreset(sdCardPath, false);
                  break;
                case PresetAction.append:
                  break;
                case PresetAction.export:
                  break;
              }
            }
          }
        }
      }
    } finally {
      _isBrowsePresetsOpen = false;
    }
  }

  Widget _buildSplitView() {
    const double dividerWidth = 8.0;
    const double minPaneWidth = 500.0;
    final effectiveRoutingViewMode = MediaQuery.of(context).accessibleNavigation
        ? RoutingEditorViewMode.list
        : _routingViewMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - dividerWidth;
        final minFraction = minPaneWidth / availableWidth;
        final maxFraction = (1.0 - minFraction).clamp(minFraction, 1.0);
        final clampedPosition = _splitDividerPosition.clamp(
          minFraction,
          maxFraction,
        );
        final leftFlex = (clampedPosition * 1000).round();
        final rightFlex = ((1.0 - clampedPosition) * 1000).round();

        return Row(
          children: [
            Expanded(flex: leftFlex, child: _buildWideScreenBody()),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final newPosition =
                        _splitDividerPosition +
                        details.delta.dx / availableWidth;
                    _splitDividerPosition = newPosition.clamp(
                      minFraction,
                      maxFraction,
                    );
                  });
                },
                onHorizontalDragEnd: (_) {
                  SettingsService().setSplitDividerPosition(
                    _splitDividerPosition,
                  );
                },
                child: Container(
                  width: dividerWidth,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: rightFlex,
              child: _buildKeyedRoutingCanvas(effectiveRoutingViewMode),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWideScreenBody() {
    return Row(
      children: [
        // Left side algorithm list
        Container(
          width: 250,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: AlgorithmListView(
            slots: widget.slots,
            selectedIndex: _selectedIndex,
            clipboardSelection: _clipboardSelection,
            onToggleClipboardSelection: widget.loading
                ? null
                : (index) {
                    // Multi-select is desktop-only (the side list only shows
                    // on wide-screen / desktop). Toggle without setState: the
                    // indicator leaf listens via ValueListenableBuilder.
                    final next = Set<int>.of(_clipboardSelection.value);
                    if (!next.add(index)) {
                      next.remove(index);
                    }
                    _clipboardSelection.value = next;
                  },
            onSelectionChanged: (index) {
              setState(() {
                _selectedIndex = index;
                _tabController.animateTo(index);
              });
              _syncSelectionToRouting(index);
            },
            onHelpTextChanged: _showContextualHelp
                ? (text) => setState(() => _contextualHelpText = text)
                : null,
            onMoveUp: widget.loading
                ? null
                : (index) async {
                    final cubit = context.read<DistingCubit>();
                    final newIndex = await cubit.moveAlgorithmUp(index);
                    setState(() {
                      _selectedIndex = newIndex;
                    });
                    _tabController.animateTo(newIndex);
                    return newIndex;
                  },
            onMoveDown: widget.loading
                ? null
                : (index) async {
                    final cubit = context.read<DistingCubit>();
                    final currentState = cubit.state;
                    int slotCount = 0;
                    if (currentState is DistingStateSynchronized) {
                      slotCount = currentState.slots.length;
                    }
                    if (index < slotCount - 1) {
                      final newIndex = await cubit.moveAlgorithmDown(index);
                      setState(() {
                        _selectedIndex = newIndex;
                      });
                      _tabController.animateTo(newIndex);
                      return newIndex;
                    }
                    return index;
                  },
            onDelete: widget.loading
                ? null
                : (index) {
                    final cubit = context.read<DistingCubit>();
                    cubit.onRemoveAlgorithm(index);
                  },
          ),
        ),
        // Right side content
        Expanded(
          child: widget.slots.isNotEmpty
              ? IndexedStack(
                  index: _selectedIndex,
                  children: widget.slots.mapIndexed((index, slot) {
                    return SlotDetailView(
                      key: ValueKey("$index - ${slot.algorithm.guid}"),
                      slot: slot,
                      slotIndex: index,
                      units: widget.units,
                      firmwareVersion: widget.firmwareVersion,
                      sectionController: _sectionController,
                      algorithmControllerSections:
                          _algorithmControllerSectionsFor(index, slot),
                      editorMode: _parameterEditorMode,
                      onEditorModeChanged: _setParameterEditorMode,
                      editorModeEnabled: !widget.loading,
                    );
                  }).toList(),
                )
              : Center(
                  child: Text(
                    "No algorithms",
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFloatingActionButton() {
    return Builder(
      builder: (context) {
        return FloatingActionButton.small(
          tooltip: "Add Algorithm to Preset",
          onPressed: _isAddAlgorithmOpen
              ? null
              : () => _handleAddAlgorithmShortcut(context.read<DistingCubit>()),
          child: Icon(
            Icons.add_circle_rounded,
            semanticLabel: 'Add Algorithm to Preset',
          ),
        );
      },
    );
  }

  Widget _buildRoutingCanvas() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header with routing controls
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
                builder: (context, state) {
                  final isMobile = _platformService.isMobilePlatform();
                  final buttonStyle = isMobile
                      ? const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStatePropertyAll(EdgeInsets.all(8)),
                        )
                      : null;
                  final effectiveRoutingViewMode =
                      MediaQuery.of(context).accessibleNavigation
                      ? RoutingEditorViewMode.list
                      : _routingViewMode;
                  return Row(
                    children: [
                      // Zoom controls (canvas-only)
                      if (state is RoutingEditorStateLoaded &&
                          effectiveRoutingViewMode ==
                              RoutingEditorViewMode.canvas) ...[
                        IconButton(
                          onPressed: () =>
                              context.read<RoutingEditorCubit>().zoomOut(),
                          icon: const Icon(
                            Icons.zoom_out,
                            semanticLabel: 'Zoom out',
                          ),
                          tooltip: 'Zoom out (Ctrl/Cmd + -)',
                          style: buttonStyle,
                        ),
                        Container(
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 60 : 80,
                          ),
                          child: DropdownButton<double>(
                            value: _findClosestZoomLevel(state.zoomLevel),
                            onChanged: (value) {
                              if (value != null) {
                                context.read<RoutingEditorCubit>().setZoomLevel(
                                  value,
                                );
                              }
                            },
                            items: RoutingEditorCubit.availableZoomLevels.map((
                              zoom,
                            ) {
                              return DropdownMenuItem<double>(
                                value: zoom,
                                child: Text('${(zoom * 100).round()}%'),
                              );
                            }).toList(),
                            underline: const SizedBox.shrink(),
                            isDense: true,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              context.read<RoutingEditorCubit>().zoomIn(),
                          icon: const Icon(
                            Icons.zoom_in,
                            semanticLabel: 'Zoom in',
                          ),
                          tooltip: 'Zoom in (Ctrl/Cmd + +)',
                          style: buttonStyle,
                        ),
                        IconButton(
                          onPressed: () =>
                              context.read<RoutingEditorCubit>().resetZoom(),
                          icon: const Icon(
                            Icons.zoom_out_map,
                            semanticLabel: 'Reset zoom',
                          ),
                          tooltip: 'Reset zoom (100%)',
                          style: buttonStyle,
                        ),
                        SizedBox(width: isMobile ? 4 : 8),
                        Container(
                          height: 24,
                          width: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        SizedBox(width: isMobile ? 4 : 8),
                      ],
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          semanticLabel: 'Refresh Routing',
                        ),
                        style: buttonStyle,
                        onPressed: state.maybeWhen(
                          loaded:
                              (
                                deviceIoProfile,
                                physicalInputs,
                                physicalOutputs,
                                es5Inputs,
                                algorithms,
                                connections,
                                buses,
                                portOutputModes,
                                nodePositions,
                                zoomLevel,
                                panOffset,
                                isHardwareSynced,
                                isPersistenceEnabled,
                                lastSyncTime,
                                lastPersistTime,
                                lastError,
                                subState,
                                focusedAlgorithmIds,
                                cascadeScrollTarget,
                                auxBusUsage,
                                hasExtendedAuxBuses,
                              ) => () {
                                context
                                    .read<RoutingEditorCubit>()
                                    .refreshRouting();
                              },
                          orElse: () => null,
                        ),
                        tooltip: 'Refresh Routing',
                      ),
                      if (effectiveRoutingViewMode ==
                          RoutingEditorViewMode.canvas)
                        state.maybeWhen(
                          loaded:
                              (
                                deviceIoProfile,
                                physicalInputs,
                                physicalOutputs,
                                es5Inputs,
                                algorithms,
                                connections,
                                buses,
                                portOutputModes,
                                nodePositions,
                                zoomLevel,
                                panOffset,
                                isHardwareSynced,
                                isPersistenceEnabled,
                                lastSyncTime,
                                lastPersistTime,
                                lastError,
                                subState,
                                focusedAlgorithmIds,
                                cascadeScrollTarget,
                                auxBusUsage,
                                hasExtendedAuxBuses,
                              ) {
                                // Show loading during layout calculation
                                if (subState == SubState.syncing) {
                                  return IconButton(
                                    icon: const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    onPressed: null,
                                    tooltip: 'Calculating Layout...',
                                    style: buttonStyle,
                                  );
                                }

                                // Show normal layout button
                                return IconButton(
                                  icon: const Icon(
                                    Icons.auto_fix_high,
                                    semanticLabel: 'Apply Layout Algorithm',
                                  ),
                                  onPressed: () {
                                    context
                                        .read<RoutingEditorCubit>()
                                        .applyLayoutAlgorithm();
                                  },
                                  tooltip: 'Apply Layout Algorithm',
                                  style: buttonStyle,
                                );
                              },
                          orElse: () => const SizedBox.shrink(),
                        ),
                      // Optimize AUX Buses
                      state.maybeWhen(
                        loaded:
                            (
                              deviceIoProfile,
                              physicalInputs,
                              physicalOutputs,
                              es5Inputs,
                              algorithms,
                              connections,
                              buses,
                              portOutputModes,
                              nodePositions,
                              zoomLevel,
                              panOffset,
                              isHardwareSynced,
                              isPersistenceEnabled,
                              lastSyncTime,
                              lastPersistTime,
                              lastError,
                              subState,
                              focusedAlgorithmIds,
                              cascadeScrollTarget,
                              auxBusUsage,
                              hasExtendedAuxBuses,
                            ) {
                              return IconButton(
                                icon: const Icon(
                                  Icons.compress,
                                  semanticLabel: 'Optimize Buses',
                                ),
                                onPressed: () async {
                                  final cubit = context
                                      .read<RoutingEditorCubit>();
                                  final plan = cubit.buildConsolidationPlan();
                                  if (plan == null) {
                                    if (context.mounted) {
                                      _editorController.showError(
                                        'No AUX buses can be consolidated',
                                      );
                                    }
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  await showDialog(
                                    context: context,
                                    builder: (_) => ConsolidateBusesDialog(
                                      plan: plan,
                                      cubit: cubit,
                                    ),
                                  );
                                },
                                tooltip: 'Optimize AUX Buses',
                                style: buttonStyle,
                              );
                            },
                        orElse: () => const SizedBox.shrink(),
                      ),
                      state.maybeWhen(
                        loaded:
                            (
                              deviceIoProfile,
                              physicalInputs,
                              physicalOutputs,
                              es5Inputs,
                              algorithms,
                              connections,
                              buses,
                              portOutputModes,
                              nodePositions,
                              zoomLevel,
                              panOffset,
                              isHardwareSynced,
                              isPersistenceEnabled,
                              lastSyncTime,
                              lastPersistTime,
                              lastError,
                              subState,
                              focusedAlgorithmIds,
                              cascadeScrollTarget,
                              auxBusUsage,
                              hasExtendedAuxBuses,
                            ) {
                              final flowSolution = BusFlowSolver.fromAlgorithms(
                                algorithms,
                                deviceIoProfile: deviceIoProfile,
                              ).solve();
                              if (effectiveRoutingViewMode !=
                                      RoutingEditorViewMode.busLanes ||
                                  !flowSolution.reorderNeeded) {
                                return const SizedBox.shrink();
                              }
                              return IconButton(
                                icon: const Icon(
                                  Icons.alt_route,
                                  semanticLabel: 'Reorder Algorithms',
                                ),
                                onPressed: () async {
                                  await context
                                      .read<RoutingEditorCubit>()
                                      .autoSolveFlow();
                                },
                                tooltip: 'Reorder algorithms to fix bus flow',
                                style: buttonStyle,
                              );
                            },
                        orElse: () => const SizedBox.shrink(),
                      ),
                      // Checkpoint
                      _buildCheckpointButton(context, buttonStyle),
                      if (effectiveRoutingViewMode ==
                          RoutingEditorViewMode.canvas) ...[
                        // Center View
                        IconButton(
                          icon: const Icon(
                            Icons.center_focus_strong,
                            semanticLabel: 'Center View',
                          ),
                          onPressed: () => _editorController.fitToView(),
                          tooltip: 'Center View',
                          style: buttonStyle,
                        ),

                        // Share/Copy Nodes Image (tight bounds, 24px margin)
                        IconButton(
                          icon: Icon(
                            isMobile ? Icons.share : Icons.image_outlined,
                            semanticLabel: isMobile
                                ? 'Share Nodes Image'
                                : 'Copy Nodes Image',
                          ),
                          onPressed: () {
                            if (isMobile) {
                              _editorController.shareNodesImage();
                            } else {
                              _editorController.copyNodesImage();
                            }
                          },
                          tooltip: isMobile
                              ? 'Share Nodes Image'
                              : 'Copy Nodes Image',
                          style: buttonStyle,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Routing Canvas
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return RoutingEditorWidget(
                  controller: _editorController,
                  canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
                  showPhysicalPorts: true,
                  onViewModeChanged: (mode) {
                    if (!mounted) return;
                    setState(() => _routingViewMode = mode);
                  },
                  onConnectionCreated: (source, target) {
                    context.read<RoutingEditorCubit>().createConnection(
                      sourcePortId: source,
                      targetPortId: target,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _canShowSplitScreen(double width) {
    return !_platformService.isMobilePlatform() && width >= 1008;
  }

  Future<void> _openTemplateManager(BuildContext context) {
    final distingCubit = context.read<DistingCubit>();
    final metadataCubit = MetadataSyncCubit(
      distingCubit.database,
      distingCubit,
    );

    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TemplateManagerScreen(
          database: distingCubit.database,
          onApplyDevice: (template, selectedIndices) async {
            await metadataCubit.applyTemplateToDevice(
              template: template,
              templateSlotIndices: selectedIndices,
              manager: distingCubit.requireDisting(),
            );
            final state = metadataCubit.state;
            if (state case PresetLoadFailure(error: final error)) {
              throw StateError(error);
            }
          },
          onCancelDeviceApply: metadataCubit.cancelInjection,
          loadCurrentPresetSource: () async =>
              fullPresetDetailsFromDistingState(distingCubit.state),
        ),
      ),
    ).whenComplete(metadataCubit.close);
  }

  Future<void> _handleOpenTemplateManagerShortcut() async {
    if (_isTemplateManagerOpen) return;
    _isTemplateManagerOpen = true;
    try {
      await _openTemplateManager(context);
    } finally {
      _isTemplateManagerOpen = false;
    }
  }

  AlgorithmClipboardService _algorithmClipboardService(DistingCubit cubit) =>
      AlgorithmClipboardService(cubit.database);

  void _handleClearAlgorithmSelection() {
    if (_clipboardSelection.value.isEmpty) return;
    _clipboardSelection.value = <int>{};
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Cleared algorithm clipboard selection',
      TextDirection.ltr,
    );
  }

  Future<void> _handleCopyAlgorithmsToClipboard(DistingCubit cubit) async {
    final state = cubit.state;
    if (state is! DistingStateSynchronized) return;

    final selected = _clipboardSelection.value.toList()..sort();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select slot tabs with shift-click, then press Mod+C to copy.',
          ),
        ),
      );
      return;
    }

    try {
      final copied = await _algorithmClipboardService(
        cubit,
      ).copyFromDistingState(state, selected);
      if (copied > 0) {
        // Clear the on-screen selection now that it has been snapshotted.
        _clipboardSelection.value = <int>{};
      }
      if (copied == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No slots were copied.')));
        return;
      }
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Copied ${describeClipboardCount(copied)} to clipboard',
        TextDirection.ltr,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copy failed: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handlePasteAlgorithmsFromClipboard(DistingCubit cubit) async {
    final state = cubit.state;
    if (state is! DistingStateSynchronized) return;
    if (widget.loading) return;

    final service = _algorithmClipboardService(cubit);
    final count = await service.clipboardSlotCount();
    if (count == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(algorithmClipboardEmptyMessage)),
      );
      return;
    }

    if (!mounted) return;
    final metadataCubit = MetadataSyncCubit(cubit.database, cubit);
    try {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Pasting ${describeClipboardCount(count)} to end of preset',
        TextDirection.ltr,
      );
      await service.pasteToCurrentDevice(metadataCubit, cubit.requireDisting());
      final resultState = metadataCubit.state;
      if (!mounted) return;
      if (resultState case PresetLoadFailure(error: final error)) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else if (resultState case PresetLoadSuccess(message: _)) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Pasted ${describeClipboardCount(count)} to preset',
          TextDirection.ltr,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Paste failed: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      await metadataCubit.close();
    }
  }

  Widget _buildBottomAppBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    bool isWideScreen = screenWidth > 900;
    final showModeLabels = screenWidth > 1250;
    bool isMobile = _platformService.isMobilePlatform();
    final theme = Theme.of(context);
    final bottomBarTheme = BottomAppBarTheme.of(context);

    Widget buildBarContents() {
      return Row(
        children: [
          // Left side - Mode switcher
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: SegmentedButton<EditMode>(
              multiSelectionEnabled: true,
              emptySelectionAllowed: false,
              segments: [
                ButtonSegment(
                  value: EditMode.parameters,
                  label: showModeLabels ? const Text('Parameters') : null,
                  icon: const Icon(Icons.tune, semanticLabel: 'Parameters'),
                  tooltip: 'Parameters mode',
                ),
                ButtonSegment(
                  value: EditMode.routing,
                  label: showModeLabels ? const Text('Routing') : null,
                  icon: const Icon(
                    Icons.account_tree,
                    semanticLabel: 'Routing',
                  ),
                  tooltip: 'Routing mode',
                ),
              ],
              selected: _currentMode == EditMode.both
                  ? {EditMode.parameters, EditMode.routing}
                  : {_currentMode},
              onSelectionChanged: (Set<EditMode> modes) {
                setState(() {
                  final previousMode = _currentMode;
                  if (modes.length == 2 &&
                      modes.contains(EditMode.parameters) &&
                      modes.contains(EditMode.routing) &&
                      _canShowSplitScreen(screenWidth)) {
                    _currentMode = EditMode.both;
                  } else if (modes.length == 2) {
                    // Can't split - keep only the newly clicked one
                    final newMode = modes.firstWhere(
                      (m) =>
                          m !=
                          (previousMode == EditMode.both
                              ? EditMode.parameters
                              : previousMode),
                      orElse: () => modes.first,
                    );
                    _currentMode = newMode;
                  } else if (modes.length == 1) {
                    _currentMode = modes.first;
                  }
                });
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.comfortable,
              ),
            ),
          ),

          const SizedBox(width: 24),

          // Quick-action buttons for frequently used features
          BlocBuilder<DistingCubit, DistingState>(
            buildWhen: (previous, current) {
              final prevOffline =
                  previous is DistingStateSynchronized && previous.offline;
              final currOffline =
                  current is DistingStateSynchronized && current.offline;
              return prevOffline != currOffline;
            },
            builder: (context, state) {
              final isOffline = switch (state) {
                DistingStateSynchronized(offline: final o) => o,
                _ => false,
              };

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'File Browser',
                    icon: const Icon(
                      Icons.folder_open,
                      semanticLabel: 'File Browser',
                    ),
                    onPressed: widget.loading || isOffline
                        ? null
                        : () {
                            final cubit = context.read<DistingCubit>();
                            _handleBrowsePresets(cubit);
                          },
                  ),
                  IconButton(
                    tooltip: 'Template Manager',
                    icon: const Icon(
                      Icons.dashboard_customize,
                      semanticLabel: 'Template Manager',
                    ),
                    onPressed: widget.loading
                        ? null
                        : () => _openTemplateManager(context),
                  ),
                  IconButton(
                    tooltip: 'Video',
                    icon: const Icon(Icons.videocam, semanticLabel: 'Video'),
                    onPressed: widget.loading || isOffline
                        ? null
                        : () {
                            _showScreenshotOverlay(context);
                          },
                  ),
                  IconButton(
                    tooltip: 'Perform',
                    icon: const Icon(
                      Icons.library_music,
                      semanticLabel: 'Perform',
                    ),
                    onPressed: widget.loading
                        ? null
                        : () {
                            final cubit = context.read<DistingCubit>();
                            final midiListener = context
                                .read<MidiListenerCubit>();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MultiBlocProvider(
                                  providers: [
                                    BlocProvider.value(value: cubit),
                                    BlocProvider.value(value: midiListener),
                                  ],
                                  child: PerformanceScreen(units: widget.units),
                                ),
                              ),
                            );
                          },
                  ),
                  if (!kPlayStoreBuild)
                    IconButton(
                      tooltip: 'Plugin Manager',
                      icon: const Icon(
                        Icons.extension_rounded,
                        semanticLabel: 'Plugin Manager',
                      ),
                      onPressed: widget.loading
                          ? null
                          : () {
                              final distingCubit = context.read<DistingCubit>();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PluginGalleryScreen(
                                    distingCubit: distingCubit,
                                    database: distingCubit.database,
                                  ),
                                ),
                              );
                            },
                    ),
                  if (!isMobile)
                    IconButton(
                      tooltip: 'Samples',
                      icon: const Icon(Icons.piano, semanticLabel: 'Samples'),
                      onPressed: widget.loading
                          ? null
                          : () {
                              final distingCubit = context.read<DistingCubit>();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PolySamplesScreen(
                                    distingCubit: distingCubit,
                                  ),
                                ),
                              );
                            },
                    ),
                ],
              );
            },
          ),

          const Spacer(),

          // MCP server status indicator (desktop only)
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            ChangeNotifierProvider.value(
              value: McpServerService.instance,
              child: Consumer<McpServerService>(
                builder: (context, mcpService, child) {
                  return const McpStatusIndicator();
                },
              ),
            ),
          const SizedBox(width: 8),
          // Only show version on tablets and desktop, not mobile
          if (!isMobile)
            BlocBuilder<DistingCubit, DistingState>(
              buildWhen: (previous, current) {
                // Only rebuild when availableFirmwareUpdate changes
                final prevUpdate = previous is DistingStateSynchronized
                    ? previous.availableFirmwareUpdate
                    : null;
                final currUpdate = current is DistingStateSynchronized
                    ? current.availableFirmwareUpdate
                    : null;
                return prevUpdate != currUpdate;
              },
              builder: (context, state) {
                final updateAvailable = state is DistingStateSynchronized
                    ? state.availableFirmwareUpdate
                    : null;
                final isDesktop =
                    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Firmware update indicator (desktop only)
                    if (!kPlayStoreBuild &&
                        updateAvailable != null &&
                        isDesktop)
                      Tooltip(
                        message:
                            'Update available: v${updateAvailable.version}',
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_circle_up,
                            semanticLabel:
                                'Firmware update available: v${updateAvailable.version}',
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          onPressed: () {
                            final distingCubit = context.read<DistingCubit>();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FirmwareUpdateScreen(
                                  distingCubit: distingCubit,
                                ),
                              ),
                            );
                          },
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    if (!kPlayStoreBuild &&
                        updateAvailable != null &&
                        isDesktop)
                      const SizedBox(width: 4),
                    DistingVersion(
                      distingVersion: widget.distingVersion,
                      requiredVersion: Constants.requiredDistingVersion,
                      firmwareVersion: widget.firmwareVersion,
                      firmwareDate: widget.firmwareVersion.date,
                      onTap: kPlayStoreBuild
                          ? null
                          : isDesktop
                          ? () {
                              final distingCubit = context.read<DistingCubit>();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FirmwareUpdateScreen(
                                    distingCubit: distingCubit,
                                  ),
                                ),
                              );
                            }
                          : null,
                      onHelpTextChanged: _showContextualHelp && isDesktop
                          ? (text) => setState(() => _contextualHelpText = text)
                          : null,
                    ),
                  ],
                );
              },
            ),
          // CPU Monitor Widget - only in wide-screen mode
          if (isWideScreen) ...[
            const SizedBox(width: 16),
            CpuMonitorWidget(paused: _showChatPanel),
          ],
          // Spacer for FAB so it doesn't cover the version/CPU info
          const SizedBox(width: 80),
        ],
      );
    }

    // Do not use BottomAppBar here. Its Material 3 default notched shape reads
    // ScaffoldGeometry while hit-testing. During a route-pop transition that
    // can happen outside paint, poisoning Flutter's MouseTracker in debug mode
    // and leaving the desktop UI unable to receive any more mouse clicks.
    return Material(
      key: const ValueKey('main-bottom-action-bar'),
      color: bottomBarTheme.color ?? theme.colorScheme.surfaceContainer,
      elevation: bottomBarTheme.elevation ?? 3,
      shadowColor: bottomBarTheme.shadowColor ?? Colors.transparent,
      surfaceTintColor: bottomBarTheme.surfaceTintColor ?? Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: bottomBarTheme.height ?? 80,
          child: Padding(
            padding:
                bottomBarTheme.padding ??
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: buildBarContents(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.slots.isNotEmpty) {
      return TabBarView(
        controller: _tabController,
        children: widget.slots.mapIndexed((index, slot) {
          return SlotDetailView(
            key: ValueKey("$index - ${slot.algorithm.guid}"),
            slot: slot,
            slotIndex: index,
            units: widget.units,
            firmwareVersion: widget.firmwareVersion,
            sectionController: _sectionController,
            algorithmControllerSections: _algorithmControllerSectionsFor(
              index,
              slot,
            ),
            editorMode: _parameterEditorMode,
            onEditorModeChanged: _setParameterEditorMode,
            editorModeEnabled: !widget.loading,
          );
        }).toList(),
      );
    }
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Text(
          "No algorithms in preset. Tap the + button to add one.",
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, bool isWideScreen) {
    final cubit = context.read<DistingCubit>();
    return AppBar(
      title: const Text('NT Helper'),
      titleTextStyle: Theme.of(context).textTheme.titleLarge,
      actions: _buildAppBarActions(cubit),
      elevation: 0,
      scrolledUnderElevation: 0,
      notificationPredicate: (ScrollNotification notification) =>
          notification.depth == 1,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(
          72.0, // Consistent height for both modes
        ),
        child: Column(
          children: [
            _buildPresetInfoEditor(context), // The preset info
            // Always reserve space for tab bar to prevent jumping
            SizedBox(
              height: 32.0,
              child: !isWideScreen && _currentMode == EditMode.parameters
                  ? _buildTabBar(context)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(DistingCubit cubit) {
    final isOffline = switch (cubit.state) {
      DistingStateSynchronized(offline: final o) => o,
      _ => false,
    };

    return [
      // Refresh: Only disabled by loading OR offline
      IconButton(
        icon: const Icon(Icons.refresh_rounded, semanticLabel: 'Refresh'),
        tooltip: 'Refresh',
        onPressed: widget.loading || isOffline
            ? null
            : () {
                cubit.refresh();
              },
      ),
      if (widget.slots.isNotEmpty &&
          (isOffline || widget.firmwareVersion.hasAlgorithmVisualStyle))
        AlgorithmDecorationButton(
          key: const ValueKey('toolbar-algorithm-decoration'),
          slot: widget.slots[_selectedIndex],
          enabled: !widget.loading,
          tooltip: 'Decorate selected algorithm',
        ),
      // Mode-specific actions with AnimatedSwitcher
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 100),
        child: _buildModeSpecificActions(cubit),
      ),
      // Chat panel toggle (desktop only — side panel doesn't fit on mobile)
      if (!_platformService.isMobilePlatform())
        IconButton(
          icon: Icon(
            _showChatPanel ? Icons.chat_bubble : Icons.chat_bubble_outline,
            semanticLabel: _showChatPanel
                ? 'Hide chat panel'
                : 'Show chat panel',
          ),
          tooltip: _showChatPanel ? 'Hide chat' : 'Show chat',
          onPressed: _toggleChatPanel,
        ),
      // Overflow menu
      _buildOverflowMenu(cubit),
    ];
  }

  Widget _buildModeSpecificActions(DistingCubit cubit) {
    return Row(
      key: ValueKey(_currentMode),
      mainAxisSize: MainAxisSize.min,
      children: switch (_currentMode) {
        EditMode.parameters => _buildParameterModeActions(cubit),
        EditMode.routing => _buildRoutingModeActions(),
        EditMode.both => [
          ..._buildParameterModeActions(cubit),
          ..._buildRoutingModeActions(),
        ],
      },
    );
  }

  void _setParameterEditorMode(SlotEditorMode mode) {
    if (_parameterEditorMode == mode) return;
    setState(() => _parameterEditorMode = mode);
    SemanticsService.sendAnnouncement(View.of(context), switch (mode) {
      SlotEditorMode.standard => 'Standard parameter editor shown',
      SlotEditorMode.spreadsheet => 'Spreadsheet parameter editor shown',
      SlotEditorMode.controller => 'Algorithm controller shown',
    }, Directionality.of(context));
  }

  List<Widget> _buildParameterModeActions(DistingCubit cubit) {
    return [
      // Move Up
      Builder(
        builder: (ctx) {
          return IconButton(
            icon: const Icon(
              Icons.arrow_upward_rounded,
              semanticLabel: 'Move Algorithm Up',
            ),
            tooltip: 'Move Algorithm Up',
            onPressed: widget.loading
                ? null
                : () async {
                    final newIndex = await cubit.moveAlgorithmUp(
                      _selectedIndex,
                    );
                    setState(() {
                      _selectedIndex = newIndex;
                    });
                    _tabController.animateTo(newIndex);
                  },
          );
        },
      ),
      // Move Down
      Builder(
        builder: (ctx) {
          return IconButton(
            icon: const Icon(
              Icons.arrow_downward_rounded,
              semanticLabel: 'Move Algorithm Down',
            ),
            tooltip: 'Move Algorithm Down',
            onPressed: widget.loading
                ? null
                : () async {
                    final currentState = cubit.state;
                    int slotCount = 0;
                    if (currentState is DistingStateSynchronized) {
                      slotCount = currentState.slots.length;
                    }
                    if (_selectedIndex < slotCount - 1) {
                      final newIndex = await cubit.moveAlgorithmDown(
                        _selectedIndex,
                      );
                      setState(() {
                        _selectedIndex = newIndex;
                      });
                      _tabController.animateTo(newIndex);
                    }
                  },
          );
        },
      ),
      // Remove Algorithm
      Builder(
        builder: (ctx) {
          return IconButton(
            icon: const Icon(
              Icons.delete_forever_rounded,
              semanticLabel: 'Remove Algorithm',
            ),
            tooltip: 'Remove Algorithm',
            onPressed: widget.loading
                ? null
                : () async {
                    cubit.onRemoveAlgorithm(_selectedIndex);
                  },
          );
        },
      ),
    ];
  }

  List<Widget> _buildRoutingModeActions() {
    return [
      // Placeholder for future routing actions
    ];
  }

  Widget _buildOverflowMenu(DistingCubit cubit) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, semanticLabel: 'More options'),
      onSelected: (value) {
        if (value == 'expanders') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const Ntx8cvScreen()));
        }
      },
      itemBuilder: (popupCtx) {
        // Get offline status here for menu items that need it
        final isOffline = switch (cubit.state) {
          DistingStateSynchronized(offline: final o) => o,
          _ => false,
        };
        return [
          PopupMenuItem(
            value: "wake",
            enabled: !widget.loading && !isOffline,
            onTap: widget.loading || isOffline
                ? null
                : () {
                    cubit.requireDisting().requestWake();
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Wake Display'), Icon(Icons.alarm_on_rounded)],
            ),
          ),
          PopupMenuItem(
            value: "browse",
            enabled: !widget.loading && !isOffline,
            onTap: widget.loading || isOffline
                ? null
                : () async {
                    final currentState = cubit.state;
                    final isMounted = context.mounted;
                    if (currentState is DistingStateSynchronized && isMounted) {
                      final midiManager = cubit.disting();
                      if (midiManager != null) {
                        final prefs = await SharedPreferences.getInstance();
                        // ignore: use_build_context_synchronously
                        var presetInfo = await showDialog(
                          // ignore: use_build_context_synchronously
                          context: popupCtx,
                          builder: (context) => BlocProvider(
                            create: (context) => PresetBrowserCubit(
                              midiManager: midiManager,
                              prefs: prefs,
                            ),
                            child: PresetBrowserDialog(
                              distingCubit: cubit,
                              firmwareVersion: currentState.firmwareVersion,
                            ),
                          ),
                        );
                        if (presetInfo != null && presetInfo is Map) {
                          final sdCardPath = presetInfo['sdCardPath'];
                          final action = presetInfo['action'] as PresetAction?;
                          if (sdCardPath != null &&
                              sdCardPath.isNotEmpty &&
                              action != null) {
                            switch (action) {
                              case PresetAction.load:
                                cubit.loadPreset(sdCardPath, false);
                                break;
                              case PresetAction.append:
                                // Append is not directly supported, could be handled differently
                                break;
                              case PresetAction.export:
                                // Export is not applicable for browse
                                break;
                            }
                          }
                        }
                      }
                    }
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('File Browser'), Icon(Icons.folder_open)],
            ),
          ),

          PopupMenuItem(
            value: "new",
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () async {
                    final currentState = cubit.state;
                    bool hasAlgorithms = false;

                    if (currentState is DistingStateSynchronized) {
                      hasAlgorithms = currentState.slots.isNotEmpty;
                    }

                    if (hasAlgorithms) {
                      // Show confirmation dialog
                      final result = await showDialog<String>(
                        context:
                            popupCtx, // Use the context from the PopupMenuItem
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Create New Preset?'),
                          content: const Text(
                            'The current preset has algorithms. Creating a new preset will clear them.\n\nWould you like to save the current preset first?',
                          ),
                          actions: <Widget>[
                            TextButton(
                              child: const Text('Cancel'),
                              onPressed: () {
                                Navigator.of(dialogContext).pop('cancel');
                              },
                            ),
                            TextButton(
                              child: const Text('Discard & New'),
                              onPressed: () {
                                Navigator.of(dialogContext).pop('new_discard');
                              },
                            ),
                            TextButton(
                              child: const Text('Save First & New'),
                              onPressed: () {
                                Navigator.of(
                                  dialogContext,
                                ).pop('save_first_new');
                              },
                            ),
                          ],
                        ),
                      );

                      if (result == 'new_discard') {
                        cubit.newPreset();
                      } else if (result == 'save_first_new') {
                        try {
                          await cubit.savePreset();
                          cubit.newPreset();
                        } catch (_) {}
                      }
                      // If 'cancel' or dialog dismissed, do nothing.
                    } else {
                      // No algorithms, proceed directly
                      cubit.newPreset();
                    }
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('New Preset'), Icon(Icons.fiber_new_rounded)],
            ),
          ),
          PopupMenuItem(
            value: "save",
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () {
                    cubit.savePreset();
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Save Preset'), Icon(Icons.save_alt_rounded)],
            ),
          ),
          // Video: Disabled by loading OR offline
          PopupMenuItem(
            value: 'screenshot',
            enabled: !widget.loading && !isOffline,
            onTap: widget.loading || isOffline
                ? null
                : () {
                    _showScreenshotOverlay(popupCtx);
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Video'), Icon(Icons.videocam)],
            ),
          ),
          // Perform: Disabled by loading only
          PopupMenuItem(
            value: 'perform',
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () {
                    final midiListener = popupCtx.read<MidiListenerCubit>();
                    Navigator.push(
                      popupCtx,
                      MaterialPageRoute(
                        builder: (_) => MultiBlocProvider(
                          providers: [
                            BlocProvider.value(value: cubit),
                            BlocProvider.value(value: midiListener),
                          ],
                          child: PerformanceScreen(units: widget.units),
                        ),
                      ),
                    );
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Perform'), Icon(Icons.library_music)],
            ),
          ),
          // Plugin Manager: Always enabled (excluded from Play Store build)
          if (!kPlayStoreBuild)
            PopupMenuItem(
              value: 'plugin_manager',
              enabled: !widget.loading,
              onTap: widget.loading
                  ? null
                  : () {
                      final distingCubit = popupCtx.read<DistingCubit>();
                      Navigator.push(
                        popupCtx,
                        MaterialPageRoute(
                          builder: (_) => PluginGalleryScreen(
                            distingCubit: distingCubit,
                            database: distingCubit.database,
                          ),
                        ),
                      );
                    },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Plugin Manager'),
                  Icon(Icons.extension_rounded),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'expanders',
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Expanders'), Icon(Icons.hub_outlined)],
            ),
          ),
          // Switch Devices: Only disabled by loading (Fix context usage)
          PopupMenuItem(
            value: 'Switch Devices',
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () {
                    popupCtx.read<DistingCubit>().goOnline();
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Switch'), Icon(Icons.login_rounded)],
            ),
          ),
          // Settings: Only disabled by loading
          PopupMenuItem(
            value: 'Settings',
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () async {
                    // Get the midi manager and algorithms for RTT stats
                    final cubit = popupCtx.read<DistingCubit>();
                    final state = cubit.state;
                    final midiManager =
                        state is DistingStateSynchronized && !state.offline
                        ? cubit.requireDisting()
                        : null;
                    final algorithms = state is DistingStateSynchronized
                        ? state.algorithms
                        : null;
                    // Original call to show the dialog
                    final result = await popupCtx.showSettingsDialog(
                      midiManager: midiManager,
                      algorithms: algorithms,
                      ccNotificationDiagnostics:
                          cubit.ccNotificationDiagnostics,
                    );

                    // Logic copied and adapted from _DistingPageState._handleSettingsDialog
                    if (result == true && popupCtx.mounted) {
                      // Ensure context is still valid
                      final settings = SettingsService();
                      final mcpInstance = McpServerService.instance;
                      final bool isMcpEnabledAfterDialog = settings.mcpEnabled;
                      final bool isServerStillRunningBeforeAction =
                          mcpInstance.isRunning;

                      if (Platform.isMacOS ||
                          Platform.isWindows ||
                          Platform.isLinux) {
                        final bindAddress = settings.mcpRemoteConnections
                            ? InternetAddress.anyIPv4
                            : InternetAddress.loopbackIPv4;
                        if (isMcpEnabledAfterDialog) {
                          if (!isServerStillRunningBeforeAction) {
                            await mcpInstance
                                .start(bindAddress: bindAddress)
                                .catchError((e) {});
                          } else {
                            if (mcpInstance.boundAddress?.address !=
                                bindAddress.address) {
                              await mcpInstance
                                  .restart(bindAddress: bindAddress)
                                  .catchError((e) {});
                            }
                          }
                        } else {
                          // MCP Setting is OFF
                          if (isServerStillRunningBeforeAction) {
                            await mcpInstance.stop().catchError((e) {});
                          }
                        }
                      }
                    } else {}
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Settings'), Icon(Icons.settings)],
            ),
          ),
          // Sync Metadata: Only disabled by loading
          PopupMenuItem(
            value: 'sync_metadata',
            enabled: !widget.loading,
            onTap: widget.loading
                ? null
                : () {
                    final distingCubit = popupCtx.read<DistingCubit>();
                    Navigator.push(
                      popupCtx,
                      MaterialPageRoute(
                        builder: (_) =>
                            MetadataSyncPage(distingCubit: distingCubit),
                      ),
                    );
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Offline Data'), Icon(Icons.sync_alt_rounded)],
            ),
          ),
          // System submenu: Remount, Reboot, Rescan Algorithms
          PopupMenuItem(
            value: 'system',
            enabled: !widget.loading && !isOffline,
            onTap: widget.loading || isOffline
                ? null
                : () {
                    _showSystemSubmenu(popupCtx, cubit);
                  },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('System'), Icon(Icons.settings_applications)],
            ),
          ),
          // Firmware: Desktop only, disabled when loading (excluded from Play Store build)
          if (!kPlayStoreBuild &&
              (Platform.isMacOS || Platform.isWindows || Platform.isLinux))
            PopupMenuItem(
              value: 'firmware',
              enabled: !widget.loading,
              onTap: widget.loading
                  ? null
                  : () {
                      final distingCubit = popupCtx.read<DistingCubit>();
                      Navigator.push(
                        popupCtx,
                        MaterialPageRoute(
                          builder: (_) =>
                              FirmwareUpdateScreen(distingCubit: distingCubit),
                        ),
                      );
                    },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Firmware'), Icon(Icons.system_update)],
              ),
            ),
          // About: Always enabled (Fix context usage for Theme)
          PopupMenuItem(
            value: 'about',
            enabled: true,
            onTap: widget.loading
                ? null
                : () async {
                    final info = await PackageInfo.fromPlatform();
                    if (!popupCtx.mounted) return;
                    showDialog<String>(
                      context: popupCtx,
                      builder: (dialogCtx) => AboutDialog(
                        applicationName: "NT Helper",
                        applicationVersion:
                            "${info.version} (${info.buildNumber})",
                        applicationLegalese:
                            "Written by Neal Sanche (Thorinside), 2026, No Rights Reserved.",
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              children: [
                                Text(
                                  "Disting Firmware: ${widget.distingVersion}",
                                  style: Theme.of(
                                    dialogCtx,
                                  ).textTheme.bodySmall,
                                ),
                                if (Platform.isMacOS ||
                                    Platform.isLinux ||
                                    Platform.isWindows) ...[
                                  const SizedBox(height: 16),
                                  _UpdateCheckButton(
                                    onUpdateFound: (release) {
                                      Navigator.of(dialogCtx).pop();
                                      _showAppUpdateDialog(release);
                                    },
                                    updateService: _appUpdateService ??=
                                        AppUpdateService(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
            child: const Text('About'),
          ),
        ];
      },
    );
  }

  Padding _buildPresetInfoEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: widget.isDirty
                ? 'Preset: ${widget.presetName.trim()}, unsaved changes'
                : 'Preset: ${widget.presetName.trim()}',
            hint: 'Double tap to rename preset',
            child: InkWell(
              onTap: () async {
                var cubit = context.read<DistingCubit>();

                final newName = await showDialog<String>(
                  context: context,
                  builder: (context) =>
                      RenamePresetDialog(initialName: widget.presetName),
                );

                if (newName != null &&
                    newName.isNotEmpty &&
                    newName != widget.presetName) {
                  cubit.renamePreset(newName);
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Preset:\u2007',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          widget.isDirty
                              ? '${widget.presetName.trim()} *'
                              : widget.presetName.trim(),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return BlocBuilder<DistingCubit, DistingState>(
      buildWhen: (previous, current) {
        if (previous.runtimeType != current.runtimeType) {
          return true;
        }
        if (previous is! DistingStateSynchronized ||
            current is! DistingStateSynchronized) {
          return true;
        }
        if (previous.slots.length != current.slots.length) {
          return true;
        }
        for (int i = 0; i < previous.slots.length; i++) {
          if (previous.slots[i].algorithm.name !=
              current.slots[i].algorithm.name) {
            return true;
          }
        }
        return false;
      },
      builder: (context, state) {
        return switch (state) {
          DistingStateSynchronized(slots: final syncState) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorAnimation: TabIndicatorAnimation.elastic,
              indicatorWeight: 1,
              enableFeedback: true,
              dividerHeight: 0,
              tabs: List<Widget>.generate(syncState.length, (index) {
                final slot = syncState[index];
                final displayName = slot.algorithm.name;
                final isDesktop = !_platformService.isMobilePlatform();

                return Semantics(
                  label: 'Slot ${index + 1}: $displayName',
                  hint: isDesktop
                      ? 'Double tap to select. Long press to rename. '
                            'Shift-click to mark for clipboard copy.'
                      : 'Double tap to select. Long press to rename.',
                  customSemanticsActions: {
                    const CustomSemanticsAction(
                      label: 'Rename algorithm',
                    ): () async {
                      var cubit = context.read<DistingCubit>();
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (dialogCtx) =>
                            RenameSlotDialog(initialName: displayName),
                      );
                      if (newName != null && newName != displayName) {
                        cubit.renameSlot(index, newName);
                      }
                    },
                    const CustomSemanticsAction(
                      label: 'Focus algorithm UI',
                    ): () {
                      var cubit = context.read<DistingCubit>();
                      cubit.disting()?.let((manager) {
                        manager.requestSetFocus(index, 0);
                        manager.requestSetDisplayMode(DisplayMode.algorithmUI);
                      });
                    },
                  },
                  child: MouseRegion(
                    onEnter: (_) {
                      if (_showContextualHelp) {
                        setState(() {
                          _contextualHelpText = _algorithmNameHelpText;
                        });
                      }
                    },
                    onExit: (_) {
                      setState(() {
                        _contextualHelpText = null;
                      });
                    },
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      gestures: {
                        ShiftClickGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              ShiftClickGestureRecognizer
                            >(
                              () => ShiftClickGestureRecognizer(
                                onShiftTap: () {
                                  // Multi-select is desktop-only: the slot tab
                                  // bar is the persistent top chrome there,
                                  // whereas mobile collapses it and
                                  // shift-clicking is not ergonomic.
                                  if (!isDesktop) return;
                                  // Toggle without setState: the indicator
                                  // leaf listens via ValueListenableBuilder
                                  // below. Winning the gesture arena here
                                  // also prevents the TabBar from switching
                                  // the active tab during multi-select.
                                  final next = Set<int>.of(
                                    _clipboardSelection.value,
                                  );
                                  if (!next.add(index)) {
                                    next.remove(index);
                                  }
                                  _clipboardSelection.value = next;
                                  if (SettingsService().hapticsEnabled) {
                                    Haptics.vibrate(HapticsType.light);
                                  }
                                },
                              ),
                              (_) {},
                            ),
                      },
                      child: GestureDetector(
                        onDoubleTap: () async {
                          var cubit = context.read<DistingCubit>();
                          cubit.disting()?.let((manager) {
                            manager.requestSetFocus(index, 0);
                            manager.requestSetDisplayMode(
                              DisplayMode.algorithmUI,
                            );
                          });
                          if (SettingsService().hapticsEnabled) {
                            Haptics.vibrate(HapticsType.medium);
                          }
                        },
                        onLongPress: () async {
                          var cubit = context.read<DistingCubit>();
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (dialogCtx) =>
                                RenameSlotDialog(initialName: displayName),
                          );
                          if (newName != null && newName != displayName) {
                            cubit.renameSlot(index, newName);
                          }
                        },
                        child: Builder(
                          builder: (context) {
                            final originalName = AlgorithmMetadataService()
                                .getAlgorithmByGuid(slot.algorithm.guid)
                                ?.name;
                            final isRenamed =
                                originalName != null &&
                                originalName != displayName;
                            final tabWidget = !isRenamed
                                ? Tab(text: displayName)
                                : Tab(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(displayName),
                                        Text(
                                          originalName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withAlpha(153),
                                              ),
                                        ),
                                      ],
                                    ),
                                  );
                            return ClipboardSelectableTab(
                              key: ValueKey('clipboard-tab-$index'),
                              selection: _clipboardSelection,
                              slotIndex: index,
                              child: tabWidget,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          _ => const Center(child: Text("Loading slots...")),
        };
      },
    );
  }

  void _showSystemSubmenu(BuildContext context, DistingCubit cubit) {
    final supportsWaveCacheTroubleshooting =
        widget.firmwareVersion.hasWaveCacheListing;
    showDialog(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Row(
          children: [
            Icon(Icons.settings_applications),
            SizedBox(width: 8),
            Text('System'),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.remountSd();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SD card remount requested'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const ListTile(
              leading: Icon(Icons.sd_card),
              title: Text('Remount SD Card'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: supportsWaveCacheTroubleshooting
                ? () {
                    Navigator.of(dialogContext).pop();
                    _showWaveCacheTroubleshooting(context, cubit);
                  }
                : null,
            child: ListTile(
              enabled: supportsWaveCacheTroubleshooting,
              leading: const Icon(Icons.troubleshoot),
              title: const Text('Wave Cache Troubleshooting'),
              subtitle: supportsWaveCacheTroubleshooting
                  ? const Text('Find and reset corrupted WAV caches')
                  : const Text('Requires firmware 1.17 or later'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showRebootConfirmationDialog(context, cubit);
            },
            child: const ListTile(
              leading: Icon(Icons.restart_alt),
              title: Text('Reboot Device'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.refreshAlgorithms();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rescanning algorithms...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Rescan Algorithms'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWaveCacheTroubleshooting(
    BuildContext context,
    DistingCubit cubit,
  ) async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaveCacheTroubleshootingDialog(
        service: WaveCacheMaintenanceService(cubit.requireDisting()),
      ),
    );
  }

  void _showRebootConfirmationDialog(BuildContext context, DistingCubit cubit) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.restart_alt,
              color: dialogContext.appColors.warning.color,
            ),
            const SizedBox(width: 8),
            const Text('Reboot Device'),
          ],
        ),
        content: const Text(
          'This will reboot your Disting NT. Any unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.reboot();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reboot command sent'),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            child: const Text('Reboot'),
          ),
        ],
      ),
    );
  }

  void _showScreenshotOverlay(BuildContext context) {
    final cubit = context.read<DistingCubit>();
    final popupService = VideoPopupWindowService.instance;
    if (popupService.isSupported &&
        SettingsService().videoPopupNativeWindowEnabled) {
      unawaited(_showVideoPopupOrFallback(context, cubit));
      return;
    }

    _showInWindowVideoOverlay(context, cubit);
  }

  Future<void> _showVideoPopupOrFallback(
    BuildContext context,
    DistingCubit cubit,
  ) async {
    try {
      final opened = await VideoPopupWindowService.instance.open(cubit);
      if (opened) return;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open video popup; using overlay instead.'),
          ),
        );
      }
    }

    if (context.mounted) {
      _showInWindowVideoOverlay(context, cubit);
    }
  }

  void _showInWindowVideoOverlay(BuildContext context, DistingCubit cubit) {
    // Create a VideoFrameCubit for this overlay
    final videoFrameCubit = VideoFrameCubit();

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => FloatingVideoOverlay(
        overlayEntry: overlayEntry,
        cubit: cubit,
        videoFrameCubit: videoFrameCubit,
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  Widget _buildCheckpointButton(
    BuildContext context,
    ButtonStyle? buttonStyle,
  ) {
    final distingCubit = context.read<DistingCubit>();
    final checkpoints = distingCubit.checkpoints;

    return PopupMenuButton<String>(
      icon: Icon(
        checkpoints.isEmpty ? Icons.bookmark_border : Icons.bookmark,
        semanticLabel: 'Checkpoints',
      ),
      tooltip: 'Preset Checkpoints',
      style: buttonStyle,
      onSelected: (value) async {
        if (value == 'create') {
          final checkpoint = distingCubit.createCheckpoint();
          if (checkpoint != null) {
            setState(() {});
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Checkpoint created (${checkpoint.slotCount} slots)',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else if (value.startsWith('restore:')) {
          final index = int.parse(value.substring(8));
          final currentCheckpoints = distingCubit.checkpoints;
          if (index >= currentCheckpoints.length) return;
          final checkpoint = currentCheckpoints[index];
          final messenger = ScaffoldMessenger.of(context);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Restore Checkpoint?'),
              content: Text(
                'Restore to checkpoint from '
                '${_formatCheckpointTime(checkpoint.createdAt)}?\n\n'
                'This will revert all parameter values to the '
                'checkpoint state (${checkpoint.slotCount} slots).',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error,
                  ),
                  child: const Text('Restore'),
                ),
              ],
            ),
          );
          if (confirmed == true && mounted) {
            try {
              final routingCubit = _routingEditorCubit;
              final int result;
              if (routingCubit != null) {
                result = await routingCubit.runBatched(() async {
                  return distingCubit.restoreCheckpoint(checkpoint);
                });
              } else {
                result = await distingCubit.restoreCheckpoint(checkpoint);
              }
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      result > 0
                          ? 'Restored $result parameters'
                          : result == 0
                          ? 'Nothing to restore (no changes)'
                          : 'Restore failed',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } catch (_) {
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Restore failed unexpectedly'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        } else if (value == 'clear') {
          distingCubit.clearCheckpoints();
          setState(() {});
        }
      },
      itemBuilder: (context) {
        final currentCheckpoints = distingCubit.checkpoints;
        final items = <PopupMenuEntry<String>>[];

        items.add(
          const PopupMenuItem(
            value: 'create',
            child: ListTile(
              leading: Icon(Icons.add_circle_outline),
              title: Text('Create Checkpoint'),
              dense: true,
            ),
          ),
        );

        if (currentCheckpoints.isNotEmpty) {
          items.add(const PopupMenuDivider());

          for (int i = currentCheckpoints.length - 1; i >= 0; i--) {
            final cp = currentCheckpoints[i];
            items.add(
              PopupMenuItem(
                value: 'restore:$i',
                child: ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(cp.label ?? _formatCheckpointTime(cp.createdAt)),
                  subtitle: Text(
                    '${cp.slotCount} slots'
                    '${cp.label != null ? ' - ${_formatCheckpointTime(cp.createdAt)}' : ''}',
                  ),
                  dense: true,
                ),
              ),
            );
          }

          items.add(const PopupMenuDivider());
          items.add(
            const PopupMenuItem(
              value: 'clear',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Clear All Checkpoints'),
                dense: true,
              ),
            ),
          );
        }

        return items;
      },
    );
  }

  String _formatCheckpointTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  double _findClosestZoomLevel(double currentZoom) {
    final levels = RoutingEditorCubit.availableZoomLevels;
    double closest = levels.first;
    double minDifference = (currentZoom - closest).abs();

    for (final level in levels) {
      final difference = (currentZoom - level).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closest = level;
      }
    }

    return closest;
  }
}

class _UpdateCheckButton extends StatefulWidget {
  final void Function(AppRelease release) onUpdateFound;
  final AppUpdateService updateService;

  const _UpdateCheckButton({
    required this.onUpdateFound,
    required this.updateService,
  });

  @override
  State<_UpdateCheckButton> createState() => _UpdateCheckButtonState();
}

class _UpdateCheckButtonState extends State<_UpdateCheckButton> {
  bool _checking = false;
  String? _message;

  Future<void> _check({bool skipVersionCheck = false}) async {
    setState(() {
      _checking = true;
      _message = null;
    });

    final release = await widget.updateService.checkForUpdate(
      forceRefresh: true,
      skipVersionCheck: skipVersionCheck,
    );

    if (!mounted) return;

    if (release != null) {
      widget.onUpdateFound(release);
    } else {
      setState(() {
        _checking = false;
        _message = "You're up to date!";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: _checking
              ? null
              : () => _check(
                  skipVersionCheck:
                      kDebugMode &&
                      HardwareKeyboard.instance.logicalKeysPressed.any(
                        (k) =>
                            k == LogicalKeyboardKey.shiftLeft ||
                            k == LogicalKeyboardKey.shiftRight,
                      ),
                ),
          icon: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          label: Text(_checking ? 'Checking...' : 'Check for Updates'),
        ),
        const SizedBox(height: 8),
        Visibility(
          visible: _message != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Text(
            _message ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
