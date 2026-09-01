import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/algorithm_documentation_screen.dart';
import 'package:nt_helper/ui/reset_outputs_dialog.dart';
import 'package:nt_helper/ui/widgets/slot_bypass_control.dart';

class SlotEditorActionBar extends StatelessWidget {
  const SlotEditorActionBar({
    super.key,
    required this.slot,
    required this.sectionsCollapsed,
    this.editorModeSelector,
    this.onToggleSections,
    this.bypassFocusNode,
  });

  final Slot slot;
  final bool sectionsCollapsed;
  final Widget? editorModeSelector;
  final VoidCallback? onToggleSections;
  final FocusNode? bypassFocusNode;

  @override
  Widget build(BuildContext context) {
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?editorModeSelector,
        if (editorModeSelector != null) const SizedBox(width: 8),
        Tooltip(
          message: sectionsCollapsed ? 'Expand all' : 'Collapse all',
          child: IconButton.filledTonal(
            key: const ValueKey('slot-editor-collapse-toggle'),
            onPressed: onToggleSections,
            enableFeedback: true,
            icon: sectionsCollapsed
                ? const Icon(
                    Icons.keyboard_double_arrow_down_sharp,
                    semanticLabel: 'Expand all',
                  )
                : const Icon(
                    Icons.keyboard_double_arrow_up_sharp,
                    semanticLabel: 'Collapse all',
                  ),
          ),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('slot-editor-more-options'),
          icon: const Icon(Icons.more_vert, semanticLabel: 'More options'),
          itemBuilder: (context) {
            final metadata = AlgorithmMetadataService().getAlgorithmByGuid(
              slot.algorithm.guid,
            );
            final isHelpAvailable = metadata != null;

            return <PopupMenuEntry<String>>[
              if (isHelpAvailable)
                PopupMenuItem(
                  value: 'Show Help',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            AlgorithmDocumentationScreen(metadata: metadata),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Show Help'),
                      Icon(Icons.help_outline_rounded),
                    ],
                  ),
                ),
              if (isHelpAvailable) const PopupMenuDivider(),
              PopupMenuItem(
                value: 'Reset Outputs',
                onTap: () {
                  final distingState = context.read<DistingCubit>().state;
                  if (distingState is! DistingStateSynchronized) return;
                  final outputParameters = slot.parameters.where(
                    (parameter) =>
                        parameter.isOutput &&
                        parameter.unit == 1 &&
                        parameter.min == 0,
                  );
                  final maximum = outputParameters.isEmpty
                      ? 0
                      : outputParameters
                            .map((parameter) => parameter.max)
                            .reduce(
                              (left, right) => left < right ? left : right,
                            );
                  showResetOutputsDialog(
                    context: context,
                    initialCvInput: 0,
                    deviceIoProfile: distingState.deviceIoProfile,
                    minimum: 0,
                    maximum: maximum,
                    onReset: (outputIndex) {
                      context.read<DistingCubit>().resetOutputs(
                        slot,
                        outputIndex,
                      );
                    },
                  );
                },
                child: const Text('Reset Outputs'),
              ),
            ];
          },
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.end,
          runAlignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            SlotBypassControl(slot: slot, focusNode: bypassFocusNode),
            actions,
          ],
        ),
      ),
    );
  }
}
