import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';

void main() {
  const resolver = PolySampleMappingResolver();

  group('PolySampleMappingResolver', () {
    test('automatic switch matches manual gaps zero through six', () {
      const expectedHigherLows = [61, 61, 61, 61, 62, 62, 63];
      const expectedLowerHighs = [60, 60, 60, 60, 61, 61, 62];
      for (var gap = 0; gap <= 6; gap++) {
        final higherNatural = 61 + gap;
        final resolution = resolver.resolve([
          _region('Lower.wav', rootMidi: 60),
          _region('Higher.wav', rootMidi: higherNatural),
        ]);
        expect(
          resolution.mappings[1].lowMidi,
          expectedHigherLows[gap],
          reason: 'intervening gap $gap',
        );
        expect(
          resolution.mappings[0].highMidi,
          expectedLowerHighs[gap],
          reason: 'intervening gap $gap',
        );
      }
    });

    test('first automatic Low is zero and final High is 127', () {
      final mapping = resolver
          .resolve([_region('Only.wav', rootMidi: 60)])
          .mappings
          .single;

      expect(mapping.lowMidi, 0);
      expect(mapping.highMidi, 127);
    });

    test('explicit SW overrides automatic Low and previous High', () {
      final resolution = resolver.resolve([
        _region('Lower.wav', rootMidi: 60),
        _region('Higher.wav', rootMidi: 67, switchPoint: 65),
      ]);

      expect(resolution.mappings[0].highMidi, 64);
      expect(resolution.mappings[1].lowMidi, 65);
      expect(resolution.mappings[1].switchIsAutomatic, isFalse);
    });

    test('EVOS A1 resolves to F1 through B1', () {
      const naturals = [12, 19, 26, 33, 40, 47, 54, 61, 68, 75];
      final resolution = resolver.resolve([
        for (final natural in naturals)
          _region('Sample_$natural.wav', rootMidi: natural),
      ]);

      expect(resolution.mappings.map((mapping) => mapping.lowMidi), [
        0,
        15,
        22,
        29,
        36,
        43,
        50,
        57,
        64,
        71,
      ]);
      expect(resolution.mappings.map((mapping) => mapping.highMidi), [
        14,
        21,
        28,
        35,
        42,
        49,
        56,
        63,
        70,
        127,
      ]);
      expect(resolution.mappings[3].naturalMidi, 33);
      expect(resolution.mappings[3].lowMidi, 29);
      expect(resolution.mappings[3].highMidi, 35);
    });

    test('rootless families receive deterministic naturals from C3', () {
      final resolution = resolver.resolve([
        _region('Tom.wav'),
        _region('Snare.wav'),
        _region('Kick.wav'),
      ]);

      expect(resolution.mappingForPath('/tmp/Kick.wav')!.naturalMidi, 48);
      expect(resolution.mappingForPath('/tmp/Snare.wav')!.naturalMidi, 49);
      expect(resolution.mappingForPath('/tmp/Tom.wav')!.naturalMidi, 50);
    });

    test('rootless V and RR variants share one natural', () {
      final resolution = resolver.resolve([
        _region('Snare_V1_RR1.wav', velocityLayer: 1, roundRobin: 1),
        _region('Snare_V2_RR1.wav', velocityLayer: 2, roundRobin: 1),
        _region('Snare_V1_RR2.wav', velocityLayer: 1, roundRobin: 2),
        _region('Snare_V2_RR2.wav', velocityLayer: 2, roundRobin: 2),
        _region('Tom_V1.wav', velocityLayer: 1),
      ]);

      expect(
        resolution.mappings.take(4).map((mapping) => mapping.naturalMidi),
        everyElement(48),
      );
      expect(resolution.mappings.last.naturalMidi, 49);
    });

    test('SW remains part of a rootless family key', () {
      final resolution = resolver.resolve([
        PolyMultisampleParser.parsePath('/tmp/Snare_SW40_V1.wav'),
        PolyMultisampleParser.parsePath('/tmp/Snare_SW41_V1.wav'),
      ]);

      expect(resolution.mappings.map((mapping) => mapping.naturalMidi), [
        48,
        49,
      ]);
    });

    test('explicit roots do not consume rootless ordinals', () {
      final resolution = resolver.resolve([
        _region('Explicit.wav', rootMidi: 48),
        _region('Kick.wav'),
      ]);

      expect(resolution.mappings.map((mapping) => mapping.naturalMidi), [
        48,
        48,
      ]);
      expect(
        resolution.issues.map((issue) => issue.kind),
        contains(PolySampleMappingIssueKind.overlappingRange),
      );
    });

    test('switch neighbours are global across incomplete velocity layers', () {
      final resolution = resolver.resolve([
        _region('Lower_V1.wav', rootMidi: 60, velocityLayer: 1),
        _region('Middle_V2.wav', rootMidi: 67, velocityLayer: 2),
        _region('Higher_V1.wav', rootMidi: 72, velocityLayer: 1),
      ]);

      expect(resolution.mappings[1].lowMidi, 63);
      expect(resolution.mappings[1].highMidi, 68);
    });

    test('automatic natural above MIDI 127 is unresolved', () {
      final resolution = resolver.resolve([
        for (var index = 0; index <= 80; index++)
          _region('Family${index.toString().padLeft(3, '0')}.wav'),
      ]);

      expect(resolution.mappings[79].naturalMidi, 127);
      expect(resolution.mappings[79].isPlayable, isTrue);
      expect(resolution.mappings[80].naturalMidi, 128);
      expect(resolution.mappings[80].lowMidi, isNull);
      expect(resolution.mappings[80].highMidi, isNull);
      expect(resolution.mappings[80].isPlayable, isFalse);
      expect(
        resolution
            .issuesForPath(resolution.mappings[80].region.path)
            .single
            .kind,
        PolySampleMappingIssueKind.naturalOutOfMidiRange,
      );
    });

    test('different switch values at one natural report variant mismatch', () {
      final resolution = resolver.resolve([
        _region('A.wav', rootMidi: 60, switchPoint: 55, roundRobin: 1),
        _region('B.wav', rootMidi: 60, switchPoint: 56, roundRobin: 2),
      ]);

      expect(
        resolution.issues.map((issue) => issue.kind),
        contains(PolySampleMappingIssueKind.variantSwitchMismatch),
      );
    });

    test('same velocity and RR overlap reports an overlap issue', () {
      final resolution = resolver.resolve([
        _region('A.wav', rootMidi: 60, velocityLayer: 2, roundRobin: 3),
        _region('B.wav', rootMidi: 60, velocityLayer: 2, roundRobin: 3),
      ]);

      expect(
        resolution.issues.map((issue) => issue.kind),
        contains(PolySampleMappingIssueKind.overlappingRange),
      );
    });

    test('out-of-range parsed SW is preserved and reported', () {
      final region = PolyMultisampleParser.parsePath('/tmp/Piano_C3_SW999.wav');
      final resolution = resolver.resolve([region]);

      expect(resolution.mappings.single.lowMidi, 999);
      expect(
        resolution.issues.first.kind,
        PolySampleMappingIssueKind.switchOutOfMidiRange,
      );
    });

    test('issue order and pair membership are stable', () {
      final resolution = resolver.resolve([
        _region('Out.wav', rootMidi: -1),
        _region('Invalid.wav', rootMidi: 60, switchPoint: 999),
        _region('Variant.wav', rootMidi: 60, switchPoint: 50),
      ]);

      expect(resolution.issues.map((issue) => issue.kind), [
        PolySampleMappingIssueKind.naturalOutOfMidiRange,
        PolySampleMappingIssueKind.switchOutOfMidiRange,
        PolySampleMappingIssueKind.impossibleRange,
        PolySampleMappingIssueKind.naturalOutsideRange,
        PolySampleMappingIssueKind.variantSwitchMismatch,
      ]);
      final pairIssue = resolution.issues.last;
      expect(resolution.issuesForPath('/tmp/Invalid.wav'), contains(pairIssue));
      expect(resolution.issuesForPath('/tmp/Variant.wav'), contains(pairIssue));
    }, tags: ['regression']);

    test('duplicate region paths are rejected', () {
      expect(
        () => resolver.resolve([
          _region('Duplicate.wav'),
          _region('Duplicate.wav'),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Duplicate poly sample path: /tmp/Duplicate.wav',
          ),
        ),
      );
    });
  });
}

PolySampleRegion _region(
  String name, {
  int? rootMidi,
  int? switchPoint,
  int? velocityLayer,
  int? roundRobin,
}) {
  return PolySampleRegion(
    path: '/tmp/$name',
    fileName: name,
    displayName: name,
    rootMidi: rootMidi,
    rootName: rootMidi == null
        ? null
        : PolyMultisampleParser.midiToNoteName(rootMidi),
    switchPoint: switchPoint,
    velocityLayer: velocityLayer,
    roundRobin: roundRobin,
  );
}
