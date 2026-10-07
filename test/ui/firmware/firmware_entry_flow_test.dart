import 'dart:async';

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/widgets/disting_version.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockPresetsDao extends Mock implements PresetsDao {}

class _TrackingMidiManager extends DistingMidiManager {
  _TrackingMidiManager({
    required super.midiCommand,
    required super.inputDevice,
    required super.outputDevice,
    required super.sysExId,
  });

  int disposals = 0;
  int cpuReads = 0;

  @override
  Future<void> requestWake() async {}

  @override
  Future<CpuUsage?> requestCpuUsage() async {
    cpuReads++;
    return CpuUsage(cpu1: 1, cpu2: 2, slotUsages: const []);
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _MockFirmwareVersionService extends Mock
    implements FirmwareVersionService {}

class _MockFlashToolManager extends Mock implements FlashToolManager {}

class _MockFlashToolBridge extends Mock implements FlashToolBridge {}

class _TrackingDistingCubit extends DistingCubit {
  _TrackingDistingCubit(super.database, {required super.midiCommand})
    : super(isWindowsOverride: true);

  int firmwareCompletionCalls = 0;
  int firmwareManagerCreations = 0;
  int firmwareManagerDisposals = 0;
  int cpuListeners = 0;

  @override
  Stream<CpuUsage?> get cpuUsageStream => _countedCpuUsageStream;

  late final Stream<CpuUsage?> _countedCpuUsageStream = Stream<CpuUsage?>.multi(
    (controller) {
      cpuListeners++;
      final subscription = super.cpuUsageStream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        cpuListeners--;
        return subscription.cancel();
      };
    },
    isBroadcast: true,
  );

  @override
  void disposeFirmwareMidiManager(
    IDistingMidiManager manager,
    MidiDevice input,
    MidiDevice output,
  ) {
    firmwareManagerDisposals++;
    super.disposeFirmwareMidiManager(manager, input, output);
  }

  @override
  Future<IDistingMidiManager> createFirmwareMidiManager(
    MidiDevice inputDevice,
    MidiDevice outputDevice,
    int sysExId,
  ) {
    firmwareManagerCreations++;
    return super.createFirmwareMidiManager(inputDevice, outputDevice, sysExId);
  }

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

enum _FirmwareSource { downloaded, local }

class _FirmwareEntryHarness {
  _FirmwareEntryHarness._() {
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    when(() => midiCommand.onMidiSetupChanged).thenReturn(null);
    when(() => midiCommand.devices).thenAnswer((_) async {
      midiSnapshots++;
      return midiSnapshots == 1
          ? [initialInput, initialOutput]
          : [returnedInput, returnedOutput];
    });
    when(
      () => firmwareVersionService.fetchAvailableVersions(),
    ).thenAnswer((_) async => [release]);
    when(
      () => firmwareVersionService.downloadFirmware(
        release,
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => downloadedFirmwarePath);
    when(
      () => flashToolManager.getToolPath(),
    ).thenAnswer((_) async => '/path/to/nt-flash');
    when(
      () => flashToolBridge.flash(any()),
    ).thenAnswer((_) => flashProgress.stream);
    when(() => flashToolBridge.cancel()).thenAnswer((_) async {});

    distingCubit = _TrackingDistingCubit(database, midiCommand: midiCommand);
  }

  static const downloadedFirmwarePath = '/tmp/downloaded-firmware.zip';
  static const localFirmwarePath = '/tmp/local-firmware.zip';

  final _MockAppDatabase database = _MockAppDatabase();
  final _MockMetadataDao metadataDao = _MockMetadataDao();
  final MockMidiCommand midiCommand = MockMidiCommand();
  final _MockFirmwareVersionService firmwareVersionService =
      _MockFirmwareVersionService();
  final _MockFlashToolManager flashToolManager = _MockFlashToolManager();
  final _MockFlashToolBridge flashToolBridge = _MockFlashToolBridge();
  final StreamController<FlashProgress> flashProgress =
      StreamController<FlashProgress>.broadcast();
  final _PopCountingNavigatorObserver navigatorObserver =
      _PopCountingNavigatorObserver();
  final FirmwareRelease release = FirmwareRelease(
    version: '1.16.0',
    releaseDate: DateTime(2026),
    changelog: const ['Composed firmware entry flow'],
    downloadUrl: 'https://example.com/firmware.zip',
  );
  final MidiDevice initialInput = _device(
    'before-input',
    'Disting NT Input',
    MidiPortType.IN,
  );
  final MidiDevice initialOutput = _device(
    'before-output',
    'Disting NT Output',
    MidiPortType.OUT,
  );
  final MidiDevice returnedInput = _device(
    'after-input',
    'Disting NT Input',
    MidiPortType.IN,
  );
  final MidiDevice returnedOutput = _device(
    'after-output',
    'Disting NT Output',
    MidiPortType.OUT,
  );

  late final _TrackingDistingCubit distingCubit;
  int midiSnapshots = 0;
  bool _closed = false;

  static Future<_FirmwareEntryHarness> create({
    required bool selectCompletePair,
  }) async {
    SharedPreferences.setMockInitialValues(
      selectCompletePair
          ? {
              'selectedInputMidiDevice': 'Disting NT Input',
              'selectedOutputMidiDevice': 'Disting NT Output',
              'selectedSysExId': 17,
            }
          : {},
    );
    final harness = _FirmwareEntryHarness._();
    await harness.distingCubit.initialize();
    return harness;
  }

  FirmwareUpdateScreenDependencies dependencies({
    _FirmwareSource source = _FirmwareSource.downloaded,
  }) {
    final archive = Archive()
      ..addFile(ArchiveFile('bootable_images/disting_NT.bin', 4, [0, 1, 2, 3]));
    final localFirmwareBytes = ZipEncoder().encode(archive);
    return FirmwareUpdateScreenDependencies(
      firmwareVersionService: firmwareVersionService,
      flashToolManager: flashToolManager,
      flashToolBridge: flashToolBridge,
      pickLocalFirmwareFile: source == _FirmwareSource.local
          ? () async => localFirmwarePath
          : null,
      readLocalFirmwareFile: source == _FirmwareSource.local
          ? (path) async {
              expect(path, localFirmwarePath);
              return localFirmwareBytes;
            }
          : null,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await flashProgress.close();
    await distingCubit.close();
  }
}

MidiDevice _device(String id, String name, MidiPortType direction) {
  final device = MidiDevice(id, name, MidiDeviceType.serial, true);
  if (direction == MidiPortType.IN) {
    device.inputPorts.add(MidiPort(0, direction));
  } else {
    device.outputPorts.add(MidiPort(0, direction));
  }
  return device;
}

Future<void> _pumpConnectionScreen(
  WidgetTester tester,
  _FirmwareEntryHarness harness, {
  required _FirmwareSource source,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(harness.close);

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [harness.navigatorObserver],
      home: BlocProvider<DistingCubit>.value(
        value: harness.distingCubit,
        child: DistingPage(
          firmwareUpdateDependencies: harness.dependencies(source: source),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _completeManualFlash(
  WidgetTester tester,
  _FirmwareEntryHarness harness, {
  required _FirmwareSource source,
}) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Firmware'));
  await tester.pumpAndSettle();
  expect(find.text('Firmware Update'), findsOneWidget);

  switch (source) {
    case _FirmwareSource.downloaded:
      await tester.tap(find.widgetWithText(FilledButton, 'Install'));
    case _FirmwareSource.local:
      await tester.tap(find.text('Local Zip File'));
  }
  await tester.pumpAndSettle();

  final manualConfirmation = find.widgetWithText(
    FilledButton,
    "I'm in bootloader mode - Flash Now",
  );
  expect(manualConfirmation, findsOneWidget);
  expect(harness.midiSnapshots, 1);
  expect(harness.distingCubit.firmwareManagerCreations, 0);

  await tester.tap(manualConfirmation);
  await tester.pump();

  final expectedPath = source == _FirmwareSource.downloaded
      ? _FirmwareEntryHarness.downloadedFirmwarePath
      : _FirmwareEntryHarness.localFirmwarePath;
  verify(() => harness.flashToolBridge.flash(expectedPath)).called(1);

  harness.flashProgress.add(
    const FlashProgress(
      stage: FlashStage.write,
      percent: 60,
      message: 'Writing through composed flow',
    ),
  );
  await tester.pump();
  expect(find.text('Writing through composed flow'), findsOneWidget);

  harness.flashProgress.add(
    const FlashProgress(
      stage: FlashStage.complete,
      percent: 100,
      message: 'Done',
    ),
  );
  await tester.pump();
  expect(find.text('Waiting for Disting NT'), findsOneWidget);
  expect(harness.navigatorObserver.popCount, 0);

  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  expect(find.text('Firmware Update'), findsNothing);
  expect(
    find.text('Select MIDI input and output ports, then connect.'),
    findsOneWidget,
  );
  expect(harness.navigatorObserver.popCount, 1);
  expect(harness.distingCubit.firmwareCompletionCalls, 1);
  expect(harness.midiSnapshots, 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      _device('fallback', 'Fallback MIDI', MidiPortType.IN),
    );
    registerFallbackValue(
      FirmwareRelease(
        version: '0.0.0',
        releaseDate: DateTime(2024),
        changelog: const [],
        downloadUrl: '',
      ),
    );
  });

  for (final entry in ['bottom details', 'Firmware menu']) {
    testWidgets(
      'passive connected $entry visits preserve the live editor repeatedly',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({
          'show_debug_panel': false,
          'cpu_monitor_enabled': true,
          'inter_message_delay_ms': 0,
          'request_timeout_ms': 1000,
        });
        await SettingsService().init();
        final harness = _FirmwareEntryHarness._();
        addTearDown(harness.close);
        final presets = _MockPresetsDao();
        when(() => harness.database.presetsDao).thenReturn(presets);
        when(() => presets.getTemplates()).thenAnswer((_) async => []);
        final incoming = StreamController<MidiPacket>.broadcast();
        addTearDown(incoming.close);
        var midiListeners = 0;
        final packets = <Uint8List>[];
        when(() => harness.midiCommand.onMidiPacketReceived).thenAnswer(
          (_) => Stream<MidiPacket>.multi((controller) {
            midiListeners++;
            final subscription = incoming.stream.listen(controller.add);
            controller.onCancel = () {
              midiListeners--;
              return subscription.cancel();
            };
          }, isBroadcast: true),
        );
        when(
          () => harness.midiCommand.sendData(
            any(),
            deviceId: any(named: 'deviceId'),
          ),
        ).thenAnswer((invocation) {
          final packet = invocation.positionalArguments.single as Uint8List;
          packets.add(packet);
          final command = packet[6];
          if (command == 0x22 || command == 0x62) {
            incoming.add(
              MidiPacket(
                Uint8List.fromList([
                  0xF0,
                  0,
                  0x21,
                  0x27,
                  0x6D,
                  17,
                  command == 0x22 ? 0x32 : 0x62,
                  if (command == 0x22) ...'1.14.0'.codeUnits else ...[1, 2],
                  0,
                  0xF7,
                ]),
                0,
                harness.initialInput,
              ),
            );
          }
        });
        final manager = _TrackingMidiManager(
          midiCommand: harness.midiCommand,
          inputDevice: harness.initialInput,
          outputDevice: harness.initialOutput,
          sysExId: 17,
        );
        final sync = DistingState.synchronized(
          disting: manager,
          distingVersion: '1.14.0',
          firmwareVersion: FirmwareVersion('1.14.0'),
          presetName: 'Retained patch',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
          inputDevice: harness.initialInput,
          outputDevice: harness.initialOutput,
        );
        harness.distingCubit.emit(sync);
        McpServerService.initialize(distingCubit: harness.distingCubit);
        final emitted = <DistingState>[];
        final subscription = harness.distingCubit.stream.listen(emitted.add);
        addTearDown(subscription.cancel);
        await _pumpConnectionScreen(
          tester,
          harness,
          source: _FirmwareSource.downloaded,
        );
        addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
        final editor = tester.state(find.byType(SynchronizedScreen));
        final detailsRect = tester.getRect(find.byType(DistingVersion));
        expect(midiListeners, 1);
        expect(harness.distingCubit.cpuListeners, 1);
        expect(
          find.bySemanticsLabel('CPU usage: Audio thread 1%, Overall CPU 2%'),
          findsOneWidget,
        );
        for (var visit = 0; visit < 3; visit++) {
          if (entry == 'bottom details') {
            await tester.tap(find.byType(DistingVersion));
          } else {
            await tester.tap(find.byTooltip('Show menu').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Firmware'));
          }
          await tester.pumpAndSettle();
          expect(find.byType(FirmwareUpdateScreen), findsOneWidget);
          final updater = tester
              .element(find.byType(FirmwareUpdateStateContent))
              .read<FirmwareUpdateCubit>();
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          expect(updater.isClosed, isTrue);
          expect(find.byType(FirmwareUpdateScreen), findsNothing);
          expect(tester.state(find.byType(SynchronizedScreen)), same(editor));
          expect(tester.getRect(find.byType(DistingVersion)), detailsRect);
          expect(harness.distingCubit.state, same(sync));
          expect(harness.distingCubit.disting(), same(manager));
          expect(
            (harness.distingCubit.state as DistingStateSynchronized)
                .inputDevice,
            same(harness.initialInput),
          );
          expect(
            (harness.distingCubit.state as DistingStateSynchronized)
                .outputDevice,
            same(harness.initialOutput),
          );
          expect(manager.sysExId, 17);
          expect(manager.disposals, 0);
          expect(midiListeners, 1);
          expect(harness.distingCubit.cpuListeners, 1);
          String? readback;
          final request = manager.requestVersionString().then(
            (value) => readback = value,
          );
          for (var tick = 0; tick < 10 && readback == null; tick++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(readback, '1.14.0');
          await request;
          final polls = manager.cpuReads;
          await tester.pump(const Duration(seconds: 10));
          await tester.pumpAndSettle();
          expect(
            manager.cpuReads,
            polls + 1,
            reason:
                'visit $visit, listeners ${harness.distingCubit.cpuListeners}',
          );
        }
        expect(emitted, isEmpty);
        expect(
          harness.navigatorObserver.popCount,
          entry == 'Firmware menu' ? 6 : 3,
        );
        expect(harness.distingCubit.firmwareManagerCreations, 0);
        expect(harness.distingCubit.firmwareManagerDisposals, 0);
        expect(harness.distingCubit.firmwareCompletionCalls, 0);
        expect(harness.flashProgress.hasListener, isFalse);
        expect(packets.every((p) => p[5] == 17), isTrue);
        expect(packets.map((p) => p[6]).toSet(), isNot(contains(0x7C)));
        verifyNever(() => harness.midiCommand.disconnectDevice(any()));
        verifyNever(() => harness.midiCommand.connectToDevice(any()));
        verifyNever(() => harness.midiCommand.dispose());
        verifyNever(
          () => harness.firmwareVersionService.downloadFirmware(
            any(),
            onProgress: any(named: 'onProgress'),
          ),
        );
        verifyNever(() => harness.flashToolManager.getToolPath());
        verifyNever(() => harness.flashToolBridge.flash(any()));
        verifyNever(() => harness.flashToolBridge.cancel());
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 200));
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final inputOnly in [true, false]) {
    final selectedEndpoint = inputOnly ? 'input' : 'output';
    testWidgets(
      'connection Firmware opens with only the $selectedEndpoint selected',
      (tester) async {
        final input = _device('input', 'Disting NT Input', MidiPortType.IN);
        final output = _device('output', 'Disting NT Output', MidiPortType.OUT);
        final state = DistingState.selectDevice(
          inputDevices: [input],
          outputDevices: [output],
          canWorkOffline: false,
          selectedInputDevice: inputOnly ? input : null,
          selectedOutputDevice: inputOnly ? null : output,
          selectedSysExId: 17,
        );
        final states = StreamController<DistingState>();
        final cubit = _MockDistingCubit();
        final firmwareVersionService = _MockFirmwareVersionService();
        final flashToolManager = _MockFlashToolManager();
        final flashToolBridge = _MockFlashToolBridge();
        whenListen(cubit, states.stream, initialState: state);
        when(
          () => firmwareVersionService.fetchAvailableVersions(),
        ).thenAnswer((_) async => const []);
        addTearDown(states.close);

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<DistingCubit>.value(
              value: cubit,
              child: DistingPage(
                firmwareUpdateDependencies: FirmwareUpdateScreenDependencies(
                  firmwareVersionService: firmwareVersionService,
                  flashToolManager: flashToolManager,
                  flashToolBridge: flashToolBridge,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final connect = find.widgetWithText(FilledButton, 'Connect');
        expect(tester.widget<FilledButton>(connect).onPressed, isNull);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Firmware'));
        await tester.pumpAndSettle();

        final firmwareScreen = tester.widget<FirmwareUpdateScreen>(
          find.byType(FirmwareUpdateScreen),
        );
        expect(firmwareScreen.inputDevice, inputOnly ? same(input) : isNull);
        expect(firmwareScreen.outputDevice, inputOnly ? isNull : same(output));
        expect(firmwareScreen.sysExId, 17);
        expect(find.text('Firmware Update'), findsOneWidget);
        verifyNever(() => cubit.createFirmwareMidiManager(any(), any(), any()));
        verifyNever(() => flashToolBridge.flash(any()));

        Navigator.of(tester.element(find.text('Firmware Update'))).pop();
        await tester.pumpAndSettle();
        expect(
          find.text('Select MIDI input and output ports, then connect.'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'connection Firmware downloads and returns after a complete flash without a MIDI selection',
    (tester) async {
      final harness = await _FirmwareEntryHarness.create(
        selectCompletePair: false,
      );
      await _pumpConnectionScreen(
        tester,
        harness,
        source: _FirmwareSource.downloaded,
      );

      final initialState =
          harness.distingCubit.state as DistingStateSelectDevice;
      expect(initialState.selectedInputDevice, isNull);
      expect(initialState.selectedOutputDevice, isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
            .onPressed,
        isNull,
      );

      await _completeManualFlash(
        tester,
        harness,
        source: _FirmwareSource.downloaded,
      );

      final returnedState =
          harness.distingCubit.state as DistingStateSelectDevice;
      expect(returnedState.inputDevices, [harness.returnedInput]);
      expect(returnedState.outputDevices, [harness.returnedOutput]);
      expect(returnedState.selectedInputDevice, isNull);
      expect(returnedState.selectedOutputDevice, isNull);
      expect(harness.distingCubit.firmwareManagerCreations, 0);
    },
  );

  testWidgets(
    'connection Firmware accepts a local ZIP and returns after a complete flash with MIDI selected',
    (tester) async {
      final harness = await _FirmwareEntryHarness.create(
        selectCompletePair: true,
      );
      await _pumpConnectionScreen(
        tester,
        harness,
        source: _FirmwareSource.local,
      );

      final initialState =
          harness.distingCubit.state as DistingStateSelectDevice;
      expect(initialState.selectedInputDevice, same(harness.initialInput));
      expect(initialState.selectedOutputDevice, same(harness.initialOutput));
      expect(initialState.selectedSysExId, 17);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
            .onPressed,
        isNotNull,
      );

      await _completeManualFlash(
        tester,
        harness,
        source: _FirmwareSource.local,
      );

      final returnedState =
          harness.distingCubit.state as DistingStateSelectDevice;
      expect(returnedState.inputDevices, [harness.returnedInput]);
      expect(returnedState.outputDevices, [harness.returnedOutput]);
      expect(returnedState.selectedInputDevice, same(harness.returnedInput));
      expect(returnedState.selectedOutputDevice, same(harness.returnedOutput));
      expect(returnedState.selectedSysExId, 17);
    },
  );
}
