import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show AlgorithmVisualStyle, DisplayMode;
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_container.dart';
import 'package:nt_helper/ui/widgets/clipboard_selectable_tab.dart';
import 'package:nt_helper/ui/widgets/rename_slot_dialog.dart';
import 'package:nt_helper/ui/widgets/shift_click_gesture_recognizer.dart';
import 'package:nt_helper/util/extensions.dart';

class AlgorithmListView extends StatelessWidget {
  final List<Slot> slots;
  final int selectedIndex;
  final ValueChanged<int> onSelectionChanged;
  final ValueChanged<String?>? onHelpTextChanged;
  final Future<int> Function(int index)? onMoveUp;
  final Future<int> Function(int index)? onMoveDown;
  final ValueChanged<int>? onDelete;

  /// Live clipboard-selection set used by the algorithm-clipboard (Mod+C)
  /// flow. When non-null, shift-clicking a tile toggles it in this set and a
  /// tertiary-coloured box is drawn around clipboard-selected tiles.
  final ValueNotifier<Set<int>>? clipboardSelection;

  /// Toggle callback invoked when a tile is shift-clicked for the clipboard.
  final ValueChanged<int>? onToggleClipboardSelection;

  const AlgorithmListView({
    super.key,
    required this.slots,
    required this.selectedIndex,
    required this.onSelectionChanged,
    this.onHelpTextChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
    this.clipboardSelection,
    this.onToggleClipboardSelection,
  });

  static const String algorithmNameHelpText =
      'Double-click: Focus algorithm UI  •  Long-press: Rename algorithm';

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        return _AlgorithmListTile(
          slot: slots[index],
          index: index,
          isSelected: index == selectedIndex,
          onSelectionChanged: onSelectionChanged,
          onHelpTextChanged: onHelpTextChanged,
          onMoveUp: onMoveUp,
          onMoveDown: onMoveDown,
          onDelete: onDelete,
          clipboardSelection: clipboardSelection,
          onToggleClipboardSelection: onToggleClipboardSelection,
        );
      },
    );
  }
}

class _AlgorithmListTile extends StatefulWidget {
  final Slot slot;
  final int index;
  final bool isSelected;
  final ValueChanged<int> onSelectionChanged;
  final ValueChanged<String?>? onHelpTextChanged;
  final Future<int> Function(int index)? onMoveUp;
  final Future<int> Function(int index)? onMoveDown;
  final ValueChanged<int>? onDelete;
  final ValueNotifier<Set<int>>? clipboardSelection;
  final ValueChanged<int>? onToggleClipboardSelection;

  const _AlgorithmListTile({
    required this.slot,
    required this.index,
    required this.isSelected,
    required this.onSelectionChanged,
    this.onHelpTextChanged,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
    this.clipboardSelection,
    this.onToggleClipboardSelection,
  });

  @override
  State<_AlgorithmListTile> createState() => _AlgorithmListTileState();
}

