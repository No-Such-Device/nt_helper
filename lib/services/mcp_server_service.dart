import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/debug_service.dart';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'mcp_lan_context.dart';
import 'mcp_lan_policy.dart';

part 'mcp_ipad_runtime.dart';

/// Generate a unique session ID with secure random number generator
String generateUUID() {
  // Try multiple approaches to get secure randomness
  late math.Random rng;

  try {
    // First try: Use Dart's secure random
    rng = math.Random.secure();
  } catch (e) {
    try {
      // Second try: Create entropy using crypto package and timestamp
      final timestamp = DateTime.now().microsecondsSinceEpoch.toString();
      final processId = DateTime.now().millisecondsSinceEpoch & 0xFFFF;
      final entropy = sha256.convert('$timestamp-$processId'.codeUnits).bytes;
      final seed = entropy.fold<int>(
        0,
        (prev, byte) => prev ^ (byte << (prev % 24)),
      );
      rng = math.Random(seed);
    } catch (e2) {
      try {
        // Third try: Simple timestamp seed
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final seed = timestamp ^ (timestamp >> 32);
        rng = math.Random(seed);
      } catch (e3) {
        // Final fallback: Regular random
        rng = math.Random();
      }
    }
  }

  // Create a custom UUID v4 with our secure RNG
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // Set version (4) and variant bits according to RFC 4122
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // Version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variant bits

  // Convert to UUID format
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// MCP server service using Streamable HTTP transport on /mcp.
/// Manages multiple MCP server instances, one per client session.
class McpServerService extends ChangeNotifier {
  McpServerService._(this._distingCubit);

  @visibleForTesting
  McpServerService.forTesting({
    required DistingCubit distingCubit,
    required McpLanContext context,
    required McpSocketBinder bindSocket,
    required List<int> Function() randomBytes,
    HttpServer Function(ServerSocket) listenOn = HttpServer.listenOn,
    Future<void> Function()? beforeSessionConnect,
  }) : _distingCubit = distingCubit {
    _ipad = _IpadRuntime(
      this,
      context,
      bindSocket,
      randomBytes,
      listenOn,
      beforeSessionConnect,
    );
  }

  void _notifyIpad() {
    if (!_disposed) notifyListeners();
  }

  _IpadRuntime? _ipad;
  bool _disposed = false;
  McpIpadState get ipadState => _ipad?.state ?? McpIpadState.off;
  String? get ipadReason => _ipad?.reason;
  // Credentials are memory-only and exposed solely for deliberate Settings copy.
  String? get ipadToken => _ipad?.consent?.token;

  /// Only an explicit Settings command may call this, with its successful save.
  /// Neither start() nor restored/generic enable flags grant iPad authority.
  Future<void> enableIpad({
    required McpLanPolicy policy,
    required Future<bool> Function() persistSettings,
  }) {
    if (_disposed) return Future.value();
    _ipad ??= _IpadRuntime(
      this,
      MethodChannelMcpLanContext(),
      (address, port, {required shared, required v6Only}) =>
          ServerSocket.bind(address, port, shared: shared, v6Only: v6Only),
      () {
        final rng = math.Random.secure();
        return List.generate(32, (_) => rng.nextInt(256));
      },
      HttpServer.listenOn,
      null,
    );
    return _ipad!.enable(policy, persistSettings);
  }

  Future<void> regenerateIpad({
    required McpLanPolicy policy,
    required Future<bool> Function() persistSettings,
  }) => enableIpad(policy: policy, persistSettings: persistSettings);
  Future<void> disableIpad() => _ipad?.disable() ?? Future.value();
  Future<void> ipadLifecycleChanged(String transition) =>
      _ipad?.lifecycle(transition) ?? Future.value();
  Future<void> ipadNetworkChanged({bool failed = false}) =>
      _ipad?.invalidate(
        failed
            ? 'Network monitor failed. Check network and enable again.'
            : 'Network changed. Enable again in Settings.',
        failure: failed,
      ) ??
      Future.value();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final runtime = _ipad;
    if (runtime != null) {
      runtime.disposed = true;
      runtime.revoke();
      runtime.state = McpIpadState.off;
      runtime.reason = null;
    }
    unawaited(stop());
    super.dispose();
  }

  static McpServerService? _instance;

  static McpServerService get instance {
    if (_instance == null) {
      throw StateError(
        'McpServerService not initialized. Call initialize() first.',
      );
    }
    return _instance!;
  }

  static void initialize({required DistingCubit distingCubit}) {
    if (_instance != null) {
      return;
    }
    _instance = McpServerService._(distingCubit);
  }

  final DistingCubit _distingCubit;

  // Map of session ID to server instance for multi-client support
  final _desktop = _McpResources();
  Map<String, McpServer> get _servers => _desktop.servers;
  Map<String, StreamableHTTPServerTransport> get _transports =>
      _desktop.transports;
  Map<McpServer, ToolRegistry> get _registries => _desktop.registries;
  _McpResources _resources(_IpadGeneration? g) => g ?? _desktop;
  bool _active(_IpadGeneration? g) => g == null ? isRunning : _ipad!.admits(g);
  Future<bool> _fresh(_IpadGeneration? g) async =>
      g == null ? isRunning : await _ipad!.validate(g);

  HttpServer? _httpServer;
  StreamSubscription<HttpRequest>? _httpSubscription;
  String? _lastError;

  bool get isRunning =>
      !_disposed &&
      (_httpServer != null ||
          (_ipad?.current != null && _ipad!.admits(_ipad!.current!)));
  int? get boundPort => _httpServer?.port ?? _ipad?.current?.httpServer?.port;
  InternetAddress? get boundAddress =>
      _httpServer?.address ?? _ipad?.current?.httpServer?.address;

  /// Returns the last error that occurred when trying to start the server
  String? get lastError => _lastError;

  /// Returns true if MCP is enabled but failed to start
  bool get hasError => _lastError != null;

  /// Get basic connection diagnostics
  Map<String, dynamic> get connectionDiagnostics {
    return {
      'server_running': isRunning,
      'active_servers': _servers.length + (_ipad?.current?.servers.length ?? 0),
      'active_transports':
          _transports.length + (_ipad?.current?.transports.length ?? 0),
      'active_registries':
          _registries.length + (_ipad?.current?.registries.length ?? 0),
      'server_implementation': 'nt-helper-flutter',
      'library_version': 'mcp_dart 1.2.2',
    };
  }

  Future<void> start({int port = 3847, InternetAddress? bindAddress}) async {
    // Generic flags/startup are never iOS LAN consent. Settings uses enableIpad.
    if (_disposed ||
        _ipad != null ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return;
    }
    if (isRunning) {
      _lastError = null;
      notifyListeners();
      return;
    }

    // Clear any previous error
    _lastError = null;

    try {
      // Bind to localhost by default to avoid exposing the MCP server on the LAN.
      // Use bindAddress: InternetAddress.anyIPv4 if you explicitly want to expose it.
      final address = bindAddress ?? InternetAddress.loopbackIPv4;

      // Create HTTP server
      _httpServer = await HttpServer.bind(address, port);

      // Handle HTTP requests
      _httpSubscription = _httpServer!.listen(
        (HttpRequest request) async {
          await _handleHttpRequest(request);
        },
        onError: (error, stackTrace) {},
        onDone: () {
          unawaited(_cleanup());
        },
        cancelOnError: false,
      );

      DebugService().addLocalMessage(
        'MCP server started on port ${_httpServer!.port}',
      );
      notifyListeners();
    } catch (e) {
      // Capture error for display
      if (e is SocketException) {
        if (e.osError?.errorCode == 48 ||
            e.message.contains('Address already in use')) {
          _lastError = 'Port $port is already in use';
        } else {
          _lastError = e.message;
        }
      } else {
        _lastError = e.toString();
      }
      DebugService().addLocalMessage('MCP server error: $_lastError');
      await stop();
      notifyListeners();
    }
  }

  void _log(String message) {
    DebugService().addLocalMessage('MCP: $message');
  }

  Future<void> _handleHttpRequest(
    HttpRequest request, {
    _IpadGeneration? generation,
  }) async {
    if (generation != null) {
      if (!await _admitIpadRequest(request, generation)) return;
      final guarded = _IpadHttpRequest(request);
      try {
        switch (request.method) {
          case 'POST':
            await _handlePostRequest(guarded, generation: generation);
          case 'GET':
            await _handleGetRequest(guarded, generation: generation);
          case 'DELETE':
            await _handleDeleteRequest(guarded, generation: generation);
        }
      } on Object {
        if (_active(generation)) {
          _sendErrorResponse(
            request,
            HttpStatus.internalServerError,
            'Internal server error',
          );
        }
      }
      return;
    }
    _log('Request: ${request.method} ${request.uri}');
    // Apply CORS headers to all responses
    _setCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      // Handle CORS preflight request
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    switch (request.uri.path) {
      case '/mcp':
        switch (request.method) {
          case 'POST':
            await _handlePostRequest(request);
          case 'GET':
            await _handleGetRequest(request);
          case 'DELETE':
            await _handleDeleteRequest(request);
          default:
            request.response.statusCode = HttpStatus.methodNotAllowed;
            request.response.headers.set(
              HttpHeaders.allowHeader,
              'GET, POST, DELETE, OPTIONS',
            );
            request.response.write('Method Not Allowed');
            await request.response.close();
        }
      default:
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.text;
        request.response.write('Not Found.');
        await request.response.close();
    }
  }

  String _ipadAuthority(_IpadGeneration g) {
    final address = g.consent.policy.address;
    return '${address.bytes.length == 16 ? '[${address.text}]' : address.text}:3847';
  }

  String _ipadEndpoint(_IpadGeneration g) => 'http://${_ipadAuthority(g)}/mcp';

  Future<bool> _admitIpadRequest(HttpRequest request, _IpadGeneration g) async {
    Future<bool> deny(int code) async {
      try {
        request.response.statusCode = code;
        await request.response.close();
      } on Object {
        /* The generation may already have destroyed this socket. */
      }
      return false;
    }

    request.response.persistentConnection = false;
    if (!_ipad!.admits(g)) return deny(HttpStatus.unauthorized);
    final info = request.connectionInfo;
    _AcceptedSocket? accepted;
    if (info != null && info.localPort == 3847) {
      for (final socket in g.sockets) {
        try {
          if (socket.remotePort == info.remotePort &&
              LanAddress.parse(
                socket.remoteAddress.address,
              ).sameAddress(LanAddress.parse(info.remoteAddress.address))) {
            accepted = socket;
            break;
          }
        } on Object {
          /* Closed metadata cannot authenticate a request. */
        }
      }
    }
    if (accepted == null || accepted.claimed || !accepted.headersWellFormed) {
      return deny(HttpStatus.forbidden);
    }
    accepted.claimed = true;
    final rawHeaders = Map<String, List<String>>.of(accepted.rawHeaders);
    accepted.rawHeaders.clear();
    if (accepted.target != '/mcp' || request.uri.toString() != '/mcp') {
      return deny(HttpStatus.notFound);
    }
    String? unique(String name) {
      final values = rawHeaders[name];
      if (values == null || values.length != 1) return null;
      final value = values.single;
      return value.length <= 128 &&
              value.codeUnits.every((b) => b >= 33 && b <= 126)
          ? value
          : null;
    }

    final host = unique('host');
    bool validHost = false;
    if (host != null) {
      final match = RegExp(
        r'^(\[[0-9a-fA-F:.]*:[0-9a-fA-F:.]*\]|[0-9.]+):([0-9]{1,5})$',
      ).firstMatch(host);
      if (match != null && int.tryParse(match[2]!) == 3847) {
        var address = match[1]!;
        if (address.startsWith('[')) {
          address = address.substring(1, address.length - 1);
        }
        try {
          validHost = g.consent.policy.address.sameAddress(
            LanAddress.parse(address),
          );
        } on Object {
          /* Numeric parsing only; never DNS. */
        }
      }
    }
    if (!validHost || rawHeaders['origin'] != null) {
      return deny(HttpStatus.forbidden);
    }
    final credentials = rawHeaders['authorization'];
    var validCredential = false;
    if (credentials != null &&
        credentials.length == 1 &&
        credentials.single.length <= 128) {
      final match = RegExp(
        r'^Bearer ([A-Za-z0-9_-]{43})$',
        caseSensitive: false,
      ).firstMatch(credentials.single);
      if (match != null) {
        final supplied = match[1]!;
        var difference = 0;
        for (var i = 0; i < 43; i++) {
          difference |= supplied.codeUnitAt(i) ^ g.consent.token.codeUnitAt(i);
        }
        validCredential = difference == 0;
      }
    }
    if (!validCredential) return deny(HttpStatus.unauthorized);
    if (!await _ipad!.validate(g)) return deny(HttpStatus.forbidden);
    if (!['POST', 'GET', 'DELETE'].contains(request.method)) {
      return deny(HttpStatus.methodNotAllowed);
    }
    return true;
  }

  void _setCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, DELETE, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, mcp-session-id, Last-Event-ID, Authorization',
    );
    response.headers.set('Access-Control-Allow-Credentials', 'true');
    response.headers.set('Access-Control-Max-Age', '86400');
    response.headers.set('Access-Control-Expose-Headers', 'mcp-session-id');
  }

  /// Handle POST requests for JSON-RPC calls (Streamable HTTP).
  /// The transport validates Accept headers and handles the protocol per spec.
  Future<void> _handlePostRequest(
    HttpRequest request, {
    _IpadGeneration? generation,
  }) async {
    final resources = _resources(generation);
    final sessionId = request.headers.value('mcp-session-id');
    try {
      final bodyBytes = await request.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      if (!await _fresh(generation)) return;
      final bodyString = utf8.decode(bodyBytes);
      final parsedBody = jsonDecode(bodyString);
      if (generation == null) {
        DebugService().addLocalMessage('MCP request: $bodyString');
      }

      var transport = resources.transports[sessionId];
      if (transport == null) {
        transport = await _createNewTransport(
          sessionId: sessionId,
          generation: generation,
        );
        if (!await _fresh(generation)) return;
        if (!_isInitializeBody(parsedBody) && sessionId != null) {
          final initBody = jsonDecode(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': '_reinit',
              'method': 'initialize',
              'params': {
                'protocolVersion': '2025-03-26',
                'capabilities': {},
                'clientInfo': {'name': 'auto-reinit', 'version': '0.0.0'},
              },
            }),
          );
          final host = generation == null
              ? request.headers.value('host')
              : _ipadAuthority(generation);
          final syntheticRequest = _SyntheticHttpRequest(host: host);
          await transport.handleRequest(syntheticRequest, initBody);
          if (!await _fresh(generation)) return;
          await syntheticRequest.response.done;
          if (!await _fresh(generation)) return;
          final initialized = _SyntheticHttpRequest(
            sessionId: transport.sessionId,
            host: host,
          );
          await transport.handleRequest(initialized, <String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          });
          if (!await _fresh(generation)) return;
          await initialized.response.done;
          if (!await _fresh(generation)) return;
        }
      }
      if (!await _fresh(generation)) return;
      await transport.handleRequest(request, parsedBody);
    } on Object catch (e) {
      if (generation == null) DebugService().addLocalMessage('MCP error: $e');
      if (_active(generation)) {
        _sendErrorResponse(
          request,
          HttpStatus.internalServerError,
          generation == null
              ? 'Internal server error: $e'
              : 'Internal server error',
        );
      }
    }
  }

  /// Check if a parsed JSON body contains an initialize request
  bool _isInitializeBody(dynamic parsedBody) {
    if (parsedBody is Map<String, dynamic>) {
      return parsedBody['method'] == 'initialize';
    }
    if (parsedBody is List) {
      return parsedBody.any(
        (msg) => msg is Map<String, dynamic> && msg['method'] == 'initialize',
      );
    }
    return false;
  }

  /// Handle GET requests on /mcp for Streamable HTTP standalone SSE streams.
  Future<void> _handleGetRequest(
    HttpRequest request, {
    _IpadGeneration? generation,
  }) async {
    if (!_active(generation)) return;
    final transports = _resources(generation).transports;
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null) {
      _sendErrorResponse(
        request,
        HttpStatus.badRequest,
        'Missing session ID for SSE stream',
      );
      return;
    }

    final transport = transports[sessionId];
    if (transport == null) {
      _sendErrorResponse(request, HttpStatus.notFound, 'Session not found');
      return;
    }

    if (generation == null) {
      _log('GET /mcp: opening SSE stream for session $sessionId');
    }
    if (!await _fresh(generation)) return;
    await transport.handleRequest(request);
  }

  /// Handle DELETE requests for session termination
  Future<void> _handleDeleteRequest(
    HttpRequest request, {
    _IpadGeneration? generation,
  }) async {
    if (!await _fresh(generation)) return;
    final resources = _resources(generation);
    final transports = resources.transports;
    final servers = resources.servers;
    final registries = resources.registries;
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null) {
      _sendErrorResponse(
        request,
        HttpStatus.badRequest,
        'Missing session ID for termination',
      );
      return;
    }

    try {
      if (!_active(generation)) return;
      if (transports.containsKey(sessionId)) {
        final transport = transports.remove(sessionId)!;
        final server = servers.remove(sessionId);
        // Invalidate this client's tools before yielding to gesture cleanup.
        // Let the transport write its DELETE response before closing the server.
        final registry = registries.remove(server);
        try {
          await registry?.dispose();
        } on Object {
          // The remote operation records an uncertain release result itself.
        }
        try {
          if (!await _fresh(generation)) return;
          await transport.handleRequest(request);
        } finally {
          await server?.close();
        }
      } else {
        // Session doesn't exist - just return OK since it's already "terminated"
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'status': 'ok', 'message': 'Session already terminated'}),
        );
        await request.response.close();
      }
    } catch (e) {
      _sendErrorResponse(
        request,
        HttpStatus.internalServerError,
        'Error processing session termination',
      );
    }
  }

  /// Helper to send JSON error responses
  void _sendErrorResponse(HttpRequest request, int statusCode, String message) {
    try {
      // Check if headers are already sent
      bool headersSent = false;
      try {
        headersSent = request.response.headers.contentType
            .toString()
            .startsWith('text/event-stream');
      } catch (_) {
        // Ignore errors when checking headers
      }

      if (!headersSent) {
        request.response.statusCode = statusCode;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {'code': -32000, 'message': message},
            'id': null,
          }),
        );
        request.response.close();
      }
    } catch (_) {
      // Ignore errors when sending error response
    }
  }

  Future<void> stop() async {
    final stoppingIpad = _ipad?.disable();
    if (_httpServer == null && _lastError == null && _registries.isEmpty) {
      await stoppingIpad;
      return;
    }

    final subscription = _httpSubscription;
    _httpSubscription = null;
    final httpServer = _httpServer;
    _httpServer = null;
    _transports.clear();
    _servers.clear();
    final closing = _registries.keys.toList().map(_disposeServer).toList();
    await Future.wait(closing);
    await subscription?.cancel();
    await httpServer?.close(force: true);
    await stoppingIpad;

    // Clear error when explicitly stopped
    _lastError = null;

    if (!_disposed) {
      DebugService().addLocalMessage('MCP server stopped');
      notifyListeners();
    }
  }

  Future<void> restart({int port = 3847, InternetAddress? bindAddress}) async {
    await stop();
    if (_ipad != null || defaultTargetPlatform == TargetPlatform.iOS) return;
    await Future.delayed(const Duration(milliseconds: 500));
    await start(port: port, bindAddress: bindAddress);
  }

  Future<void> _cleanup() async {
    _httpSubscription = null;
    _httpServer = null;
    _transports.clear();
    _servers.clear();
    final closing = _registries.keys.toList().map(_disposeServer).toList();
    await Future.wait(closing);
    if (!_disposed) notifyListeners();
  }

  McpServer _buildServer({_IpadGeneration? generation}) {
    if (!_active(generation)) throw StateError('MCP authority revoked');
    final registry = ToolRegistry(_distingCubit);

    final server = McpServer(
      Implementation(name: 'nt-helper-flutter', version: '1.39.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );

    // Register all tools from the shared registry
    registry.applyToMcpServer(
      server,
      canDispatch: generation == null ? null : () => _fresh(generation),
    );
    _resources(generation).registries[server] = registry;

    // Register and immediately disable a dummy resource to initialize the
    // resources/list handler. Without this, clients that call resources/list
    // get a "method not found" error that the transport never writes back
    // (mcp_dart bug with enableJsonResponse + error responses).
    server
        .registerResource(
          '_init',
          'nt://init',
          null,
          (uri, extra) => ReadResourceResult(contents: []),
        )
        .disable();

    return server;
  }

  /// Create a new transport and connect server following example pattern
  Future<StreamableHTTPServerTransport> _createNewTransport({
    String? sessionId,
    _IpadGeneration? generation,
  }) async {
    final resources = _resources(generation);
    final registries = resources.registries;
    final servers = resources.servers;
    final transports = resources.transports;
    if (!_active(generation)) {
      throw StateError('The MCP server stopped before session initialization.');
    }
    StreamableHTTPServerTransport? transport;
    McpServer? server;

    // Create new server instance first
    server = _buildServer(generation: generation);

    // Create new transport with event store for resumability. Leave
    // enableJsonResponse at the Streamable HTTP default so standard clients use
    // SSE for request responses and standalone server streams.
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: sessionId != null
            ? () => sessionId
            : () => generateUUID(),
        eventStore: InMemoryEventStore(),
        enableDnsRebindingProtection: true,
        allowedHosts: generation == null
            ? null
            : {generation.consent.policy.address.text},
        allowedOrigins: generation == null ? null : {_ipadEndpoint(generation)},
        onsessioninitialized: (initializedSessionId) {
          if (!_active(generation) || !registries.containsKey(server)) {
            unawaited(_disposeServer(server!, resources: resources));
            return;
          }
          if (servers.containsKey(initializedSessionId)) {
            unawaited(
              _cleanupSession(initializedSessionId, generation: generation),
            );
          }
          transports[initializedSessionId] = transport!;
          servers[initializedSessionId] = server!;
          if (generation == null) {
            DebugService().addLocalMessage(
              'MCP client connected (session: $initializedSessionId)',
            );
          }
        },
      ),
    );

    // Wrap transport to log outgoing responses
    final loggingTransport = _LoggingTransport(
      transport,
      log: generation == null,
    );

    // Connect server to the logging wrapper so send() calls are intercepted
    try {
      if (generation != null) await _ipad!.beforeConnect?.call();
      if (!await _fresh(generation)) throw StateError('MCP authority revoked');
      await server.connect(loggingTransport);
      if (!await _fresh(generation) || !registries.containsKey(server)) {
        throw StateError(
          'The MCP server stopped during session initialization.',
        );
      }
    } on Object {
      await _disposeServer(server, resources: resources);
      await transport.close();
      rethrow;
    }

    // connect installs the protocol's close handler. Preserve it, and attach
    // session cleanup afterwards so the SDK cannot overwrite our callback.
    final protocolOnClose = transport.onclose;
    transport.onclose = () {
      protocolOnClose?.call();
      final sessionId = transport!.sessionId;
      if (sessionId != null && identical(servers[sessionId], server)) {
        unawaited(_cleanupSession(sessionId, generation: generation));
      } else {
        unawaited(_disposeServer(server!, resources: resources));
      }
    };

    // Forward onmessage from the real transport to the logging wrapper
    // so handleRequest triggers the server's handler
    final dispatch = loggingTransport.onmessage;
    transport.onmessage = (message) {
      if (_active(generation)) dispatch?.call(message);
    };

    return transport;
  }

  /// Clean up a specific session
  Future<void> _cleanupSession(
    String sessionId, {
    _IpadGeneration? generation,
  }) async {
    final resources = _resources(generation);
    final transport = resources.transports.remove(sessionId);
    final server = resources.servers.remove(sessionId);
    if (transport == null && server == null) return;
    if (generation == null) {
      DebugService().addLocalMessage(
        'MCP client disconnected (session: $sessionId)',
      );
    }
    if (server != null) {
      await _disposeServer(server, resources: resources);
    } else {
      await transport?.close();
    }
  }

  Future<void> _disposeServer(
    McpServer server, {
    _McpResources? resources,
  }) async {
    final registry = (resources ?? _desktop).registries.remove(server);
    if (registry == null) return;
    try {
      await registry.dispose();
    } on Object {
      // Finish closing the client even when hardware release is uncertain.
    } finally {
      try {
        await server.close();
      } on Object {
        // Registry ownership is already detached; other sessions still close.
      }
    }
  }
}

