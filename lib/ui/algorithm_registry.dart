import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/disting_cubit.dart' show Slot;
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/notes_algorithm_view.dart';
import 'package:nt_helper/ui/patch_map/patch_map_editor.dart';
import 'package:nt_helper/ui/step_sequencer_view.dart';

class AlgorithmViewRegistry {
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
      case 'spsq':
        return StepSequencerView(
          slot: slot,
          slotIndex: slotIndex,
          firmwareVersion: firmwareVersion,
        );
    }
    return null;
  }
}
