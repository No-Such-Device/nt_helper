import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/cubit/disting_cubit.dart' show Slot;
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/notes_algorithm_view.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import 'package:nt_helper/ui/step_sequencer_view.dart';

class NativeAlgorithmAlternate {
  final String name;
  final Widget Function(Slot, int, FirmwareVersion) builder;

  const NativeAlgorithmAlternate({required this.name, required this.builder});
}

class AlgorithmViewRegistry {
  static final _stepSequencer = NativeAlgorithmAlternate(
    name: 'Step Sequencer editor',
    builder: (slot, slotIndex, firmwareVersion) => StepSequencerView(
      slot: slot,
      slotIndex: slotIndex,
      firmwareVersion: firmwareVersion,
    ),
  );

  static NativeAlgorithmAlternate? findAlternateForGuid(String guid) =>
      guid == 'spsq' ? _stepSequencer : null;

  static Widget? findViewFor(
    Slot slot,
    int slotIndex,
    FirmwareVersion firmwareVersion,
  ) {
    switch (slot.algorithm.guid) {
      case 'ThPh':
        return PatchMapAlgorithmView(slotIndex: slotIndex);
      case 'note':
        return NotesAlgorithmView(slot: slot, firmwareVersion: firmwareVersion);
    }
    return null;
  }
}