/// Transport wrapper that logs outgoing JSON-RPC responses via [DebugService].
/// The [McpServer] is connected to this wrapper so all [send] calls pass
/// through here before being forwarded to the real transport.
class _LoggingTransport implements Transport {
  _LoggingTransport(this._inner, {this.log = true});

  final StreamableHTTPServerTransport _inner;
  final bool log;

  @override
  Future<void> send(JsonRpcMessage message, {dynamic relatedRequestId}) async {
    if (log) {
      DebugService().addLocalMessage(
        'MCP response: ${jsonEncode(message.toJson())}',
      );
    }
    return _inner.send(message, relatedRequestId: relatedRequestId);
  }

  @override
  Future<void> start() => _inner.start();

  @override
  Future<void> close() => _inner.close();

  @override
  String? get sessionId => _inner.sessionId;

  set sessionId(String? value) => _inner.sessionId = value;

  @override
  void Function()? get onclose => _inner.onclose;

  @override
  set onclose(void Function()? value) => _inner.onclose = value;

  @override
  void Function(Error error)? get onerror => _inner.onerror;

  @override
  set onerror(void Function(Error error)? value) => _inner.onerror = value;

  @override
  void Function(JsonRpcMessage message)? get onmessage => _inner.onmessage;

  @override
  set onmessage(void Function(JsonRpcMessage message)? value) =>
      _inner.onmessage = value;
}

