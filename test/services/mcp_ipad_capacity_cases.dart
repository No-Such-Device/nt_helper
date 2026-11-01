part of 'mcp_server_service_transport_test.dart';

// Real HTTP/SDK; only native/socket identity is simulated. I/O uses completion
// signals, and every listener/tool timer uses a virtual clock, never a sleep.
class _RealIpad {
  final setup = _IpadHarness(FakeAsync());
  final clock = FakeAsync();
  late McpServerService service;
  late _LoopbackListener listener;
  late HttpClient http;
  late Zone timerZone;
  Completer<_MemorySocket>? getPrimed;
  HttpOverrides? previous;
  Completer<void>? timerArmed;
  Completer<void>? connectGate;
  Completer<void>? connectReached;
  bool connectFails = false;
  int connects = 0;
  int connectTarget = 8;
  final requests = <(String, String?, String?)>[];
  final accepted = <Socket>[];
  final getResponses = <HttpResponse>[];

  Future<void> start() async {
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    http = HttpClient();
    service = McpServerService.forTesting(
      distingCubit: setup.cubit,
      context: setup.native,
      randomBytes: () => List.filled(32, ++setup.randomCalls),
      bindSocket: (address, port, {required shared, required v6Only}) async =>
          listener = _LoopbackListener(
            await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          ),
      listenOn: (s) => _ObservedHttpServer(
        HttpServer.listenOn(_SocketTap(s, accepted.add)),
        null,
        observe: (r) {
          requests.add((
            r.method,
            r.headers.value('authorization'),
            r.headers.value('last-event-id'),
          ));
          if (r.method == 'GET') {
            getResponses.add(r.response);
            final socket = listener.sockets.firstWhere(
              (s) => s.peerPort == r.connectionInfo!.remotePort,
            );
            socket.onOutput = () {
              if (socket.response.contains('data:') &&
                  getPrimed != null &&
                  !getPrimed!.isCompleted) {
                getPrimed!.complete(socket);
              }
            };
          }
        },
      ),
      beforeSessionConnect: () async {
        connects++;
        if (connects == connectTarget) connectReached?.complete();
        await connectGate?.future;
        if (connectFails) throw StateError('Connect failed');
      },
    );
    await runZoned(
      () {
        timerZone = Zone.current;
        return service.enableIpad(
          policy: setup.policy,
          persistSettings: () async => true,
        );
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = clock.run(
            (_) => Timer(duration, () => zone.run(callback)),
          );
          if (duration == Duration.zero) {
            parent.scheduleMicrotask(zone, () => clock.elapse(Duration.zero));
          }
          if (duration == const Duration(seconds: 10) &&
              timerArmed != null &&
              !timerArmed!.isCompleted) {
            timerArmed!.complete();
          }
          return timer;
        },
        createPeriodicTimer: (self, parent, zone, duration, callback) =>
            clock.run(
              (_) =>
                  Timer.periodic(duration, (t) => zone.run(() => callback(t))),
            ),
      ),
    );
  }

  Uri get url => Uri.parse('http://127.0.0.1:${listener.inner.port}/mcp');
  String get bearer => 'Bearer ${service.ipadToken}';
  Future<HttpClientResponse> request({
    String method = 'POST',
    String? session,
    Object? body,
    String? payload,
    bool authorized = true,
    String? credential,
    bool chunked = false,
  }) async {
    final r = await http.openUrl(method, url);
    r.headers
      ..set('Host', '192.168.2.1:3847')
      ..set('Accept', 'application/json, text/event-stream')
      ..set('Content-Type', 'application/json');
    if (authorized) r.headers.set('Authorization', credential ?? bearer);
    if (session != null) r.headers.set('mcp-session-id', session);
    if (chunked) r.contentLength = -1;
    if (method == 'POST') r.write(payload ?? jsonEncode(body ?? _initBody));
    return r.close();
  }

  Future<int> status({
    String method = 'POST',
    String? session,
    Object? body,
  }) async {
    final r = await request(method: method, session: session, body: body);
    await r.drain<void>();
    return r.statusCode;
  }

  Future<String> session() async {
    final r = await request();
    expect(r.statusCode, 200);
    final id = r.headers.value('mcp-session-id')!;
    expect(
      await utf8.decodeStream(r),
      contains('"protocolVersion":"2025-06-18"'),
    );
    expect(
      await status(
        session: id,
        body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      ),
      202,
    );
    return id;
  }

  // Raw HTTP only to leave a body unfinished, using the same listener/parser.
  Future<_SlowPost> slow(String session) async {
    timerArmed = Completer<void>();
    final s = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.inner.port,
    );
    final post = _SlowPost(s);
    post.payload = jsonEncode(_effectBody);
    s.write(
      'POST /mcp HTTP/1.1\r\nHost: 192.168.2.1:3847\r\n'
      'Authorization: $bearer\r\nmcp-session-id: $session\r\n'
      'Accept: application/json, text/event-stream\r\nContent-Type: application/json\r\n'
      'Transfer-Encoding: chunked\r\n\r\n',
    );
    await s.flush();
    await timerArmed!.future;
    return post;
  }

  Future<void> clean() async {
    await service.disableIpad();
    service.dispose();
    setup.service.dispose();
    http.close(force: true);
    HttpOverrides.global = previous;
    verifyZeroInteractions(setup.midi);
  }
}

