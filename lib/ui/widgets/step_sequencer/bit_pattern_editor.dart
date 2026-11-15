import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Dedicated widget for editing 8-bit pattern parameters (Pattern/Ties)
/// Each bit is a separate clickable cell - much simpler than repurposing pitch bar
class BitPatternEditor extends StatefulWidget {
  final int value; // 0-255 bit pattern
  final Color color;
  final int validBitCount; // 1-8, based on division
  final ValueChanged<int> onChanged;

  const BitPatternEditor({
    super.key,
    required this.value,
    required this.color,
    required this.validBitCount,
    required this.onChanged,
  });

  @override
  State<BitPatternEditor> createState() => _BitPatternEditorState();
}

class _BitPatternEditorState extends State<BitPatternEditor> {
  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());
  int _focusedBitIndex = -1;

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int _countSetBits(int value, int validCount) {
    int count = 0;
    for (int i = 0; i < validCount; i++) {
      if ((value >> i) & 1 == 1) count++;
    }
    return count;
  }

  void _handleKeyEvent(int bitIndex, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final isValid = bitIndex < widget.validBitCount;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.enter:
        if (isValid) {
          final newValue = widget.value ^ (1 << bitIndex);
          widget.onChanged(newValue);
        }
      case LogicalKeyboardKey.arrowUp:
        // Move to higher bit (visual up = higher index in the column layout)
        final visualIndex = 7 - bitIndex;
        if (visualIndex > 0) {
          final nextBitIndex = 7 - (visualIndex - 1);
          _focusNodes[nextBitIndex].requestFocus();
        }
      case LogicalKeyboardKey.arrowDown:
        // Move to lower bit
        final visualIndex = 7 - bitIndex;
        if (visualIndex < 7) {
          final nextBitIndex = 7 - (visualIndex + 1);
          _focusNodes[nextBitIndex].requestFocus();
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label:
          'Pattern: ${widget.validBitCount} substeps, '
          '${_countSetBits(widget.value, widget.validBitCount)} active',
      child: Column(
        children: List.generate(8, (index) {
          // Invert index: bit 7 at top, bit 0 at bottom
          final bitIndex = 7 - index;
          final isSet = (widget.value >> bitIndex) & 1 == 1;
          final isValid = bitIndex < widget.validBitCount;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 1.0),
              child: Semantics(
                label: 'Substep ${bitIndex + 1}',
                toggled: isSet,
                enabled: isValid,
                onTap: isValid
                    ? () {
                        final newValue = widget.value ^ (1 << bitIndex);
                        widget.onChanged(newValue);
                      }
                    : null,
                child: Focus(
                  focusNode: _focusNodes[bitIndex],
                  onFocusChange: (hasFocus) {
                    setState(() {
                      _focusedBitIndex = hasFocus ? bitIndex : -1;
                    });
                  },
                  onKeyEvent: (node, event) {
                    _handleKeyEvent(bitIndex, event);
                    if (event.logicalKey == LogicalKeyboardKey.space ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.arrowUp ||
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isValid
                        ? () {
                            final newValue = widget.value ^ (1 << bitIndex);
                            widget.onChanged(newValue);
                          }
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: !isValid
                            ? scheme.surfaceContainerHighest.withValues(
                                alpha: 0.4,
                              )
                            : isSet
                            ? widget.color
                            : null,
                        border: Border.all(
                          color: _focusedBitIndex == bitIndex
                              ? scheme.primary
                              : !isValid
                              ? scheme.outlineVariant
                              : isSet
                              ? widget.color
                              : scheme.outline,
                          width: _focusedBitIndex == bitIndex ? 2.0 : 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