/// Minimal fake [HttpRequest] used to pump a synthetic init through a
/// [StreamableHTTPServerTransport] so it transitions to the initialized state.
/// Only the members actually touched by the transport are implemented.
class _SyntheticHttpRequest extends Stream<Uint8List> implements HttpRequest {
  _SyntheticHttpRequest({this.host, this.sessionId});

  final String? sessionId;
  final String? host;

  @override
  final String method = 'POST';

  @override
  late final HttpHeaders headers = _SyntheticHeaders(
    sessionId: sessionId,
    host: host,
  );

  @override
  late final HttpResponse response = _SyntheticHttpResponse();

  @override
  Uri get uri => Uri.parse('/mcp');

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<Uint8List>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // -- Unused members required by HttpRequest --
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not implemented on _SyntheticHttpRequest',
  );
}

class _SyntheticHeaders implements HttpHeaders {
  _SyntheticHeaders({this.sessionId, this.host});
  final String? sessionId;
  @override
  final String? host;

  @override
  ContentType? get contentType => ContentType.json;

  @override
  List<String>? operator [](String name) {
    final header = value(name);
    return header == null ? null : [header];
  }

  @override
  String? value(String name) {
    switch (name.toLowerCase()) {
      case 'host':
        return host;
      case 'accept':
        return 'application/json, text/event-stream';
      case 'content-type':
        return 'application/json';
      case 'mcp-session-id':
        return sessionId;
      default:
        return null;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not implemented on _SyntheticHeaders',
  );
}

class _SyntheticHttpResponse implements HttpResponse {
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Future get done => _doneCompleter.future;

