import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_response.dart';

void main() {
  group('AlgorithmResponse', () {
    test('parses firmware 1.18 visual style after the slot name', () {
      final algorithm = AlgorithmResponse(
        Uint8List.fromList([
          3,
          ...'ABCD'.codeUnits,
          ...'Styled delay'.codeUnits,
          0,
          1,
          2,
          4,
          1,
          0,
          4,
        ]),
      ).parse();

      expect(algorithm.algorithmIndex, 3);
      expect(algorithm.guid, 'ABCD');
      expect(algorithm.name, 'Styled delay');
      expect(
        algorithm.visualStyle,
        const AlgorithmVisualStyle(
          leftIndent: 2,
          rightIndent: 4,
          lineAbove: true,
          bracket: AlgorithmVisualBracket.openAndClose,
        ),
      );
    });

    test('keeps legacy responses without a style block compatible', () {
      final algorithm = AlgorithmResponse(
        Uint8List.fromList([0, ...'TEST'.codeUnits, ...'Legacy'.codeUnits, 0]),
      ).parse();

      expect(algorithm.name, 'Legacy');
      expect(algorithm.visualStyle, isNull);
    });

    test('parses style after a full 24-byte name without a terminator', () {
      const name = '123456789012345678901234';
      final algorithm = AlgorithmResponse(
        Uint8List.fromList([
          0,
          ...'TEST'.codeUnits,
          ...name.codeUnits,
          1,
          0,
          0,
          0,
          1,
          2,
        ]),
      ).parse();

      expect(algorithm.name, name);
      expect(
        algorithm.visualStyle,
        const AlgorithmVisualStyle(
          lineBelow: true,
          bracket: AlgorithmVisualBracket.close,
        ),
      );
    });

    test('ignores unsupported or truncated style versions', () {
      for (final suffix in <List<int>>[
        [2, 1, 2, 1, 1, 3],
        [1, 1, 2],
      ]) {
        final algorithm = AlgorithmResponse(
          Uint8List.fromList([
            0,
            ...'TEST'.codeUnits,
            ...'Safe'.codeUnits,
            0,
            ...suffix,
          ]),
        ).parse();

        expect(algorithm.name, 'Safe');
        expect(algorithm.visualStyle, isNull);
      }
    });
  });
}
