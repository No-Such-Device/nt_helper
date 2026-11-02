import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/grouped_audio_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

class _Controller extends Mock implements DistingController {}

void main() {
  late _Disting disting;
  late StreamController<DistingState> stream;
  late DistingStateSynchronized current;
  late RoutingEditorCubit routing;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stream = StreamController<DistingState>();
    disting = _Disting();
    current = DistingStateSynchronized(
      disting: _Manager(),
      distingVersion: '1.17',
      firmwareVersion: FirmwareVersion('1.17'),
      deviceIoProfile: DeviceIoProfile.distingExtended,
      presetName: 'Airwindows test',
      slots: [groupedAudioSlot()],
      algorithms: [groupedAudioInfo()],
      unitStrings: const [],
    );
    when(() => disting.state).thenAnswer((_) => current);
    when(() => disting.stream).thenAnswer((_) => stream.stream);
    routing = RoutingEditorCubit(disting);
  });

  tearDown(() async {
    await routing.close();
    await stream.close();
  });

  Future<void> publish(DistingStateSynchronized state) async {
    current = state;
    stream.add(state);
    await Future<void>.delayed(Duration.zero);
  }

  RoutingEditorStateLoaded loaded() => switch (routing.state) {
    RoutingEditorStateLoaded state => state,
    _ => throw StateError('Routing not loaded'),
  };

  test('UI carries the implicit ports without adding editable parameters', () {
    final algorithm = loaded().algorithms.single;
    expect(algorithm.inputPorts.map((p) => p.busValue), [11, 12]);
    expect(algorithm.outputPorts.map((p) => p.busValue), [23, 24]);
    expect(algorithm.inputPorts.last.parameterNumber, isNull);
    expect(algorithm.outputPorts.last.parameterNumber, isNull);
    expect(algorithm.outputPorts.last.channelNumber, 2);
    expect(current.slots.single.parameters, hasLength(3));
  });

  test(
    'late library metadata rebuilds identical slots and losing it fails closed',
    () async {
      await publish(
        current.copyWith(algorithms: const [], slots: current.slots),
      );
      final sameSlots = current.slots;
      expect(loaded().algorithms.single.inputPorts, hasLength(1));
      await publish(current.copyWith(algorithms: [groupedAudioInfo()]));
      expect(identical(current.slots, sameSlots), isTrue);
      expect(loaded().algorithms.single.inputPorts, hasLength(2));
      await publish(current.copyWith(algorithms: const []));
      expect(loaded().algorithms.single.inputPorts, hasLength(1));
    },
  , tags: ['regression']);

  test(
    'batching retains library-only changes until its single rebuild',
    () async {
      await publish(current.copyWith(algorithms: const []));
      await routing.runBatched(() async {
        await publish(current.copyWith(algorithms: [groupedAudioInfo()]));
        expect(loaded().algorithms.single.inputPorts, hasLength(1));
      });
      expect(loaded().algorithms.single.inputPorts, hasLength(2));
    },
  , tags: ['regression']);

  test(
    'changing base buses and construction values moves the whole span',
    () async {
      await publish(
        current.copyWith(
          slots: [
            groupedAudioSlot(input: 5, output: 27, specifications: [3]),
          ],
        ),
      );
      expect(loaded().algorithms.single.inputPorts.map((p) => p.busValue), [
        5,
        6,
        7,
      ]);
      expect(loaded().algorithms.single.outputPorts.map((p) => p.busValue), [
        27,
        28,
        29,
      ]);
    },
  );

  test(
    'MCP show_routing includes the right channel using the same metadata',
    () async {
      final tools = MCPAlgorithmTools(_Controller(), disting);
      final result = jsonDecode(await tools.getCurrentRoutingState({}));
      expect(result.single['input_buses'], ['Input 11', 'Input 12']);
      expect(result.single['output_buses'], ['Aux 3', 'Aux 4']);
    },
  );

  test(
    'derived ports cannot independently rewrite their implicit buses',
    () async {
      final algorithm = loaded().algorithms.single;
      await expectLater(
        routing.createConnection(
          sourcePortId: algorithm.outputPorts.last.id,
          targetPortId: loaded().physicalOutputs.first.id,
        ),
        throwsStateError,
      );
      await expectLater(
        routing.createConnection(
          sourcePortId: loaded().physicalInputs.first.id,
          targetPortId: algorithm.inputPorts.last.id,
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
}
