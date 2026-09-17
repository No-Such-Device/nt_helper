import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';

/// Called once when a memory-detail surface changes from closed to open.
typedef MemoryDetailOpenedCallback = FutureOr<void> Function();

/// Calls [onOpened] once for each mount of a memory-detail surface.
///
/// The bottom-bar detail overlay and the System dialog can share this hook.
/// Rebuilding an already-open surface does not request another refresh; after
/// the surface is removed, mounting a new hook represents a later opening.
class MemoryDetailOpeningHook extends StatefulWidget {
  const MemoryDetailOpeningHook({
    super.key,
    required this.onOpened,
    required this.child,
  });

  final MemoryDetailOpenedCallback onOpened;
  final Widget child;

  @override
  State<MemoryDetailOpeningHook> createState() =>
      _MemoryDetailOpeningHookState();
}

class _MemoryDetailOpeningHookState extends State<MemoryDetailOpeningHook> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOpened();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Presents a compact, read-only view of the four device memory pools.
class MemoryDetailPresenter extends StatelessWidget {
  const MemoryDetailPresenter({super.key, required this.state});

  final MemoryDisplayState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sample = state.sample;
    final pools = <_MemoryPoolPresentation>[
      _MemoryPoolPresentation('SRAM', sample?.sram, colorScheme.primary),
      _MemoryPoolPresentation('DRAM', sample?.dram, colorScheme.secondary),
      _MemoryPoolPresentation('DTC', sample?.dtc, colorScheme.tertiary),
      _MemoryPoolPresentation('ITC', sample?.itc, colorScheme.error),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Memory details',
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Memory',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    _MemoryFreshnessStatus(status: state.status),
                  ],
                ),
                const SizedBox(height: 8),
                const _MemoryColumnHeadings(),
                const SizedBox(height: 4),
                for (final pool in pools) _MemoryPoolRow(pool: pool),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds accessible mouse, keyboard and touch opening behavior around [child].
///
/// [initialState] and [stateStream] are the connection-local display state.
/// The overlay remains mounted while open, so state changes update the values
/// without turning refresh, focus, hover, tap or keyboard events into another
/// opening. Escape dismisses the overlay from any opening mode.
class MemoryDetailOpener extends StatefulWidget {
  const MemoryDetailOpener({
    super.key,
    required this.initialState,
    required this.stateStream,
    required this.onOpened,
    this.child,
    this.childBuilder,
    this.semanticLabel = 'Show memory details',
    this.targetAnchor = Alignment.topCenter,
    this.followerAnchor = Alignment.bottomCenter,
    this.offset = const Offset(0, -8),
  }) : assert((child == null) != (childBuilder == null));

  final MemoryDisplayState initialState;
  final Stream<MemoryDisplayState> stateStream;
  final MemoryDetailOpenedCallback onOpened;
  final Widget? child;
  final Widget Function(BuildContext context, MemoryDisplayState state)?
  childBuilder;
  final String semanticLabel;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  State<MemoryDetailOpener> createState() => _MemoryDetailOpenerState();
}