class _SocketTap extends Stream<Socket> implements ServerSocket {
  _SocketTap(this.inner, this.accepted);
  final ServerSocket inner;
  final void Function(Socket) accepted;
  @override
  InternetAddress get address => inner.address;
  @override
  int get port => inner.port;
  @override
  Future<ServerSocket> close() => inner.close();
  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner
      .map((socket) {
        accepted(socket);
        return socket;
      })
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

class _SlowPost {
  _SlowPost(this.socket) {
    socket.listen(
      bytes.addAll,
      onDone: done.complete,
      onError: done.completeError,
    );
  }
  final Socket socket;
  final bytes = <int>[];
  final done = Completer<void>();
  late String payload;
  String get response => utf8.decode(bytes);
  void chunk(String value) => socket.write(
    '${utf8.encode(value).length.toRadixString(16)}\r\n$value\r\n',
  );
  void finish() {
    chunk(payload);
    socket.write('0\r\n\r\n');
  }
}

void _ipadNativeClientTests() {
  // AC-010: manual JSON-RPC helpers cannot prove the pinned client's handshake,
  // Authorization propagation, standalone SSE, resumption or DELETE behavior.
  test(
    'AC-010 pinned native SDK completes authorized SSE resume and DELETE round trip',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      final old = h.bearer;
      await h.timerZone.run(
        () => h.service.regenerateIpad(
          policy: h.setup.policy,
          persistSettings: () async => true,
        ),
      );
      await h.timerZone.run(() async {
        final transport = StreamableHttpClientTransport(
          h.url,
          opts: StreamableHttpClientTransportOptions(
            requestInit: {
              'headers': {
                'Authorization': h.bearer,
                'Host': '192.168.2.1:3847',
              },
            },
          ),
        );
        final client = McpClient(
          Implementation(name: 'native-reference', version: '1'),
          options: const McpClientOptions(
            protocolVersion: '2025-06-18',
            useServerDiscover: false,
          ),
        );
        addTearDown(client.close);
        h.getPrimed = Completer<_MemorySocket>();
        await client.connect(transport);
        final standalone = await h.getPrimed!.future;
        expect(standalone.response, contains('text/event-stream'));
        final tools = await client.listTools();
        expect(tools.tools.map((t) => t.name), contains('show_memory'));
        await client.ping();
        final result = await client.callTool(
          CallToolRequest(name: 'show_memory', arguments: {}),
        );
        expect(
          (result.content.single as TextContent).text,
          contains('memory_usage'),
        );
        expect(h.setup.effects, 1);

        // Public SDK send/resumption APIs, not a hand-built protocol client.
        final first = Completer<JsonRpcMessage>();
        final replayed = Completer<JsonRpcMessage>();
        final dispatch = transport.onmessage;
        transport.onmessage = (message) {
          if (message is JsonRpcResponse && message.id == 900) {
            if (!first.isCompleted) {
              first.complete(message);
            } else if (!replayed.isCompleted) {
              replayed.complete(message);
            }
          } else {
            dispatch?.call(message);
          }
        };
        String? cursor;
        await transport.send(
          const JsonRpcRequest(id: 900, method: 'ping'),
          onResumptionToken: (token) => cursor ??= token,
        );
        await first.future;
        expect(cursor, isNotNull);
        final posts = h.requests.where((r) => r.$1 == 'POST').length;
        h.getPrimed = Completer<_MemorySocket>();
        await transport.send(
          const JsonRpcRequest(id: 900, method: 'ping'),
          resumptionToken: cursor,
        );
        expect((await replayed.future as JsonRpcResponse).result, isEmpty);
        await h.getPrimed!.future;
        expect(h.requests.where((r) => r.$1 == 'POST'), hasLength(posts));
        expect(h.requests, contains(('GET', h.bearer, cursor)));
        final session = transport.sessionId!;
        final authorizedRequests = List.of(h.requests);
        expect(
          authorizedRequests.map((r) => r.$1).toSet(),
          containsAll(['POST', 'GET']),
        );
        expect(authorizedRequests.every((r) => r.$2 == h.bearer), isTrue);
        final wire = h.listener.sockets
            .map((s) => utf8.decode(s.received))
            .join();
        expect(wire, contains('"method":"initialize"'));
        expect(wire, contains('"protocolVersion":"2025-06-18"'));
        expect(wire, contains('"method":"notifications/initialized"'));
        expect(wire, isNot(contains('server/discover')));

        // Each negative credential is rejected on every HTTP method, with both
        // live/stale sessions and no allocation, tool effect, deletion or eviction.
        final before = h.service.connectionDiagnostics;
        for (final credential in <String?>[null, 'Bearer ${'Z' * 43}', old]) {
          for (final method in ['POST', 'GET', 'DELETE']) {
            for (final id in [session, 'stale-session']) {
              final r = await h.request(
                method: method,
                session: id,
                body: _effectBody,
                authorized: credential != null,
                credential: credential,
              );
              expect(r.statusCode, 401);
              await r.drain<void>();
            }
          }
        }
        expect(h.service.connectionDiagnostics, before);
        expect(h.setup.effects, 1);
        await client.ping();
        await transport.terminateSession();
        expect(h.requests.last, ('DELETE', h.bearer, null));
        expect(h.service.connectionDiagnostics['active_servers'], 0);
        expect(h.service.connectionDiagnostics['active_registries'], 0);
        await Future.wait(h.getResponses.map((r) => r.done));
        await client.close();
      });
    },
  );
}

