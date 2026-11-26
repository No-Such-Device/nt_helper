import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/module_settings_fixtures.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockDistingCubit extends MockCubit<DistingState>
    implements DistingCubit {}

class _FakeMidiCommand extends Fake implements MidiCommand {
  _FakeMidiCommand() {
    _setupController = StreamController<MidiSetupChange>.broadcast(
      sync: true,
      onListen: () => setupListenerCount++,
      onCancel: () => setupListenerCount--,
    );
    _packetController = StreamController<MidiPacket>.broadcast(
      onListen: () => packetListenerCount++,
      onCancel: () => packetListenerCount--,
    );
  }

  late final StreamController<MidiSetupChange> _setupController;
  late final StreamController<MidiPacket> _packetController;

  List<MidiDevice> availableDevices = [];
  final Set<String> openDeviceIds = {};
  final Map<String, MidiDevice> connectedLinuxDevices = {};
  final Set<String> alsaConnectedEndpoints = {};
  final Map<String, Completer<void>> pendingAsyncDisconnectById = {};
  final Map<String, Completer<void>> pendingConnectByDeviceId = {};
  final List<Completer<void>> pendingConnectQueue = [];
  Completer<void>? pendingDevicesGate;
  VoidCallback? onDevicesRequested;
  bool simulateLinuxAsyncClose = false;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];
  final List<Uint8List> sentPackets = [];

  int setupListenerCount = 0;
  int packetListenerCount = 0;
  int disposeCalls = 0;
  int teardownCalls = 0;

  String firmwareVersion = '1.15.0';
  String presetName = 'Before Disconnect';
  bool mutateNameOnFirstPacket = false;
  bool respondToQueries = true;
  bool respondToSettings = true;
  bool respondToSd = true;
  bool throwOnConnect = false;
  String? throwOnConnectDeviceId;
  Completer<void>? pendingConnect;
  void Function(Uint8List packet)? onPacketSent;

  MidiDevice? _activeInputDevice;
  MidiDevice? _activeOutputDevice;

  @override
  Future<List<MidiDevice>?> get devices async {
    onDevicesRequested?.call();
    final gate = pendingDevicesGate;
    if (gate != null) {
      pendingDevicesGate = null;
      await gate.future;
    }
    if (!simulateLinuxAsyncClose) {
      return List<MidiDevice>.of(availableDevices);
    }
    // Mirrors FlutterMidiCommandLinux.devices (1.4.0, lines 132-154):
    // returns the existing connected LinuxMidiDevice for connected IDs and
    // creates fresh disconnected instances for non-connected IDs.
    return availableDevices
        .map((device) {
          final existing = connectedLinuxDevices[device.id];
          if (existing != null) {
            existing
              ..name = device.name
              ..connected = true;
            return existing;
          }
          final fresh = MidiDevice(device.id, device.name, device.type, false);
          for (final port in device.inputPorts) {
            fresh.inputPorts.add(MidiPort(port.id, port.type));
          }
          for (final port in device.outputPorts) {
            fresh.outputPorts.add(MidiPort(port.id, port.type));
          }
          return fresh;
        })
        .toList(growable: false);
  }

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => _setupController.stream;

  @override
  Stream<MidiPacket>? get onMidiPacketReceived => _packetController.stream;

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout = const Duration(seconds: 30),
  }) async {
    connectCalls.add(device.id);
    if (throwOnConnect || throwOnConnectDeviceId == device.id) {
      throw StateError('Port unavailable: ${device.id}');
    }
    final queuedGate = pendingConnectQueue.isNotEmpty
        ? pendingConnectQueue.removeAt(0)
        : null;
    if (queuedGate != null) {
      await queuedGate.future;
    }
    final perDeviceGate = pendingConnectByDeviceId.remove(device.id);
    if (perDeviceGate != null) {
      await perDeviceGate.future;
    }
    if (pendingConnect != null) {
      await pendingConnect!.future;
    }
    if (!availableDevices.any((d) => d.id == device.id)) {
      throw StateError('Device not present: ${device.id}');
    }
    if (simulateLinuxAsyncClose) {
      if (connectedLinuxDevices.containsKey(device.id)) {
        return;
      }
      // Mirrors AlsaSeqLinuxDevice.connect (lines 91-94): if the underlying
      // endpoint is still marked connected because an unawaited disconnect has
      // not reached ALSA teardown yet, connect() returns early and the late
      // disconnect then tears down the ALSA route.
      if (!alsaConnectedEndpoints.contains(device.id)) {
        alsaConnectedEndpoints.add(device.id);
      }
      connectedLinuxDevices[device.id] = device;
    }
    openDeviceIds.add(device.id);
    if (device.inputPorts.isNotEmpty) {
      _activeInputDevice = device;
    }
    if (device.outputPorts.isNotEmpty) {
      _activeOutputDevice = device;
    }
    device.connected = true;
    _setupController.add(MidiSetupChange.deviceConnected);
  }

  @override
  void disconnectDevice(MidiDevice device) {
    disconnectCalls.add(device.id);
    if (simulateLinuxAsyncClose) {
      final existing = connectedLinuxDevices.remove(device.id);
      if (existing == null) {
        return;
      }
      // Mirrors FlutterMidiCommandLinux.disconnectDevice (lines 179-190) and
      // LinuxMidiDevice.disconnect (lines 84-90): removes map entry and emits
      // deviceDisconnected + connected=false synchronously, then awaits rx sub
      // cancellation before running AlsaSeqLinuxDevice.disconnect.
      _setupController.add(MidiSetupChange.deviceDisconnected);
      existing.connected = false;
      final closeGate = pendingAsyncDisconnectById.remove(device.id);
      unawaited(() async {
        if (closeGate != null) {
          await closeGate.future;
        }
        alsaConnectedEndpoints.remove(device.id);
        openDeviceIds.remove(device.id);
      }());
      return;
    }
    openDeviceIds.remove(device.id);
    device.connected = false;
    _setupController.add(MidiSetupChange.deviceDisconnected);
  }

  @override
  void sendData(Uint8List data, {String? deviceId, int? timestamp}) {
    final copy = Uint8List.fromList(data);
    sentPackets.add(copy);
    onPacketSent?.call(copy);
    if (!respondToQueries) return;
    if (deviceId == null || !openDeviceIds.contains(deviceId)) return;
    if (simulateLinuxAsyncClose && !alsaConnectedEndpoints.contains(deviceId)) {
      return;
    }
    final input = _activeInputDevice;
    if (input == null || !openDeviceIds.contains(input.id)) return;
    if (simulateLinuxAsyncClose && !alsaConnectedEndpoints.contains(input.id)) {
      return;
    }
    if (data.length < 8 || data[0] != 0xF0 || data[4] != 0x6D) return;

    final sysExId = data[5];
    final command = data[6];
    if (mutateNameOnFirstPacket) {
      input.name = '${input.name} ${input.name}';
      if (_activeOutputDevice != null && _activeOutputDevice!.id != input.id) {
        _activeOutputDevice!.name =
            '${_activeOutputDevice!.name} ${_activeOutputDevice!.name}';
      }
      mutateNameOnFirstPacket = false;
    }

    if (command == 0x63 || command == 0x64 || command == 0x65) {
      if (!respondToSettings) return;
      final settingId = data.length >= 11 ? decode16(data, 7) : 0;
      final payload = switch (command) {
        0x63 => settingsGroupsPayload(),
        0x64 => settingInfoPayload(settingId),
        0x65 => settingValuePayload(settingId, 0),
        _ => const <int>[],
      };
      _packetController.add(
        MidiPacket(
          ModuleSettingsCodec.packet(sysExId, command, payload),
          0,
          input,
        ),
      );
      return;
    }

    if (command == DistingNTRequestMessageType.sdCardOperation.value) {
      if (!respondToSd) return;
      final opCode = data[7];
      _packetController.add(
        MidiPacket(
          Uint8List.fromList([
            0xF0,
            0x00,
            0x21,
            0x27,
            0x6D,
            sysExId,
            DistingNTRespMessageType.respDirectoryListing.value,
            0,
            opCode,
            0xF7,
          ]),
          0,
          input,
        ),
      );
      return;
    }

    List<int>? responsePayload;
    DistingNTRespMessageType? responseType;
    if (command == DistingNTRequestMessageType.requestNumAlgorithms.value) {
      responseType = DistingNTRespMessageType.respNumAlgorithms;
      responsePayload = [0x00, 0x00, 0x00];
    } else if (command ==
        DistingNTRequestMessageType.requestNumAlgorithmsInPreset.value) {
      responseType = DistingNTRespMessageType.respNumAlgorithmsInPreset;
      responsePayload = [0x00, 12, 8, 8];
    } else if (command ==
        DistingNTRequestMessageType.requestVersionString.value) {
      responseType = DistingNTRespMessageType.respMessage;
      responsePayload = [...ascii.encode(firmwareVersion), 0];
    } else if (command == DistingNTRequestMessageType.requestPresetName.value) {
      responseType = DistingNTRespMessageType.respPresetName;
      responsePayload = [...ascii.encode(presetName), 0];
    } else if (command ==
        DistingNTRequestMessageType.requestUnitStrings.value) {
      responseType = DistingNTRespMessageType.respUnitStrings;
      responsePayload = [0x00];
    } else if (command ==
        DistingNTRequestMessageType.requestPerfPageItem.value) {
      responseType = DistingNTRespMessageType.respPerfPageItem;
      final itemIndex = data.length > 7 ? data[7] : 0;
      responsePayload = [itemIndex, 0];
    }

    if (responseType != null && responsePayload != null) {
      _packetController.add(
        MidiPacket(
          Uint8List.fromList([
            0xF0,
            0x00,
            0x21,
            0x27,
            0x6D,
            sysExId,
            responseType.value,
            ...responsePayload,
            0xF7,
          ]),
          0,
          input,
        ),
      );
    }
  }

  void simulateDevicesDisappeared(Set<String> ids) {
    final removed = availableDevices
        .where((device) => ids.contains(device.id))
        .toList();
    availableDevices = availableDevices
        .where((device) => !ids.contains(device.id))
        .toList();
    for (final device in removed) {
      final wasOpen = openDeviceIds.remove(device.id);
      device.connected = false;
      if (wasOpen) {
        _setupController.add(MidiSetupChange.deviceDisconnected);
      }
      _setupController.add(MidiSetupChange.deviceDisappeared);
    }
  }

  void simulateDevicesAppeared(List<MidiDevice> devices) {
    availableDevices = [...availableDevices, ...devices];
    for (final _ in devices) {
      _setupController.add(MidiSetupChange.deviceAppeared);
    }
  }

  void emitSetupChange(MidiSetupChange change) {
    _setupController.add(change);
  }

  @override
  void teardown() {
    teardownCalls++;
    openDeviceIds.clear();
  }

  @override
  void dispose() {
    disposeCalls++;
  }

  Future<void> closeControllers() async {
    await _setupController.close();
    await _packetController.close();
  }
}

