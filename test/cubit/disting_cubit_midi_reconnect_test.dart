import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
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
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/app_update_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/algorithm_list_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/module_settings_fixtures.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockAppUpdateService extends Mock implements AppUpdateService {}

_MockAppUpdateService _createNoOpAppUpdateService() {
  final service = _MockAppUpdateService();
  when(() => service.isSupported).thenReturn(false);
  when(
    () => service.checkForUpdate(
      forceRefresh: any(named: 'forceRefresh'),
      skipVersionCheck: any(named: 'skipVersionCheck'),
    ),
  ).thenAnswer((_) async => null);
  return service;
}

class _FakeMidiCommand extends Fake implements MidiCommand {
  _FakeMidiCommand() {
    // Production backends (Darwin, Linux, Windows, Android) deliver setup
    // events asynchronously on broadcast streams rather than synchronously.
    _setupController = StreamController<MidiSetupChange>.broadcast(
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
      // Mirrors FlutterMidiCommandLinux.disconnectDevice (lines 177-190) and
      // LinuxMidiDevice.disconnect (lines 84-90): removes map entry and emits
      // deviceDisconnected + connected=false, then awaits rx sub cancellation
      // before running AlsaSeqLinuxDevice.disconnect.
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
      if (simulateLinuxAsyncClose) {
        connectedLinuxDevices.remove(device.id);
        alsaConnectedEndpoints.remove(device.id);
      }
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

Slot _makeSlot(int index, String guid, String name, {int value = 10}) => Slot(
  algorithm: Algorithm(algorithmIndex: index, guid: guid, name: name),
  routing: RoutingInfo.filler(),
  pages: ParameterPages(
    algorithmIndex: index,
    pages: [
      ParameterPage(name: 'Main', parameters: const [0]),
    ],
  ),
  parameters: [
    ParameterInfo(
      algorithmIndex: index,
      parameterNumber: 0,
      min: 0,
      max: 1000,
      defaultValue: 0,
      unit: 0,
      name: 'Level',
      powerOfTen: 0,
    ),
  ],
  values: [
    ParameterValue(algorithmIndex: index, parameterNumber: 0, value: value),
  ],
  enums: [ParameterEnumStrings.filler()],
  mappings: [Mapping.filler()],
  valueStrings: [ParameterValueString.filler()],
);

Future<void> _flushEventQueue() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  Key dropdownKey,
  String label,
) async {
  final dropdown = find.byKey(dropdownKey);
  await tester.tapAt(tester.getTopLeft(dropdown) + const Offset(20, 20));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label).hitTestable());
  await tester.pumpAndSettle();
}