  @override
  int statusCode = HttpStatus.ok;

  @override
  set bufferOutput(bool value) {}

  @override
  bool get bufferOutput => false;

  @override
  final HttpHeaders headers = _SyntheticResponseHeaders();

  @override
  void write(Object? object) {}

  @override
  void add(List<int> bytes) {}

  @override
  Future<void> flush() async {}

  @override
  Future close() async {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not implemented on _SyntheticHttpResponse',
  );
}

class _SyntheticResponseHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not implemented on _SyntheticResponseHeaders',
  );
}

/// Enhanced in-memory event store for MCP message persistence
class InMemoryEventStore implements EventStore {
  final Map<
    String,
    List<({EventId id, JsonRpcMessage message, DateTime timestamp})>
  >
  _events = {};
  int _eventCounter = 0;
  static const int maxEventsPerStream = 1000;
  static const Duration maxEventAge = Duration(hours: 24);

  @override
  Future<EventId> storeEvent(StreamId streamId, JsonRpcMessage message) async {
    final eventId = (++_eventCounter).toString();
    final now = DateTime.now();
    _events.putIfAbsent(streamId, () => []);
    _events[streamId]!.add((id: eventId, message: message, timestamp: now));

    _cleanupEvents(streamId);
    return eventId;
  }

  void _cleanupEvents(StreamId streamId) {
    final events = _events[streamId];
    if (events == null) return;

    final now = DateTime.now();
    events.removeWhere(
      (event) => now.difference(event.timestamp) > maxEventAge,
    );

    if (events.length > maxEventsPerStream) {
      events.removeRange(0, events.length - maxEventsPerStream);
    }
  }

  @override
  Future<StreamId> replayEventsAfter(
    EventId lastEventId, {
    required Future<void> Function(EventId eventId, JsonRpcMessage message)
    send,
  }) async {
    String? streamId;
    int fromIndex = -1;

    for (final entry in _events.entries) {
      final idx = entry.value.indexWhere((event) => event.id == lastEventId);
      if (idx >= 0) {
        streamId = entry.key;
        fromIndex = idx;
        break;
      }
    }

    if (streamId == null) {
      throw StateError('Event ID not found: $lastEventId');
    }

    for (int i = fromIndex + 1; i < _events[streamId]!.length; i++) {
      final event = _events[streamId]![i];
      await send(event.id, event.message);
    }
    return streamId;
  }
}
