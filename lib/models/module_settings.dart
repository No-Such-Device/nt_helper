import 'package:flutter/foundation.dart';

@immutable
final class ModuleSettingChild {
  const ModuleSettingChild({required this.id, required this.isGroup});
  final int id;
  final bool isGroup;
}

@immutable
final class ModuleSettingsGroup {
  ModuleSettingsGroup({
    required this.id,
    required this.name,
    required List<ModuleSettingChild> children,
  }) : children = List.unmodifiable(children);
  final int id;
  final String name;
  final List<ModuleSettingChild> children;
}

@immutable
final class ModuleSettingsTree {
  ModuleSettingsTree({
    required List<int> opaqueHeader,
    required Map<int, ModuleSettingsGroup> groups,
  }) : opaqueHeader = List.unmodifiable(opaqueHeader),
       groups = Map.unmodifiable(groups);
  final List<int> opaqueHeader;
  final Map<int, ModuleSettingsGroup> groups;
  List<int> get settingIds {
    final ids = <int>[];
    void visit(int id) {
      for (final child in groups[id]!.children) {
        if (child.isGroup) {
          visit(child.id);
        } else {
          ids.add(child.id);
        }
      }
    }

    visit(0);
    return List.unmodifiable(ids);
  }
}

@immutable
final class ModuleSettingInfo {
  ModuleSettingInfo({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.type,
    required this.unit,
    required this.flags,
    required this.maxLength,
    List<String> enums = const [],
  }) : enums = List.unmodifiable(enums);
  final int id;
  final String name;
  final int min;
  final int max;
  final int defaultValue;
  final int type;
  final int unit;
  final int flags;
  final int maxLength;
  final List<String> enums;
  bool get restartsEngine => flags & 1 != 0;
  bool get needsReboot => flags & 2 != 0;
  bool get isNumeric => type >= 0 && type <= 3;
  bool get writable => flags & ~3 == 0 && (isNumeric || type == 4 || type == 6);
  bool get isToggle =>
      unit == 1 &&
      enums.length == 2 &&
      ((enums[0] == 'Off' && enums[1] == 'On') ||
          (enums[0] == 'No' && enums[1] == 'Yes'));
  String? validate(ModuleSettingValue value) {
    if (!writable) return 'This setting is read only.';
    if (type == 4) {
      if (value.value is! String) return 'Enter a name.';
      final name = value.value as String;
      if (name.codeUnits.any((c) => c < 32 || c > 126)) {
        return 'Use printable ASCII characters only.';
      }
      if (name.length > maxLength) return 'Use at most $maxLength characters.';
    } else if (type == 6) {
      if (value.value is! BigInt ||
          (value.value as BigInt).isNegative ||
          (value.value as BigInt).bitLength > 64) {
        return 'Choose a 64-bit value.';
      }
    } else {
      if (value.value is! int) return 'Enter a whole number.';
      final number = value.value as int;
      if (number < min || number > max) {
        return 'Enter a value from $min to $max.';
      }
      if (unit == 1 && (number < 0 || number >= enums.length)) {
        return 'Choose a listed value.';
      }
    }
    return null;
  }
}

/// BigInt preserves all 64 bits on native and web runtimes.
@immutable
final class ModuleSettingValue {
  const ModuleSettingValue(this.value, {this.presentation = ''});
  final Object value;
  final String presentation;
  bool sameValue(ModuleSettingValue other) => value == other.value;
}

enum ModuleSettingWritePhase { beforeSend, send, readback }

final class ModuleSettingWriteException implements Exception {
  const ModuleSettingWriteException(this.id, this.phase, this.cause);
  final int id;
  final ModuleSettingWritePhase phase;
  final Object cause;
  bool get mutationMayHaveOccurred =>
      phase != ModuleSettingWritePhase.beforeSend;
  @override
  String toString() => switch (phase) {
    ModuleSettingWritePhase.beforeSend =>
      'Pre-write read failed for setting $id. No change was sent. $cause',
    ModuleSettingWritePhase.send =>
      'Sending setting $id failed; delivery is unknown. $cause',
    ModuleSettingWritePhase.readback =>
      'Readback failed after sending setting $id. $cause',
  };
}

@immutable
final class ModuleSettingEdit {
  const ModuleSettingEdit({
    required this.info,
    required this.observed,
    this.draft,
    this.error,
    this.uncertain = false,
    this.refreshRequired = false,
  });
  final ModuleSettingInfo info;
  final ModuleSettingValue observed;
  final ModuleSettingValue? draft;
  final String? error;
  final bool uncertain;
  final bool refreshRequired;
  bool get needsRefresh => uncertain || refreshRequired;
  ModuleSettingValue get displayed => draft ?? observed;
  bool get changed => draft != null && !draft!.sameValue(observed);
}

@immutable
final class ModuleSettingsState {
  ModuleSettingsState({
    this.connectionId = 0,
    this.unavailableReason,
    this.tree,
    Map<int, ModuleSettingEdit> settings = const {},
    this.busy = false,
    this.message = '',
    this.changedOnModule = false,
    this.actionUncertain = false,
  }) : settings = Map.unmodifiable(settings);
  final int connectionId;
  final String? unavailableReason;
  final ModuleSettingsTree? tree;
  final Map<int, ModuleSettingEdit> settings;
  final bool busy;
  final String message;
  final bool changedOnModule;
  final bool actionUncertain;
  bool get ready => unavailableReason == null && tree != null && !busy;
  bool get hasDrafts => settings.values.any(
    (s) => s.changed || s.error != null && s.draft != null,
  );
  bool get hasUncertainty =>
      actionUncertain || settings.values.any((s) => s.uncertain);
  bool canApplyGroup(int id) {
    if (!ready || actionUncertain || tree == null) return false;
    final changes =
        tree!.groups[id]?.children
            .where((c) => !c.isGroup)
            .map((c) => settings[c.id]!)
            .where((e) => e.changed && !e.needsRefresh)
            .toList() ??
        [];
    return changes.isNotEmpty &&
        changes.every((e) => e.info.validate(e.displayed) == null);
  }

  bool get canCommit =>
      ready &&
      changedOnModule &&
      !hasDrafts &&
      !hasUncertainty &&
      !settings.values.any((e) => e.needsRefresh);
}
