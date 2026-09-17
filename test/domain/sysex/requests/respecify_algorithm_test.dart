import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/sysex/requests/respecify_algorithm.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_response.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

void main() {
  group('RespecifyAlgorithmMessage', () {
    test('matches the approved Slot 3 Attenuverter example frame', () {
      final encoded = RespecifyAlgorithmMessage(
        sysExId: 0,
        algorithmIndex: 2,
        specifications: const [8],
      ).encode();

      expect(encoded, [
        0xF0,
        0x00,
        0x21,
        0x27,
        0x6D,
        0x00,
        0x3A,
        0x02,
        0x01,
        0x00,
        0x00,
        0x08,
        0xF7,
      ]);
    });

    test('encodes parsed signed boundaries with the configured SysEx ID', () {
      final returned = _parseReturnedSpecifications(const [
        0,
        8,
        32767,
        -32768,
        -1,
      ]);

      final encoded = RespecifyAlgorithmMessage(
        sysExId: 0x2A,
        algorithmIndex: 2,
        specifications: returned,
      ).encode();

      expect(encoded, [
        0xF0,
        0x00,
        0x21,
        0x27,
        0x6D,
        0x2A,
        0x3A,
        0x02,
        0x05,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x08,
        0x01,
        0x7F,
        0x7F,
        0x02,
        0x00,
        0x00,
        0x03,
        0x7F,
        0x7F,
        0xF7,
      ]);
    });

    test('uses each parsed list count and preserves its returned order', () {
      final cases = <(List<int>, List<int>)>[
        (
          const [8, -1],
          const [
            0xF0,
            0x00,
            0x21,
            0x27,
            0x6D,
            0x11,
            0x3A,
            0x02,
            0x02,
            0x00,
            0x00,
            0x08,
            0x03,
            0x7F,
            0x7F,
            0xF7,
          ],
        ),
        (
          const [-1, 0, 8],
          const [
            0xF0,
            0x00,
            0x21,
            0x27,
            0x6D,
            0x11,
            0x3A,
            0x02,
            0x03,
            0x03,
            0x7F,
            0x7F,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x08,
            0xF7,
          ],
        ),
      ];

      for (final (values, expected) in cases) {
        final returned = _parseReturnedSpecifications(values);
        final encoded = RespecifyAlgorithmMessage(
          sysExId: 0x11,
          algorithmIndex: 2,
          specifications: returned,
        ).encode();

        expect(encoded, expected);
      }
    });

    test('rejects payload fields that cannot be represented canonically', () {
      final messages = [
        RespecifyAlgorithmMessage(
          sysExId: 0,
          algorithmIndex: -1,
          specifications: const [],
        ),
        RespecifyAlgorithmMessage(
          sysExId: 0,
          algorithmIndex: 0x80,
          specifications: const [],
        ),
        RespecifyAlgorithmMessage(
          sysExId: 0,
          algorithmIndex: 0,
          specifications: const [0x8000],
        ),
        RespecifyAlgorithmMessage(
          sysExId: 0,
          algorithmIndex: 0,
          specifications: const [-0x8001],
        ),
        RespecifyAlgorithmMessage(
          sysExId: 0,
          algorithmIndex: 0,
          specifications: List<int>.filled(0x80, 0),
        ),
      ];

      for (final message in messages) {
        expect(message.encode, throwsArgumentError);
      }
    });
  });
}

List<int> _parseReturnedSpecifications(List<int> values) {
  final response = AlgorithmResponse(
    Uint8List.fromList([
      2,
      ...'TEST'.codeUnits,
      ...'Returned'.codeUnits,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      values.length,
      for (final value in values) ...encode16(value),
    ]),
  ).parse();

  expect(response.hasAuthoritativeSpecifications, isTrue);
  return response.specifications;
}
