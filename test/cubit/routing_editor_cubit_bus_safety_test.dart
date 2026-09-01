import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late _MockDistingCubit distingCubit;
  late RoutingEditorCubit routingCubit;

  setUp(() {
    distingCubit = _MockDistingCubit();
    when(() => distingCubit.stream).thenAnswer((_) => const Stream.empty());
    when(
      () => distingCubit.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() => routingCubit.close());

  void seed(Slot slot, {DeviceIoProfile? profile}) {
    when(() => distingCubit.state).thenReturn(_state(slot, profile: profile));
    routingCubit = RoutingEditorCubit(distingCubit);
  }

  Future<void> seedLoaded(Slot slot) async {
    final state = _state(slot);
    when(() => distingCubit.state).thenReturn(state);
    when(() => distingCubit.stream).thenAnswer((_) => Stream.value(state));
    routingCubit = RoutingEditorCubit(distingCubit);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  test('Reset All Connections preserves non-routing enums', () async {
    seed(_slotWithOutputAndMode());

    final resetCount = await routingCubit.resetAllConnections(0);

    expect(resetCount, 1);
    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 0,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verifyNever(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 1,
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    );
  });

  test(
    'Reset All Connections identifies buses from I/O flags, not topology',
    () async {
      seed(
        _slotWithNarrowOutput(maximum: 100),
        profile: DeviceIoProfile.tryCreate(
          inputBusCount: 0,
          outputBusCount: 0,
          auxBusCount: 0,
        )!,
      );

      final resetCount = await routingCubit.resetAllConnections(0);

      expect(resetCount, 1);
    },
  );

  test('lane assignments clamp to the parameter bus range', () async {
    seed(_slotWithNarrowInput());

    final result = await routingCubit.assignBusAndSolve(
      algorithmIndex: 0,
      parameterNumber: 0,
      previousBusValue: 2,
      busValue: 10,
    );

    expect(result.newBusValue, 5);
    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 5,
        userIsChangingTheValue: true,
      ),
    ).called(1);
  });

  test('USB From Host assignments preserve its contextual ES-5 pair', () async {
    seed(_slotWithUsbFromHostOutput());

    final result = await routingCubit.assignBusAndSolve(
      algorithmIndex: 0,
      parameterNumber: 0,
      previousBusValue: 12,
      busValue: 13,
    );

    expect(result.newBusValue, 13);
    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 13,
        userIsChangingTheValue: true,
      ),
    ).called(1);
  });

  test('physical connections clamp to the parameter bus range', () async {
    await seedLoaded(_slotWithNarrowInput());
    final loaded = routingCubit.state as RoutingEditorStateLoaded;
    final inputPort = loaded.algorithms.single.inputPorts.singleWhere(
      (port) => port.parameterNumber == 0,
    );

    await routingCubit.createConnection(
      sourcePortId: 'hw_out_3',
      targetPortId: inputPort.id,
    );

    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 5,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  test('physical input connections clamp to the parameter bus range', () async {
    await seedLoaded(_slotWithNarrowInput(maximum: 3));
    final loaded = routingCubit.state as RoutingEditorStateLoaded;
    final inputPort = loaded.algorithms.single.inputPorts.singleWhere(
      (port) => port.parameterNumber == 0,
    );

    await routingCubit.createConnection(
      sourcePortId: 'hw_in_4',
      targetPortId: inputPort.id,
    );

    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 3,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  test('ghost connections clamp to the parameter bus range', () async {
    await seedLoaded(_slotWithNarrowOutput(maximum: 3));
    final loaded = routingCubit.state as RoutingEditorStateLoaded;
    final outputPort = loaded.algorithms.single.outputPorts.singleWhere(
      (port) => port.parameterNumber == 0,
    );

    await routingCubit.createConnection(
      sourcePortId: outputPort.id,
      targetPortId: 'hw_in_4',
    );

    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 3,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  test('physical output connections clamp writer parameter ranges', () async {
    await seedLoaded(_slotWithNarrowOutput());
    final loaded = routingCubit.state as RoutingEditorStateLoaded;
    final outputPort = loaded.algorithms.single.outputPorts.singleWhere(
      (port) => port.parameterNumber == 0,
    );

    await routingCubit.createConnection(
      sourcePortId: outputPort.id,
      targetPortId: 'hw_out_3',
    );

    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 5,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });

  test('Aux moves clamp once to the common parameter range', () async {
    seed(_slotWithSharedAuxReferences());

    final writeCount = await routingCubit.moveAuxBus(8, 12);

    expect(writeCount, 2);
    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 9,
        userIsChangingTheValue: false,
      ),
    ).called(1);
    verify(
      () => distingCubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 1,
        value: 9,
        userIsChangingTheValue: false,
      ),
    ).called(1);
  });
}

final DeviceIoProfile _profile = DeviceIoProfile.tryCreate(
  inputBusCount: 4,
  outputBusCount: 3,
  auxBusCount: 5,
)!;

DistingState _state(Slot slot, {DeviceIoProfile? profile}) =>
    DistingState.synchronized(
      disting: _MockDistingMidiManager(),
      distingVersion: '1.20',
      firmwareVersion: FirmwareVersion('1.20'),
      deviceIoProfile: profile ?? _profile,
      presetName: 'Test',
      algorithms: const [],
      slots: [slot],
      unitStrings: const [],
    );

Slot _slotWithOutputAndMode() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    _parameter(0, 'Output A', 0, 12, 2),
    _parameter(1, 'Output A mode', 0, 1, 8),
  ],
  values: [_value(0, 5), _value(1, 1)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

Slot _slotWithNarrowInput({int maximum = 5}) => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [_parameter(0, 'Input', 0, maximum, 1)],
  values: [_value(0, 2)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

Slot _slotWithNarrowOutput({int maximum = 5}) => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [_parameter(0, 'Output', 0, maximum, 2)],
  values: [_value(0, 2)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

Slot _slotWithUsbFromHostOutput() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'usbf', name: 'USB From Host'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [_parameter(0, 'Output', 0, 14, 2)],
  values: [_value(0, 12)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

Slot _slotWithSharedAuxReferences() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    _parameter(0, 'Output A', 0, 9, 2),
    _parameter(1, 'Output B', 0, 10, 2),
  ],
  values: [_value(0, 8), _value(1, 8)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

ParameterInfo _parameter(
  int number,
  String name,
  int min,
  int max,
  int ioFlags,
) => ParameterInfo(
  algorithmIndex: 0,
  parameterNumber: number,
  min: min,
  max: max,
  defaultValue: min,
  unit: 1,
  name: name,
  powerOfTen: 0,
  ioFlags: ioFlags,
);

ParameterValue _value(int number, int value) =>
    ParameterValue(algorithmIndex: 0, parameterNumber: number, value: value);
