import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppDatabase database;
  late _MockMetadataDao metadataDao;
  late MockMidiCommand midiCommand;
  late DistingCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    midiCommand = MockMidiCommand();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: true,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  MidiDevice device(String id, String name, MidiPortType direction) {
    final device = MidiDevice(id, name, MidiDeviceType.serial, true);
    if (direction == MidiPortType.IN) {
      device.inputPorts.add(MidiPort(0, direction));
    } else {
      device.outputPorts.add(MidiPort(0, direction));
    }
    return device;
  }

  test('releases input and output independently and retains MidiCommand', () {
    final input = device('input', 'Disting NT', MidiPortType.IN);
    final output = device('output', 'Disting NT', MidiPortType.OUT);
    final manager = _MockDistingMidiManager();
    when(
      () => midiCommand.disconnectDevice(input),
    ).thenThrow(StateError('input already gone'));
    when(() => midiCommand.disconnectDevice(output)).thenAnswer((_) {});
    when(() => manager.dispose()).thenAnswer((_) {});

    cubit.disposeFirmwareMidiManager(manager, input, output);

    verify(() => midiCommand.disconnectDevice(input)).called(1);
    verify(() => midiCommand.disconnectDevice(output)).called(1);
    verify(() => manager.dispose()).called(1);
    verifyNever(() => midiCommand.dispose());
  });

  test('firmware handoff stops polling the disposed pre-flash manager', () {
    final input = device('input', 'Disting NT', MidiPortType.IN);
    final output = device('output', 'Disting NT', MidiPortType.OUT);
    final manager = _MockDistingMidiManager();
    when(() => manager.requestWake()).thenAnswer((_) async {});
    when(
      () => manager.requestCpuUsage(),
    ).thenAnswer((_) async => CpuUsage(cpu1: 1, cpu2: 2, slotUsages: const []));
    when(() => manager.dispose()).thenAnswer((_) {});
    when(() => midiCommand.disconnectDevice(input)).thenAnswer((_) {});
    when(() => midiCommand.disconnectDevice(output)).thenAnswer((_) {});
    cubit.emit(
      DistingState.synchronized(
        disting: manager,
        distingVersion: '1.16.0',
        firmwareVersion: FirmwareVersion('1.16.0'),
        presetName: 'Test',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
        inputDevice: input,
        outputDevice: output,
      ),
    );

    fakeAsync((async) {
      final subscription = cubit.cpuUsageStream.listen((_) {});
      async.flushMicrotasks();
      verify(() => manager.requestCpuUsage()).called(1);
      clearInteractions(manager);

      cubit.disposeFirmwareMidiManager(manager, input, output);
      clearInteractions(manager);
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      verifyNever(() => manager.requestWake());
      verifyNever(() => manager.requestCpuUsage());
      subscription.cancel();
    });
  });

  test(
    'uses a fresh snapshot and refreshes device selection on completion',
    () async {
      final input = device('input', 'Disting NT', MidiPortType.IN);
      final output = device('output', 'Disting NT', MidiPortType.OUT);
      var snapshots = 0;
      when(() => midiCommand.devices).thenAnswer((_) async {
        snapshots++;
        return snapshots == 1 ? [] : [input, output];
      });
      when(() => midiCommand.onMidiSetupChanged).thenReturn(null);

      expect(
        await cubit.firmwareMidiDevicesAvailable('Disting NT', 'Disting NT'),
        isFalse,
      );
      expect(
        await cubit.firmwareMidiDevicesAvailable('Disting NT', 'Disting NT'),
        isTrue,
      );

      await cubit.onFirmwareUpdateComplete();

      expect(snapshots, 3);
      final state = cubit.state as DistingStateSelectDevice;
      expect(state.inputDevices, [input]);
      expect(state.outputDevices, [output]);
      verifyNever(() => midiCommand.dispose());
    },
  );

  test(
    'recreates the native MIDI client after firmware release off Windows',
    () async {
      final input = device('input', 'Disting NT', MidiPortType.IN);
      final output = device('output', 'Disting NT', MidiPortType.OUT);
      final manager = _MockDistingMidiManager();
      final originalCommand = MockMidiCommand();
      final replacementCommand = MockMidiCommand();
      when(() => originalCommand.disconnectDevice(input)).thenAnswer((_) {});
      when(() => originalCommand.disconnectDevice(output)).thenAnswer((_) {});
      when(() => originalCommand.dispose()).thenAnswer((_) {});
      when(() => manager.dispose()).thenAnswer((_) {});
      when(
        () => replacementCommand.devices,
      ).thenAnswer((_) async => [input, output]);
      when(() => replacementCommand.onMidiSetupChanged).thenReturn(null);

      final nonWindowsCubit = DistingCubit(
        database,
        midiCommand: originalCommand,
        midiCommandFactory: () => replacementCommand,
        isWindowsOverride: false,
      );
      addTearDown(nonWindowsCubit.close);

      nonWindowsCubit.disposeFirmwareMidiManager(manager, input, output);

      expect(
        await nonWindowsCubit.firmwareMidiDevicesAvailable(
          'Disting NT',
          'Disting NT',
        ),
        isTrue,
      );
      verify(() => originalCommand.dispose()).called(1);
      verify(() => replacementCommand.devices).called(1);
      verifyNever(() => originalCommand.devices);
    },
  );

  test(
    'reacquires the exact MIDI names saved by the last connection',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedInputMidiDevice', 'Saved NT Input');
      await prefs.setString('selectedOutputMidiDevice', 'Saved NT Output');
      await prefs.setInt('selectedSysExId', 7);
      final input = device('input', 'Saved NT Input', MidiPortType.IN);
      final output = device('output', 'Saved NT Output', MidiPortType.OUT);
      when(() => midiCommand.devices).thenAnswer((_) async => [input, output]);

      expect(
        await cubit.firmwareMidiDevicesAvailable(
          'Wrong Fallback Input',
          'Wrong Fallback Output',
        ),
        isTrue,
      );
    },
  );

  test('manual MIDI selection survives an explicit device refresh', () async {
    final input = device('input', 'Forever', MidiPortType.IN);
    final output = device('output', 'Forever', MidiPortType.OUT);
    final refreshedInput = device('input', 'Forever', MidiPortType.IN);
    final refreshedOutput = device('output', 'Forever', MidiPortType.OUT);
    var snapshot = 0;
    when(() => midiCommand.devices).thenAnswer((_) async {
      snapshot++;
      return snapshot == 1
          ? [input, output]
          : [refreshedInput, refreshedOutput];
    });
    when(() => midiCommand.onMidiSetupChanged).thenReturn(null);

    await cubit.initialize();
    cubit.updateDeviceSelection(
      inputDevice: input,
      outputDevice: output,
      sysExId: 7,
    );

    await cubit.loadDevices();

    final state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(refreshedInput));
    expect(state.selectedOutputDevice, same(refreshedOutput));
    expect(state.selectedSysExId, 7);
    verifyNever(() => midiCommand.connectToDevice(input));
    verifyNever(() => midiCommand.connectToDevice(output));
    verifyNever(() => midiCommand.connectToDevice(refreshedInput));
    verifyNever(() => midiCommand.connectToDevice(refreshedOutput));
  });

  test('selection made during refresh survives its completion', () async {
    final input = device('input', 'Forever', MidiPortType.IN);
    final output = device('output', 'Forever', MidiPortType.OUT);
    final refreshedInput = device('input', 'Forever', MidiPortType.IN);
    final refreshedOutput = device('output', 'Forever', MidiPortType.OUT);
    final refreshSnapshot = Completer<List<MidiDevice>?>();
    var snapshot = 0;
    when(() => midiCommand.devices).thenAnswer((_) {
      snapshot++;
      return snapshot == 1
          ? Future.value([input, output])
          : refreshSnapshot.future;
    });
    when(() => midiCommand.onMidiSetupChanged).thenReturn(null);

    await cubit.initialize();
    final refresh = cubit.loadDevices();
    cubit.updateDeviceSelection(
      inputDevice: input,
      outputDevice: output,
      sysExId: 12,
    );
    refreshSnapshot.complete([refreshedInput, refreshedOutput]);

    await refresh;

    final state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(refreshedInput));
    expect(state.selectedOutputDevice, same(refreshedOutput));
    expect(state.selectedSysExId, 12);
  });

  test('failed refresh keeps the existing manual selection', () async {
    final input = device('input', 'Forever', MidiPortType.IN);
    final output = device('output', 'Forever', MidiPortType.OUT);
    var snapshot = 0;
    when(() => midiCommand.devices).thenAnswer((_) async {
      snapshot++;
      if (snapshot > 1) throw StateError('MIDI discovery failed');
      return [input, output];
    });
    when(() => midiCommand.onMidiSetupChanged).thenReturn(null);

    await cubit.initialize();
    cubit.updateDeviceSelection(
      inputDevice: input,
      outputDevice: output,
      sysExId: 7,
    );

    await cubit.loadDevices();

    final state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(input));
    expect(state.selectedOutputDevice, same(output));
    expect(state.selectedSysExId, 7);
  });

  test(
    'initialize shows all MIDI devices without reconnecting saved ports',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedInputMidiDevice', 'Disting NT');
      await prefs.setString('selectedOutputMidiDevice', 'Disting NT');
      await prefs.setInt('selectedSysExId', 0);
      final distingInput = device(
        'disting-input',
        'Disting NT',
        MidiPortType.IN,
      );
      final distingOutput = device(
        'disting-output',
        'Disting NT',
        MidiPortType.OUT,
      );
      final foreverInput = device('forever-input', 'Forever', MidiPortType.IN);
      final foreverOutput = device(
        'forever-output',
        'Forever',
        MidiPortType.OUT,
      );
      when(() => midiCommand.devices).thenAnswer(
        (_) async => [distingInput, distingOutput, foreverInput, foreverOutput],
      );
      when(() => midiCommand.onMidiSetupChanged).thenReturn(null);
      when(
        () => midiCommand.connectToDevice(distingInput),
      ).thenThrow(StateError('saved-device autoconnect attempted'));

      await cubit.initialize();

      final state = cubit.state as DistingStateSelectDevice;
      expect(state.inputDevices, containsAll([distingInput, foreverInput]));
      expect(state.outputDevices, containsAll([distingOutput, foreverOutput]));
      expect(state.selectedInputDevice, distingInput);
      expect(state.selectedOutputDevice, distingOutput);
      expect(state.selectedSysExId, 0);
      verifyNever(() => midiCommand.connectToDevice(distingInput));
      verifyNever(() => midiCommand.connectToDevice(distingOutput));
    },
  );
}
