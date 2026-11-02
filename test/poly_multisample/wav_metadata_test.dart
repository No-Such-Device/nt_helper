import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/wav_metadata.dart';

void main() {
  group('WavMetadataReader', () {
    test('reads PCM waveform peaks and first smpl loop', () {
      final bytes = _pcm16WavWithLoop(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
        loopStart: 2,
        loopEnd: 6,
      );

      final overview = WavMetadataReader.parse(bytes, peakCount: 4);

      expect(overview, isNotNull);
      expect(overview!.sampleRate, 44100);
      expect(overview.frameCount, 8);
      expect(overview.loopStart, 2);
      expect(overview.loopEnd, 6);
      expect(overview.peaks, hasLength(4));
      expect(overview.peaks.first.min, lessThan(0));
      expect(overview.peaks[2].max, greaterThan(0.9));
      expect(overview.zeroCrossings, containsAll([2, 6]));
      expect(overview.nearestZeroCrossing(3, searchRadius: 4), 2);
    });

    test('writes smpl loop metadata', () {
      final bytes = _pcm16Wav(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
      );

      final updated = WavMetadataWriter.writeSmplLoop(
        bytes,
        loopStart: 1,
        loopEnd: 5,
      );
      final overview = WavMetadataReader.parse(updated);

      expect(overview, isNotNull);
      expect(overview!.loopStart, 1);
      expect(overview.loopEnd, 5);
      expect(overview.frameCount, 8);
    });

    test('replaces existing smpl loop metadata', () {
      final bytes = _pcm16WavWithLoop(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
        loopStart: 2,
        loopEnd: 6,
      );

      final updated = WavMetadataWriter.writeSmplLoop(
        bytes,
        loopStart: 3,
        loopEnd: 7,
      );
      final overview = WavMetadataReader.parse(updated);

      expect(overview, isNotNull);
      expect(overview!.loopStart, 3);
      expect(overview.loopEnd, 7);
      expect(overview.frameCount, 8);
    });

    test('removes existing smpl loop metadata', () {
      final bytes = _pcm16WavWithLoop(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
        loopStart: 2,
        loopEnd: 6,
      );

      final updated = WavMetadataWriter.removeSmplLoop(bytes);
      final overview = WavMetadataReader.parse(updated);

      expect(overview, isNotNull);
      expect(overview!.loopStart, isNull);
      expect(overview.loopEnd, isNull);
      expect(overview.frameCount, 8);
    });

    test('renderPitchedPreview doubles pitch by halving frame count', () {
      final bytes = _pcm16Wav(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
      );

      final rendered = WavAudioRenderer.renderPitchedPreview(
        bytes,
        pitchRatio: 2,
      );
      final overview = WavMetadataReader.parse(rendered);

      expect(overview, isNotNull);
      expect(overview!.frameCount, 4);
      expect(overview.sampleRate, 44100);
      expect(overview.loopStart, isNull);
      expect(_pcm16Samples(rendered), hasLength(4));
    });

    test('renderPitchedPreview respects smpl loop points', () {
      final bytes = _pcm16WavWithLoop(
        samples: [1000, 2000, 3000, 4000],
        loopStart: 1,
        loopEnd: 2,
      );

      final rendered = WavAudioRenderer.renderPitchedPreview(
        bytes,
        pitchRatio: 1,
        renderedFrameLimit: 6,
      );

      expect(_pcm16Samples(rendered), [1000, 2000, 3000, 2000, 3000, 2000]);
    });

    test('renderPitchedPreview wraps when preview starts inside loop', () {
      final bytes = _pcm16WavWithLoop(
        samples: [1000, 2000, 3000, 4000, 5000],
        loopStart: 1,
        loopEnd: 3,
      );

      final rendered = WavAudioRenderer.renderPitchedPreview(
        bytes,
        pitchRatio: 1,
        previewStartFrame: 3,
        renderedFrameLimit: 5,
      );

      expect(_pcm16Samples(rendered), [4000, 2000, 3000, 4000, 2000]);
    }, tags: ['regression']);

    test('renderPitchedPreview lowers pitch by extending frame count', () {
      final bytes = _pcm16Wav(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
      );

      final rendered = WavAudioRenderer.renderPitchedPreview(
        bytes,
        pitchRatio: 0.5,
      );
      final overview = WavMetadataReader.parse(rendered);

      expect(overview, isNotNull);
      expect(overview!.frameCount, 16);
      expect(_pcm16Samples(rendered), hasLength(16));
    });

    test('renderPitchedPreview falls back to unity for invalid ratios', () {
      final bytes = _pcm16Wav(
        samples: [-32768, -12000, 0, 12000, 32767, 12000, 0, -12000],
      );

      final rendered = WavAudioRenderer.renderPitchedPreview(
        bytes,
        pitchRatio: double.nan,
      );
      final overview = WavMetadataReader.parse(rendered);

      expect(overview, isNotNull);
      expect(overview!.frameCount, 8);
    });

    test('renderPitchedPreview rejects invalid wav bytes', () {
      expect(
        () => WavAudioRenderer.renderPitchedPreview(
          Uint8List.fromList([1, 2, 3]),
          pitchRatio: 1,
        ),
        throwsFormatException,
      );
    });

    test('renders trim and adjusts existing loop metadata', () {
      final bytes = _pcm16WavWithLoop(
        samples: [-10000, -8000, -6000, -4000, -2000, 0, 2000, 4000],
        loopStart: 2,
        loopEnd: 6,
      );

      final rendered = WavAudioRenderer.render(
        bytes,
        const WavRenderOptions(trimStartFrame: 2, trimEndFrame: 5),
      );
      final overview = WavMetadataReader.parse(rendered);

      expect(overview, isNotNull);
      expect(overview!.frameCount, 4);
      expect(overview.loopStart, 0);
      expect(overview.loopEnd, 3);
      expect(_pcm16Samples(rendered), [-6000, -4000, -2000, 0]);
    });

    test('renders trim start at the exact requested frame', () {
      final bytes = _pcm16Wav(samples: [100, 200, 300, 400, 500]);

      final rendered = WavAudioRenderer.render(
        bytes,
        const WavRenderOptions(trimStartFrame: 1, trimEndFrame: 3),
      );

      expect(_pcm16Samples(rendered), [200, 300, 400]);
    });

    test('renders fades, gain, and normalize', () {
      final bytes = _pcm16Wav(samples: [1000, 4000, 8000, 12000, 16000]);

      final rendered = WavAudioRenderer.render(
        bytes,
        const WavRenderOptions(
          trimStartFrame: 0,
          trimEndFrame: 4,
          fadeInFrames: 2,
          fadeOutFrames: 2,
          fadeInCurve: WavFadeCurve.linear,
          fadeOutCurve: WavFadeCurve.linear,
          gainDb: 6,
          normalizePeakDb: -6,
        ),
      );
      final samples = _pcm16Samples(rendered);

      expect(samples, hasLength(5));
      expect(samples.first.abs(), lessThan(samples[1].abs()));
      expect(samples.last.abs(), lessThan(samples[3].abs()));
      expect(
        samples.map((sample) => sample.abs()).reduce((a, b) => a > b ? a : b),
        closeTo(16422, 2),
      );
    });

    test('fade strength uses curve-specific shaping', () {
      final bytes = _pcm16Wav(samples: [10000, 10000, 10000]);

      List<int> renderAt(double strength) {
        final rendered = WavAudioRenderer.render(
          bytes,
          WavRenderOptions(
            trimStartFrame: 0,
            trimEndFrame: 2,
            fadeInFrames: 2,
            fadeInCurve: WavFadeCurve.exponential,
            fadeInStrength: strength,
          ),
        );
        return _pcm16Samples(rendered);
      }

      expect(renderAt(0)[1], 5000);
      expect(renderAt(0.5)[1], 2500);
      expect(renderAt(1)[1], lessThan(renderAt(0.5)[1]));
      expect(
        WavFadeShaper.apply(0.5, WavFadeCurve.equalPower),
        closeTo(0.7071, 0.0001),
      );
      expect(
        WavFadeShaper.apply(0.5, WavFadeCurve.equalPower, strength: 1),
        closeTo(0.8660, 0.0001),
      );
      expect(WavFadeShaper.apply(0.5, WavFadeCurve.linear, strength: 1), 0.5);
      expect(
        WavFadeShaper.apply(0.25, WavFadeCurve.sCurve, strength: 1),
        lessThan(WavFadeShaper.apply(0.25, WavFadeCurve.sCurve)),
      );
      expect(
        WavFadeShaper.apply(0.25, WavFadeCurve.sCurve, strength: 1),
        greaterThan(0.07),
      );
      expect(
        WavFadeShaper.apply(0.75, WavFadeCurve.sCurve, strength: 1),
        greaterThan(WavFadeShaper.apply(0.75, WavFadeCurve.sCurve)),
      );
      expect(
        WavFadeShaper.apply(0.75, WavFadeCurve.sCurve, strength: 1),
        lessThan(0.93),
      );
    });
  });
}

