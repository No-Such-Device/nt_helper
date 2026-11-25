import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/parameter_update_queue.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/module_settings_fixtures.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

MidiDevice _endpoint(
  String id,
  String name, {
  bool input = false,
  bool output = false,
  bool connected = true,
}) {
  final dev = MidiDevice(id, name, MidiDeviceType.serial, connected);
  if (input) dev.inputPorts.add(MidiPort(0, MidiPortType.IN));
  if (output) dev.outputPorts.add(MidiPort(0, MidiPortType.OUT));
  return dev;
}

Uint8List _respFrame(
  int sysExId,
  DistingNTRespMessageType type,
  List<int> payload,
) => Uint8List.fromList([
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  sysExId,
  type.value,
  ...payload,
  0xF7,
]);

final class _RecordedSend {
  _RecordedSend({
    required this.clientEpoch,
    required this.deviceId,
    required this.packet,
  });

  final int clientEpoch;
  final String? deviceId;
  final Uint8List packet;

  int get command => packet.length > 6 ? packet[6] : -1;
}

/// Deterministic controllable fake implementing [MidiCommand] with swappable
/// packet/setup streams, connect completers, and per-command response hooks.
final class _FakeMidiTransport extends Fake implements MidiCommand {
  _FakeMidiTransport({
    required this.clientEpoch,
    required this.devicesProvider,
    required this.sentLog,
    this.onSend,
    this.connectHandler,
  });

  final int clientEpoch;
  final List<MidiDevice> Function() devicesProvider;
  final List<_RecordedSend> sentLog;
  void Function(
    _FakeMidiTransport transport,
    Uint8List packet,
    String? deviceId,
  )?
  onSend;
  Future<void> Function(_FakeMidiTransport transport, MidiDevice device)?
  connectHandler;

  final StreamController<MidiPacket> incoming =
      StreamController<MidiPacket>.broadcast();
  final StreamController<MidiSetupChange> setup =
      StreamController<MidiSetupChange>.broadcast();

  final List<String> connectedIds = [];
  final List<String> disconnectedIds = [];
  bool disposed = false;
  bool returnNullPacketStream = false;

  @override
  Future<List<MidiDevice>?> get devices async => devicesProvider();

  @override
  Stream<MidiPacket>? get onMidiPacketReceived =>
      returnNullPacketStream ? null : incoming.stream;

  @override
  Stream<MidiSetupChange>? get onMidiSetupChanged => setup.stream;

  @override
  Future<void> connectToDevice(
    MidiDevice device, {
    Duration? awaitConnectionTimeout = const Duration(seconds: 30),
  }) async {
    connectedIds.add(device.id);
    if (connectHandler != null) {
      await connectHandler!(this, device);
      return;
    }
    device.setConnectionState(MidiConnectionState.connected);
  }

  @override
  void disconnectDevice(MidiDevice device) {
    disconnectedIds.add(device.id);
  }

  @override
  void sendData(Uint8List data, {String? deviceId, int? timestamp}) {
    final copy = Uint8List.fromList(data);
    sentLog.add(
      _RecordedSend(clientEpoch: clientEpoch, deviceId: deviceId, packet: copy),
    );
    onSend?.call(this, copy, deviceId);
  }

  @override
  void teardown() {}

  @override
  void dispose() {
    disposed = true;
    if (!incoming.isClosed) unawaited(incoming.close());
    if (!setup.isClosed) unawaited(setup.close());
  }

  void injectSysEx(
    MidiDevice source,
    int sysExId,
    DistingNTRespMessageType type,
    List<int> payload,
  ) {
    if (!incoming.isClosed) {
      incoming.add(MidiPacket(_respFrame(sysExId, type, payload), 0, source));
    }
  }
}

