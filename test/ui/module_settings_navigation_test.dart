import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/ui/module_settings_navigation.dart';

ModuleSettingsTree menu({bool rootSetting = true}) => ModuleSettingsTree(
  opaqueHeader: [0, 0, 0],
  groups: {
    0: ModuleSettingsGroup(
      id: 0,
      name: '',
      children: [
        const ModuleSettingChild(id: 3, isGroup: true),
        if (rootSetting) const ModuleSettingChild(id: 9, isGroup: false),
        const ModuleSettingChild(id: 2, isGroup: true),
      ],
    ),
    3: ModuleSettingsGroup(
      id: 3,
      name: 'Display',
      children: const [
        ModuleSettingChild(id: 4, isGroup: true),
        ModuleSettingChild(id: 5, isGroup: false),
      ],
    ),
    4: ModuleSettingsGroup(
      id: 4,
      name: 'Labels',
      children: const [ModuleSettingChild(id: 7, isGroup: false)],
    ),
    2: ModuleSettingsGroup(id: 2, name: '', children: const []),
  },
);

void main() {
  test('initial selection follows first setting in depth-first menu order', () {
    final n = ModuleSettingsNavigation(menu());
    expect(n.initial, 4);
    expect(n.ancestors(n.initial), {3});
    expect(n.rows(n.ancestors(n.initial)), [(0, 0), (3, 0), (4, 1), (2, 0)]);
    expect(n.direct(3), [5]);
    expect(n.descendants(3), [5, 7]);
  });
  test('root is a non-collapsing peer only if it owns settings', () {
    expect(ModuleSettingsNavigation(menu(rootSetting: false)).rows({}), [
      (3, 0),
      (2, 0),
    ]);
    final n = ModuleSettingsNavigation(menu());
    expect(n.rows({0}), n.rows({}));
    expect(n.name(0), 'NT Settings');
    expect(n.name(2), 'Group 2');
  });
  test('collapsed ancestor takes selection; missing selection falls back', () {
    final n = ModuleSettingsNavigation(menu());
    expect(n.effective(4, {}), 3);
    expect(n.effective(4, {3}), 4);
    expect(n.effective(999, {3}), 4);
    expect(n.effective(0, {3}), 0);
  });
  test('empty tree has no selection', () {
    final n = ModuleSettingsNavigation(
      ModuleSettingsTree(
        opaqueHeader: [0, 0, 0],
        groups: {0: ModuleSettingsGroup(id: 0, name: '', children: const [])},
      ),
    );
    expect(n.initial, isNull);
    expect(n.effective(null, {}), isNull);
    expect(n.rows({}), isEmpty);
  });
  test('first direct root setting selects root, not a child group', () {
    final n = ModuleSettingsNavigation(
      ModuleSettingsTree(
        opaqueHeader: [0, 0, 0],
        groups: {
          0: ModuleSettingsGroup(
            id: 0,
            name: '',
            children: const [ModuleSettingChild(id: 9, isGroup: false)],
          ),
        },
      ),
    );
    expect(n.initial, 0);
    expect(n.ancestors(n.initial), isEmpty);
  });
}
