import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:nt_helper/core/routing/algorithm_routing.dart' as core_routing;
import 'package:nt_helper/core/routing/bus_color_palette.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/routing/bus_lanes_painter.dart';
import 'package:nt_helper/ui/widgets/routing/bus_picker_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Graphical, bus-centric routing view. Buses are vertical colored lanes
/// (tubes). Each algorithm is a block whose individual inputs (top rows) and
/// outputs (bottom rows) each carry a bead that sits on the bus lane it uses.
///
/// Interactions:
/// - Drag a bead onto a lane to connect/reassign it; drag it to the "—" column
///   to disconnect. Slots auto-reorder to keep signal flowing (with Undo).
/// - Tap an output bead to flip Add ↔ Replace.
/// - Drag a block's gutter up/down to reorder; blocks spring into place.
/// - Scroll with the wheel/trackpad or the scrollbars.
class BusLanesView extends StatefulWidget {
  const BusLanesView({super.key});

  @override
  State<BusLanesView> createState() => _BusLanesViewState();
}

class _BusLanesViewState extends State<BusLanesView> {
  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final ScrollController _h = ScrollController();
  final ScrollController _v = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'BusLanes');
  String? _draggingId;
  double _dragDy = 0;
  final Set<int> _canvasPanPointers = {};

  /// The currently selected junction (bead), if any. Delete/Backspace
  /// disconnects it.
  _PortRef? _selected;

  /// Current mouse position (content coords) for the hover drop-target hints.
  final ValueNotifier<Offset?> _hover = ValueNotifier<Offset?>(null);

  BusLanesMetrics? _lastMetrics;
  List<int> _lastVisibleBuses = const [];
  DeviceIoProfile _lastProfile = DeviceIoProfile.distingExtended;

  /// Reorder responds to mouse/touch press-drag only. Trackpad two-finger
  /// swipes are reserved for scrolling, so they're excluded here — otherwise
  /// the drag-to-reorder gesture would capture every scroll over a block.
  static final Set<PointerDeviceKind> _reorderDevices =
      PointerDeviceKind.values.toSet()..remove(PointerDeviceKind.trackpad);
  static const Set<PointerDeviceKind> _canvasPanDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    _focusNode.dispose();
    _hover.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_selected != null) setState(() => _selected = null);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      final sel = _selected;
      if (sel != null && sel.parameterNumber >= 0 && sel.previousBus > 0) {
        _applyAssign(context, sel, 0);
        setState(() => _selected = null);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _scroll(ScrollController c, double delta) {
    if (!c.hasClients || delta == 0) return;
    c.jumpTo((c.offset + delta).clamp(0.0, c.position.maxScrollExtent));
  }

  void _panCanvasBy(Offset delta) {
    _scroll(_h, -delta.dx);
    _scroll(_v, -delta.dy);
  }

  bool _isCanvasPanDown(PointerDownEvent event, _BusLanesData data) {
    if (!_canvasPanDevices.contains(event.kind) ||
        event.buttons != kPrimaryButton) {
      return false;
    }
    final position = event.localPosition;
    if (position.dx < BusLanesMetrics.gutterWidth) return false;
    return !_isOnBead(position, data);
  }

  bool _isCanvasPanMove(PointerMoveEvent event) {
    return _canvasPanPointers.contains(event.pointer) &&
        _canvasPanDevices.contains(event.kind) &&
        event.buttons == kPrimaryButton;
  }

  bool _isOnBead(Offset position, _BusLanesData data) {
    final m = data.metrics;
    for (var i = 0; i < data.cards.length; i++) {
      final cardTop = m.cardTops[i];
      for (final bead in data.cards[i].beads) {
        final beadRect = Rect.fromCenter(
          center: Offset(bead.x, cardTop + bead.y),
          width: 26,
          height: 26,
        );
        if (beadRect.contains(position)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // A scoped messenger so snackbars appear within the Bus Lanes canvas area
    // rather than at the bottom of the whole window.
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BlocBuilder<RoutingEditorCubit, RoutingEditorState>(
          buildWhen: (prev, curr) {
            if (prev is! RoutingEditorStateLoaded ||
                curr is! RoutingEditorStateLoaded) {
              return true;
            }
            return prev.algorithms != curr.algorithms ||
                prev.connections != curr.connections ||
                prev.portOutputModes != curr.portOutputModes ||
                prev.deviceIoProfile != curr.deviceIoProfile ||
                prev.hasExtendedAuxBuses != curr.hasExtendedAuxBuses;
          },
          builder: (context, state) {
            final theme = Theme.of(context);
            if (state is! RoutingEditorStateLoaded) {
              return Center(
                child: Text(
                  state is RoutingEditorStateInitial
                      ? 'Initializing…'
                      : 'Disconnected',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }

            final isDark = theme.brightness == Brightness.dark;
            final data = _buildData(
              state.algorithms,
              state.portOutputModes,
              state.deviceIoProfile,
              isDark,
            );
            if (data == null) {
              return Center(
                child: Text(
                  'No algorithms loaded.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            final m = data.metrics;
            final colors = _BlockColors(
              card: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              border: theme.colorScheme.outlineVariant,
              text: theme.colorScheme.onSurface,
              muted: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              error: theme.colorScheme.error,
            );

            final order = [for (var i = 0; i < data.cards.length; i++) i];
            order.sort((a, b) {
              final ad = data.cards[a].id == _draggingId ? 1 : 0;
              final bd = data.cards[b].id == _draggingId ? 1 : 0;
              return ad - bd;
            });
            final tops = _displayTops(data);
            final blockCount = data.cards.length;
            final blockLabel = blockCount == 1 ? 'block' : 'blocks';

            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _scroll(_v, event.scrollDelta.dy);
                  _scroll(_h, event.scrollDelta.dx);
                }
              },
              // Trackpad two-finger swipes arrive as pan/zoom events, not pointer
              // signals. Mirror Flutter's own scroll conversion (negated pan delta)
              // so the canvas scrolls instead of the swipe falling through to a
              // child gesture.
              onPointerPanZoomUpdate: (event) {
                _scroll(_v, -event.localPanDelta.dy);
                _scroll(_h, -event.localPanDelta.dx);
              },
              child: Scrollbar(
                controller: _v,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                child: Scrollbar(
                  controller: _h,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  notificationPredicate: (n) =>
                      n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _v,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SingleChildScrollView(
                      controller: _h,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        key: _contentKey,
                        width: m.contentWidth,
                        height: m.contentHeight,
                        child: Semantics(
                          label:
                              'Bus lanes canvas with $blockCount algorithm $blockLabel',
                          hint:
                              'Pan to navigate. Drag beads to reassign buses.',
                          container: true,
                          child: MouseRegion(
                            onHover: (e) => _hover.value = e.localPosition,
                            onExit: (_) => _hover.value = null,
                            child: Focus(
                              focusNode: _focusNode,
                              onKeyEvent: _onKey,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: BusLanesPainter(
                                        rails: data.rails,
                                        metrics: m,
                                        noneColor:
                                            theme.colorScheme.outlineVariant,
                                        separatorColor: theme.dividerColor,
                                      ),
                                    ),
                                  ),
                                  for (final i in order)
                                    _buildBlock(context, i, data, colors, tops),
                                  Positioned.fill(
                                    child: ValueListenableBuilder<Offset?>(
                                      valueListenable: _hover,
                                      builder: (ctx, hover, _) => _buildGhosts(
                                        context,
                                        data,
                                        hover,
                                        state,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Listener(
                                      behavior: HitTestBehavior.translucent,
                                      onPointerDown: (event) {
                                        if (_isCanvasPanDown(event, data)) {
                                          _canvasPanPointers.add(event.pointer);
                                        }
                                      },
                                      onPointerMove: (event) {
                                        if (_isCanvasPanMove(event)) {
                                          _panCanvasBy(event.delta);
                                        }
                                      },
                                      onPointerUp: (event) {
                                        _canvasPanPointers.remove(
                                          event.pointer,
                                        );
                                      },
                                      onPointerCancel: (event) {
                                        _canvasPanPointers.remove(
                                          event.pointer,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Per-frame vertical positions for each block. While a block is being
  /// dragged, the others make a gap at the would-be drop slot so the resulting
  /// swap is visible; the dragged block follows the finger.
  Map<String, double> _displayTops(_BusLanesData data) {
    final m = data.metrics;
    final tops = <String, double>{};
    final draggingIdx = _draggingId == null
        ? -1
        : data.cards.indexWhere((c) => c.id == _draggingId);
    if (draggingIdx < 0) {
      for (var i = 0; i < data.cards.length; i++) {
        tops[data.cards[i].id] = m.cardTops[i];
      }
      return tops;
    }

    final draggedCenter = m.cardCenter(draggingIdx) + _dragDy;
    var target = 0;
    for (var i = 0; i < data.cards.length; i++) {
      if (i == draggingIdx) continue;
      if (m.cardCenter(i) < draggedCenter) target++;
    }
    final ids = [for (final c in data.cards) c.id]..removeAt(draggingIdx);
    ids.insert(target, data.cards[draggingIdx].id);
    final heightById = {
      for (var i = 0; i < data.cards.length; i++)
        data.cards[i].id: m.cardHeights[i],
    };
    var y = BusLanesMetrics.headerHeight;
    for (final id in ids) {
      tops[id] = y;
      y += heightById[id]!;
    }
    // The dragged block follows the finger rather than its preview slot.
    tops[data.cards[draggingIdx].id] = m.cardTops[draggingIdx] + _dragDy;
    return tops;
  }

  Widget _buildBlock(
    BuildContext context,
    int index,
    _BusLanesData data,
    _BlockColors colors,
    Map<String, double> tops,
  ) {
    final card = data.cards[index];
    final m = data.metrics;
    final isDragging = card.id == _draggingId;
    final top = tops[card.id] ?? m.cardTops[index];
    final height = m.cardHeights[index];

    final content = SizedBox(
      width: m.contentWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: BusBlockPainter(
                title: card.title,
                ports: card.ports,
                cardColor: colors.card,
                borderColor: colors.border,
                textColor: colors.text,
                mutedColor: colors.muted,
                errorColor: colors.error,
                selected: isDragging,
              ),
            ),
          ),
          // Gutter = reorder handle (drag up/down).
          Positioned(
            left: 0,
            top: 0,
            width: BusLanesMetrics.gutterWidth,
            height: height,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              supportedDevices: _reorderDevices,
              onVerticalDragStart: (_) => setState(() {
                _draggingId = card.id;
                _dragDy = 0;
              }),
              onVerticalDragUpdate: (d) =>
                  setState(() => _dragDy += d.delta.dy),
              onVerticalDragEnd: (_) => _commitReorder(context, data, index),
              onVerticalDragCancel: () => setState(() {
                _draggingId = null;
                _dragDy = 0;
              }),
            ),
          ),
          for (final bead in card.beads) _buildBead(context, bead),
        ],
      ),
    );

    return AnimatedPositioned(
      key: ValueKey(card.id),
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      left: 0,
      top: top,
      width: m.contentWidth,
      height: height,
      child: content,
    );
  }

  Widget _buildBead(BuildContext context, _Bead bead) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final selected = _selected?.portId == bead.ref.portId;

    Widget visual = _beadVisual(
      bead.color,
      surface,
      theme.colorScheme.shadow,
      filled: bead.connected,
    );
    if (bead.unprovided) {
      visual = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.error, width: 2),
        ),
        child: visual,
      );
    }
    if (selected) {
      visual = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.tertiary, width: 2),
        ),
        child: visual,
      );
    }

    final draggable = bead.ref.parameterNumber < 0
        ? Center(child: visual)
        : Draggable<_PortRef>(
            data: bead.ref,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _beadVisual(
              bead.color,
              surface,
              theme.colorScheme.shadow,
              filled: true,
              dragging: true,
            ),
            childWhenDragging: Center(
              child: Opacity(
                opacity: 0.3,
                child: _beadVisual(
                  bead.color,
                  surface,
                  theme.colorScheme.shadow,
                  filled: bead.connected,
                ),
              ),
            ),
            onDragEnd: (d) => _onBeadDrop(context, bead.ref, d.offset),
            child: Center(child: visual),
          );

    return Positioned(
      left: bead.x - 13,
      top: bead.y - 13,
      width: 26,
      height: 26,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            // Tapping the selected junction again clears the selection.
            _selected = _selected?.portId == bead.ref.portId ? null : bead.ref;
          });
          _focusNode.requestFocus();
        },
        onDoubleTap: (bead.ref.isOutput && bead.ref.modeParam != null)
            ? () => context.read<RoutingEditorCubit>().togglePortOutputMode(
                portId: bead.ref.portId,
              )
            : null,
        child: draggable,
      ),
    );
  }

  Widget _beadVisual(
    Color color,
    Color surface,
    Color shadow, {
    required bool filled,
    bool dragging = false,
  }) {
    final size = dragging ? 17.0 : 14.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // A contrasting ring so the bead stays visible on a same-colored lane.
        color: filled ? color : surface,
        shape: BoxShape.circle,
        border: Border.all(color: filled ? surface : color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: shadow.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  void _commitReorder(BuildContext context, _BusLanesData data, int index) {
    final id = _draggingId;
    final dy = _dragDy;
    setState(() {
      _draggingId = null;
      _dragDy = 0;
    });
    if (id == null || dy.abs() < 14) return; // resistance deadzone

    final m = data.metrics;
    final draggedCenter = m.cardCenter(index) + dy;
    var target = 0;
    for (var i = 0; i < data.cards.length; i++) {
      if (i == index) continue;
      if (m.cardCenter(i) < draggedCenter) target++;
    }
    if (target == index) return;

    final newOrder = [for (final c in data.cards) c.id]..removeAt(index);
    newOrder.insert(target, id);
    context.read<RoutingEditorCubit>().applyReorder(newOrder);
  }

  /// A single faint, tappable drop-target hint for the cell under the cursor.
  Widget _buildGhosts(
    BuildContext context,
    _BusLanesData data,
    Offset? hover,
    RoutingEditorState state,
  ) {
    if (hover == null ||
        _draggingId != null ||
        hover.dx < BusLanesMetrics.gutterWidth) {
      return const SizedBox.shrink();
    }
    final m = data.metrics;
    for (var bi = 0; bi < data.cards.length; bi++) {
      final blockTop = m.cardTops[bi];
      if (hover.dy < blockTop || hover.dy >= blockTop + m.cardHeights[bi]) {
        continue;
      }
      final row =
          ((hover.dy -
                      blockTop -
                      BusLanesMetrics.titleHeight -
                      BusLanesMetrics.padV) /
                  BusLanesMetrics.portRowHeight)
              .floor();
      final card = data.cards[bi];
      if (row < 0 || row >= card.beads.length) break;
      final bead = card.beads[row];
      if (bead.ref.parameterNumber < 0) break;

      final currentCol =
          ((bead.x - BusLanesMetrics.gutterWidth) / BusLanesMetrics.railWidth)
              .floor();
      final col =
          ((hover.dx - BusLanesMetrics.gutterWidth) / BusLanesMetrics.railWidth)
              .floor();

      // Check if we are in the "None" column (col 0) and if disconnect is allowed (min == 0)
      bool canDisconnect = false;
      if (col == 0 && state is RoutingEditorStateLoaded) {
        final algo = state.algorithms[bi];
        final distingState = context.read<DistingCubit>().state;
        if (distingState is DistingStateSynchronized) {
          final slot = distingState.slots[algo.index];
          final param = slot.parameters.firstWhere(
            (p) => p.parameterNumber == bead.ref.parameterNumber,
            orElse: () => ParameterInfo.filler(),
          );
          if (param.min == 0) {
            canDisconnect = true;
          }
        }
      }

      final isLane = col >= 1 && col <= _lastVisibleBuses.length;
      final isAdd = col == m.columnCount - 1;
      if ((!isLane && !isAdd && !canDisconnect) || col == currentCol) {
        return const SizedBox.shrink();
      }

      final portY = blockTop + BusLanesMetrics.portRowY(row);
      final accent = Theme.of(context).colorScheme.primary;
      return Stack(
        children: [
          Positioned(
            left: m.columnX(col) - 13,
            top: portY - 13,
            width: 26,
            height: 26,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => isAdd
                  ? _showBusPicker(context, bead.ref, d.globalPosition)
                  : _placeAt(context, bead.ref, col),
              child: Center(
                child: Opacity(
                  opacity: 0.55,
                  child: isAdd
                      ? Icon(Icons.add_circle_outline, size: 18, color: accent)
                      : (col == 0
                            ? Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                                color: accent,
                              )
                            : Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: accent, width: 2),
                                ),
                              )),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  void _placeAt(BuildContext context, _PortRef ref, int column) {
    if (column == 0) {
      // Disconnect: set bus to 0
      if (ref.previousBus == 0) return;
      _applyAssign(context, ref, 0);
      return;
    }
    if (column < 1 || column > _lastVisibleBuses.length) return;
    final targetBus = _lastVisibleBuses[column - 1];
    if (targetBus == ref.previousBus && !ref.appliesOnSameBus(targetBus)) {
      return;
    }
    _applyAssign(context, ref, targetBus);
  }

  void _onBeadDrop(BuildContext context, _PortRef ref, Offset globalOffset) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final m = _lastMetrics;
    if (box == null || m == null) return;
    final local = box.globalToLocal(globalOffset);

    final col =
        ((local.dx - BusLanesMetrics.gutterWidth) / BusLanesMetrics.railWidth)
            .floor();
    if (col < 0) return; // off the left edge: cancel
    if (col >= m.columnCount - 1) {
      // Dropped on (or past) the "＋" column: ask which bus to add.
      _showBusPicker(context, ref, globalOffset);
      return;
    }
    final targetBus = col == 0 ? 0 : _lastVisibleBuses[col - 1];
    if (targetBus == ref.previousBus && !ref.appliesOnSameBus(targetBus)) {
      return;
    }
    _applyAssign(context, ref, targetBus);
  }

  Future<void> _showBusPicker(
    BuildContext context,
    _PortRef ref,
    Offset globalPos,
  ) async {
    // Determine if the algorithm is USB Audio (from Host) — only usbf outputs
    // may target the ES-5 expansion buses.
    bool isUsbf = false;
    final cubit = context.read<RoutingEditorCubit>();
    final state = cubit.state;
    if (state is RoutingEditorStateLoaded) {
      for (final algo in state.algorithms) {
        if (algo.index == ref.algorithmIndex) {
          isUsbf = algo.algorithm.guid == 'usbf';
          break;
        }
      }
    }

    final range = cubit.busParameterRange(
      algorithmIndex: ref.algorithmIndex,
      parameterNumber: ref.parameterNumber,
    );
    if (range == null) return;

    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: _lastProfile,
      currentValue: ref.previousBus,
      minimum: range.min,
      maximum: range.max,
      allowNone: range.min <= 0,
      includeEs5: isUsbf,
    );
    if (!model.hasSelectableValue) return;

    final choice = await showDialog<int>(
      context: context,
      builder: (ctx) => BusPickerDialog(portLabel: ref.label, model: model),
    );
    if (choice == null || !mounted || !context.mounted) return;
    if (choice == ref.previousBus) return;
    await _applyAssign(context, ref, choice);
  }

  Future<void> _applyAssign(
    BuildContext context,
    _PortRef ref,
    int targetBus,
  ) async {
    final cubit = context.read<RoutingEditorCubit>();
    final result = await cubit.assignBusAndSolve(
      algorithmIndex: ref.algorithmIndex,
      parameterNumber: ref.parameterNumber,
      previousBusValue: ref.previousBus,
      busValue: targetBus,
    );
    if (!mounted) return;
    final reorder = result.reorder;
    final what = targetBus == 0
        ? 'Disconnected ${ref.label}'
        : 'Connected ${ref.label} → ${_busLabel(targetBus)}';
    final messenger = _messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          (reorder != null && reorder.changed)
              ? '$what — ${reorder.description}'
              : what,
        ),
        duration: const Duration(seconds: 7),
        persist: false,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => cubit.undoBusAssignment(result),
        ),
      ),
    );
  }

  String _busLabel(int bus) {
    if (bus <= 0) return 'None';
    final local = _lastProfile.localNumber(bus);
    if (_lastProfile.isInput(bus)) return 'I$local';
    if (_lastProfile.isOutput(bus)) return 'O$local';
    if (_lastProfile.isAux(bus)) return 'A$local';
    final es5Index = _lastProfile.contextualEs5Buses.indexOf(bus);
    return es5Index >= 0 ? 'ES${es5Index + 1}' : 'Bus $bus';
  }

  _BusLanesData? _buildData(
    List<RoutingAlgorithm> algorithms,
    Map<String, OutputMode> portOutputModes,
    DeviceIoProfile deviceIoProfile,
    bool isDark,
  ) {
    final slots = List<RoutingAlgorithm>.from(algorithms)
      ..sort((a, b) => a.index.compareTo(b.index));
    if (slots.isEmpty) return null;
    final n = slots.length;

    OutputMode modeOf(Port p) =>
        portOutputModes[p.id] ?? p.outputMode ?? OutputMode.add;

    final usedBuses = <int>{};
    for (final algo in slots) {
      for (final p in [...algo.inputPorts, ...algo.outputPorts]) {
        final b = p.busValue;
        if (b != null && b > 0) usedBuses.add(b);
      }
    }

    // Only show buses actually in use (sorted). With nothing used, "＋" is the
    // first lane; as buses get used they appear in order; when the last user of
    // a bus is removed it collapses out of the diagram. Any bus is reachable by
    // dropping a bead on "＋".
    final visible =
        usedBuses
            .where(
              (bus) =>
                  deviceIoProfile.contains(bus) ||
                  deviceIoProfile.contextualEs5Buses.contains(bus),
            )
            .toList()
          ..sort();
    final railIndex = {for (var i = 0; i < visible.length; i++) visible[i]: i};
    _lastVisibleBuses = visible;
    _lastProfile = deviceIoProfile;

    final cardHeights = [
      for (final a in slots)
        BusLanesMetrics.cardHeightFor(
          a.inputPorts.length + a.outputPorts.length,
        ),
    ];
    final cardTops = <double>[];
    var y = BusLanesMetrics.headerHeight;
    for (final h in cardHeights) {
      cardTops.add(y);
      y += h;
    }
    final metrics = BusLanesMetrics(
      columnCount: 2 + visible.length, // None + lanes + "＋"
      cardTops: cardTops,
      cardHeights: cardHeights,
    );
    _lastMetrics = metrics;

    // Colors originate from the signal (the originating output), not the bus.
    Color signalTubeColor(int signalId, int addDepth) =>
        BusColorPalette.withAddDepth(
          BusColorPalette.signalColor(signalId, isDark: isDark),
          addDepth,
          isDark: isDark,
        );
    // Collect write events (global y, in evaluation order) per bus. Each write
    // carries a stable [origin] id — the output's fixed ordinal across all
    // slots — so any signal it starts is colored by *which output* started it,
    // independent of how many other signals exist or their Add/Replace state.
    final writeYsByBus = <int, List<({double y, bool replace, int origin})>>{};
    var outputOrdinal = 0;
    for (var s = 0; s < n; s++) {
      final algo = slots[s];
      final nIn = algo.inputPorts.length;
      for (var o = 0; o < algo.outputPorts.length; o++) {
        final p = algo.outputPorts[o];
        final b = p.busValue;
        // Output-originated signal ids start past inputMax so they never
        // collide with physical-input ids (which use the bus number, 1-12).
        final origin = deviceIoProfile.inputBusCount + 1 + outputOrdinal;
        outputOrdinal++;
        if (b != null && b > 0 && railIndex.containsKey(b)) {
          (writeYsByBus[b] ??= []).add((
            y: cardTops[s] + BusLanesMetrics.portRowY(nIn + o),
            replace: modeOf(p) == OutputMode.replace,
            origin: origin,
          ));
        }
      }
    }

    // Per-bus colored "stops" top→bottom. A non-input bus is grey above its
    // first writer (no signal); from the first writer down it carries the
    // session color. Physical inputs are driven (hardware) from the top.
    const capGap = 5.0;
    final theme = Theme.of(context);
    final grey = BusColorPalette.empty(
      0,
      neutralColor: theme.appColors.emptyBus,
    );
    final laneLabel = theme.colorScheme.onSurfaceVariant;
    final changesByBus =
        <int, List<({double y, Color color, bool driven, bool cap})>>{};
    final rails = <BusRailRender>[];
    for (final b in visible) {
      final isInput = deviceIoProfile.isInput(b);
      final writes = writeYsByBus[b] ?? const [];

      final changes = <({double y, Color color, bool driven, bool cap})>[];
      final caps = <LaneCap>[];
      var driven = isInput;
      // A physical input's signal is keyed by its bus number, so the same
      // input always reads the same color; a write's signal is keyed by the
      // output that started it (w.origin). Neither shifts when an unrelated
      // output toggles Add/Replace.
      var signalId = isInput ? b : -1;
      var addDepth = 0;
      changes.add((
        y: metrics.railsTop,
        color: isInput ? signalTubeColor(signalId, 0) : grey,
        driven: isInput,
        cap: false,
      ));
      for (final w in writes) {
        if (w.replace) {
          signalId = w.origin;
          driven = true;
          addDepth = 0;
        } else if (!driven) {
          signalId = w.origin;
          driven = true;
          addDepth = 0;
        } else {
          addDepth++;
        }
        final c = signalTubeColor(signalId, addDepth);
        changes.add((y: w.y, color: c, driven: true, cap: w.replace));
      }
      changesByBus[b] = changes;

      // Full-height tube: grey where there's no signal, the signal's color
      // where driven, down to the bottom (the physical output for output
      // buses). Just above a replace the old signal fades out, then a cap + gap
      // starts the new signal's color.
      final segs = <LaneSegment>[];
      for (var i = 0; i < changes.length; i++) {
        final segTop = changes[i].y + (changes[i].cap ? capGap : 0);
        final segBottom = i + 1 < changes.length
            ? changes[i + 1].y
            : metrics.railsBottom;
        final fade = i + 1 < changes.length && changes[i + 1].cap;
        if (segBottom > segTop) {
          segs.add(
            LaneSegment(
              segTop,
              segBottom,
              changes[i].color,
              changes[i].driven,
              fadeBottom: fade && changes[i].driven,
            ),
          );
        }
      }
      rails.add(
        BusRailRender(
          bus: b,
          x: metrics.columnX(railIndex[b]! + 1),
          label: _busLabel(b),
          labelColor: laneLabel,
          segments: segs,
          caps: caps,
        ),
      );
    }

    // Signal at [bus]/[y]: the latest stop at/above y. Reads look strictly
    // above (signal flows down); a write is inclusive of itself. Returns null
    // when there is no signal (grey) there.
    Color? signalAt(int bus, double y, {required bool inclusive}) {
      Color? c;
      for (final ch in changesByBus[bus] ?? const []) {
        if (inclusive ? ch.y <= y + 0.01 : ch.y < y - 0.01) {
          c = ch.driven ? ch.color : null;
        } else {
          break;
        }
      }
      return c;
    }

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final cards = <_CardData>[];
    for (var s = 0; s < n; s++) {
      final algo = slots[s];
      final ports = <PortRowRender>[];
      final beads = <_Bead>[];
      final isConditionalInPlace = core_routing
          .AlgorithmRouting.isConditionalInPlaceGuid(algo.algorithm.guid);

      String channelPrefix(String? busParam) {
        if (busParam == null) return '';
        final colon = busParam.indexOf(':');
        return colon >= 0 ? busParam.substring(0, colon + 1) : '';
      }

      int? matchingInputBus(Port outputPort) {
        if (!isConditionalInPlace) return null;
        final prefix = channelPrefix(outputPort.busParam);
        for (final inputPort in algo.inputPorts) {
          if (channelPrefix(inputPort.busParam) != prefix) continue;
          final bus = inputPort.busValue ?? 0;
          return bus > 0 ? bus : null;
        }
        return null;
      }

      void addPort(Port p, bool isOutput, int row) {
        final bus = p.busValue ?? 0;
        final connected = bus > 0 && railIndex.containsKey(bus);
        final column = connected ? railIndex[bus]! + 1 : 0;
        final beadX = metrics.columnX(column);
        final beadY = BusLanesMetrics.portRowY(row);
        final globalY = cardTops[s] + beadY;

        Color color;
        var unprovided = false;
        if (!connected) {
          color = muted;
        } else if (isOutput) {
          color = signalAt(bus, globalY, inclusive: true) ?? grey;
        } else {
          final incoming = signalAt(bus, globalY, inclusive: false);
          if (incoming != null) {
            color = incoming;
          } else {
            unprovided = true;
            color = BusColorPalette.empty(
              bus,
              neutralColor: theme.appColors.emptyBus,
            );
          }
        }

        ports.add(
          PortRowRender(
            label: p.name,
            isOutput: isOutput,
            row: row,
            beadX: beadX,
            connected: connected,
            color: color,
            write: !isOutput
                ? BandWrite.none
                : (modeOf(p) == OutputMode.replace
                      ? BandWrite.replace
                      : BandWrite.add),
            unprovided: unprovided,
          ),
        );
        beads.add(
          _Bead(
            x: beadX,
            y: beadY,
            color: color,
            connected: connected,
            unprovided: unprovided,
            ref: _PortRef(
              algorithmIndex: algo.index,
              parameterNumber: p.parameterNumber ?? -1,
              modeParam: p.modeParameterNumber,
              previousBus: bus,
              isOutput: isOutput,
              portId: p.id,
              label: p.name,
              matchingInputBus: isOutput ? matchingInputBus(p) : null,
            ),
          ),
        );
      }

      var row = 0;
      for (final p in algo.inputPorts) {
        addPort(p, false, row++);
      }
      for (final p in algo.outputPorts) {
        addPort(p, true, row++);
      }

      cards.add(
        _CardData(
          id: algo.id,
          title: '${algo.index + 1}. ${algo.algorithm.name}',
          ports: ports,
          beads: beads,
        ),
      );
    }

    return _BusLanesData(metrics: metrics, rails: rails, cards: cards);
  }
}

class _BlockColors {
  final Color card;
  final Color border;
  final Color text;
  final Color muted;
  final Color error;
  const _BlockColors({
    required this.card,
    required this.border,
    required this.text,
    required this.muted,
    required this.error,
  });
}

class _PortRef {
  final int algorithmIndex;
  final int parameterNumber;
  final int? modeParam;
  final int previousBus;
  final bool isOutput;
  final String portId;
  final String label;
  final int? matchingInputBus;
  const _PortRef({
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.modeParam,
    required this.previousBus,
    required this.isOutput,
    required this.portId,
    required this.label,
    required this.matchingInputBus,
  });

  bool appliesOnSameBus(int bus) =>
      isOutput && matchingInputBus != null && bus == matchingInputBus;
}

class _Bead {
  final double x;
  final double y;
  final Color color;
  final bool connected;

  /// An input reading a bus with no signal present at this point.
  final bool unprovided;
  final _PortRef ref;
  const _Bead({
    required this.x,
    required this.y,
    required this.color,
    required this.connected,
    required this.unprovided,
    required this.ref,
  });
}

class _CardData {
  final String id;
  final String title;
  final List<PortRowRender> ports;
  final List<_Bead> beads;
  const _CardData({
    required this.id,
    required this.title,
    required this.ports,
    required this.beads,
  });
}

class _BusLanesData {
  final BusLanesMetrics metrics;
  final List<BusRailRender> rails;
  final List<_CardData> cards;
  const _BusLanesData({
    required this.metrics,
    required this.rails,
    required this.cards,
  });
}
