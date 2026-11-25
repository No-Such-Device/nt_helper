import 'package:material_ui/material_ui.dart';

/// Control widget for sequence selection in Step Sequencer
///
/// Provides a dropdown for selecting stored sequences based on parameter range.
/// Shows loading indicator during sequence switch operations.
///
/// Layout adapts responsively:
/// - Desktop/Tablet: Horizontal row layout with full labels
/// - Mobile: Compact layout with abbreviated labels
///
/// Supports firmware-provided sequence names via enumStrings parameter.
class SequenceSelector extends StatelessWidget {
  final int currentSequence; // Current parameter value
  final bool isLoading;
  final ValueChanged<int> onSequenceChanged;
  final Map<int, String>?
  sequenceNames; // Optional custom names (deprecated - use enumStrings)
  final List<String>? enumStrings; // Firmware-provided sequence names
  final int? minValue; // Parameter minimum value
  final int? maxValue; // Parameter maximum value

  const SequenceSelector({
    super.key,
    required this.currentSequence,
    required this.isLoading,
    required this.onSequenceChanged,
    this.sequenceNames,
    this.enumStrings,
    this.minValue,
    this.maxValue,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 768;

    return Row(
      children: [
        Expanded(child: _buildSequenceDropdown(context, isMobile)),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: isLoading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceDropdown(BuildContext context, bool isMobile) {
    // Determine range from parameter min/max or fallback
    final min = minValue ?? 0;
    final max = maxValue ?? (enumStrings?.length ?? 32) - 1;
    final count = max - min + 1;

    return DropdownButtonFormField<int>(
      initialValue: currentSequence,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Sequence',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      items: List.generate(count, (index) {
        final value = min + index;
        String name;
        if (enumStrings != null &&
            index < enumStrings!.length &&
            enumStrings![index].isNotEmpty) {
          // Use firmware-provided enum string
          name = enumStrings![index];
        } else if (sequenceNames != null && sequenceNames!.containsKey(value)) {
          // Fallback to custom names (deprecated)
          name = sequenceNames![value]!;
        } else {
          // Use numeric label from parameter range
          name = '$value';
        }

        return DropdownMenuItem<int>(value: value, child: Text(name));
      }),
      onChanged: isLoading
          ? null
          : (sequence) {
              if (sequence != null) {
                onSequenceChanged(sequence);
              }
            },
    );
  }
}
