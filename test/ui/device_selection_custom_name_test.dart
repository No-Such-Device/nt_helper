import 'dart:async';

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

  testWidgets('custom MIDI ports enable Connect without version reply', (
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
    ).thenAnswer((_) async => null);
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

  testWidgets('saved Disting selection can change to Forever before Connect', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final distingInput = MidiDevice(
      'disting-input',
      'Disting NT',
      MidiDeviceType.serial,
      true,
    )..inputPorts.add(MidiPort(0, MidiPortType.IN));
    final distingOutput = MidiDevice(
      'disting-output',
      'Disting NT',
      MidiDeviceType.serial,
      true,
    )..outputPorts.add(MidiPort(0, MidiPortType.OUT));
    final foreverInput = MidiDevice(
      'forever-input',
      'Forever',
      MidiDeviceType.serial,
      true,
    )..inputPorts.add(MidiPort(0, MidiPortType.IN));
    final foreverOutput = MidiDevice(
      'forever-output',
      'Forever',
      MidiDeviceType.serial,
      true,
    )..outputPorts.add(MidiPort(0, MidiPortType.OUT));
    final state = DistingState.selectDevice(
      inputDevices: [distingInput, foreverInput],
      outputDevices: [distingOutput, foreverOutput],
      canWorkOffline: true,
      selectedInputDevice: distingInput,
      selectedOutputDevice: distingOutput,
    );
    final cubit = _MockDistingCubit();
    whenListen(cubit, const Stream<DistingState>.empty(), initialState: state);
    when(
      () => cubit.probeFirmwareVersion(distingInput, distingOutput, 0),
    ).thenAnswer((_) async => '1.18.0');
    when(
      () => cubit.probeFirmwareVersion(foreverInput, distingOutput, 0),
    ).thenAnswer((_) async => null);
    when(
      () => cubit.probeFirmwareVersion(foreverInput, foreverOutput, 0),
    ).thenAnswer((_) async => 'Forever 1.0');
    when(
      () => cubit.connectToDevices(foreverInput, foreverOutput, 0),
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

    final inputDropdown = find.byKey(
      const ValueKey('input-midi-device-dropdown'),
    );
    final outputDropdown = find.byKey(
      const ValueKey('output-midi-device-dropdown'),
    );
    expect(
      tester.widget<DropdownMenu<MidiDevice>>(inputDropdown).initialSelection,
      distingInput,
    );
    expect(
      tester.widget<DropdownMenu<MidiDevice>>(outputDropdown).initialSelection,
      distingOutput,
    );
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    verifyNever(() => cubit.connectToDevices(distingInput, distingOutput, 0));

    await tester.tapAt(tester.getTopLeft(inputDropdown) + const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Forever').hitTestable(),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(outputDropdown) + const Offset(20, 20),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Forever').hitTestable(),
    );
    await tester.pumpAndSettle();

    final connectButton = find.widgetWithText(FilledButton, 'Connect');
    expect(connectButton, findsOneWidget);
    expect(tester.widget<FilledButton>(connectButton).onPressed, isNotNull);

    await tester.tap(connectButton);
    await tester.pump();

    verify(
      () => cubit.connectToDevices(foreverInput, foreverOutput, 0),
    ).called(1);
    verifyNever(() => cubit.connectToDevices(distingInput, distingOutput, 0));
  });

  testWidgets(
    'device refresh between port choices preserves the partial selection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      MidiDevice input(String id, String name) =>
          MidiDevice(id, name, MidiDeviceType.serial, true)
            ..inputPorts.add(MidiPort(0, MidiPortType.IN));
      MidiDevice output(String id, String name) =>
          MidiDevice(id, name, MidiDeviceType.serial, true)
            ..outputPorts.add(MidiPort(0, MidiPortType.OUT));

      final distingInput = input('disting-input', 'Disting NT');
      final distingOutput = output('disting-output', 'Disting NT');
      final foreverInput = input('forever-input', 'Forever');
      final foreverOutput = output('forever-output', 'Forever');
      final refreshedDistingInput = input('disting-input', 'Disting NT');
      final refreshedDistingOutput = output('disting-output', 'Disting NT');
      final refreshedForeverInput = input('forever-input', 'Forever');
      final refreshedForeverOutput = output('forever-output', 'Forever');
      final initialState = DistingState.selectDevice(
        inputDevices: [distingInput, foreverInput],
        outputDevices: [distingOutput, foreverOutput],
        canWorkOffline: true,
      );
      final refreshedState = DistingState.selectDevice(
        inputDevices: [refreshedDistingInput, refreshedForeverInput],
        outputDevices: [refreshedDistingOutput, refreshedForeverOutput],
        canWorkOffline: true,
      );
      final stateController = StreamController<DistingState>();
      addTearDown(stateController.close);
      final cubit = _MockDistingCubit();
      whenListen(cubit, stateController.stream, initialState: initialState);
      when(
        () => cubit.probeFirmwareVersion(
          refreshedForeverInput,
          refreshedForeverOutput,
          0,
        ),
      ).thenAnswer((_) async => 'Forever 1.0');
      when(
        () => cubit.connectToDevices(
          refreshedForeverInput,
          refreshedForeverOutput,
          0,
        ),
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

      final inputDropdown = find.byKey(
        const ValueKey('input-midi-device-dropdown'),
      );
      await tester.tapAt(
        tester.getTopLeft(inputDropdown) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, 'Forever').hitTestable(),
      );
      await tester.pumpAndSettle();

      stateController.add(refreshedState);
      await tester.pumpAndSettle();

      final outputDropdown = find.byKey(
        const ValueKey('output-midi-device-dropdown'),
      );
      await tester.tapAt(
        tester.getTopLeft(outputDropdown) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(MenuItemButton, 'Forever').hitTestable(),
      );
      await tester.pumpAndSettle();

      final connectButton = find.widgetWithText(FilledButton, 'Connect');
      expect(connectButton, findsOneWidget);
      expect(tester.widget<FilledButton>(connectButton).onPressed, isNotNull);

      await tester.tap(connectButton);
      await tester.pump();

      verify(
        () => cubit.connectToDevices(
          refreshedForeverInput,
          refreshedForeverOutput,
          0,
        ),
      ).called(1);
    },
  );
}
