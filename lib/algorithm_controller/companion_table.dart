import 'package:nt_helper/domain/patch_map/patch_map.dart';

/// Validated host primitives. Lua chooses labels, field bindings, sections and
/// minimap geometry; the host owns widgets, focus, scrolling and the MIDI queue.
class CompanionTable {
  CompanionTable._(this.groups, this.labels, this.focusSocket, this.actions);
  final int? focusSocket;
  final List<CompanionChoiceAction> actions;
  final List<CompanionSocketGroup> groups;
  final Map<String, String> labels;

  factory CompanionTable.parse(Map<String, dynamic> document, PatchMap map) {
    if (document['type'] != 'socket_table' || document['version'] != 1) {
      throw const FormatException('Unsupported companion view');
    }
    final rawGroups = document['groups'];
    final rawLabels = document['labels'];
    if (rawGroups is! List || rawLabels is! Map) {
      throw const FormatException('Invalid companion table');
    }
    final groups = <CompanionSocketGroup>[];
    final sockets = <int>{};
    for (final group in rawGroups) {
      if (group is! Map) throw const FormatException('Invalid socket group');
      final start = group['start'],
          count = group['count'],
          columns = group['columns'];
      if (start is! int ||
          count is! int ||
          columns is! int ||
          start < 0 ||
          count < 1 ||
          columns < 1 ||
          columns > count ||
          count % columns != 0 ||
          start + count > map.connections.length) {
        throw const FormatException('Invalid socket grid');
      }
      for (var i = start; i < start + count; i++) {
        if (!sockets.add(i)) throw const FormatException('Duplicate socket');
      }
      groups.add(
        CompanionSocketGroup(
          start,
          count,
          columns,
          _label(group['title']),
          _label(group['short']),
        ),
      );
    }
    if (sockets.length != map.connections.length) {
      throw const FormatException('Companion omitted sockets');
    }
    final focus = document['focus_socket'];
    if (focus != null &&
        (focus is! int || focus < 0 || focus >= map.connections.length)) {
      throw const FormatException('Invalid focused socket');
    }
    final rawActions = document['actions'] ?? const [];
    if (rawActions is! List) {
      throw const FormatException('Invalid companion actions');
    }
    final actions = rawActions.map(CompanionChoiceAction.parse).toList();
    if (actions.map((action) => action.id).toSet().length != actions.length) {
      throw const FormatException('Duplicate companion action');
    }
    return CompanionTable._(
      List.unmodifiable(groups),
      {
        for (final field in ['socket', 'destination', 'colour', 'tag', 'group'])
          field: _label(rawLabels[field]),
      },
      focus as int?,
      List.unmodifiable(actions),
    );
  }
  static String _label(Object? value) {
    if (value is! String || value.isEmpty || value.length > 128) {
      throw const FormatException('Invalid companion label');
    }
    return value;
  }
}

class CompanionSocketGroup {
  const CompanionSocketGroup(
    this.start,
    this.count,
    this.columns,
    this.title,
    this.short,
  );
  final int start, count, columns;
  final String title, short;
}

/// Lua declares a choice dialog; the host retains a narrow action capability.
class CompanionChoiceAction {
  const CompanionChoiceAction._(
    this.id,
    this.label,
    this.title,
    this.cancel,
    this.choices,
  );
  final String id, label, title, cancel;
  final Map<int, String> choices;

  factory CompanionChoiceAction.parse(Object? value) {
    if (value is! Map || value['id'] != 'add_expander') {
      throw const FormatException('Unsupported companion action');
    }
    final dialog = value['dialog'];
    if (dialog is! Map ||
        dialog['type'] != 'choice_dialog' ||
        dialog['choices'] is! List) {
      throw const FormatException('Invalid companion dialog');
    }
    final choices = <int, String>{};
    for (final choice in dialog['choices'] as List) {
      if (choice is! Map || choice['value'] is! int) {
        throw const FormatException('Invalid dialog choice');
      }
      final model = choice['value'] as int;
      if (model < 0 ||
          model >= PatchMap.expanderTypes.length ||
          choices.containsKey(model)) {
        throw const FormatException('Invalid expander choice');
      }
      choices[model] = CompanionTable._label(choice['label']);
    }
    if (choices.isEmpty) throw const FormatException('Empty companion dialog');
    return CompanionChoiceAction._(
      value['id'] as String,
      CompanionTable._label(value['label']),
      CompanionTable._label(dialog['title']),
      CompanionTable._label(dialog['cancel']),
      Map.unmodifiable(choices),
    );
  }
}
