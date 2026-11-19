import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/sysex/requests/set_cv_mapping.dart';
import 'package:nt_helper/domain/sysex/requests/set_midi_mapping.dart';
import 'package:nt_helper/domain/sysex/requests/set_i2c_mapping.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mapping_v8.dart' show mappingV8Fixture;

class _Midi extends Mock implements MidiCommand {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  for (final firmware in [
    '1.20beta',
    '1.20.0',
    '1.12.0',
    '1.19.99',
    'unknown',
  ]) {
    for (final observedVersion in [7, 8]) {
      test(
        'v8 write requires eligible firmware $firmware and observed v$observedVersion',
        () async {
          SharedPreferences.setMockInitialValues({'inter_message_delay_ms': 0});
          await SettingsService().init();
          final midi = _Midi();
          final incoming = StreamController<MidiPacket>.broadcast();
          final device = MidiDevice(
            'test',
            'test',
            MidiDeviceType.serial,
            true,
          );
          when(() => midi.onMidiPacketReceived)
              .thenAnswer((_) => incoming.stream);
          final packets = <Uint8List>[];
          void reply(int command, List<int> payload) => incoming.add(
            MidiPacket(
              Uint8List.fromList([
                0xF0,
                0,
                0x21,
                0x27,
                0x6D,
                0,
                command,
                ...payload,
                0xF7,
              ]),
              0,
              device,
            ),
          );
          when(
            () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
          ).thenAnswer((call) {
            final packet = call.positionalArguments.single as Uint8List;
            packets.add(packet);
            if (packet[6] == 0x22) reply(0x32, [...ascii.encode(firmware), 0]);
            if (packet[6] == 0x4B) {
              reply(0x4B, [0, 0, 0, 5, observedVersion, ...mappingV8Fixture()]);
            }
          });
          final manager = DistingMidiManager(
            midiCommand: midi,
            inputDevice: device,
            outputDevice: device,
            sysExId: 0,
          );
          addTearDown(() async {
            manager.dispose();
            await incoming.close();
          });
          final mapping = PackedMappingData.fromBytes(
            8,
            mappingV8Fixture(),
          ).copyWith(cvInput: 2);
          final write = manager.requestSetMapping(0, 5, mapping);
          if (firmware.startsWith('1.20') && observedVersion == 8) {
            await write;
            final sent = packets
                .where((p) => [0x4D, 0x4E, 0x4F].contains(p[6]))
                .toList();
            expect(sent, [
              SetCVMappingMessage(
                sysExId: 0,
                algorithmIndex: 0,
                parameterNumber: 5,
                data: mapping,
              ).encode(),
              SetMidiMappingMessage(
                sysExId: 0,
                algorithmIndex: 0,
                parameterNumber: 5,
                data: mapping,
              ).encode(),
              SetI2CMappingMessage(
                sysExId: 0,
                algorithmIndex: 0,
                parameterNumber: 5,
                data: mapping,
              ).encode(),
            ]);
            expect(sent[1].sublist(11, 15), [8, 74, 29, 3]);
            expect(sent[2].sublist(11, 15), [8, 72, 1, 71]);
          } else {
            await expectLater(write, throwsUnsupportedError);
            expect(
              packets.where((p) => [0x4D, 0x4E, 0x4F].contains(p[6])),
              isEmpty,
            );
          }
        },
      );
    }
  }
}
