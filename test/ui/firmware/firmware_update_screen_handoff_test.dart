import 'dart:async';

import 'package:archive/archive.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

class _MockFirmwareVersionService extends Mock
    implements FirmwareVersionService {}

class _MockFlashToolManager extends Mock implements FlashToolManager {}

class _MockFlashToolBridge extends Mock implements FlashToolBridge {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

MidiDevice _inputDevice() =>
    MidiDevice('input', 'Disting NT Input', MidiDeviceType.serial, true)
      ..inputPorts.add(MidiPort(0, MidiPortType.IN));

MidiDevice _outputDevice() =>
    MidiDevice('output', 'Disting NT Output', MidiDeviceType.serial, true)
      ..outputPorts.add(MidiPort(0, MidiPortType.OUT));

DistingState _selectionState({
  MidiDevice? inputDevice,
  MidiDevice? outputDevice,
}) => DistingState.selectDevice(
  inputDevices: [?inputDevice],
  outputDevices: [?outputDevice],
  canWorkOffline: true,
  selectedInputDevice: inputDevice,
  selectedOutputDevice: outputDevice,
  selectedSysExId: 17,
);

void _stubDistingState(_MockDistingCubit cubit, DistingState state) {
  whenListen(cubit, const Stream<DistingState>.empty(), initialState: state);
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DistingCubit distingCubit,
  required FirmwareUpdateScreenDependencies dependencies,
  String? currentVersionOverride,
  MidiDevice? inputDevice,
  MidiDevice? outputDevice,
  int? sysExId,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: FirmwareUpdateScreen(
        distingCubit: distingCubit,
        currentVersionOverride: currentVersionOverride,
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: sysExId,
        dependencies: dependencies,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpBootloaderWait(WidgetTester tester) async {
  await tester.pump();
  for (var tick = 0; tick < 50; tick++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDistingCubit distingCubit;
  late _MockFirmwareVersionService firmwareVersionService;
  late _MockFlashToolManager flashToolManager;
  late _MockFlashToolBridge flashToolBridge;
  late FirmwareRelease release;

  setUpAll(() {
    registerFallbackValue(
      FirmwareRelease(
        version: '0.0.0',
        releaseDate: DateTime(2024),
        changelog: const [],
        downloadUrl: '',
      ),
    );
    registerFallbackValue(_inputDevice());
  });

  setUp(() {
    distingCubit = _MockDistingCubit();
    firmwareVersionService = _MockFirmwareVersionService();
    flashToolManager = _MockFlashToolManager();
    flashToolBridge = _MockFlashToolBridge();
    release = FirmwareRelease(
      version: '1.16.0',
      releaseDate: DateTime(2026),
      changelog: const ['Firmware handoff test'],
      downloadUrl: 'https://example.com/firmware.zip',
    );

    when(
      () => firmwareVersionService.fetchAvailableVersions(),
    ).thenAnswer((_) async => [release]);
    when(
      () => firmwareVersionService.downloadFirmware(
        any(),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => '/tmp/downloaded-firmware.zip');
    when(
      () => flashToolManager.getToolPath(),
    ).thenAnswer((_) async => '/path/to/nt-flash');
    when(() => flashToolBridge.cancel()).thenAnswer((_) async {});
  });

  FirmwareUpdateScreenDependencies dependencies({
    LocalFirmwareFilePicker? pickLocalFirmwareFile,
    LocalFirmwareFileReader? readLocalFirmwareFile,
  }) => FirmwareUpdateScreenDependencies(
    firmwareVersionService: firmwareVersionService,
    flashToolManager: flashToolManager,
    flashToolBridge: flashToolBridge,
    pickLocalFirmwareFile: pickLocalFirmwareFile,
    readLocalFirmwareFile: readLocalFirmwareFile,
  );

  testWidgets(
    'downloaded firmware reaches the flasher without MIDI and propagates progress and errors',
    (tester) async {
      final flashProgress = StreamController<FlashProgress>();
      addTearDown(flashProgress.close);
      _stubDistingState(distingCubit, _selectionState());
      when(
        () => flashToolBridge.flash(any()),
      ).thenAnswer((_) => flashProgress.stream);

      await _pumpScreen(
        tester,
        distingCubit: distingCubit,
        dependencies: dependencies(),
        currentVersionOverride: '1.15.0',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Install'));
      await tester.pump();

      expect(
        find.widgetWithText(FilledButton, "I'm in bootloader mode - Flash Now"),
        findsOneWidget,
      );
      verifyNever(
        () => distingCubit.createFirmwareMidiManager(any(), any(), any()),
      );

      await tester.tap(
        find.widgetWithText(FilledButton, "I'm in bootloader mode - Flash Now"),
      );
      await tester.pump();

      verify(
        () => flashToolBridge.flash('/tmp/downloaded-firmware.zip'),
      ).called(1);
      flashProgress.add(
        const FlashProgress(
          stage: FlashStage.write,
          percent: 40,
          message: 'Writing downloaded firmware',
        ),
      );
      await tester.pump();
      expect(find.text('Writing downloaded firmware'), findsOneWidget);

      flashProgress.add(
        const FlashProgress(
          stage: FlashStage.write,
          percent: 40,
          message: 'Downloaded firmware write failed',
          isError: true,
        ),
      );
      await tester.pump();
      expect(find.text('Downloaded firmware write failed'), findsOneWidget);
      verifyNever(
        () => distingCubit.createFirmwareMidiManager(any(), any(), any()),
      );
    },
  );

  testWidgets(
    'unknown firmware keeps complete selection on manual local ZIP handoff',
    (tester) async {
      const firmwarePath = '/tmp/local-firmware.zip';
      final archive = Archive()
        ..addFile(
          ArchiveFile('bootable_images/disting_NT.bin', 4, [0, 1, 2, 3]),
        );
      final firmwareBytes = ZipEncoder().encode(archive);
      final inputDevice = _inputDevice();
      final outputDevice = _outputDevice();
      final midiManager = _MockDistingMidiManager();
      final flashProgress = StreamController<FlashProgress>();
      addTearDown(flashProgress.close);

      _stubDistingState(
        distingCubit,
        _selectionState(inputDevice: inputDevice, outputDevice: outputDevice),
      );
      when(
        () => distingCubit.createFirmwareMidiManager(
          inputDevice,
          outputDevice,
          17,
        ),
      ).thenAnswer((_) async => midiManager);
      when(
        () => flashToolBridge.flash(any()),
      ).thenAnswer((_) => flashProgress.stream);

      await _pumpScreen(
        tester,
        distingCubit: distingCubit,
        dependencies: dependencies(
          pickLocalFirmwareFile: () async => firmwarePath,
          readLocalFirmwareFile: (path) async {
            expect(path, firmwarePath);
            return firmwareBytes;
          },
        ),
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: 17,
      );

      await tester.tap(find.text('Local Zip File'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, "I'm in bootloader mode - Flash Now"),
        findsOneWidget,
      );
      verifyNever(
        () => distingCubit.createFirmwareMidiManager(
          inputDevice,
          outputDevice,
          17,
        ),
      );
      verifyNever(() => midiManager.requestEnterBootloader());

      await tester.tap(
        find.widgetWithText(FilledButton, "I'm in bootloader mode - Flash Now"),
      );
      await tester.pump();

      verify(() => flashToolBridge.flash(firmwarePath)).called(1);
      verifyNever(
        () => distingCubit.createFirmwareMidiManager(
          inputDevice,
          outputDevice,
          17,
        ),
      );
      verifyNever(() => midiManager.requestEnterBootloader());
    },
  );

  testWidgets(
    'known capable selection lazily creates, boots, and releases MIDI before flashing',
    (tester) async {
      final inputDevice = _inputDevice();
      final outputDevice = _outputDevice();
      final midiManager = _MockDistingMidiManager();
      final flashProgress = StreamController<FlashProgress>();
      final events = <String>[];
      addTearDown(flashProgress.close);

      _stubDistingState(
        distingCubit,
        _selectionState(inputDevice: inputDevice, outputDevice: outputDevice),
      );
      when(
        () => distingCubit.createFirmwareMidiManager(
          inputDevice,
          outputDevice,
          17,
        ),
      ).thenAnswer((_) async {
        events.add('create');
        return midiManager;
      });
      when(() => midiManager.requestEnterBootloader()).thenAnswer((_) async {
        events.add('bootloader');
      });
      when(
        () => distingCubit.disposeFirmwareMidiManager(
          midiManager,
          inputDevice,
          outputDevice,
        ),
      ).thenAnswer((_) {
        events.add('release');
      });
      when(() => flashToolBridge.flash(any())).thenAnswer((_) {
        events.add('flash');
        return flashProgress.stream;
      });

      await _pumpScreen(
        tester,
        distingCubit: distingCubit,
        dependencies: dependencies(),
        currentVersionOverride: '1.15.0',
        inputDevice: inputDevice,
        outputDevice: outputDevice,
        sysExId: 17,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Install'));
      await tester.pump();
      expect(
        find.widgetWithText(FilledButton, 'Update Firmware'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Update Firmware'));
      await _pumpBootloaderWait(tester);

      expect(events, ['create', 'bootloader', 'release', 'flash']);
      verify(() => midiManager.requestEnterBootloader()).called(1);
      verify(
        () => distingCubit.disposeFirmwareMidiManager(
          midiManager,
          inputDevice,
          outputDevice,
        ),
      ).called(1);
      verify(
        () => flashToolBridge.flash('/tmp/downloaded-firmware.zip'),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      verifyNoMoreInteractions(midiManager);
    },
  );

  testWidgets(
    'known capable synchronized manager is released before flashing without lazy creation',
    (tester) async {
      final inputDevice = _inputDevice();
      final outputDevice = _outputDevice();
      final midiManager = _MockDistingMidiManager();
      final flashProgress = StreamController<FlashProgress>();
      final events = <String>[];
      addTearDown(flashProgress.close);

      _stubDistingState(
        distingCubit,
        DistingState.synchronized(
          disting: midiManager,
          distingVersion: '1.15.0',
          firmwareVersion: FirmwareVersion('1.15.0'),
          presetName: 'Test',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
          inputDevice: inputDevice,
          outputDevice: outputDevice,
        ),
      );
      when(() => distingCubit.disting()).thenReturn(midiManager);
      when(() => midiManager.requestEnterBootloader()).thenAnswer((_) async {
        events.add('bootloader');
      });
      when(
        () => distingCubit.disposeFirmwareMidiManager(
          midiManager,
          inputDevice,
          outputDevice,
        ),
      ).thenAnswer((_) {
        events.add('release');
      });
      when(() => flashToolBridge.flash(any())).thenAnswer((_) {
        events.add('flash');
        return flashProgress.stream;
      });

      await _pumpScreen(
        tester,
        distingCubit: distingCubit,
        dependencies: dependencies(),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Install'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Update Firmware'));
      await _pumpBootloaderWait(tester);

      expect(events, ['bootloader', 'release', 'flash']);
      verifyNever(
        () => distingCubit.createFirmwareMidiManager(any(), any(), any()),
      );
      verify(() => midiManager.requestEnterBootloader()).called(1);
      verify(
        () => distingCubit.disposeFirmwareMidiManager(
          midiManager,
          inputDevice,
          outputDevice,
        ),
      ).called(1);
      verify(
        () => flashToolBridge.flash('/tmp/downloaded-firmware.zip'),
      ).called(1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      verifyNoMoreInteractions(midiManager);
    },
  );
}
