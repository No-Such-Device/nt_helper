import 'package:nt_helper/domain/patch_map/patch_map.dart';

/// Validated host primitives. Lua chooses labels, field bindings, sections and
/// minimap geometry; the host owns widgets, focus, scrolling and the MIDI queue.
class CompanionTable {
  CompanionTable._(this.groups, this.labels);
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
    return CompanionTable._(List.unmodifiable(groups), {
      for (final field in ['socket', 'destination', 'colour', 'tag', 'group'])
        field: _label(rawLabels[field]),
    });
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