Uint8List _pcm16Wav({required List<int> samples}) {
  final fmtChunk = BytesBuilder()
    ..add(_ascii('fmt '))
    ..add(_u32(16))
    ..add(_u16(1))
    ..add(_u16(1))
    ..add(_u32(44100))
    ..add(_u32(44100 * 2))
    ..add(_u16(2))
    ..add(_u16(16));

  final sampleData = BytesBuilder();
  for (final sample in samples) {
    sampleData.add(_i16(sample));
  }
  final dataBytes = sampleData.toBytes();
  final dataChunk = BytesBuilder()
    ..add(_ascii('data'))
    ..add(_u32(dataBytes.length))
    ..add(dataBytes);

  final body = BytesBuilder()
    ..add(_ascii('WAVE'))
    ..add(fmtChunk.toBytes())
    ..add(dataChunk.toBytes());
  final bodyBytes = body.toBytes();

  return (BytesBuilder()
        ..add(_ascii('RIFF'))
        ..add(_u32(bodyBytes.length))
        ..add(bodyBytes))
      .toBytes();
}

Uint8List _pcm16WavWithLoop({
  required List<int> samples,
  required int loopStart,
  required int loopEnd,
}) {
  final fmtChunk = BytesBuilder()
    ..add(_ascii('fmt '))
    ..add(_u32(16))
    ..add(_u16(1))
    ..add(_u16(1))
    ..add(_u32(44100))
    ..add(_u32(44100 * 2))
    ..add(_u16(2))
    ..add(_u16(16));

  final smplChunk = BytesBuilder()
    ..add(_ascii('smpl'))
    ..add(_u32(60))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(60))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(1))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(0))
    ..add(_u32(loopStart))
    ..add(_u32(loopEnd))
    ..add(_u32(0))
    ..add(_u32(0));

  final sampleData = BytesBuilder();
  for (final sample in samples) {
    sampleData.add(_i16(sample));
  }
  final dataBytes = sampleData.toBytes();
  final dataChunk = BytesBuilder()
    ..add(_ascii('data'))
    ..add(_u32(dataBytes.length))
    ..add(dataBytes);

  final body = BytesBuilder()
    ..add(_ascii('WAVE'))
    ..add(fmtChunk.toBytes())
    ..add(smplChunk.toBytes())
    ..add(dataChunk.toBytes());
  final bodyBytes = body.toBytes();

  return (BytesBuilder()
        ..add(_ascii('RIFF'))
        ..add(_u32(bodyBytes.length))
        ..add(bodyBytes))
      .toBytes();
}

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

List<int> _pcm16Samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (id == 'data') {
      return [
        for (var i = start; i < start + size; i += 2)
          data.getInt16(i, Endian.little),
      ];
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  return const [];
}

Uint8List _u16(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _i16(int value) {
  final data = ByteData(2)..setInt16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}
