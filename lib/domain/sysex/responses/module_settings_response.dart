import 'dart:typed_data';

import 'package:nt_helper/domain/sysex/responses/sysex_response.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';

final class ModuleSettingsGroupsResponse extends SysexResponse {
  ModuleSettingsGroupsResponse(super.data);
  @override
  dynamic parse() => ModuleSettingsCodec.groups(data);
}

final class ModuleSettingInfoResponse extends SysexResponse {
  ModuleSettingInfoResponse(super.data);
  @override
  dynamic parse() => ModuleSettingsCodec.info(data);
}

final class ModuleSettingValueResponse extends SysexResponse {
  ModuleSettingValueResponse(super.data);
  @override
  Uint8List parse() => Uint8List.fromList(data);
}
