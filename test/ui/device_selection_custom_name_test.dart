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

class _SelectionHarness {
  _SelectionHarness(DistingStateSelectDevice initialState)
    : state = initialState {
    whenListen(cubit, states.stream, initialState: state);
    when(
      () => cubit.updateDeviceSelection(
        inputDevice: any(named: 'inputDevice'),
        outputDevice: any(named: 'outputDevice'),
        sysExId: any(named: 'sysExId'),
      ),
    ).thenAnswer((invocation) {
      emit(
        state.copyWith(
          selectedInputDevice:
              invocation.namedArguments[#inputDevice] as MidiDevice?,
          selectedOutputDevice:
              invocation.namedArguments[#outputDevice] as MidiDevice?,
          selectedSysExId: invocation.namedArguments[#sysExId] as int,
        ),
      );
    });
  }

  final cubit = _MockDistingCubit();
  final states = StreamController<DistingState>();
  DistingStateSelectDevice state;

  void emit(DistingStateSelectDevice nextState) {
    state = nextState;
    states.add(nextState);
  }

  Future<void> close() => states.close();
}

MidiDevice _input(String id, String name) =>
    MidiDevice(id, name, MidiDeviceType.serial, true)
      ..inputPorts.add(MidiPort(0, MidiPortType.IN));

MidiDevice _output(String id, String name) =>
    MidiDevice(id, name, MidiDeviceType.serial, true)
      ..outputPorts.add(MidiPort(0, MidiPortType.OUT));

Future<void> _pumpPage(WidgetTester tester, _SelectionHarness harness) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(harness.close);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<DistingCubit>.value(
        value: harness.cubit,
        child: const DistingPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, Key dropdownKey, String label) async {
  final dropdown = find.byKey(dropdownKey);
  await tester.tapAt(tester.getTopLeft(dropdown) + const Offset(20, 20));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).hitTestable());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Connect is always shown and enables for any selected input and output',
    (tester) async {
      final inputDevice = _input('custom-input', 'Custom Input');
      final outputDevice = _output('custom-output', 'Custom Output');
      final harness = _SelectionHarness(
        DistingState.selectDevice(
              inputDevices: [inputDevice],
              outputDevices: [outputDevice],
              canWorkOffline: true,
            )
            as DistingStateSelectDevice,
      );
      when(
        () => harness.cubit.connectToDevices(inputDevice, outputDevice, 0),
      ).thenAnswer((_) async {});

      await _pumpPage(tester, harness);

      var connect = find.widgetWithText(FilledButton, 'Connect');
      expect(connect, findsOneWidget);
      expect(tester.widget<FilledButton>(connect).onPressed, isNull);
      expect(find.widgetWithText(OutlinedButton, 'Firmware'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Offline'), findsOneWidget);

      await _choose(
        tester,
        const ValueKey('input-midi-device-dropdown'),
        'Custom Input',
      );
      await _choose(
        tester,
        const ValueKey('output-midi-device-dropdown'),
        'Custom Output',
      );

      connect = find.widgetWithText(FilledButton, 'Connect');
      expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
      verifyNever(
        () => harness.cubit.probeFirmwareVersion(inputDevice, outputDevice, 0),
      );

      await tester.tap(connect);
      await tester.pump();

      verify(
        () => harness.cubit.connectToDevices(inputDevice, outputDevice, 0),
      ).called(1);
    },
  );

  testWidgets('saved Disting selection can change to Forever before Connect', (
    tester,
  ) async {
    final distingInput = _input('disting-input', 'Disting NT');
    final distingOutput = _output('disting-output', 'Disting NT');
    final foreverInput = _input('forever-input', 'Forever');
    final foreverOutput = _output('forever-output', 'Forever');
    final harness = _SelectionHarness(
      DistingState.selectDevice(
            inputDevices: [distingInput, foreverInput],
            outputDevices: [distingOutput, foreverOutput],
            canWorkOffline: true,
            selectedInputDevice: distingInput,
            selectedOutputDevice: distingOutput,
          )
          as DistingStateSelectDevice,
    );
    when(
      () => harness.cubit.connectToDevices(foreverInput, foreverOutput, 0),
    ).thenAnswer((_) async {});

    await _pumpPage(tester, harness);

    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byKey(const ValueKey('input-midi-device-dropdown')),
          )
          .initialSelection,
      distingInput.id,
    );
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byKey(const ValueKey('output-midi-device-dropdown')),
          )
          .initialSelection,
      distingOutput.id,
    );
    verifyNever(
      () => harness.cubit.connectToDevices(distingInput, distingOutput, 0),
    );

    await _choose(
      tester,
      const ValueKey('input-midi-device-dropdown'),
      'Forever',
    );
    await _choose(
      tester,
      const ValueKey('output-midi-device-dropdown'),
      'Forever',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();

    verify(
      () => harness.cubit.connectToDevices(foreverInput, foreverOutput, 0),
    ).called(1);
    verifyNever(
      () => harness.cubit.probeFirmwareVersion(foreverInput, foreverOutput, 0),
    );
  });

  testWidgets('Refresh retains a complete valid selection and Connect', (
    tester,
  ) async {
    final inputDevice = _input('forever-input', 'Forever');
    final outputDevice = _output('forever-output', 'Forever');
    final refreshedInput = _input('forever-input', 'Forever');
    final refreshedOutput = _output('forever-output', 'Forever');
    final harness = _SelectionHarness(
      DistingState.selectDevice(
            inputDevices: [inputDevice],
            outputDevices: [outputDevice],
            canWorkOffline: true,
            selectedInputDevice: inputDevice,
            selectedOutputDevice: outputDevice,
            selectedSysExId: 7,
          )
          as DistingStateSelectDevice,
    );
    when(() => harness.cubit.loadDevices()).thenAnswer((_) async {
      harness.emit(
        DistingState.selectDevice(
              inputDevices: [refreshedInput],
              outputDevices: [refreshedOutput],
              canWorkOffline: true,
              selectedInputDevice: refreshedInput,
              selectedOutputDevice: refreshedOutput,
              selectedSysExId: 7,
            )
            as DistingStateSelectDevice,
      );
    });
    when(
      () => harness.cubit.connectToDevices(refreshedInput, refreshedOutput, 7),
    ).thenAnswer((_) async {});

    await _pumpPage(tester, harness);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byTooltip('Refresh devices'));
    await tester.pumpAndSettle();

    final connect = find.widgetWithText(FilledButton, 'Connect');
    expect(connect, findsOneWidget);
    expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
    await tester.tap(connect);
    await tester.pump();

    verify(
      () => harness.cubit.connectToDevices(refreshedInput, refreshedOutput, 7),
    ).called(1);
  });
}
