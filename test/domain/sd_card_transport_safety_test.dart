import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/domain/sd_card_file_activity.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Midi extends Mock implements MidiCommand {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  setUp(() async {
    SharedPreferences.setMockInitialValues({'inter_message_delay_ms': 0});
    prefs = await SharedPreferences.getInstance();
    await SettingsService().init();
  });

  test(
    'late /A cannot populate /B or authorize deletion, even after manager replacement',
    () {
      fakeAsync((time) {
        final wire = _Wire();
        var manager = wire.manager();
        final cubit = PresetBrowserCubit(midiManager: manager, prefs: prefs);
        cubit.loadRootDirectory();
        time.flushMicrotasks();
        wire.reply(_listing('same.json'));
        time.flushMicrotasks();
        cubit.navigateToAbsolutePath('/A');
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 10));
        time.flushMicrotasks();
        expect(cubit.state.view!.errors['/A'], contains('No response'));
        cubit.navigateToAbsolutePath('/B');
        time.flushMicrotasks();
        expect(wire.sdPaths, [
          '/',
          '/A',
        ]); // /B was rejected BEFORE transmission.
        expect(cubit.state.view!.errors['/B'], contains('attribution'));
        expect(cubit.getSelectedPath(), isEmpty);
        Object? deleteError;
        cubit.deleteEntry('/B/same.json').catchError((Object e) {
          deleteError = e;
        });
        time.flushMicrotasks();
        expect(deleteError, isA<AmbiguousResponseAttributionException>());
        expect(
          wire.sent.where((p) => p.length > 7 && p[6] == 0x7A && p[7] == 3),
          isEmpty,
        );
        cubit.close();
        manager.dispose();
        manager = wire.manager();
        Object? blocked;
        manager.requestDirectoryListing('/B').catchError((Object e) {
          blocked = e;
          return null;
        });
        time.flushMicrotasks();
        expect(blocked, isA<AmbiguousResponseAttributionException>());
        time.elapse(
          const Duration(minutes: 2),
        ); // Time alone never clears debt.
        wire.reply(_listing('late-from-A.json'));
        time.flushMicrotasks();
        DirectoryListing? result;
        manager.requestDirectoryListing('/B').then((value) => result = value);
        time.flushMicrotasks();
        expect(wire.sdPaths, ['/', '/A', '/B']);
        wire.reply(_listing('actual-B.json'));
        time.flushMicrotasks();
        // The actual future, not a mocked path-specific callback, parsed /B's reply.
        expect(result!.entries.single.name, 'actual-B.json');
        manager.dispose();
        wire.close();
        time.flushMicrotasks();
      });
    },
    tags: ['regression'],
  );

  for (final op in [3, 5]) {
    test(
      'partial SD reply plus stream error never replays operation $op',
      () {
        fakeAsync((time) {
          final wire = _Wire();
          final manager = wire.manager();
          Object? failure;
          final future = op == 5
              ? manager.requestFileRename('/A/one.json', '/A/two.json')
              : manager.requestFileDelete('/A/one.json');
          future.catchError((Object e) {
            failure = e;
            return null;
          });
          time.flushMicrotasks();
          wire.partial([0xF0, 0, 0x21, 0x27, 0x6D, 0, 0x7A, 0]);
          time.flushMicrotasks();
          wire.incoming.addError(StateError('Interrupted transfer'));
          time.flushMicrotasks();
          time.elapse(const Duration(seconds: 30));
          expect(failure.toString(), contains('not replayed'));
          expect(
            wire.sent.where((p) => p.length > 7 && p[6] == 0x7A && p[7] == op),
            hasLength(1),
          );
          Object? nextError;
          manager.requestDirectoryListing('/').catchError((Object e) {
            nextError = e;
            return null;
          });
          time.flushMicrotasks();
          expect(nextError, isA<AmbiguousResponseAttributionException>());
          manager.dispose();
          wire.close();
          time.flushMicrotasks();
        });
      },
      tags: ['regression'],
    );
  }

  test(
    'load/export and queued load cannot read an upload across manager replacement',
    () {
      fakeAsync((time) {
        final wire = _Wire();
        final manager = wire.manager();
        // Queue load behind a request, then acquire the upload lease before send.
        wire.autoVersion = false;
        manager.requestVersionString();
        manager.requestLoadPreset('/presets/one.json', false).catchError((
          Object e,
        ) {
          expect(e, isA<SdCardFileBusyException>());
        });
        final release = Completer<void>();
        manager.fileActivity.hold({'/presets/one.json'}, () => release.future);
        time.flushMicrotasks();
        wire.version();
        time.flushMicrotasks();
        time.elapse(
          Duration.zero,
        ); // Run the scheduler's configured zero inter-message interval.
        time.flushMicrotasks();
        expect(wire.sent.where((p) => p[6] == 0x34), isEmpty);
        final replacement = wire.manager();
        expect(
          () => replacement.requestLoadPreset('one', false),
          throwsA(isA<SdCardFileBusyException>()),
        );
        Object? exportError;
        replacement.requestFileDownload('/presets/one.json').catchError((
          Object e,
        ) {
          exportError = e;
          return null;
        });
        time.flushMicrotasks();
        expect(exportError, isA<SdCardFileBusyException>());
        expect(wire.sdPaths, isEmpty);
        release.complete();
        time.flushMicrotasks();
        manager.dispose();
        replacement.dispose();
        wire.close();
        time.flushMicrotasks();
      });
    },
    tags: ['regression'],
  );
}

List<int> _listing(String name) => [
  0,
  1,
  0,
  ...List.filled(16, 0),
  ...ascii.encode(name),
  0,
];

class _Wire {
  final midi = _Midi();
  final incoming = StreamController<MidiPacket>.broadcast();
  final device = MidiDevice(
    'safe-test',
    'safe-test',
    MidiDeviceType.serial,
    true,
  );
  final sent = <Uint8List>[];
  bool autoVersion = true;
  _Wire() {
    when(() => midi.onMidiPacketReceived).thenAnswer((_) => incoming.stream);
    when(
      () => midi.sendData(any(), deviceId: any(named: 'deviceId')),
    ).thenAnswer((call) {
      final packet = call.positionalArguments.single as Uint8List;
      sent.add(packet);
      if (autoVersion && packet[6] == 0x22) version();
    });
  }
  DistingMidiManager manager() => DistingMidiManager(
    midiCommand: midi,
    inputDevice: device,
    outputDevice: device,
    sysExId: 0,
  );
  List<String> get sdPaths => sent
      .where((p) => p.length > 8 && p[6] == 0x7A && p[7] == 1)
      .map((p) => ascii.decode(p.sublist(8, p.length - 2)))
      .toList();
  void version() => partial([
    0xF0,
    0,
    0x21,
    0x27,
    0x6D,
    0,
    0x32,
    ...ascii.encode('1.17.0'),
    0,
    0xF7,
  ]);
  void reply(List<int> payload) =>
      partial([0xF0, 0, 0x21, 0x27, 0x6D, 0, 0x7A, ...payload, 0xF7]);
  void partial(List<int> data) =>
      incoming.add(MidiPacket(Uint8List.fromList(data), 0, device));
  void close() {
    incoming.close();
  }
}
