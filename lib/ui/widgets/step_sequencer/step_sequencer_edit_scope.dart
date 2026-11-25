import 'dart:async';

import 'package:collection/collection.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';

/// Presentation changes keep an editor; replacement or schema changes do not.
class StepSequencerEditIdentity {
  final Object? manager;
  final int slotIndex;
  final Object instance;
  final String guid;
  final List<int> specifications;
  final List<ParameterInfo> parameters;

  StepSequencerEditIdentity(this.manager, this.slotIndex, Slot slot)
    : instance = slot.algorithm.instanceIdentity,
      guid = slot.algorithm.guid,
      specifications = List.unmodifiable(slot.algorithm.specifications),
      parameters = List.unmodifiable(slot.parameters);

  @override
  bool operator ==(Object other) =>
      other is StepSequencerEditIdentity &&
      identical(manager, other.manager) &&
      slotIndex == other.slotIndex &&
      identical(instance, other.instance) &&
      guid == other.guid &&
      const ListEquality<int>().equals(specifications, other.specifications) &&
      const ListEquality<ParameterInfo>().equals(parameters, other.parameters);

  @override
  int get hashCode => Object.hash(
    manager,
    slotIndex,
    instance,
    guid,
    Object.hashAll(specifications),
    Object.hashAll(parameters),
  );
}

/// Binds delayed work to displayed input, permanently cancelling on departure.
class StepSequencerEditScope {
  final DistingCubit cubit;
  final int slotIndex;
  final Slot slot;
  final bool checkSequence;
  final StepSequencerEditIdentity _identity;
  StreamSubscription<DistingState>? _subscription;
  bool _valid = true;

  StepSequencerEditScope._(
    this.cubit,
    this.slotIndex,
    this.slot,
    this.checkSequence,
    this._identity,
  ) {
    _subscription = cubit.stream.listen((state) {
      if (!_matches(state, checkSequence: checkSequence)) dispose();
    }, onDone: dispose);
  }

  static StepSequencerEditScope? capture(
    DistingCubit cubit,
    int slotIndex,
    Slot expectedSlot, {
    bool checkSequence = true,
  }) {
    final state = cubit.state;
    if (cubit.isClosed ||
        state is! DistingStateSynchronized ||
        state.loading ||
        slotIndex < 0 ||
        slotIndex >= state.slots.length) {
      return null;
    }
    final identity = StepSequencerEditIdentity(
      state.disting,
      slotIndex,
      expectedSlot,
    );
    final currentSlot = state.slots[slotIndex];
    if (identity !=
            StepSequencerEditIdentity(state.disting, slotIndex, currentSlot) ||
        _sequence(expectedSlot) != _sequence(currentSlot)) {
      return null;
    }
    return StepSequencerEditScope._(
      cubit,
      slotIndex,
      expectedSlot,
      checkSequence,
      identity,
    );
  }

  static int? _sequence(Slot slot) {
    final parameter = StepSequencerParams.fromSlot(slot).currentSequence;
    return parameter == null
        ? null
        : slot.values.elementAtOrNull(parameter)?.value;
  }

  bool _matches(DistingState state, {required bool checkSequence}) =>
      state is DistingStateSynchronized &&
      !state.loading &&
      slotIndex < state.slots.length &&
      _identity ==
          StepSequencerEditIdentity(
            state.disting,
            slotIndex,
            state.slots[slotIndex],
          ) &&
      (!checkSequence || _sequence(slot) == _sequence(state.slots[slotIndex]));

  bool get isCurrent {
    if (!_valid) return false;
    if (cubit.isClosed ||
        !_matches(cubit.state, checkSequence: checkSequence)) {
      dispose();
    }
    return _valid;
  }

  void dispose() {
    _valid = false;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
