import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
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
