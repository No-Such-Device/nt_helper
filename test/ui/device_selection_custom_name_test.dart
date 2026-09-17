import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;
  Route<dynamic>? lastPushedRoute;

  void reset() {
    pushCount = 0;
    lastPushedRoute = null;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    lastPushedRoute = route;
  }
}

class _SelectionCase {
  const _SelectionCase({
    required this.label,
    required this.inputDevices,
    required this.outputDevices,
    required this.selectedInputDevice,
    required this.selectedOutputDevice,
    required this.expectedInputDevice,
    required this.expectedOutputDevice,
  });

  final String label;
  final List<MidiDevice> inputDevices;
  final List<MidiDevice> outputDevices;
  final MidiDevice? selectedInputDevice;
  final MidiDevice? selectedOutputDevice;
  final MidiDevice? expectedInputDevice;
  final MidiDevice? expectedOutputDevice;

  bool get canConnect =>
      expectedInputDevice != null && expectedOutputDevice != null;
}

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

Future<void> _pumpPage(
  WidgetTester tester,
  _SelectionHarness harness, {
  NavigatorObserver? navigatorObserver,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(harness.close);

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [?navigatorObserver],
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

  setUpAll(() {
    registerFallbackValue(_input('fallback-device', 'Fallback Device'));
  });

  test('Firmware availability is limited to non-Play-Store desktop builds', () {
    expect(
      isFirmwareUpdateAvailable(
        isPlayStoreBuild: false,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
      ),
      isTrue,
    );
    expect(
      isFirmwareUpdateAvailable(
        isPlayStoreBuild: false,
        isMacOS: false,
        isWindows: true,
        isLinux: false,
      ),
      isTrue,
    );
    expect(
      isFirmwareUpdateAvailable(
        isPlayStoreBuild: false,
        isMacOS: false,
        isWindows: false,
        isLinux: true,
      ),
      isTrue,
    );
    expect(
      isFirmwareUpdateAvailable(
        isPlayStoreBuild: true,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
      ),
      isFalse,
    );
    expect(
      isFirmwareUpdateAvailable(
        isPlayStoreBuild: false,
        isMacOS: false,
        isWindows: false,
        isLinux: false,
      ),
      isFalse,
    );
  });

  final inputDevice = _input('input', 'Input');
  final outputDevice = _output('output', 'Output');
  final replacementInput = _input('replacement-input', 'Replacement Input');
  final replacementOutput = _output('replacement-output', 'Replacement Output');
  final selectionCases = [
    _SelectionCase(
      label: 'with neither endpoint selected',
      inputDevices: [inputDevice],
      outputDevices: [outputDevice],
      selectedInputDevice: null,
      selectedOutputDevice: null,
      expectedInputDevice: null,
      expectedOutputDevice: null,
    ),
    _SelectionCase(
      label: 'with only the input selected',
      inputDevices: [inputDevice],
      outputDevices: [outputDevice],
      selectedInputDevice: inputDevice,
      selectedOutputDevice: null,
      expectedInputDevice: inputDevice,
      expectedOutputDevice: null,
    ),
    _SelectionCase(
      label: 'with only the output selected',
      inputDevices: [inputDevice],
      outputDevices: [outputDevice],
      selectedInputDevice: null,
      selectedOutputDevice: outputDevice,
      expectedInputDevice: null,
      expectedOutputDevice: outputDevice,
    ),
    _SelectionCase(
      label: 'with both endpoints selected',
      inputDevices: [inputDevice],
      outputDevices: [outputDevice],
      selectedInputDevice: inputDevice,
      selectedOutputDevice: outputDevice,
      expectedInputDevice: inputDevice,
      expectedOutputDevice: outputDevice,
    ),
    const _SelectionCase(
      label: 'with no available devices',
      inputDevices: [],
      outputDevices: [],
      selectedInputDevice: null,
      selectedOutputDevice: null,
      expectedInputDevice: null,
      expectedOutputDevice: null,
    ),
    _SelectionCase(
      label: 'after the selected endpoints disappear',
      inputDevices: [replacementInput],
      outputDevices: [replacementOutput],
      selectedInputDevice: inputDevice,
      selectedOutputDevice: outputDevice,
      expectedInputDevice: null,
      expectedOutputDevice: null,
    ),
  ];

  for (final selectionCase in selectionCases) {
    testWidgets(
      'Firmware opens ${selectionCase.label} without changing Connect',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final harness = _SelectionHarness(
          DistingState.selectDevice(
                inputDevices: selectionCase.inputDevices,
                outputDevices: selectionCase.outputDevices,
                canWorkOffline: true,
                selectedInputDevice: selectionCase.selectedInputDevice,
                selectedOutputDevice: selectionCase.selectedOutputDevice,
                selectedSysExId: 17,
              )
              as DistingStateSelectDevice,
        );
        when(
          () => harness.cubit.connectToDevices(any(), any(), any()),
        ).thenAnswer((_) async {});
        final navigatorObserver = _RecordingNavigatorObserver();

        await _pumpPage(tester, harness, navigatorObserver: navigatorObserver);
        navigatorObserver.reset();

        final connect = find.widgetWithText(FilledButton, 'Connect');
        final firmware = find.widgetWithText(OutlinedButton, 'Firmware');
        final connectButton = tester.widget<FilledButton>(connect);
        final firmwareButton = tester.widget<OutlinedButton>(firmware);
        final connectSemantics = tester
            .getSemantics(connect)
            .getSemanticsData();
        final firmwareSemantics = tester
            .getSemantics(firmware)
            .getSemanticsData();

        expect(
          connectButton.onPressed,
          selectionCase.canConnect ? isNotNull : isNull,
        );
        expect(
          connectSemantics.flagsCollection.isEnabled,
          selectionCase.canConnect ? Tristate.isTrue : Tristate.isFalse,
        );
        expect(firmwareButton.onPressed, isNotNull);
        expect(firmwareSemantics.flagsCollection.isEnabled, Tristate.isTrue);
        expect(firmwareSemantics.hasAction(SemanticsAction.tap), isTrue);

        await tester.tap(firmware);

        expect(navigatorObserver.pushCount, 1);
        final route = navigatorObserver.lastPushedRoute;
        expect(route, isA<MaterialPageRoute<dynamic>>());
        final pushedWidget = (route! as MaterialPageRoute<dynamic>).builder(
          tester.element(firmware),
        );
        expect(pushedWidget, isA<FirmwareUpdateScreen>());
        final firmwareScreen = pushedWidget as FirmwareUpdateScreen;
        expect(firmwareScreen.distingCubit, same(harness.cubit));
        expect(firmwareScreen.currentVersionOverride, isNull);
        expect(
          firmwareScreen.inputDevice,
          same(selectionCase.expectedInputDevice),
        );
        expect(
          firmwareScreen.outputDevice,
          same(selectionCase.expectedOutputDevice),
        );
        expect(firmwareScreen.sysExId, 17);
        verifyNever(() => harness.cubit.connectToDevices(any(), any(), any()));
        verifyNever(
          () => harness.cubit.probeFirmwareVersion(any(), any(), any()),
        );

        Navigator.of(tester.element(firmware)).pop();
        await tester.pumpAndSettle();

        if (selectionCase.canConnect) {
          await tester.tap(connect);
          await tester.pump();
          verify(
            () => harness.cubit.connectToDevices(
              selectionCase.expectedInputDevice!,
              selectionCase.expectedOutputDevice!,
              17,
            ),
          ).called(1);
        }
        semantics.dispose();
      },
    );
  }

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
