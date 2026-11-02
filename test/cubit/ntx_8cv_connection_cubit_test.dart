import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/ntx_8cv_connection_cubit.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_midi_connection.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_sysex.dart';

import '../fixtures/ntx_8cv_sysex_fixtures.dart';

void main() {
  group('Ntx8cvConnectionCubit', () {
    late _FakeNtx8cvMidiConnection midiConnection;
    late _MemoryNtx8cvConnectionStore store;
    late Ntx8cvConnectionCubit cubit;

    setUp(() {
      midiConnection = _FakeNtx8cvMidiConnection();
      store = _MemoryNtx8cvConnectionStore();
      cubit = Ntx8cvConnectionCubit(
        midiConnection: midiConnection,
        store: store,
        sessionTimeout: const Duration(milliseconds: 10),
        rebootReconnectDelay: Duration.zero,
        rebootReconnectPollInterval: Duration.zero,
        rebootReconnectTimeout: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      await cubit.close();
      await midiConnection.dispose();
    });

    test('preselects one unambiguous NTX-8CV input and output pair', () async {
      final ntx8cv = _midiDevice(
        id: 'ntx8cv',
        name: 'ntx-8cv',
        input: true,
        output: true,
      );
      midiConnection.devices = [
        _midiDevice(
          id: 'disting',
          name: 'Disting NT',
          input: true,
          output: true,
        ),
        ntx8cv,
      ];

      await cubit.initialize();

      expect(cubit.state.deviceId, 0);
      expect(cubit.state.selectedInputDevice?.id, 'ntx8cv');
      expect(cubit.state.selectedOutputDevice?.id, 'ntx8cv');
      expect(cubit.state.status, Ntx8cvConnectionStatus.disconnected);
    });

    test(
      'keeps manual endpoint selection and a persistent ID from 0 through 126',
      () async {
        final input = _midiDevice(
          id: 'input',
          name: 'Manual input',
          input: true,
        );
        final output = _midiDevice(
          id: 'output',
          name: 'Manual output',
          output: true,
        );
        midiConnection.devices = [input, output];

        await cubit.initialize();
        await cubit.selectInputDevice(input);
        await cubit.selectOutputDevice(output);
        await cubit.setDeviceIdText('126');

        expect(cubit.state.selectedInputDevice?.id, 'input');
        expect(cubit.state.selectedOutputDevice?.id, 'output');
        expect(cubit.state.deviceId, 126);
        expect(store.saved.inputDeviceId, 'input');
        expect(store.saved.outputDeviceId, 'output');
        expect(store.saved.deviceId, 126);

        await cubit.setDeviceIdText('127');

        expect(cubit.state.deviceId, 126);
        expect(cubit.state.deviceIdError, isNotNull);
        expect(store.saved.deviceId, 126);
      },
    tags: ['regression']);

    test(
      'connects only the selected endpoints after device information validates',
      () async {
        final ntx8cv = _midiDevice(
          id: 'ntx8cv',
          name: 'NTX-8CV',
          input: true,
          output: true,
        );
        midiConnection.devices = [
          _midiDevice(
            id: 'disting',
            name: 'Disting NT',
            input: true,
            output: true,
          ),
          ntx8cv,
        ];
        midiConnection.transport.onSend = (_) {
          midiConnection.transport.receive(
            Ntx8cvSysExFixtures.deviceInformationResponse,
          );
        };
        await cubit.initialize();

        await cubit.connect();

        expect(cubit.state.status, Ntx8cvConnectionStatus.connected);
        expect(cubit.session, isNotNull);
        expect(midiConnection.openedPairs, hasLength(1));
        expect(midiConnection.openedPairs.single.inputDevice.id, 'ntx8cv');
        expect(midiConnection.openedPairs.single.outputDevice.id, 'ntx8cv');
        expect(
          midiConnection.transport.sent.single,
          orderedEquals(Ntx8cvSysExFixtures.deviceInformationRequest),
        );
      },
    );

    test(
      'does not accept a mismatched device-information response as connected',
      () async {
        midiConnection.devices = [
          _midiDevice(id: 'ntx8cv', name: 'NTX-8CV', input: true, output: true),
        ];
        midiConnection.transport.onSend = (_) {
          midiConnection.transport.receive(
            Uint8List.fromList([
              0xF0,
              0x00,
              0x21,
              0x27,
              0x6A,
              0x01,
              0x32,
              0x00,
              0xF7,
            ]),
          );
        };
        await cubit.initialize();

        await cubit.connect();

        expect(cubit.state.status, Ntx8cvConnectionStatus.failed);
        expect(cubit.session, isNull);
        expect(cubit.state.statusMessage, contains('did not return valid'));
      },
    tags: ['regression']);

    test(
      'waits for endpoints to return after reboot before reconnecting',
      () async {
        final ntx8cv = _midiDevice(
          id: 'ntx8cv',
          name: 'NTX-8CV',
          input: true,
          output: true,
        );
        var rebooted = false;
        var postRebootLists = 0;
        midiConnection.onListDevices = () {
          if (!rebooted) return [ntx8cv];
          postRebootLists += 1;
          return postRebootLists < 3 ? [] : [ntx8cv];
        };
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x7F) {
            rebooted = true;
            return;
          }
          midiConnection.transport.receive(
            Ntx8cvSysExFixtures.deviceInformationResponse,
          );
        };
        await cubit.initialize();
        await cubit.connect();
        final recoveryStates = <bool>[];
        final recoverySubscription = cubit.stream.listen(
          (state) => recoveryStates.add(state.isReacquiringAfterReboot),
        );
        addTearDown(recoverySubscription.cancel);

        final reconnected = await cubit.rebootAndReconnect();

        expect(reconnected, isTrue);
        expect(recoveryStates, contains(true));
        expect(cubit.state.isReacquiringAfterReboot, isFalse);
        expect(postRebootLists, 3);
        expect(cubit.state.status, Ntx8cvConnectionStatus.connected);
        expect(midiConnection.openedPairs, hasLength(2));
      },
    tags: ['regression']);

    test(
      'disconnects on endpoint loss, reselects on return, and never reconnects automatically',
      () async {
        final ntx8cv = _midiDevice(
          id: 'ntx8cv',
          name: 'NTX-8CV',
          input: true,
          output: true,
        );
        midiConnection.devices = [ntx8cv];
        midiConnection.transport.onSend = (_) {
          midiConnection.transport.receive(
            Ntx8cvSysExFixtures.deviceInformationResponse,
          );
        };
        await cubit.initialize();
        await cubit.connect();
        expect(cubit.state.status, Ntx8cvConnectionStatus.connected);

        midiConnection.devices = [];
        midiConnection.notifySetupChange(MidiSetupChange.deviceDisappeared);
        await _flushEvents();

        expect(cubit.state.status, Ntx8cvConnectionStatus.disconnected);
        expect(cubit.state.selectedInputDevice, isNull);
        expect(cubit.state.selectedOutputDevice, isNull);
        expect(midiConnection.openedPairs, hasLength(1));

        midiConnection.devices = [ntx8cv];
        midiConnection.notifySetupChange(MidiSetupChange.deviceAppeared);
        await _flushEvents();

        expect(cubit.state.selectedInputDevice?.id, 'ntx8cv');
        expect(cubit.state.selectedOutputDevice?.id, 'ntx8cv');
        expect(midiConnection.openedPairs, hasLength(1));
      },
    );
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Ntx8cvMidiEndpoint _midiDevice({
  required String id,
  required String name,
  bool input = false,
  bool output = false,
}) =>
    Ntx8cvMidiEndpoint(id: id, name: name, hasInput: input, hasOutput: output);

class _MemoryNtx8cvConnectionStore implements Ntx8cvConnectionStore {
  Ntx8cvSavedConnection saved = const Ntx8cvSavedConnection();

  @override
  Future<Ntx8cvSavedConnection> load() async => saved;

  @override
  Future<void> save(Ntx8cvSavedConnection selection) async {
    saved = selection;
  }
}

class _FakeNtx8cvMidiConnection implements Ntx8cvMidiConnection {
  List<Ntx8cvMidiEndpoint> devices = [];
  List<Ntx8cvMidiEndpoint> Function()? onListDevices;
  final _setupChanges = StreamController<MidiSetupChange>.broadcast();
  final _FakeNtx8cvMidiTransport transport = _FakeNtx8cvMidiTransport();
  final List<_OpenedPair> openedPairs = [];

  @override
  Stream<MidiSetupChange> get setupChanges => _setupChanges.stream;

  @override
  Future<List<Ntx8cvMidiEndpoint>> listDevices() async =>
      List.of(onListDevices?.call() ?? devices);

  @override
  Future<Ntx8cvMidiTransport> open({
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    openedPairs.add(_OpenedPair(inputDevice, outputDevice));
    return transport;
  }

  @override
  Future<void> close({
    required Ntx8cvMidiTransport transport,
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {}

  void notifySetupChange(MidiSetupChange change) => _setupChanges.add(change);

  Future<void> dispose() async {
    await transport.close();
    await _setupChanges.close();
  }
}

class _OpenedPair {
  const _OpenedPair(this.inputDevice, this.outputDevice);

  final Ntx8cvMidiEndpoint inputDevice;
  final Ntx8cvMidiEndpoint outputDevice;
}

class _FakeNtx8cvMidiTransport implements Ntx8cvMidiTransport {
  final _received = StreamController<Uint8List>.broadcast(sync: true);
  final List<Uint8List> sent = [];
  void Function(Uint8List packet)? onSend;

  @override
  Stream<Uint8List> get receivedPackets => _received.stream;

  @override
  Future<void> send(Uint8List packet) async {
    sent.add(packet);
    onSend?.call(packet);
  }

  void receive(Uint8List packet) => _received.add(packet);

  Future<void> close() => _received.close();
}
