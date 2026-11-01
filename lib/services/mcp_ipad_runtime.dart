part of 'mcp_server_service.dart';

/// Listener state, not a claim that a client can reach the device.
enum McpIpadState { off, starting, running, stopping, paused, failed }

typedef McpSocketBinder =
    Future<ServerSocket> Function(
      InternetAddress address,
      int port, {
      required bool shared,
      required bool v6Only,
    });

class _IpadConsent {
  _IpadConsent(this.policy, this.token);
  final McpLanPolicy policy;
  final String token;
}

class _McpResources {
  final servers = <String, McpServer>{};
  final transports = <String, StreamableHTTPServerTransport>{};
  final registries = <McpServer, ToolRegistry>{};
}

class _IpadGeneration extends _McpResources {
  _IpadGeneration(this.consent);
  final _IpadConsent consent;
  ServerSocket? socketServer;
  HttpServer? httpServer;
  StreamSubscription<HttpRequest>? subscription;
  final sockets = <_AcceptedSocket>{};
  int handlers = 0;
  bool revoked = false;
  Future<void>? closing;
}

/// One coalescing worker; all authority changes happen synchronously, before
/// cleanup, persistence, native calls or binds can yield.
class _IpadRuntime {
  _IpadRuntime(
    this.service,
    this.context,
    this.bind,
    this.randomBytes,
    this.listenOn,
    this.beforeConnect,
  );
  final McpServerService service;
  final McpLanContext context;
  final McpSocketBinder bind;
  final List<int> Function() randomBytes;
  final HttpServer Function(ServerSocket) listenOn;
  final Future<void> Function()? beforeConnect;
  McpIpadState state = McpIpadState.off;
  String? reason;
  bool foreground = true;
  bool disposed = false;
  int revision = 0;
  _IpadConsent? consent;
  _IpadGeneration? current;
  Future<void>? worker;
  Future<void> cleanup = Future.value();
  bool dirty = false;

  void report(McpIpadState value, [String? why]) {
    state = value;
    reason = why;
    if (!disposed) service._notifyIpad();
  }

  bool owns(_IpadGeneration g) =>
      !disposed &&
      foreground &&
      identical(current, g) &&
      !g.revoked &&
      identical(consent, g.consent);
  bool admits(_IpadGeneration g) => owns(g) && state == McpIpadState.running;

  void revoke({bool retainConsent = false}) {
    revision++;
    if (!retainConsent) consent = null;
    final old = current;
    current = null;
    if (old != null) {
      old.revoked = true;
      // Start every close now, without waiting behind another generation.
      cleanup = Future.wait([cleanup, close(old)]).then((_) {});
    }
  }

  Future<void> close(_IpadGeneration g) => g.closing ??= _close(g);
  Future<void> _close(_IpadGeneration g) async {
    g.revoked = true;
    for (final socket in g.sockets.toList()) {
      socket.destroy();
    }
    g.sockets.clear();
    g.transports.clear();
    g.servers.clear();
    final closing = g.registries.keys
        .toList()
        .map((server) => service._disposeServer(server, resources: g))
        .toList();
    // HttpServer.listenOn does not own/close its ServerSocket.
    Future<void> safely(Future<dynamic> Function() action) async {
      try {
        await action();
      } on Object {
        /* Continue closing other owners. */
      }
    }

    await Future.wait([
      ...closing,
      safely(() async => g.httpServer?.close(force: true)),
      safely(() async => g.socketServer?.close()),
      safely(() async => g.subscription?.cancel()),
    ]);
  }

  Future<void> enable(
    McpLanPolicy policy,
    Future<bool> Function() persist,
  ) async {
    revoke();
    final attempt = revision;
    if (disposed || !foreground) return;
    report(McpIpadState.starting);
    try {
      final saved = await persist();
      if (disposed || !foreground || attempt != revision) return;
      if (!saved) {
        report(
          McpIpadState.failed,
          'Save Settings successfully, then enable again.',
        );
        return;
      }
      final bytes = randomBytes();
      if (bytes.length != 32 || bytes.any((b) => b < 0 || b > 255)) {
        throw StateError('Invalid secure randomness');
      }
      consent = _IpadConsent(
        policy,
        base64Url.encode(bytes).replaceAll('=', ''),
      );
      await reconcile();
    } on Object {
      if (attempt != revision || disposed) return;
      revoke();
      report(
        McpIpadState.failed,
        'Unable to enable securely. Check LAN Settings and enable again.',
      );
      await cleanup;
    }
  }

