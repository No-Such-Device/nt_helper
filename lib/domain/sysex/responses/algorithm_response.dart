import 'package:nt_helper/domain/sysex/responses/sysex_response.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

class AlgorithmResponse extends SysexResponse {
  AlgorithmResponse(super.data);

  late final Algorithm algorithm;

  @override
  Algorithm parse() {
    const nameOffset = 5;
    const maximumNameLength = 24;
    final nameLimit = data.length < nameOffset + maximumNameLength
        ? data.length
        : nameOffset + maximumNameLength;
    var nameEnd = nameOffset;
    while (nameEnd < nameLimit && data[nameEnd] != 0) {
      nameEnd++;
    }
    final styleOffset = nameEnd < nameLimit ? nameEnd + 1 : nameLimit;
    final visualStyle = AlgorithmVisualStyle.tryParse(data, styleOffset);

    return Algorithm(
      algorithmIndex: data[0].toInt(),
      guid: String.fromCharCodes(data.sublist(1, 5)),
      name: String.fromCharCodes(data.sublist(nameOffset, nameEnd)).trim(),
      visualStyle: visualStyle,
    );
  }
}
