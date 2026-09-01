import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';

class ConsolidateBusesDialog extends StatefulWidget {
  final AuxBusConsolidationPlan plan;
  final RoutingEditorCubit cubit;

  const ConsolidateBusesDialog({
    super.key,
    required this.plan,
    required this.cubit,
  });

  @override
  State<ConsolidateBusesDialog> createState() => _ConsolidateBusesDialogState();
}

class _ConsolidateBusesDialogState extends State<ConsolidateBusesDialog> {
  bool _isExecuting = false;
  bool _isComplete = false;
  late final Set<int> _enabledMerges;

  // Progress tracking: mergeIndex → set of completed step indices
  final Map<int, Set<int>> _replaceModesDone = {};
  final Map<int, Set<int>> _completedSteps = {};

  @override
  void initState() {
    super.initState();
    _enabledMerges = Set<int>.from(
      List.generate(widget.plan.merges.length, (i) => i),
    );
  }

  bool get _hasEnabledMerges => _enabledMerges.isNotEmpty;

  Future<void> _execute() async {
    setState(() => _isExecuting = true);

    // Build a filtered plan with only enabled merges
    final enabledPlan = AuxBusConsolidationPlan(
      description: widget.plan.description,
      merges: [
        for (int i = 0; i < widget.plan.merges.length; i++)
          if (_enabledMerges.contains(i)) widget.plan.merges[i],
      ],
    );

    // Map filtered indices back to original indices for progress tracking
    final originalIndices = <int>[
      for (int i = 0; i < widget.plan.merges.length; i++)
        if (_enabledMerges.contains(i)) i,
    ];

    await widget.cubit.executeConsolidationPlan(
      enabledPlan,
      onReplaceModeSet: (filteredIndex, replaceModeIndex) {
        if (mounted) {
          setState(() {
            final origIdx = originalIndices[filteredIndex];
            _replaceModesDone
                .putIfAbsent(origIdx, () => {})
                .add(replaceModeIndex);
          });
        }
      },
      onStepComplete: (filteredIndex, stepIndex) {
        if (mounted) {
          setState(() {
            final origIdx = originalIndices[filteredIndex];
            _completedSteps.putIfAbsent(origIdx, () => {}).add(stepIndex);
          });
        }
      },
    );
    if (mounted) {
      setState(() {
        _isExecuting = false;
        _isComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final successColor = context.appColors.success.color;
    final merges = widget.plan.merges;

    return PopScope(
      canPop: !_isExecuting,
      child: AlertDialog(
        title: Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.compress, color: colorScheme.primary),
            ),
            const SizedBox(width: 8),
            const Text('Optimize AUX Buses'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.plan.description, style: textTheme.titleSmall),
              const Divider(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: merges.length,
                  itemBuilder: (context, mergeIndex) =>
                      _buildMergeSection(mergeIndex, colorScheme, textTheme),
                ),
              ),
              if (_isComplete) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.check_circle, color: successColor, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Optimization complete',
                      style: textTheme.bodyMedium?.copyWith(
                        color: successColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_isExecuting && !_isComplete)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          if (!_isExecuting && !_isComplete)
            ElevatedButton(
              onPressed: _hasEnabledMerges ? _execute : null,
              child: const Text('Confirm'),
            ),
          if (_isComplete)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }

  Widget _buildMergeSection(
    int mergeIndex,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final merge = widget.plan.merges[mergeIndex];
    final enabled = _enabledMerges.contains(mergeIndex);
    final routingState = widget.cubit.state;
    final profile = routingState is RoutingEditorStateLoaded
        ? routingState.deviceIoProfile
        : DeviceIoProfile.distingExtended;
    final keepLocal = profile.localNumber(merge.keepBus) ?? merge.keepBus;
    final canToggle = !_isExecuting && !_isComplete;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.plan.merges.length > 1)
          InkWell(
            onTap: canToggle
                ? () => setState(() {
                    if (enabled) {
                      _enabledMerges.remove(mergeIndex);
                    } else {
                      _enabledMerges.add(mergeIndex);
                    }
                  })
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (canToggle)
                    Checkbox(
                      value: enabled,
                      onChanged: (_) => setState(() {
                        if (enabled) {
                          _enabledMerges.remove(mergeIndex);
                        } else {
                          _enabledMerges.add(mergeIndex);
                        }
                      }),
                    ),
                  Expanded(
                    child: Text(
                      merge.description,
                      style: textTheme.titleSmall?.copyWith(
                        color: enabled ? null : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (enabled) ...[
          for (int r = 0; r < merge.replaceModeSteps.length; r++)
            _buildStepRow(
              done: _replaceModesDone[mergeIndex]?.contains(r) ?? false,
              label:
                  'Set ${merge.replaceModeSteps[r].algorithmName} to Replace on AUX $keepLocal',
              colorScheme: colorScheme,
            ),
          for (int i = 0; i < merge.steps.length; i++)
            _buildStepRow(
              done: _completedSteps[mergeIndex]?.contains(i) ?? false,
              label: 'Move ${merge.steps[i].algorithmName} to AUX $keepLocal',
              colorScheme: colorScheme,
            ),
        ],
        if (mergeIndex < widget.plan.merges.length - 1)
          const Divider(height: 16),
      ],
    );
  }

  Widget _buildStepRow({
    required bool done,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        children: [
          done
              ? Icon(
                  Icons.check_circle,
                  color: context.appColors.success.color,
                  size: 20,
                )
              : Icon(
                  Icons.circle_outlined,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
