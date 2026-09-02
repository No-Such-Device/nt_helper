import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/requests/set_algorithm_visual_style.dart';

void main() {
  group('SetAlgorithmVisualStyleMessage', () {
    test('matches the firmware 1.18 version-1 message layout', () {
      final encoded = SetAlgorithmVisualStyleMessage(
        sysExId: 7,
        algorithmIndex: 12,
        style: const AlgorithmVisualStyle(
          leftIndent: 2,
          rightIndent: 5,
          lineAbove: true,
          lineBelow: false,
          bracket: AlgorithmVisualBracket.line,
        ),
      ).encode();

      expect(encoded, [
        0xF0,
        0x00,
        0x21,
        0x27,
        0x6D,
        7,
        0x54,
        12,
        1,
        2,
        5,
        1,
        0,
        3,
        0xF7,
      ]);
    });

    test('keeps all payload bytes 7-bit safe', () {
      final encoded = SetAlgorithmVisualStyleMessage(
        sysExId: 127,
        algorithmIndex: 255,
        style: const AlgorithmVisualStyle(
          leftIndent: 15,
          rightIndent: 15,
          lineAbove: true,
          lineBelow: true,
          bracket: AlgorithmVisualBracket.openAndClose,
        ),
      ).encode();

      for (var index = 1; index < encoded.length - 1; index++) {
        expect(encoded[index], lessThan(0x80));
      }
      expect(encoded[7], 127);
    });
  });
}
