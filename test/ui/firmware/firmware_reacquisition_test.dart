import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class _MockFirmwareUpdateCubit extends MockCubit<FirmwareUpdateState>
    implements FirmwareUpdateCubit {}

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockFirmwareVersionService extends Mock
    implements FirmwareVersionService {}

class _MockFlashToolManager extends Mock implements FlashToolManager {}

class _MockFlashToolBridge extends Mock implements FlashToolBridge {}

class _TrackingDistingCubit extends DistingCubit {
  _TrackingDistingCubit(super.database, {required super.midiCommand})
    : super(isWindowsOverride: true);

  int firmwareCompletionCalls = 0;

  @override
  Future<void> onFirmwareUpdateComplete() async {
    firmwareCompletionCalls++;
    await super.onFirmwareUpdateComplete();
  }
}

class _PopCountingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

class _FirmwareReturnHarness {
  _FirmwareReturnHarness() {
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    when(() => midiCommand.onMidiSetupChanged).thenReturn(null);
    when(
      () => firmwareVersionService.fetchAvailableVersions(),
    ).thenAnswer((_) async => [release]);
    when(
      () => firmwareVersionService.downloadFirmware(
        release,
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => '/tmp/firmware.zip');
    when(
      () => flashToolManager.getToolPath(),
    ).thenAnswer((_) async => '/path/to/nt-flash');
    when(
      () => flashToolBridge.flash('/tmp/firmware.zip'),
    ).thenAnswer((_) => flashProgress.stream);
    when(() => flashToolBridge.cancel()).thenAnswer((_) async {});
    distingCubit = _TrackingDistingCubit(database, midiCommand: midiCommand);
  }

  final _MockAppDatabase database = _MockAppDatabase();
  final _MockMetadataDao metadataDao = _MockMetadataDao();
  final MockMidiCommand midiCommand = MockMidiCommand();
  final _MockFirmwareVersionService firmwareVersionService =
      _MockFirmwareVersionService();
  final _MockFlashToolManager flashToolManager = _MockFlashToolManager();
  final _MockFlashToolBridge flashToolBridge = _MockFlashToolBridge();
  final StreamController<FlashProgress> flashProgress =
      StreamController<FlashProgress>();
  final FirmwareRelease release = FirmwareRelease(
    version: '1.16.0',
    releaseDate: DateTime(2026),
    changelog: const ['Post-flash return test'],
    downloadUrl: 'https://example.com/firmware.zip',
  );
  final _PopCountingNavigatorObserver navigatorObserver =
      _PopCountingNavigatorObserver();
  late final _TrackingDistingCubit distingCubit;

  FirmwareUpdateScreenDependencies get dependencies =>
      FirmwareUpdateScreenDependencies(
        firmwareVersionService: firmwareVersionService,
        flashToolManager: flashToolManager,
        flashToolBridge: flashToolBridge,
      );

  Future<void> close() async {
    await flashProgress.close();
    await distingCubit.close();
  }
}

MidiDevice _midiDevice(String id, String name, MidiPortType direction) {
  final device = MidiDevice(id, name, MidiDeviceType.serial, true);
  if (direction == MidiPortType.IN) {
    device.inputPorts.add(MidiPort(0, direction));
  } else {
    device.outputPorts.add(MidiPort(0, direction));
  }
  return device;
}

Future<FirmwareUpdateCubit> _openFirmwareAndStartManualFlash(
  WidgetTester tester,
  _FirmwareReturnHarness harness,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [harness.navigatorObserver],
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FirmwareUpdateScreen(
                  distingCubit: harness.distingCubit,
                  currentVersionOverride: '1.14.0',
                  dependencies: harness.dependencies,
                ),
              ),
            ),
            child: const Text('Open Firmware'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open Firmware'));
  await tester.pumpAndSettle();
  final listenerContext = tester.element(
    find.byType(FirmwareUpdateCompletionListener),
  );
  final firmwareCubit = listenerContext.read<FirmwareUpdateCubit>();

  await tester.tap(find.widgetWithText(FilledButton, 'Install'));
  await tester.pump();
  await tester.tap(
    find.widgetWithText(FilledButton, "I'm in bootloader mode - Flash Now"),
  );
  await tester.pump();

  return firmwareCubit;
}

