import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _sysExId = 0x2A;

// Recorded catalogue frames retain the complete bytes presented to the MIDI
// parser rather than constructing AlgorithmInfo objects in the test.
const List<int> _emptyPresetResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x60,
  0x00,
  0xF7,
];

const List<int> _twoAlgorithmsResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x30,
  0x00,
  0x00,
  0x02,
  0xF7,
];

const List<int> _zeroAlgorithmsResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x30,
  0x00,
  0x00,
  0x00,
  0xF7,
];

const List<int> _pluginAlgorithmResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x31,
  0x00,
  0x00,
  0x00, // catalogue index 0
  0x70,
  0x6C,
  0x75,
  0x67, // raw GUID "plug"
  0x01, // one specification
  0x00,
  0x00,
  0x00, // minimum 0
  0x00,
  0x00,
  0x7F, // maximum 127
  0x00,
  0x00,
  0x63, // default 99
  0x00, // type
  0x50,
  0x6C,
  0x75,
  0x67,
  0x69,
  0x6E,
  0x00, // "Plugin"
  0x4D,
  0x6F,
  0x64,
  0x65,
  0x00, // "Mode"
  0x01, // isPlugin
  0x01, // isLoaded
  0xF7,
];

const List<int> _builtInAlgorithmResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x31,
  0x00,
  0x00,
  0x01, // catalogue index 1
  0x6E,
  0x6F,
  0x74,
  0x65, // raw GUID "note"
  0x02, // two specifications
  0x03,
  0x7F,
  0x76, // minimum -10
  0x00,
  0x00,
  0x0A, // maximum 10
  0x03,
  0x7F,
  0x7C, // default -4
  0x00, // type
  0x00,
  0x00,
  0x00, // minimum 0
  0x01,
  0x00,
  0x00, // maximum 16384
  0x00,
  0x24,
  0x34, // default 4660
  0x03, // type
  0x4E,
  0x6F,
  0x74,
  0x65,
  0x73,
  0x00, // "Notes"
  0x53,
  0x70,
  0x72,
  0x65,
  0x61,
  0x64,
  0x00, // "Spread"
  0x4D,
  0x6F,
  0x64,
  0x65,
  0x00, // "Mode"
  0x00, // isPlugin
  0x01, // isLoaded
  0xF7,
];

const List<int> _zeroGuidAlgorithmResponse = [
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  _sysExId,
  0x31,
  0x00,
  0x00,
  0x01, // catalogue index 1
  0x00,
  0x00,
  0x00,
  0x00, // undocumented zero GUID
  0x00, // no specifications
  0x5A,
  0x65,
  0x72,
  0x6F,
  0x00, // "Zero"
  0x00, // isPlugin
  0x01, // isLoaded
  0xF7,
];

class _MockMidiCommand extends Mock implements MidiCommand {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  test(
    'selects the exact built-in tuple from an empty-preset connection',
    () async {
      final harness = _CatalogueHarness(
        countResponse: _twoAlgorithmsResponse,
        algorithmResponses: const {
          0: _pluginAlgorithmResponse,
          1: _builtInAlgorithmResponse,
        },
      );
      addTearDown(harness.close);

      expect(await harness.manager.requestNumAlgorithmsInPreset(), 0);

      final input = await MemoryQueryInput.requestFromCatalogue(
        harness.manager,
      );

      expect(input, isNotNull);
      expect(input!.guidBytes, orderedEquals([0x6E, 0x6F, 0x74, 0x65]));
      expect(input.specificationValues, orderedEquals([-4, 4660, 0]));
      expect(
        harness.sentPackets,
        hasLength(4),
        reason: 'empty-preset check, count, plugin info, built-in info',
      );
      expect(
        harness.sentPackets[0],
        orderedEquals([0xF0, 0x00, 0x21, 0x27, 0x6D, _sysExId, 0x60, 0xF7]),
      );
      expect(
        harness.sentPackets[1],
        orderedEquals([0xF0, 0x00, 0x21, 0x27, 0x6D, _sysExId, 0x30, 0xF7]),
      );
      expect(
        harness.sentPackets[2],
        orderedEquals([
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
          0xF7,
        ]),
      );
      expect(
        harness.sentPackets[3],
        orderedEquals([
          0xF0,
          0x00,
          0x21,
          0x27,
          0x6D,
          _sysExId,
          0x31,
          0x00,
          0x00,
          0x01,
          0xF7,
        ]),
      );
      _expectNoAlgorithmMutationOrMemoryRequest(harness.sentPackets);
    },
  );

