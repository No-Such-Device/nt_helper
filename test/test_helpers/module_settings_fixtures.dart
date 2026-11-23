import 'dart:typed_data';

import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/module_settings.dart';

Uint8List settingsGroupsPayload() => Uint8List.fromList([
  1,
  12,
  34,
  56,
  2,
  0,
  ...'Root'.codeUnits,
  0,
  2,
  1,
  3,
  0,
  9,
  3,
  ...'Engine'.codeUnits,
  0,
  1,
  0,
  5,
]);

Uint8List settingInfoPayload(
  int id, {
  int type = 0,
  int unit = 0,
  int flags = 0,
  int min = -100,
  int max = 100,
  int def = 0,
  int maxLength = 20,
  String? name,
  List<String> enums = const [],
}) => Uint8List.fromList([
  ...encode16(id),
  ...encode16(min),
  ...encode16(max),
  ...encode16(def),
  type,
  unit,
  flags,
  ...encode16(maxLength),
  ...(name ?? 'Setting $id').codeUnits,
  0,
  if (unit == 1) ...[
    enums.length,
    for (final s in enums) ...[...s.codeUnits, 0],
  ],
]);

ModuleSettingInfo settingInfo(
  int id, {
  int type = 0,
  int unit = 0,
  int flags = 0,
  int min = -100,
  int max = 100,
  int def = 0,
  String? name,
  List<String> enums = const [],
}) => ModuleSettingsCodec.info(
  settingInfoPayload(
    id,
    type: type,
    unit: unit,
    flags: flags,
    min: min,
    max: max,
    def: def,
    name: name,
    enums: enums,
  ),
);

Uint8List settingValuePayload(int id, int value, [String presentation = '']) =>
    Uint8List.fromList([
      ...encode16(id),
      ...encode16(value),
      ...presentation.codeUnits,
      0,
    ]);

ModuleSettingsState settingsScreenState({
  bool busy = false,
  String message = '',
  String? unavailable,
  String? error,
  bool draft = false,
}) {
  final info = settingInfo(5);
  return ModuleSettingsState(
    connectionId: 1,
    tree: ModuleSettingsCodec.groups(settingsGroupsPayload()),
    busy: busy,
    message: message,
    unavailableReason: unavailable,
    settings: {
      5: ModuleSettingEdit(
        info: info,
        observed: const ModuleSettingValue(0),
        draft: draft ? const ModuleSettingValue(4) : null,
        error: error,
      ),
      9: ModuleSettingEdit(
        info: settingInfo(9),
        observed: const ModuleSettingValue(0),
      ),
    },
  );
}
