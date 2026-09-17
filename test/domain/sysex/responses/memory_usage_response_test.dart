import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/response_factory.dart';
import 'package:nt_helper/domain/sysex/responses/memory_usage_response.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';
import 'package:nt_helper/models/memory_usage.dart';

void main() {
  group('MemoryUsageResponse', () {
    test('decodes unsigned totals and currents in protocol order', () {
      final response = MemoryUsageResponse(
        _payload([
          0,
          0xFFFFFFFF,
          100,
          50,
          0,
          0xFFFFFFFE,
          125,
          75,
          11,
          22,
          33,
          44,
        ]),
      );

      final result = response.parse();

      expect(result.sram.total, 0);
      expect(result.sram.current, 0);
      expect(result.sram.free, 0);
      expect(result.dram.total, 0xFFFFFFFF);
      expect(result.dram.current, 0xFFFFFFFE);
      expect(result.dram.free, 1);
      expect(result.dtc.total, 100);
      expect(result.dtc.current, 125);
      expect(result.dtc.free, -25);
      expect(result.itc.total, 50);
      expect(result.itc.current, 75);
      expect(result.itc.free, -25);
    });

    test(
      'ResponseFactory dispatches 0x39 without exposing required fields',
      () {
        final response = ResponseFactory.fromMessageType(
          DistingNTRespMessageType.respMemoryUsage,
          _payload(List<int>.generate(12, (index) => index + 1)),
        );

        expect(response, isA<MemoryUsageResponse>());
        final result = response!.parse() as MemoryUsage;
        expect(result.sram.total, 1);
        expect(result.itc.total, 4);
        expect(result.sram.current, 5);
        expect(result.itc.current, 8);
      },
    );

    test('rejects incomplete and overlong payloads', () {
      final valid = _payload(List<int>.filled(12, 0));

      expect(
        () => MemoryUsageResponse(valid.sublist(0, valid.length - 1)).parse(),
        throwsFormatException,
      );
      expect(
        () => MemoryUsageResponse(Uint8List.fromList([...valid, 0])).parse(),
        throwsFormatException,
      );
    });

    test('rejects non-status-3 payloads', () {
      final payload = _payload(List<int>.filled(12, 0))..[0] = 2;

      expect(() => MemoryUsageResponse(payload).parse(), throwsStateError);
    });

    test('rejects high-bit data', () {
      final payload = _payload(List<int>.filled(12, 0))..[17] = 0x80;

      expect(() => MemoryUsageResponse(payload).parse(), throwsFormatException);
    });

    test('rejects uint32 overflow in exposed and discarded fields', () {
      final exposedOverflow = _payload(List<int>.filled(12, 0))..[1] = 0x10;
      final requiredOverflow = _payload(List<int>.filled(12, 0))
        ..[1 + (11 * 5)] = 0x10;

      expect(
        () => MemoryUsageResponse(exposedOverflow).parse(),
        throwsFormatException,
      );
      expect(
        () => MemoryUsageResponse(requiredOverflow).parse(),
        throwsFormatException,
      );
    });
  });

  group('0x39 SysEx frame parsing', () {
    test('recognizes only the complete manufacturer/product frame', () {
      final frame = _frame(_payload(List<int>.filled(12, 0)));

      expect(frame, hasLength(69));
      final parsed = decodeDistingNTSysEx(frame);
      expect(parsed, isNotNull);
      expect(parsed!.sysExId, 0x2A);
      expect(parsed.messageType, DistingNTRespMessageType.respMemoryUsage);
      expect(parsed.payload, hasLength(61));

      final wrongManufacturer = Uint8List.fromList(frame)..[3] = 0x26;
      final wrongProduct = Uint8List.fromList(frame)..[4] = 0x6C;
      final badStart = Uint8List.fromList(frame)..[0] = 0;
      final badEnd = Uint8List.fromList(frame)..[68] = 0;

      expect(decodeDistingNTSysEx(wrongManufacturer), isNull);
      expect(decodeDistingNTSysEx(wrongProduct), isNull);
      expect(decodeDistingNTSysEx(badStart), isNull);
      expect(decodeDistingNTSysEx(badEnd), isNull);
    });

    test('does not mask high-bit device IDs or commands into a match', () {
      final frame = _frame(_payload(List<int>.filled(12, 0)));
      final highDevice = Uint8List.fromList(frame)..[5] = 0xAA;
      final highCommand = Uint8List.fromList(frame)..[6] = 0xB9;

      expect(decodeDistingNTSysEx(highDevice), isNull);
      expect(decodeDistingNTSysEx(highCommand), isNull);
    });
  });
}

Uint8List _payload(List<int> values) {
  assert(values.length == 12);
  return Uint8List.fromList([
    3,
    for (final value in values) ..._encodeUint32(value),
  ]);
}

List<int> _encodeUint32(int value) => [
  (value >> 28) & 0x0F,
  (value >> 21) & 0x7F,
  (value >> 14) & 0x7F,
  (value >> 7) & 0x7F,
  value & 0x7F,
];

Uint8List _frame(Uint8List payload) => Uint8List.fromList([
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6D,
  0x2A,
  0x39,
  ...payload,
  0xF7,
]);
