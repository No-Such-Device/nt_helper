import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

class AlgorithmVisualStyleDialog extends StatefulWidget {
  const AlgorithmVisualStyleDialog({super.key, required this.initialStyle});

  final AlgorithmVisualStyle initialStyle;

  @override
  State<AlgorithmVisualStyleDialog> createState() =>
      _AlgorithmVisualStyleDialogState();
}

class _AlgorithmVisualStyleDialogState
    extends State<AlgorithmVisualStyleDialog> {
  late int _leftIndent = widget.initialStyle.leftIndent;
  late int _rightIndent = widget.initialStyle.rightIndent;
  late bool _lineAbove = widget.initialStyle.lineAbove;
  late bool _lineBelow = widget.initialStyle.lineBelow;
  late AlgorithmVisualBracket _bracket = widget.initialStyle.bracket;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Semantics(header: true, child: const Text('Algorithm Decoration')),
      content: DigitShortcutBlocker(
        child: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Place lines, brackets, and indents around this algorithm on the disting NT overview screen.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    'Lines',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      key: const ValueKey('algorithm-style-line-above'),
                      label: const Text('Line above'),
                      selected: _lineAbove,
                      onSelected: (value) => setState(() {
                        _lineAbove = value;
                      }),
                    ),
                    FilterChip(
                      key: const ValueKey('algorithm-style-line-below'),
                      label: const Text('Line below'),
                      selected: _lineBelow,
                      onSelected: (value) => setState(() {
                        _lineBelow = value;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    'Bracket',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final bracket in AlgorithmVisualBracket.values)
                      ChoiceChip(
                        key: ValueKey(
                          'algorithm-style-bracket-${bracket.name}',
                        ),
                        label: Text(_bracketLabel(bracket)),
                        selected: _bracket == bracket,
                        onSelected: (_) => setState(() {
                          _bracket = bracket;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(
                    'Indent',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _indentField(
                        key: const ValueKey('algorithm-style-left-indent'),
                        label: 'Left indent',
                        value: _leftIndent,
                        onChanged: (value) => setState(() {
                          _leftIndent = value;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _indentField(
                        key: const ValueKey('algorithm-style-right-indent'),
                        label: 'Right indent',
                        value: _rightIndent,
                        onChanged: (value) => setState(() {
                          _rightIndent = value;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          key: const ValueKey('algorithm-style-save'),
          onPressed: () {
            Navigator.of(context).pop(
              AlgorithmVisualStyle(
                leftIndent: _leftIndent,
                rightIndent: _rightIndent,
                lineAbove: _lineAbove,
                lineBelow: _lineBelow,
                bracket: _bracket,
              ),
            );
          },
          child: const Text('SAVE'),
        ),
      ],
    );
  }

  Widget _indentField({
    required Key key,
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (var indent = 0; indent <= 15; indent++)
          DropdownMenuItem(value: indent, child: Text('$indent')),
      ],
      onChanged: (newValue) {
        if (newValue != null) onChanged(newValue);
      },
    );
  }

  String _bracketLabel(AlgorithmVisualBracket bracket) {
    return switch (bracket) {
      AlgorithmVisualBracket.none => 'No bracket',
      AlgorithmVisualBracket.open => 'Open',
      AlgorithmVisualBracket.close => 'Close',
      AlgorithmVisualBracket.line => 'Line',
      AlgorithmVisualBracket.openAndClose => 'Open + close',
    };
  }
}

Future<void> showAlgorithmVisualStyleEditor({
  required BuildContext context,
  required Slot slot,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return;

  final style = await showDialog<AlgorithmVisualStyle>(
    context: context,
    builder: (_) => AlgorithmVisualStyleDialog(
      initialStyle: slot.algorithm.visualStyle ?? const AlgorithmVisualStyle(),
    ),
  );
  if (style == null || !context.mounted) return;

  try {
    await context.read<DistingCubit>().setAlgorithmVisualStyle(
      slot.algorithm.algorithmIndex,
      style,
    );
    if (!context.mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Algorithm decoration updated',
      Directionality.of(context),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to update algorithm decoration: $error')),
    );
  }
}
