import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/mcp_lan_context.dart';
import 'package:nt_helper/services/mcp_lan_policy.dart';
import 'package:nt_helper/services/debug_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'mcp_ipad_capacity_cases.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

Future<HttpClientResponse> _postJsonRpc(
  HttpClient client,
  int port,
  Object body, {
  String? sessionId,
}) async {
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
  request.headers
    ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
    ..set(HttpHeaders.contentTypeHeader, 'application/json');
  if (sessionId != null) {
    request.headers.set('mcp-session-id', sessionId);
  }
  request.write(jsonEncode(body));
  return request.close().timeout(const Duration(seconds: 5));
}

Future<Map<String, dynamic>> _readJsonRpcMessage(
  HttpClientResponse response,
) async {
  final body = await utf8
      .decodeStream(response)
      .timeout(const Duration(seconds: 5));

  if (response.headers.contentType?.mimeType == 'application/json') {
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  expect(response.headers.contentType?.mimeType, equals('text/event-stream'));

  for (final eventBlock in body.split(RegExp(r'\r?\n\r?\n'))) {
    final data = eventBlock
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring('data:'.length).trimLeft())
        .join('\n')
        .trim();
    if (data.isEmpty) {
      continue;
    }

    final decoded = jsonDecode(data);
    if (decoded is Map && decoded['jsonrpc'] == '2.0') {
      return decoded.cast<String, dynamic>();
    }
  }

  fail('No JSON-RPC message found in SSE response: $body');
}

Future<String> _initializeSession(
  HttpClient client,
  int port, {
  int id = 1,
}) async {
  final initResponse = await _postJsonRpc(client, port, {
    'jsonrpc': '2.0',
    'id': id,
    'method': 'initialize',
    'params': {
      'protocolVersion': '2025-06-18',
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '0.0.0'},
    },
  });
  expect(initResponse.statusCode, equals(HttpStatus.ok));
  expect(
    initResponse.headers.contentType?.mimeType,
    equals('text/event-stream'),
  );

  final sessionId = initResponse.headers.value('mcp-session-id');
  expect(sessionId, isNotNull);

  final initMessage = await _readJsonRpcMessage(initResponse);
  expect(initMessage['jsonrpc'], equals('2.0'));
  expect(initMessage['id'], equals(id));

  final initializedResponse = await _postJsonRpc(client, port, {
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  }, sessionId: sessionId);
  expect(initializedResponse.statusCode, equals(HttpStatus.accepted));
  await initializedResponse.drain<void>();

  return sessionId!;
}

// AC-003..006 fixtures keep the real HttpServer parser, SDK transport, registry,
// and mocked cubit/MIDI boundary. Socket identities/native paths are simulated:
// these tests do not prove OS ingress identity, actual LAN reachability or iPad
// lifecycle delivery. Existing loopback desktop tests cannot exercise these seams.
McpLanSnapshot _nativeSnapshot({
  int generation = 3,
  bool ipv6 = false,
  String name = 'physical-lan',
  int prefix = 24,
}) {
  final length = ipv6 ? 16 : 4;
  final bits = ipv6 ? 64 : prefix;
  return McpLanSnapshot.decode({
    'version': 1,
    'idiom': 'pad',
    'pathCurrent': true,
    'pathGeneration': generation,
    'interfaces': [
      {
        'index': 7,
        'name': name,
        'type': 'wifi',
        'flags': 0x41,
        'addresses': [
          {
            'family': ipv6 ? 'ipv6' : 'ipv4',
            'bytes': InternetAddress(
              ipv6 ? 'fd12::1' : '192.168.2.1',
            ).rawAddress.toList(),
            'mask': List.generate(length, (i) => bits >= (i + 1) * 8 ? 255 : 0),
            'prefix': bits,
            'scopeId': 0,
          },
        ],
      },
    ],
  });
}

class _NativeContext implements McpLanContext {
  _NativeContext(this.value);
  McpLanSnapshot value;
  int calls = 0;
  Future<McpLanSnapshot> Function(int)? read;
  @override
  Future<McpLanSnapshot> snapshot() {
    calls++;
    return read?.call(calls) ?? Future.value(value);
  }
}

class _CaptureConsumer implements StreamConsumer<List<int>> {
  _CaptureConsumer(this.output);
  final List<int> output;
  final pending = <Completer<void>, StreamSubscription<List<int>>>{};
  void destroy() {
    for (final entry in pending.entries.toList()) {
      unawaited(entry.value.cancel());
      if (!entry.key.isCompleted) {
        entry.key.completeError(const SocketException('Socket destroyed'));
      }
    }
    pending.clear();
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final complete = Completer<void>();
    pending[complete] = stream.listen(
      output.addAll,
      onDone: () {
        pending.remove(complete);
        complete.complete();
      },
      onError: (Object e, StackTrace s) {
        pending.remove(complete);
        complete.completeError(e, s);
      },
      cancelOnError: true,
    );
    return complete.future;
  }

  @override
  Future<void> close() async {}
}

class _MemorySocket extends Stream<Uint8List> implements Socket {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
  _MemorySocket({
    this.real,
    this.local = '192.168.2.1',
    this.peer = '192.168.2.2',
    this.localPort = 3847,
    required this.peerPort,
  });
  final Socket? real;
  final received = <int>[];
  final String local;
  final String peer;
  final int localPort;
  final int peerPort;
  final input = StreamController<Uint8List>();
  final output = <int>[];
  void Function()? onOutput;
  void capture(List<int> bytes) {
    output.addAll(bytes);
    onOutput?.call();
  }

  late final consumer = _CaptureConsumer(output);
  late final sink = IOSink(consumer);
  final ended = Completer<void>();
  bool destroyed = false;
  @override
  InternetAddress get address => InternetAddress(local);
  @override
  InternetAddress get remoteAddress => InternetAddress(peer);
  @override
  int get port => localPort;
  @override
  int get remotePort => peerPort;
  @override
  Encoding encoding = utf8;
  @override
  Future get done => real?.done ?? ended.future;
  @override
  bool setOption(SocketOption option, bool enabled) => true;
  @override
  void add(List<int> bytes) {
    if (!destroyed) {
      if (real != null) {
        capture(bytes);
        real!.add(bytes);
      } else {
        sink.add(bytes);
      }
    }
  }

