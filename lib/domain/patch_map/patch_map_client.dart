import 'dart:math';
import 'dart:typed_data';

import 'patch_map.dart';

/// Optional capability: live managers carry plug-in traffic on their MIDI queue.
abstract interface class PatchMapTransport {
  Future<Uint8List> exchangePatchMessage(
    Uint8List request,
    bool Function(Uint8List) matches,
  );
}

class PatchMapSyncException implements Exception {
  const PatchMapSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns one editing session. Every write compares the device revision; an
/// uncertain outcome invalidates the session until the full map is read again.
class PatchMapClient {
  PatchMapClient(this.transport, this.slot, {int? lease})
    : _lease = lease ?? Random.secure().nextInt(0x0ffffffe) + 1 {
    if (slot < 0 || slot > 127 || _lease < 1 || _lease > 0x0fffffff) {
      throw ArgumentError('Invalid Patch Helper address');
    }
  }

  final PatchMapTransport transport;
  final int slot;
  int _lease;
  int _requestId = 0;
  int _revision = 0;
  bool _ready = false;
  bool _busy = false;
  PatchMap? _map;
  static const _prefix = [0x7d, 84, 104, 80, 104, 1];

  bool get ready => _ready;

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_busy) throw StateError('A Patch Helper operation is already running');
    _busy = true;
    try {
      return await action();
    } catch (_) {
      _ready = false;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<PatchMap> load() => _run(() async {
    _ready = false;
    // A fresh lease also separates late replies from an earlier reload.
    _lease = _lease == 0x0fffffff ? 1 : _lease + 1;
    final titleData = _Reader(await _exchange(1, const []));
    final title = titleData.text(63);
    titleData.finish();
    final rows = <PatchConnection>[];
    for (var socket = 0; socket < PatchMap.socketCount; socket++) {
      final data = _Reader(await _exchange(2, [socket]));
      final identity = data.byte();
      final colour = data.byte();
      final tag = data.byte();
      final destination = data.text(63);
      final group = data.text(31);
      data.finish();
      if (identity != socket) throw const FormatException('Wrong socket reply');
      rows.add(
        PatchConnection(
          socket: socket,
          destination: destination,
          colour: colour,
          tag: tag,
          group: group,
        ),
      );
    }
    _map = PatchMap(title: title, connections: rows);
    _ready = true;
    return _map!;
  });

  Future<PatchMap> setConnection(PatchConnection row) => _run(() async {
    _requireReady();
    final payload = [
      row.socket,
      row.colour,
      row.tag,
      ..._text(row.destination),
      ..._text(row.group),
    ];
    final response = await _exchange(3, payload);
    if (response.isNotEmpty) {
      throw const FormatException('Unexpected write reply');
    }
    return _map = _map!.withConnection(row);
  });

  Future<PatchMap> setTitle(String title) => _run(() async {
    _requireReady();
    final candidate = PatchMap(title: title, connections: _map!.connections);
    final response = await _exchange(4, _text(candidate.title));
    if (response.isNotEmpty) {
      throw const FormatException('Unexpected write reply');
    }
    return _map = candidate;
  });

  void _requireReady() {
    if (!_ready) {
      throw const PatchMapSyncException('Reload the map before editing.');
    }
  }

  static List<int> _text(String value) => [value.length, ...value.codeUnits];
  static List<int> _integer(int value) => [
    value & 127,
    (value >> 7) & 127,
    (value >> 14) & 127,
    (value >> 21) & 127,
  ];
  static int _readInteger(List<int> data, int at) =>
      data[at] |
      (data[at + 1] << 7) |
      (data[at + 2] << 14) |
      (data[at + 3] << 21);

  Future<List<int>> _exchange(int command, List<int> payload) async {
    if (++_requestId > 0x0fffffff) {
      throw const PatchMapSyncException(
        'Reopen the editor to start a new session.',
      );
    }
    final header = [
      ..._prefix,
      command,
      slot,
      ..._integer(_requestId),
      ..._integer(_lease),
      ..._integer(_revision),
    ];
    bool matches(Uint8List response) {
      if (response.length < 23 ||
          response.first != 0xf0 ||
          response.last != 0xf7) {
        return false;
      }
      for (var i = 0; i < 16; i++) {
        final expected = i == 6 ? command | 0x40 : header[i];
        if (response[i + 1] != expected) return false;
      }
      return true;
    }

    final response = await transport.exchangePatchMessage(
      Uint8List.fromList([0xf0, ...header, ...payload, 0xf7]),
      matches,
    );
    if (!matches(response) ||
        response.length > 122 ||
        response.sublist(1, response.length - 1).any((byte) => byte > 127)) {
      throw const FormatException('Invalid Patch Helper reply');
    }
    final status = response[21];
    if (status != 0) {
      throw PatchMapSyncException(switch (status) {
        2 => 'The preset or editing session changed. Reload the map.',
        3 => 'The map changed on the NT. Reload before editing.',
        _ => 'The NT rejected this change. Reload the map and try again.',
      });
    }
    final revision = _readInteger(response, 17);
    final expected = _revision + (command >= 3 ? 1 : 0);
    if (command != 1 && revision != expected) {
      throw const FormatException('Unexpected Patch Helper revision');
    }
    _revision = revision;
    return response.sublist(22, response.length - 1);
  }
}

class _Reader {
  _Reader(this.data);
  final List<int> data;
  int position = 0;
  int byte() {
    if (position >= data.length) {
      throw const FormatException('Incomplete map reply');
    }
    return data[position++];
  }

  String text(int maximum) {
    final length = byte();
    if (length > maximum || position + length > data.length) {
      throw const FormatException('Invalid map text length');
    }
    final chars = data.sublist(position, position + length);
    if (chars.any((c) => c < 32 || c > 126)) {
      throw const FormatException('Invalid map text');
    }
    position += length;
    return String.fromCharCodes(chars);
  }

  void finish() {
    if (position != data.length) {
      throw const FormatException('Unexpected map data');
    }
  }
}
