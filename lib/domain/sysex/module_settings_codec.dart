import 'dart:typed_data';

import 'package:nt_helper/domain/sysex/sysex_utils.dart';
import 'package:nt_helper/models/module_settings.dart';

/// Protocol v1 from Os' preset editor, commit 82c23673b7e63371df60a59951ab13182cf703ca.
abstract final class ModuleSettingsCodec {
  static Uint8List packet(
    int sysExId,
    int command, [
    List<int> payload = const [],
  ]) {
    if (sysExId < 0 ||
        sysExId > 127 ||
        command < 0x63 ||
        command > 0x67 ||
        payload.any((b) => b < 0 || b > 127) ||
        payload.length + 8 > 1024) {
      throw ArgumentError('Invalid module settings packet.');
    }
    return Uint8List.fromList([
      ...buildHeader(sysExId),
      command,
      ...payload,
      ...buildFooter(),
    ]);
  }

  static List<int> settingId(int id) {
    if (id < 0 || id > 32767) {
      throw RangeError.range(id, 0, 32767, 'setting ID');
    }
    return encode16(id);
  }

  static ModuleSettingsTree groups(Uint8List payload) {
    final r = _SettingsReader(payload);
    final version = r.byte();
    if (version != 1) {
      throw UnsupportedError('Unsupported settings protocol version $version.');
    }
    final header = [r.byte(), r.byte(), r.byte()];
    final count = r.byte();
    final groups = <int, ModuleSettingsGroup>{};
    for (var i = 0; i < count; i++) {
      final id = r.byte();
      final name = r.string();
      final children = <ModuleSettingChild>[];
      final size = r.byte();
      for (var c = 0; c < size; c++) {
        final kind = r.byte();
        if (kind > 1) {
          throw const FormatException('Unknown settings child kind.');
        }
        children.add(ModuleSettingChild(id: r.byte(), isGroup: kind == 1));
      }
      if (groups.containsKey(id)) {
        throw const FormatException('Duplicate settings group.');
      }
      groups[id] = ModuleSettingsGroup(id: id, name: name, children: children);
    }
    r.end();
    if (!groups.containsKey(0)) {
      throw const FormatException('Missing settings root.');
    }
    final visited = <int>{};
    final settingIds = <int>{};
    void visit(int id) {
      if (!visited.add(id) || !groups.containsKey(id)) {
        throw const FormatException(
          'Cyclic, repeated, or missing settings group.',
        );
      }
      for (final child in groups[id]!.children) {
        if (child.isGroup) {
          visit(child.id);
        } else if (!settingIds.add(child.id)) {
          throw const FormatException('Duplicate setting.');
        }
      }
    }

    visit(0);
    if (visited.length != groups.length) {
      throw const FormatException('Unreachable settings group.');
    }
    return ModuleSettingsTree(opaqueHeader: header, groups: groups);
  }

  static ModuleSettingInfo info(Uint8List payload) {
    final r = _SettingsReader(payload);
    final id = r.short();
    final min = r.short(), max = r.short(), def = r.short();
    final type = r.byte(),
        unit = r.byte(),
        flags = r.byte(),
        maxLength = r.short();
    final name = r.string();
    final enums = <String>[];
    if (unit == 1) {
      final count = r.byte();
      for (var i = 0; i < count; i++) {
        enums.add(r.string());
      }
    }
    r.end();
    if (id < 0 ||
        maxLength < 0 ||
        min > max ||
        def < min ||
        def > max ||
        unit == 1 && (enums.isEmpty || min < 0 || max >= enums.length)) {
      throw const FormatException('Inconsistent setting metadata.');
    }
    return ModuleSettingInfo(
      id: id,
      name: name,
      min: min,
      max: max,
      defaultValue: def,
      type: type,
      unit: unit,
      flags: flags,
      maxLength: maxLength,
      enums: enums,
    );
  }

  static ModuleSettingValue value(Uint8List payload, ModuleSettingInfo info) {
    final r = _SettingsReader(payload);
    if (r.short() != info.id) throw const FormatException('Wrong setting ID.');
    late final ModuleSettingValue value;
    if (info.type == 4 || info.type == 5) {
      final name = r.string();
      if (info.type == 4 && name.length > info.maxLength) {
        throw const FormatException('Name exceeds metadata limit.');
      }
      value = ModuleSettingValue(info.type == 4 ? name.trimRight() : name);
    } else if (info.type == 6) {
      var bits = BigInt.zero;
      for (var i = 0; i < 10; i++) {
        final limb = r.byte();
        if (i == 9 && limb > 1) {
          throw const FormatException('Bitset exceeds 64 bits.');
        }
        bits |= BigInt.from(limb) << (7 * i);
      }
      value = ModuleSettingValue(bits);
    } else {
      final number = r.short();
      final text = r.string();
      if (number < info.min ||
          number > info.max ||
          info.unit == 1 && (number < 0 || number >= info.enums.length)) {
        throw const FormatException('Setting value outside metadata range.');
      }
      value = ModuleSettingValue(number, presentation: text);
    }
    r.end();
    return value;
  }

  static List<int> write(ModuleSettingInfo info, ModuleSettingValue value) {
    final error = info.validate(value);
    if (error != null) throw ArgumentError(error);
    final bytes = <int>[...settingId(info.id)];
    if (info.type == 4) {
      bytes.addAll([...(value.value as String).codeUnits, 0]);
    } else if (info.type == 6) {
      final bits = value.value as BigInt;
      bytes.addAll(
        List.generate(
          10,
          (i) => ((bits >> (7 * i)) & BigInt.from(127)).toInt(),
        ),
      );
    } else {
      bytes.addAll(encode16(value.value as int));
    }
    return bytes;
  }
}

final class _SettingsReader {
  _SettingsReader(this.data) {
    if (data.length > 1016 || data.any((b) => b > 127)) {
      throw const FormatException(
        'Settings payload must fit a 1024-byte, MIDI-safe packet.',
      );
    }
  }
  final Uint8List data;
  int offset = 0;
  int byte() {
    if (offset >= data.length) {
      throw const FormatException('Truncated settings response.');
    }
    return data[offset++];
  }

  int short() {
    final high = byte(), mid = byte(), low = byte();
    if (high > 3) throw const FormatException('Invalid signed 16-bit value.');
    final raw = (high << 14) | (mid << 7) | low;
    return raw >= 32768 ? raw - 65536 : raw;
  }

  String string() {
    final bytes = <int>[];
    while (true) {
      final b = byte();
      if (b == 0) return String.fromCharCodes(bytes);
      bytes.add(b);
    }
  }

  void end() {
    if (offset != data.length) {
      throw const FormatException('Unexpected settings response data.');
    }
  }
}
