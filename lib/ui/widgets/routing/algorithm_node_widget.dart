import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/ui/widgets/mapping_editor_bottom_sheet.dart';

import 'package:nt_helper/ui/widgets/routing/port_widget.dart';

// No direct dependency on RoutingEditorWidget static members

/// A draggable widget representing an algorithm node in the routing editor.
///
/// Features:
/// - Draggable with precise coordinate transforms
/// - Title bar showing algorithm name and slot number
/// - Toolbar with up/down/delete actions
/// - Input and output connection points
/// - Theme-aware styling
class AlgorithmNodeWidget extends StatefulWidget {
  final String algorithmName;
  final String? algorithmGuid;
  final int slotNumber;
  // Position is now handled by parent Positioned widget
  final Offset position;
  // Optional leading icon for the top bar
  final Widget? leadingIcon;
  final bool isSelected;
  final Function(Offset)? onPositionChanged;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final List<String> inputLabels;
  final List<String> outputLabels;
  final Widget? virtualCvInputs;
  // Port IDs aligned with labels, used for accurate connection anchors
  final List<String>? inputPortIds;
  final List<String>? outputPortIds;
  // Channel numbers aligned with output labels (for ES-5 toggle support)
  final List<int>? outputChannelNumbers;
  // Set of port IDs that are currently connected
  final Set<String>? connectedPorts;
  // Set of output port IDs that are shadowed (red dot indicator)
  final Set<String>? shadowedPortIds;
  // Callback to report per-port anchor global position
  final void Function(String portId, Offset globalCenter, bool isInput)?
  onPortPositionResolved;

  // Callback for routing actions from ports
  final void Function(String portId, String action)? onRoutingAction;

  // Callback when a port is tapped
  final void Function(String portId)? onPortTapped;

  // Callback when a port is long-pressed (for connection deletion)
  final void Function(String portId)? onPortLongPress;

  // Callback when long press starts on a port (for animated deletion)
  final void Function(String portId)? onPortLongPressStart;

  // Callback when long press is cancelled on a port
  final VoidCallback? onPortLongPressCancel;

  // Port drag callbacks for connection creation
  final void Function(String portId)? onPortDragStart;
  final void Function(String portId, Offset position)? onPortDragUpdate;
  final void Function(String portId, Offset position)? onPortDragEnd;

  // ID of the port that should be highlighted (during drag operations)
  final String? highlightedPortId;

  // ES-5 direct output support (for Clock/Euclidean algorithms)
  // Map of channel number to ES-5 Expander enabled state
  final Map<int, bool>? es5ChannelToggles;
  // Map of channel number to ES-5 Expander parameter number
  final Map<int, int>? es5ExpanderParameterNumbers;
  // Callback when ES-5 toggle is changed
  final void Function(int channel, bool enabled)? onEs5ToggleChanged;

  // Callback to report the actual rendered size of the node
  final ValueChanged<Size>? onSizeResolved;

  // Whether this node should be dimmed (not in focus during focus mode)
  final bool isDimmed;

  const AlgorithmNodeWidget({
    super.key,
    required this.algorithmName,
    this.algorithmGuid,
    required this.slotNumber,
    required this.position,
    this.leadingIcon,
    this.isSelected = false,
    this.onPositionChanged,
    this.onDragStart,
    this.onDragEnd,
    this.onMoveUp,
    this.onMoveDown,
    this.onDelete,
    this.onTap,
    this.inputLabels = const [],
    this.outputLabels = const [],
    this.virtualCvInputs,
    this.inputPortIds,
    this.outputPortIds,
    this.outputChannelNumbers,
    this.connectedPorts,
    this.shadowedPortIds,
    this.onPortPositionResolved,
    this.onRoutingAction,
    this.onPortTapped,
    this.onPortLongPress,
    this.onPortLongPressStart,
    this.onPortLongPressCancel,
    this.onPortDragStart,
    this.onPortDragUpdate,
    this.onPortDragEnd,
    this.highlightedPortId,
    this.es5ChannelToggles,
    this.es5ExpanderParameterNumbers,
    this.onEs5ToggleChanged,
    this.onSizeResolved,
    this.isDimmed = false,
  });

