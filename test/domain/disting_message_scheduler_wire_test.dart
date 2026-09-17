import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/request_key.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockMidiCommand extends Mock implements MidiCommand {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const int _testSysExId = 0x00;

MidiDevice _makeDevice(String id) =>
    MidiDevice(id, 'Test Device', MidiDeviceType.serial, true);

/// Builds a valid Disting NT SysEx response frame.
Uint8List _buildSysEx(
  DistingNTRespMessageType type,
  List<int> payload, {
  int sysExId = _testSysExId,
}) {
  return Uint8List.fromList([
    0xF0,
    0x00, 0x21, 0x27, // Expert Sleepers manufacturer ID
    0x6D, // Disting NT prefix
    sysExId,
    type.value,
    ...payload,
    0xF7,
  ]);
}

/// Builds a CC message (status byte 0xBn).
Uint8List _buildCC(int channel, int controller, int value) {
  return Uint8List.fromList([0xB0 | (channel & 0x0F), controller, value]);
}

/// Builds a Note On message (status byte 0x9n).
Uint8List _buildNoteOn(int channel, int note, int velocity) {
  return Uint8List.fromList([0x90 | (channel & 0x0F), note, velocity]);
}

/// Builds a Note Off message (status byte 0x8n).
Uint8List _buildNoteOff(int channel, int note, int velocity) {
  return Uint8List.fromList([0x80 | (channel & 0x0F), note, velocity]);
}

/// Builds a foreign SysEx message (non-Expert Sleepers manufacturer).
Uint8List _buildForeignSysEx(List<int> manufacturerId, List<int> payload) {
  return Uint8List.fromList([0xF0, ...manufacturerId, ...payload, 0xF7]);
}

/// Combines multiple MIDI messages into a single raw packet.
Uint8List _combineMessages(List<Uint8List> messages) {
  final result = <int>[];
  for (final msg in messages) {
    result.addAll(msg);
  }
  return Uint8List.fromList(result);
}

/// Injects raw bytes as a MidiPacket into the stream.
void _injectRawBytes(
  StreamController<MidiPacket> incoming,
  MidiDevice device,
  Uint8List data,
) {
  incoming.add(MidiPacket(data, 0, device));
}

/// Injects a SysEx response into the scheduler's incoming stream.
void _injectResponse(
  StreamController<MidiPacket> incoming,
  MidiDevice device,
  DistingNTRespMessageType type,
  List<int> payload, {
  int sysExId = _testSysExId,
}) {
  final data = _buildSysEx(type, payload, sysExId: sysExId);
  incoming.add(MidiPacket(data, 0, device));
}

/// Creates a scheduler wired to a broadcast [StreamController] so tests can
/// inject incoming MIDI packets.
({
  DistingMessageScheduler scheduler,
  StreamController<MidiPacket> incoming,
  MidiDevice device,
  MockMidiCommand midi,
})
_createScheduler({
  Duration messageInterval = Duration.zero,
  Duration defaultTimeout = const Duration(milliseconds: 200),
  int defaultMaxRetries = 1,
}) {
  final midi = MockMidiCommand();
  final incoming = StreamController<MidiPacket>.broadcast();
  final device = _makeDevice('test-device');

  when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
  when(
    () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
  ).thenAnswer((_) {});

  final scheduler = DistingMessageScheduler(
    midiCommand: midi,
    inputDevice: device,
    outputDevice: device,
    sysExId: _testSysExId,
    messageInterval: messageInterval,
    defaultTimeout: defaultTimeout,
    defaultMaxRetries: defaultMaxRetries,
  );

  return (scheduler: scheduler, incoming: incoming, device: device, midi: midi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  group('Wire coexistence — CC messages', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('CC packet between two SysEx request/response cycles', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      // First cycle
      final future1 = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final result1 = await future1;
      expect(result1, isNotNull);

      // CC packet arrives between cycles
      _injectRawBytes(incoming, device, _buildCC(0, 20, 64));
      await Future.microtask(() {});

      // Second cycle still works
      final future2 = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x04],
      );
      final result2 = await future2;
      expect(result2, isNotNull);
    });

    test('CC bytes prepended to SysEx in same packet', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // CC prepended to SysEx response in one packet
      final combined = _combineMessages([
        _buildCC(0, 20, 64),
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });

    test('CC bytes appended to SysEx in same packet', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
        _buildCC(0, 20, 64),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });

    test('CC bytes between two SysEx messages in same packet', () async {
      final key1 = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key1,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
        _buildCC(0, 20, 64),
        _buildSysEx(DistingNTRespMessageType.respPresetName, [0x41, 0x00]),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });

    test(
      'CC packet during split SysEx buffering — buffer NOT corrupted',
      () async {
        final key = RequestKey(
          sysExId: _testSysExId,
          messageType: DistingNTRespMessageType.respNumAlgorithms,
        );

        final future = scheduler.sendRequest(
          _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
          key,
        );
        await Future.microtask(() {});

        // Split SysEx: first half (F0, no F7)
        final fullSysEx = _buildSysEx(
          DistingNTRespMessageType.respNumAlgorithms,
          [0x00, 0x00, 0x08],
        );
        final firstHalf = fullSysEx.sublist(0, 5);
        final secondHalf = fullSysEx.sublist(5);

        _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
        await Future.microtask(() {});

        // CC arrives during buffering — should be skipped
        _injectRawBytes(incoming, device, _buildCC(0, 20, 64));
        await Future.microtask(() {});

        // Second half completes the SysEx
        _injectRawBytes(incoming, device, Uint8List.fromList(secondHalf));

        final result = await future;
        expect(result, isNotNull);
      },
    );

    test('Multiple CC packets during split SysEx buffering', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final firstHalf = fullSysEx.sublist(0, 5);
      final secondHalf = fullSysEx.sublist(5);

      _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
      await Future.microtask(() {});

      // Multiple CC packets during buffering
      _injectRawBytes(incoming, device, _buildCC(0, 20, 64));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildCC(0, 21, 127));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildCC(1, 7, 100));
      await Future.microtask(() {});

      _injectRawBytes(incoming, device, Uint8List.fromList(secondHalf));

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('Wire coexistence — Note messages', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('Note On/Off between SysEx cycles', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      _injectRawBytes(incoming, device, _buildNoteOn(0, 60, 100));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildNoteOff(0, 60, 0));
      await Future.microtask(() {});

      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Note On during split SysEx buffering', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final firstHalf = fullSysEx.sublist(0, 5);
      final secondHalf = fullSysEx.sublist(5);

      _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
      await Future.microtask(() {});

      // Note On during buffering — should be skipped
      _injectRawBytes(incoming, device, _buildNoteOn(0, 60, 100));
      await Future.microtask(() {});

      _injectRawBytes(incoming, device, Uint8List.fromList(secondHalf));

      final result = await future;
      expect(result, isNotNull);
    });

    test('Note + SysEx mixed in same packet', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildNoteOn(0, 60, 100),
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
        _buildNoteOff(0, 60, 0),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('Wire coexistence — Foreign SysEx', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test(
      'Complete foreign SysEx while not buffering — ignored by parser',
      () async {
        final key = RequestKey(
          sysExId: _testSysExId,
          messageType: DistingNTRespMessageType.respNumAlgorithms,
        );

        final future = scheduler.sendRequest(
          _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
          key,
        );
        await Future.microtask(() {});

        // Foreign SysEx (Yamaha manufacturer ID 0x43)
        _injectRawBytes(
          incoming,
          device,
          _buildForeignSysEx([0x43], [0x10, 0x4C]),
        );
        await Future.microtask(() {});

        // Our response still works
        _injectResponse(
          incoming,
          device,
          DistingNTRespMessageType.respNumAlgorithms,
          [0x00, 0x00, 0x08],
        );

        final result = await future;
        expect(result, isNotNull);
      },
    );

    test('Complete foreign SysEx during split SysEx buffering', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 500),
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final firstHalf = fullSysEx.sublist(0, 5);

      // Start buffering our SysEx
      _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
      await Future.microtask(() {});

      // Foreign SysEx arrives — has F0, so buffer is discarded
      _injectRawBytes(
        incoming,
        device,
        _buildForeignSysEx([0x43], [0x10, 0x4C]),
      );
      await Future.microtask(() {});

      // Retry will send the request again; inject the full response
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Foreign SysEx + our SysEx in same packet', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildForeignSysEx([0x43], [0x10, 0x4C]),
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });

    test('Two foreign SysEx then our SysEx', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildForeignSysEx([0x43], [0x10]),
        _buildForeignSysEx([0x41], [0x20]),
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('Wire coexistence — Same-manufacturer SysEx (different module ID)', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('SysEx from different module ID — filtered by sysExId', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // SysEx from different module (sysExId = 0x01)
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x04],
        sysExId: 0x01,
      );
      await Future.microtask(() {});

      // Our response with correct sysExId
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Same-manufacturer SysEx during split SysEx buffering', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 500),
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final firstHalf = fullSysEx.sublist(0, 5);

      _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
      await Future.microtask(() {});

      // Different module's SysEx during our buffering — has F0, discards buffer
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x04],
        sysExId: 0x01,
      );
      await Future.microtask(() {});

      // Retry sends again; inject the full response
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('Wire coexistence — Real-time MIDI', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('Timing clock (0xF8) during SysEx buffering — skipped', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final firstHalf = fullSysEx.sublist(0, 5);
      final secondHalf = fullSysEx.sublist(5);

      _injectRawBytes(incoming, device, Uint8List.fromList(firstHalf));
      await Future.microtask(() {});

      // Timing clock during buffering — status byte >= 0x80, skipped
      _injectRawBytes(incoming, device, Uint8List.fromList([0xF8]));
      await Future.microtask(() {});

      _injectRawBytes(incoming, device, Uint8List.fromList(secondHalf));

      final result = await future;
      expect(result, isNotNull);
    });

    test('Active sensing (0xFE) between SysEx packets', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // Active sensing
      _injectRawBytes(incoming, device, Uint8List.fromList([0xFE]));
      await Future.microtask(() {});

      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('_extractSysExMessages edge cases', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('Re-entrant F0 — extracts only the last F0 message', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // Re-entrant F0: [F0 garbage F0 real_data F7]
      // The second F0 should cancel the first, extracting only real_data
      final reentrant = Uint8List.fromList([
        0xF0, 0x43, 0x10, // first F0 + foreign data
        0xF0, 0x00, 0x21, 0x27, 0x6D, _testSysExId,
        DistingNTRespMessageType.respNumAlgorithms.value,
        0x00, 0x00, 0x08,
        0xF7,
      ]);
      _injectRawBytes(incoming, device, reentrant);

      final result = await future;
      expect(result, isNotNull);
    });

    test('Multiple complete SysEx in one packet', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final combined = _combineMessages([
        _buildSysEx(DistingNTRespMessageType.respPresetName, [0x41, 0x00]),
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, [
          0x00,
          0x00,
          0x08,
        ]),
      ]);
      _injectRawBytes(incoming, device, combined);

      final result = await future;
      expect(result, isNotNull);
    });

    test('Orphaned F7 (no preceding F0) — no crash', () async {
      _injectRawBytes(incoming, device, Uint8List.fromList([0xF7]));
      await Future.microtask(() {});

      final diag = scheduler.getDiagnostics();
      expect(diag['nonSysexPacketsReceived'], greaterThanOrEqualTo(1));
    });

    test('Orphaned F0 (no following F7) — starts buffering', () async {
      _injectRawBytes(incoming, device, Uint8List.fromList([0xF0, 0x43, 0x10]));
      await Future.microtask(() {});

      // The scheduler should now be buffering; verify by completing the message
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 500),
      );
      await Future.microtask(() {});

      // The buffered orphaned F0 will be discarded when real response arrives
      // (because it has F0, triggering buffer reset)
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Empty packet — no crash', () async {
      _injectRawBytes(incoming, device, Uint8List(0));
      await Future.microtask(() {});

      final diag = scheduler.getDiagnostics();
      expect(diag['nonSysexPacketsReceived'], greaterThanOrEqualTo(1));
    });
  });

  group('Split SysEx buffering', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('Normal split across 2 packets', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final mid = fullSysEx.length ~/ 2;

      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(0, mid)),
      );
      await Future.microtask(() {});
      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(mid)),
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Normal split across 3 packets', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      final third = fullSysEx.length ~/ 3;

      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(0, third)),
      );
      await Future.microtask(() {});
      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(third, third * 2)),
      );
      await Future.microtask(() {});
      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(third * 2)),
      );

      final result = await future;
      expect(result, isNotNull);
    });

    test('Split with trailing F0 for next message', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // First half of SysEx
      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(0, 5)),
      );
      await Future.microtask(() {});

      // Second half + start of next message (trailing F0)
      final secondWithTrailing = Uint8List.fromList([
        ...fullSysEx.sublist(5),
        0xF0, 0x00, 0x21, 0x27, // start of next SysEx
      ]);
      _injectRawBytes(incoming, device, secondWithTrailing);

      final result = await future;
      expect(result, isNotNull);
    });

    test('Split interrupted by new F0 packet — buffer resets', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
        maxRetries: 3,
        timeout: const Duration(milliseconds: 500),
      );
      await Future.microtask(() {});

      // Start buffering
      final fullSysEx = _buildSysEx(
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      _injectRawBytes(
        incoming,
        device,
        Uint8List.fromList(fullSysEx.sublist(0, 5)),
      );
      await Future.microtask(() {});

      // New F0 packet arrives (start of different SysEx) — should reset buffer
      _injectRawBytes(incoming, device, Uint8List.fromList([0xF0, 0x43, 0x10]));
      await Future.microtask(() {});

      // Retry: complete correct response
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );

      final result = await future;
      expect(result, isNotNull);
    });
  });

  group('Respecify manager/scheduler wire contract', () {
    const configuredSysExId = 0x2A;
    late MockMidiCommand midi;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;
    late IDistingMidiManager manager;

    setUp(() {
      midi = MockMidiCommand();
      incoming = StreamController<MidiPacket>.broadcast();
      device = _makeDevice('respecify-test-device');
      when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
      when(
        () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
      ).thenAnswer((_) {});
      manager = DistingMidiManager(
        midiCommand: midi,
        inputDevice: device,
        outputDevice: device,
        sysExId: configuredSysExId,
      );
    });

    tearDown(() async {
      manager.dispose();
      await incoming.close();
    });

    test(
      'sends one configured-device mutation without awaiting an ack',
      () async {
        await manager.requestRespecifyAlgorithm(2, const [
          0,
          8,
          32767,
          -32768,
          -1,
        ]);

        final captured =
            verify(
                  () => midi.sendData(captureAny(), deviceId: device.id),
                ).captured.single
                as Uint8List;
        expect(captured, [
          0xF0,
          0x00,
          0x21,
          0x27,
          0x6D,
          configuredSysExId,
          0x3A,
          0x02,
          0x05,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x08,
          0x01,
          0x7F,
          0x7F,
          0x02,
          0x00,
          0x00,
          0x03,
          0x7F,
          0x7F,
          0xF7,
        ]);
      },
    );

    test(
      'honors the caller timeout and one-attempt budget for 0x40 readback',
      () async {
        const requestTimeout = Duration(milliseconds: 25);

        await expectLater(
          manager.requestAlgorithmGuid(
            2,
            timeout: requestTimeout,
            maxRetries: 1,
          ),
          throwsA(
            isA<TimeoutException>().having(
              (error) => error.duration,
              'duration',
              requestTimeout,
            ),
          ),
        );

        final captured =
            verify(
                  () => midi.sendData(captureAny(), deviceId: device.id),
                ).captured.single
                as Uint8List;
        expect(captured, [
          0xF0,
          0x00,
          0x21,
          0x27,
          0x6D,
          configuredSysExId,
          0x40,
          0x02,
          0xF7,
        ]);
      },
    );

    test(
      'propagates a send error after exactly one mutation attempt',
      () async {
        when(
          () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
        ).thenThrow(StateError('send failed'));

        await expectLater(
          manager.requestRespecifyAlgorithm(2, const [8]),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Failed to send request after 1 attempts'),
            ),
          ),
        );
        verify(() => midi.sendData(any(), deviceId: device.id)).called(1);
      },
    );
  });

  group('Wire coexistence — Stress/integration', () {
    late DistingMessageScheduler scheduler;
    late StreamController<MidiPacket> incoming;
    late MidiDevice device;

    setUp(() {
      final setup = _createScheduler();
      scheduler = setup.scheduler;
      incoming = setup.incoming;
      device = setup.device;
    });

    tearDown(() {
      scheduler.dispose();
      incoming.close();
    });

    test('Mixed traffic: CC, NoteOn, SysEx, CC, SysEx, NoteOff', () async {
      final key = RequestKey(
        sysExId: _testSysExId,
        messageType: DistingNTRespMessageType.respNumAlgorithms,
      );

      final future = scheduler.sendRequest(
        _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
        key,
      );
      await Future.microtask(() {});

      // Send mixed traffic as individual packets
      _injectRawBytes(incoming, device, _buildCC(0, 1, 64));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildNoteOn(0, 60, 100));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildForeignSysEx([0x43], [0x10]));
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildCC(0, 2, 32));
      await Future.microtask(() {});

      // Our actual response
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respNumAlgorithms,
        [0x00, 0x00, 0x08],
      );
      await Future.microtask(() {});
      _injectRawBytes(incoming, device, _buildNoteOff(0, 60, 0));

      final result = await future;
      expect(result, isNotNull);
    });

    test(
      'Active request with heavy CC/Note traffic — response received',
      () async {
        final key = RequestKey(
          sysExId: _testSysExId,
          messageType: DistingNTRespMessageType.respNumAlgorithms,
        );

        final future = scheduler.sendRequest(
          _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
          key,
        );
        await Future.microtask(() {});

        // Flood with CC and Note messages
        for (int i = 0; i < 20; i++) {
          _injectRawBytes(incoming, device, _buildCC(0, i % 128, i % 128));
          if (i % 3 == 0) {
            _injectRawBytes(incoming, device, _buildNoteOn(0, i % 128, 100));
          }
        }
        await Future.microtask(() {});

        // Response arrives after flood
        _injectResponse(
          incoming,
          device,
          DistingNTRespMessageType.respNumAlgorithms,
          [0x00, 0x00, 0x08],
        );

        final result = await future;
        expect(result, isNotNull);
      },
    );

    test(
      'Split SysEx with interleaved CC + foreign SysEx — retry recovers',
      () async {
        final key = RequestKey(
          sysExId: _testSysExId,
          messageType: DistingNTRespMessageType.respNumAlgorithms,
        );

        final future = scheduler.sendRequest(
          _buildSysEx(DistingNTRespMessageType.respNumAlgorithms, []),
          key,
          maxRetries: 3,
          timeout: const Duration(milliseconds: 500),
        );
        await Future.microtask(() {});

        // Start split SysEx
        final fullSysEx = _buildSysEx(
          DistingNTRespMessageType.respNumAlgorithms,
          [0x00, 0x00, 0x08],
        );
        _injectRawBytes(
          incoming,
          device,
          Uint8List.fromList(fullSysEx.sublist(0, 5)),
        );
        await Future.microtask(() {});

        // CC during buffering — skipped
        _injectRawBytes(incoming, device, _buildCC(0, 20, 64));
        await Future.microtask(() {});

        // Foreign SysEx — has F0, discards buffer
        _injectRawBytes(incoming, device, _buildForeignSysEx([0x43], [0x10]));
        await Future.microtask(() {});

        // Retry: full correct response
        _injectResponse(
          incoming,
          device,
          DistingNTRespMessageType.respNumAlgorithms,
          [0x00, 0x00, 0x08],
        );

        final result = await future;
        expect(result, isNotNull);
      },
    );
  });
}
