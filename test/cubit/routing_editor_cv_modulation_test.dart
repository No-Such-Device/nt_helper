import 'package:nt_helper/core/routing/models/port.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/cv_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

class _Controller extends Mock implements DistingController {}

void main() {
  late _Disting disting;
  late _Manager manager;
  late StreamController<DistingState> events;
  late RoutingEditorCubit cubit;
  late DistingStateSynchronized snapshot;
  DistingStateSynchronized stateFor(List<Slot> slots) =>
      DistingState.synchronized(
        disting: manager,
        distingVersion: '1.20.0beta',
        firmwareVersion: FirmwareVersion('1.20.0beta'),
        presetName: 'CV fixture',
        algorithms: const [],
        slots: slots,
        unitStrings: const [],
      ) as DistingStateSynchronized;
  void seed(List<Slot> slots) {
    snapshot = stateFor(slots);
    when(() => disting.state).thenAnswer((_) => snapshot);
    cubit = RoutingEditorCubit(disting);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    disting = _Disting();
    manager = _Manager();
    events = StreamController<DistingState>.broadcast(sync: true);
    when(() => disting.stream).thenAnswer((_) => events.stream);
    when(() => disting.refreshRouting()).thenAnswer((_) async {});
    when(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
  });
  tearDown(() async {
    await cubit.close();
    await events.close();
  });

  test(
    'mapped-only nodes, real indices and cached API share one target set',
    () async {
      seed([
        cvSlot(0),
        cvSlot(1, outputs: [32, 33]),
        cvSlot(2, cvBuses: [32, 33], source: 3),
      ]);
      final loaded = cubit.state as RoutingEditorStateLoaded;
      expect(loaded.algorithms, hasLength(3));
      final target = loaded.algorithms.last;
      expect(target.inputPorts, isEmpty);
      expect(target.outputPorts, isEmpty);
      expect(target.cvModulations, hasLength(2));
      expect(
        target.cvModulations.map((m) => m.destinationSlot),
        everyElement(2),
      );
      expect(loaded.auxBusUsage[32]!.destNames.single, contains('CC 1 (CV)'));

      final controller = _Controller();
      final api = jsonDecode(
        await MCPAlgorithmTools(controller, disting).getCurrentRoutingState({}),
      ) as List;
      expect(
        api.last['cv_modulation'],
        target.cvModulations.map((m) => m.toJson()).toList(),
      );
      expect(api.last['slot_index'], 2);
      expect(
        api.last['cv_modulation'][0]['contributors'][0]['algorithm_name'],
        'Step 1',
      );
      expect(api.last['cv_modulation'][0]['contributors'][0]['slot_index'], 1);
      expect(
        api.last['cv_modulation'][0]['contributors'][0]['port_name'],
        'Step output 1',
      );
      expect(api.last['mapping_coverage'], 'complete_cached');
      verifyZeroInteractions(controller);
      verifyZeroInteractions(manager);
    },
  );

  test('mapping-only immutable updates and clearing rebuild without new MIDI reads', () {
    final source = cvSlot(0, outputs: [32]);
    final empty = cvSlot(1, cvBuses: [0]);
    seed([source, empty]);
    final before = cubit.state as RoutingEditorStateLoaded;
    snapshot = stateFor([
      source,
      cvSlot(1, cvBuses: [32]),
    ]);
    events.add(snapshot);
    final after = cubit.state as RoutingEditorStateLoaded;
    expect(after.algorithms.last.cvModulations, hasLength(1));
    expect(
      after.algorithms.map((a) => a.id),
      before.algorithms.map((a) => a.id),
    );
    expect(after.connections, before.connections);
    snapshot = stateFor([source, empty]);
    events.add(snapshot);
    expect(
      (cubit.state as RoutingEditorStateLoaded).algorithms.last.cvModulations,
      isEmpty,
    );
    verifyZeroInteractions(manager);
  });

  test('mapped buses cannot be moved on either side, including zero-depth mappings', () async {
    seed([
      cvSlot(0, outputs: [32]),
      cvSlot(1, cvBuses: [32]),
    ]);
    expect(await cubit.moveAuxBus(32, 33), -1);
    expect(await cubit.moveAuxBus(33, 32), -1);
    verifyNever(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    );
  });

  test(
    'unknown mapping coverage cannot authorize bus moves or optimization',
    () async {
      seed([
        cvSlot(0, outputs: [32]).copyWith(mappings: []),
      ]);
      expect(await cubit.moveAuxBus(32, 33), -1);
      expect(cubit.buildConsolidationPlan(), isNull);
      expect(
        cvRoutingOptimizationBlockReason(snapshot.slots),
        contains('Refresh'),
      );
    },
  );

  test('reordering with CV mappings fails before the first swap', () async {
    seed([
      cvSlot(0, outputs: [32]),
      cvSlot(1, cvBuses: [32]),
    ]);
    final loaded = cubit.state as RoutingEditorStateLoaded;
    await expectLater(
      cubit.applyReorder(loaded.algorithms.reversed.map((a) => a.id).toList()),
      throwsStateError,
    );
    verifyNever(() => disting.moveAlgorithmUp(any()));
    verifyNever(() => disting.moveAlgorithmDown(any()));
  });

  test(
    'automatic connection excludes mapping-reserved buses from allocation',
    () async {
      seed([
        cvSlot(0, outputs: [0]),
        cvSlot(1, inputs: [0]),
        cvSlot(2, cvBuses: [21]),
      ]);
      final loaded = cubit.state as RoutingEditorStateLoaded;
      await cubit.createConnection(
        sourcePortId: loaded.algorithms[0].outputPorts.single.id,
        targetPortId: loaded.algorithms[1].inputPorts.single.id,
      );
      verify(
        () => disting.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 22,
          userIsChangingTheValue: false,
        ),
      ).called(1);
      verifyNever(
        () => disting.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: 21,
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      );
    },
  );

  for (final modes in [
    <OutputMode>[],
    [OutputMode.replace],
  ]) {
    test(
      'safe mapped-bus fanout writes only the new reader (modes=$modes)',
      () async {
        seed([
          cvSlot(0, outputs: [32], modes: modes),
          cvSlot(1, inputs: [0]),
          cvSlot(2, cvBuses: [32]),
        ]);
        final loaded = cubit.state as RoutingEditorStateLoaded;
        await cubit.createConnection(
          sourcePortId: loaded.algorithms[0].outputPorts.single.id,
          targetPortId: loaded.algorithms[1].inputPorts.single.id,
        );
        verify(
          () => disting.updateParameterValue(
            algorithmIndex: 1,
            parameterNumber: 0,
            value: 32,
            userIsChangingTheValue: false,
          ),
        ).called(1);
        verifyNever(
          () => disting.updateParameterValue(
            algorithmIndex: 0,
            parameterNumber: any(named: 'parameterNumber'),
            value: any(named: 'value'),
            userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
          ),
        );
      },
    );
  }

  test('Module-input-only mappings allow routing reorder', () async {
    seed([
      cvSlot(0, outputs: [32]),
      cvSlot(1, cvBuses: [1], source: 1),
    ]);
    when(() => disting.moveAlgorithmUp(any())).thenAnswer((_) async => 0);
    final loaded = cubit.state as RoutingEditorStateLoaded;
    final result = await cubit.applyReorder(
      loaded.algorithms.reversed.map((a) => a.id).toList(),
    );
    expect(result.changed, isTrue);
    verify(() => disting.moveAlgorithmUp(1)).called(1);
  });

  test(
    'automatic composite connection cannot change a mapped-bus writer',
    () async {
      seed([
        cvSlot(0, outputs: [32], modes: [OutputMode.add]),
        cvSlot(1, inputs: [0]),
        cvSlot(2, cvBuses: [32]),
      ]);
      final loaded = cubit.state as RoutingEditorStateLoaded;
      await expectLater(
        cubit.createConnection(
          sourcePortId: loaded.algorithms[0].outputPorts.single.id,
          targetPortId: loaded.algorithms[1].inputPorts.single.id,
        ),
        throwsStateError,
      );
      verifyNever(
        () => disting.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      );
    },
  );
  test('automatic bus reassignment of a mapped writer is still rejected before any write', () async {
    seed([
      cvSlot(0, outputs: [1]),
      cvSlot(1, inputs: [0]),
      cvSlot(2, cvBuses: [1]),
    ]);
    final loaded = cubit.state as RoutingEditorStateLoaded;
    await expectLater(
      cubit.createConnection(
        sourcePortId: loaded.algorithms[0].outputPorts.single.id,
        targetPortId: loaded.algorithms[1].inputPorts.single.id,
      ),
      throwsStateError,
    );
    verifyNever(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    );
  });

  for (final protectedBus in [21, 22]) {
    test(
      'stale consolidation refuses mapped source/destination bus $protectedBus before writes',
      () async {
        final slots = [
          cvSlot(0, outputs: [21], modes: [OutputMode.replace]),
          cvSlot(1, inputs: [21]),
          cvSlot(2, outputs: [22], modes: [OutputMode.replace]),
          cvSlot(3, inputs: [22]),
          cvSlot(4, cvBuses: [0]),
        ];
        seed(slots);
        final plan = cubit.buildConsolidationPlan();
        expect(plan, isNotNull);
        snapshot = stateFor([
          ...slots.take(4),
          cvSlot(4, cvBuses: [protectedBus]),
        ]);
        events.add(snapshot);
        await expectLater(
          cubit.executeConsolidationPlan(plan!),
          throwsStateError,
        );
        verifyNever(
          () => disting.updateParameterValue(
            algorithmIndex: any(named: 'algorithmIndex'),
            parameterNumber: any(named: 'parameterNumber'),
            value: any(named: 'value'),
            userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
          ),
        );
        expect(cubit.buildConsolidationPlan(), isNull);
      },
    );
  }
}
