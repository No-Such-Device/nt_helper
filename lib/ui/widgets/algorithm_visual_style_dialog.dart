import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/algorithm_visual_style_preview.dart';

class AlgorithmVisualStyleDialog extends StatefulWidget {
  const AlgorithmVisualStyleDialog({
    super.key,
    required this.initialStyle,
    required this.algorithmName,
    required this.onChanged,
    this.offlinePreview = false,
  });

  final AlgorithmVisualStyle initialStyle;
  final String algorithmName;
  final Future<void> Function(AlgorithmVisualStyle style) onChanged;
  final bool offlinePreview;

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
  Timer? _saveStatusTimer;
  int _saveGeneration = 0;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _syncFailed = false;

  static const _saveStatusDelay = Duration(seconds: 1);

  AlgorithmVisualStyle get _style => AlgorithmVisualStyle(
    leftIndent: _leftIndent,
    rightIndent: _rightIndent,
    lineAbove: _lineAbove,
    lineBelow: _lineBelow,
    bracket: _bracket,
  );

  @override
  void dispose() {
    _saveStatusTimer?.cancel();
    super.dispose();
  }

  void _edit(VoidCallback update) {
    final generation = ++_saveGeneration;
    setState(() {
      update();
      _isDirty = true;
      _isSaving = false;
      _syncFailed = false;
    });

    final style = _style;
    _saveStatusTimer?.cancel();
    _saveStatusTimer = Timer(_saveStatusDelay, () {
      if (!mounted || generation != _saveGeneration) return;
      setState(() => _isSaving = true);
    });
    unawaited(
      _trackUpdate(Future.sync(() => widget.onChanged(style)), generation),
    );
  }

  Future<void> _trackUpdate(Future<void> update, int generation) async {
    try {
      await update;
      if (!mounted || generation != _saveGeneration) return;
      _saveStatusTimer?.cancel();
      setState(() {
        _isDirty = false;
        _isSaving = false;
      });
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.offlinePreview
            ? 'Algorithm decoration preview updated'
            : 'Algorithm decoration synced',
        Directionality.of(context),
      );
    } catch (error) {
      if (!mounted || generation != _saveGeneration) return;
      _saveStatusTimer?.cancel();
      setState(() {
        _isSaving = false;
        _syncFailed = true;
      });
      const message = 'Unable to update algorithm decoration';
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$message: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: const Text('Algorithm Decoration'),
            ),
          ),
          if (_isDirty || _isSaving || _syncFailed) _buildSyncIndicator(),
        ],
      ),
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
                    'Preview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  label:
                      'Decoration preview for ${widget.algorithmName}: '
                      '${describeAlgorithmVisualStyle(_style)}',
                  child: ExcludeSemantics(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppThemeColors.ntDisplaySurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: AlgorithmVisualStylePreview(
                        key: const ValueKey('algorithm-style-live-preview'),
                        style: _style,
                        color: AppThemeColors.ntDisplayForeground,
                        child: Text(
                          widget.algorithmName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppThemeColors.ntDisplayForeground,
                              ),
                        ),
                      ),
                    ),
                  ),
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
                      onSelected: (value) => _edit(() {
                        _lineAbove = value;
                      }),
                    ),
                    FilterChip(
                      key: const ValueKey('algorithm-style-line-below'),
                      label: const Text('Line below'),
                      selected: _lineBelow,
                      onSelected: (value) => _edit(() {
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
                        onSelected: (_) {
                          if (_bracket == bracket) return;
                          _edit(() {
                            _bracket = bracket;
                          });
                        },
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
                        onChanged: (value) => _edit(() {
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
                        onChanged: (value) => _edit(() {
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
          child: const Text('CLOSE'),
        ),
      ],
    );
  }

  Widget _buildSyncIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = _syncFailed
        ? ('Sync failed', colorScheme.error)
        : _isSaving
        ? ('Syncing changes', colorScheme.primary)
        : ('Changes pending', colorScheme.tertiary);

    return Semantics(
      liveRegion: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Container(
          key: const ValueKey('algorithm-style-sync-indicator'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
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

  final cubit = context.read<DistingCubit>();
  final isOffline = switch (cubit.state) {
    DistingStateSynchronized(offline: final offline) => offline,
    _ => false,
  };

  await showDialog<void>(
    context: context,
    builder: (_) => AlgorithmVisualStyleDialog(
      initialStyle: slot.algorithm.visualStyle ?? const AlgorithmVisualStyle(),
      algorithmName: slot.algorithm.name,
      onChanged: (style) =>
          cubit.setAlgorithmVisualStyle(slot.algorithm.algorithmIndex, style),
      offlinePreview: isOffline,
    ),
  );
}