  @override
  State<AlgorithmNodeWidget> createState() => _AlgorithmNodeWidgetState();
}

class _AlgorithmNodeWidgetState extends State<AlgorithmNodeWidget> {
  bool _isDragging = false;
  bool _isCollapsed = false;
  // Track drag start and initial position for stable deltas
  Offset _dragStartGlobal = Offset.zero;
  Offset _initialPosition = Offset.zero;
  double _dragScale = 1.0;

  final GlobalKey _containerKey = GlobalKey();
  Size? _lastSize;

  // Focus and keyboard navigation state
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;
  int _focusedPortIndex = -1; // -1 = node level (no port focused)
  List<String?> _visiblePortIds = [];

  @override
  void initState() {
    super.initState();
    _scheduleSizeReport();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AlgorithmNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSizeReport();
    if (widget.inputLabels.length != oldWidget.inputLabels.length ||
        widget.outputLabels.length != oldWidget.outputLabels.length) {
      _focusedPortIndex = -1;
    }
  }

  void _scheduleSizeReport() {
    if (widget.onSizeResolved == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _containerKey.currentContext;
      if (context == null) return;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) return;

      final size = renderBox.size;
      if (_lastSize != size) {
        _lastSize = size;
        widget.onSizeResolved!(size);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final inputCount = widget.inputLabels.length;
    final outputCount = widget.outputLabels.length;
    final connectedCount = widget.connectedPorts?.length ?? 0;

    Widget content = Focus(
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        setState(() {
          _hasFocus = hasFocus;
          if (!hasFocus) _focusedPortIndex = -1;
        });
      },
      onKeyEvent: _handleNodeKeyEvent,
      child: Semantics(
        label:
            'Slot ${widget.slotNumber}: ${widget.algorithmName}, $inputCount inputs, $outputCount outputs, $connectedCount connected',
        hint: _focusedPortIndex >= 0
            ? 'In port navigation. Arrow keys to move between ports. Escape to exit.'
            : 'Press Enter to navigate ports. Tab to next node.',
        container: true,
        selected: widget.isSelected,
        focused: _hasFocus,
        child: GestureDetector(
          onTap: () {
            widget.onTap?.call();
          },
          onPanStart: _handleDragStart,
          onPanUpdate: _handleDragUpdate,
          onPanEnd: _handleDragEnd,
          child: AnimatedContainer(
            key: _containerKey,
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? theme.colorScheme.tertiary
                    : _hasFocus
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withAlpha(179),
                width: (widget.isSelected || _hasFocus) ? 3 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withAlpha(
                    _isDragging ? 77 : 26,
                  ),
                  blurRadius: _isDragging ? 8 : 4,
                  offset: Offset(0, _isDragging ? 4 : 2),
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTitleBar(theme),
                  _buildPorts(theme),
                  if (_shouldShowCollapseToggle()) _buildCollapseToggle(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Apply dimming for focus mode
    if (widget.isDimmed) {
      content = Opacity(opacity: 0.3, child: content);
    }

    return content;
  }

  KeyEventResult _handleNodeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedPortIndex < 0 && _visiblePortIds.isNotEmpty) {
        setState(() {
          _focusedPortIndex = 0;
        });
        return KeyEventResult.handled;
      }
      if (_focusedPortIndex >= 0) {
        _activateFocusedPort();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_focusedPortIndex >= 0) {
        setState(() {
          _focusedPortIndex = -1;
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _focusedPortIndex >= 0) {
      if (_visiblePortIds.isNotEmpty) {
        setState(() {
          _focusedPortIndex = (_focusedPortIndex + 1).clamp(
            0,
            _visiblePortIds.length - 1,
          );
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        _focusedPortIndex >= 0) {
      if (_visiblePortIds.isNotEmpty) {
        setState(() {
          _focusedPortIndex = (_focusedPortIndex - 1).clamp(
            0,
            _visiblePortIds.length - 1,
          );
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.space &&
        _focusedPortIndex >= 0) {
      _activateFocusedPort();
      return KeyEventResult.handled;
    }

    if ((event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) &&
        _focusedPortIndex >= 0) {
      _deleteFocusedPortConnections();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _activateFocusedPort() {
    if (_focusedPortIndex < 0 || _focusedPortIndex >= _visiblePortIds.length) {
      return;
    }
    final portId = _visiblePortIds[_focusedPortIndex];
    if (portId != null) {
      widget.onPortTapped?.call(portId);
    }
  }

  void _deleteFocusedPortConnections() {
    if (_focusedPortIndex < 0 || _focusedPortIndex >= _visiblePortIds.length) {
      return;
    }
    final portId = _visiblePortIds[_focusedPortIndex];
    if (portId != null) {
      widget.onPortLongPress?.call(portId);
    }
  }

  int _unconnectedPortCount() {
    final connected = widget.connectedPorts ?? {};
    int count = 0;
    if (widget.inputPortIds != null) {
      for (final id in widget.inputPortIds!) {
        if (!connected.contains(id)) count++;
      }
    }
    if (widget.outputPortIds != null) {
      for (final id in widget.outputPortIds!) {
        if (!connected.contains(id)) count++;
      }
    }
    return count;
  }

  bool _shouldShowCollapseToggle() => _unconnectedPortCount() > 5;

  Widget _buildTitleBar(ThemeData theme) {
    // Use app bar theming for better readability and consistency
    final backgroundColor =
        (theme.appBarTheme.backgroundColor ??
                theme.colorScheme.surfaceContainerHigh)
            .withValues(alpha: 0.7);
    final foregroundColor =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leadingIcon != null) ...[
            IconTheme(
              data: IconThemeData(color: foregroundColor, size: 18),
              child: widget.leadingIcon!,
            ),
            const SizedBox(width: 8),
          ],
          // Show mapping icon if any parameters are mapped
          if (_hasAnyMappings()) ...[
            Semantics(
              label: 'Has parameter mappings',
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.map_sharp,
                  size: 16,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Title with slot number pre-pended
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                right: 12.0,
              ), // Add space after title per Material 3 specs
              child: _buildTitleText(theme, foregroundColor),
            ),
          ),
          // Up/Down actions always present; disabled when not applicable
          // Material 3 specs: use density for closer action spacing
          IconButton(
            tooltip: 'Move Up',
            icon: const Icon(
              Icons.arrow_upward,
              size: 18,
              semanticLabel: 'Move Up',
            ),
            onPressed: widget.onMoveUp,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Move Down',
            icon: const Icon(
              Icons.arrow_downward,
              size: 18,
              semanticLabel: 'Move Down',
            ),
            onPressed: widget.onMoveDown,
            visualDensity: VisualDensity.compact,
          ),
          // Overflow menu: mapped parameters and delete
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: foregroundColor,
              semanticLabel: 'More',
            ),
            itemBuilder: (context) {
              List<PopupMenuEntry<String>> items = [];

              // Add mapped parameter items first
              final cubit = context.read<DistingCubit>();
              final state = cubit.state;
              if (state is DistingStateSynchronized) {
                final slotIndex = widget.slotNumber - 1;
                if (slotIndex >= 0 && slotIndex < state.slots.length) {
                  final slot = state.slots[slotIndex];

                  // Find mapped parameters by checking both parameters list and mappings
                  final mappedParams =
                      <({ParameterInfo param, Mapping mapping})>[];
                  for (int i = 0; i < slot.mappings.length; i++) {
                    final mapping = slot.mappings.elementAtOrNull(i);
                    if (mapping != null &&
                        mapping.packedMappingData !=
                            PackedMappingData.filler() &&
                        mapping.packedMappingData.isMapped()) {
                      // Find corresponding parameter info
                      final param = slot.parameters
                          .where(
                            (p) => p.parameterNumber == mapping.parameterNumber,
                          )
                          .firstOrNull;
                      if (param != null) {
                        mappedParams.add((param: param, mapping: mapping));
                      }
                    }
                  }

                  for (final mappedParam in mappedParams) {
                    items.add(
                      PopupMenuItem(
                        value: 'mapping_${mappedParam.param.parameterNumber}',
                        child: Row(
                          children: [
                            const Icon(Icons.map_sharp, size: 18),
                            const SizedBox(width: 8),
                            Text(mappedParam.param.name),
                          ],
                        ),
                      ),
                    );
                  }

                  if (mappedParams.isNotEmpty) {
                    items.add(const PopupMenuDivider());
                  }
                }
              }

              // Reset all connections item
              items.add(
                const PopupMenuItem(
                  value: 'reset_connections',
                  child: Row(
                    children: [
                      Icon(Icons.link_off, size: 18),
                      SizedBox(width: 8),
                      Text('Disconnect'),
                    ],
                  ),
                ),
              );

              items.add(const PopupMenuDivider());

              // Add existing delete item
              items.add(
                PopupMenuItem(
                  value: 'delete',
                  enabled: widget.onDelete != null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Delete',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ),
              );

              return items;
            },
            onSelected: (value) {
              if (value == 'delete') {
                _handleDelete();
              } else if (value == 'reset_connections') {
                _handleResetConnections();
              } else if (value.startsWith('mapping_')) {
                final paramNumber = int.parse(value.substring(8));
                _handleMappingEdit(paramNumber);
              }
            },
          ),
        ],
      ),
    );
  }

  // Removed old overflow-only toolbar; actions are now visible icon buttons with delete in overflow

  Widget _buildPorts(ThemeData theme) {
    final connected = widget.connectedPorts ?? {};

    // Build filtered input list
    final filteredInputs = <({String label, String? portId})>[];
    for (int i = 0; i < widget.inputLabels.length; i++) {
      final portId =
          (widget.inputPortIds != null && i < widget.inputPortIds!.length)
          ? widget.inputPortIds![i]
          : null;
      if (_isCollapsed && portId != null && !connected.contains(portId)) {
        continue;
      }
      filteredInputs.add((label: widget.inputLabels[i], portId: portId));
    }

    // Build filtered output list
    final filteredOutputs =
        <({String label, String? portId, int? channelNumber})>[];
    for (int i = 0; i < widget.outputLabels.length; i++) {
      final portId =
          (widget.outputPortIds != null && i < widget.outputPortIds!.length)
          ? widget.outputPortIds![i]
          : null;
      final channelNumber =
          (widget.outputChannelNumbers != null &&
              i < widget.outputChannelNumbers!.length)
          ? widget.outputChannelNumbers![i]
          : null;
      if (_isCollapsed && portId != null && !connected.contains(portId)) {
        continue;
      }
      filteredOutputs.add((
        label: widget.outputLabels[i],
        portId: portId,
        channelNumber: channelNumber,
      ));
    }

    // Track visible ports for keyboard navigation
    _visiblePortIds = [
      ...filteredInputs.map((i) => i.portId),
      ...filteredOutputs.map((o) => o.portId),
    ];
    // Clamp focused index if ports changed
    if (_focusedPortIndex >= _visiblePortIds.length) {
      _focusedPortIndex = _visiblePortIds.isEmpty
          ? -1
          : _visiblePortIds.length - 1;
    }

    int portFocusIndex = 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inputs (natural width)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final input in filteredInputs)
                _buildPort(
                  theme,
                  input.label,
                  true,
                  portId: input.portId,
                  focusIndex: portFocusIndex++,
                ),
              if (widget.virtualCvInputs != null) widget.virtualCvInputs!,
            ],
          ),
          const SizedBox(width: 16),
          // Flexible spacer pushes outputs to the far right edge
          const Expanded(child: SizedBox.shrink()),
          // Outputs (flush right)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final output in filteredOutputs)
                _buildPort(
                  theme,
                  output.label,
                  false,
                  portId: output.portId,
                  channelNumber: output.channelNumber,
                  focusIndex: portFocusIndex++,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollapseToggle(ThemeData theme) {
    final unconnected = _unconnectedPortCount();
    final color = theme.colorScheme.onSurface.withAlpha(153);
    return Semantics(
      button: true,
      label: _isCollapsed
          ? 'Show $unconnected hidden ports'
          : 'Hide unconnected ports',
      child: InkWell(
        onTap: () {
          setState(() {
            _isCollapsed = !_isCollapsed;
          });
          _scheduleSizeReport();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isCollapsed ? Icons.unfold_more : Icons.unfold_less,
                size: 16,
                color: color,
              ),
              if (_isCollapsed) ...[
                const SizedBox(width: 4),
                Text(
                  '+$unconnected hidden',
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPort(
    ThemeData theme,
    String label,
    bool isInput, {
    String? portId,
    int? channelNumber,
    int? focusIndex,
  }) {
    final isConnected =
        portId != null && (widget.connectedPorts?.contains(portId) ?? false);
    final showShadowDot =
        !isInput &&
        portId != null &&
        (widget.shadowedPortIds?.contains(portId) ?? false);

    // Check if this output port has an ES-5 toggle
    final hasEs5Toggle =
        !isInput &&
        channelNumber != null &&
        widget.es5ChannelToggles != null &&
        widget.es5ChannelToggles!.containsKey(channelNumber);

    final isEs5Enabled =
        hasEs5Toggle && (widget.es5ChannelToggles![channelNumber] ?? false);

    Widget portWidget = PortWidget(
      label: label,
      isInput: isInput,
      portId: portId,
      labelPosition: isInput ? PortLabelPosition.right : PortLabelPosition.left,
      theme: theme,
      isConnected: isConnected, // Keep using the passed connection info for algorithm ports
      isHighlighted: portId != null && portId == widget.highlightedPortId,
      showShadowDot: showShadowDot,
      isFocused: focusIndex != null && focusIndex == _focusedPortIndex,
      onPortPositionResolved: widget.onPortPositionResolved,
      onRoutingAction: widget.onRoutingAction,
      // Long-press to delete - available on both inputs and outputs
      onLongPress: portId != null && widget.onPortLongPress != null
          ? () => widget.onPortLongPress!(portId)
          : null,
      // Animated long press (for desktop)
      onLongPressStart: portId != null && widget.onPortLongPressStart != null
          ? () => widget.onPortLongPressStart!(portId)
          : null,
      onLongPressCancel: widget.onPortLongPressCancel,
      // Drag to create connections - now available on both inputs and outputs
      onDragStart: portId != null && widget.onPortDragStart != null
          ? () => widget.onPortDragStart!(portId)
          : null,
      onDragUpdate: portId != null && widget.onPortDragUpdate != null
          ? (position) => widget.onPortDragUpdate!(portId, position)
          : null,
      onDragEnd: portId != null && widget.onPortDragEnd != null
          ? (position) => widget.onPortDragEnd!(portId, position)
          : null,
    );

    // If this port has an ES-5 toggle, wrap it with the toggle button
    if (hasEs5Toggle) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ES-5 toggle button
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: isEs5Enabled ? 'ES-5 Mode: On' : 'ES-5 Mode: Off',
              icon: Icon(
                Icons.output,
                semanticLabel: isEs5Enabled
                    ? 'ES-5 Mode: On'
                    : 'ES-5 Mode: Off',
                color: isEs5Enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withAlpha(128),
              ),
              onPressed: widget.onEs5ToggleChanged != null
                  ? () =>
                        widget.onEs5ToggleChanged!(channelNumber, !isEs5Enabled)
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          portWidget,
        ],
      );
    }

    return portWidget;
  }

  String? _originalAlgorithmName() {
    final guid = widget.algorithmGuid;
    if (guid == null) return null;
    final original = AlgorithmMetadataService().getAlgorithmByGuid(guid)?.name;
    if (original == null || original == widget.algorithmName) return null;
    return original;
  }

  Widget _buildTitleText(ThemeData theme, Color foregroundColor) {
    final originalName = _originalAlgorithmName();
    if (originalName == null) {
      return Text(
        '#${widget.slotNumber} ${_truncateWithEllipsis(widget.algorithmName, 25)}',
        style: theme.textTheme.titleSmall?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        softWrap: false,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '#${widget.slotNumber} ${_truncateWithEllipsis(widget.algorithmName, 25)}',
          style: theme.textTheme.titleSmall?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        Text(
          originalName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foregroundColor.withAlpha(153),
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ],
    );
  }

  String _truncateWithEllipsis(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}…';
  }

  void _handleDragStart(DragStartDetails details) {
    // Capture the local-to-global scale factor from the render tree.
    // This accounts for any ancestor Transform.scale (e.g. canvas zoom).
    final box = context.findRenderObject() as RenderBox?;
    _dragScale = box != null ? box.getTransformTo(null).entry(0, 0) : 1.0;

    setState(() {
      _isDragging = true;
      _dragStartGlobal = details.globalPosition;
      _initialPosition = widget.position;
    });

    // Notify parent that a drag has begun
    widget.onDragStart?.call();
  }

  // Toolbar action handlers removed; actions call callbacks directly

  Future<void> _handleResetConnections() async {
    final algorithmIndex = widget.slotNumber - 1;
    await context.read<RoutingEditorCubit>().resetAllConnections(
      algorithmIndex,
    );
  }

  void _handleDelete() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Algorithm'),
        content: Text(
          'Are you sure you want to delete "${widget.algorithmName}" from slot #${widget.slotNumber}?',
        ),
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

    if (confirmed != true) {
      return;
    }

    if (!mounted) return;
    final cubit = context.read<DistingCubit>();
    try {
      // Slot numbers are 1-indexed, but the cubit uses 0-indexed
      final algorithmIndex = widget.slotNumber - 1;

      await cubit.onRemoveAlgorithm(algorithmIndex);
      widget.onDelete?.call();
    } catch (e) {
      _showFeedback('Failed to delete algorithm: $e', isError: true);
    }
  }

  Future<void> _handleMappingEdit(int parameterNumber) =>
      showParameterMappingEditor(
        context,
        algorithmIndex: widget.slotNumber - 1,
        parameterNumber: parameterNumber,
      );

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted || !isError) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    // Compute new position from drag delta relative to drag start,
    // accounting for canvas zoom level (screen pixels != canvas pixels)
    final dragDelta = (details.globalPosition - _dragStartGlobal) / _dragScale;
    final newPosition = _initialPosition + dragDelta;

    // Snap to grid
    const double gridSize = 50.0;
    final snappedPosition = Offset(
      (newPosition.dx / gridSize).round() * gridSize,
      (newPosition.dy / gridSize).round() * gridSize,
    );

    // Constrain to canvas bounds
    const double canvasSize = 5000.0;
    final constrainedPosition = Offset(
      snappedPosition.dx.clamp(0.0, canvasSize - 200),
      snappedPosition.dy.clamp(0.0, canvasSize - 100),
    );

    widget.onPositionChanged?.call(constrainedPosition);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    // Notify parent that drag ended
    widget.onDragEnd?.call();
  }

  /// Check if the slot has any mapped parameters
  bool _hasAnyMappings() {
    // Get slot data from cubit to check for mappings. In tests, the provider
    // may be absent; in that case, default to false (no mappings).
    DistingCubit cubit;
    try {
      cubit = context.read<DistingCubit>();
    } catch (_) {
      return false;
    }
    final state = cubit.state;

    if (state is! DistingStateSynchronized) {
      return false;
    }

    // Find the slot by index (slot numbers are 1-indexed, but list is 0-indexed)
    final slotIndex = widget.slotNumber - 1;
    if (slotIndex < 0 || slotIndex >= state.slots.length) {
      return false;
    }

    final slot = state.slots[slotIndex];

    // Check if any parameter has a mapping that's not empty/filler
    for (int i = 0; i < slot.mappings.length; i++) {
      final mapping = slot.mappings.elementAtOrNull(i);
      if (mapping != null &&
          mapping.packedMappingData != PackedMappingData.filler() &&
          mapping.packedMappingData.isMapped()) {
        return true;
      }
    }

    return false;
  }
}

// Removed dependency on RoutingEditorWidget static values
