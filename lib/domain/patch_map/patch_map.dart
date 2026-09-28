/// Development preset format shared with the Patch Helper C++ plug-in.
/// This is a record of intended cabling, not detected connectivity.
class PatchMap {
  static const version = 1;
  static const maxEditableTextLength = 32;
  static const socketCount = 20;
  // Limited by the protocol's seven-bit socket address, not hardware topology.
  static const maxExpanders = (128 - socketCount) ~/ 8;
  // New maps fit four-field native pages including read-only text.
  // Keep maxExpanders unchanged so existing 13-bank presets remain readable.
  static const maxNewExpanders = 8;
  static const maxSockets = socketCount + 8 * maxExpanders;
  static const expanderTypes = ['NTX-8CV', 'ES-5', 'ESX-8GT', 'ESX-8CV'];
  static const colours = <String>[
    'None',
    'Black',
    'White',
    'Grey',
    'Red',
    'Orange',
    'Yellow',
    'Green',
    'Blue',
    'Purple',
    'Pink',
    'Brown',
  ];

  PatchMap({
    required String title,
    required List<PatchConnection> connections,
    List<PatchExpander> expanders = const [],
  }) : title = _text(title, 63, 'title'),
       expanders = _expanders(expanders),
       connections = _orderedConnections(connections, expanders.length);

  factory PatchMap.empty() => PatchMap(
    title: 'Patch Helper',
    connections: List.generate(
      socketCount,
      (socket) => PatchConnection(socket: socket),
    ),
  );

  factory PatchMap.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'version',
      'title',
      'connections',
      if (json['version'] == 2) 'expanders',
    }, 'patch_helper');
    if (json['version'] is! int ||
        (json['version'] != version && json['version'] != 2)) {
      throw const FormatException('Unsupported Patch Helper version');
    }
    final rows = json['connections'];
    if (rows is! List) {
      throw const FormatException('connections must be a list');
    }
    return PatchMap(
      title: _text(json['title'], 63, 'title'),
      expanders: json['version'] == 2
          ? _parseExpanders(json['expanders'])
          : const [],
      connections: [
        for (final row in rows)
          if (row is Map<String, dynamic>)
            PatchConnection.fromJson(row)
          else
            throw const FormatException('Invalid connection'),
      ],
    );
  }

  final String title;
  final List<PatchExpander> expanders;
  final List<PatchConnection> connections;

  Map<String, dynamic> toJson() => {
    'version': expanders.isEmpty ? version : 2,
    if (expanders.isNotEmpty)
      'expanders': [for (final e in expanders) e.toJson()],
    'title': title,
    'connections': [for (final connection in connections) connection.toJson()],
  };

  PatchMap withConnection(PatchConnection connection) => PatchMap(
    title: title,
    expanders: expanders,
    connections: [
      for (final previous in connections)
        previous.socket == connection.socket ? connection : previous,
    ],
  );

  PatchMap addExpander(int type) => PatchMap(
    title: title,
    expanders: [
      ...expanders,
      PatchExpander(type: type, name: 'Expander ${expanders.length + 1}'),
    ],
    connections: [
      ...connections,
      ...List.generate(
        8,
        (i) => PatchConnection(socket: connections.length + i),
      ),
    ],
  );

  PatchMap renameExpander(int index, String name) {
    final next = List<PatchExpander>.of(expanders);
    next[index] = PatchExpander(type: next[index].type, name: name);
    return PatchMap(title: title, connections: connections, expanders: next);
  }

  PatchMap moveExpander(int from, int to) {
    RangeError.checkValidIndex(from, expanders);
    RangeError.checkValidIndex(to, expanders);
    final order = List.generate(expanders.length, (i) => i);
    order.insert(to, order.removeAt(from));
    final rows = connections.take(20).toList();
    for (final index in order) {
      for (final row in connections.skip(20 + index * 8).take(8)) {
        rows.add(
          PatchConnection(
            socket: rows.length,
            destination: row.destination,
            colour: row.colour,
            tag: row.tag,
            group: row.group,
          ),
        );
      }
    }
    return PatchMap(
      title: title,
      connections: rows,
      expanders: [for (final i in order) expanders[i]],
    );
  }

  static List<PatchExpander> _parseExpanders(Object? value) {
    if (value is! List) throw const FormatException('expanders must be a list');
    return [
      for (final item in value)
        if (item is Map<String, dynamic>)
          PatchExpander.fromJson(item)
        else
          throw const FormatException('Invalid expander'),
    ];
  }

  static List<PatchExpander> _expanders(List<PatchExpander> types) {
    if (types.length > maxExpanders) {
      throw const FormatException('Invalid expander inventory');
    }
    return List.unmodifiable(types);
  }

  static List<PatchConnection> _orderedConnections(
    List<PatchConnection> rows,
    int expanderCount,
  ) {
    final count = socketCount + 8 * expanderCount;
    if (rows.length != count ||
        rows.map((row) => row.socket).toSet().length != count ||
        rows.any((row) => row.socket >= count)) {
      throw const FormatException(
        'Expected each configured socket exactly once',
      );
    }
    final ordered = List<PatchConnection>.of(rows)
      ..sort((a, b) => a.socket.compareTo(b.socket));
    return List.unmodifiable(ordered);
  }
}

