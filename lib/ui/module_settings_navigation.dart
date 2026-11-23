import 'package:nt_helper/models/module_settings.dart';

/// Menu-order navigation; the root is a peer only when it owns settings.
final class ModuleSettingsNavigation {
  ModuleSettingsNavigation(this.tree) {
    for (final group in tree.groups.values) {
      for (final child in group.children.where((c) => c.isGroup)) {
        parents[child.id] = group.id;
      }
    }
  }
  final ModuleSettingsTree tree;
  final parents = <int, int>{};
  List<int> direct(int id) => tree.groups[id]!.children
      .where((c) => !c.isGroup)
      .map((c) => c.id)
      .toList();
  List<int> children(int id) => tree.groups[id]!.children
      .where((c) => c.isGroup)
      .map((c) => c.id)
      .toList();
  String name(int id) => tree.groups[id]!.name.isEmpty
      ? (id == 0 ? 'NT Settings' : 'Group $id')
      : tree.groups[id]!.name;
  int? get initial {
    if (tree.settingIds.isEmpty) return null;
    final first = tree.settingIds.first;
    return tree.groups.values
        .firstWhere((g) => g.children.any((c) => !c.isGroup && c.id == first))
        .id;
  }

  Set<int> ancestors(int? id) {
    final result = <int>{};
    while (id != null && parents.containsKey(id)) {
      id = parents[id];
      if (id != 0) result.add(id!);
    }
    return result;
  }

  List<(int, int)> rows(Set<int> expanded) {
    final result = <(int, int)>[];
    void visit(int id, int depth) {
      result.add((id, depth));
      if (expanded.contains(id)) {
        for (final child in children(id)) {
          visit(child, depth + 1);
        }
      }
    }

    if (direct(0).isNotEmpty) result.add((0, 0));
    for (final id in children(0)) {
      visit(id, 0);
    }
    return result;
  }

  int? effective(int? requested, Set<int> expanded) {
    var id = tree.groups.containsKey(requested) ? requested : initial;
    final visible = rows(expanded).map((r) => r.$1).toSet();
    while (id != null && !visible.contains(id)) {
      id = parents[id];
    }
    return id;
  }

  List<int> descendants(int id) => [
    ...direct(id),
    for (final child in children(id)) ...descendants(child),
  ];
}
