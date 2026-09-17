import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/sysex/requests/request_memory_usage.dart';

void main() {
  test('encodes the exact 21-byte 0x39 request', () {
    final packet = RequestMemoryUsageMessage(
      sysExId: 0x2A,
      guidBytes: const [0x6E, 0x6F, 0x74, 0x65],
      specificationValues: const [-4, 4660, 0],
    ).encode();

    expect(packet, hasLength(21));
    expect(packet, [
      0xF0,
      0x00,
      0x21,
      0x27,
      0x6D,
      0x2A,
      0x39,
      0x6E,
      0x6F,
      0x74,
      0x65,
      0x03,
      0x7F,
      0x7C,
      0x00,
      0x24,
      0x34,
      0x00,
      0x00,
      0x00,
      0xF7,
    ]);
  });

  test('packs signed 16-bit specification boundaries', () {
    final packet = RequestMemoryUsageMessage(
      sysExId: 0,
      guidBytes: const [0x74, 0x65, 0x73, 0x74],
      specificationValues: const [-0x8000, 0x7FFF, 0],
    ).encode();

    expect(packet.sublist(11, 20), [
      0x02,
      0x00,
      0x00,
      0x01,
      0x7F,
      0x7F,
      0x00,
      0x00,
      0x00,
    ]);
  });

  test('rejects a non-four-byte or non-7-bit GUID', () {
    expect(
      () => RequestMemoryUsageMessage(
        sysExId: 0,
        guidBytes: const [1, 2, 3],
        specificationValues: const [0, 0, 0],
      ).encode(),
      throwsArgumentError,
    );
    expect(
      () => RequestMemoryUsageMessage(
        sysExId: 0,
        guidBytes: const [1, 2, 3, 0x80],
        specificationValues: const [0, 0, 0],
      ).encode(),
      throwsArgumentError,
    );
  });

  test('rejects a malformed specification vector', () {
    expect(
      () => RequestMemoryUsageMessage(
        sysExId: 0,
        guidBytes: const [1, 2, 3, 4],
        specificationValues: const [0, 0],
      ).encode(),
      throwsArgumentError,
    );
    expect(
      () => RequestMemoryUsageMessage(
        sysExId: 0,
        guidBytes: const [1, 2, 3, 4],
        specificationValues: const [0, 0, 0x8000],
      ).encode(),
      throwsArgumentError,
    );
  });
}
