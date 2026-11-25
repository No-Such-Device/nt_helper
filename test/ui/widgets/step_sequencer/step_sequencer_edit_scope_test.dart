import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_sequencer_edit_scope.dart';

import '../../../test_helpers/step_sequencer_slot_fixture.dart';

class _Cubit extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  late _Cubit cubit;
  late _Manager manager;
  late Slot slot;
  late DistingState state;
  late StreamController<DistingState> states;

  DistingStateSynchronized synchronized(List<Slot> slots) =>
      DistingStateSynchronized(
        disting: manager,
        distingVersion: '1.20.0beta',
        firmwareVersion: FirmwareVersion('1.20.0beta'),
        presetName: 'Scope tests',
        algorithms: const [],
        slots: slots,
        unitStrings: const [],
      );

  void emit(DistingState next) {
    state = next;
    states.add(next);
  }

  setUp(() {
    cubit = _Cubit();
    manager = _Manager();
    slot = stepSequencerSlot();
    state = synchronized([slot]);
    states = StreamController<DistingState>.broadcast(sync: true);
    when(() => cubit.state).thenAnswer((_) => state);
    when(() => cubit.stream).thenAnswer((_) => states.stream);
    when(() => cubit.isClosed).thenReturn(false);
  });

  tearDown(() async => states.close());

  test('rename and visual style copies preserve the actual instance', () {
    final renamed = slot.copyWith(
      algorithm: slot.algorithm.copyWith(name: 'Melody'),
    );
    final styled = renamed.copyWith(
      algorithm: renamed.algorithm.copyWith(
        visualStyle: const AlgorithmVisualStyle(leftIndent: 1),
      ),
    );
    final identity = StepSequencerEditIdentity(manager, 0, slot);
    expect(
      styled.algorithm.instanceIdentity,
      same(slot.algorithm.instanceIdentity),
    );
    expect(StepSequencerEditIdentity(manager, 0, styled), identity);
    final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
    emit(synchronized([renamed]));
    emit(synchronized([styled]));
    expect(scope.isCurrent, isTrue);
    scope.dispose();
    expect(states.hasListener, isFalse);
  });

  test('fresh same-GUID replacement is not an old algorithm instance', () {
    final replacement = stepSequencerSlot();
    expect(replacement.algorithm.guid, slot.algorithm.guid);
    expect(replacement.parameters, slot.parameters);
    expect(
      replacement.algorithm.instanceIdentity,
      isNot(same(slot.algorithm.instanceIdentity)),
    );
    final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
    emit(synchronized([replacement]));
    emit(synchronized([slot]));
    expect(scope.isCurrent, isFalse);
    scope.dispose();
  });

  test(
    'schema and specification changes invalidate even a copied instance',
    () {
      for (final updated in [
        slot.copyWith(
          parameters: slot.parameters.sublist(0, slot.parameters.length - 1),
        ),
        slot.copyWith(
          algorithm: slot.algorithm.copyWith(specifications: const [2]),
        ),
      ]) {
        final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
        expect(
          updated.algorithm.instanceIdentity,
          same(slot.algorithm.instanceIdentity),
        );
        expect(
          StepSequencerEditIdentity(manager, 0, updated),
          isNot(StepSequencerEditIdentity(manager, 0, slot)),
        );
        emit(synchronized([updated]));
        emit(synchronized([slot]));
        expect(scope.isCurrent, isFalse);
        scope.dispose();
      }
    },
  );

  test('reordering away and back cannot revive pending input', () {
    final other = stepSequencerSlot(index: 1);
    emit(synchronized([slot, other]));
    final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
    emit(
      synchronized([
        other.copyWith(algorithm: other.algorithm.copyWith(algorithmIndex: 0)),
        slot.copyWith(algorithm: slot.algorithm.copyWith(algorithmIndex: 1)),
      ]),
    );
    emit(synchronized([slot, other]));
    expect(scope.isCurrent, isFalse);
    scope.dispose();
  });

  test(
    'disconnect and return with the same objects still cancels pending input',
    () {
      final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
      emit(const DistingState.initial());
      emit(synchronized([slot]));
      expect(scope.isCurrent, isFalse);
      scope.dispose();
    },
  );

  test('ordinary value readback does not masquerade as a newer user edit', () {
    final scope = StepSequencerEditScope.capture(cubit, 0, slot)!;
    final glide = slot.parameters.indexWhere((p) => p.name == 'Glide');
    emit(
      synchronized([
        slot.copyWith(
          values: [
            for (final value in slot.values)
              value.parameterNumber == glide
                  ? ParameterValue(
                      algorithmIndex: 0,
                      parameterNumber: glide,
                      value: 55,
                    )
                  : value,
          ],
        ),
      ]),
    );
    expect(scope.isCurrent, isTrue);
    scope.dispose();
  });
}
