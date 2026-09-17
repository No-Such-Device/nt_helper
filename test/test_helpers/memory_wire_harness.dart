import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';

const int memoryWireSysExId = 0x2A;

class MemoryWireMockMidiCommand extends Mock implements MidiCommand {}

final class MemoryWireHarness {
  MemoryWireHarness({this.autoMemoryStatus}) {
    when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
    when(
      () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
    ).thenAnswer((invocation) {
      final packet = Uint8List.fromList(
        invocation.positionalArguments.single as Uint8List,
      );
      sentPackets.add(List<int>.unmodifiable(packet));
      switch (packet[6]) {
        case 0x30:
          _schedule(_catalogueCountResponse);
        case 0x31:
          _schedule(_catalogueAlgorithmResponse);
        case 0x39:
          final status = autoMemoryStatus;
          if (status != null) {
            scheduleMicrotask(() => injectMemory(status: status));
          }
      }
    });
  }

  final int? autoMemoryStatus;
  final MemoryWireMockMidiCommand midi = MemoryWireMockMidiCommand();
  final StreamController<MidiPacket> incoming =
      StreamController<MidiPacket>.broadcast();
  final MidiDevice device = MidiDevice(
    'memory-wire-test-device',
    'Memory Wire Test Device',
    MidiDeviceType.serial,
    true,
  );
  final List<List<int>> sentPackets = [];

  final List<DistingMidiManager> _managers = [];
  late DistingMidiManager manager = _createManager();

  DistingMidiManager _createManager() {
    final next = DistingMidiManager(
      midiCommand: midi,
      inputDevice: device,
      outputDevice: device,
      sysExId: memoryWireSysExId,
    );
    _managers.add(next);
    return next;
  }

  DistingMidiManager replaceManager() {
    manager = _createManager();
    return manager;
  }

  List<List<int>> get memoryRequests => packetsForCommand(0x39);

  List<List<int>> packetsForCommand(int command) => sentPackets
      .where((packet) => packet.length > 6 && packet[6] == command)
      .toList(growable: false);

  Future<MemoryQueryInput> catalogueInput() async {
    final input = await MemoryQueryInput.requestFromCatalogue(manager);
    expect(input, isNotNull);
    return input!;
  }

  Future<void> waitForMemoryRequests(int count) =>
      waitForCommandRequests(0x39, count);

  Future<void> waitForCommandRequests(int command, int count) async {
    while (packetsForCommand(command).length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void injectMemory({
    int sysExId = memoryWireSysExId,
    int command = 0x39,
    int status = 3,
    List<int> values = const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
  }) {
    incoming.add(
      MidiPacket(
        Uint8List.fromList([
          0xF0,
          0x00,
          0x21,
          0x27,
          0x6D,
          sysExId,
          command,
          status,
          for (final value in values) ..._encodeUint32(value),
          0xF7,
        ]),
        0,
        device,
      ),
    );
  }

  void _schedule(List<int> response) {
    scheduleMicrotask(() {
      incoming.add(MidiPacket(Uint8List.fromList(response), 0, device));
    });
  }

  Future<void> close() async {
    for (final manager in _managers) {
      manager.dispose();
    }
    await incoming.close();
  }
}

List<int> _encodeUint32(int value) => [
  (value >> 28) & 0x0F,
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

const List<int> _catalogueCountResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  memoryWireSysExId,
  0x30,
  0x00,
  0x00,
  0x01,
  0xF7,
];

const List<int> _catalogueAlgorithmResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  memoryWireSysExId,
  0x31,
  0x00,
  0x00,
  0x00,
  0x6E,
  0x6F,
  0x74,
  0x65,
  0x02,
  0x03,
  0x7F,
  0x76,
  0x00,
  0x00,
  0x0A,
  0x03,
  0x7F,
  0x7C,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x24,
  0x34,
  0x03,
  0x4E,
  0x6F,
  0x74,
  0x65,
  0x73,
  0x00,
  0x53,
  0x70,
  0x72,
  0x65,
  0x61,
  0x64,
  0x00,
  0x4D,
  0x6F,
  0x64,
  0x65,
  0x00,
  0x00,
  0x01,
  0xF7,
];
