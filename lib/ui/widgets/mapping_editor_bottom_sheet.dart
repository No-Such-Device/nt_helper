import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/widgets/packed_mapping_data_editor.dart';

Future<void> showParameterMappingEditor(
  BuildContext context, {
  required int algorithmIndex,
  required int parameterNumber,
}) async {
  final distingCubit = context.read<DistingCubit>();
  final state = distingCubit.state;
  if (state is! DistingStateSynchronized ||
      algorithmIndex < 0 ||
      algorithmIndex >= state.slots.length) {
    return;
  }
  final slot = state.slots[algorithmIndex];
  final mapping =
      slot.mappings
          .where((m) => m.parameterNumber == parameterNumber)
          .firstOrNull ??
      slot.mappings.elementAtOrNull(parameterNumber);
  if (mapping == null ||
      (mapping.parameterNumber >= 0 &&
          mapping.parameterNumber != parameterNumber)) {
    return;
  }
  final parameter = slot.parameters
      .where((p) => p.parameterNumber == parameterNumber)
      .firstOrNull;
  final midiCubit = context.read<MidiListenerCubit>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => MappingEditorBottomSheet(
      myMidiCubit: midiCubit,
      distingCubit: distingCubit,
      data: mapping.packedMappingData,
      slots: state.slots,
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      parameterMin: parameter?.min ?? 0,
      parameterMax: parameter?.max ?? 0,
      powerOfTen: parameter?.powerOfTen ?? 0,
    ),
  );
}

class MappingEditorBottomSheet extends StatelessWidget {
  const MappingEditorBottomSheet({
    super.key,
    required this.myMidiCubit,
    required this.distingCubit,
    required this.data,
    required this.slots,
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.parameterMin,
    required this.parameterMax,
    required this.powerOfTen,
    this.unitString,
  });

  final MidiListenerCubit myMidiCubit;
  final DistingCubit distingCubit;
  final PackedMappingData data;
  final List<Slot> slots;
  final int algorithmIndex;
  final int parameterNumber;
  final int parameterMin;
  final int parameterMax;
  final int powerOfTen;
  final String? unitString;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom > 0
              ? MediaQuery.of(context).viewInsets.bottom
              : MediaQuery.of(context).padding.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Mapping Editor',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const Divider(height: 1),
              MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: myMidiCubit),
                  BlocProvider.value(value: distingCubit),
                ],
                child: PackedMappingDataEditor(
                  initialData: data,
                  slots: slots,
                  algorithmIndex: algorithmIndex,
                  parameterNumber: parameterNumber,
                  parameterMin: parameterMin,
                  parameterMax: parameterMax,
                  powerOfTen: powerOfTen,
                  unitString: unitString,
                  onSave: (updatedData) async {
                    await distingCubit.saveMapping(
                      algorithmIndex,
                      parameterNumber,
                      updatedData,
                    );
                  },
                  onSaveImmediately: (updatedData) async {
                    await distingCubit.saveMappingImmediately(
                      algorithmIndex,
                      parameterNumber,
                      updatedData,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
