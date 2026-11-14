import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockMidiCommand extends Mock implements MidiCommand {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockMidiCommand midi;
  late StreamController<MidiPacket> incoming;
  late MidiDevice device;
  late DistingMidiManager manager;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();

    midi = _MockMidiCommand();
    incoming = StreamController<MidiPacket>.broadcast();
    device = MidiDevice(
      'test-device',
      'Test Device',
      MidiDeviceType.serial,
      true,
    );

    when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
    when(
      () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
    ).thenAnswer((_) {});

    manager = DistingMidiManager(
      midiCommand: midi,
      inputDevice: device,
      outputDevice: device,
      sysExId: 0,
    );
  });

  tearDown(() async {
    manager.dispose();
    await incoming.close();
  });

  for (final success in [true, false]) {
    test(
      'rename preserves #n paths and reports SD success=$success',
      () async {
        final sentRename = Completer<Uint8List>();
        when(
          () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
        ).thenAnswer((call) {
          final packet = call.positionalArguments.single as Uint8List;
          if (packet[6] ==
              DistingNTRequestMessageType.requestVersionString.value) {
            _injectResponse(
              incoming,
              device,
              DistingNTRespMessageType.respMessage,
              [...ascii.encode('1.17.0'), 0],
            );
          } else if (packet[6] == 0x7A &&
              packet[7] == SdCardOperation.fileRename.code) {
            sentRename.complete(packet);
            _injectResponse(
              incoming,
              device,
              DistingNTRespMessageType.respDirectoryListing,
              success
                  ? [0, SdCardOperation.fileRename.code]
                  : [1, ...ascii.encode('Destination exists'), 0],
            );
          }
        });
        final rename = manager.requestFileRename(
          '/presets/Alpha.json',
          '/presets/Alpha #42.json',
        );
        if (success) {
          expect((await rename)!.success, isTrue);
        } else {
          await expectLater(
            rename,
            throwsA(
              isA<SdCardOperationException>()
                  .having(
                    (e) => e.operation,
                    'operation',
                    SdCardOperation.fileRename,
                  )
                  .having((e) => e.message, 'message', 'Destination exists'),
            ),
          );
        }
        final packet = await sentRename.future;
        expect(
          ascii.decode(packet.sublist(8, packet.length - 2)),
          '/presets/Alpha.json\u0000/presets/Alpha #42.json\u0000',
        );
      },
      tags: ['regression'],
    );
  }

  test(
    'delayed directory listing cannot complete a following upload',
    () async {
      final listingFuture = manager.requestDirectoryListing('/');

      await Future.microtask(() {});
      _injectResponse(incoming, device, DistingNTRespMessageType.respMessage, [
        ...ascii.encode('1.17.0'),
        0,
      ]);
      await Future<void>.delayed(Duration.zero);
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respDirectoryListing,
        [0, SdCardOperation.directoryListing.code],
      );
      await listingFuture;

      final uploadFuture = manager.requestFileUploadChunk(
        '/programs/plug-ins/chimera.o',
        Uint8List.fromList([1, 2, 3]),
        0,
        createAlways: true,
      );

      await Future.microtask(() {});
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respDirectoryListing,
        [0, SdCardOperation.directoryListing.code],
      );
      _injectResponse(
        incoming,
        device,
        DistingNTRespMessageType.respDirectoryListing,
        [0, SdCardOperation.fileUpload.code],
      );

      final status = await uploadFuture;
      expect(status, isNotNull);
      expect(status!.success, isTrue);
      verify(() => midi.sendData(any(), deviceId: device.id)).called(3);
    },
    tags: ['regression'],
  );
}

void _injectResponse(
  StreamController<MidiPacket> incoming,
  MidiDevice device,
  DistingNTRespMessageType type,
  List<int> payload,
) {
  incoming.add(
    MidiPacket(
      Uint8List.fromList([
        0xF0,
        0x00,
        0x21,
        0x27,
        0x6D,
        0,
        type.value,
        ...payload,
        0xF7,
      ]),
      0,
      device,
    ),
  );
}
