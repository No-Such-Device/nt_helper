import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/preset_load_completion.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';

class _MockDisting extends Mock implements IDistingMidiManager {}

void main() {
  late _MockDisting disting;
  const completion = PresetLoadCompletion();

  setUp(() {
    disting = _MockDisting();
  });

  void stubSlotCounts(List<int?> counts) {
    var index = 0;
    when(
      () => disting.requestNumAlgorithmsInPreset(
        timeout: any(named: 'timeout'),
        maxRetries: any(named: 'maxRetries'),
      ),
    ).thenAnswer((_) async {
      final count = counts[index < counts.length ? index : counts.length - 1];
      index++;
      return count;
    });
  }

  group('readPresetSlotCount', () {
    test('counts the slots in the preset file on the SD card', () async {
      when(() => disting.requestFileDownload('/presets/a.json')).thenAnswer(
        (_) async => Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'name': 'A',
              'slots': [{}, {}, {}],
            }),
          ),
        ),
      );
      expect(
        await completion.readPresetSlotCount(disting, '/presets/a.json'),
        3,
      );
    });

    test('is unknown when the file cannot be read or parsed', () async {
      when(() => disting.requestFileDownload('/missing.json'))
          .thenAnswer((_) async => null);
      when(() => disting.requestFileDownload('/bad.json'))
          .thenAnswer((_) async => Uint8List.fromList(utf8.encode('not json')));
      when(() => disting.requestFileDownload('/error.json'))
          .thenThrow(StateError('busy'));
      for (final path in ['/missing.json', '/bad.json', '/error.json']) {
        expect(await completion.readPresetSlotCount(disting, path), isNull);
      }
    });
  });

  group('waitForSlots', () {
    test(
      'waits through the empty and partial preset until the file count holds',
      () {
        fakeAsync((async) {
          // Matches the NT log: new name at once, 0 slots, then the algorithms.
          stubSlotCounts([0, 0, 0, 1, 2, 2]);
          final reported = <int>[];
          int? result;
          completion
              .waitForSlots(
                disting,
                targetSlotCount: 2,
                isCurrent: () => true,
                onSlotCount: reported.add,
              )
              .then((value) => result = value);
          async.elapse(const Duration(milliseconds: 1000));
          expect(result, isNull);
          async.elapse(const Duration(milliseconds: 250));
          expect(result, 2);
          expect(reported, [0, 1, 2]);
        });
      },
      tags: ['regression'],
    );

    test('accepts a count below the file count once it stops changing', () {
      fakeAsync((async) {
        stubSlotCounts([0, 2]);
        int? result;
        completion
            .waitForSlots(disting, targetSlotCount: 3, isCurrent: () => true)
            .then((value) => result = value);
        async.elapse(const Duration(milliseconds: 10249));
        expect(result, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(result, 2);
      });
    });

    test('without a file count, accepts a count unchanged for 3 seconds', () {
      fakeAsync((async) {
        stubSlotCounts([0, 0, 4]);
        int? result;
        completion
            .waitForSlots(disting, targetSlotCount: null, isCurrent: () => true)
            .then((value) => result = value);
        async.elapse(const Duration(milliseconds: 3499));
        expect(result, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(result, 4);
      });
    });

    test('gives up after 30 seconds of unanswered reads', () {
      fakeAsync((async) {
        stubSlotCounts([null]);
        var done = false;
        int? result = -1;
        completion
            .waitForSlots(disting, targetSlotCount: 2, isCurrent: () => true)
            .then((value) {
              done = true;
              result = value;
            });
        async.elapse(const Duration(milliseconds: 29999));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        expect(result, isNull);
      });
    });

    test('stops when the load is cancelled', () {
      fakeAsync((async) {
        stubSlotCounts([0]);
        var current = true;
        var done = false;
        completion
            .waitForSlots(disting, targetSlotCount: 2, isCurrent: () => current)
            .then((_) => done = true);
        async.elapse(const Duration(milliseconds: 500));
        current = false;
        async.elapse(const Duration(milliseconds: 250));
        expect(done, isTrue);
      });
    });
  });
}