  @override
  Future addStream(Stream<List<int>> stream) =>
      real?.addStream(
        stream.map((bytes) {
          capture(bytes);
          return bytes;
        }),
      ) ??
      sink.addStream(stream);

  @override
  void write(Object? object) => add(encoding.encode('$object'));
  @override
  Future flush() => real?.flush() ?? sink.flush();
  @override
  Future<void> close() async {
    await real?.close();
    if (!ended.isCompleted) ended.complete();
  }

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    real?.destroy();
    if (real == null) {
      consumer.destroy();
      unawaited(close());
    }
    unawaited(input.close());
  }

  void receive(String bytes) {
    if (!destroyed) input.add(Uint8List.fromList(utf8.encode(bytes)));
  }

  String get response => utf8.decode(output, allowMalformed: true);
  int? get status => int.tryParse(response.split(' ').elementAtOrNull(1) ?? '');
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      (real == null
              ? input.stream
              : real!.map((bytes) {
                  received.addAll(bytes);
                  return bytes;
                }))
          .listen(
            onData,
            onError: onError,
            onDone: onDone,
            cancelOnError: cancelOnError,
          );
}

class _MemoryListener extends Stream<Socket> implements ServerSocket {
  _MemoryListener(this.address);
  final incoming = StreamController<Socket>();
  @override
  final InternetAddress address;
  @override
  int get port => 3847;
  int closes = 0;
  Completer<void>? closeGate;
  @override
  Future<ServerSocket> close() async {
    closes++;
    unawaited(incoming.close());
    await closeGate?.future;
    return this;
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => incoming.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _LoopbackListener extends Stream<Socket> implements ServerSocket {
  _LoopbackListener(this.inner);
  final ServerSocket inner;
  final sockets = <_MemorySocket>[];
  @override
  InternetAddress get address => InternetAddress('192.168.2.1');
  @override
  int get port => 3847;
  @override
  Future<ServerSocket> close() async {
    await inner.close();
    return this;
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner
      .map((s) {
        final socket = _MemorySocket(real: s, peerPort: s.remotePort);
        sockets.add(socket);
        return socket;
      })
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

class _ChangedRequest extends Mock implements HttpRequest {
  _ChangedRequest(this.inner, this.connectionInfo);
  final HttpRequest inner;
  @override
  final HttpConnectionInfo? connectionInfo;
  @override
  String get method => inner.method;
  @override
  Uri get uri => inner.uri;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  HttpResponse get response => inner.response;
}

class _Info extends Mock implements HttpConnectionInfo {
  _Info({
    this.localPort = 3847,
    this.remotePort = 9000,
    String peer = '192.168.2.2',
  }) : remoteAddress = InternetAddress(peer);
  @override
  final int localPort;
  @override
  final int remotePort;
  @override
  final InternetAddress remoteAddress;
}

class _ObservedHttpServer extends Mock implements HttpServer {
  _ObservedHttpServer(this.inner, this.changeInfo, {this.observe});
  final void Function(HttpRequest)? observe;
  final HttpServer inner;
  final HttpConnectionInfo? Function(HttpRequest)? changeInfo;
  int closes = 0;
  @override
  int get port => inner.port;
  @override
  InternetAddress get address => inner.address;
  @override
  Future<HttpServer> close({bool force = false}) async {
    closes++;
    await inner.close(force: force);
    return this;
  }

  @override
  StreamSubscription<HttpRequest> listen(
    void Function(HttpRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner
      .map((r) {
        observe?.call(r);
        return changeInfo == null ? r : _ChangedRequest(r, changeInfo!(r));
      })
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

class _IpadHarness {
  _IpadHarness(
    this.time, {
    bool ipv6 = false,
    HttpConnectionInfo? Function(HttpRequest)? changeInfo,
  }) {
    native = _NativeContext(_nativeSnapshot(ipv6: ipv6));
    policy = McpLanPolicy.select(
      native.value,
      interfaceIndex: 7,
      address: ipv6 ? 'fd12::1' : '192.168.2.1',
      peers: [ipv6 ? 'fd12::2' : '192.168.2.2'],
    );
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: midi,
        distingVersion: '1.19.0',
        firmwareVersion: FirmwareVersion('1.19.0'),
        presetName: 'simulated',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );
    when(() => cubit.requestFreshMemoryUsage()).thenAnswer((_) async {
      effects++;
      return const MemoryUsage(
        sram: MemoryPoolUsage(total: 10, current: 1),
        dram: MemoryPoolUsage(total: 10, current: 1),
        dtc: MemoryPoolUsage(total: 10, current: 1),
        itc: MemoryPoolUsage(total: 10, current: 1),
      );
    });
    service = McpServerService.forTesting(
      distingCubit: cubit,
      context: native,
      randomBytes: () {
        randomCalls++;
        if (rngFails) throw StateError('RNG');
        return List.filled(32, randomCalls);
      },
      bindSocket: (address, port, {required shared, required v6Only}) {
        binds.add((address.address, port, shared, v6Only));
        if (bindFails) {
          return Future.error(const SocketException('Bind failed'));
        }
        final gate = bindGate;
        bindGate = null;
        if (gate != null) return gate.future;
        final listener = _MemoryListener(address);
        listeners.add(listener);
        return Future.value(listener);
      },
      listenOn: (socket) {
        final http = _ObservedHttpServer(
          HttpServer.listenOn(socket),
          changeInfo,
        );
        httpServers.add(http);
        return http;
      },
      beforeSessionConnect: () async {
        connects++;
        await connectGate?.future;
      },
    );
  }
  final FakeAsync time;
  final cubit = MockDistingCubit();
  final midi = MockDistingMidiManager();
  late final McpServerService service;
  late final _NativeContext native;
  late final McpLanPolicy policy;
  final binds = <(String, int, bool, bool)>[];
  final listeners = <_MemoryListener>[];
  final httpServers = <_ObservedHttpServer>[];
  Completer<ServerSocket>? bindGate;
  Completer<void>? connectGate;
  int randomCalls = 0;
  int effects = 0;
  int connects = 0;
  int nextPort = 9000;
  bool rngFails = false;
  bool bindFails = false;
  void flush() {
    time.flushMicrotasks();
    time.elapse(Duration.zero);
  }

  void enable({Future<bool> Function()? save}) {
    unawaited(
      service.enableIpad(
        policy: policy,
        persistSettings: save ?? () async => true,
      ),
    );
    flush();
  }

  _MemorySocket accept({String? local, String? peer, int port = 3847}) {
    final socket = _MemorySocket(
      local: local ?? policy.address.text,
      peer: peer ?? policy.peers.single.text,
      localPort: port,
      peerPort: nextPort++,
    );
    listeners.last.incoming.add(socket);
    flush();
    return socket;
  }

  _MemorySocket send({
    String method = 'POST',
    String target = '/mcp',
    String? session,
    List<String>? headers,
    Object? body,
    String? local,
    String? peer,
    int port = 3847,
    bool partial = false,
  }) {
    final socket = accept(local: local, peer: peer, port: port);
    if (socket.destroyed) return socket;
    final payload = jsonEncode(body ?? _initBody);
    final h =
        headers ??
        [
          'Host: ${policy.address.bytes.length == 16 ? '[${policy.address.text}]' : policy.address.text}:3847',
          'Authorization: Bearer ${service.ipadToken}',
        ];
    socket.receive(
      '$method $target HTTP/1.1\r\n${h.join('\r\n')}\r\n'
      'Accept: application/json, text/event-stream\r\nContent-Type: application/json\r\n'
      '${session == null ? '' : 'mcp-session-id: $session\r\n'}'
      'Content-Length: ${utf8.encode(payload).length}\r\n\r\n${partial ? '' : payload}',
    );
    flush();
    return socket;
  }

  String session() {
    final initialized = send();
    expect(initialized.status, 200, reason: initialized.response);
    final id = RegExp(
      r'mcp-session-id: ([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(initialized.response)![1]!;
    expect(
      send(
        session: id,
        body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      ).status,
      202,
    );
    return id;
  }

  void clean() {
    service.dispose();
    flush();
    verifyZeroInteractions(midi);
  }
}

const _initBody = {
  'jsonrpc': '2.0',
  'id': 1,
  'method': 'initialize',
  'params': {
    'protocolVersion': '2025-06-18',
    'capabilities': {},
    'clientInfo': {'name': 'simulated-native', 'version': '1'},
  },
};
const _effectBody = {
  'jsonrpc': '2.0',
  'id': 2,
  'method': 'tools/call',
  'params': {'name': 'show_memory', 'arguments': <String, dynamic>{}},
};

void _ipadRuntimeTests() {
  // AC-001: restored-OFF widget checks had no native path/lifecycle events;
  // initial monitor callbacks and unarmed interruptions must still show OFF.
  test(
    'AC-001 unarmed native and lifecycle observations stay OFF without binds',
    () {
      fakeAsync((time) {
        final h = _IpadHarness(time);
        for (final transition in [
          'inactive',
          'resumed',
          'paused',
          'resumed',
          'unknown',
          'resumed',
        ]) {
          unawaited(h.service.ipadLifecycleChanged(transition));
          unawaited(h.service.ipadNetworkChanged());
          h.flush();
          expect(h.service.ipadState, McpIpadState.off);
          expect(h.binds, isEmpty);
          expect(h.service.ipadToken, isNull);
        }
        h.enable(save: () async => false);
        final reason = h.service.ipadReason;
        unawaited(h.service.ipadNetworkChanged());
        unawaited(h.service.ipadLifecycleChanged('inactive'));
        h.flush();
        expect(h.service.ipadState, McpIpadState.failed);
        expect(h.service.ipadReason, reason);
        expect(h.binds, isEmpty);
        h.clean();
      });
    },
  );
  // AC-007: prior rotation tests reject old credentials but do not search
  // observable diagnostics for synthetic raw headers/URI/session data.
  test(
    'AC-007 synthetic secrets never enter iPad diagnostics; failed rotation retains no authority',
    () {
      fakeAsync((time) {
        DebugService().clearMessages();
        final h = _IpadHarness(time)..enable();
        final token = h.service.ipadToken!;
        final session = h.session();
        const pasted = 'synthetic-user-private-value';
        final uri = 'http://192.168.2.1:3847/mcp?private=$pasted';
        h.send(
          target: uri,
          session: session,
          headers: ['Host: 192.168.2.1:3847', 'Authorization: Bearer $pasted'],
        );
        final diagnostic =
            jsonEncode(h.service.connectionDiagnostics) +
            DebugService().debugMessages.join();
        for (final value in [token, session, pasted, uri]) {
          expect(diagnostic, isNot(contains(value)));
        }
        h.rngFails = true;
        unawaited(
          h.service.regenerateIpad(
            policy: h.policy,
            persistSettings: () async => true,
          ),
        );
        expect(h.service.ipadToken, isNull);
        h.flush();
        expect(h.service.ipadState, McpIpadState.failed);
        expect(h.service.isRunning, isFalse);
        expect(h.listeners.every((s) => s.closes == 1), isTrue);
        expect(h.service.connectionDiagnostics['active_servers'], 0);
        expect(h.effects, 0);
        h.clean();
      });
    },
  );
  group('iPad generation runtime (simulated socket identity)', () {
    // AC-003/005/006: loopback bytes complement simulated identities with a
    // full real socket/HTTP/SDK round trip. No LAN/hardware or time-based waits.
    test(
      'AC-003 AC-005 AC-006 real HTTP bytes dispatch and inactive cleanup recover',
      () async {
        final setup = _IpadHarness(FakeAsync());
        late ServerSocket socket;
        final service = McpServerService.forTesting(
          distingCubit: setup.cubit,
          context: setup.native,
          randomBytes: () => List.filled(32, 1),
          bindSocket:
              (address, port, {required shared, required v6Only}) async {
                socket = await ServerSocket.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                return _LoopbackListener(socket);
              },
        );
        final previous = HttpOverrides.current;
        HttpOverrides.global = null;
        final client = HttpClient();
        addTearDown(() async {
          await service.disableIpad();
          service.dispose();
          setup.service.dispose();
          client.close(force: true);
          HttpOverrides.global = previous;
        });
        await service.enableIpad(
          policy: setup.policy,
          persistSettings: () async => true,
        );
        Future<HttpClientResponse> post(Object body, [String? id]) async {
          final req = await client.postUrl(
            Uri.parse('http://127.0.0.1:${socket.port}/mcp'),
          );
          req.headers
            ..set('Host', '192.168.2.1:3847')
            ..set('Authorization', 'Bearer ${service.ipadToken}')
            ..set('Accept', 'application/json, text/event-stream')
            ..set('Content-Type', 'application/json');
          if (id != null) req.headers.set('mcp-session-id', id);
          req.write(jsonEncode(body));
          return req.close();
        }

        final init = await post(_initBody);
        final id = init.headers.value('mcp-session-id')!;
        expect(await utf8.decodeStream(init), contains('protocolVersion'));
        final notification = await post({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, id);
        expect(
          notification.statusCode,
          202,
          reason: await utf8.decodeStream(notification),
        );
        final response = await post(_effectBody, id);
        expect(await utf8.decodeStream(response), contains('memory_usage'));
        expect(setup.effects, 1);
        final stale = await post(_effectBody, 'stale-session');
        expect(await utf8.decodeStream(stale), contains('memory_usage'));
        expect(setup.effects, 2);
        final token = service.ipadToken;
        await service.ipadLifecycleChanged('inactive');
        expect(service.isRunning, isFalse);
        await service.ipadLifecycleChanged('resumed');
        expect(service.ipadState, McpIpadState.running);
        expect(service.ipadToken, token);
        final reinit = await post(_initBody);
        final newId = reinit.headers.value('mcp-session-id')!;
        expect(await utf8.decodeStream(reinit), contains('protocolVersion'));
        final initialized = await post({
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, newId);
        expect(initialized.statusCode, 202);
        await initialized.drain<void>();

        final get = await client.getUrl(
          Uri.parse('http://127.0.0.1:${socket.port}/mcp'),
        );
        get.headers
          ..set('Host', '192.168.2.1:3847')
          ..set('Authorization', 'Bearer ${service.ipadToken}')
          ..set('mcp-session-id', newId)
          ..set('Accept', 'text/event-stream');
        final stream = await get.close();
        final first = Completer<void>();
        final ended = Completer<void>();
        final subscription = stream.listen(
          (_) {
            if (!first.isCompleted) first.complete();
          },
          onDone: () {
            if (!ended.isCompleted) ended.complete();
          },
          onError: (Object _) {
            if (!ended.isCompleted) ended.complete();
          },
        );
        await first.future;

        // AC-005: a native check immediately before registry dispatch is pending.
        // The real SDK/HTTP result above proves this is a reachable effect path.
        final reached = Completer<void>();
        final snapshot = Completer<McpLanSnapshot>();
        final baseline = setup.native.calls;
        setup.native.read = (call) {
          if (call == baseline + 4) {
            reached.complete();
            return snapshot.future;
          }
          return Future.value(setup.native.value);
        };
        final pending = await post(_effectBody, newId);
        final drained = pending.drain<void>().catchError((Object _) {});
        await reached.future;
        service.dispose();
        expect(service.ipadToken, isNull);
        expect(service.isRunning, isFalse);
        snapshot.complete(setup.native.value);
        await service.disableIpad();
        await drained;
        await ended.future;
        await subscription.cancel();
        expect(setup.effects, 2);
        await service.enableIpad(
          policy: setup.policy,
          persistSettings: () async => true,
        );
        expect(service.isRunning, isFalse);
      },
    );

    // AC-003: desktop binding never selects an eligible native address or owns
    // a separately supplied ServerSocket, so it cannot prove both-owner cleanup.
    test(
      'AC-003 selected-address exclusive IPv4/IPv6 binding and both owners close',
      () {
        for (final ipv6 in [false, true]) {
          fakeAsync((time) {
            final h = _IpadHarness(time, ipv6: ipv6)..enable();
            expect(h.service.ipadState, McpIpadState.running);
            expect(h.binds.single, (h.policy.address.text, 3847, false, ipv6));
            final session = h.session();
            final stream = h.send(method: 'GET', session: session);
            expect(stream.status, 200);
            unawaited(h.service.disableIpad());
            expect(h.service.ipadToken, isNull);
            expect(h.service.isRunning, isFalse);
            expect(stream.destroyed, isTrue);
            h.flush();
            expect(h.listeners.single.closes, 1);
            expect(h.httpServers.single.closes, 1);
            expect(h.service.connectionDiagnostics['active_registries'], 0);
            h.clean();
          });
        }
      },
    );

    // AC-003: a valid Host alone cannot prove the actual accepted socket tuple.
    test(
      'AC-003 actual destination and peer reject forged proxy authority before parsing',
      () {
        fakeAsync((time) {
          final h = _IpadHarness(time)..enable();
          for (final row in [
            ('192.168.2.9', 3847, '192.168.2.2'),
            ('192.168.2.1', 3848, '192.168.2.2'),
            ('192.168.2.1', 3847, '192.168.2.3'),
          ]) {
            final socket = h.send(
              local: row.$1,
              port: row.$2,
              peer: row.$3,
              headers: [
                'Host: 192.168.2.1:3847',
                'Authorization: Bearer ${h.service.ipadToken}',
                'Forwarded: for=192.168.2.2;host=192.168.2.1:3847',
                'X-Forwarded-For: 192.168.2.2',
                'X-Real-IP: 192.168.2.2',
              ],
            );
            expect(socket.destroyed, isTrue);
            expect(socket.output, isEmpty);
          }
          expect(h.connects, 0);
          expect(h.effects, 0);
          h.clean();
        });
      },
    );

    // AC-003: real parser connectionInfo must still match retained socket evidence.
    test(
      'AC-003 absent or inconsistent connectionInfo cannot allocate a registry',
      () {
        for (final info in <HttpConnectionInfo?>[
          null,
          _Info(localPort: 9999),
          _Info(remotePort: 9999),
          _Info(peer: '192.168.2.3'),
        ]) {
          fakeAsync((time) {
            final h = _IpadHarness(time, changeInfo: (_) => info)..enable();
            expect(h.send().status, 403);
            expect(h.connects, 0);
            expect(h.effects, 0);
            h.clean();
          });
        }
      },
    );

    // AC-003/006: same-IP updates and stale native replies are not exercised by
    // address-policy unit tests, which do not own running sessions or SSE.
    test(
      'AC-003 AC-006 fresh request snapshot changes revoke live authority',
      () {
        for (final changed in [
          _nativeSnapshot(generation: 4),
          _nativeSnapshot(generation: 2),
          _nativeSnapshot(name: 'changed-lan'),
          _nativeSnapshot(prefix: 16),
        ]) {
          fakeAsync((time) {
            final h = _IpadHarness(time)..enable();
            final id = h.session();
            final sse = h.send(method: 'GET', session: id);
            h.native.value = changed;
            h.send(session: id, body: _effectBody);
            expect(h.service.ipadToken, isNull);
            expect(h.service.ipadState, McpIpadState.failed);
            expect(
              h.service.ipadReason?.toLowerCase(),
              contains('enable again'),
            );
            expect(sse.destroyed, isTrue);
            expect(h.effects, 0);
            expect(h.listeners.single.closes, 1);
            expect(h.httpServers.single.closes, 1);
            h.clean();
          });
        }
      },
    );

    // AC-004: table covers current AND stale session effects across every method;
    // desktop tests intentionally have no iPad bearer/Origin/Host outer guards.
    test(
      'AC-004 negative method/header/target matrix has no allocation deletion or dispatch',
      () {
        fakeAsync((time) {
          final h = _IpadHarness(time)..enable();
          final current = h.session();
          final token = h.service.ipadToken!;
          final host = 'Host: 192.168.2.1:3847';
          final auth = 'Authorization: Bearer $token';
          final rows = <(List<String>, String, int)>[
            ([host], '/mcp', 401),
            ([host, 'Authorization: Bearer ${'x' * 43}'], '/mcp', 401),
            ([host, auth, auth], '/mcp', 401),
            ([host, '$auth, Bearer $token'], '/mcp', 401),
            ([host, '$auth '], '/mcp', 401),
            ([host, auth, ' continued'], '/mcp', 403),
            ([host, 'Authorization: Basic $token'], '/mcp', 401),
            ([host, 'Authorization: Bearer ${'x' * 129}'], '/mcp', 401),
            ([auth], '/mcp', 403),
            ([host, host, auth], '/mcp', 403),
            ...[
              'localhost:3847',
              '192.168.2.1',
              '192.168.2.1:3848',
              '192.168.2.1:abc',
              '192.168.2.1:3847,other',
              '192.168.2.1:3847/path',
              'user@192.168.2.1:3847',
              '192.168.2.1 :3847',
              '192.168.2.1:3847 ',
              '[192.168.2.1]:3847',
              '[fd12::1%en0]:3847',
              'a' * 129,
            ].map((v) => (['Host: $v', auth], '/mcp', 403)),
            ...[
              '',
              'null',
              'http://192.168.2.1:3847',
              'https://other.example',
            ].map((v) => ([host, auth, 'Origin: $v'], '/mcp', 403)),
            ([host, auth, 'Origin: null', 'Origin: null'], '/mcp', 403),
            ...[
              '/other',
              '/mcp?x=1',
              '/mcp?',
              '/%6dcp',
              '/a/../mcp',
              'http://192.168.2.1:3847/mcp',
              '//192.168.2.1:3847/mcp',
              '*',
            ].map((v) => ([host, auth], v, 404)),
          ];
          final before = Map.of(h.service.connectionDiagnostics);
          final connections = h.connects;
          for (final session in [null, current, 'stale-session']) {
            for (final method in ['POST', 'GET', 'DELETE', 'OPTIONS']) {
              for (final row in rows) {
                final rejected = h.send(
                  method: method,
                  target: row.$2,
                  session: session,
                  headers: row.$1,
                  body: session == null ? _initBody : _effectBody,
                );
                expect(
                  rejected.status,
                  row.$3,
                  reason: '$method ${row.$2} ${row.$1} => ${rejected.response}',
                );
                expect(
                  rejected.response.toLowerCase(),
                  isNot(contains('access-control-')),
                );
                expect(h.service.connectionDiagnostics, before);
                expect(h.connects, connections);
                expect(h.effects, 0);
              }
            }
            for (final method in ['OPTIONS', 'PATCH', 'PUT', 'HEAD']) {
              expect(
                h
                    .send(method: method, session: session, body: _effectBody)
                    .status,
                405,
              );
              expect(h.service.connectionDiagnostics, before);
            }
          }
          h.clean();
        });
      },
    );

    // AC-005: previous stop/body regression does not defer native checks or a
    // per-generation session connection, nor exercise secure credential rotation.
    test('AC-005 deferred persistence and failed RNG never revive consent', () {
      fakeAsync((time) {
        final h = _IpadHarness(time);
        final save = Completer<bool>();
        h.enable(save: () => save.future);
        expect(h.binds, isEmpty);
        expect(h.randomCalls, 0);
        unawaited(h.service.disableIpad());
        save.complete(true);
        h.flush();
        expect(h.binds, isEmpty);
        expect(h.randomCalls, 0);
        h.enable(save: () async => false);
        expect(h.binds, isEmpty);
        h.rngFails = true;
        h.enable();
        expect(h.service.ipadState, McpIpadState.failed);
        expect(h.service.ipadToken, isNull);
        expect(h.binds, isEmpty);
        h.clean();
      });
    });

    // AC-005: binding can complete after OFF; only the latest coalesced intent
    // may listen, while the late old socket must dispose itself.
    test(
      'AC-005 late bind rapid toggles and rotation admit only newest generation',
      () {
        fakeAsync((time) {
          final h = _IpadHarness(time);
          final gate = Completer<ServerSocket>();
          h.bindGate = gate;
          h.enable();
          final oldToken = h.service.ipadToken;
          unawaited(h.service.disableIpad());
          expect(h.service.ipadToken, isNull);
          expect(h.service.isRunning, isFalse);
          h.enable();
          unawaited(
            h.service.regenerateIpad(
              policy: h.policy,
              persistSettings: () async => true,
            ),
          );
          h.flush();
          final late = _MemoryListener(InternetAddress('192.168.2.1'));
          gate.complete(late);
          h.flush();
          expect(late.closes, 1);
          expect(h.binds.length, 2);
          expect(h.service.ipadState, McpIpadState.running);
          expect(h.service.ipadToken, isNot(oldToken));
          h.session();
          final runningToken = h.service.ipadToken;
          unawaited(
            h.service.regenerateIpad(
              policy: h.policy,
              persistSettings: () async => true,
            ),
          );
          expect(h.service.ipadToken, isNull);
          expect(h.service.isRunning, isFalse);
          h.flush();
          expect(h.service.ipadToken, isNot(runningToken));
          final id = h.session();
          final before = Map.of(h.service.connectionDiagnostics);
          for (final session in [id, 'stale-session']) {
            for (final method in ['POST', 'GET', 'DELETE', 'OPTIONS']) {
              final response = h.send(
                method: method,
                session: session,
                body: _effectBody,
                headers: [
                  'Host: 192.168.2.1:3847',
                  'Authorization: Bearer $runningToken',
                ],
              );
              expect(response.status, 401);
              expect(
                response.response.toLowerCase(),
                isNot(contains('access-control-')),
              );
              expect(h.service.connectionDiagnostics, before);
              expect(h.effects, 0);
            }
          }
          h.clean();
        });
      },
    );

    // AC-005: validation-pending requests must have no effects; stale callbacks
    // must not remove a newer generation's maps, even with the same session ID.
    test(
      'AC-005 deferred snapshot body and connect self-dispose after revocation',
      () {
        for (final boundary in ['snapshot', 'body', 'connect']) {
          fakeAsync((time) {
            final h = _IpadHarness(time)..enable();
            final native = Completer<McpLanSnapshot>();
            final connect = Completer<void>();
            if (boundary == 'snapshot') h.native.read = (_) => native.future;
            if (boundary == 'connect') h.connectGate = connect;
            final old = h.send(
              session: 'same-session',
              body: _effectBody,
              partial: boundary == 'body',
            );
            if (boundary != 'connect') expect(h.connects, 0);
            unawaited(h.service.disableIpad());
            expect(h.service.ipadToken, isNull);
            expect(old.destroyed, isTrue);
            h.native.read = null;
            h.connectGate = null;
            h.enable();
            h.send(session: 'same-session', body: _initBody);
            final before = Map.of(h.service.connectionDiagnostics);
            expect(before['active_registries'], 1);
            expect(before['active_servers'], 1);
            final effects = h.effects;
            native.complete(_nativeSnapshot());
            connect.complete();
            old.receive(jsonEncode(_effectBody));
            h.flush();
            expect(h.service.connectionDiagnostics, before);
            expect(h.effects, effects);
            expect(h.service.ipadState, McpIpadState.running);
            h.clean();
          });
        }
      },
    );

    // AC-005: pending start snapshots and slow owner cleanup differ from the
    // request/body/connect races above; neither may publish stale listeners.
    test(
      'AC-005 start snapshot late bind dispose and slow cleanup coalesce safely',
      () {
        for (final phase in [
          'beforeBind',
          'afterBind',
          'lateBindDispose',
          'cleanup',
        ]) {
          fakeAsync((time) {
            final h = _IpadHarness(time);
            final snapshot = Completer<McpLanSnapshot>();
            final bind = Completer<ServerSocket>();
            final close = Completer<void>();
            if (phase == 'beforeBind' || phase == 'afterBind') {
              h.native.read = (n) => n == (phase == 'beforeBind' ? 1 : 2)
                  ? snapshot.future
                  : Future.value(h.native.value);
            }
            if (phase == 'lateBindDispose') h.bindGate = bind;
            h.enable();
            if (phase == 'cleanup') {
              h.session();
              h.listeners.single.closeGate = close;
            }
            if (phase == 'lateBindDispose') {
              h.service.dispose();
              final late = _MemoryListener(InternetAddress('192.168.2.1'));
              bind.complete(late);
              h.flush();
              expect(late.closes, 1);
              expect(h.httpServers, isEmpty);
              expect(h.service.ipadToken, isNull);
            } else {
              final stopped = h.service.stop();
              expect(h.service.ipadToken, isNull);
              expect(h.service.isRunning, isFalse);
              expect(h.service.connectionDiagnostics['active_registries'], 0);
              h.native.read = null;
              h.enable();
              if (phase == 'cleanup') expect(h.binds.length, 1);
              snapshot.complete(_nativeSnapshot());
              close.complete();
              h.flush();
              unawaited(stopped);
              expect(h.service.ipadState, McpIpadState.running);
              expect(h.service.connectionDiagnostics['active_servers'], 0);
              if (phase == 'afterBind' || phase == 'cleanup') {
                expect(h.listeners.first.closes, 1);
              }
            }
            h.clean();
          });
        }
      },
    );

    // AC-003/005: a failed selected bind must not try a wildcard/family fallback,
    // and a stopped/restarted service must not treat retry as fresh consent.
    test(
      'AC-003 AC-005 bind failure stays failed until explicit saved retry',
      () {
        fakeAsync((time) {
          final h = _IpadHarness(time)..bindFails = true;
          h.enable();
          expect(h.binds.length, 1);
          expect(h.httpServers, isEmpty);
          expect(h.service.ipadState, McpIpadState.failed);
          expect(h.service.ipadReason?.toLowerCase(), contains('port 3847'));
          expect(h.service.ipadToken, isNull);
          unawaited(h.service.ipadLifecycleChanged('resumed'));
          h.flush();
          expect(h.binds.length, 1);
          h.bindFails = false;
          h.enable();
          expect(h.service.ipadState, McpIpadState.running);
          unawaited(h.service.restart());
          h.flush();
          expect(h.service.ipadState, McpIpadState.off);
          expect(h.binds.length, 2);
          h.clean();
        });
      },
    );

    // AC-006: the distinct inactive recovery rule requires live-resource tests;
    // no existing desktop stop/start test models retained enable-interval trust.
    test(
      'AC-006 only transient inactive resumes with matching fresh context',
      () {
        fakeAsync((time) {
          final h = _IpadHarness(time)..enable();
          final id = h.session();
          final sse = h.send(method: 'GET', session: id);
          final token = h.service.ipadToken;
          unawaited(h.service.ipadLifecycleChanged('inactive'));
          expect(h.service.isRunning, isFalse);
          expect(sse.destroyed, isTrue);
          expect(h.service.ipadToken, token);
          h.flush();
          expect(h.service.ipadState, McpIpadState.paused);
          unawaited(h.service.ipadLifecycleChanged('resumed'));
          h.flush();
          expect(
            h.service.ipadState,
            McpIpadState.running,
            reason: '${h.binds} ${h.service.ipadReason}',
          );
          expect(h.service.ipadToken, token);
          expect(h.binds.length, 2);
          expect(h.service.connectionDiagnostics['active_servers'], 0);
          unawaited(h.service.ipadLifecycleChanged('inactive'));
          h.flush();
          h.native.value = _nativeSnapshot(generation: 4);
          unawaited(h.service.ipadLifecycleChanged('resumed'));
          h.flush();
          expect(h.service.ipadState, McpIpadState.failed);
          expect(h.service.ipadToken, isNull);
          expect(h.binds.length, 2);
          h.clean();
        });
      },
    );

    // AC-006: every real/unknown transition, observed same-IP path update and
    // bridge/monitor failure revokes; checking only background misses these.
    test(
      'AC-006 background path unknown and bridge failure require explicit re-enable',
      () {
        for (final transition in [
          'background',
          'hidden',
          'paused',
          'detached',
          'unknown',
          'path',
          'monitor',
          'bridge',
        ]) {
          fakeAsync((time) {
            final h = _IpadHarness(time)..enable();
            final id = h.session();
            final stream = h.send(method: 'GET', session: id);
            if (transition == 'path' || transition == 'monitor') {
              unawaited(
                h.service.ipadNetworkChanged(failed: transition == 'monitor'),
              );
            } else if (transition == 'bridge') {
              h.native.read = (_) =>
                  Future.error(StateError('bridge unavailable'));
              h.send(session: id, body: _effectBody);
            } else {
              unawaited(h.service.ipadLifecycleChanged(transition));
            }
            expect(h.service.ipadToken, isNull);
            expect(stream.destroyed, isTrue);
            h.flush();
            expect(h.service.isRunning, isFalse);
            expect(h.effects, 0);
            expect(h.listeners.single.closes, 1);
            expect(h.httpServers.single.closes, 1);
            expect(
              h.service.ipadReason?.toLowerCase(),
              contains('enable again'),
            );
            unawaited(h.service.ipadLifecycleChanged('resumed'));
            h.flush();
            expect(h.binds.length, 1);
            expect(h.service.isRunning, isFalse);
            h.native.read = null;
            h.enable();
            expect(h.service.isRunning, isTrue);
            h.clean();
          });
        }
      },
    );
  });
}

void main() {
  _ipadRuntimeTests();
  _ipadCapacityTests();
  _ipadNativeClientTests();
  group('McpServerService transports', () {
    late McpServerService service;
    late MockDistingCubit distingCubit;
    late HttpOverrides? previousHttpOverrides;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      distingCubit = MockDistingCubit();
      final manager = MockDistingMidiManager();
      when(() => distingCubit.state).thenReturn(
        DistingState.synchronized(
          disting: manager,
          distingVersion: '1.19.0',
          firmwareVersion: FirmwareVersion('1.19.0'),
          presetName: 'Transport test',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
        ),
      );
      when(() => distingCubit.requestFreshMemoryUsage()).thenAnswer(
        (_) async => const MemoryUsage(
          sram: MemoryPoolUsage(total: 100, current: 10),
          dram: MemoryPoolUsage(total: 200, current: 20),
          dtc: MemoryPoolUsage(total: 300, current: 30),
          itc: MemoryPoolUsage(total: 400, current: 40),
        ),
      );
      McpServerService.initialize(distingCubit: distingCubit);
      service = McpServerService.instance;
    });

    tearDownAll(() {
      HttpOverrides.global = previousHttpOverrides;
    });

    tearDown(() async {
      await service.stop();
    });

    test('Streamable HTTP: initialize + initialized notification', () async {
      await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);

      final port = service.boundPort;
      expect(port, isNotNull);

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      await _initializeSession(client, port!);
    });

    test(
      'a deferred initialize body cannot create a session after stop',
      () async {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final received = DebugService().debugStream.firstWhere(
          (message) => message.contains('Request: POST /mcp'),
        );
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${service.boundPort}/mcp'),
        );
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
          ..set(HttpHeaders.contentTypeHeader, 'application/json');
        request.write('{"jsonrpc":"2.0",');
        await request.flush();
        await received.timeout(const Duration(seconds: 2));

        final stopped = service.stop();
        expect(service.isRunning, isFalse);
        // Complete the body while stop is awaiting asynchronous resource cleanup.
        request.write(
          '"id":1,"method":"initialize","params":'
          '{"protocolVersion":"2025-06-18","capabilities":{},'
          '"clientInfo":{"name":"deferred-client","version":"1"}}}',
        );
        final finished = request.close().then<void>(
          (response) => response.drain<void>(),
          onError: (Object _) {},
        );
        await stopped;
        await finished.timeout(const Duration(seconds: 2));
        expect(service.connectionDiagnostics['active_registries'], 0);
        expect(service.connectionDiagnostics['active_servers'], 0);
        expect(service.connectionDiagnostics['active_transports'], 0);
      },
    );

    test('DELETE disposes only the terminated session registry', () async {
      await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);
      final port = service.boundPort!;
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final first = await _initializeSession(client, port);
      final second = await _initializeSession(client, port, id: 2);
      expect(service.connectionDiagnostics['active_registries'], 2);

      final request = await client.openUrl(
        'DELETE',
        Uri.parse('http://127.0.0.1:$port/mcp'),
      );
      request.headers
        ..set('mcp-session-id', first)
        ..set('mcp-protocol-version', '2025-06-18');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
      expect(service.connectionDiagnostics['active_registries'], 1);
      expect(service.connectionDiagnostics['active_servers'], 1);
      expect(service.connectionDiagnostics['active_transports'], 1);

      final listResponse = await _postJsonRpc(client, port, {
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/list',
        'params': <String, dynamic>{},
      }, sessionId: second);
      expect((await _readJsonRpcMessage(listResponse))['error'], isNull);

      await service.stop();
      expect(service.connectionDiagnostics['active_registries'], 0);
      expect(service.connectionDiagnostics['active_servers'], 0);
      expect(service.connectionDiagnostics['active_transports'], 0);
    });

    test(
      'GET /mcp opens standalone SSE stream for an initialized session',
      () async {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);

        final port = service.boundPort;
        expect(port, isNotNull);

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final sessionId = await _initializeSession(client, port!);

        final getRequest = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        getRequest.headers
          ..set(HttpHeaders.acceptHeader, 'text/event-stream')
          ..set('mcp-session-id', sessionId);

        final response = await getRequest.close().timeout(
          const Duration(seconds: 5),
        );
        expect(response.statusCode, equals(HttpStatus.ok));
        expect(
          response.headers.contentType?.mimeType,
          equals('text/event-stream'),
        );

        final firstChunk = await response.first.timeout(
          const Duration(seconds: 5),
        );
        expect(utf8.decode(firstChunk), contains('data:'));
      },
    );

    test(
      'add without target returns tool result and does not block subsequent calls',
      () async {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);

        final port = service.boundPort;
        expect(port, isNotNull);

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final sessionId = await _initializeSession(client, port!);

        final addResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'add',
            'arguments': {'name': 'VCO/Multiplier'},
          },
        }, sessionId: sessionId);
        expect(addResponse.statusCode, equals(HttpStatus.ok));
        final addMessage = await _readJsonRpcMessage(addResponse);
        expect(addMessage['id'], equals(2));
        expect(addMessage.containsKey('result'), isTrue);
        expect(addMessage.containsKey('error'), isFalse);

        final removeResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'remove',
            'arguments': {'slot_index': 0},
          },
        }, sessionId: sessionId);
        expect(removeResponse.statusCode, equals(HttpStatus.ok));
        final removeMessage = await _readJsonRpcMessage(removeResponse);
        expect(removeMessage['id'], equals(3));
        expect(removeMessage.containsKey('result'), isTrue);
        expect(removeMessage.containsKey('error'), isFalse);