class _AlgorithmListTileState extends State<_AlgorithmListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  Timer? _fadeOutDelay;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _fadeOutDelay?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool hovered) {
    _fadeOutDelay?.cancel();
    if (hovered) {
      _fadeController.duration = const Duration(milliseconds: 100);
      _fadeController.forward();
    } else if (widget.isSelected) {
      _fadeOutDelay = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _fadeController.duration = const Duration(milliseconds: 300);
          _fadeController.reverse();
        }
      });
    } else {
      _fadeController.duration = const Duration(milliseconds: 100);
      _fadeController.reverse();
    }
  }

  Widget _buildActionRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onMoveUp != null)
          _buildActionButton(
            icon: Icons.arrow_upward_rounded,
            onPressed: () => widget.onMoveUp!(widget.index),
          ),
        if (widget.onMoveDown != null)
          _buildActionButton(
            icon: Icons.arrow_downward_rounded,
            onPressed: () => widget.onMoveDown!(widget.index),
          ),
        if (widget.onDelete != null)
          _buildActionButton(
            icon: Icons.delete_forever_rounded,
            onPressed: () => widget.onDelete!(widget.index),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 28,
        height: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget? _buildOriginalNameSubtitle(BuildContext context) {
    final guid = widget.slot.algorithm.guid;
    final originalName = AlgorithmMetadataService()
        .getAlgorithmByGuid(guid)
        ?.name;
    if (originalName == null || originalName == widget.slot.algorithm.name) {
      return null;
    }
    return Text(
      originalName,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.slot.algorithm.name;
    final visualStyle =
        widget.slot.algorithm.visualStyle ?? const AlgorithmVisualStyle();
    final originalNameSubtitle = _buildOriginalNameSubtitle(context);
    final colorScheme = Theme.of(context).colorScheme;
    final algorithmBoxColor = widget.isSelected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerLow;
    final hasActions =
        widget.onMoveUp != null ||
        widget.onMoveDown != null ||
        widget.onDelete != null;

    return Semantics(
      label:
          'Slot ${widget.index + 1}: $displayName; '
          '${describeAlgorithmVisualStyle(visualStyle)}',
      hint: 'Double tap to select. Long press to rename.',
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Rename algorithm'): () async {
          var cubit = context.read<DistingCubit>();
          final newName = await showDialog<String>(
            context: context,
            builder: (dialogCtx) => RenameSlotDialog(initialName: displayName),
          );
          if (newName != null && newName != displayName) {
            cubit.renameSlot(widget.index, newName);
          }
        },
        const CustomSemanticsAction(label: 'Focus algorithm UI'): () {
          var cubit = context.read<DistingCubit>();
          cubit.disting()?.let((manager) {
            manager.requestSetFocus(widget.index, 0);
            manager.requestSetDisplayMode(DisplayMode.algorithmUI);
          });
        },
      },
      child: MouseRegion(
        onEnter: (_) {
          widget.onHelpTextChanged?.call(
            AlgorithmListView.algorithmNameHelpText,
          );
          if (hasActions) _onHoverChanged(true);
        },
        onExit: (_) {
          widget.onHelpTextChanged?.call(null);
          if (hasActions) _onHoverChanged(false);
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: widget.onToggleClipboardSelection == null
              ? const <Type, GestureRecognizerFactory>{}
              : {
                  ShiftClickGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        ShiftClickGestureRecognizer
                      >(
                        () => ShiftClickGestureRecognizer(
                          onShiftTap: () {
                            widget.onToggleClipboardSelection!(widget.index);
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
                manager.requestSetFocus(widget.index, 0);
                manager.requestSetDisplayMode(DisplayMode.algorithmUI);
              });
              if (SettingsService().hapticsEnabled) {
                Haptics.vibrate(HapticsType.medium);
              }
            },
            child: ClipboardSelectableTab(
              key: ValueKey('clipboard-tile-${widget.index}'),
              selection: widget.clipboardSelection ?? _emptySelection,
              slotIndex: widget.index,
              horizontalPadding: 4,
              child: AlgorithmVisualStyleContainer(
                key: ValueKey('algorithm-style-preview-${widget.index}'),
                style: visualStyle,
                color: colorScheme.onSurfaceVariant,
                contentPadding: EdgeInsets.zero,
                boxDecoration: BoxDecoration(
                  color: algorithmBoxColor,
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Stack(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 12,
                        right: 16,
                      ),
                      title: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, overflow: TextOverflow.ellipsis),
                            ?originalNameSubtitle,
                          ],
                        ),
                      ),
                      selected: widget.isSelected,
                      selectedColor: colorScheme.onSecondaryContainer,
                      onTap: () {
                        widget.onSelectionChanged(widget.index);
                        SemanticsService.sendAnnouncement(
                          WidgetsBinding
                              .instance
                              .platformDispatcher
                              .views
                              .first,
                          'Slot ${widget.index + 1}: $displayName selected',
                          TextDirection.ltr,
                        );
                      },
                      onLongPress: () async {
                        var cubit = context.read<DistingCubit>();
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (dialogCtx) =>
                              RenameSlotDialog(initialName: displayName),
                        );
                        if (newName != null && newName != displayName) {
                          cubit.renameSlot(widget.index, newName);
                        }
                      },
                    ),
                    if (hasActions)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: AnimatedBuilder(
                          animation: _fadeController,
                          builder: (context, child) {
                            final t = _fadeController.value;
                            final tileColor = algorithmBoxColor;
                            final maskColor = Theme.of(
                              context,
                            ).colorScheme.onSurface;
                            return ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: [
                                  maskColor.withValues(alpha: t),
                                  maskColor,
                                ],
                                stops: const [0.0, 0.5],
                              ).createShader(bounds),
                              blendMode: BlendMode.dstIn,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      tileColor.withValues(alpha: 0),
                                      tileColor.withValues(alpha: t),
                                    ],
                                    stops: const [0.0, 0.3],
                                  ),
                                ),
                                padding: const EdgeInsets.only(
                                  left: 24,
                                  right: 8,
                                ),
                                child: Opacity(
                                  opacity: widget.isSelected
                                      ? 0.3 + 0.7 * t
                                      : t,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: _buildActionRow(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// A stable, never-mutated notifier used when no clipboard selection is wired
// up, so tiles can always hand a [ValueNotifier] to [ClipboardSelectableTab].
final ValueNotifier<Set<int>> _emptySelection = ValueNotifier<Set<int>>(
  <int>{},
);
