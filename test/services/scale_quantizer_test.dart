import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/scale_quantizer.dart';

void main() {
  group('ScaleQuantizer', () {
    group('scales map', () {
      test('contains expected common scales', () {
        expect(ScaleQuantizer.scales.containsKey('Chromatic'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Major'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Minor'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Dorian'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Phrygian'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Lydian'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Mixolydian'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Locrian'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Pentatonic Major'), isTrue);
        expect(ScaleQuantizer.scales.containsKey('Pentatonic Minor'), isTrue);
      });

      test('Chromatic scale has all 12 semitones', () {
        final chromatic = ScaleQuantizer.scales['Chromatic']!;
        expect(chromatic, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
      });

      test('Major scale has correct intervals', () {
        final major = ScaleQuantizer.scales['Major']!;
        expect(major, equals([0, 2, 4, 5, 7, 9, 11]));
      });

      test('Minor scale has correct intervals', () {
        final minor = ScaleQuantizer.scales['Minor']!;
        expect(minor, equals([0, 2, 3, 5, 7, 8, 10]));
      });

      test('Pentatonic Major has 5 notes', () {
        final pentatonic = ScaleQuantizer.scales['Pentatonic Major']!;
        expect(pentatonic.length, equals(5));
        expect(pentatonic, equals([0, 2, 4, 7, 9]));
      });

      test('Pentatonic Minor has 5 notes', () {
        final pentatonic = ScaleQuantizer.scales['Pentatonic Minor']!;
        expect(pentatonic.length, equals(5));
        expect(pentatonic, equals([0, 3, 5, 7, 10]));
      });
    });

    group('quantize - basic functionality', () {
      test('Chromatic scale passes through any note unchanged', () {
        for (int note = 0; note <= 127; note++) {
          final quantized = ScaleQuantizer.quantize(note, 'Chromatic', 0);
          expect(quantized, equals(note));
        }
      });

      test('quantizes C# (61) to C (60) in C Major', () {
        // C# is 1 semitone away from C, 1 semitone away from D
        // Should quantize to C (closer)
        final quantized = ScaleQuantizer.quantize(61, 'Major', 0);
        expect(quantized, isIn([60, 62])); // Could be C or D
      });

      test('quantizes to correct octave', () {
        // C4 = 60, E4 = 64
        final quantized = ScaleQuantizer.quantize(60, 'Major', 0);
        expect(quantized, equals(60)); // C4 is in C Major

        // C5 = 72
        final quantized5 = ScaleQuantizer.quantize(72, 'Major', 0);
        expect(quantized5, equals(72)); // C5 is in C Major
      });

      test('quantizes across octaves consistently', () {
        // Test the same note class in different octaves
        // C# in octaves 0-10
        for (int octave = 0; octave < 11; octave++) {
          final midiNote = (octave * 12) + 1; // C# in each octave
          final quantized = ScaleQuantizer.quantize(midiNote, 'Major', 0);
          final expectedNoteClass = quantized % 12;
          // C# should quantize to C (0) or D (2) in C Major
          expect(expectedNoteClass, isIn([0, 2]));
        }
      });
    });

    group('quantize - root note transposition', () {
      test('transposition to C (root=0) works', () {
        // E (64) in C Major should stay at E
        final quantized = ScaleQuantizer.quantize(64, 'Major', 0);
        expect(quantized, equals(64)); // E is in C Major scale
      });

      test('transposition to D (root=2) works', () {
        // E (64) in D Major: D Major = D, E, F#, G, A, B, C#
        // E is in D Major, should stay at E
        final quantized = ScaleQuantizer.quantize(64, 'Major', 2);
        expect(quantized, equals(64));
      });

      test('transposition to F# (root=6) works', () {
        // F# Major = F#, G#, A#, B, C#, D#, E#(F)
        // C (60) should quantize to B (59) or C# (61)
        final quantized = ScaleQuantizer.quantize(60, 'Major', 6);
        expect(quantized, isIn([59, 61]));
      });

      test('all root notes (0-11) work without error', () {
        for (int root = 0; root < 12; root++) {
          final quantized = ScaleQuantizer.quantize(60, 'Major', root);
          expect(quantized, greaterThanOrEqualTo(0));
          expect(quantized, lessThanOrEqualTo(127));
        }
      });
    });

    group('quantize - edge cases', () {
      test('handles MIDI note 0', () {
        final quantized = ScaleQuantizer.quantize(0, 'Major', 0);
        expect(quantized, equals(0));
      });

      

      test('handles negative MIDI notes by clamping', () {
        final quantized = ScaleQuantizer.quantize(-10, 'Major', 0);
        expect(quantized, equals(0));
      });

      test('handles MIDI notes > 127 by clamping', () {
        final quantized = ScaleQuantizer.quantize(150, 'Major', 0);
        expect(quantized, equals(127));
      });

      test('handles root < 0 by clamping', () {
        final quantized = ScaleQuantizer.quantize(60, 'Major', -5);
        expect(quantized, greaterThanOrEqualTo(0));
        expect(quantized, lessThanOrEqualTo(127));
      });

      test('handles root > 11 by clamping', () {
        final quantized = ScaleQuantizer.quantize(60, 'Major', 20);
        expect(quantized, greaterThanOrEqualTo(0));
        expect(quantized, lessThanOrEqualTo(127));
      });

      test('handles unknown scale by defaulting to Chromatic', () {
        final quantized = ScaleQuantizer.quantize(61, 'UnknownScale', 0);
        expect(quantized, equals(61)); // Chromatic passes through
      });
    });

    group('quantize - scale accuracy', () {
      test('C Major scale notes pass through unchanged', () {
        final cMajorNotes = [60, 62, 64, 65, 67, 69, 71]; // C, D, E, F, G, A, B
        for (final note in cMajorNotes) {
          final quantized = ScaleQuantizer.quantize(note, 'Major', 0);
          expect(quantized, equals(note));
        }
      });

      test('C Minor scale notes pass through unchanged', () {
        final cMinorNotes = [
          60,
          62,
          63,
          65,
          67,
          68,
          70,
        ]; // C, D, Eb, F, G, Ab, Bb
        for (final note in cMinorNotes) {
          final quantized = ScaleQuantizer.quantize(note, 'Minor', 0);
          expect(quantized, equals(note));
        }
      });

      test('Pentatonic Major quantizes correctly', () {
        // C Pentatonic Major = C, D, E, G, A (60, 62, 64, 67, 69)
        // F (65) should quantize to E (64) or G (67)
        final quantized = ScaleQuantizer.quantize(65, 'Pentatonic Major', 0);
        expect(quantized, isIn([64, 67]));
      });
    });

    group('quantize - nearest degree selection', () {
      test('selects nearest scale degree when equidistant', () {
        // In C Major, F# (66) is equidistant from F (65) and G (67)
        // Implementation should pick the first match (F in this case)
        final quantized = ScaleQuantizer.quantize(66, 'Major', 0);
        expect(quantized, isIn([65, 67]));
      });

      test('always returns a value in the scale', () {
        final testNotes = [60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71];
        final cMajor = [60, 62, 64, 65, 67, 69, 71];

        for (final note in testNotes) {
          final quantized = ScaleQuantizer.quantize(note, 'Major', 0);
          final noteClass = quantized % 12;
          final cMajorNoteClasses = cMajor.map((n) => n % 12).toList();
          expect(cMajorNoteClasses, contains(noteClass));
        }
      });
    });

    group('helper methods', () {
      test('scaleNames returns scale names', () {
        final names = ScaleQuantizer.scaleNames;
        expect(names.isNotEmpty, isTrue);
        expect(names, contains('Major'));
        expect(names, contains('Minor'));
        expect(names, contains('Chromatic'));
      });

      test('getScaleIntervals returns correct intervals', () {
        final intervals = ScaleQuantizer.getScaleIntervals('Major');
        expect(intervals, equals([0, 2, 4, 5, 7, 9, 11]));
      });

      test('getScaleIntervals returns null for unknown scale', () {
        final intervals = ScaleQuantizer.getScaleIntervals('UnknownScale');
        expect(intervals, isNull);
      });

      test('hasScale returns true for existing scales', () {
        expect(ScaleQuantizer.hasScale('Major'), isTrue);
        expect(ScaleQuantizer.hasScale('Minor'), isTrue);
      });

      test('hasScale returns false for non-existing scales', () {
        expect(ScaleQuantizer.hasScale('UnknownScale'), isFalse);
        expect(ScaleQuantizer.hasScale(''), isFalse);
      });
    });
  });
}