class PatchConnection {
  PatchConnection({
    required int socket,
    String destination = '',
    int colour = 0,
    int tag = 0,
    String group = '',
  }) : socket = _integer(socket, 0, PatchMap.maxSockets - 1, 'socket'),
       destination = _text(destination, 63, 'destination'),
       colour = _integer(colour, 0, PatchMap.colours.length - 1, 'colour'),
       tag = _integer(tag, 0, 12, 'tag'),
       group = _text(group, PatchMap.maxEditableTextLength, 'group');

  factory PatchConnection.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'socket',
      'destination',
      'colour',
      'tag',
      'group',
    }, 'connection');
    return PatchConnection(
      socket: _integer(json['socket'], 0, PatchMap.maxSockets - 1, 'socket'),
      destination: _text(json['destination'], 63, 'destination'),
      colour: _integer(
        json['colour'],
        0,
        PatchMap.colours.length - 1,
        'colour',
      ),
      tag: _integer(json['tag'], 0, 12, 'tag'),
      group: _text(json['group'], PatchMap.maxEditableTextLength, 'group'),
    );
  }

  final int socket;
  final String destination;
  final int colour;
  final int tag;
  final String group;

  bool get connected => destination.isNotEmpty;
  String get socketLabel => socket < 12
      ? 'In ${socket + 1}'
      : socket < 20
      ? 'Out ${socket - 11}'
      : 'E${(socket - 20) ~/ 8 + 1} Out ${(socket - 20) % 8 + 1}';

  PatchConnection withDestination(String value) => PatchConnection(
    socket: socket,
    destination: value,
    colour: colour,
    tag: tag,
    group: group,
  );

  Map<String, dynamic> toJson() => {
    'socket': socket,
    'destination': destination,
    'colour': colour,
    'tag': tag,
    'group': group,
  };
}

String _text(Object? value, int maximum, String name) {
  if (value is! String ||
      value.length > maximum ||
      value.codeUnits.any((byte) => byte < 32 || byte > 126)) {
    throw FormatException(
      '$name must contain at most $maximum printable ASCII characters',
    );
  }
  return value;
}

int _integer(Object? value, int minimum, int maximum, String name) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('$name must be an integer from $minimum to $maximum');
  }
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected, String name) {
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw FormatException('Unexpected or missing fields in $name');
  }
}

class PatchExpander {
  PatchExpander({required int type, required String name})
    : type = _integer(type, 0, 3, 'expander type'),
      name = _text(name, PatchMap.maxEditableTextLength, 'expander name');
  factory PatchExpander.fromJson(Map<String, dynamic> json) {
    _keys(json, {'type', 'name'}, 'expander');
    return PatchExpander(
      type: _integer(json['type'], 0, 3, 'expander type'),
      name: _text(
        json['name'],
        PatchMap.maxEditableTextLength,
        'expander name',
      ),
    );
  }
  final int type;
  final String name;
  Map<String, dynamic> toJson() => {'type': type, 'name': name};
}
