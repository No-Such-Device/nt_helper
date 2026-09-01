import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/routing_table_view.dart';

class _MockRoutingEditorCubit extends Mock implements RoutingEditorCubit {}

void main() {
  testWidgets('routing table marks an algorithm output on bus 64', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final cubit = _MockRoutingEditorCubit();
    final state = RoutingEditorState.loaded(
      deviceIoProfile: DeviceIoProfile.distingExtended,
      physicalInputs: const [],
      physicalOutputs: const [],
      algorithms: [_algorithmWritingBus64()],
      connections: const [],
    );
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RoutingEditorCubit>.value(
          value: cubit,
          child: const Scaffold(body: RoutingTableView()),
        ),
      ),
    );

    expect(find.text('+'), findsOneWidget);
  });
}

RoutingAlgorithm _algorithmWritingBus64() => RoutingAlgorithm(
  id: 'writer',
  index: 0,
  algorithm: Algorithm(algorithmIndex: 0, guid: 'writer', name: 'Writer'),
  inputPorts: const [],
  outputPorts: const [
    Port(
      id: 'writer_out',
      name: 'Output',
      type: PortType.audio,
      direction: PortDirection.output,
      busValue: 64,
      outputMode: OutputMode.add,
    ),
  ],
);
