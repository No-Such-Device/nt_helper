import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_dialog.dart';

class AlgorithmDecorationButton extends StatelessWidget {
  const AlgorithmDecorationButton({
    super.key,
    required this.slot,
    this.enabled = true,
    this.compact = false,
    this.tooltip,
  });

  final Slot slot;
  final bool enabled;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDecorated = slot.algorithm.visualStyle?.isDecorated ?? false;
    final algorithmName = slot.algorithm.name;
    final label = isDecorated
        ? 'Edit decoration for $algorithmName; decoration applied'
        : 'Decorate $algorithmName';
    final button = IconButton(
      tooltip: tooltip ?? label,
      onPressed: enabled
          ? () {
              unawaited(
                showAlgorithmVisualStyleEditor(context: context, slot: slot),
              );
            }
          : null,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints.tightFor(width: 40, height: 40)
          : null,
      icon: Icon(
        Icons.format_shapes_rounded,
        semanticLabel: label,
        size: compact ? 19 : null,
        color: isDecorated && enabled
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
    );

    return Semantics(button: true, selected: isDecorated, child: button);
  }
}
