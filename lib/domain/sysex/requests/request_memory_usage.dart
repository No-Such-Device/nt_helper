import 'dart:typed_data';

import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/sysex_message.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

/// Requests the memory impact report for a catalogue-derived algorithm tuple.
final class RequestMemoryUsageMessage extends SysexMessage {
  RequestMemoryUsageMessage({
    required super.sysExId,
    required List<int> guidBytes,
    required List<int> specificationValues,
  }) : guidBytes = List<int>.unmodifiable(guidBytes),
       specificationValues = List<int>.unmodifiable(specificationValues);

  final List<int> guidBytes;
  final List<int> specificationValues;

  @override
  Uint8List encode() {
    if (guidBytes.length != 4 ||
        guidBytes.any((byte) => byte < 0 || byte > 0x7F)) {
      throw ArgumentError.value(
        guidBytes,
        'guidBytes',
        'must contain exactly four 7-bit bytes',
      );
    }
    if (specificationValues.length != 3 ||
        specificationValues.any((value) => value < -0x8000 || value > 0x7FFF)) {
      throw ArgumentError.value(
        specificationValues,
        'specificationValues',
        'must contain exactly three signed 16-bit values',
      );
    }

    return Uint8List.fromList([
      ...buildHeader(sysExId),
      DistingNTRequestMessageType.requestMemoryUsage.value,
      ...guidBytes,
      for (final value in specificationValues) ...[
        (value >> 14) & 0x03,
        (value >> 7) & 0x7F,
        value & 0x7F,
      ],
      ...buildFooter(),
    ]);
  }
}
