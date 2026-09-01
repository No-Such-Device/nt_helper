import 'package:nt_helper/domain/sysex/responses/sysex_response.dart';
import 'package:nt_helper/models/slot_count_info.dart';

class NumberOfAlgorithmsInPresetResponse extends SysexResponse {
  NumberOfAlgorithmsInPresetResponse(super.data);

  @override
  SlotCountInfo parse() {
    if (data.length >= 4) {
      return SlotCountInfo(
        slotCount: data[0],
        inputBusCount: data[1],
        outputBusCount: data[2],
        auxBusCount: data[3],
      );
    }
    return SlotCountInfo(slotCount: data[0]);
  }
}
