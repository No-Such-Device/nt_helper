import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/services/settings_service.dart';

/// A specialized tooltip widget for explaining ghost connections
///
/// Ghost connections represent indirect routing paths, typically from algorithm
/// outputs to physical hardware inputs. This tooltip provides clear explanations
/// to help users understand the difference between ghost and direct connections.
class GhostConnectionTooltip extends StatefulWidget {
  /// The connection to show tooltip information for
  final Connection connection;

  /// The child widget that triggers the tooltip on hover
  final Widget child;

  /// Custom tooltip message (optional - defaults to standard ghost connection explanation)
  final String? customMessage;

  /// Whether the tooltip should be shown
  final bool show;

  /// Delay before showing the tooltip
  final Duration delay;

  const GhostConnectionTooltip({
    super.key,
    required this.connection,
    required this.child,
    this.customMessage,
    this.show = true,
    this.delay = const Duration(milliseconds: 500),
  });

  @override
  State<GhostConnectionTooltip> createState() => _GhostConnectionTooltipState();
}

class _GhostConnectionTooltipState extends State<GhostConnectionTooltip>
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

  /// Generate tooltip message based on connection type and properties
  String _getTooltipMessage() {
    if (widget.customMessage != null) {
      return widget.customMessage!;
    }

    if (widget.connection.isGhostConnection) {
      return 'Ghost Connection\n'
          'Algorithm output → Physical input\n'
          'Indirect signal routing path\n\n'
          'This connection represents signal flow from an '
          'algorithm processing module to the physical hardware inputs, '
          'creating an indirect routing path.';
    } else {
      return 'Direct Connection\n'
          'Direct signal routing path\n\n'
          'This connection represents a direct signal path between '
          'compatible ports without intermediate processing.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final semanticLabel = widget.connection.isGhostConnection
        ? 'Ghost connection: indirect routing path'
        : 'Direct connection';
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
      top: -80, // Position above the connection
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.connection.isGhostConnection
                    ? theme.colorScheme.primary.withValues(alpha: 0.3)
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
                      widget.connection.isGhostConnection
                          ? Icons.auto_awesome
                          : Icons.sync_alt,
                      size: 16,
                      color: widget.connection.isGhostConnection
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.connection.isGhostConnection
                          ? 'Ghost Connection'
                          : 'Direct Connection',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.connection.isGhostConnection
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Description
                Text(
                  _getTooltipMessage(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.3,
                  ),
                ),
                // Connection details
                if (widget.connection.gain != 1.0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Gain: ${widget.connection.gain.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