  Future<void> disable() async {
    revoke();
    final attempt = revision;
    if (disposed) {
      await cleanup;
      return;
    }
    report(McpIpadState.stopping);
    await cleanup;
    if (attempt == revision && !disposed) report(McpIpadState.off);
  }

  Future<void> invalidate(String why, {bool failure = false}) async {
    if (disposed) return;
    revoke();
    report(failure ? McpIpadState.failed : McpIpadState.paused, why);
    await cleanup;
  }

  Future<void> lifecycle(String transition) async {
    if (disposed) return;
    if (transition == 'inactive') {
      foreground = false;
      revoke(retainConsent: true);
      report(McpIpadState.paused, 'Temporarily inactive.');
      await cleanup;
    } else if (transition == 'resumed') {
      foreground = true;
      if (consent != null) await reconcile();
    } else {
      foreground = false;
      await invalidate('Return to Settings and enable again.');
    }
  }

  bool matches(McpLanPolicy expected, McpLanSnapshot snapshot) {
    final observed = McpLanPolicy.select(
      snapshot,
      interfaceIndex: expected.interfaceIndex,
      address: expected.address.text,
      peers: expected.peers.map((p) => p.text),
    );
    return observed.pathGeneration == expected.pathGeneration &&
        observed.interfaceName == expected.interfaceName &&
        listEquals(observed.mask, expected.mask);
  }

  Future<bool> validate(_IpadGeneration g, {bool starting = false}) async {
    if (!owns(g)) return false;
    try {
      final snapshot = await context.snapshot();
      if (!owns(g)) return false;
      if (!matches(g.consent.policy, snapshot)) {
        throw StateError('Changed context');
      }
      return starting || admits(g);
    } on Object {
      if (owns(g)) {
        unawaited(
          invalidate(
            'LAN context changed or unavailable. Check network and enable again.',
            failure: true,
          ),
        );
      }
      return false;
    }
  }

  Future<void> reconcile() {
    dirty = true;
    return worker ??= _reconcile().whenComplete(() {
      worker = null;
      if (dirty && !disposed) return reconcile();
    });
  }

  Future<void> _reconcile() async {
    while (dirty && !disposed) {
      dirty = false;
      await cleanup;
      final selected = consent;
      if (selected == null || !foreground || current != null) continue;
      final g = _IpadGeneration(selected);
      current = g;
      report(McpIpadState.starting);
      try {
        if (!await validate(g, starting: true)) continue;
        final address = InternetAddress(selected.policy.address.text);
        final socket = await bind(
          address,
          3847,
          shared: false,
          v6Only: address.type == InternetAddressType.IPv6,
        );
        if (!owns(g)) {
          await socket.close();
          continue;
        }
        g.socketServer = socket;
        if (socket.port != 3847 ||
            !selected.policy.address.sameAddress(
              LanAddress.parse(socket.address.address),
            )) {
          throw StateError('Unexpected listener identity');
        }
        if (!await validate(g, starting: true)) continue;
        final http = listenOn(_AcceptedServerSocket(socket, this, g));
        g.httpServer = http;
        g.subscription = http.listen(
          (request) {
            unawaited(service._handleHttpRequest(request, generation: g));
          },
          onError: (Object error) {
            if (owns(g)) {
              unawaited(
                invalidate(
                  'Listener failed. Enable again in Settings.',
                  failure: true,
                ),
              );
            }
          },
          onDone: () {
            if (owns(g)) {
              unawaited(
                invalidate(
                  'Listener closed. Enable again in Settings.',
                  failure: true,
                ),
              );
            }
          },
        );
        if (!owns(g)) {
          await close(g);
          continue;
        }
        report(McpIpadState.running);
      } on Object {
        if (owns(g)) {
          await invalidate(
            'Cannot bind selected LAN address on port 3847. Check network/port and enable again.',
            failure: true,
          );
        } else {
          await close(g);
        }
      }
    }
  }
}

