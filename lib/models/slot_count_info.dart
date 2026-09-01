/// Slot count and optional firmware-reported bus topology returned by SysEx
/// response 0x60.
class SlotCountInfo {
  final int slotCount;
  final int? inputBusCount;
  final int? outputBusCount;
  final int? auxBusCount;

  const SlotCountInfo({
    required this.slotCount,
    this.inputBusCount,
    this.outputBusCount,
    this.auxBusCount,
  });

  bool get hasCompleteBusCounts =>
      inputBusCount != null && outputBusCount != null && auxBusCount != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlotCountInfo &&
          slotCount == other.slotCount &&
          inputBusCount == other.inputBusCount &&
          outputBusCount == other.outputBusCount &&
          auxBusCount == other.auxBusCount;

  @override
  int get hashCode =>
      Object.hash(slotCount, inputBusCount, outputBusCount, auxBusCount);
}