void _ipadCapacityTests() {
  // AC-008: prior admission tests never filled session capacity or proved reuse.
  test(
    'AC-008 eight sessions reject excess without dispatch or eviction and recover',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      final ids = <String>[];
      for (var i = 0; i < 8; i++) {
        ids.add(await h.session());
      }
      expect(await h.status(), 429);
      expect(h.connects, 8);
      expect(h.setup.effects, 0);
      expect(await h.status(session: ids.first, body: _effectBody), 200);
      expect(h.setup.effects, 1);
      expect(await h.status(method: 'DELETE', session: ids.last), 200);
      expect(await h.status(body: {'invalid': true}), 400);
      expect(h.service.connectionDiagnostics['active_registries'], 7);
      await h.session();
      expect(h.service.connectionDiagnostics['active_servers'], 8);
    },
  );

  // AC-008: sequential sessions cannot expose initialization reservations.
  test(
    'AC-008 eight concurrent reservations and failed connections clean up',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      h.connectGate = Completer<void>();
      h.connectReached = Completer<void>();
      final pending = List.generate(8, (_) => h.request());
      await h.connectReached!.future;
      expect(await h.status(), 429);
      expect(h.service.connectionDiagnostics['active_registries'], 8);
      expect(h.service.connectionDiagnostics['active_servers'], 0);
      h.connectGate!.complete();
      final ids = <String>[];
      for (final response in pending) {
        final r = await response;
        expect(r.statusCode, 200);
        ids.add(r.headers.value('mcp-session-id')!);
        await r.drain<void>();
      }
      expect(ids.toSet(), hasLength(8));
      for (final id in ids) {
        expect(await h.status(method: 'DELETE', session: id), 200);
      }
      h.connectGate = null;
      h.connectFails = true;
      expect(await h.status(), 500);
      expect(h.service.connectionDiagnostics['active_registries'], 0);
      h.connectFails = false;
      final retained = await h.session();
      expect(h.setup.effects, 0);
      // Two initializations can race to reclaim the same stale session ID.
      // The losing transport must release only its own reservation, not evict
      // the winner or a different live client.
      h.connectGate = Completer<void>();
      h.connectReached = Completer<void>();
      h.connectTarget = h.connects + 2;
      final racing = List.generate(
        2,
        (_) => h.request(session: 'same-session'),
      );
      await h.connectReached!.future;
      h.connectGate!.complete();
      final statuses = <int>[];
      for (final pending in racing) {
        final response = await pending;
        statuses.add(response.statusCode);
        await response.drain<void>();
      }
      expect(statuses..sort(), [200, 500]);
      expect(h.service.connectionDiagnostics['active_servers'], 2);
      expect(h.service.connectionDiagnostics['active_registries'], 2);
      expect(
        await h.status(
          session: 'same-session',
          body: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        ),
        202,
      );
      expect(await h.status(session: retained, body: _effectBody), 200);
      expect(await h.status(session: 'same-session', body: _effectBody), 200);
      expect(h.setup.effects, 2);
    },
  );

  // AC-008: HTTP responses cannot prove rejection before parser handoff.
  test(
    'AC-008 sixteen accepted sockets reject excess before HTTP and release',
    () {
      fakeAsync((time) {
        final h = _IpadHarness(time)..enable();
        final sockets = List.generate(16, (_) => h.accept());
        expect(sockets.any((s) => s.destroyed), isFalse);
        final rejected = h.accept();
        expect(rejected.destroyed, isTrue);
        expect(rejected.output, isEmpty);
        expect(h.native.calls, 2);
        expect(h.connects, 0);
        sockets.first.destroy();
        h.flush();
        final replacement = h.accept();
        expect(replacement.destroyed, isFalse);
        h.clean();
        expect(sockets.every((s) => s.destroyed), isTrue);
        expect(replacement.destroyed, isTrue);
      });
    },
  );

  // AC-008: disconnect at post-body freshness checks to exhaust handlers
  // independently of the socket/session caps, then verify error cleanup.
  test(
    'AC-008 sixteen handlers authenticate exhaustion and recover after errors',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      final gate = Completer<McpLanSnapshot>();
      final pending = <Future<Object>>[];
      for (var i = 0; i < 16; i++) {
        final reached = Completer<void>();
        final next = h.setup.native.calls + 2;
        h.setup.native.read = (call) {
          if (call == next) {
            reached.complete();
            return gate.future;
          }
          return Future.value(h.setup.native.value);
        };
        pending.add(
          h
              .request(payload: '{')
              .then<Object>((r) => r, onError: (Object e) => e),
        );
        await reached.future;
        h.accepted.last.destroy();
        await pending.last;
      }
      h.setup.native.read = null;
      expect(await h.status(), 429);
      final unauthorized = await h.request(authorized: false);
      expect(unauthorized.statusCode, 401);
      await unauthorized.drain<void>();
      expect(h.connects, 0);
      expect(h.setup.effects, 0);
      gate.complete(h.setup.native.value);
      await h.session();
      expect(h.service.connectionDiagnostics['active_servers'], 1);
    },
  );

  // AC-008: chunked bytes bypass Content-Length; exact success, overflow and
  // a continuing trickle distinguish measured size and an absolute deadline.
  test(
    'AC-008 measured 1 MiB boundary and absolute ten-second receive timeout',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      final id = await h.session();
      final json = jsonEncode(_effectBody);
      final payload = json + ' ' * (1024 * 1024 - utf8.encode(json).length);
      final boundary = await h.request(
        session: id,
        payload: payload,
        chunked: true,
      );
      expect(boundary.statusCode, 200);
      await boundary.drain<void>();
      expect(h.setup.effects, 1);
      final overflow = await h.request(
        session: id,
        payload: '$payload ',
        chunked: true,
      );
      expect(overflow.statusCode, 413);
      await overflow.drain<void>();
      expect(h.setup.effects, 1);
      final slow = await h.slow(id);
      addTearDown(slow.socket.destroy);
      for (var i = 0; i < 9; i++) {
        h.clock.elapse(const Duration(seconds: 1));
        slow.chunk(' ');
        await slow.socket.flush();
      }
      h.clock.elapse(const Duration(milliseconds: 999));
      expect(slow.response, isNot(contains('408')));
      h.clock.elapse(const Duration(milliseconds: 1));
      await slow.done.future;
      expect(slow.response, startsWith('HTTP/1.1 408'));
      expect(h.setup.effects, 1);
      expect(await h.status(session: id, body: _effectBody), 200);
      expect(h.setup.effects, 2);
      expect(h.service.connectionDiagnostics['active_servers'], 1);
    },
  );

  // AC-008: late receipt followed by a slow tool exposes a whole-handler timer;
  // a second call also proves the original registry execution timeout remains.
  test(
    'AC-008 receive deadline excludes executing tools and preserves registry timeout',
    () async {
      final h = _RealIpad();
      await h.start();
      addTearDown(h.clean);
      final id = await h.session();
      var gate = Completer<MemoryUsage>();
      var reached = Completer<void>();
      when(() => h.setup.cubit.requestFreshMemoryUsage()).thenAnswer((_) {
        h.setup.effects++;
        reached.complete();
        return gate.future;
      });
      final slow = await h.slow(id);
      addTearDown(slow.socket.destroy);
      h.clock.elapse(const Duration(seconds: 9));
      slow.finish();
      await reached.future;
      h.clock.elapse(const Duration(seconds: 9));
      expect(slow.response, isNot(contains('408')));
      gate.complete(
        const MemoryUsage(
          sram: MemoryPoolUsage(total: 10, current: 1),
          dram: MemoryPoolUsage(total: 10, current: 1),
          dtc: MemoryPoolUsage(total: 10, current: 1),
          itc: MemoryPoolUsage(total: 10, current: 1),
        ),
      );
      await slow.done.future;
      expect(slow.response, contains('memory_usage'));
      gate = Completer<MemoryUsage>();
      reached = Completer<void>();
      h.timerArmed = Completer<void>();
      final pending = h.request(session: id, body: _effectBody);
      await reached.future;
      await h.timerArmed!.future;
      await Future<void>.value();
      h.clock.elapse(const Duration(seconds: 10));
      final timed = await pending;
      expect(timed.statusCode, 200);
      expect(
        await utf8.decodeStream(timed),
        contains('Tool execution timed out after 10 seconds'),
      );
      gate.completeError(StateError('Late failure'));
      expect(h.setup.effects, 2);
      expect(h.service.connectionDiagnostics['active_servers'], 1);
    },
  );
}
