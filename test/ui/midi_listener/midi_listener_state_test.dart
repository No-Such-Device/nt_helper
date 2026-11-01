import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';

void main() {
  group('MidiListenerState.data', () {
    test('accepts all MidiEventType variants', () {
      for (final type in MidiEventType.values) {
        final state = MidiListenerState.data(lastDetectedType: type);
        // Use pattern matching to access Data variant fields
        expect(state, isA<Data>());
        final dataState = state as Data;
        expect(dataState.lastDetectedType, type);
      }
    });

    test('copyWith preserves 14-bit type (cc14BitLowFirst)', () {
      final state =
          MidiListenerState.data(
                lastDetectedType: MidiEventType.cc14BitLowFirst,
                lastDetectedCc: 1,
                lastDetectedChannel: 0,
              )
              as Data;

      final timestamp = DateTime.utc(2026, 1, 1);
      final updated = state.copyWith(lastDetectedTime: timestamp);

      expect(updated.lastDetectedTime, timestamp);
      expect(updated.lastDetectedType, MidiEventType.cc14BitLowFirst);
      expect(updated.lastDetectedCc, 1);
      expect(updated.lastDetectedChannel, 0);
    });

    test('copyWith preserves 14-bit type (cc14BitHighFirst)', () {
      final state =
          MidiListenerState.data(
                lastDetectedType: MidiEventType.cc14BitHighFirst,
                lastDetectedCc: 32,
                lastDetectedChannel: 5,
              )
              as Data;

      final timestamp = DateTime.utc(2026, 1, 1);
      final updated = state.copyWith(lastDetectedTime: timestamp);

      expect(updated.lastDetectedTime, timestamp);
      expect(updated.lastDetectedType, MidiEventType.cc14BitHighFirst);
      expect(updated.lastDetectedCc, 32);
      expect(updated.lastDetectedChannel, 5);
    });
  });
}
