import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_dialog.dart';

class AlgorithmStyleButton extends StatelessWidget {
  const AlgorithmStyleButton({
    super.key,
    required this.slot,
    this.enabled = true,
    this.tooltip,
  });

  final Slot slot;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final hasCustomStyle = slot.algorithm.visualStyle?.hasCustomStyle ?? false;
    final algorithmName = slot.algorithm.name;
    final label = hasCustomStyle
        ? 'Edit algorithm style for $algorithmName; custom style applied'
        : 'Edit algorithm style for $algorithmName';
    final button = IconButton.filledTonal(
      tooltip: tooltip ?? label,
      onPressed: enabled
          ? () {
              unawaited(
                showAlgorithmVisualStyleEditor(context: context, slot: slot),
              );
            }
          : null,
      iconSize: 24,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      enableFeedback: true,
      icon: Icon(
        Icons.format_shapes_rounded,
        semanticLabel: label,
        color: hasCustomStyle && enabled
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
    );

    return Semantics(button: true, selected: hasCustomStyle, child: button);
  }
}
