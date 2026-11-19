import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
  });

  // Request encoder tests alone cannot prove that older devices receive no
  // 0x55 traffic. Exercise the real manager and scheduler with a fake transport.
  for (final version in [
    '1.11.0',
    '1.11.99beta',
    '',
    'unknown',
    'custom 1.12.0',
    '1.12.0-rc.1',
    '1.12.0.1',
    '1.11.0\nNov 19 2026',
    '1.12.0',
    'v1.12.0\nDec 2 2025',
    '1.12beta',
    '1.12.0-beta.2',
    '1.19.0',
    '2.0',
  ]) {
    final supported = [
      '1.12.0',
      'v1.12.0\nDec 2 2025',
      '1.12beta',
      '1.12.0-beta.2',
      '1.19.0',
      '2.0',
    ].contains(version);
    test('output usage sends 0x55 only for supported firmware "$version"', () {
      fakeAsync((time) {
        final midi = MockMidiCommand();
        final incoming = StreamController<MidiPacket>.broadcast();
        final device = MidiDevice(
          'io-fixture',
          'Fixture',
          MidiDeviceType.serial,
          true,
        );
        final packets = <List<int>>[];
        when(() => midi.onMidiPacketReceived)
            .thenAnswer((_) => incoming.stream);
        void reply(int command, List<int> payload) {
          incoming.add(
            MidiPacket(
              Uint8List.fromList([
                0xF0,
                0,
                0x21,
                0x27,
                0x6D,
                9,
                command,
                ...payload,
                0xF7,
              ]),
              0,
              device,
            ),
          );
        }

        when(() => midi.sendData(any(), deviceId: any(named: 'deviceId')))
            .thenAnswer((call) {
              final packet = List<int>.of(
                call.positionalArguments.single as Uint8List,
              );
              packets.add(packet);
              if (packet[6] == 0x22) {
                reply(0x32, [...version.codeUnits, 0]);
              } else if (packet[6] == 0x55) {
                reply(0x55, [2, 0, 0, 5, 1, 0, 0, 6]);
              }
            });
        final manager = DistingMidiManager(
          midiCommand: midi,
          inputDevice: device,
          outputDevice: device,
          sysExId: 9,
        );

        // Cover both a fresh manager's probe and reuse of the connection's
        // version read, without sending a redundant 0x22 per parameter.
        if (supported && version != '1.12.0') {
          String? observedVersion;
          manager.requestVersionString().then(
            (value) => observedVersion = value,
          );
          time.flushMicrotasks();
          expect(observedVersion, version);
        }
        var completed = false;
        OutputModeUsage? result;
        manager.requestOutputModeUsage(2, 5).then((value) {
          result = value;
          completed = true;
        });
        time.elapse(const Duration(seconds: 1));
        time.flushMicrotasks();
        expect(completed, isTrue);
        expect(packets.where((p) => p[6] == 0x22), hasLength(1));
        final usagePackets = packets.where((p) => p[6] == 0x55).toList();
        if (supported) {
          expect(usagePackets, [
            [0xF0, 0, 0x21, 0x27, 0x6D, 9, 0x55, 2, 0, 0, 5, 0xF7],
          ]);
          expect(result?.affectedParameterNumbers, [6]);
          expect(result?.algorithmIndex, 2);
          expect(result?.parameterNumber, 5);
        } else {
          expect(usagePackets, isEmpty);
          expect(result, isNull);
        }
        manager.dispose();
        unawaited(incoming.close());
        time.flushMicrotasks();
      });
    });
  }
}
