import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/services/scale_quantizer.dart';

/// Control widget for scale quantization settings in Step Sequencer
///
/// Provides toggle button for snap-to-scale, scale selector dropdown,
/// root note selector, bulk "Quantize All Steps" button, and undo button.
///
/// Layout adapts responsively:
/// - Desktop/Tablet: Horizontal row layout
/// - Mobile: Vertical stack with compact controls
class QuantizeControls extends StatelessWidget {
  final bool snapEnabled;
  final String selectedScale;
  final int rootNote;
  final VoidCallback onToggleSnap;
  final ValueChanged<String> onScaleChanged;
  final ValueChanged<int> onRootNoteChanged;
  final VoidCallback onQuantizeAll;
  final VoidCallback? onUndo;
  final bool canUndo;

  const QuantizeControls({
    super.key,
    required this.snapEnabled,
    required this.selectedScale,
    required this.rootNote,
    required this.onToggleSnap,
    required this.onScaleChanged,
    required this.onRootNoteChanged,
    required this.onQuantizeAll,
    this.onUndo,
    this.canUndo = false,
  });

  static const Map<int, String> _rootNoteNames = {
    0: 'C',
    1: 'C#',
    2: 'D',
    3: 'D#',
    4: 'E',
    5: 'F',
    6: 'F#',
    7: 'G',
    8: 'G#',
    9: 'A',
    10: 'A#',
    11: 'B',
  };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 768;

    if (isMobile) {
      return _buildMobileLayout(context);
    } else {
      return _buildDesktopLayout(context);
    }
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildSnapCheckbox(context),
        SizedBox(width: 150, child: _buildScaleDropdown(context)),
        SizedBox(width: 100, child: _buildRootNoteDropdown(context)),
        _buildQuantizeAllButton(context),
        _buildUndoButton(context),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSnapCheckbox(context),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildScaleDropdown(context)),
            const SizedBox(width: 8),
            Expanded(child: _buildRootNoteDropdown(context)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildQuantizeAllButton(context)),
            const SizedBox(width: 8),
            _buildUndoButton(context),
          ],
        ),
      ],
    );
  }

  Widget _buildSnapCheckbox(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: snapEnabled, onChanged: (_) => onToggleSnap()),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onToggleSnap,
          child: const Text('Snap to Scale', style: TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildScaleDropdown(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedScale,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Scale',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      items: ScaleQuantizer.scaleNames.map((scale) {
        return DropdownMenuItem<String>(value: scale, child: Text(scale));
      }).toList(),
      onChanged: (scale) {
        if (scale != null) {
          onScaleChanged(scale);
        }
      },
    );
  }

  Widget _buildRootNoteDropdown(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: rootNote,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Root',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      items: _rootNoteNames.entries.map((entry) {
        return DropdownMenuItem<int>(
          value: entry.key,
          child: Text(entry.value),
        );
      }).toList(),
      onChanged: (note) {
        if (note != null) {
          onRootNoteChanged(note);
        }
      },
    );
  }

  Widget _buildQuantizeAllButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ElevatedButton.icon(
      icon: const Icon(Icons.auto_fix_high),
      label: const Text('Quantize All'),
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: onQuantizeAll,
    );
  }

  Widget _buildUndoButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: const Icon(Icons.undo, semanticLabel: 'Undo last quantize'),
      tooltip: 'Undo last quantize',
      onPressed: canUndo ? onUndo : null,
      style: IconButton.styleFrom(
        backgroundColor: canUndo
            ? scheme.primary
            : scheme.surfaceContainerHighest,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: scheme.surfaceContainerHighest,
        disabledForegroundColor: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}