void main() {
  late _MockFirmwareUpdateCubit firmwareCubit;

  setUp(() {
    firmwareCubit = _MockFirmwareUpdateCubit();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpState(WidgetTester tester, FirmwareUpdateState state) async {
    when(() => firmwareCubit.state).thenReturn(state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<FirmwareUpdateCubit>.value(
          value: firmwareCubit,
          child: Scaffold(body: FirmwareUpdateStateContent(state: state)),
        ),
      ),
    );
  }

  testWidgets('shows the shared waiting state after firmware completes', (
    tester,
  ) async {
    await pumpState(
      tester,
      const FirmwareUpdateState.verifyingMidi(
        newVersion: '1.16.0',
        completedAttempts: 5,
      ),
    );

    expect(find.text('Waiting for Disting NT'), findsOneWidget);
    expect(find.textContaining('completed successfully'), findsOneWidget);
    expect(find.text('Check 6 of 12'), findsOneWidget);
  });

  testWidgets('shows generic recovery without Windows service instructions', (
    tester,
  ) async {
    await pumpState(
      tester,
      const FirmwareUpdateState.midiRecoveryRequired(
        newVersion: '1.16.0',
        isWindows: false,
      ),
    );

    expect(find.text('Firmware Installed'), findsOneWidget);
    expect(find.textContaining('USB connection and power'), findsOneWidget);
    expect(find.textContaining('power-cycle'), findsOneWidget);
    expect(find.textContaining('restart the computer'), findsOneWidget);
    expect(find.textContaining('MidiSrv'), findsNothing);
    expect(find.text('Check Again'), findsOneWidget);
  });

  testWidgets('shows Windows MidiSrv recovery and copies the command', (
    tester,
  ) async {
    Object? clipboardArguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardArguments = call.arguments;
          }
          return null;
        });
    when(() => firmwareCubit.checkMidiAgain()).thenAnswer((_) async {});

    await pumpState(
      tester,
      const FirmwareUpdateState.midiRecoveryRequired(
        newVersion: '1.16.0',
        isWindows: true,
      ),
    );

    expect(find.textContaining('PowerShell as Administrator'), findsOneWidget);
    expect(find.text('Restart-Service MidiSrv'), findsOneWidget);
    expect(find.textContaining('Restart Windows'), findsOneWidget);

    await tester.tap(find.text('Copy Command'));
    await tester.pump();

    expect(clipboardArguments, {'text': 'Restart-Service MidiSrv'});
    expect(find.text('PowerShell command copied'), findsOneWidget);

    await tester.tap(find.text('Check Again'));
    verify(() => firmwareCubit.checkMidiAgain()).called(1);
  });

  testWidgets(
    'screen-created cubit waits for both fallback endpoints then refreshes and pops once',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final harness = _FirmwareReturnHarness();
      addTearDown(harness.close);
      final input = _midiDevice(
        'returning-input',
        'Expert Sleepers Disting NT Input',
        MidiPortType.IN,
      );
      final output = _midiDevice(
        'returning-output',
        'Expert Sleepers Disting NT Output',
        MidiPortType.OUT,
      );
      var snapshots = 0;
      when(() => harness.midiCommand.devices).thenAnswer((_) async {
        snapshots++;
        return snapshots == 1 ? [input] : [input, output];
      });

      final firmwareCubit = await _openFirmwareAndStartManualFlash(
        tester,
        harness,
      );
      final observedStates = <FirmwareUpdateState>[];
      final stateSubscription = firmwareCubit.stream.listen(observedStates.add);
      addTearDown(stateSubscription.cancel);

      harness.flashProgress.add(
        const FlashProgress(
          stage: FlashStage.complete,
          percent: 100,
          message: 'Done',
        ),
      );
      await tester.pump();

      expect(firmwareCubit.state, isA<FirmwareUpdateStateVerifyingMidi>());

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(snapshots, 1);
      expect(
        firmwareCubit.state,
        isA<FirmwareUpdateStateVerifyingMidi>().having(
          (state) => state.completedAttempts,
          'completedAttempts',
          1,
        ),
      );
      expect(harness.distingCubit.firmwareCompletionCalls, 0);
      expect(harness.navigatorObserver.popCount, 0);
      expect(find.text('Firmware Update'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(
        observedStates.whereType<FirmwareUpdateStateSuccess>(),
        hasLength(1),
      );
      expect(snapshots, 3);
      expect(harness.distingCubit.firmwareCompletionCalls, 1);
      expect(harness.navigatorObserver.popCount, 1);
      expect(find.text('Open Firmware'), findsOneWidget);
      expect(find.text('Firmware Update'), findsNothing);
      final refreshedState =
          harness.distingCubit.state as DistingStateSelectDevice;
      expect(refreshedState.inputDevices, [input]);
      expect(refreshedState.outputDevices, [output]);
      expect(refreshedState.selectedInputDevice, isNull);
      expect(refreshedState.selectedOutputDevice, isNull);
    },
  );

  testWidgets(
    'screen-created cubit retains recovery and Check Again after enumeration failures',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final harness = _FirmwareReturnHarness();
      addTearDown(harness.close);
      final input = _midiDevice(
        'returning-input',
        'Disting NT Input',
        MidiPortType.IN,
      );
      final output = _midiDevice(
        'returning-output',
        'Disting NT Output',
        MidiPortType.OUT,
      );
      var recovered = false;
      var snapshots = 0;
      when(() => harness.midiCommand.devices).thenAnswer((_) async {
        snapshots++;
        if (!recovered) throw StateError('MIDI enumeration failed');
        return [input, output];
      });

      final firmwareCubit = await _openFirmwareAndStartManualFlash(
        tester,
        harness,
      );
      harness.flashProgress.add(
        const FlashProgress(
          stage: FlashStage.complete,
          percent: 100,
          message: 'Done',
        ),
      );
      await tester.pump();

      for (var attempt = 0; attempt < 12; attempt++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
      }

      expect(
        firmwareCubit.state,
        isA<FirmwareUpdateStateMidiRecoveryRequired>(),
      );
      expect(snapshots, 12);
      expect(find.text('Firmware Installed'), findsOneWidget);
      expect(find.text('Check Again'), findsOneWidget);
      expect(harness.distingCubit.firmwareCompletionCalls, 0);
      expect(harness.navigatorObserver.popCount, 0);

      recovered = true;
      await tester.tap(find.text('Check Again'));
      await tester.pump();
      expect(firmwareCubit.state, isA<FirmwareUpdateStateVerifyingMidi>());

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(snapshots, 14);
      expect(harness.distingCubit.firmwareCompletionCalls, 1);
      expect(harness.navigatorObserver.popCount, 1);
      expect(find.text('Open Firmware'), findsOneWidget);
      expect(find.text('Firmware Installed'), findsNothing);
    },
  );

  testWidgets('successful reacquisition refreshes and closes the route', (
    tester,
  ) async {
    final firmwareStates = StreamController<FirmwareUpdateState>.broadcast();
    final distingCubit = _MockDistingCubit();
    whenListen(
      firmwareCubit,
      firmwareStates.stream,
      initialState: const FirmwareUpdateState.verifyingMidi(
        newVersion: '1.16.0',
      ),
    );
    when(() => distingCubit.state).thenReturn(
      const DistingState.selectDevice(
        inputDevices: [],
        outputDevices: [],
        canWorkOffline: false,
      ),
    );
    when(
      () => distingCubit.onFirmwareUpdateComplete(),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const Text('Device Selection'),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MultiBlocProvider(
                        providers: [
                          BlocProvider<FirmwareUpdateCubit>.value(
                            value: firmwareCubit,
                          ),
                          BlocProvider<DistingCubit>.value(value: distingCubit),
                        ],
                        child: FirmwareUpdateCompletionListener(
                          bloc: firmwareCubit,
                          child: const Scaffold(body: Text('Firmware Route')),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open Firmware'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Firmware'));
    await tester.pumpAndSettle();
    expect(find.text('Firmware Route'), findsOneWidget);

    firmwareStates.add(const FirmwareUpdateState.success(newVersion: '1.16.0'));
    await tester.pumpAndSettle();

    expect(find.text('Device Selection'), findsOneWidget);
    expect(find.text('Firmware Route'), findsNothing);
    verify(() => distingCubit.onFirmwareUpdateComplete()).called(1);

    await firmwareStates.close();
    await firmwareCubit.close();
    await distingCubit.close();
  });
}