class _MemoryDetailOpenerState extends State<MemoryDetailOpener> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode(debugLabel: 'Memory detail opener');

  late MemoryDisplayState _displayState;
  StreamSubscription<MemoryDisplayState>? _stateSubscription;
  OverlayEntry? _overlayEntry;
  bool _hovered = false;
  bool _showFocusHighlight = false;

  bool get _isOpen => _overlayEntry != null;

  @override
  void initState() {
    super.initState();
    _displayState = widget.initialState;
    _subscribeToState();
  }

  @override
  void didUpdateWidget(covariant MemoryDetailOpener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stateStream, widget.stateStream)) {
      unawaited(_stateSubscription?.cancel());
      _displayState = widget.initialState;
      _subscribeToState();
    } else if (!identical(oldWidget.initialState, widget.initialState)) {
      _displayState = widget.initialState;
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _overlayEntry?.remove();
    _overlayEntry = null;
    unawaited(_stateSubscription?.cancel());
    _focusNode.dispose();
    super.dispose();
  }

  void _subscribeToState() {
    _stateSubscription = widget.stateStream.listen((state) {
      _displayState = state;
      if (mounted && widget.childBuilder != null) {
        setState(() {});
      }
      _overlayEntry?.markNeedsBuild();
    });
  }

  void _open() {
    if (_isOpen || !mounted) return;

    final entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: widget.targetAnchor,
        followerAnchor: widget.followerAnchor,
        offset: widget.offset,
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: MemoryDetailOpeningHook(
            onOpened: widget.onOpened,
            child: MemoryDetailPresenter(state: _displayState),
          ),
        ),
      ),
    );
    _overlayEntry = entry;
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    Overlay.of(context, rootOverlay: true).insert(entry);
    setState(() {});
  }

  void _close() {
    final entry = _overlayEntry;
    if (entry == null) return;

    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _overlayEntry = null;
    entry.remove();
    if (mounted) setState(() {});
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _isOpen) {
      _close();
      return true;
    }
    return false;
  }

  void _handleFocusChange(bool focused) {
    if (focused) {
      _open();
    } else if (!_hovered) {
      _close();
    }
  }

  void _handlePointerEnter(PointerEnterEvent event) {
    _hovered = true;
    _open();
  }

  void _handlePointerExit(PointerExitEvent event) {
    _hovered = false;
    if (!_focusNode.hasFocus) _close();
  }

  void _handleActivation() {
    _focusNode.requestFocus();
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: _handlePointerEnter,
        onExit: _handlePointerExit,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                _open();
                return null;
              },
            ),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (intent) {
                _close();
                return null;
              },
            ),
          },
          onFocusChange: _handleFocusChange,
          onShowFocusHighlight: (show) {
            if (_showFocusHighlight == show) return;
            setState(() => _showFocusHighlight = show);
          },
          child: Semantics(
            container: true,
            button: true,
            focusable: true,
            focused: _focusNode.hasFocus,
            label: widget.semanticLabel,
            value: _isOpen ? 'Open' : 'Closed',
            onTap: _handleActivation,
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleActivation,
                child: ConstrainedBox(
                  key: const ValueKey('memory-detail-interaction-target'),
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _showFocusHighlight
                            ? colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child:
                          widget.childBuilder?.call(context, _displayState) ??
                          widget.child!,
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
}

/// Compact visual used by the wide-screen bottom-bar memory shortcut.
///
/// The icon and four pool columns stay within two small-text lines while the
/// surrounding [MemoryDetailOpener] retains the native interaction target.
class MemoryMiniature extends StatelessWidget {
  const MemoryMiniature({super.key, required this.state});

  final MemoryDisplayState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sample = state.sample;
    final pools = <(String, MemoryPoolUsage?, Color)>[
      ('SRAM', sample?.sram, colorScheme.primary),
      ('DRAM', sample?.dram, colorScheme.secondary),
      ('DTC', sample?.dtc, colorScheme.tertiary),
      ('ITC', sample?.itc, colorScheme.error),
    ];

    return SizedBox(
      key: const ValueKey('memory-miniature-visual'),
      width: 41,
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.memory,
            key: const ValueKey('memory-miniature-icon'),
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          for (var index = 0; index < pools.length; index++) ...[
            if (index > 0) const SizedBox(width: 2),
            _MemoryMiniatureColumn(
              key: ValueKey('memory-miniature-${pools[index].$1}'),
              color: pools[index].$3,
              usage: pools[index].$2,
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryMiniatureColumn extends StatelessWidget {
  const _MemoryMiniatureColumn({
    super.key,
    required this.color,
    required this.usage,
  });

  final Color color;
  final MemoryPoolUsage? usage;

  @override
  Widget build(BuildContext context) {
    final fraction = switch (usage) {
      MemoryPoolUsage(total: final total, current: final current)
          when total > 0 =>
        (current / total).clamp(0.0, 1.0),
      _ => 0.0,
    };

    return Container(
      width: 4,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: fraction,
        child: ColoredBox(color: color),
      ),
    );
  }
}

class _MemoryColumnHeadings extends StatelessWidget {
  const _MemoryColumnHeadings();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      children: [
        const SizedBox(width: 58),
        for (final label in const ['Current', 'Total', 'Free'])
          Expanded(
            child: Text(label, textAlign: TextAlign.end, style: style),
          ),
      ],
    );
  }
}

class _MemoryPoolRow extends StatelessWidget {
  const _MemoryPoolRow({required this.pool});

  final _MemoryPoolPresentation pool;

  @override
  Widget build(BuildContext context) {
    final values = <(String, int?)>[
      ('current', pool.usage?.current),
      ('total', pool.usage?.total),
      ('free', pool.usage?.free),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: pool.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              pool.name,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          for (final value in values)
            Expanded(
              child: _MemoryValue(
                semanticLabel:
                    '${pool.name} ${value.$1}, ${_formatBytes(value.$2)}',
                value: _formatBytes(value.$2),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemoryValue extends StatelessWidget {
  const _MemoryValue({required this.semanticLabel, required this.value});

  final String semanticLabel;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _MemoryFreshnessStatus extends StatelessWidget {
  const _MemoryFreshnessStatus({required this.status});

  final MemoryDisplayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final (label, semanticLabel, icon, refreshing) = switch (status) {
      MemoryDisplayStatus.unavailable => (
        'Unavailable',
        'Memory values unavailable',
        Icons.remove_circle_outline,
        false,
      ),
      MemoryDisplayStatus.refreshing => (
        'Refreshing',
        'Refreshing memory values',
        Icons.refresh,
        true,
      ),
      MemoryDisplayStatus.available => (
        'Updated',
        'Memory values updated',
        Icons.check_circle_outline,
        false,
      ),
      MemoryDisplayStatus.unfresh => (
        'Unfresh',
        'Memory values are unfresh because the latest refresh failed',
        Icons.schedule,
        false,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refreshing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

final class _MemoryPoolPresentation {
  const _MemoryPoolPresentation(this.name, this.usage, this.color);

  final String name;
  final MemoryPoolUsage? usage;
  final Color color;
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '—';

  const kibibyte = 1024;
  const mebibyte = 1024 * 1024;
  final magnitude = bytes.abs();
  if (magnitude >= mebibyte && (bytes * 100) % mebibyte == 0) {
    return '${_formatExactScale(bytes, mebibyte)} MiB';
  }
  if (magnitude >= kibibyte && (bytes * 100) % kibibyte == 0) {
    return '${_formatExactScale(bytes, kibibyte)} KiB';
  }
  return '$bytes B';
}

String _formatExactScale(int bytes, int unit) {
  final fixed = (bytes / unit).toStringAsFixed(2);
  final withoutTrailingZeroes = fixed.replaceFirst(RegExp(r'0+$'), '');
  return withoutTrailingZeroes.replaceFirst(RegExp(r'\.$'), '');
}