Future<T> _awaitWhilePumping<T>(
  WidgetTester tester,
  Future<T> future, {
  int maxPumps = 100,
  Duration step = const Duration(milliseconds: 10),
}) async {
  var done = false;
  late T result;
  Object? error;
  StackTrace? stackTrace;
  unawaited(
    future.then(
      (value) {
        result = value;
        done = true;
      },
      onError: (Object e, StackTrace st) {
        error = e;
        stackTrace = st;
        done = true;
      },
    ),
  );
  for (var i = 0; i < maxPumps && !done; i++) {
    await tester.pump(step);
  }
  if (!done) {
    fail('Future did not complete after $maxPumps pumps');
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  return result;
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
    when(() => metadataDao.getOrderedUnitStrings()).thenAnswer((_) async => []);
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
      isLinuxOverride: false,
    );
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await midiCommand.closeControllers();
  });

  test('transient MIDI loss and return with re-enumerated IDs and mutated names stays silently synchronized without replaying writes', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];
    midiCommand.mutateNameOnFirstPacket = true;

    await cubit.initialize();
    expect(cubit.state, isA<DistingStateSelectDevice>());

    await cubit.connectToDevices(input1, output1, 0);
    expect(cubit.state, isA<DistingStateSynchronized>());
    final connectedSync = cubit.state as DistingStateSynchronized;
    cubit.emit(
      connectedSync.copyWith(slots: [_makeSlot(0, 'G1', 'Alpha', value: 10)]),
    );
    final oldManager = cubit.requireDisting();
    expect(input1.name, 'disting NT disting NT');

    final emittedStates = <DistingState>[];
    final sub = cubit.stream.listen(emittedStates.add);
    addTearDown(sub.cancel);

    // Simulate USB/MIDI disconnect: endpoints vanish and OS closes handles.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    // Must remain silently in DistingStateSynchronized without leaving the editor.
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(
      emittedStates.where(
        (s) => s is DistingStateSelectDevice || s is DistingStateConnected,
      ),
      isEmpty,
    );
    expect(midiCommand.disposeCalls, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 0);

    // Edits while disconnected keep local optimistic state but send/queue no MIDI writes.
    midiCommand.sentPackets.clear();
    await cubit.updateParameterValue(
      algorithmIndex: 0,
      parameterNumber: 0,
      value: 42,
      userIsChangingTheValue: false,
    );
    expect(
      (cubit.state as DistingStateSynchronized).slots.first.values.first.value,
      42,
    );
    expect(midiCommand.sentPackets, isEmpty);

    // Simulate USB/MIDI return with newly assigned OS endpoint IDs.
    midiCommand.presetName = 'After Reconnect';
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    final synced = await reconnected.timeout(
      const Duration(seconds: 2),
    ) as DistingStateSynchronized;

    // Never bounced through SelectDevice or Connected; editor state preserved.
    expect(
      emittedStates.where(
        (s) => s is DistingStateSelectDevice || s is DistingStateConnected,
      ),
      isEmpty,
    );
    expect(synced.presetName, 'Before Disconnect');
    expect(synced.slots.first.values.first.value, 42);
    expect(synced.inputDevice?.id, 'nt-in-2');
    expect(synced.outputDevice?.id, 'nt-out-2');
    expect(midiCommand.disposeCalls, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);

    // Zero stale writes or unsolicited commands sent on silent reconnect.
    expect(midiCommand.sentPackets, isEmpty);

    // Fresh NT query after return succeeds immediately without manual Connect.
    expect(await cubit.requireDisting().requestPresetName(), 'After Reconnect');
  }, tags: ['regression']);

  test('duplex endpoint same-ID bounce silently reopens fresh snapshot object and resumes queries automatically', () async {
    final duplex1 = _makeDuplexEndpoint('nt-duplex', 'disting NT');
    midiCommand.availableDevices = [duplex1];

    await cubit.initialize();
    await cubit.connectToDevices(duplex1, duplex1, 0);
    expect(cubit.state, isA<DistingStateSynchronized>());
    final oldManager = cubit.requireDisting();
    expect(midiCommand.connectCalls, ['nt-duplex']);

    final emittedStates = <DistingState>[];
    final sub = cubit.stream.listen(emittedStates.add);
    addTearDown(sub.cancel);

    midiCommand.presetName = 'Same ID Bounce';
    midiCommand.openDeviceIds.remove('nt-duplex');
    final duplex2 = _makeDuplexEndpoint('nt-duplex', 'disting NT');
    midiCommand.availableDevices = [duplex2];
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    duplex1.connected = false;
    final synced = await reconnected.timeout(
      const Duration(seconds: 2),
    ) as DistingStateSynchronized;

    expect(
      emittedStates.where(
        (s) => s is DistingStateSelectDevice || s is DistingStateConnected,
      ),
      isEmpty,
    );
    expect(synced.inputDevice, same(duplex2));
    expect(synced.outputDevice, same(duplex2));
    expect(midiCommand.connectCalls, ['nt-duplex', 'nt-duplex']);
    expect(await cubit.requireDisting().requestPresetName(), 'Same ID Bounce');
  }, tags: ['regression']);

  test('in-flight query fails promptly on disconnect without hanging and fresh query succeeds after silent return', () async {
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

    // Disconnect immediately fails the in-flight request while staying synchronized.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await inFlightError;
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    // Any late call against the disposed manager also fails immediately without sending.
    final sentBeforeLateCall = midiCommand.sentPackets.length;
    await expectLater(
      oldManager.requestVersionString(),
      throwsA(isA<StateError>()),
    );
    expect(midiCommand.sentPackets.length, sentBeforeLateCall);

    // Device returns and replies normally again without manual Connect.
    midiCommand.respondToQueries = true;
    midiCommand.presetName = 'Fresh Query OK';
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await reconnected.timeout(const Duration(seconds: 2));

    expect(await cubit.requireDisting().requestPresetName(), 'Fresh Query OK');
  }, tags: ['regression']);

  test('failed silent reconnect cleans up opened port without retry loop on async setup stream and recovers on next setup event', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    final oldManager = cubit.requireDisting();

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    // First return fails when opening the output port after input opened.
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.connectCalls.clear();
    midiCommand.throwOnConnectDeviceId = output2.id;
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await _flushEventQueue();

    // Input that opened during the failed attempt was cleanly disconnected,
    // and its async deviceDisconnected echo did not trigger a retry loop.
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.connectCalls, [input2.id, output2.id]);
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(identical(cubit.disting(), oldManager), isTrue);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 0);

    // Subsequent setup event succeeds cleanly without app restart.
    midiCommand.throwOnConnectDeviceId = null;
    midiCommand.presetName = 'Recovered After Failure';
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    await reconnected.timeout(const Duration(seconds: 2));

    expect(
      await cubit.requireDisting().requestPresetName(),
      'Recovered After Failure',
    );
  }, tags: ['regression']);

  test('partial return, ambiguous return, and unrelated disconnects are handled silently and safely', () async {
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

    // Selected NT disappears: stays silently in Synchronized.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());
    final connectsBeforePartial = midiCommand.connectCalls.length;

    // Partial return (only input): stays silently waiting without connecting.
    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    midiCommand.simulateDevicesAppeared([input2]);
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());
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
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls.length, connectsBeforePartial);

    // Ambiguity clears -> exact single match reconnects silently.
    midiCommand.presetName = 'Unambiguous Return';
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, originalManager),
    );
    midiCommand.simulateDevicesDisappeared({duplicateInput.id});
    await reconnected.timeout(const Duration(seconds: 2));
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Unambiguous Return',
    );
  }, tags: ['regression']);

  test('subscriptions do not duplicate across repeated silent disconnect/reconnect cycles', () async {
    final input0 = _makeEndpoint('nt-in-0', 'disting NT', MidiPortType.IN);
    final output0 = _makeEndpoint('nt-out-0', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input0, output0];

    await cubit.initialize();
    await cubit.connectToDevices(input0, output0, 0);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);

    final emittedStates = <DistingState>[];
    final sub = cubit.stream.listen(emittedStates.add);
    addTearDown(sub.cancel);

    var currentInId = input0.id;
    var currentOutId = output0.id;
    for (var cycle = 1; cycle <= 3; cycle++) {
      final previousManager = cubit.requireDisting();
      midiCommand.simulateDevicesDisappeared({currentInId, currentOutId});
      await _flushEventQueue();
      expect(midiCommand.setupListenerCount, 1);
      expect(midiCommand.packetListenerCount, 0);

      currentInId = 'nt-in-$cycle';
      currentOutId = 'nt-out-$cycle';
      midiCommand.presetName = 'Cycle $cycle';
      final reconnected = cubit.stream.firstWhere(
        (state) =>
            state is DistingStateSynchronized &&
            !identical(state.disting, previousManager),
      );
      midiCommand.simulateDevicesAppeared([
        _makeEndpoint(currentInId, 'disting NT', MidiPortType.IN),
        _makeEndpoint(currentOutId, 'disting NT', MidiPortType.OUT),
      ]);
      await reconnected.timeout(const Duration(seconds: 2));
      expect(midiCommand.setupListenerCount, 1);
      expect(midiCommand.packetListenerCount, 1);
    }

    expect(
      emittedStates.where(
        (s) => s is DistingStateSelectDevice || s is DistingStateConnected,
      ),
      isEmpty,
    );
    expect(midiCommand.disposeCalls, 0);
    expect(await cubit.requireDisting().requestPresetName(), 'Cycle 3');
  }, tags: ['regression']);

  test('silent reconnects do not overlap under burst setup events', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    final oldManager = cubit.requireDisting();

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

    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.pendingConnect = null;
    gate.complete();
    await reconnected.timeout(const Duration(seconds: 2));

    expect(midiCommand.connectCalls, ['nt-in-2', 'nt-out-2']);
    expect(midiCommand.setupListenerCount, 1);
    expect(midiCommand.packetListenerCount, 1);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Single Reconnect',
    );
  }, tags: ['regression']);

  test('strict SD card attribution, NT Settings guards, and pending mapping write discard remain enforced across silent disconnect/reconnect', () async {
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
    final oldManager = cubit.requireDisting();
    cubit.emit(
      (cubit.state as DistingStateSynchronized).copyWith(
        slots: [_makeSlot(0, 'G1', 'Alpha', value: 10)],
      ),
    );

    // Load NT Settings and stage a local draft (not applied).
    await cubit.loadModuleSettings();
    expect(cubit.moduleSettingsState.ready, isTrue);
    final connectionIdBefore = cubit.moduleSettingsState.connectionId;
    cubit.editModuleSetting(5, const ModuleSettingValue(1));
    expect(cubit.moduleSettingsState.settings[5]?.changed, isTrue);

    // Queue a debounced mapping save just before disconnect.
    final pendingMapping = cubit.saveMapping(
      0,
      0,
      PackedMappingData.filler().copyWith(version: 6, cvInput: 2),
    );
    final pendingMappingFailed = expectLater(
      pendingMapping,
      throwsA(isA<StateError>()),
    );

    // Leave unacknowledged SD response debt right as MIDI disconnects.
    midiCommand.respondToSd = false;
    final sdListing = cubit.requireDisting().requestDirectoryListing('/');
    final sdFailed = expectLater(sdListing, throwsA(isA<StateError>()));
    await _flushEventQueue();

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await sdFailed;
    await pendingMappingFailed;
    await _flushEventQueue();

    // Still silently in Synchronized, yet Module Settings is immediately unavailable.
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(cubit.moduleSettingsState.unavailableReason, isNotNull);

    // Reconnect on the same endpoint ID.
    midiCommand.sentPackets.clear();
    midiCommand.respondToSd = true;
    midiCommand.presetName = 'Guards Preserved';
    final input2 = _makeEndpoint('nt-in-same', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint(
      'nt-out-same',
      'disting NT',
      MidiPortType.OUT,
    );
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await reconnected.timeout(const Duration(seconds: 2));

    // Discarded mapping write was NOT replayed after return.
    expect(midiCommand.sentPackets, isEmpty);

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

  test('explicit permanent disconnect, manual selection, and disposal cancel silent reconnect and clean up all listeners', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final otherIn = _makeEndpoint('other-in', 'Forever', MidiPortType.IN);
    midiCommand.availableDevices = [input1, output1, otherIn];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    // Transient disconnect -> silently waiting in Synchronized.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    // User explicitly disconnects to device selection and picks another device.
    cubit.disconnect();
    await cubit.loadDevices();
    expect(cubit.state, isA<DistingStateSelectDevice>());
    cubit.updateDeviceSelection(
      inputDevice: otherIn,
      outputDevice: null,
      sysExId: 0,
    );

    final connectsBeforeReturn = midiCommand.connectCalls.length;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSelectDevice>());
    expect(midiCommand.connectCalls.length, connectsBeforeReturn);

    // Reconnect manually, then dispose cubit mid-connect.
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

  test('goOffline while silent auto-reconnect open is gated preserves offline mode and sends no stale traffic', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    final inputOpenGate = Completer<void>();
    midiCommand.connectCalls.clear();
    midiCommand.pendingConnectByDeviceId['nt-in-2'] = inputOpenGate;
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
      _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
    ]);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, ['nt-in-2']);

    // Go offline while silent auto-reconnect is gated on input open.
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

  test('onDemo while silent auto-reconnect open is gated preserves demo mode and cleans up stale ports', () async {
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

  test('failing stale silent auto-reconnect after goOffline does not overwrite offline mode', () async {
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

  test('disconnect and updateDeviceSelection while silent auto-reconnect open is gated preserves selection and protects replacement connection', () async {
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

    // User disconnects to selection screen and changes selection while silent open is gated.
    midiCommand.sentPackets.clear();
    cubit.disconnect();
    await cubit.loadDevices();
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
    expect(midiCommand.openDeviceIds, isEmpty);
    expect(midiCommand.sentPackets, isEmpty);

    // Replacement connection on the SAME endpoints while a stale open is gated:
    // releasing the stale open never closes or disposes the replacement connection.
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

  test('failed silent reconnect keeps opening ownership through cleanup, drains queued retry, and prevents overlapping third open', () async {
    final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [input1, output1];

    await cubit.initialize();
    await cubit.connectToDevices(input1, output1, 0);
    final oldManager = cubit.requireDisting();

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();

    final input2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final output2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    final attempt1Gate = Completer<void>();
    midiCommand.connectCalls.clear();
    midiCommand.pendingConnectByDeviceId[input2.id] = attempt1Gate;
    midiCommand.simulateDevicesAppeared([input2, output2]);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id]);

    // Arm a gate on the retry's input open.
    final retryGate = Completer<void>();
    midiCommand.pendingConnectByDeviceId[input2.id] = retryGate;
    midiCommand.presetName = 'Single Retry Owner';

    // Deliver a setup event while attempt #1 still owns the opening lock:
    // must NOT start an overlapping retry yet.
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id]);

    // Fail attempt #1 -> finally releases ownership and drains queued retry attempt #2,
    // which suspends on retryGate.
    attempt1Gate.completeError(StateError('Transient open failure'));
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id, input2.id]);

    // Deliver another setup event while retry attempt #2 is still gated:
    // must NOT start an overlapping third open.
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();
    expect(midiCommand.connectCalls, [input2.id, input2.id]);

    // Release retryGate -> attempt #2 finishes silently.
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    retryGate.complete();
    await reconnected.timeout(const Duration(seconds: 2));

    expect(midiCommand.connectCalls, [input2.id, input2.id, output2.id]);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Single Retry Owner',
    );
  }, tags: ['regression']);

  test('Linux async-close contract: surviving counterpart during rapid bounce stays silently synchronized without racing unawaited close and reconnects fresh on refresh', () async {
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: true,
    );
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
    final oldManager = cubit.requireDisting();
    expect(cubit.state, isA<DistingStateSynchronized>());

    // Hold the Linux async close of the surviving output endpoint on a gate.
    final outputCloseGate = Completer<void>();
    midiCommand.pendingAsyncDisconnectById[output1.id] = outputCloseGate;
    midiCommand.connectCalls.clear();
    midiCommand.presetName = 'Fresh After Async Close';

    // Input bounces rapidly to a new ID while output stays in the Linux
    // connected map.
    midiCommand.connectedLinuxDevices.remove(input1.id);
    midiCommand.alsaConnectedEndpoints.remove(input1.id);
    midiCommand.openDeviceIds.remove(input1.id);
    final input2 = _makeEndpoint('aseq:21:0', 'disting NT', MidiPortType.IN);
    midiCommand.availableDevices = [input2, output1];
    midiCommand.emitSetupChange(MidiSetupChange.deviceDisappeared);
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    // Must NOT leave SynchronizedScreen and must NOT immediately race
    // an automatic open against the unawaited Linux close.
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls, isEmpty);

    // Complete the native async close, then recover via user refresh without leaving editor.
    outputCloseGate.complete();
    await _flushEventQueue();

    await cubit.refresh();
    final recovered = cubit.state as DistingStateSynchronized;
    expect(identical(recovered.disting, oldManager), isFalse);
    expect(recovered.inputDevice?.id, input2.id);
    expect(recovered.outputDevice?.id, output1.id);
    expect(identical(recovered.outputDevice, connectedOutput), isFalse);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Fresh After Async Close',
    );
  }, tags: ['regression']);

  test('Linux async-close contract: surviving counterpart with delayed input return avoids racing unawaited close and auto-recovers once surviving port vanishes and returns', () async {
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: true,
    );
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
    final oldManager = cubit.requireDisting();

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

    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls, isEmpty);

    // Input returns while output's unawaited Linux close is STILL in flight.
    final input2 = _makeEndpoint('aseq:21:0', 'disting NT', MidiPortType.IN);
    midiCommand.availableDevices = [input2, output1];
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    // Must NOT race an automatic open against the unawaited close.
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect(midiCommand.connectCalls, isEmpty);

    // Complete the native async close; user refresh silently reopens fresh objects.
    outputCloseGate.complete();
    await _flushEventQueue();

    await cubit.refresh();
    final recovered = cubit.state as DistingStateSynchronized;
    expect(identical(recovered.disting, oldManager), isFalse);
    expect(recovered.inputDevice?.id, input2.id);
    expect(recovered.outputDevice?.id, output1.id);
    expect(identical(recovered.outputDevice, connectedOutput), isFalse);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Delayed Return After Async Close',
    );
  }, tags: ['regression']);

  test('Linux full disappearance (both ports vanish and return) recovers silently and automatically', () async {
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: true,
    );
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
    final oldManager = cubit.requireDisting();

    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    midiCommand.presetName = 'Linux Full Auto Reconnect';
    final reconnected = cubit.stream.firstWhere(
      (state) =>
          state is DistingStateSynchronized &&
          !identical(state.disting, oldManager),
    );
    midiCommand.simulateDevicesAppeared([
      _makeEndpoint('aseq:24:0', 'disting NT', MidiPortType.IN),
      _makeEndpoint('aseq:24:1', 'disting NT', MidiPortType.OUT),
    ]);
    await reconnected.timeout(const Duration(seconds: 2));
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Linux Full Auto Reconnect',
    );
  }, tags: ['regression']);

  test('disconnect during in-flight initial sync aborts sync promptly and recovers silently on return', () async {
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

    final emittedStates = <DistingState>[];
    final sub = cubit.stream.listen(emittedStates.add);
    addTearDown(sub.cancel);

    // Disconnect mid-sync: sync exits promptly without bouncing to SelectDevice.
    midiCommand.simulateDevicesDisappeared({input1.id, output1.id});
    await connectFuture.timeout(const Duration(seconds: 2));
    await _flushEventQueue();

    expect(cubit.state, isA<DistingStateConnected>());
    expect(emittedStates.whereType<DistingStateSelectDevice>(), isEmpty);

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

    expect(emittedStates.whereType<DistingStateSelectDevice>(), isEmpty);
    expect(
      await cubit.requireDisting().requestPresetName(),
      'Synced After Mid-Sync Drop',
    );
  }, tags: ['regression']);

  testWidgets(
    'starting with no MIDI ports then plugging in NT enables Connect after valid user selection without restart',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final testDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(testDb.close);
      await tester.runAsync(
        () => AlgorithmMetadataService().initialize(testDb),
      );

      final appUpdateService = _createNoOpAppUpdateService();

      final widgetMidi = _FakeMidiCommand();
      addTearDown(widgetMidi.closeControllers);
      final widgetCubit = DistingCubit(
        testDb,
        midiCommand: widgetMidi,
        isWindowsOverride: false,
        isLinuxOverride: false,
      );
      addTearDown(widgetCubit.close);

      // App starts with zero MIDI ports available.
      await widgetCubit.initialize();
      expect(widgetCubit.state, isA<DistingStateSelectDevice>());
      expect(widgetMidi.setupListenerCount, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: widgetCubit,
            child: DistingPage(appUpdateService: appUpdateService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final connectFinder = find.widgetWithText(FilledButton, 'Connect');
      expect(tester.widget<FilledButton>(connectFinder).onPressed, isNull);

      // USB connected after app start alongside another MIDI port (multiple choices).
      final otherIn = _makeEndpoint('bus-1', 'Bus 1', MidiPortType.IN);
      final otherOut = _makeEndpoint('bus-1-out', 'Bus 1', MidiPortType.OUT);
      final ntIn = _makeEndpoint('nt-in-late', 'disting NT', MidiPortType.IN);
      final ntOut = _makeEndpoint(
        'nt-out-late',
        'disting NT',
        MidiPortType.OUT,
      );
      widgetMidi.presetName = 'Connected After Late USB';
      widgetMidi.simulateDevicesAppeared([otherIn, otherOut, ntIn, ntOut]);
      await tester.pump();
      await tester.pumpAndSettle();

      final afterAppear = widgetCubit.state as DistingStateSelectDevice;
      expect(afterAppear.inputDevices.map((d) => d.id), contains('nt-in-late'));
      expect(
        afterAppear.outputDevices.map((d) => d.id),
        contains('nt-out-late'),
      );
      expect(afterAppear.selectedInputDevice, isNull);
      expect(afterAppear.selectedOutputDevice, isNull);
      expect(tester.widget<FilledButton>(connectFinder).onPressed, isNull);

      // Selecting NT input alone keeps Connect disabled.
      await _chooseDropdown(
        tester,
        const ValueKey('input-midi-device-dropdown'),
        'disting NT',
      );
      expect(tester.widget<FilledButton>(connectFinder).onPressed, isNull);

      // Selecting NT output as well enables Connect with no pending flags blocking it.
      await _chooseDropdown(
        tester,
        const ValueKey('output-midi-device-dropdown'),
        'disting NT',
      );
      expect(tester.widget<FilledButton>(connectFinder).onPressed, isNotNull);

      // Tapping Connect connects and synchronizes cleanly with no restart.
      final synchronized = widgetCubit.stream.firstWhere(
        (state) => state is DistingStateSynchronized,
      );
      await tester.tap(connectFinder);
      await _awaitWhilePumping(tester, synchronized);
      await tester.pump();

      expect(widgetCubit.state, isA<DistingStateSynchronized>());
      expect(find.byType(SynchronizedScreen), findsOneWidget);
      expect(
        await _awaitWhilePumping(
          tester,
          widgetCubit.requireDisting().requestPresetName(),
        ),
        'Connected After Late USB',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
    },
    tags: ['regression'],
  );

  testWidgets(
    'real SynchronizedScreen preserves editor instance, selected slot, and local edits silently across MIDI loss and return with zero notifications',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final testDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(testDb.close);
      await tester.runAsync(
        () => AlgorithmMetadataService().initialize(testDb),
      );

      final appUpdateService = _createNoOpAppUpdateService();

      final widgetMidi = _FakeMidiCommand();
      addTearDown(widgetMidi.closeControllers);
      final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
      final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
      widgetMidi.availableDevices = [input1, output1];
      widgetMidi.presetName = 'Live Session';

      final widgetCubit = DistingCubit(
        testDb,
        midiCommand: widgetMidi,
        isWindowsOverride: false,
        isLinuxOverride: false,
      );
      addTearDown(widgetCubit.close);

      await widgetCubit.initialize();
      await _awaitWhilePumping(
        tester,
        widgetCubit.connectToDevices(input1, output1, 0),
      );
      final initialSync = widgetCubit.state as DistingStateSynchronized;
      final oldManager = widgetCubit.requireDisting();
      widgetCubit.emit(
        initialSync.copyWith(
          slots: [
            _makeSlot(0, 'G1', 'Alpha', value: 10),
            _makeSlot(1, 'G2', 'Beta', value: 25),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: widgetCubit,
            child: DistingPage(appUpdateService: appUpdateService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SynchronizedScreen), findsOneWidget);
      final initialScreenState = tester.state(find.byType(SynchronizedScreen));

      // Select slot 1 (Beta) in the editor sidebar.
      final sidebarBefore = tester.widget<AlgorithmListView>(
        find.byType(AlgorithmListView),
      );
      sidebarBefore.onSelectionChanged(1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AlgorithmListView>(find.byType(AlgorithmListView))
            .selectedIndex,
        1,
      );

      // Simulate transient MIDI loss.
      widgetMidi.simulateDevicesDisappeared({input1.id, output1.id});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Exact same SynchronizedScreen State instance remains mounted; zero messages/banners/dialogs.
      expect(find.byType(SynchronizedScreen), findsOneWidget);
      expect(
        identical(
          tester.state(find.byType(SynchronizedScreen)),
          initialScreenState,
        ),
        isTrue,
      );
      expect(find.textContaining('MIDI connection lost'), findsNothing);
      expect(
        find.text('Select MIDI input and output ports, then connect.'),
        findsNothing,
      );
      expect(find.text('Synchronizing...'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<AlgorithmListView>(find.byType(AlgorithmListView))
            .selectedIndex,
        1,
      );

      // Perform a local parameter edit while disconnected: preserved in UI, no MIDI sent/queued, no snackbar.
      widgetMidi.sentPackets.clear();
      await widgetCubit.updateParameterValue(
        algorithmIndex: 1,
        parameterNumber: 0,
        value: 77,
        userIsChangingTheValue: false,
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('77'), findsWidgets);
      expect(find.byType(SnackBar), findsNothing);
      expect(widgetMidi.sentPackets, isEmpty);

      // Simulate MIDI return with re-enumerated IDs.
      widgetMidi.presetName = 'Resumed Quietly';
      final reconnected = widgetCubit.stream.firstWhere(
        (state) =>
            state is DistingStateSynchronized &&
            !identical(state.disting, oldManager),
      );
      widgetMidi.simulateDevicesAppeared([
        _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN),
        _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT),
      ]);
      await _awaitWhilePumping(tester, reconnected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Still the exact same SynchronizedScreen instance, same selected slot, local edit preserved, zero notifications.
      expect(find.byType(SynchronizedScreen), findsOneWidget);
      expect(
        identical(
          tester.state(find.byType(SynchronizedScreen)),
          initialScreenState,
        ),
        isTrue,
      );
      expect(
        tester
            .widget<AlgorithmListView>(find.byType(AlgorithmListView))
            .selectedIndex,
        1,
      );
      expect(find.text('77'), findsWidgets);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // No stale parameter writes or unsolicited resync traffic on silent return
      // (only read-only CPU monitoring resumed for the active SynchronizedScreen).
      expect(
        widgetMidi.sentPackets.where(
          (packet) =>
              packet.length <= 6 ||
              (packet[6] != DistingNTRequestMessageType.wake.value &&
                  packet[6] !=
                      DistingNTRequestMessageType.requestCpuUsage.value),
        ),
        isEmpty,
      );

      // Fresh NT query immediately works automatically without manual Connect.
      expect(
        await _awaitWhilePumping(
          tester,
          widgetCubit.requireDisting().requestPresetName(),
        ),
        'Resumed Quietly',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
    },
    tags: ['regression'],
  );

  test('explicit device selection persists across restart and restores without auto-connecting', () async {
    final otherIn = _makeEndpoint('other-in', 'Bus 1', MidiPortType.IN);
    final otherOut = _makeEndpoint('other-out', 'Bus 1', MidiPortType.OUT);
    final ntIn = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final ntOut = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [otherIn, otherOut, ntIn, ntOut];

    await cubit.initialize();
    expect(midiCommand.connectCalls, isEmpty);

    cubit.updateDeviceSelection(
      inputDevice: ntIn,
      outputDevice: ntOut,
      sysExId: 17,
    );
    await _flushEventQueue();
    expect(midiCommand.connectCalls, isEmpty);

    // Simulate cold app restart with a brand-new cubit and same SharedPreferences.
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );

    await cubit.initialize();
    final restored = cubit.state as DistingStateSelectDevice;
    expect(restored.selectedInputDevice, same(ntIn));
    expect(restored.selectedOutputDevice, same(ntOut));
    expect(restored.selectedSysExId, 17);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  test('absent preferred ports retain desires without unrelated sole substitution and restore independently on hotplug with nonzero SysEx ID', () async {
    final ntIn1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final ntOut1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final otherIn = _makeEndpoint('other-in', 'Bus 1', MidiPortType.IN);
    final otherOut = _makeEndpoint('other-out', 'Bus 1', MidiPortType.OUT);
    midiCommand.availableDevices = [ntIn1, ntOut1, otherIn, otherOut];

    await cubit.initialize();
    cubit.updateDeviceSelection(
      inputDevice: ntIn1,
      outputDevice: ntOut1,
      sysExId: 9,
    );
    await _flushEventQueue();

    // Restart while BOTH preferred ports are absent and only unrelated sole ports exist.
    await cubit.close();
    midiCommand.availableDevices = [otherIn, otherOut];
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );

    await cubit.initialize();
    var state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, isNull);
    expect(state.selectedOutputDevice, isNull);
    expect(state.selectedSysExId, 9);
    expect(midiCommand.connectCalls, isEmpty);

    // Changing Device ID while both ports are absent must keep both saved port desires.
    cubit.updateDeviceSelection(
      inputDevice: null,
      outputDevice: null,
      sysExId: 14,
    );
    await _flushEventQueue();

    // Only preferred input returns with a new OS ID; output still absent.
    final ntIn2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    midiCommand.simulateDevicesAppeared([ntIn2]);
    await _flushEventQueue();

    state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(ntIn2));
    expect(state.selectedOutputDevice, isNull);
    expect(state.selectedSysExId, 14);
    expect(midiCommand.connectCalls, isEmpty);

    // Changing input explicitly while output is absent retains desired output.
    cubit.updateDeviceSelection(
      inputDevice: otherIn,
      outputDevice: null,
      sysExId: 14,
    );
    await _flushEventQueue();

    // Preferred output returns later and resolves independently while picker stays disconnected.
    final ntOut2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.simulateDevicesAppeared([ntOut2]);
    await _flushEventQueue();

    state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(otherIn));
    expect(state.selectedOutputDevice, same(ntOut2));
    expect(state.selectedSysExId, 14);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  test('nonzero SysEx ID 0..127 persists and restores independently when zero ports are present and invalid stored IDs fall back to 0', () async {
    midiCommand.availableDevices = [];
    await cubit.initialize();

    cubit.updateDeviceSelection(
      inputDevice: null,
      outputDevice: null,
      sysExId: 127,
    );
    await _flushEventQueue();

    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );
    await cubit.initialize();
    expect((cubit.state as DistingStateSelectDevice).selectedSysExId, 127);

    // Out-of-range persisted value falls back to 0 cleanly.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selectedSysExId', 200);
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );
    await cubit.initialize();
    expect((cubit.state as DistingStateSelectDevice).selectedSysExId, 0);
  }, tags: ['regression']);

  test('duplicate-name ambiguity refuses first match and resolves once unambiguous', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedInputMidiDevice', 'disting NT');
    await prefs.setString('selectedInputMidiDeviceId', 'nt-in-old');
    await prefs.setString('selectedOutputMidiDevice', 'disting NT');
    await prefs.setString('selectedOutputMidiDeviceId', 'nt-out-old');
    await prefs.setInt('selectedSysExId', 5);

    final dupIn1 = _makeEndpoint('nt-in-a', 'disting NT', MidiPortType.IN);
    final dupIn2 = _makeEndpoint('nt-in-b', 'disting NT', MidiPortType.IN);
    final dupOut1 = _makeEndpoint('nt-out-a', 'disting NT', MidiPortType.OUT);
    final dupOut2 = _makeEndpoint('nt-out-b', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [dupIn1, dupIn2, dupOut1, dupOut2];

    await cubit.initialize();
    var state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, isNull);
    expect(state.selectedOutputDevice, isNull);
    expect(state.selectedSysExId, 5);
    expect(midiCommand.connectCalls, isEmpty);

    // Removing one duplicate in each direction makes the match unambiguous.
    midiCommand.simulateDevicesDisappeared({dupIn1.id, dupOut1.id});
    await _flushEventQueue();

    state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(dupIn2));
    expect(state.selectedOutputDevice, same(dupOut2));
    expect(state.selectedSysExId, 5);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  test('stable endpoint ID wins over duplicate names, tracks same-ID backend rename, and falls back to unique normalized directional name when ID changes', () async {
    final ntIn1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final ntOut1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [ntIn1, ntOut1];

    await cubit.initialize();
    cubit.updateDeviceSelection(
      inputDevice: ntIn1,
      outputDevice: ntOut1,
      sysExId: 4,
    );
    await _flushEventQueue();

    // Restart with duplicate names where the saved stable ID is second in the list.
    await cubit.close();
    final otherSameNameIn = _makeEndpoint(
      'nt-in-other',
      'disting NT',
      MidiPortType.IN,
    );
    final stableIn = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final otherSameNameOut = _makeEndpoint(
      'nt-out-other',
      'disting NT',
      MidiPortType.OUT,
    );
    final stableOut = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    midiCommand.availableDevices = [
      otherSameNameIn,
      stableIn,
      otherSameNameOut,
      stableOut,
    ];
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );

    await cubit.initialize();
    var state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(stableIn));
    expect(state.selectedOutputDevice, same(stableOut));
    expect(state.selectedSysExId, 4);

    // Backend renames the same stable ID: selection follows ID and reflects new name.
    final renamedIn = _makeEndpoint('nt-in-1', 'Studio NT', MidiPortType.IN);
    final renamedOut = _makeEndpoint('nt-out-1', 'Studio NT', MidiPortType.OUT);
    midiCommand.availableDevices = [
      otherSameNameIn,
      renamedIn,
      otherSameNameOut,
      renamedOut,
    ];
    midiCommand.emitSetupChange(MidiSetupChange.deviceStateChanged);
    await _flushEventQueue();

    state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(renamedIn));
    expect(state.selectedInputDevice?.name, 'Studio NT');
    expect(state.selectedOutputDevice, same(renamedOut));
    expect(state.selectedOutputDevice?.name, 'Studio NT');

    // Stable ID disappears and reappears with a new OS ID and different casing/whitespace;
    // wrong-direction device with same name must be ignored.
    final newIdIn = _makeEndpoint(
      'nt-in-99',
      '  DISTING nt  ',
      MidiPortType.IN,
    );
    final newIdOut = _makeEndpoint(
      'nt-out-99',
      '  DISTING nt  ',
      MidiPortType.OUT,
    );
    midiCommand.availableDevices = [newIdIn, newIdOut];
    midiCommand.emitSetupChange(MidiSetupChange.deviceAppeared);
    await _flushEventQueue();

    state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(newIdIn));
    expect(state.selectedOutputDevice, same(newIdOut));
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  test('newer explicit user selection wins over in-flight enumeration and earlier persistence', () async {
    final inA = _makeEndpoint('in-a', 'Alpha', MidiPortType.IN);
    final outA = _makeEndpoint('out-a', 'Alpha', MidiPortType.OUT);
    final inB = _makeEndpoint('in-b', 'Beta', MidiPortType.IN);
    final outB = _makeEndpoint('out-b', 'Beta', MidiPortType.OUT);
    midiCommand.availableDevices = [inA, outA, inB, outB];

    await cubit.initialize();

    // Gate an async device enumeration while the user rapidly changes selection.
    final refreshGate = Completer<void>();
    midiCommand.pendingDevicesGate = refreshGate;
    final inFlightRefresh = cubit.loadDevices();

    cubit.updateDeviceSelection(
      inputDevice: inA,
      outputDevice: outA,
      sysExId: 5,
    );
    cubit.updateDeviceSelection(
      inputDevice: inB,
      outputDevice: outB,
      sysExId: 19,
    );

    refreshGate.complete();
    await inFlightRefresh;
    await _flushEventQueue();

    final state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(inB));
    expect(state.selectedOutputDevice, same(outB));
    expect(state.selectedSysExId, 19);

    // Restart confirms the latest explicit user choice won persistence.
    await cubit.close();
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: false,
      isLinuxOverride: false,
    );
    await cubit.initialize();
    final restarted = cubit.state as DistingStateSelectDevice;
    expect(restarted.selectedInputDevice, same(inB));
    expect(restarted.selectedOutputDevice, same(outB));
    expect(restarted.selectedSysExId, 19);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  testWidgets(
    'manual Switch from offline after an online session opens restored Device page without reconnecting and displays one label per direction',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final testDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(testDb.close);
      await tester.runAsync(
        () => AlgorithmMetadataService().initialize(testDb),
      );

      final appUpdateService = _createNoOpAppUpdateService();
      final widgetMidi = _FakeMidiCommand();
      addTearDown(widgetMidi.closeControllers);

      final input1 = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
      final output1 = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
      final otherIn = _makeEndpoint('other-in', 'Bus 1', MidiPortType.IN);
      final otherOut = _makeEndpoint('other-out', 'Bus 1', MidiPortType.OUT);
      widgetMidi.availableDevices = [otherIn, otherOut, input1, output1];
      widgetMidi.mutateNameOnFirstPacket = true;

      final widgetCubit = DistingCubit(
        testDb,
        midiCommand: widgetMidi,
        isWindowsOverride: false,
        isLinuxOverride: false,
      );
      addTearDown(widgetCubit.close);

      await widgetCubit.initialize();
      await _awaitWhilePumping(
        tester,
        widgetCubit.connectToDevices(input1, output1, 11),
      );
      expect(widgetCubit.state, isA<DistingStateSynchronized>());
      expect(input1.name, 'disting NT disting NT');

      // Enter offline mode so _lastOnline* is populated.
      await _awaitWhilePumping(tester, widgetCubit.goOffline());
      expect((widgetCubit.state as DistingStateSynchronized).offline, isTrue);

      // Fresh enumerated snapshot has clean backend names (as listDevices returns).
      final freshIn = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
      final freshOut = _makeEndpoint(
        'nt-out-1',
        'disting NT',
        MidiPortType.OUT,
      );
      widgetMidi.availableDevices = [otherIn, otherOut, freshIn, freshOut];
      widgetMidi.connectCalls.clear();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: widgetCubit,
            child: DistingPage(appUpdateService: appUpdateService),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open overflow menu and tap Switch.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();

      // Must show restored Device page WITHOUT reconnecting to _lastOnline.
      expect(widgetCubit.state, isA<DistingStateSelectDevice>());
      expect(widgetMidi.connectCalls, isEmpty);
      final selectState = widgetCubit.state as DistingStateSelectDevice;
      expect(selectState.selectedInputDevice, same(freshIn));
      expect(selectState.selectedOutputDevice, same(freshOut));
      expect(selectState.selectedSysExId, 11);

      String dropdownText(Key key) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      expect(
        dropdownText(const ValueKey('input-midi-device-dropdown')),
        'disting NT',
      );
      expect(
        dropdownText(const ValueKey('output-midi-device-dropdown')),
        'disting NT',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(DropdownMenu<int>),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '11',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 150));
    },
    tags: ['regression'],
  );

  test('switchToDeviceSelection from online or pending silent reconnect returns to restored picker without connecting while goOnline preserves offline reconnect', () async {
    final ntIn = _makeEndpoint('nt-in-1', 'disting NT', MidiPortType.IN);
    final ntOut = _makeEndpoint('nt-out-1', 'disting NT', MidiPortType.OUT);
    final otherIn = _makeEndpoint('other-in', 'Bus 1', MidiPortType.IN);
    final otherOut = _makeEndpoint('other-out', 'Bus 1', MidiPortType.OUT);
    midiCommand.availableDevices = [otherIn, otherOut, ntIn, ntOut];

    await cubit.initialize();
    await cubit.connectToDevices(ntIn, ntOut, 8);
    expect(cubit.state, isA<DistingStateSynchronized>());

    // Enter offline mode -> intentional goOnline still reconnects _lastOnline.
    await cubit.goOffline();
    expect((cubit.state as DistingStateSynchronized).offline, isTrue);
    midiCommand.connectCalls.clear();
    await cubit.goOnline();
    expect(cubit.state, isA<DistingStateSynchronized>());
    expect((cubit.state as DistingStateSynchronized).offline, isFalse);
    expect(midiCommand.connectCalls, ['nt-in-1', 'nt-out-1']);

    // Drop transport into silent reconnect pending state, then manually switch to Device page.
    midiCommand.simulateDevicesDisappeared({ntIn.id, ntOut.id});
    await _flushEventQueue();
    expect(cubit.state, isA<DistingStateSynchronized>());

    midiCommand.connectCalls.clear();
    await cubit.switchToDeviceSelection();
    var selectState = cubit.state as DistingStateSelectDevice;
    expect(selectState.selectedInputDevice, isNull);
    expect(selectState.selectedOutputDevice, isNull);
    expect(selectState.selectedSysExId, 8);
    expect(midiCommand.connectCalls, isEmpty);

    // Returning endpoints restore in picker without auto-connecting.
    final ntIn2 = _makeEndpoint('nt-in-2', 'disting NT', MidiPortType.IN);
    final ntOut2 = _makeEndpoint('nt-out-2', 'disting NT', MidiPortType.OUT);
    midiCommand.simulateDevicesAppeared([ntIn2, ntOut2]);
    await _flushEventQueue();

    selectState = cubit.state as DistingStateSelectDevice;
    expect(selectState.selectedInputDevice, same(ntIn2));
    expect(selectState.selectedOutputDevice, same(ntOut2));
    expect(selectState.selectedSysExId, 8);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);

  test('stale initialize completing after newer loadDevices and user override does not clobber newer selection', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedInputMidiDevice', 'Alpha');
    await prefs.setString('selectedInputMidiDeviceId', 'in-a');
    await prefs.setString('selectedOutputMidiDevice', 'Alpha');
    await prefs.setString('selectedOutputMidiDeviceId', 'out-a');
    await prefs.setInt('selectedSysExId', 3);

    final inA = _makeEndpoint('in-a', 'Alpha', MidiPortType.IN);
    final outA = _makeEndpoint('out-a', 'Alpha', MidiPortType.OUT);
    final inB = _makeEndpoint('in-b', 'Beta', MidiPortType.IN);
    final outB = _makeEndpoint('out-b', 'Beta', MidiPortType.OUT);
    midiCommand.availableDevices = [inA, outA, inB, outB];

    // Hold initialize() on its initial device enumeration.
    final initGate = Completer<void>();
    midiCommand.pendingDevicesGate = initGate;
    final staleInit = cubit.initialize();
    await _flushEventQueue();

    // A newer loadDevices completes first and user overrides selection to Beta / 25.
    await cubit.loadDevices();
    cubit.updateDeviceSelection(
      inputDevice: inB,
      outputDevice: outB,
      sysExId: 25,
    );

    // Now release stale initialize: it must not overwrite Beta / 25.
    initGate.complete();
    await staleInit;
    await _flushEventQueue();

    final state = cubit.state as DistingStateSelectDevice;
    expect(state.selectedInputDevice, same(inB));
    expect(state.selectedOutputDevice, same(outB));
    expect(state.selectedSysExId, 25);
    expect(midiCommand.connectCalls, isEmpty);
  }, tags: ['regression']);
}
