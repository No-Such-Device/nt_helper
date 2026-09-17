import 'package:nt_helper/domain/sysex/responses/sysex_response.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
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
    final specifications = visualStyle == null
        ? null
        : _tryParseSpecifications(styleOffset + 6);

    return Algorithm(
      algorithmIndex: data[0].toInt(),
      guid: String.fromCharCodes(data.sublist(1, 5)),
      name: String.fromCharCodes(data.sublist(nameOffset, nameEnd)).trim(),
      specifications: specifications ?? const [],
      hasAuthoritativeSpecifications: specifications != null,
      visualStyle: visualStyle,
    );
  }

  List<int>? _tryParseSpecifications(int offset) {
    if (offset < 0 || offset >= data.length) return null;

    final count = data[offset];
    if (count > 0x7F || data.length != offset + 1 + count * 3) return null;

    final specifications = <int>[];
    for (var index = 0; index < count; index++) {
      final valueOffset = offset + 1 + index * 3;
      if (data[valueOffset] > 0x03 ||
          data[valueOffset + 1] > 0x7F ||
          data[valueOffset + 2] > 0x7F) {
        return null;
      }
      specifications.add(decode16(data, valueOffset));
    }
    return List<int>.unmodifiable(specifications);
  }
}
