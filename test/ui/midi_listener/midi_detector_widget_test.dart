import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/ui/midi_listener/midi_detector_widget.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';

/// Format a MIDI detection message for display.
///
/// For 14-bit CC types, uses concise format: "14-bit CC {number} Ch {channel}"
/// For all other types (CC, Note On, Note Off), uses verbose format:
/// "Detected {type} {number} on channel {channel}"
String formatMidiDetectionMessage({
  required MidiEventType type,
  required String eventTypeStr,
  required int eventNumber,
  required int channel,
}) {
  return switch (type) {
    MidiEventType.cc14BitLowFirst || MidiEventType.cc14BitHighFirst =>
      '14-bit CC $eventNumber Ch ${channel + 1}',
    MidiEventType.pitchBend => 'Pitch bend Ch ${channel + 1}',
    MidiEventType.channelPressure => 'Channel pressure Ch ${channel + 1}',
    MidiEventType.nrpn => 'NRPN $eventNumber Ch ${channel + 1}',
    _ => 'Detected $eventTypeStr $eventNumber on channel ${channel + 1}',
  };
}

void main() {
  group('MidiDetectorWidget - stale detections', () {
    late _MockMidiListenerCubit cubit;
    late StreamController<MidiListenerState> controller;

    setUp(() {
      cubit = _MockMidiListenerCubit();
      controller = StreamController<MidiListenerState>.broadcast();
      when(() => cubit.startDetecting()).thenReturn(null);
      when(() => cubit.stopDetecting()).thenReturn(null);
    });

    tearDown(() async {
      await controller.close();
    });

    testWidgets('does not replay stale pitch bend detection on mount', (
      tester,
    ) async {
      const staleState = MidiListenerState.data(
        lastDetectedType: MidiEventType.pitchBend,
        lastDetectedChannel: 2,
        lastDetectedCc: 0,
      );
      whenListen(cubit, controller.stream, initialState: staleState);

      var callbackCount = 0;

      await tester.pumpWidget(
        BlocProvider<MidiListenerCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: MidiDetectorWidget(
                onMidiEventFound:
                    ({required type, required channel, required number}) {
                      callbackCount++;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(callbackCount, isZero);
      expect(find.text('Pitch bend Ch 3'), findsNothing);
    }, tags: ['regression']);

    testWidgets('does not replay stale detection on connection state update', (
      tester,
    ) async {
      final detectionTime = DateTime(2026, 6, 4, 12);
      final staleState = MidiListenerState.data(
        lastDetectedType: MidiEventType.pitchBend,
        lastDetectedChannel: 2,
        lastDetectedCc: 0,
        lastDetectedTime: detectionTime,
      );
      whenListen(cubit, controller.stream, initialState: staleState);

      var callbackCount = 0;

      await tester.pumpWidget(
        BlocProvider<MidiListenerCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: MidiDetectorWidget(
                onMidiEventFound:
                    ({required type, required channel, required number}) {
                      callbackCount++;
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      controller.add(
        MidiListenerState.data(
          isConnected: true,
          lastDetectedType: MidiEventType.pitchBend,
          lastDetectedChannel: 2,
          lastDetectedCc: 0,
          lastDetectedTime: detectionTime,
        ),
      );
      await tester.pump();

      expect(callbackCount, isZero);
    }, tags: ['regression']);
  });

  group('MidiDetectorWidget - Status Message Format', () {
    test('14-bit CC low-first uses concise format', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitLowFirst,
        eventTypeStr: '14-bit CC', // Not actually used for 14-bit types
        eventNumber: 1,
        channel: 0, // MIDI channel 0 = display as "Ch 1"
      );

      expect(message, equals('14-bit CC 1 Ch 1'));
      // Verify it's 5 words (concise format)
      expect(message.split(' ').length, equals(5));
    });

    test('14-bit CC high-first uses concise format', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitHighFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 32,
        channel: 5, // MIDI channel 5 = display as "Ch 6"
      );

      expect(message, equals('14-bit CC 32 Ch 6'));
      // Verify it's 5 words (concise format)
      expect(message.split(' ').length, equals(5));
    });

    test('7-bit CC uses verbose format (unchanged)', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc,
        eventTypeStr: 'CC',
        eventNumber: 7,
        channel: 2, // MIDI channel 2 = display as "channel 3"
      );

      expect(message, equals('Detected CC 7 on channel 3'));
      // Verify it's 6 words (verbose format)
      expect(message.split(' ').length, equals(6));
    });

    test('Note On uses verbose format (unchanged)', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.noteOn,
        eventTypeStr: 'Note On',
        eventNumber: 60,
        channel: 0,
      );

      expect(message, equals('Detected Note On 60 on channel 1'));
      // Verify it's 7 words (verbose format)
      expect(message.split(' ').length, equals(7));
    });

    test('Note Off uses verbose format (unchanged)', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.noteOff,
        eventTypeStr: 'Note Off',
        eventNumber: 60,
        channel: 15, // MIDI channel 15 = display as "channel 16"
      );

      expect(message, equals('Detected Note Off 60 on channel 16'));
      // Verify it's 7 words (verbose format)
      expect(message.split(' ').length, equals(7));
    });

    test('NRPN uses concise format', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.nrpn,
        eventTypeStr: 'NRPN',
        eventNumber: 42,
        channel: 2,
      );

      expect(message, equals('NRPN 42 Ch 3'));
    });

    test('14-bit format is significantly shorter than verbose', () {
      final bit14Message = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitLowFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 1,
        channel: 0,
      );

      final bit7Message = formatMidiDetectionMessage(
        type: MidiEventType.cc,
        eventTypeStr: 'CC',
        eventNumber: 1,
        channel: 0,
      );

      // 14-bit message should be shorter (better UI density)
      expect(bit14Message.length, lessThan(bit7Message.length));
    });

    test('All MidiEventType variants produce valid messages', () {
      for (final type in MidiEventType.values) {
        final eventTypeStr = switch (type) {
          MidiEventType.cc => 'CC',
          MidiEventType.noteOn => 'Note On',
          MidiEventType.noteOff => 'Note Off',
          MidiEventType.cc14BitLowFirst => '14-bit CC',
          MidiEventType.cc14BitHighFirst => '14-bit CC',
          MidiEventType.pitchBend => 'Pitch bend',
          MidiEventType.channelPressure => 'Channel pressure',
          MidiEventType.nrpn => 'NRPN',
        };

        final message = formatMidiDetectionMessage(
          type: type,
          eventTypeStr: eventTypeStr,
          eventNumber: 64,
          channel: 0,
        );

        // All messages should be non-empty and contain the event number
        expect(message, isNotEmpty);
        if (type != MidiEventType.pitchBend &&
            type != MidiEventType.channelPressure) {
          expect(message, contains('64'));
        }
        expect(message, anyOf(contains('Ch 1'), contains('channel 1')));
      }
    });
  });

  group('MidiDetectorWidget - Channel Display', () {
    test('MIDI channel 0 displays as Ch 1', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitLowFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 1,
        channel: 0,
      );

      expect(message, contains('Ch 1'));
    });

    test('MIDI channel 15 displays as Ch 16', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitLowFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 1,
        channel: 15,
      );

      expect(message, contains('Ch 16'));
    });

    test('Verbose format displays channel correctly', () {
      final message = formatMidiDetectionMessage(
        type: MidiEventType.cc,
        eventTypeStr: 'CC',
        eventNumber: 7,
        channel: 9, // MIDI channel 9 = display as "channel 10"
      );

      expect(message, contains('channel 10'));
    });
  });

  group('MidiDetectorWidget - Message Consistency', () {
    test('14-bit low-first and high-first use identical format', () {
      final lowMessage = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitLowFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 1,
        channel: 0,
      );

      final highMessage = formatMidiDetectionMessage(
        type: MidiEventType.cc14BitHighFirst,
        eventTypeStr: '14-bit CC',
        eventNumber: 1,
        channel: 0,
      );

      // Both should produce same format (only difference is internal byte order)
      expect(lowMessage, equals(highMessage));
    });

    test('Different CC numbers produce unique messages', () {
      final messages = <String>{};

      for (int ccNum = 0; ccNum < 32; ccNum++) {
        final message = formatMidiDetectionMessage(
          type: MidiEventType.cc14BitLowFirst,
          eventTypeStr: '14-bit CC',
          eventNumber: ccNum,
          channel: 0,
        );
        messages.add(message);
      }

      // All messages should be unique (32 different CC numbers)
      expect(messages.length, equals(32));
    });
  });
}

class _MockMidiListenerCubit extends MockCubit<MidiListenerState>
    implements MidiListenerCubit {}