/// Responds to basic Disting NT sync queries (0 slots, version 1.19.0).
void _autoRespondBasicSync(
  _FakeMidiTransport transport,
  MidiDevice Function() currentInput,
  Uint8List packet, {
  int sysExId = 0,
  String version = '1.19.0',
  String presetName = 'Init',
  bool Function(int command)? allowCommand,
}) {
  if (packet.length < 7) return;
  final cmd = packet[6];
  if (allowCommand != null && !allowCommand(cmd)) return;
  final source = currentInput();
  if (cmd == DistingNTRequestMessageType.requestVersionString.value) {
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respMessage,
      [...version.codeUnits, 0],
    );
  } else if (cmd == DistingNTRequestMessageType.requestNumAlgorithms.value) {
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respNumAlgorithms,
      [0, 0, 0],
    );
  } else if (cmd ==
      DistingNTRequestMessageType.requestNumAlgorithmsInPreset.value) {
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respNumAlgorithmsInPreset,
      [0],
    );
  } else if (cmd == DistingNTRequestMessageType.requestPresetName.value) {
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respPresetName,
      [...presetName.codeUnits, 0],
    );
  } else if (cmd == DistingNTRequestMessageType.requestUnitStrings.value) {
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respUnitStrings,
      [0],
    );
  } else if (cmd == DistingNTRequestMessageType.requestPerfPageItem.value) {
    final itemIndex = packet.length > 7 ? packet[7] : 0;
    transport.injectSysEx(
      source,
      sysExId,
      DistingNTRespMessageType.respPerfPageItem,
      [1, itemIndex, 0],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppDatabase database;
  late _MockMetadataDao metadataDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'inter_message_delay_ms': 0,
      'request_timeout_ms': 50,
    });
    await SettingsService().init();
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(() => metadataDao.hasCachedAlgorithms())
        .thenAnswer((_) async => false);
    when(
      () => metadataDao.getAlgorithmInfoCache(
        any(),
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => null);
    when(() => metadataDao.invalidateAlgorithmInfoCache())
        .thenAnswer((_) async {});
  });

  const fastRecovery = OnlineRecoveryConfig(
    connectTimeout: Duration(milliseconds: 200),
    probeTimeout: Duration(milliseconds: 100),
    initialRetryDelay: Duration(milliseconds: 100),
    maxRetryDelay: Duration(milliseconds: 200),
    maxRecoveryAttempts: 4,
    maxRecoveryDuration: Duration(seconds: 2),
  );

  group('Online USB disconnect/reset and NT reboot lifecycle', () {
    test('idle USB reset recovers with one reconnect owner and reaches usable synchronized state', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final clients = <_FakeMidiTransport>[];
        var presetName = 'BeforeReset';

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) => _autoRespondBasicSync(
              t,
              () => input,
              p,
              presetName: presetName,
            ),
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: false,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));

        expect(cubit.state, isA<DistingStateSynchronized>());
        expect(
          (cubit.state as DistingStateSynchronized).presetName,
          'BeforeReset',
        );
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        final firstManager = cubit.disting();

        // Simulate idle USB disconnect (non-Windows recreates MidiCommand).
        visibleDevices = [];
        clients.last.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();

        expect(cubit.connectionHealth, ConnectionHealthState.lost);
        expect(cubit.state, isA<DistingStateConnected>());
        expect(clients.first.disposed, isTrue);
        expect(clients, hasLength(2));

        // Device returns on same IDs with fresh state.
        presetName = 'AfterReset';
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        clients.last.setup.add(MidiSetupChange.deviceAppeared);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 250));

        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        expect(
          (cubit.state as DistingStateSynchronized).presetName,
          'AfterReset',
        );
        expect(identical(cubit.disting(), firstManager), isFalse);
        expect(clients.last.connectedIds, ['nt-in', 'nt-out']);

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('NT reboot waits past initial boot probe timeout and recovers once firmware responds', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        var ntBooted = true;
        final clients = <_FakeMidiTransport>[];

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) {
              if (!ntBooted) return;
              _autoRespondBasicSync(t, () => input, p, presetName: 'Rebooted');
            },
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: true, // Also verifies Windows keeps single client!
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // NT reboots: endpoints disappear, then reappear BEFORE firmware SysEx is ready.
        ntBooted = false;
        visibleDevices = [];
        input.setConnectionState(MidiConnectionState.disconnected);
        time.flushMicrotasks();
        expect(cubit.connectionHealth, ConnectionHealthState.lost);
        // Windows retains single MidiCommand instance!
        expect(clients, hasLength(1));
        expect(clients.single.disposed, isFalse);

        // Endpoints reappear while firmware still booting -> attempt 1 probe times out.
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        clients.single.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 120));
        expect(cubit.state, isNot(isA<DistingStateSynchronized>()));

        // Firmware finishes booting before retry attempt 2.
        ntBooted = true;
        time.elapse(const Duration(milliseconds: 300));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        expect(
          (cubit.state as DistingStateSynchronized).presetName,
          'Rebooted',
        );
        expect(clients, hasLength(1));

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('active read + queued read + queued write settle phase-aware once with zero unsent write sends and no packet migration', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        var holdCpuReply = false;
        final clients = <_FakeMidiTransport>[];

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) {
              if (p.length > 6 &&
                  p[6] == DistingNTRequestMessageType.requestCpuUsage.value &&
                  holdCpuReply) {
                return; // Keep requestCpuUsage in flight
              }
              _autoRespondBasicSync(t, () => input, p, presetName: 'Fresh');
            },
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        final oldManager = cubit.disting()!;

        // Put a read in-flight, queue a read behind it, and queue a write (newPreset 0x35).
        holdCpuReply = true;
        Object? activeErr;
        Object? queuedReadErr;
        Object? queuedWriteErr;
        var settlements = 0;

        oldManager.requestCpuUsage().then<void>(
          (_) => settlements++,
          onError: (Object e) {
            settlements++;
            activeErr = e;
          },
        );
        oldManager.requestNumberOfAlgorithms().then<void>(
          (_) => settlements++,
          onError: (Object e) {
            settlements++;
            queuedReadErr = e;
          },
        );
        oldManager.requestNewPreset().then<void>(
          (_) => settlements++,
          onError: (Object e) {
            settlements++;
            queuedWriteErr = e;
          },
        );
        time.flushMicrotasks();

        // Trigger USB loss while active read is in-flight and write is queued.
        visibleDevices = [];
        clients.single.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();

        expect(settlements, 3);
        expect(
          activeErr,
          isA<DistingSchedulerClosedException>().having(
            (e) => e.phase,
            'phase',
            RequestFailurePhase.inFlight,
          ),
        );
        expect(
          queuedReadErr,
          isA<DistingSchedulerClosedException>().having(
            (e) => e.phase,
            'phase',
            RequestFailurePhase.beforeSend,
          ),
        );
        expect(
          queuedWriteErr,
          isA<DistingSchedulerClosedException>().having(
            (e) => e.phase,
            'phase',
            RequestFailurePhase.beforeSend,
          ),
        );

        // Reconnect USB -> fresh sync runs, ZERO newPreset (0x35) packets EVER sent!
        holdCpuReply = false;
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        clients.single.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 300));

        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(sent.where((s) => s.command == 0x35), isEmpty);

        // The lost in-flight CPU read class (0x56) remains quarantined on the
        // replacement manager until drained, while unaffected reads work!
        Object? quarantinedCpuErr;
        cubit.disting()!.requestCpuUsage().then<void>(
          (_) {},
          onError: (Object e) => quarantinedCpuErr = e,
        );
        time.flushMicrotasks();
        expect(quarantinedCpuErr, isA<AmbiguousResponseAttributionException>());

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('strict settings debt survives non-Windows MidiCommand replacement and changed endpoint ID alias', () {
      fakeAsync((time) {
        var input = _endpoint('usb-port-1', 'disting NT', input: true);
        var output = _endpoint('usb-port-1', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final clients = <_FakeMidiTransport>[];
        var suppressSettingsReply = false;

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) {
              if (p.length > 6 && p[6] == 0x63) {
                if (!suppressSettingsReply) {
                  t.incoming.add(
                    MidiPacket(
                      ModuleSettingsCodec.packet(
                        0,
                        0x63,
                        settingsGroupsPayload(),
                      ),
                      0,
                      input,
                    ),
                  );
                }
                return;
              }
              _autoRespondBasicSync(t, () => input, p, version: '1.20.0');
            },
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: false, // Recreates MidiCommand on USB loss!
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        final manager1 = cubit.disting()! as DistingMidiManager;

        // Send a strict settings discovery that receives no reply, then lose USB.
        suppressSettingsReply = true;
        Object? err1;
        manager1
            .discoverModuleSettings(DistingRequestCancellation())
            .then<void>((_) {}, onError: (Object e) => err1 = e);
        time.flushMicrotasks();

        visibleDevices = [];
        clients.last.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();
        expect(err1, isA<DistingSchedulerClosedException>());
        expect(clients, hasLength(2));

        // Device re-enumerates on a DIFFERENT OS endpoint ID ('usb-port-2') with same name!
        suppressSettingsReply = false;
        input = _endpoint('usb-port-2', 'disting NT', input: true);
        output = _endpoint('usb-port-2', 'disting NT', output: true);
        visibleDevices = [input, output];
        clients.last.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 300));

        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        final manager2 = cubit.disting()! as DistingMidiManager;
        expect(identical(manager2, manager1), isFalse);

        // Even after 5 minutes, new MidiCommand, and changed endpoint ID,
        // strict settings discovery MUST remain fail-closed until drained!
        time.elapse(const Duration(minutes: 5));
        final settingsSendsBefore = sent.where((s) => s.command == 0x63).length;
        Object? quarantinedErr;
        manager2
            .discoverModuleSettings(DistingRequestCancellation())
            .then<void>((_) {}, onError: (Object e) => quarantinedErr = e);
        time.flushMicrotasks();
        expect(quarantinedErr, isA<AmbiguousResponseAttributionException>());
        expect(
          sent.where((s) => s.command == 0x63).length,
          settingsSendsBefore,
        );

        // Late old 0x63 reply drains the carried lineage debt.
        clients.last.incoming.add(
          MidiPacket(
            ModuleSettingsCodec.packet(0, 0x63, settingsGroupsPayload()),
            0,
            input,
          ),
        );
        time.flushMicrotasks();

        // Now fresh discovery succeeds!
        Object? tree;
        manager2
            .discoverModuleSettings(DistingRequestCancellation())
            .then((v) => tree = v);
        time.flushMicrotasks();
        expect(tree, isNotNull);

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('partial endpoint return (input-only or output-only) never publishes Ready or transmits until pair is usable', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final clients = <_FakeMidiTransport>[];

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) => _autoRespondBasicSync(t, () => input, p),
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // Drop both endpoints.
        visibleDevices = [];
        clients.single.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();
        final sendsAfterLoss = sent.length;
        final connectsAfterLoss = clients.single.connectedIds.length;

        // Only input returns -> MUST NOT open or send!
        input = _endpoint('nt-in', 'disting NT', input: true);
        visibleDevices = [input];
        clients.single.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 250));
        expect(cubit.state, isNot(isA<DistingStateSynchronized>()));
        expect(sent.length, sendsAfterLoss);
        expect(clients.single.connectedIds.length, connectsAfterLoss);

        // Only output returns -> MUST NOT open or send!
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [output];
        clients.single.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 250));
        expect(cubit.state, isNot(isA<DistingStateSynchronized>()));
        expect(sent.length, sendsAfterLoss);
        expect(clients.single.connectedIds.length, connectsAfterLoss);

        // Both return -> recovers cleanly!
        visibleDevices = [input, output];
        clients.single.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 300));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('unrelated hotplug does not disrupt session, different device never hijacks recovery, and explicit different-device connect isolates lineage', () {
      fakeAsync((time) {
        final ntIn = _endpoint('nt-in', 'disting NT', input: true);
        final ntOut = _endpoint('nt-out', 'disting NT', output: true);
        final otherIn = _endpoint('other-in', 'Other Synth', input: true);
        final otherOut = _endpoint('other-out', 'Other Synth', output: true);
        var visibleDevices = <MidiDevice>[ntIn, ntOut];
        final sent = <_RecordedSend>[];
        var currentSource = ntIn;

        final transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => visibleDevices,
          sentLog: sent,
          onSend: (t, p, _) {
            if (p.length > 6 &&
                p[6] == DistingNTRequestMessageType.requestCpuUsage.value &&
                identical(currentSource, ntIn)) {
              return; // Keep CPU read in-flight on NT
            }
            _autoRespondBasicSync(t, () => currentSource, p);
          },
        );

        final cubit = DistingCubit(
          database,
          midiCommand: transport,
          midiCommandFactory: () => transport,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(ntIn, ntOut, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        final ntManager = cubit.disting()!;

        // Unrelated keyboard appears -> session stays completely undisturbed.
        visibleDevices = [ntIn, ntOut, otherIn, otherOut];
        transport.setup.add(MidiSetupChange.deviceAppeared);
        time.flushMicrotasks();
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(identical(cubit.disting(), ntManager), isTrue);

        // Start in-flight CPU read on NT, then unplug NT leaving only Other Synth.
        ntManager.requestCpuUsage().ignore();
        time.flushMicrotasks();
        visibleDevices = [otherIn, otherOut];
        transport.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();
        expect(cubit.connectionHealth, ConnectionHealthState.lost);
        time.elapse(const Duration(milliseconds: 300));
        // Must NOT connect to Other Synth during NT recovery!
        expect(transport.connectedIds, isNot(contains('other-in')));

        // User explicitly connects to genuinely different device -> fresh lineage!
        currentSource = otherIn;
        unawaited(cubit.connectToDevices(otherIn, otherOut, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // NT's quarantined CPU read class MUST NOT block Other Synth!
        Object? otherCpuErr;
        cubit.disting()!.requestCpuUsage().then<void>(
          (_) {},
          onError: (Object e) => otherCpuErr = e,
        );
        time.flushMicrotasks();
        expect(
          otherCpuErr,
          isNot(isA<AmbiguousResponseAttributionException>()),
        );

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('simultaneous connectToDevices and rapid resets fence stale opens so old attempt cannot publish Ready, write clock, or disconnect newer owner', () {
      fakeAsync((time) {
        final input = _endpoint('nt-in', 'disting NT', input: true);
        final output = _endpoint('nt-out', 'disting NT', output: true);
        final visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final connectCompleters = <Completer<void>>[];

        final transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => visibleDevices,
          sentLog: sent,
          connectHandler: (t, dev) {
            final completer = Completer<void>();
            connectCompleters.add(completer);
            return completer.future;
          },
          onSend: (t, p, _) => _autoRespondBasicSync(t, () => input, p),
        );

        final cubit = DistingCubit(
          database,
          midiCommand: transport,
          midiCommandFactory: () => transport,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        // Attempt 1 starts and stalls in connectToDevice(input).
        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        expect(connectCompleters, hasLength(1));

        // Attempt 2 supersedes Attempt 1 immediately and completes both opens!
        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        expect(connectCompleters, hasLength(2));
        connectCompleters[1].complete(); // Attempt 2 input open
        time.flushMicrotasks();
        expect(connectCompleters, hasLength(3));
        connectCompleters[2].complete(); // Attempt 2 output open
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));

        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        final ownerManager = cubit.disting();
        final disconnectsBeforeStaleFinish = transport.disconnectedIds.length;
        final clockWritesBeforeStaleFinish = sent
            .where(
              (s) =>
                  s.command ==
                  DistingNTRequestMessageType.setRealTimeClock.value,
            )
            .length;

        // Now Attempt 1's stalled connectToDevice(input) finally completes late!
        connectCompleters[0].complete();
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));

        // Attempt 1 MUST NOT disconnect Attempt 2's live endpoint, replace the
        // manager, publish Ready, or write the clock!
        expect(transport.disconnectedIds.length, disconnectsBeforeStaleFinish);
        expect(identical(cubit.disting(), ownerManager), isTrue);
        expect(
          sent
              .where(
                (s) =>
                    s.command ==
                    DistingNTRequestMessageType.setRealTimeClock.value,
              )
              .length,
          clockWritesBeforeStaleFinish,
        );
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('dispose during pending native open and recovery delay leaves zero listeners, sends, or timers', () {
      fakeAsync((time) {
        final input = _endpoint('nt-in', 'disting NT', input: true);
        final output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final stalledConnect = Completer<void>();
        var stallNextConnect = false;

        final transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => visibleDevices,
          sentLog: sent,
          connectHandler: (t, dev) {
            if (stallNextConnect) return stalledConnect.future;
            return Future<void>.value();
          },
          onSend: (t, p, _) => _autoRespondBasicSync(t, () => input, p),
        );

        final cubit = DistingCubit(
          database,
          midiCommand: transport,
          midiCommandFactory: () => transport,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // Trigger loss -> recovery starts -> stall open -> close cubit mid-open!
        visibleDevices = [];
        transport.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();

        stallNextConnect = true;
        visibleDevices = [input, output];
        transport.setup.add(MidiSetupChange.deviceAppeared);
        time.flushMicrotasks();

        final sendsBeforeClose = sent.length;
        unawaited(cubit.close());
        time.flushMicrotasks();
        expect(cubit.connectionHealth, ConnectionHealthState.closed);

        // Stalled open finishes AFTER cubit.close() -> zero sends, no crash!
        stalledConnect.complete();
        time.elapse(const Duration(minutes: 5));
        time.flushMicrotasks();
        expect(sent.length, sendsBeforeClose);
        expect(transport.incoming.hasListener, isFalse);
      });
    });

    test('recovery exhaustion stops all timers cleanly and explicit retryReconnect recovers once device returns', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];

        final transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => visibleDevices,
          sentLog: sent,
          onSend: (t, p, _) => _autoRespondBasicSync(t, () => input, p),
        );

        final cubit = DistingCubit(
          database,
          midiCommand: transport,
          midiCommandFactory: () => transport,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));

        // Unplug and keep missing beyond maxRecoveryDuration (2s).
        visibleDevices = [];
        transport.setup.add(MidiSetupChange.deviceDisappeared);
        time.elapse(const Duration(seconds: 3));
        expect(cubit.connectionHealth, ConnectionHealthState.recoveryExhausted);
        expect(
          (cubit.state as DistingStateConnected).syncStatus,
          contains('timed out'),
        );

        // Advance virtual time well beyond budget -> zero sends, zero connects!
        final sendsAtExhaustion = sent.length;
        final connectsAtExhaustion = transport.connectedIds.length;
        time.elapse(const Duration(minutes: 10));
        expect(sent.length, sendsAtExhaustion);
        expect(transport.connectedIds.length, connectsAtExhaustion);

        // Device returns -> explicit retryReconnect recovers cleanly!
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        unawaited(cubit.retryReconnect());
        time.elapse(const Duration(milliseconds: 300));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('ParameterUpdateQueue retains latest-wins when healthy, discards pending values on loss, and blocks late string callbacks after dispose', () {
      fakeAsync((time) {
        final input = _endpoint('nt-in', 'disting NT', input: true);
        final output = _endpoint('nt-out', 'disting NT', output: true);
        final sent = <_RecordedSend>[];
        final transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => [input, output],
          sentLog: sent,
        );
        final manager = DistingMidiManager(
          midiCommand: transport,
          inputDevice: input,
          outputDevice: output,
          sysExId: 0,
        );

        final receivedStrings = <String>[];
        final queue = ParameterUpdateQueue(
          midiManager: manager,
          processingInterval: const Duration(milliseconds: 10),
          operationInterval: const Duration(milliseconds: 25),
          onParameterStringUpdated: (_, _, value) => receivedStrings.add(value),
        );

        // Rapid updates to same parameter coalesce (latest wins: 30).
        queue.updateParameter(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: 10,
          needsStringUpdate: false,
        );
        queue.updateParameter(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: 20,
          needsStringUpdate: false,
        );
        queue.updateParameter(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: 30,
          needsStringUpdate: true,
        );
        time.elapse(const Duration(milliseconds: 15));

        // Exactly one setParameterValue (0x46) sent for coalesced value 30,
        // and one requestParameterValueString (0x50) now in flight.
        expect(
          sent.where(
            (s) =>
                s.command ==
                DistingNTRequestMessageType.setParameterValue.value,
          ),
          hasLength(1),
        );
        expect(
          sent.where(
            (s) =>
                s.command ==
                DistingNTRequestMessageType.requestParameterValueString.value,
          ),
          hasLength(1),
        );

        // Queue another update for param 2, then dispose queue BEFORE string arrives.
        queue.updateParameter(
          algorithmIndex: 0,
          parameterNumber: 2,
          value: 99,
          needsStringUpdate: false,
        );
        queue.dispose();

        // Late string response arrives AFTER dispose -> MUST NOT invoke callback!
        transport.injectSysEx(
          input,
          0,
          DistingNTRespMessageType.respParameterValueString,
          [0, ...encode16(1), ...'STALE'.codeUnits, 0],
        );
        time.elapse(const Duration(seconds: 1));

        expect(receivedStrings, isEmpty);
        // Queued update for param 2 was discarded and never transmitted.
        expect(sent.where((s) => s.command == 0x46), hasLength(1));

        manager.dispose();
        transport.dispose();
        time.flushMicrotasks();
      });
    });

    test('rapid back-to-back USB resets during probe converge under a single recovery owner', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        var visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        var dropDuringFirstRecoveryProbe = false;
        var probeCount = 0;

        late _FakeMidiTransport transport;
        transport = _FakeMidiTransport(
          clientEpoch: 1,
          devicesProvider: () => visibleDevices,
          sentLog: sent,
          onSend: (t, p, _) {
            if (dropDuringFirstRecoveryProbe &&
                p.length > 6 &&
                p[6] ==
                    DistingNTRequestMessageType.requestVersionString.value) {
              probeCount++;
              if (probeCount == 1) {
                // Simulate a second rapid USB drop mid-validation probe!
                dropDuringFirstRecoveryProbe = false;
                visibleDevices = [];
                input.setConnectionState(MidiConnectionState.disconnected);
                return;
              }
            }
            _autoRespondBasicSync(
              t,
              () => input,
              p,
              presetName: 'StableAfterRapidResets',
            );
          },
        );

        final cubit = DistingCubit(
          database,
          midiCommand: transport,
          midiCommandFactory: () => transport,
          isWindowsOverride: true,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // First USB drop
        visibleDevices = [];
        transport.setup.add(MidiSetupChange.deviceDisappeared);
        time.flushMicrotasks();
        expect(cubit.connectionHealth, ConnectionHealthState.lost);

        // Device reappears -> triggers recovery attempt 1 -> drops AGAIN mid-probe!
        dropDuringFirstRecoveryProbe = true;
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        transport.setup.add(MidiSetupChange.deviceAppeared);
        time.flushMicrotasks();
        expect(probeCount, 1);
        expect(cubit.state, isNot(isA<DistingStateSynchronized>()));

        // Device returns cleanly -> same single recovery owner finishes recovery!
        input = _endpoint('nt-in', 'disting NT', input: true);
        output = _endpoint('nt-out', 'disting NT', output: true);
        visibleDevices = [input, output];
        transport.setup.add(MidiSetupChange.deviceAppeared);
        time.elapse(const Duration(milliseconds: 300));

        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        expect(
          (cubit.state as DistingStateSynchronized).presetName,
          'StableAfterRapidResets',
        );

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });

    test('receive stream closure (onDone) while online triggers bounded recovery and settles old work', () {
      fakeAsync((time) {
        var input = _endpoint('nt-in', 'disting NT', input: true);
        var output = _endpoint('nt-out', 'disting NT', output: true);
        final visibleDevices = <MidiDevice>[input, output];
        final sent = <_RecordedSend>[];
        final clients = <_FakeMidiTransport>[];

        _FakeMidiTransport makeClient() {
          final client = _FakeMidiTransport(
            clientEpoch: clients.length + 1,
            devicesProvider: () => visibleDevices,
            sentLog: sent,
            onSend: (t, p, _) => _autoRespondBasicSync(
              t,
              () => input,
              p,
              presetName: 'StreamRecovered',
            ),
          );
          clients.add(client);
          return client;
        }

        final cubit = DistingCubit(
          database,
          midiCommand: makeClient(),
          midiCommandFactory: makeClient,
          isWindowsOverride: false,
          recoveryConfig: fastRecovery,
        );

        unawaited(cubit.connectToDevices(input, output, 0));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 50));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);

        // Close the underlying receive stream (onDone) without any setup event.
        unawaited(clients.first.incoming.close());
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 300));

        expect(clients, hasLength(2));
        expect(cubit.connectionHealth, ConnectionHealthState.usable);
        expect(cubit.state, isA<DistingStateSynchronized>());
        expect(
          (cubit.state as DistingStateSynchronized).presetName,
          'StreamRecovered',
        );

        unawaited(cubit.close());
        time.flushMicrotasks();
      });
    });
  });
}
