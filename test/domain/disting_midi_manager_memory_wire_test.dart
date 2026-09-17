import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _sysExId = 0x2A;

class _MockMidiCommand extends Mock implements MidiCommand {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 10,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
  });

  test('sends the exact request and returns only total/current/free', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final future = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);

    final request = harness.memoryRequests.single;
    expect(request, hasLength(21));
    expect(request, [
      0xF0,
      0x00,
      0x21,
      0x27,
      0x6D,
      _sysExId,
      0x39,
      0x6E,
      0x6F,
      0x74,
      0x65,
      0x03,
      0x7F,
      0x7C,
      0x00,
      0x24,
      0x34,
      0x00,
      0x00,
      0x00,
      0xF7,
    ]);

    harness.injectMemory(
      values: const [
        1000,
        2000,
        3000,
        4000,
        100,
        2500,
        0,
        4000,
        91,
        92,
        93,
        94,
      ],
    );
    final result = await future;

    expect(result, isNotNull);
    expect(result!.sram.total, 1000);
    expect(result.sram.current, 100);
    expect(result.sram.free, 900);
    expect(result.dram.total, 2000);
    expect(result.dram.current, 2500);
    expect(result.dram.free, -500);
    expect(result.dtc.total, 3000);
    expect(result.dtc.current, 0);
    expect(result.dtc.free, 3000);
    expect(result.itc.total, 4000);
    expect(result.itc.current, 4000);
    expect(result.itc.free, 0);
  });

  test('ignores wrong-device and wrong-command frames', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final future = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);

    harness.injectMemory(sysExId: _sysExId + 1);
    harness.injectMemory(command: 0x38);
    await Future<void>.delayed(Duration.zero);
    expect(harness.memoryRequests, hasLength(1));

    harness.injectMemory();
    expect(await future, isNotNull);
  });

  test(
    'malformed status fails explicitly instead of returning zeros',
    () async {
      final harness = _MemoryWireHarness(autoMemoryStatus: 2);
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      await expectLater(
        harness.manager.requestMemoryUsage(input),
        throwsA(isA<StateError>()),
      );
      expect(harness.memoryRequests, hasLength(5));
    },
  );

  test('serializes concurrent memory requests through the scheduler', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final first = harness.manager.requestMemoryUsage(input);
    final second = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);
    expect(harness.memoryRequests, hasLength(1));

    harness.injectMemory();
    expect(await first, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(harness.memoryRequests, hasLength(2));

    harness.injectMemory();
    expect(await second, isNotNull);
  });

  test(
    'a delayed timed-out response cannot complete the next memory query',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      final timedOut = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(5);
      await expectLater(timedOut, throwsA(isA<TimeoutException>()));

      final fresh = harness.manager.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 91, 92, 93, 94, 1, 2, 3, 4],
      );

      await freshFailure;
      expect(harness.memoryRequests, hasLength(5));
    },
  );

  test(
    'extra retry responses make a newer memory query fail explicitly',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      final retried = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(2);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );
      final retriedResult = await retried;
      expect(retriedResult?.sram.current, 10);

      final fresh = harness.manager.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );

      await freshFailure;
      await Future<void>.delayed(Duration.zero);
      expect(harness.memoryRequests, hasLength(2));

      final recovered = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(3);
      harness.injectMemory(
        values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
      );
      final recoveredResult = await recovered;
      expect(recoveredResult?.sram.current, 50);
    },
  );

  test(
    'connection replacement rejects a response from the disposed manager',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();
      final oldManager = harness.manager;

      final oldQuery = oldManager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(1);
      oldManager.dispose();
      await expectLater(oldQuery, throwsA(isA<StateError>()));

      final replacement = harness.replaceManager();
      final fresh = replacement.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );

      await freshFailure;
      await Future<void>.delayed(Duration.zero);
      expect(harness.memoryRequests, hasLength(1));

      final recovered = replacement.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(2);
      harness.injectMemory(
        values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
      );
      final recoveredResult = await recovered;
      expect(recoveredResult?.sram.current, 50);
    },
  );
}

final Matcher _throwsAttributionFailure = throwsA(
  isA<AmbiguousResponseAttributionException>(),
);

final class _MemoryWireHarness {
  _MemoryWireHarness({this.autoMemoryStatus}) {
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
          break;
        case 0x31:
          _schedule(_catalogueAlgorithmResponse);
          break;
        case 0x39:
          final status = autoMemoryStatus;
          if (status != null) {
            scheduleMicrotask(() => injectMemory(status: status));
          }
          break;
      }
    });
  }

  final int? autoMemoryStatus;
  final _MockMidiCommand midi = _MockMidiCommand();
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
      sysExId: _sysExId,
    );
    _managers.add(next);
    return next;
  }

  DistingMidiManager replaceManager() {
    manager = _createManager();
    return manager;
  }

  List<List<int>> get memoryRequests => sentPackets
      .where((packet) => packet.length > 6 && packet[6] == 0x39)
      .toList(growable: false);

  Future<MemoryQueryInput> catalogueInput() async {
    final input = await MemoryQueryInput.requestFromCatalogue(manager);
    expect(input, isNotNull);
    return input!;
  }

  Future<void> waitForMemoryRequests(int count) async {
    while (memoryRequests.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void injectMemory({
    int sysExId = _sysExId,
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
  _sysExId,
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
  _sysExId,
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
