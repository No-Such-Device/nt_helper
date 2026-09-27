/// Development preset format shared with the Patch Helper C++ plug-in.
/// This is a record of intended cabling, not detected connectivity.
class PatchMap {
  static const version = 1;
  static const socketCount = 20;
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

  PatchMap({required String title, required List<PatchConnection> connections})
    : title = _text(title, 63, 'title'),
      connections = _orderedConnections(connections);

  factory PatchMap.empty() => PatchMap(
    title: 'Patch Helper',
    connections: List.generate(
      socketCount,
      (socket) => PatchConnection(socket: socket),
    ),
  );

  factory PatchMap.fromJson(Map<String, dynamic> json) {
    _keys(json, {'version', 'title', 'connections'}, 'patch_helper');
    if (json['version'] is! int || json['version'] != version) {
      throw const FormatException('Unsupported Patch Helper version');
    }
    final rows = json['connections'];
    if (rows is! List) {
      throw const FormatException('connections must be a list');
    }
    return PatchMap(
      title: _text(json['title'], 63, 'title'),
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
  final List<PatchConnection> connections;

  Map<String, dynamic> toJson() => {
    'version': version,
    'title': title,
    'connections': [for (final connection in connections) connection.toJson()],
  };

  PatchMap withConnection(PatchConnection connection) => PatchMap(
    title: title,
    connections: [
      for (final previous in connections)
        previous.socket == connection.socket ? connection : previous,
    ],
  );

  static List<PatchConnection> _orderedConnections(List<PatchConnection> rows) {
    if (rows.length != socketCount ||
        rows.map((row) => row.socket).toSet().length != socketCount) {
      throw const FormatException(
        'Expected each of the 20 native sockets exactly once',
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
  }) : socket = _integer(socket, 0, 19, 'socket'),
       destination = _text(destination, 63, 'destination'),
       colour = _integer(colour, 0, PatchMap.colours.length - 1, 'colour'),
       tag = _integer(tag, 0, 12, 'tag'),
       group = _text(group, 31, 'group');

  factory PatchConnection.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'socket',
      'destination',
      'colour',
      'tag',
      'group',
    }, 'connection');
    return PatchConnection(
      socket: _integer(json['socket'], 0, 19, 'socket'),
      destination: _text(json['destination'], 63, 'destination'),
      colour: _integer(
        json['colour'],
        0,
        PatchMap.colours.length - 1,
        'colour',
      ),
      tag: _integer(json['tag'], 0, 12, 'tag'),
      group: _text(json['group'], 31, 'group'),
    );
  }

  final int socket;
  final String destination;
  final int colour;
  final int tag;
  final String group;

  bool get connected => destination.isNotEmpty;
  String get socketLabel =>
      socket < 12 ? 'In ${socket + 1}' : 'Out ${socket - 11}';

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
