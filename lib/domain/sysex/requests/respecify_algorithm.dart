import 'dart:typed_data';

import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/sysex_message.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

/// Respecifies the algorithm already occupying [algorithmIndex].
final class RespecifyAlgorithmMessage extends SysexMessage
    implements HasAlgorithmIndex {
  RespecifyAlgorithmMessage({
    required super.sysExId,
    required this.algorithmIndex,
    required List<int> specifications,
  }) : specifications = List<int>.unmodifiable(specifications);

  @override
  final int algorithmIndex;
  final List<int> specifications;

  @override
  Uint8List encode() {
    if (algorithmIndex < 0 || algorithmIndex > 0x7F) {
      throw ArgumentError.value(
        algorithmIndex,
        'algorithmIndex',
        'must be a zero-based 7-bit slot index',
      );
    }
    if (specifications.length > 0x7F) {
      throw ArgumentError.value(
        specifications.length,
        'specifications.length',
        'must fit in one 7-bit count byte',
      );
    }
    if (specifications.any((value) => value < -0x8000 || value > 0x7FFF)) {
      throw ArgumentError.value(
        specifications,
        'specifications',
        'must contain signed 16-bit values',
      );
    }

    return Uint8List.fromList([
      ...buildHeader(sysExId),
      DistingNTRequestMessageType.respecifyAlgorithm.value,
      algorithmIndex,
      specifications.length,
      for (final value in specifications) ...encode16(value),
      ...buildFooter(),
    ]);
  }
}
