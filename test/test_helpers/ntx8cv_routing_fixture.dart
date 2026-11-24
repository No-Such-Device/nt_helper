import 'package:nt_helper/models/module_settings.dart';

/// Observed NT v1.20.0beta catalogue, 2026-11-24; IDs deliberately relocated.
/// Source: Os' editor 82c23673 and captured Engine/NTX metadata, not NTX USB IDs.
ModuleSettingsState ntxSettings({
  int mode = 0,
  BigInt? mask,
  bool busy = false,
  bool uncertain = false,
  bool needsRefresh = false,
  int? draftMode,
  String? unavailable,
  List<String>? modes,
  int offset = 100,
  int connectionId = 1,
}) {
  final modeId = offset + 28;
  final maskId = offset + 30;
  ModuleSettingsGroup group(
    int id,
    String name,
    List<ModuleSettingChild> children,
  ) => ModuleSettingsGroup(id: id, name: name, children: children);
  ModuleSettingChild child(int id, bool isGroup) =>
      ModuleSettingChild(id: id, isGroup: isGroup);
  return ModuleSettingsState(
    connectionId: connectionId,
    busy: busy,
    unavailableReason: unavailable,
    actionUncertain: uncertain,
    tree: ModuleSettingsTree(
      opaqueHeader: [0, 0, 0],
      groups: {
        0: group(0, 'Menu', [child(12, true)]),
        12: group(12, 'Settings', [child(18, true)]),
        18: group(18, 'Engine', [child(19, true)]),
        19: group(19, 'NTX-8CV', [child(modeId, false), child(maskId, false)]),
      },
    ),
    settings: {
      modeId: ModuleSettingEdit(
        info: ModuleSettingInfo(
          id: modeId,
          name: 'Mode',
          min: 0,
          max: 2,
          defaultValue: 0,
          type: 0,
          unit: 1,
          flags: 1,
          maxLength: 0,
          enums:
              modes ?? ['CV (8x8)', 'Audio 32 bit (1x8)', 'Audio 16 bit (2x8)'],
        ),
        observed: ModuleSettingValue(mode),
        draft: draftMode == null ? null : ModuleSettingValue(draftMode),
      ),
      maskId: ModuleSettingEdit(
        info: ModuleSettingInfo(
          id: maskId,
          name: 'Channel enables',
          min: 0,
          max: 0,
          defaultValue: 0,
          type: 6,
          unit: 0,
          flags: 0,
          maxLength: 0,
        ),
        observed: ModuleSettingValue(mask ?? BigInt.from(255)),
        refreshRequired: needsRefresh,
      ),
    },
  );
}
