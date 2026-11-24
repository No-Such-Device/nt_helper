import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';

/// Binds delayed native-editor work to the snapshot that accepted the input.
class StepSequencerEditScope {
  final DistingCubit cubit;
  final IDistingMidiManager manager;
  final int slotIndex;
  final Slot slot;
  final bool checkSequence;

  StepSequencerEditScope._(
    this.cubit,
    this.manager,
    this.slotIndex,
    this.slot,
    this.checkSequence,
  );

  static StepSequencerEditScope? capture(
    DistingCubit cubit,
    int slotIndex,
    Slot expectedSlot, {
    bool checkSequence = true,
  }) {
    final state = cubit.state;
    if (state is! DistingStateSynchronized ||
        state.loading ||
        slotIndex < 0 ||
        slotIndex >= state.slots.length ||
        !identical(state.slots[slotIndex].algorithm, expectedSlot.algorithm)) {
      return null;
    }
    return StepSequencerEditScope._(
      cubit,
      state.disting,
      slotIndex,
      state.slots[slotIndex],
      checkSequence,
    );
  }

  bool get isCurrent {
    final state = cubit.state;
    if (cubit.isClosed ||
        state is! DistingStateSynchronized ||
        state.loading ||
        !identical(state.disting, manager) ||
        slotIndex >= state.slots.length ||
        !identical(state.slots[slotIndex].algorithm, slot.algorithm)) {
      return false;
    }
    if (!checkSequence) return true;
    final parameter = StepSequencerParams.fromSlot(slot).currentSequence;
    if (parameter == null) return true;
    return state.slots[slotIndex].values.elementAtOrNull(parameter)?.value ==
        slot.values.elementAtOrNull(parameter)?.value;
  }
}
