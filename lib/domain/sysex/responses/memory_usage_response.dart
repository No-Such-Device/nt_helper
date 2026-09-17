import 'package:nt_helper/domain/sysex/responses/sysex_response.dart';
import 'package:nt_helper/models/memory_usage.dart';

/// Strict decoder for the 0x39 memory response payload.
///
/// The surrounding SysEx parser and scheduler validate the frame markers,
/// manufacturer, product prefix, selected device ID, and command. This decoder
/// validates the status byte and all twelve five-byte uint32 fields before
/// exposing only the four total/current pool pairs.
final class MemoryUsageResponse extends SysexResponse {
  MemoryUsageResponse(super.data);

  static const int _fieldCount = 12;
  static const int _encodedFieldLength = 5;
  static const int _expectedPayloadLength =
      1 + (_fieldCount * _encodedFieldLength);
  static const int _successStatus = 3;

  @override
  MemoryUsage parse() {
    if (data.length != _expectedPayloadLength) {
      throw FormatException(
        'Memory response payload must be exactly '
        '$_expectedPayloadLength bytes; got ${data.length}.',
      );
    }
    if (data.any((byte) => byte > 0x7F)) {
      throw const FormatException('Memory response data must be 7-bit clean.');
    }
    if (data[0] != _successStatus) {
      throw StateError(
        'Memory response status must be $_successStatus; got ${data[0]}.',
      );
    }

    final values = List<int>.generate(
      _fieldCount,
      (index) => _decodeUint32(1 + (index * _encodedFieldLength)),
      growable: false,
    );

    return MemoryUsage(
      sram: MemoryPoolUsage(total: values[0], current: values[4]),
      dram: MemoryPoolUsage(total: values[1], current: values[5]),
      dtc: MemoryPoolUsage(total: values[2], current: values[6]),
      itc: MemoryPoolUsage(total: values[3], current: values[7]),
    );
  }

  int _decodeUint32(int offset) {
    final b0 = data[offset];
    if (b0 > 0x0F) {
      throw FormatException(
        'Memory response integer at offset $offset exceeds uint32 range.',
      );
    }

    return (b0 << 28) |
        (data[offset + 1] << 21) |
        (data[offset + 2] << 14) |
        (data[offset + 3] << 7) |
        data[offset + 4];
  }
}
