import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';

import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/widgets/mapping_editor_bottom_sheet.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';

class MappingEditButton extends StatefulWidget {
  const MappingEditButton({super.key, required this.parameterViewRow});

  final ParameterViewRow parameterViewRow;

  @override
  State<MappingEditButton> createState() => _MappingEditButtonState();
}

class _MappingEditButtonState extends State<MappingEditButton> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final bool hasMapping =
        widget.parameterViewRow.mappingData != null &&
        widget.parameterViewRow.mappingData != PackedMappingData.filler() &&
        widget.parameterViewRow.mappingData?.isMapped() == true;

    final ButtonStyle defaultStyle = IconButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    final ButtonStyle mappedStyle = IconButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
    );

    return SizedBox(
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isEditing
                ? Theme.of(context).colorScheme.tertiary
                : Colors.transparent,
            width: 2.0,
          ),
        ),
        child: IconButton.filledTonal(
          style: (hasMapping ? mappedStyle : defaultStyle).copyWith(
            iconSize: const WidgetStatePropertyAll(18),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(
            Icons.map_sharp,
            semanticLabel: hasMapping ? 'Edit mapping (active)' : 'Add mapping',
          ),
          tooltip: hasMapping ? 'Edit mapping (active)' : 'Add mapping',
          onPressed: () async {
            final cubit = context.read<DistingCubit>();
            final currentState = cubit.state;
            List<Slot> currentSlots = [];
            if (currentState is DistingStateSynchronized) {
              currentSlots = currentState.slots;
            }

            final data =
                widget.parameterViewRow.mappingData ??
                PackedMappingData.filler();
            final myMidiCubit = context.read<MidiListenerCubit>();
            final distingCubit = context.read<DistingCubit>();

            setState(() {
              _isEditing = true;
            });

            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (context) {
                return MappingEditorBottomSheet(
                  myMidiCubit: myMidiCubit,
                  distingCubit: distingCubit,
                  data: data,
                  slots: currentSlots,
                  algorithmIndex: widget.parameterViewRow.algorithmIndex,
                  parameterNumber: widget.parameterViewRow.parameterNumber,
                  parameterMin: widget.parameterViewRow.min,
                  parameterMax: widget.parameterViewRow.max,
                  powerOfTen: widget.parameterViewRow.powerOfTen,
                  unitString: widget.parameterViewRow.unit,
                );
              },
            );

            if (mounted) {
              setState(() {
                _isEditing = false;
              });
            }
          },
        ),
      ),
    );
  }
}
