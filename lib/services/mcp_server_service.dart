import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nt_helper/services/ipad_local_network.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/debug_service.dart';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

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
class McpServerService extends ChangeNotifier with WidgetsBindingObserver {
  McpServerService._(this._distingCubit)
    : _isIos = Platform.isIOS,
      _readNetwork = IpadLocalNetwork.read,
      _bindHttp = ((address, port) => HttpServer.bind(address, port)) {
    if (_isIos) WidgetsBinding.instance.addObserver(this);
  }

  @visibleForTesting
  McpServerService.forTesting({
    required DistingCubit distingCubit,
    required Future<IpadLocalNetwork> Function() readNetwork,
    required Future<HttpServer> Function(InternetAddress, int) bindHttp,
  }) : _distingCubit = distingCubit,
       _isIos = true,
       _readNetwork = readNetwork,
       _bindHttp = bindHttp;

  final bool _isIos;
  final Future<IpadLocalNetwork> Function() _readNetwork;
  final Future<HttpServer> Function(InternetAddress, int) _bindHttp;
  bool _foreground = true;
  Future<void> _settingsWork = Future.value();
  List<String> _localEndpoints = const [];
  final Set<String> _ipadHosts = {'localhost'};
  List<String> get localEndpoints => _localEndpoints;

  /// All settings entry points share the same start/stop behavior.
  Future<void> applySettings() {
    return _settingsWork = _settingsWork.then((_) async {
      final settings = SettingsService();
      final enabled = _isIos ? settings.ipadMcpEnabled : settings.mcpEnabled;
      if (!enabled || (_isIos && !_foreground)) {
        await stop();
        return;
      }
      if (!_isIos &&
          !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
        return;
      }
      try {
        var address = settings.mcpRemoteConnections
            ? InternetAddress.anyIPv4
            : InternetAddress.loopbackIPv4;
        if (_isIos) {
          final network = await _readNetwork();
          if (!network.isIpad || network.subnets.isEmpty) {
            throw StateError(
              'Connect this iPad to Wi-Fi or Ethernet to use MCP.',
            );
          }
          _localEndpoints = network.subnets.map((s) => s.endpoint).toList();
          address = InternetAddress.anyIPv6;
          if (!_foreground || !settings.ipadMcpEnabled) return;
        }
        if (isRunning && boundAddress?.address != address.address) await stop();
        await start(bindAddress: address);
      } catch (error) {
        await stop();
        _lastError = error.toString();
        notifyListeners();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isIos) return;
    _foreground = state == AppLifecycleState.resumed;
    unawaited(applySettings());
  }

  @override
  void dispose() {
    if (_isIos) WidgetsBinding.instance.removeObserver(this);
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
  final Map<String, McpServer> _servers = {};
  final Map<String, StreamableHTTPServerTransport> _transports = {};
  final Map<McpServer, ToolRegistry> _registries = {};

  HttpServer? _httpServer;
  StreamSubscription<HttpRequest>? _httpSubscription;
  String? _lastError;

  bool get isRunning => _httpServer != null;
  int? get boundPort => _httpServer?.port;
  InternetAddress? get boundAddress => _httpServer?.address;

  /// Returns the last error that occurred when trying to start the server
  String? get lastError => _lastError;

  /// Returns true if MCP is enabled but failed to start
  bool get hasError => _lastError != null;

  /// Get basic connection diagnostics
  Map<String, dynamic> get connectionDiagnostics {
    return {
      'server_running': isRunning,
      'active_servers': _servers.length,
      'active_transports': _transports.length,
      'active_registries': _registries.length,
      'server_implementation': 'nt-helper-flutter',
      'library_version': 'mcp_dart 2.4.3',
    };
  }

  Future<void> start({int port = 3847, InternetAddress? bindAddress}) async {
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
      _httpServer = await _bindHttp(address, port);

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

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (_isIos) {
      final server = _httpServer;
      var allowed = false;
      try {
        final network = await _readNetwork();
        // The SDK defaults to localhost-only Host validation. Keep protection
        // enabled while accepting this iPad's current numeric LAN addresses.
        _ipadHosts
          ..clear()
          ..add('localhost') // Internal stale-session reinitialization request.
          ..addAll(network.subnets.map((subnet) => subnet.address.address));
        allowed =
            _foreground &&
            SettingsService().ipadMcpEnabled &&
            identical(server, _httpServer) &&
            isRunning &&
            network.allows(request.connectionInfo);
      } catch (_) {
        // Missing network evidence must not allow a request.
      }
      if (!allowed) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.persistentConnection = false;
        await request.response.close();
        return;
      }
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
  Future<void> _handlePostRequest(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    try {
      StreamableHTTPServerTransport? transport;

      if (sessionId != null && _transports.containsKey(sessionId)) {
        _log('POST /mcp: existing session $sessionId');
        transport = _transports[sessionId]!;
      } else {
        // Read the body to check if this is an init request or a stale session
        final bodyBytes = await request.fold<List<int>>(
          <int>[],
          (previous, element) => previous..addAll(element),
        );
        final bodyString = utf8.decode(bodyBytes);
        final parsedBody = jsonDecode(bodyString);

        DebugService().addLocalMessage('MCP request: $bodyString');

        final isInit = _isInitializeBody(parsedBody);

        if (!isInit && sessionId != null) {
          // Stale session — auto-reinitialize with the same session ID so
          // clients that don't handle 404 keep working after hot reload.
          _log('POST /mcp: stale session $sessionId, auto-reinitializing');
          DebugService().addLocalMessage(
            'MCP auto-reinit for stale session $sessionId',
          );
          transport = await _createNewTransport(sessionId: sessionId);

          // Pump a synthetic init through the transport to flip _initialized.
          // We must wait for the response to complete (the server processes
          // the init asynchronously via send()).
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
          final syntheticRequest = _SyntheticHttpRequest(sessionId: null);
          await transport.handleRequest(syntheticRequest, initBody);
          // Wait for the transport to finish writing the init response
          await syntheticRequest.response.done;

          _log(
            'POST /mcp: transport re-initialized, session: ${transport.sessionId}',
          );
          _log('POST /mcp: delegating real request to transport');
          await transport.handleRequest(request, parsedBody);
          _log('POST /mcp: handleRequest completed');
          return;
        }

        _log('POST /mcp: creating new transport (sessionId: $sessionId)');
        transport = await _createNewTransport(sessionId: sessionId);
        _log('POST /mcp: transport created, session: ${transport.sessionId}');

        _log('POST /mcp: delegating to transport.handleRequest');
        await transport.handleRequest(request, parsedBody);
        _log('POST /mcp: handleRequest completed');
        return;
      }

      // Existing session — read body, log, and delegate
      final bodyBytes = await request.fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      final bodyString = utf8.decode(bodyBytes);
      final parsedBody = jsonDecode(bodyString);

      _log('POST /mcp: delegating to transport.handleRequest');
      DebugService().addLocalMessage('MCP request: $bodyString');

      await transport.handleRequest(request, parsedBody);
      _log('POST /mcp: handleRequest completed');
    } catch (e) {
      DebugService().addLocalMessage('MCP error: ${e.toString()}');
      _sendErrorResponse(
        request,
        HttpStatus.internalServerError,
        'Internal server error: ${e.toString()}',
      );
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
  Future<void> _handleGetRequest(HttpRequest request) async {
    final sessionId = request.headers.value('mcp-session-id');
    if (sessionId == null) {
      _sendErrorResponse(
        request,
        HttpStatus.badRequest,
        'Missing session ID for SSE stream',
      );
      return;
    }

    final transport = _transports[sessionId];
    if (transport == null) {
      _sendErrorResponse(request, HttpStatus.notFound, 'Session not found');
      return;
    }

    _log('GET /mcp: opening SSE stream for session $sessionId');
    await transport.handleRequest(request);
  }

  /// Handle DELETE requests for session termination
  Future<void> _handleDeleteRequest(HttpRequest request) async {
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
      if (_transports.containsKey(sessionId)) {
        final transport = _transports.remove(sessionId)!;
        final server = _servers.remove(sessionId);
        // Invalidate this client's tools before yielding to gesture cleanup.
        // Let the transport write its DELETE response before closing the server.
        final registry = _registries.remove(server);
        try {
          await registry?.dispose();
        } on Object {
          // The remote operation records an uncertain release result itself.
        }
        try {
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
    if (!isRunning && _lastError == null && _registries.isEmpty) {
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

    // Clear error when explicitly stopped
    _lastError = null;

    DebugService().addLocalMessage('MCP server stopped');
    notifyListeners();
  }

  Future<void> restart({int port = 3847, InternetAddress? bindAddress}) async {
    await stop();
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
    notifyListeners();
  }

  McpServer _buildServer() {
    final registry = ToolRegistry(_distingCubit);

    final server = McpServer(
      Implementation(name: 'nt-helper-flutter', version: '1.39.0'),
      options: McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
      ),
    );

    // Register all tools from the shared registry
    registry.applyToMcpServer(server);
    _registries[server] = registry;

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
  }) async {
    if (!isRunning) {
      throw StateError('The MCP server stopped before session initialization.');
    }
    StreamableHTTPServerTransport? transport;
    McpServer? server;

    // Create new server instance first
    server = _buildServer();

    // Create new transport with event store for resumability. Leave
    // enableJsonResponse at the Streamable HTTP default so standard clients use
    // SSE for request responses and standalone server streams.
    transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        allowedHosts: _isIos ? _ipadHosts : null,
        sessionIdGenerator: sessionId != null
            ? () => sessionId
            : () => generateUUID(),
        eventStore: InMemoryEventStore(),
        onsessioninitialized: (initializedSessionId) {
          if (!_registries.containsKey(server)) return;
          if (_servers.containsKey(initializedSessionId)) {
            unawaited(_cleanupSession(initializedSessionId));
          }
          // Store both transport and server by session ID when session is initialized
          _transports[initializedSessionId] = transport!;
          _servers[initializedSessionId] = server!;
          DebugService().addLocalMessage(
            'MCP client connected (session: $initializedSessionId)',
          );
        },
      ),
    );

    // Wrap transport to log outgoing responses
    final loggingTransport = _LoggingTransport(transport);

    // Connect server to the logging wrapper so send() calls are intercepted
    try {
      await server.connect(loggingTransport);
      if (!isRunning || !_registries.containsKey(server)) {
        throw StateError(
          'The MCP server stopped during session initialization.',
        );
      }
    } on Object {
      await _disposeServer(server);
      rethrow;
    }

    // connect installs the protocol's close handler. Preserve it, and attach
    // session cleanup afterwards so the SDK cannot overwrite our callback.
    final protocolOnClose = transport.onclose;
    transport.onclose = () {
      protocolOnClose?.call();
      final sessionId = transport!.sessionId;
      if (sessionId != null && identical(_servers[sessionId], server)) {
        unawaited(_cleanupSession(sessionId));
      } else {
        unawaited(_disposeServer(server!));
      }
    };

    // Forward onmessage from the real transport to the logging wrapper
    // so handleRequest triggers the server's handler
    transport.onmessage = loggingTransport.onmessage;

    return transport;
  }

  /// Clean up a specific session
  Future<void> _cleanupSession(String sessionId) async {
    final transport = _transports.remove(sessionId);
    final server = _servers.remove(sessionId);
    if (transport == null && server == null) return;
    DebugService().addLocalMessage(
      'MCP client disconnected (session: $sessionId)',
    );
    if (server != null) {
      await _disposeServer(server);
    } else {
      await transport?.close();
    }
  }

  Future<void> _disposeServer(McpServer server) async {
    final registry = _registries.remove(server);
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
  _LoggingTransport(this._inner);

  final StreamableHTTPServerTransport _inner;

  @override
  Future<void> send(JsonRpcMessage message, {dynamic relatedRequestId}) async {
    DebugService().addLocalMessage(
      'MCP response: ${jsonEncode(message.toJson())}',
    );
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
  _SyntheticHttpRequest({this.sessionId});

  final String? sessionId;

  @override
  final String method = 'POST';

  @override
  late final HttpHeaders headers = _SyntheticHeaders(sessionId: sessionId);

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
  _SyntheticHeaders({this.sessionId});
  final String? sessionId;

  @override
  ContentType? get contentType => ContentType.json;

  @override
  String? value(String name) {
    switch (name.toLowerCase()) {
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
  HttpHeaders get headers => _SyntheticResponseHeaders();

  @override
  void write(Object? object) {}

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
