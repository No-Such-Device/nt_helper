import 'dart:typed_data';

import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/sysex/sysex_message.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

/// Sets a slot's visual treatment in the disting NT overview (firmware 1.18+).
class SetAlgorithmVisualStyleMessage extends SysexMessage
    implements HasAlgorithmIndex {
  @override
  final int algorithmIndex;
  final AlgorithmVisualStyle style;

  SetAlgorithmVisualStyleMessage({
    required super.sysExId,
    required this.algorithmIndex,
    required this.style,
  });

  @override
  Uint8List encode() {
    return Uint8List.fromList([
      ...buildHeader(sysExId),
      DistingNTRequestMessageType.setAlgorithmVisualStyle.value,
      algorithmIndex & 0x7F,
      ...style.encodePayload(),
      ...buildFooter(),
    ]);
  }
}
