import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/widgets/parameter_editor_view.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  testWidgets('invalid routing assignment remains visible as unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final cubit = _MockDistingCubit();
    final slot = _slotWithInvalidBus();
    final state = DistingState.synchronized(
      disting: _MockDistingMidiManager(),
      distingVersion: '1.20',
      firmwareVersion: FirmwareVersion('1.20'),
      deviceIoProfile: DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!,
      presetName: 'Test',
      algorithms: const [],
      slots: [slot],
      unitStrings: const [],
    );
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: ParameterEditorView(
              slot: slot,
              parameterInfo: slot.parameters.single,
              value: slot.values.single,
              enumStrings: slot.enums.single,
              mapping: null,
              valueString: slot.valueStrings.single,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Bus 99 (Unavailable)'), findsOneWidget);
  });
}

Slot _slotWithInvalidBus() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 12,
      defaultValue: 0,
      unit: 1,
      name: 'Input',
      powerOfTen: 0,
      ioFlags: 1,
    ),
  ],
  values: [ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 99)],
  enums: [
    ParameterEnumStrings(algorithmIndex: 0, parameterNumber: 0, values: []),
  ],
  mappings: const [],
  valueStrings: [
    ParameterValueString(algorithmIndex: 0, parameterNumber: 0, value: ''),
  ],
);