        final saveResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {'name': 'save', 'arguments': <String, dynamic>{}},
        }, sessionId: sessionId);
        expect(saveResponse.statusCode, equals(HttpStatus.ok));
        final saveMessage = await _readJsonRpcMessage(saveResponse);
        expect(saveMessage['id'], equals(4));
        expect(saveMessage.containsKey('result'), isTrue);
      },
    );

    test(
      'remove out-of-range slot_index returns tool result and does not block subsequent calls',
      () async {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);

        final port = service.boundPort;
        expect(port, isNotNull);

        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final sessionId = await _initializeSession(client, port!, id: 11);

        final removeResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 12,
          'method': 'tools/call',
          'params': {
            'name': 'remove',
            'arguments': {'slot_index': 99},
          },
        }, sessionId: sessionId);
        expect(removeResponse.statusCode, equals(HttpStatus.ok));
        final removeMessage = await _readJsonRpcMessage(removeResponse);
        expect(removeMessage['id'], equals(12));
        expect(removeMessage.containsKey('result'), isTrue);
        expect(removeMessage.containsKey('error'), isFalse);

        final saveResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 13,
          'method': 'tools/call',
          'params': {'name': 'save', 'arguments': <String, dynamic>{}},
        }, sessionId: sessionId);
        expect(saveResponse.statusCode, equals(HttpStatus.ok));
        final saveMessage = await _readJsonRpcMessage(saveResponse);
        expect(saveMessage['id'], equals(13));
        expect(saveMessage.containsKey('result'), isTrue);
      },
    );

    test(
      'show_memory is listed and returns fresh byte values over MCP',
      () async {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);

        final port = service.boundPort;
        expect(port, isNotNull);

        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final sessionId = await _initializeSession(client, port!, id: 21);

        final listResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 22,
          'method': 'tools/list',
          'params': <String, dynamic>{},
        }, sessionId: sessionId);
        final listMessage = await _readJsonRpcMessage(listResponse);
        final tools =
            (listMessage['result'] as Map<String, dynamic>)['tools'] as List;
        expect(
          tools.whereType<Map>().map((tool) => tool['name']),
          contains('show_memory'),
        );

        final callResponse = await _postJsonRpc(client, port, {
          'jsonrpc': '2.0',
          'id': 23,
          'method': 'tools/call',
          'params': {'name': 'show_memory', 'arguments': <String, dynamic>{}},
        }, sessionId: sessionId);
        expect(callResponse.statusCode, equals(HttpStatus.ok));
        final callMessage = await _readJsonRpcMessage(callResponse);
        final result = callMessage['result'] as Map<String, dynamic>;
        final content = result['content'] as List;
        final text = (content.single as Map<String, dynamic>)['text'] as String;
        final memory = jsonDecode(text) as Map<String, dynamic>;

        expect(memory['success'], isTrue);
        expect(memory['memory_usage'], {
          'sram': {'current_bytes': 10, 'total_bytes': 100, 'free_bytes': 90},
          'dram': {'current_bytes': 20, 'total_bytes': 200, 'free_bytes': 180},
          'dtc': {'current_bytes': 30, 'total_bytes': 300, 'free_bytes': 270},
          'itc': {'current_bytes': 40, 'total_bytes': 400, 'free_bytes': 360},
        });
        verify(() => distingCubit.requestFreshMemoryUsage()).called(1);
      },
    );
  });
}
