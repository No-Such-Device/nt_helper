import 'dart:async';
import 'dart:typed_data';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';

class PatchMapDevice implements PatchMapTransport {
  bool supportsAux = true;
  bool _auxSession = false;
  int selectedAux = 0;
  PatchMap map = PatchMap.empty();
  int revision = 0, lease = 0, firstSocket = 1;
  bool loseReply = false;
  Completer<void>? holdWrite;
  final writeStarted = Completer<void>();
  final frames = <Map<String, List<int>>>[];
  void changeProperty(int parameter, int value) {
    frames.add({
      'parameter': [parameter, value],
    });
    if (parameter == 0) {
      firstSocket = value;
    } else {
      final row = map.connections[firstSocket - 1];
      if ((parameter == 1 ? row.colour : row.tag) != value) {
        map = map.withConnection(
          PatchConnection(
            socket: row.socket,
            destination: row.destination,
            colour: parameter == 1 ? value : row.colour,
            tag: parameter == 2 ? value : row.tag,
            group: row.group,
          ),
        );
        revision++;
      }
    }
  }

  @override
  Future<Uint8List> exchangePatchMessage(
    Uint8List request,
    bool Function(Uint8List) matches,
  ) async {
    final command = request[7];
    int integer(int at) =>
        request[at] |
        request[at + 1] << 7 |
        request[at + 2] << 14 |
        request[at + 3] << 21;
    var at = 21;
    String text() {
      final size = request[at++];
      final result = String.fromCharCodes(request.sublist(at, at + size));
      at += size;
      return result;
    }

    List<int> encode(String value) => [value.length, ...value.codeUnits];
    var status = 0;
    var data = <int>[];
    if (command == 1) {
      if (request[21] == 3 && !supportsAux) {
        status = 1;
      } else {
        lease = integer(13);
        _auxSession = request[21] == 3;
        data = [...encode(map.title), map.expanders.length, if (_auxSession) 1];
      }
    } else if (integer(13) != lease) {
      status = 2;
    } else if (command == 9) {
      final row = map.connections[firstSocket - 1];
      data = [
        ...encode(map.title),
        map.expanders.length,
        firstSocket,
        row.colour,
        row.tag,
        if (_auxSession) selectedAux,
      ];
    } else if (integer(17) != revision) {
      status = 3;
    } else if (command == 10) {
      data = List.generate(7, (group) {
        var bits = 0;
        for (final row in map.aux) {
          if ((row.bus - 1) ~/ 7 == group) bits |= 1 << ((row.bus - 1) % 7);
        }
        return bits;
      });
    } else if (command == 11) {
      final row = map.aux.firstWhere((row) => row.bus == request[21]);
      data = [row.bus, ...encode(row.description), ...encode(row.group)];
    } else if (command == 2) {
      final row = map.connections[request[21]];
      data = [
        row.socket,
        row.colour,
        row.tag,
        ...encode(row.destination),
        ...encode(row.group),
      ];
    } else if (command == 6) {
      final expander = map.expanders[request[21]];
      data = [expander.type, ...encode(expander.name)];
    } else {
      if (command == 12) {
        map = map.addAux(request[21]);
      } else if (command == 13) {
        final bus = request[at++];
        map = map.withAux(
          PatchAux(bus: bus, description: text(), group: text()),
        );
      } else if (command == 14) {
        map = map.removeAux(request[21]);
      } else if (command == 3) {
        final socket = request[at++],
            colour = request[at++],
            tag = request[at++];
        map = map.withConnection(
          PatchConnection(
            socket: socket,
            colour: colour,
            tag: tag,
            destination: text(),
            group: text(),
          ),
        );
      } else if (command == 4) {
        map = PatchMap(
          title: text(),
          aux: map.aux,
          connections: map.connections,
          expanders: map.expanders,
        );
      } else if (command == 5) {
        final type = request[at++];
        final name = text();
        map = map.addExpander(type).renameExpander(map.expanders.length, name);
      } else if (command == 7) {
        final index = request[at++];
        map = map.renameExpander(index, text());
      } else if (command == 8) {
        map = map.moveExpander(request[21], request[22]);
      }
      revision++;
      if (holdWrite != null) {
        if (!writeStarted.isCompleted) writeStarted.complete();
        await holdWrite!.future;
      }
      if (loseReply) throw TimeoutException('Lost acknowledgement');
    }
    final reply = Uint8List.fromList([
      ...request.take(21),
      status,
      ...data,
      0xf7,
    ]);
    reply[7] |= 0x40;
    for (var i = 0; i < 4; i++) {
      reply[17 + i] = (revision >> (7 * i)) & 127;
    }
    if (!matches(reply)) throw StateError('Unexpected frame');
    frames.add({'request': request.toList(), 'response': reply.toList()});
    return reply;
  }
}