/// Filter before HTTP parsing. No Host or forwarded header is socket evidence.
class _AcceptedServerSocket extends Stream<Socket> implements ServerSocket {
  _AcceptedServerSocket(this.inner, this.runtime, this.generation);
  final ServerSocket inner;
  final _IpadRuntime runtime;
  final _IpadGeneration generation;
  @override
  int get port => inner.port;
  @override
  InternetAddress get address => inner.address;
  @override
  Future<ServerSocket> close() => inner.close();
  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return inner
        .where((socket) {
          try {
            final p = generation.consent.policy;
            if (runtime.admits(generation) &&
                generation.sockets.length < 16 &&
                socket.port == 3847 &&
                p.address.sameAddress(
                  LanAddress.parse(socket.address.address),
                ) &&
                p.allowsPeer(LanAddress.parse(socket.remoteAddress.address))) {
              return true;
            }
          } on Object {
            /* Unavailable socket metadata is not authority. */
          }
          socket.destroy();
          return false;
        })
        .map((socket) {
          final accepted = _AcceptedSocket(socket);
          generation.sockets.add(accepted);
          accepted.onFullyClosed = () => generation.sockets.remove(accepted);
          return accepted;
        })
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }
}

/// Retain the raw first target: Uri.parse normalizes escaped unreserved bytes.
/// iPad responses close keep-alive, and admission permits only the first request
/// on each socket, so pipelining cannot reuse this identity for another target.
/// This observes a bounded header prefix, not a second HTTP framing stack.
class _AcceptedSocket extends Stream<Uint8List> implements Socket {
  _AcceptedSocket(this.inner) {
    unawaited(
      inner.done.then(
        (_) {
          outputClosed = true;
          checkClosed();
        },
        onError: (Object _) {
          outputClosed = true;
          checkClosed();
        },
      ),
    );
  }
  final Socket inner;
  final _head = <int>[];
  final rawHeaders = <String, List<String>>{};
  String? target;
  bool headDone = false;
  bool claimed = false;
  bool headersWellFormed = true;
  bool inputClosed = false;
  bool outputClosed = false;
  void Function()? onFullyClosed;
  void checkClosed() {
    if (inputClosed && outputClosed) onFullyClosed?.call();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner
      .map((bytes) {
        if (!headDone) {
          for (final b in bytes) {
            _head.add(b);
            final n = _head.length;
            if (n > 16384) {
              destroy();
              return Uint8List(0);
            }
            if (n >= 4 &&
                _head[n - 4] == 13 &&
                _head[n - 3] == 10 &&
                _head[n - 2] == 13 &&
                _head[n - 1] == 10) {
              final lines = latin1.decode(_head).split('\r\n');
              final parts = lines.first.split(' ');
              if (parts.length == 3) target = parts[1];
              for (final line in lines.skip(1)) {
                if (line.startsWith(' ') || line.startsWith('\t')) {
                  headersWellFormed = false;
                }
                final colon = line.indexOf(':');
                if (colon < 1) continue;
                final name = line.substring(0, colon).toLowerCase();
                if (!['host', 'origin', 'authorization'].contains(name)) {
                  continue;
                }
                var value = line.substring(colon + 1);
                // Remove the conventional single separator SP, not arbitrary
                // whitespace that the Dart header decoder would silently trim.
                if (value.startsWith(' ')) value = value.substring(1);
                rawHeaders.putIfAbsent(name, () => []).add(value);
              }
              _head.clear();
              headDone = true;
              break;
            }
          }
        }
        return bytes;
      })
      .listen(
        onData,
        onError: onError,
        onDone: () {
          inputClosed = true;
          checkClosed();
          onDone?.call();
        },
        cancelOnError: cancelOnError,
      );
  @override
  InternetAddress get address => inner.address;
  @override
  int get port => inner.port;
  @override
  InternetAddress get remoteAddress => inner.remoteAddress;
  @override
  int get remotePort => inner.remotePort;
  @override
  Encoding get encoding => inner.encoding;
  @override
  set encoding(Encoding value) => inner.encoding = value;
  @override
  Future get done => inner.done;
  @override
  Future close() => inner.close();
  @override
  void destroy() {
    _head.clear();
    rawHeaders.clear();
    inputClosed = true;
    outputClosed = true;
    checkClosed();
    inner.destroy();
  }

  @override
  void add(List<int> data) => inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future addStream(Stream<List<int>> stream) => inner.addStream(stream);
  @override
  Future flush() => inner.flush();
  @override
  void write(Object? object) => inner.write(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      inner.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => inner.writeln(object);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      inner.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => inner.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => inner.setRawOption(option);
}

/// The SDK sets SSE Connection: keep-alive. Enforce the single-request socket
/// policy immediately before headers are committed, including GET/SSE writes.
class _IpadHttpRequest extends Stream<Uint8List> implements HttpRequest {
  _IpadHttpRequest(this.inner) : response = _IpadHttpResponse(inner.response);
  final HttpRequest inner;
  @override
  final HttpResponse response;
  @override
  int get contentLength => inner.contentLength;
  @override
  String get method => inner.method;
  @override
  Uri get uri => inner.uri;
  @override
  Uri get requestedUri => inner.requestedUri;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  List<Cookie> get cookies => inner.cookies;
  @override
  bool get persistentConnection => false;
  @override
  X509Certificate? get certificate => inner.certificate;
  @override
  HttpSession get session => inner.session;
  @override
  String get protocolVersion => inner.protocolVersion;
  @override
  HttpConnectionInfo? get connectionInfo => inner.connectionInfo;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => inner.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _IpadHttpResponse implements HttpResponse {
  _IpadHttpResponse(this.inner);
  final HttpResponse inner;
  bool committed = false;
  void prepare() {
    if (committed) return;
    inner.headers.set(HttpHeaders.connectionHeader, 'close');
    inner.persistentConnection = false;
    committed = true;
  }

  @override
  HttpHeaders get headers => inner.headers;
  @override
  List<Cookie> get cookies => inner.cookies;
  @override
  int get contentLength => inner.contentLength;
  @override
  set contentLength(int value) => inner.contentLength = value;
  @override
  int get statusCode => inner.statusCode;
  @override
  set statusCode(int value) => inner.statusCode = value;
  @override
  String get reasonPhrase => inner.reasonPhrase;
  @override
  set reasonPhrase(String value) => inner.reasonPhrase = value;
  @override
  bool get persistentConnection => false;
  @override
  set persistentConnection(bool value) => inner.persistentConnection = false;
  @override
  Duration? get deadline => inner.deadline;
  @override
  set deadline(Duration? value) => inner.deadline = value;
  @override
  bool get bufferOutput => inner.bufferOutput;
  @override
  set bufferOutput(bool value) => inner.bufferOutput = value;
  @override
  HttpConnectionInfo? get connectionInfo => inner.connectionInfo;
  @override
  Encoding get encoding => inner.encoding;
  @override
  set encoding(Encoding value) => inner.encoding = value;
  @override
  Future get done => inner.done;
  @override
  Future close() {
    prepare();
    return inner.close();
  }

  @override
  void add(List<int> bytes) {
    prepare();
    inner.add(bytes);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    prepare();
    return inner.addStream(stream);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      inner.addError(error, stackTrace);
  @override
  Future flush() {
    prepare();
    return inner.flush();
  }

  @override
  void write(Object? object) {
    prepare();
    inner.write(object);
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    prepare();
    inner.writeAll(objects, separator);
  }

  @override
  void writeln([Object? object = '']) {
    prepare();
    inner.writeln(object);
  }

  @override
  void writeCharCode(int charCode) {
    prepare();
    inner.writeCharCode(charCode);
  }

  @override
  Future redirect(Uri location, {int status = HttpStatus.movedTemporarily}) {
    prepare();
    return inner.redirect(location, status: status);
  }

  @override
  Future<Socket> detachSocket({bool writeHeaders = true}) {
    prepare();
    return inner.detachSocket(writeHeaders: writeHeaders);
  }
}
