import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/services/settings_service.dart';

/// A specialized tooltip widget for explaining invalid connections
///
/// Invalid connections represent algorithm-to-algorithm connections that violate
/// the Disting NT's slot ordering constraints. This tooltip provides clear
/// explanations and actionable guidance to help users fix the issue.
class InvalidConnectionTooltip extends StatefulWidget {
  /// The connection to show tooltip information for
  final Connection connection;

  /// The child widget that triggers the tooltip on hover
  final Widget child;

  /// Custom tooltip message (optional - defaults to standard invalid connection explanation)
  final String? customMessage;

  /// Whether the tooltip should be shown
  final bool show;

  /// Delay before showing the tooltip
  final Duration delay;

  /// Source algorithm slot number (for display in tooltip)
  final int? sourceSlot;

  /// Destination algorithm slot number (for display in tooltip)
  final int? destinationSlot;

  const InvalidConnectionTooltip({
    super.key,
    required this.connection,
    required this.child,
    this.customMessage,
    this.show = true,
    this.delay = const Duration(milliseconds: 500),
    this.sourceSlot,
    this.destinationSlot,
  });

  @override
  State<InvalidConnectionTooltip> createState() =>
      _InvalidConnectionTooltipState();
}

class _InvalidConnectionTooltipState extends State<InvalidConnectionTooltip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _isHovering = false;
  bool _isShowingTooltip = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// Show the tooltip with animation
  void _showTooltip() {
    if (!widget.show ||
        !SettingsService().showContextualHelp ||
        _isShowingTooltip) {
      return;
    }

    setState(() {
      _isShowingTooltip = true;
    });

    _animationController.forward();
  }

  /// Hide the tooltip with animation
  void _hideTooltip() {
    if (!_isShowingTooltip) return;

    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _isShowingTooltip = false;
        });
      }
    });
  }

  /// Handle hover enter with delay
  void _onHoverEnter() {
    setState(() {
      _isHovering = true;
    });

    // Show tooltip after delay
    Future.delayed(widget.delay, () {
      if (_isHovering && mounted) {
        _showTooltip();
      }
    });
  }

  /// Handle hover exit
  void _onHoverExit() {
    setState(() {
      _isHovering = false;
    });

    _hideTooltip();
  }

  /// Generate tooltip message based on connection properties
  String _getTooltipMessage() {
    if (widget.customMessage != null) {
      return widget.customMessage!;
    }

    if (widget.connection.isBackwardEdge) {
      final sourceSlotText = widget.sourceSlot != null
          ? 'Slot ${widget.sourceSlot! + 1}'
          : 'Higher slot';
      final destSlotText = widget.destinationSlot != null
          ? 'Slot ${widget.destinationSlot! + 1}'
          : 'Lower slot';

      return 'Invalid Connection Order\n'
          '$sourceSlotText → $destSlotText\n\n'
          'This connection violates the Disting NT\'s processing order. '
          'Algorithms process in slot order (1, 2, 3...), so connections '
          'from higher-numbered slots to lower-numbered slots won\'t work.\n\n'
          'Solution: Use the up/down arrows to reorder algorithms so the '
          'source algorithm comes before the destination algorithm.';
    } else {
      return 'Valid Connection\n'
          'This connection follows the correct slot ordering.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final semanticLabel = widget.connection.isBackwardEdge
        ? 'Warning: Invalid connection order. Reorder algorithms to fix.'
        : 'Valid connection';
    final gainLabel = widget.connection.gain != 1.0
        ? '. Gain: ${widget.connection.gain.toStringAsFixed(2)}'
        : '';
    final muteLabel = widget.connection.isMuted ? '. Muted' : '';

    return Semantics(
      label: '$semanticLabel$gainLabel$muteLabel',
      child: MouseRegion(
        onEnter: (_) => _onHoverEnter(),
        onExit: (_) => _onHoverExit(),
        child: Stack(
          children: [
            widget.child,
            if (_isShowingTooltip)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: _buildTooltipContent(theme),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the actual tooltip content widget
  Widget _buildTooltipContent(ThemeData theme) {
    return Positioned(
      top: -120, // Position above the connection (taller for invalid connections)
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.connection.isBackwardEdge
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.connection.isBackwardEdge
                    ? theme.colorScheme.error.withValues(alpha: 0.5)
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: theme.shadowColor.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.connection.isBackwardEdge
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 16,
                      color: widget.connection.isBackwardEdge
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.connection.isBackwardEdge
                          ? 'Invalid Connection'
                          : 'Valid Connection',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.connection.isBackwardEdge
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  _getTooltipMessage(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.connection.isBackwardEdge
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                ),
                // Additional connection details for invalid connections
                if (widget.connection.isBackwardEdge) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          size: 14,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tip: Look for the up/down arrow buttons next to each algorithm to reorder them.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontStyle: FontStyle.italic,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Connection details
                if (widget.connection.gain != 1.0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Gain: ${widget.connection.gain.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.connection.isBackwardEdge
                          ? theme.colorScheme.onErrorContainer.withValues(
                              alpha: 0.7,
                            )
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (widget.connection.isMuted) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.volume_off,
                        size: 12,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Muted',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
