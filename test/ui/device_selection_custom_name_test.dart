import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/disting_app.dart';

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selected custom-named MIDI ports enable primary Connect', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inputDevice = MidiDevice(
      'custom-input',
      'Custom MIDI Port',
      MidiDeviceType.serial,
      true,
    )..inputPorts.add(MidiPort(0, MidiPortType.IN));
    final outputDevice = MidiDevice(
      'custom-output',
      'Custom MIDI Port',
      MidiDeviceType.serial,
      true,
    )..outputPorts.add(MidiPort(0, MidiPortType.OUT));
    final state = DistingState.selectDevice(
      inputDevices: [inputDevice],
      outputDevices: [outputDevice],
      canWorkOffline: true,
    );
    final cubit = _MockDistingCubit();
    whenListen(cubit, const Stream<DistingState>.empty(), initialState: state);
    when(
      () => cubit.probeFirmwareVersion(inputDevice, outputDevice, 0),
    ).thenAnswer((_) async => '1.18.0');
    when(
      () => cubit.connectToDevices(inputDevice, outputDevice, 0),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: const DistingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Offline'), findsOneWidget);

    final inputDropdown = find.byKey(
      const ValueKey('input-midi-device-dropdown'),
    );
    await tester.tapAt(tester.getTopLeft(inputDropdown) + const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Custom MIDI Port').hitTestable(),
    );
    await tester.pumpAndSettle();

    final outputDropdown = find.byKey(
      const ValueKey('output-midi-device-dropdown'),
    );
    await tester.tapAt(
      tester.getTopLeft(outputDropdown) + const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Custom MIDI Port').hitTestable(),
    );
    await tester.pumpAndSettle();

    final connectButton = find.widgetWithText(FilledButton, 'Connect');
    expect(connectButton, findsOneWidget);
    expect(tester.widget<FilledButton>(connectButton).onPressed, isNotNull);

    await tester.tap(connectButton);
    await tester.pump();

    verify(
      () => cubit.connectToDevices(inputDevice, outputDevice, 0),
    ).called(1);
  });
}