MidiDevice _makeEndpoint(String id, String name, MidiPortType direction) {
  final device = MidiDevice(id, name, MidiDeviceType.serial, false);
  if (direction == MidiPortType.IN) {
    device.inputPorts.add(MidiPort(0, MidiPortType.IN));
  } else {
    device.outputPorts.add(MidiPort(0, MidiPortType.OUT));
  }
  return device;
}

MidiDevice _makeDuplexEndpoint(String id, String name) {
  final device = MidiDevice(id, name, MidiDeviceType.serial, false);
  device.inputPorts.add(MidiPort(0, MidiPortType.IN));
  device.outputPorts.add(MidiPort(0, MidiPortType.OUT));
  return device;
}

Future<void> _flushEventQueue() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppDatabase database;
  late _MockMetadataDao metadataDao;
  late _FakeMidiCommand midiCommand;
  late DistingCubit cubit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'inter_message_delay_ms': 0,
      'request_timeout_ms': 50,
    });
    await SettingsService().init();
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    midiCommand = _FakeMidiCommand();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(() => metadataDao.hasCachedAlgorithms())
        .thenAnswer((_) async => false);
    when(() => metadataDao.getAllUnits()).thenAnswer((_) async => []);
    when(() => metadataDao.getAllAlgorithms()).thenAnswer((_) async => []);
    when(
      () => metadataDao.getAlgorithmInfoCache(
        any(),
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => null);
    when(() => metadataDao.saveAlgorithmInfoCache(any(), any()))
        .thenAnswer((_) async {});

    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
    );
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await midiCommand.closeControllers();
  });

  test('MIDI loss and return with re-enumerated IDs and mutated names reconnects cleanly without replaying writes', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];
    midiCommand.mutateNameOnFirstPacket = true;

    await cubit.initialize();
    expect(cubit.state, isA<DistingStateSelectDevice>());

    await cubit.connectToDevices(input1, output1, 0);
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(
      (cubit.state as DistingStateSynchronized).presetName,
      'Before Disconnect',
    );
    expect(input1.name, 'disting NT disting NT');

    // Simulate USB/MIDI disconnect: endpoints vanish and OS closes handles.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    final waiting = cubit.state as DistingStateSelectDevice;
    expect(waiting.inputDevices, isEmpty);
    expect(waiting.outputDevices, isEmpty);
    expect(waiting.connectionStatus, contains('MIDI connection lost'));
    expect(waiting.connectionStatus, contains('disting NT'));
    expect(cubit.disting(), isNull);
    expect(midiCommand.disposeCalls, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 0);

    // Simulate USB/MIDI return with newly assigned OS endpoint IDs.
    midiCommand.sentPackets.clear();
    midiCommand.presetName = 'After Reconnect';
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final syncedAfterReturn = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    final synced = await syncedAfterReturn.timeout(
      const Duration(seconds: 2),
    ) as DistingStateSynchronized;

    expect(synced.presetName, 'After Reconnect');
    expect(synced.inputDevice?.id, 'nt-in-2');
    expect(synced.outputDevice?.id, 'nt-out-2');
    expect(midiCommand.disposeCalls, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);

    // Only normal connection traffic was sent; no preset/parameter/settings/SD writes.
    final sentCommands = midiCommand.sentPackets
        .where((p) => p.length > 6 && p[0] == 0xF0 && p[4] == 0x6D)
        .map((p) => p[6])
        .toList();
    expect(
      sentCommands,
      isNot(
        anyElement(
          isIn([
            DistingNTRequestMessageType.setParameterValue.value,
            DistingNTRequestMessageType.savePreset.value,
            DistingNTRequestMessageType.loadPreset.value,
            DistingNTRequestMessageType.setPresetName.value,
            DistingNTRequestMessageType.setSettingValue.value,
            DistingNTRequestMessageType.settingsAction.value,
            DistingNTRequestMessageType.sdCardOperation.value,
          ]),
        ),
      ),
    );

    // Fresh NT query after return succeeds.
    expect(await cubit.requireDisting().requestPresetName(), 'After Reconnect');
  }, tags: ['regression']);

  test('duplex endpoint fast disconnect on same ID falls back to fresh selection and communicates via normal reconnect', () async {
    final duplex1 = _makeDuplexEndpoint('nt-duplex', 'disting NT');
    midiCommand.availableDevices = [duplex1];

    await cubit.initialize();
    await cubit.connectToDevices(duplex1, duplex1, 0);
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls, ['nt-duplex']);

    // Simulate native handle closure where the same ID is still present in the
    // discovery snapshot: conservative normal flow avoids racing void
    // disconnectDevice's unawaited close on Linux/Darwin/Android.
    midiCommand.presetName = 'Same ID Bounce';
    midiCommand.openDeviceIds.remove('nt-duplex');
    final duplex2 = _makeDuplexEndpoint('nt-duplex', 'disting NT');
    midiCommand.availableDevices = [duplex2];
    duplex1.connected = false;
    await _flushEventQueue();

    final selectState = cubit.state as DistingStateSelectDevice;
    expect(selectState.selectedInputDevice, same(duplex2));
    expect(selectState.selectedOutputDevice, same(duplex2));
    expect(selectState.connectionStatus, contains('Select Connect'));
    expect(midiCommand.connectCalls, ['nt-duplex']);

    await cubit.connectToDevices(
      selectState.selectedInputDevice!,
      selectState.selectedOutputDevice!,
      selectState.selectedSysExId,
    );
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls, ['nt-duplex', 'nt-duplex']);
    expect(await cubit.requireDisting().requestPresetName(), 'Same ID Bounce');
  }, tags: ['regression']);

  test('in-flight query fails promptly on disconnect without hanging and fresh query succeeds after return', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    final oldManager = cubit.requireDisting();

    // Block replies and start an in-flight NT query.
    midiCommand.respondToQueries = false;
    final inFlight = oldManager.requestVersionString();
    final inFlightError = expectLater(inFlight, throwsA(isA<StateError>()));

    // Disconnect immediately fails the in-flight request.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await inFlightError;
    await _flushEventQueue();

    // Any late call against the disposed manager also fails immediately without sending.
    final sentBeforeLateCall = midiCommand.sentPackets.length;
    await expectLater(
      oldManager.requestVersionString(),
      throwsA(isA<StateError>()),
    );
    expect(midiCommand.sentPackets.length, sentBeforeLateCall);

    // Device returns and replies normally again.
    midiCommand.respondToQueries = true;
    midiCommand.presetName = 'Fresh Query OK';
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final syncedAfterReturn = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await syncedAfterReturn.timeout(const Duration(seconds: 2));

    expect(await cubit.requireDisting().requestPresetName(), 'Fresh Query OK');
  }, tags: ['regression']);

  test('failed reconnect attempt cleans up opened port without hanging and recovers on next return', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());

    // First return fails when opening the output port.
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.throwOnConnectDeviceId = output2.id;
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await _flushEventQueue();

    // Input that opened during the failed attempt was cleanly disconnected.
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(cubit.state, isA<DistingStateSelectDevice>());
    expect(
      (cubit.state as DistingStateSelectDevice).connectionStatus,
      contains('MIDI connection lost'),
    );
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 0);

    // Subsequent setup event succeeds cleanly without app restart.
    midiCommand.throwOnConnectDeviceId = null;
    midiCommand.presetName = 'Recovered After Failure';
    final syncedAfterRetry = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    await syncedAfterRetry.timeout(const Duration(seconds: 2));

    expect(
      await cubit.requireDisting().requestPresetName(),
      'Recovered After Failure',
    );
  }, tags: ['regression']);

  test('partial return, ambiguous return, and unrelated disconnects are handled safely', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final other = _makeEndpoint('other-in', 'MIDI Keyboard', MidiPortType.IN);
    midiCommand.availableDevices = [input1, output1, other];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    final originalManager = cubit.requireDisting();

    // Unrelated device disappears: healthy NT connection stays untouched.
    midiCommand.simulateDevicesDisappeared({other.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(identical(cubit.disting(), originalManager), isTrue);

    // Selected NT disappears.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());
    final connectsBeforePartial = midiCommand.connectCalls.length;

    // Partial return (only input): stays gracefully waiting without connecting.
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    midiCommand.simulateDevicesAppeared([input2]);
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());
    expect(midiCommand.connectCalls.length, connectsBeforePartial);

    // Ambiguous return (two identical NT inputs and one output): refuses to guess.
    final duplicateInput = _makeEndpoint(
      'nt-in-3',
      'disting NT',
      MidiPortType.IN,
    );
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.simulateDevicesAppeared([duplicateInput, output2]);
    await _flushEventQueue();
    final ambiguousState = cubit.state as DistingStateSelectDevice;
    expect(ambiguousState.connectionStatus, contains('Multiple'));
    expect(midiCommand.connectCalls.length, connectsBeforePartial);

    // Ambiguity clears -> exact single match reconnects cleanly.
    midiCommand.presetName = 'Unambiguous Return';
    final synced = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.simulateDevicesDisappeared({duplicateInput.id});
    await synced.timeout(const Duration(seconds: 2));
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Unambiguous Return',
    );
  }, tags: ['regression']);

  test('subscriptions do not duplicate across repeated disconnect/reconnect cycles', () async {
    final input0 = _makeEndpoint('nt-in-0', 'disting NT', MidiPortType.IN);
    final output0 = _makeEndpoint('nt-out-0', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input0, output0];

    await cubit.initialize();
    await cubit.connectToDevices(input0, output0, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);

    var currentInId = input0.id;
    var currentOutId = output0.id;
    for (var cycle = 1; cycle <= 3; cycle++) {
      midiCommand.simulateDevicesDisappeared({currentInId, currentOutId});
      await _flushEventQueue();
      expect(midiCommand.setupListenerCount, 1);
      expect(midiCommand.packetListenerCount, 0);

      currentInId = 'nt-in-$cycle';
      currentOutId = 'nt-out-$cycle';
      midiCommand.presetName = 'Cycle $cycle';
      final synced = cubit.stream.firstWhere(
        (state) =>
            state is DistingStateSynchronized &&
            state.presetName == 'Cycle $cycle',
      );
      midiCommand.simulateDevicesAppeared([
        _makeEndpoint(currentInId, 'disting NT', MidiPortType.IN),
        _makeEndpoint(currentOutId, 'disting NT', MidiPortType.OUT),
      ]);
      await synced.timeout(const Duration(seconds: 2));
      expect(midiCommand.setupListenerCount, 1);
      expect(midiCommand.packetListenerCount, 1);
    }

    expect(midiCommand.disposeCalls, 0);
    expect(await cubit.requireDisting().requestPresetName(), 'Cycle 3');
  }, tags: ['regression']);

  test('reconnects do not overlap under burst setup events', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    midiCommand.connectCalls.clear();

    // Hold the port open on a Completer and fire a burst of setup notifications.
    final gate = Completer<void>();
    midiCommand.pendingConnect = gate;
    midiCommand.presetName = 'Single Reconnect';
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await _flushEventQueue();

    // Fire extra burst events while the first reconnect is still opening input2.
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    expect(midiCommand.connectCalls, ['nt-in-2']);

    final synced = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.pendingConnect = null;
    gate.complete();
    await synced.timeout(const Duration(seconds: 2));

    expect(midiCommand.connectCalls, ['nt-in-2', 'nt-out-2']);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Single Reconnect',
    );
  }, tags: ['regression']);

  test('strict SD card attribution and NT Settings guards remain enforced across disconnect/reconnect', () async {
    final input1 = _makeEndpoint('nt-in-same', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint(
      'nt-out-same',
      'disting NT',
      MidiPortType.OUT,
    );
    midiCommand.firmwareVersion = '1.20.0';
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    expect(cubit.state, isA<DistingStateSynchronized>());

    // Load NT Settings and stage a local draft (not applied).
    await cubit.loadModuleSettings();
    expect(cubit.moduleSettingsState.ready, isTrue);
    final connectionIdBefore = cubit.moduleSettingsState.connectionId;
    cubit.editModuleSetting(5, const ModuleSettingValue(1));
    expect(cubit.moduleSettingsState.settings[5]?.changed, isTrue);

    // Leave unacknowledged SD response debt right as MIDI disconnects.
    midiCommand.respondToSd = false;
    final sdListing = cubit.requireDisting().requestDirectoryListing('/');
    final sdFailed = expectLater(sdListing, throwsA(isA<StateError>()));
    await _flushEventQueue();

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await sdFailed;
    await _flushEventQueue();

    // Module settings must immediately become unavailable when disconnected.
    expect(cubit.moduleSettingsState.unavailableReason, isNotNull);

    // Reconnect on the same endpoint ID.
    midiCommand.respondToSd = true;
    midiCommand.presetName = 'Guards Preserved';
    final input2 = _makeEndpoint('nt-in-same', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint(
      'nt-out-same',
      'disting NT',
      MidiPortType.OUT,
    );
    final synced = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await synced.timeout(const Duration(seconds: 2));

    // Ordinary NT query succeeds immediately.
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Guards Preserved',
    );

    // Strict SD response debt is preserved across reconnect (fail-closed, never bypassed).
    await expectLater(
      cubit.requireDisting().requestDirectoryListing('/'),
      throwsA(isA<AmbiguousResponseAttributionException>()),
    );

    // NT Settings scope is connection-scoped: old draft is cleared and fresh discovery is required.
    expect(
      cubit.moduleSettingsState.connectionId,
      greaterThan(connectionIdBefore),
    );
    expect(cubit.moduleSettingsState.tree, isNull);
    expect(cubit.moduleSettingsState.settings, isEmpty);
    await expectLater(
      (cubit.requireDisting() as ModuleSettingsTransport).writeModuleSetting(
        5,
        const ModuleSettingValue(1),
        DistingRequestCancellation(),
      ),
      throwsStateError,
    );
  }, tags: ['regression']);

  test('explicit manual selection, offline mode, and disposal cancel reconnect and clean up all listeners', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final otherIn = _makeEndpoint('other-in', 'Forever', MidiPortType.IN);
    midiCommand.availableDevices = [input1, output1, otherIn];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    // Disconnect -> waiting for disting NT.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(
      (cubit.state as DistingStateSelectDevice).connectionStatus,
      isNotNull,
    );

    // User manually selects another device -> clears pending auto-reconnect.
    cubit.updateDeviceSelection(
      inputDevice: otherIn,
      outputDevice: null,
      sysExId: 0,
    );
    expect((cubit.state as DistingStateSelectDevice).connectionStatus, isNull);

    final connectsBeforeReturn = midiCommand.connectCalls.length;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());
    expect(midiCommand.connectCalls.length, connectsBeforeReturn);

    // Reconnect manually, then dispose cubit mid-connect / active session.
    final gate = Completer<void>();
    midiCommand.pendingConnect = gate;
    final input2 = midiCommand.availableDevices.firstWhere(
      (d) => d.id == 'nt-in-2',
    );
    final output2 = midiCommand.availableDevices.firstWhere(
      (d) => d.id == 'nt-out-2',
    );
    final pendingConnectCall = cubit.connectToDevices(input2, output2, 0);
    await _flushEventQueue();

    await cubit.close();
    expect(midiCommand.setupListenerCount, 0);
    expect(midiCommand.packetListenerCount, 0);

    // Completing the late connect future after close releases the port cleanly without throwing.
    midiCommand.pendingConnect = null;
    gate.complete();
    await pendingConnectCall;
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.setupListenerCount, 0);
    expect(midiCommand.packetListenerCount, 0);

    // Late setup events after close are safely ignored.
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();
  }, tags: ['regression']);

  test('goOffline while auto-reconnect open is gated preserves offline mode and sends no stale traffic', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());

    final inputOpenGate = Completer<void>();
    midiCommand.connectCalls.clear();
    midiCommand.pendingConnectByDeviceId['nt-in-2'] = inputOpenGate;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, ['nt-in-2']);

    // Go offline while auto-reconnect is gated on input open.
    midiCommand.sentPackets.clear();
    await cubit.goOffline();
    final offlineState = cubit.state as DistingStateSynchronized;
    expect(offlineState.offline, isTrue);
    final offlineManager = cubit.disting();
    expect(offlineManager, isNotNull);

    // Release the stale open gate: offline mode must stay intact with zero stale traffic.
    inputOpenGate.complete();
    await _flushEventQueue();

    final finalState = cubit.state as DistingStateSynchronized;
    expect(finalState.offline, isTrue);
    expect(identical(cubit.disting(), offlineManager), isTrue);
    expect(midiCommand.connectCalls, ['nt-in-2']);
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.sentPackets, isEmpty);
    expect(midiCommand.setupListenerCount, 0);
    expect(midiCommand.packetListenerCount, 0);
  }, tags: ['regression']);

  test('onDemo while auto-reconnect open is gated preserves demo mode and cleans up stale ports', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    // Gate on output open so input is already opened when demo mode is entered.
    final outputOpenGate = Completer<void>();
    midiCommand.connectCalls.clear();
    midiCommand.pendingConnectByDeviceId['nt-out-2'] = outputOpenGate;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, ['nt-in-2', 'nt-out-2']);
    expect(midiCommand.openDeviceIds, {'nt-in-2'});

    // Enter demo mode while output open is suspended.
    midiCommand.sentPackets.clear();
    await cubit.onDemo();
    final demoState = cubit.state as DistingStateSynchronized;
    expect(demoState.demo, isTrue);
    final demoManager = cubit.disting();

    // Release gate: demo mode stays active, both stale ports closed, no MIDI traffic.
    outputOpenGate.complete();
    await _flushEventQueue();

    final finalState = cubit.state as DistingStateSynchronized;
    expect(finalState.demo, isTrue);
    expect(identical(cubit.disting(), demoManager), isTrue);
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.sentPackets, isEmpty);
    expect(midiCommand.setupListenerCount, 0);
    expect(midiCommand.packetListenerCount, 0);
  }, tags: ['regression']);

  test('failing stale auto-reconnect after goOffline does not overwrite offline mode', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    final outputOpenGate = Completer<void>();
    midiCommand.pendingConnectByDeviceId['nt-out-2'] = outputOpenGate;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(midiCommand.openDeviceIds, {'nt-in-2'});

    await cubit.goOffline();
    final offlineManager = cubit.disting();
    midiCommand.sentPackets.clear();

    // Stale open fails after offline mode was chosen: must only close its own
    // opened input port and leave offline mode untouched.
    outputOpenGate.completeError(StateError('Late port failure'));
    await _flushEventQueue();

    final finalState = cubit.state as DistingStateSynchronized;
    expect(finalState.offline, isTrue);
    expect(identical(cubit.disting(), offlineManager), isTrue);
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.sentPackets, isEmpty);
    expect(midiCommand.setupListenerCount, 0);
  }, tags: ['regression']);

  test('updateDeviceSelection while auto-reconnect open is gated preserves chosen selection and protects replacement connection', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final otherIn = _makeEndpoint('other-in', 'Other Synth', MidiPortType.IN);
    final otherOut = _makeEndpoint(
      'other-out',
      'Other Synth',
      MidiPortType.OUT,
    );
    midiCommand.availableDevices = [input1, output1, otherIn, otherOut];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    final inputOpenGate = Completer<void>();
    midiCommand.connectCalls.clear();
    midiCommand.pendingConnectByDeviceId['nt-in-2'] = inputOpenGate;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, ['nt-in-2']);

    // User changes selection while auto-reconnect is gated on input open.
    midiCommand.sentPackets.clear();
    cubit.updateDeviceSelection(
      inputDevice: otherIn,
      outputDevice: otherOut,
      sysExId: 3,
    );

    // Release stale auto-open gate: selection must remain untouched, no stale sends.
    inputOpenGate.complete();
    await _flushEventQueue();

    final selectionState = cubit.state as DistingStateSelectDevice;
    expect(selectionState.selectedInputDevice?.id, 'other-in');
    expect(selectionState.selectedOutputDevice?.id, 'other-out');
    expect(selectionState.selectedSysExId, 3);
    expect(selectionState.connectionStatus, isNull);
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.sentPackets, isEmpty);

    // Also verify that if user starts a replacement connection on the SAME
    // endpoints while a stale open is still gated, releasing the stale open
    // never closes or disposes the replacement connection.
    final ntIn2 = midiCommand.availableDevices.firstWhere(
      (d) => d.id == 'nt-in-2',
    );
    final ntOut2 = midiCommand.availableDevices.firstWhere(
      (d) => d.id == 'nt-out-2',
    );
    final staleGate = Completer<void>();
    midiCommand.pendingConnectQueue.add(staleGate);
    final staleAttempt = cubit.connectToDevices(ntIn2, ntOut2, 0);
    await _flushEventQueue();

    cubit.updateDeviceSelection(
      inputDevice: ntIn2,
      outputDevice: ntOut2,
      sysExId: 2,
    );
    midiCommand.presetName = 'Replacement Owner';
    await cubit.connectToDevices(ntIn2, ntOut2, 2);
    final replacementManager = cubit.requireDisting();
    expect(cubit.state, isA<DistingStateSynchronized>());

    staleGate.complete();
    await staleAttempt;
    await _flushEventQueue();

    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(identical(cubit.disting(), replacementManager), isTrue);
    expect(midiCommand.openDeviceIds, containsAll(['nt-in-2', 'nt-out-2']));
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Replacement Owner',
    );
  }, tags: ['regression']);

  test('failed reconnect keeps opening ownership through cleanup, drains queued retry, and prevents overlapping third open', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    // First return fails on input2 (so no self-disconnect occurs), then gates
    // inside catch cleanup's devices lookup after _pendingReconnectTarget is set.
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final cleanupGate = Completer<void>();
    final cleanupEntered = Completer<void>();
    midiCommand.throwOnConnectDeviceId = input2.id;
    var devicesCallsAfterReturn = 0;
    midiCommand.onDevicesRequested = () {
      devicesCallsAfterReturn++;
      // Call 1 is _checkPendingReconnect; call 2 is catch cleanup.
      if (devicesCallsAfterReturn == 2) {
        midiCommand.pendingDevicesGate = cleanupGate;
        if (!cleanupEntered.isCompleted) {
          cleanupEntered.complete();
        }
      }
    };

    midiCommand.connectCalls.clear();
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await cleanupEntered.future.timeout(const Duration(seconds: 2));
    await _flushEventQueue();
    expect(midiCommand.openDeviceIds, isEmpty);

    // Arm a gate on the retry's input open and clear the failure fault.
    midiCommand.onDevicesRequested = null;
    midiCommand.throwOnConnectDeviceId = null;
    midiCommand.connectCalls.clear();
    final retryGate = Completer<void>();
    midiCommand.pendingConnectByDeviceId[input2.id] = retryGate;
    midiCommand.presetName = 'Single Retry Owner';

    // Deliver a setup event while attempt #1 is still suspended in cleanup.
    // Because attempt #1 still owns the opening lock through cleanup, no
    // retry may start until cleanup releases ownership.
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, isEmpty);

    // Release attempt #1 cleanup -> queued notification triggers retry attempt #2,
    // which suspends on retryGate.
    cleanupGate.complete();
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id]);

    // Deliver another setup event while retry attempt #2 is still gated:
    // must NOT start an overlapping third open.
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id]);

    // Release retryGate -> attempt #2 finishes cleanly.
    final synced = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    retryGate.complete();
    await synced.timeout(const Duration(seconds: 2));

    expect(midiCommand.connectCalls, [input2.id, output2.id]);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Single Retry Owner',
    );
  }, tags: ['regression']);

  test('Linux async-close contract: surviving counterpart during rapid bounce does not reopen stale snapshot object before native close completes', () async {
    midiCommand.simulateLinuxAsyncClose = true;
    final input1 = _makeEndpoint('aseq:20:0', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('aseq:20:1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    final initialState = cubit.state as DistingStateSelectDevice;
    await cubit.connectToDevices(
      initialState.inputDevices.single,
      initialState.outputDevices.single,
      0,
    );
    final connectedOutput =
        (cubit.state as DistingStateSynchronized).outputDevice!;
    expect(cubit.state, isA<DistingStateSynchronized>());

    // Hold the Linux async close of the surviving output endpoint on a gate.
    final outputCloseGate = Completer<void>();
    midiCommand.pendingAsyncDisconnectById[output1.id] = outputCloseGate;
    midiCommand.connectCalls.clear();
    midiCommand.presetName = 'Fresh After Async Close';

    // Input bounces rapidly to a new ID while output stays in the Linux
    // connected map (so pre-teardown devices() returns connectedOutput).
    midiCommand.connectedLinuxDevices.remove(input1.id);
    midiCommand.alsaConnectedEndpoints.remove(input1.id);
    midiCommand.openDeviceIds.remove(input1.id);
    final input2 = _makeEndpoint('aseq:21:0', 'disting NT', MidiPortType.IN);
    midiCommand.availableDevices = [input2, output1];
    midiCommand.emitSetupChange(MidiSetupChange.deviceDisappeared);
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    // Must NOT immediately auto-reopen against the unawaited Linux close,
    // and must present fresh post-teardown device objects for normal Connect.
    expect(midiCommand.connectCalls, isEmpty);
    final selectState = cubit.state as DistingStateSelectDevice;
    expect(selectState.selectedInputDevice?.id, input2.id);
    expect(selectState.selectedOutputDevice?.id, output1.id);
    expect(
      identical(selectState.selectedOutputDevice, connectedOutput),
      isFalse,
    );

    // Complete the native async close, then reconnect via normal flow.
    outputCloseGate.complete();
    await _flushEventQueue();

    await cubit.connectToDevices(
      selectState.selectedInputDevice!,
      selectState.selectedOutputDevice!,
      selectState.selectedSysExId,
    );
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Fresh After Async Close',
    );
  }, tags: ['regression']);

  test('Linux async-close contract: surviving counterpart with delayed input return avoids racing unawaited close and reconnects via normal flow', () async {
    midiCommand.simulateLinuxAsyncClose = true;
    final input1 = _makeEndpoint('aseq:20:0', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('aseq:20:1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    final initialState = cubit.state as DistingStateSelectDevice;
    await cubit.connectToDevices(
      initialState.inputDevices.single,
      initialState.outputDevices.single,
      0,
    );
    final connectedOutput =
        (cubit.state as DistingStateSynchronized).outputDevice!;

    final outputCloseGate = Completer<void>();
    midiCommand.pendingAsyncDisconnectById[output1.id] = outputCloseGate;
    midiCommand.connectCalls.clear();
    midiCommand.presetName = 'Delayed Return After Async Close';

    // Input disappears first while output survives.
    midiCommand.connectedLinuxDevices.remove(input1.id);
    midiCommand.alsaConnectedEndpoints.remove(input1.id);
    midiCommand.openDeviceIds.remove(input1.id);
    midiCommand.availableDevices = [output1];
    midiCommand.emitSetupChange(MidiSetupChange.deviceDisappeared);
    await _flushEventQueue();

    final waitingState = cubit.state as DistingStateSelectDevice;
    expect(waitingState.selectedInputDevice, isNull);
    expect(waitingState.selectedOutputDevice?.id, output1.id);
    expect(
      identical(waitingState.selectedOutputDevice, connectedOutput),
      isFalse,
    );

    // Input returns while output's unawaited Linux close is STILL in flight.
    final input2 = _makeEndpoint('aseq:21:0', 'disting NT', MidiPortType.IN);
    midiCommand.availableDevices = [input2, output1];
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    // Must NOT race an automatic open against the unawaited close.
    expect(midiCommand.connectCalls, isEmpty);
    final readyState = cubit.state as DistingStateSelectDevice;
    expect(readyState.selectedInputDevice?.id, input2.id);
    expect(readyState.selectedOutputDevice?.id, output1.id);

    // Once native async close completes, normal Connect succeeds cleanly.
    outputCloseGate.complete();
    await _flushEventQueue();

    await cubit.connectToDevices(
      readyState.selectedInputDevice!,
      readyState.selectedOutputDevice!,
      readyState.selectedSysExId,
    );
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Delayed Return After Async Close',
    );
  }, tags: ['regression']);

  test('disconnect during in-flight sync aborts sync promptly and recovers on return', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();

    // Stall sync right after version string so performSyncAndEmit stays in-flight.
    final presetNameSent = Completer<void>();
    midiCommand.onPacketSent = (packet) {
      if (packet.length > 6 &&
          packet[6] == DistingNTRequestMessageType.requestPresetName.value) {
        midiCommand.respondToQueries = false;
        if (!presetNameSent.isCompleted) {
          presetNameSent.complete();
        }
      }
    };

    final connectFuture = cubit.connectToDevices(input1, output1, 0);
    await presetNameSent.future.timeout(const Duration(seconds: 2));
    expect(cubit.state, isA<DistingStateConnected>());

    // Disconnect mid-sync: sync exits promptly without hanging.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await connectFuture.timeout(const Duration(seconds: 2));
    await _flushEventQueue();

    expect(cubit.state, isA<DistingStateSelectDevice>());
    expect(
      (cubit.state as DistingStateSelectDevice).connectionStatus,
      contains('MIDI connection lost'),
    );

    // Device returns and completes full sync cleanly.
    midiCommand.onPacketSent = null;
    midiCommand.respondToQueries = true;
    midiCommand.presetName = 'Synced After Mid-Sync Drop';
    final synced = cubit.stream.firstWhere(
      (state) => state is DistingStateSynchronized,
    );
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await synced.timeout(const Duration(seconds: 2));

    expect(
      await cubit.requireDisting().requestPresetName(),
      'Synced After Mid-Sync Drop',
    );
  }, tags: ['regression']);

  testWidgets(
    'device selection status banner preserves control geometry and exposes a live region',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final mockCubit = _MockDistingCubit();
      final states = StreamController<DistingState>.broadcast();
      addTearDown(states.close);

      const baseState = DistingStateSelectDevice(
        inputDevices: [],
        outputDevices: [],
        canWorkOffline: false,
      );
      whenListen(mockCubit, states.stream, initialState: baseState);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: BlocProvider<DistingCubit>.value(
              value: mockCubit,
              child: const DistingPage(),
            ),
          ),
        );
        await tester.pump();

        final inputDropdown = find.byKey(
          const ValueKey('input-midi-device-dropdown'),
        );
        final connectButton = find.widgetWithText(FilledButton, 'Connect');
        final initialInputRect = tester.getRect(inputDropdown);
        final initialConnectRect = tester.getRect(connectButton);

        const statusText =
            'MIDI connection lost. Waiting for disting NT to reconnect.';
        states.add(baseState.copyWith(connectionStatus: statusText));
        await tester.pump();
        await tester.pump();

        expect(find.text(statusText), findsOneWidget);
        expect(tester.getRect(inputDropdown), initialInputRect);
        expect(tester.getRect(connectButton), initialConnectRect);

        final semanticsNode = tester.getSemantics(find.text(statusText));
        expect(semanticsNode.label, contains(statusText));

        states.add(baseState.copyWith(connectionStatus: null));
        await tester.pump();
        await tester.pump();

        expect(find.text(statusText), findsNothing);
        expect(tester.getRect(inputDropdown), initialInputRect);
        expect(tester.getRect(connectButton), initialConnectRect);
      } finally {
        semantics.dispose();
      }
    },
    tags: ['regression'],
  );
}