  test('returns null when every catalogue record is unsuitable', () async {
    final harness = _CatalogueHarness(
      countResponse: _twoAlgorithmsResponse,
      algorithmResponses: const {
        0: _pluginAlgorithmResponse,
        1: _zeroGuidAlgorithmResponse,
      },
    );
    addTearDown(harness.close);

    final input = await MemoryQueryInput.requestFromCatalogue(harness.manager);

    expect(input, isNull);
    expect(harness.sentPackets.map((packet) => packet[6]), [0x30, 0x31, 0x31]);
    _expectNoAlgorithmMutationOrMemoryRequest(harness.sentPackets);
  });

  test('returns null for an empty or missing catalogue', () async {
    final harness = _CatalogueHarness(
      countResponse: _zeroAlgorithmsResponse,
      algorithmResponses: const {},
    );
    addTearDown(harness.close);

    final input = await MemoryQueryInput.requestFromCatalogue(harness.manager);

    expect(input, isNull);
    expect(harness.sentPackets, hasLength(1));
    expect(harness.sentPackets.single[6], 0x30);
    _expectNoAlgorithmMutationOrMemoryRequest(harness.sentPackets);
  });
}

void _expectNoAlgorithmMutationOrMemoryRequest(List<List<int>> packets) {
  final commands = packets.map((packet) => packet[6]).toList();
  expect(commands, isNot(contains(0x32)), reason: 'must not add an algorithm');
  expect(commands, isNot(contains(0x38)), reason: 'must not load a plugin');
  expect(
    commands,
    isNot(contains(0x39)),
    reason: 'this slice only reads input',
  );
}

final class _CatalogueHarness {
  _CatalogueHarness({
    required List<int> countResponse,
    required Map<int, List<int>> algorithmResponses,
  }) : _countResponse = countResponse,
       _algorithmResponses = algorithmResponses {
    when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
    when(
      () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
    ).thenAnswer((invocation) {
      final packet = Uint8List.fromList(
        invocation.positionalArguments.single as Uint8List,
      );
      sentPackets.add(List<int>.unmodifiable(packet));
      final response = _responseFor(packet);
      if (response != null) {
        scheduleMicrotask(() {
          incoming.add(MidiPacket(Uint8List.fromList(response), 0, device));
        });
      }
    });

    manager = DistingMidiManager(
      midiCommand: midi,
      inputDevice: device,
      outputDevice: device,
      sysExId: _sysExId,
    );
  }

  final _MockMidiCommand midi = _MockMidiCommand();
  final StreamController<MidiPacket> incoming =
      StreamController<MidiPacket>.broadcast();
  final MidiDevice device = MidiDevice(
    'memory-query-test-device',
    'Memory Query Test Device',
    MidiDeviceType.serial,
    true,
  );
  final List<List<int>> sentPackets = [];
  final List<int> _countResponse;
  final Map<int, List<int>> _algorithmResponses;

  late final DistingMidiManager manager;

  List<int>? _responseFor(Uint8List request) {
    switch (request[6]) {
      case 0x60:
        return _emptyPresetResponse;
      case 0x30:
        return _countResponse;
      case 0x31:
        final index = (request[7] << 14) | (request[8] << 7) | request[9];
        return _algorithmResponses[index];
      default:
        return null;
    }
  }

  Future<void> close() async {
    manager.dispose();
    await incoming.close();
  }
}
