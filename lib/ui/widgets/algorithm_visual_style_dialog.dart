import 'package:flutter/material.dart';
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
      title: Semantics(
        header: true,
        child: const Text('Algorithm Overview Style'),
      ),
      content: DigitShortcutBlocker(
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controls how this algorithm is grouped on the disting NT overview screen.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<AlgorithmVisualBracket>(
                  key: const ValueKey('algorithm-style-bracket'),
                  initialValue: _bracket,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Bracket',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final bracket in AlgorithmVisualBracket.values)
                      DropdownMenuItem(
                        value: bracket,
                        child: Text(_bracketLabel(bracket)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _bracket = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('algorithm-style-line-above'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Line above'),
                  value: _lineAbove,
                  onChanged: (value) => setState(() {
                    _lineAbove = value;
                  }),
                ),
                SwitchListTile(
                  key: const ValueKey('algorithm-style-line-below'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Line below'),
                  value: _lineBelow,
                  onChanged: (value) => setState(() {
                    _lineBelow = value;
                  }),
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
      AlgorithmVisualBracket.openAndClose => 'Open & close',
    };
  }
}
