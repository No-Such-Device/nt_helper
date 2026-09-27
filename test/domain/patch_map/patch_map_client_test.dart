import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/patch_map/patch_map.dart';
import 'package:nt_helper/domain/patch_map/patch_map_client.dart';

class FixtureTransport implements PatchMapTransport {
  final frames =
      (jsonDecode(
            File(
              'test/fixtures/patch_map/midi-session.json',
            ).readAsStringSync(),
          )
          as List);
  int index = 0;
  int? status;
  bool timeout = false;
  @override
  Future<Uint8List> exchangePatchMessage(
    Uint8List request,
    bool Function(Uint8List) matches,
  ) async {
    if (timeout) throw TimeoutException('Lost acknowledgement');
    final frame = frames[index++] as Map;
    expect(request, frame['request']);
    final reply = Uint8List.fromList((frame['response'] as List).cast<int>());
    expect(matches(reply), isTrue);
    final other = Uint8List.fromList(reply)..[9] ^= 1;
    expect(
      matches(other),
      isFalse,
      reason: 'Ignore replies to another transaction',
    );
    if (status != null) reply[21] = status!;
    return reply;
  }
}

void main() {
  test('client exchanges the same wire fixtures as the C++ factory', () async {
    final transport = FixtureTransport();
    final client = PatchMapClient(transport, 0, lease: 42);
    final map = await client.load();
    expect(map.title, 'Patch Helper');
    expect(map.connections.every((row) => !row.connected), isTrue);
    final updated = await client.setConnection(
      PatchConnection(
        socket: 0,
        destination: 'Echo',
        colour: 4,
        tag: 7,
        group: 'Delay',
      ),
    );
    expect(updated.connections.first.destination, 'Echo');
    expect(transport.index, 22);
    expect(client.ready, isTrue);
  });
  test('uncertain writes cannot be retried until a full reload', () async {
    final transport = FixtureTransport();
    final client = PatchMapClient(transport, 0, lease: 42);
    await client.load();
    transport.timeout = true;
    await expectLater(
      client.setTitle('New title'),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.ready, isFalse);
    await expectLater(
      client.setTitle('New title'),
      throwsA(isA<PatchMapSyncException>()),
    );
    expect(transport.index, 21);
  });
  for (final status in [2, 3]) {
    test(
      'expired or conflicting edit invalidates the loaded map ($status)',
      () async {
        final transport = FixtureTransport();
        final client = PatchMapClient(transport, 0, lease: 42);
        await client.load();
        transport.status = status;
        await expectLater(
          client.setConnection(
            PatchConnection(
              socket: 0,
              destination: 'Echo',
              colour: 4,
              tag: 7,
              group: 'Delay',
            ),
          ),
          throwsA(isA<PatchMapSyncException>()),
        );
        expect(client.ready, isFalse);
      },
    );
  }
}
