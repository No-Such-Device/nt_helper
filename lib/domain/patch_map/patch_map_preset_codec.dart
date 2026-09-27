import 'patch_map.dart';

/// Operates on one slot object, preserving all firmware-owned fields.
/// It does not send MIDI, load a preset, or maintain a second state store.
class PatchMapPresetCodec {
  static const algorithmGuid = 'ThPh';

  static PatchMap readSlot(Map<String, dynamic> slot) {
    _checkGuid(slot);
    if (!slot.containsKey('patch_helper')) return PatchMap.empty();
    final value = slot['patch_helper'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('patch_helper must be an object');
    }
    return PatchMap.fromJson(value);
  }

  static Map<String, dynamic> writeSlot(
    Map<String, dynamic> slot,
    PatchMap map,
  ) {
    // Reject newer or malformed existing data rather than overwrite it and
    // silently discard information this version cannot represent.
    readSlot(slot);
    return {...slot, 'patch_helper': map.toJson()};
  }

  static void _checkGuid(Map<String, dynamic> slot) {
    if (slot['guid'] != algorithmGuid) {
      throw const FormatException('Expected a Patch Helper algorithm slot');
    }
  }
}
