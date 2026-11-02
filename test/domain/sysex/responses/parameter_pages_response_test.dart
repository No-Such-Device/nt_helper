import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/sysex/responses/parameter_pages_response.dart';

void main() {
  group('ParameterPagesResponse', () {
    test('parses complete parameter pages', () {
      final response = ParameterPagesResponse(
        Uint8List.fromList([
          5, // algorithm index
          1, // page count
          ...'Main'.codeUnits,
          0,
          2, // parameter count
          0,
          1,
          0,
          2,
        ]),
      );

      final pages = response.parse();

      expect(pages.algorithmIndex, 5);
      expect(pages.pages, hasLength(1));
      expect(pages.pages.single.name, 'Main');
      expect(pages.pages.single.parameters, [1, 2]);
    });

    test('reports the page where the response ends mid-page', () {
      final response = ParameterPagesResponse(
        Uint8List.fromList([
          5,
          6,
          ...'Quantizer'.codeUnits,
          0,
          10,
          0,
          1,
          0,
          2,
          0,
          3,
          0,
          4,
          0,
          6,
          0,
          5,
          0,
          7,
          0,
          8,
          0,
          9,
          0,
          16,
          ...'Mask'.codeUnits,
          0,
        ]),
      );

      expect(
        response.parse,
        throwsA(
          isA<TruncatedParameterPagesException>()
              .having((e) => e.algorithmIndex, 'algorithmIndex', 5)
              .having((e) => e.expectedPages, 'expectedPages', 6)
              .having((e) => e.completedPages, 'completedPages', 1)
              .having((e) => e.truncatedPageName, 'truncatedPageName', 'Mask')
              .having((e) => e.payloadLength, 'payloadLength', 38),
        ),
      );
    });

    test('reports when a page name ends without a null terminator', () {
      final response = ParameterPagesResponse(
        Uint8List.fromList([
          5,
          2,
          ...'Quantizer'.codeUnits,
          0,
          0,
          ...'Ma'.codeUnits,
        ]),
      );

      expect(
        response.parse,
        throwsA(
          isA<TruncatedParameterPagesException>()
              .having((e) => e.algorithmIndex, 'algorithmIndex', 5)
              .having((e) => e.expectedPages, 'expectedPages', 2)
              .having((e) => e.completedPages, 'completedPages', 1)
              .having(
                (e) => e.truncatedPageName,
                'truncatedPageName',
                '<unterminated page name: Ma>',
              ),
        ),
      );
    }, tags: ['regression']);
  });
}
