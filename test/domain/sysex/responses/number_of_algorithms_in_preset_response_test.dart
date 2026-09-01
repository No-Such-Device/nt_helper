import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/sysex/responses/number_of_algorithms_in_preset_response.dart';
import 'package:nt_helper/models/slot_count_info.dart';

void main() {
  group('NumberOfAlgorithmsInPresetResponse', () {
    test('parses the legacy slot-count payload', () {
      expect(
        NumberOfAlgorithmsInPresetResponse(Uint8List.fromList([8])).parse(),
        const SlotCountInfo(slotCount: 8),
      );
    });

    test('parses all bus counts from the extended payload', () {
      expect(
        NumberOfAlgorithmsInPresetResponse(
          Uint8List.fromList([8, 4, 3, 5]),
        ).parse(),
        const SlotCountInfo(
          slotCount: 8,
          inputBusCount: 4,
          outputBusCount: 3,
          auxBusCount: 5,
        ),
      );
    });

    test('ignores partial bus counts', () {
      expect(
        NumberOfAlgorithmsInPresetResponse(
          Uint8List.fromList([8, 4, 3]),
        ).parse(),
        const SlotCountInfo(slotCount: 8),
      );
    });

    test('keeps the first four values when trailing data is present', () {
      expect(
        NumberOfAlgorithmsInPresetResponse(
          Uint8List.fromList([8, 4, 3, 5, 99]),
        ).parse(),
        const SlotCountInfo(
          slotCount: 8,
          inputBusCount: 4,
          outputBusCount: 3,
          auxBusCount: 5,
        ),
      );
    });

    test('leaves invalid seven-bit counts for profile validation', () {
      expect(
        NumberOfAlgorithmsInPresetResponse(
          Uint8List.fromList([8, 128, 3, 5]),
        ).parse(),
        const SlotCountInfo(
          slotCount: 8,
          inputBusCount: 128,
          outputBusCount: 3,
          auxBusCount: 5,
        ),
      );
    });
  });
}
