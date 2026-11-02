import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/remote_wire_harness.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _NonWriter extends Mock implements IDistingMidiManager {}

class _StalledWriter extends Mock
    implements IDistingMidiManager, RemoteControlWriter {}

DistingState _connected(
  IDistingMidiManager manager, {
  String version = '1.19.0',
  bool offline = false,
  bool demo = false,
}) => DistingState.synchronized(
  disting: manager,
  distingVersion: version,
  firmwareVersion: FirmwareVersion(version),
  presetName: 'Remote API test',
  algorithms: const [],
  slots: const [],
  unitStrings: const [],
  offline: offline,
  demo: demo,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const RemotePush(0));
    registerFallbackValue(DistingRequestCancellation());
  });
  late RemoteWireHarness wire;
  late DistingCubit cubit;
  late ToolRegistry registry;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 1000,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
    wire = RemoteWireHarness();
    final database = _Database();
    final metadata = _Metadata();
    when(() => database.metadataDao).thenReturn(metadata);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    cubit = DistingCubit(
      database,
      midiCommand: wire.midi,
      isWindowsOverride: true,
    );
    cubit.emit(_connected(wire.manager));
    registry = ToolRegistry(cubit);
  });

  tearDown(() async {
    try {
      await registry.dispose();
    } catch (_) {}
    await cubit.close();
    await wire.close();
  });

  Future<Map<String, dynamic>> call(
    String tool,
    Map<String, dynamic> args, {
    bool chat = false,
  }) async =>
      jsonDecode(
            chat
                ? await ToolBridgeService(registry).executeTool(tool, args)
                : await registry.executeTool(tool, args),
          )
          as Map<String, dynamic>;

  test(
    'both facades expose matching bounded remote schemas and truthful state',
    () async {
      final bridge = ToolBridgeService(registry);
      final control = registry.findByName('remote_control')!;
      expect(
        bridge.toolDefinitions
            .singleWhere((tool) => tool.name == 'remote_control')
            .inputSchema,
        control.inputSchema,
      );
      final actions = control.inputSchema['properties']['actions'] as Map;
      expect(actions['maxItems'], 32);
      expect(actions['minItems'], 1);
      expect(actions['items']['properties']['type']['enum'], [
        'push',
        'release',
        'encoder_turn',
        'pot_turn',
        'wait',
      ]);
      for (final chat in [false, true]) {
        final state = await call('remote_state', {}, chat: chat);
        expect(state['success'], isTrue);
        expect(state['available'], isTrue);
        expect(state['busy'], isFalse);
        expect(state['hardware_reported'], isNull);
        expect(state['acknowledged'], isFalse);
        expect(state['commanded']['pot_values'], [2048, 2048, 2048]);
        expect(state['commanded']['held_controls'], isEmpty);
        final capabilities = state['capabilities'] as Map;
        final controls = state['controls'] as Map;
        expect(capabilities['pot_indices'], [0, 1, 2]);
        expect(capabilities['pot_indices'], controls['pots'].values.toList());
        expect(
          capabilities['encoder_indices'],
          controls['encoders'].values.toList(),
        );
        expect(capabilities['push_indices'], [
          ...controls['buttons'].values,
          ...controls['pot_pushes'].values,
          ...controls['encoder_pushes'].values,
        ]);
        expect(state['capabilities']['holds_across_calls'], isFalse);
        expect(state['capabilities']['gesture_deadline_ms'], 6000);
        expect(state['capabilities']['cleanup_deadline_ms'], 2000);
      }
      expect(wire.remoteAttempts, isEmpty);
    },
  );

  for (final chat in [false, true]) {
    final facade = chat ? 'chat' : 'MCP';
    test(
      '$facade sends held combinations in order and releases remaining holds',
      () async {
        final response = await call('remote_control', {
          'actions': [
            {'type': 'push', 'index': 3},
            {'type': 'push', 'index': 7},
            {'type': 'encoder_turn', 'index': 0, 'delta': -2},
            {'type': 'release', 'index': 3},
          ],
        }, chat: chat);
        expect(response['success'], isTrue, reason: '$response');
        expect(response['actions_completed'], 4);
        expect(response['delivery'], 'transport_send_only');
        expect(response['acknowledged'], isFalse);
        expect(response['hardware_reported'], isNull);
        expect(wire.remotePackets, [
          remoteFrame([1, 3]),
          remoteFrame([1, 7]),
          remoteFrame([3, 0, 126]),
          remoteFrame([2, 3]),
          remoteFrame([2, 7]),
        ]);
        final state = await call('remote_state', {}, chat: chat);
        expect(state['commanded']['held_controls'], isEmpty);
        expect(state['busy'], isFalse);
        expect(cubit.remoteControlState.sessionId, isNull);
      },
    );

    test(
      '$facade accepts pot endpoints as commanded state without readback claims',
      () async {
        final response = await call('remote_control', {
          'actions': [
            {'type': 'pot_turn', 'index': 0, 'value': 0},
            {'type': 'pot_turn', 'index': 2, 'value': 4095},
          ],
        }, chat: chat);
        expect(response['success'], isTrue, reason: '$response');
        expect(wire.remotePackets, [
          remoteFrame([4, 0, 0, 0]),
          remoteFrame([4, 2, 127, 31]),
        ]);
        final state = await call('remote_state', {}, chat: chat);
        expect(state['commanded']['pot_values'], [0, 2048, 4095]);
        expect(state['hardware_reported'], isNull);
        expect(state['acknowledged'], isFalse);
      },
    );

    test('$facade counts waits and no-ops as processed actions', () async {
      final response = await call('remote_control', {
        'actions': [
          {'type': 'wait', 'duration_ms': 0},
          {'type': 'encoder_turn', 'index': 0, 'delta': 0},
          {'type': 'release', 'index': 0},
          {'type': 'pot_turn', 'index': 1, 'value': 2048},
        ],
      }, chat: chat);
      expect(response['success'], isTrue);
      expect(response['actions_completed'], 4);
      expect(wire.remotePackets, isEmpty);
    });

    test('$facade supports every advertised pot index', () async {
      final state = await call('remote_state', {}, chat: chat);
      for (final index in state['capabilities']['pot_indices'] as List) {
        final response = await call('remote_control', {
          'actions': [
            {'type': 'pot_turn', 'index': index, 'value': 1024},
          ],
        }, chat: chat);
        expect(response['success'], isTrue);
      }
      expect(wire.remotePackets, [
        for (final index in [0, 1, 2]) remoteFrame([4, index, 0, 8]),
      ]);
      expect(cubit.remoteControlState.potValues, [1024, 1024, 1024]);
    });

    test(
      '$facade prevalidates entire batches and rejects invalid input without writes',
      () async {
        final invalid = <Map<String, dynamic>>[
          {},
          {'actions': []},
          {
            'actions': List.generate(33, (_) => {'type': 'push', 'index': 0}),
          },
          {
            'actions': [
              {'type': 'push', 'index': 9},
            ],
          },
          {
            'actions': [
              {'type': 'encoder_turn', 'index': 2, 'delta': 1},
            ],
          },
          {
            'actions': [
              {'type': 'encoder_turn', 'index': 0, 'delta': 1025},
            ],
          },
          {
            'actions': [
              for (var i = 0; i < 3; i++)
                {'type': 'encoder_turn', 'index': 0, 'delta': 1024},
            ],
          },
          {
            'actions': [
              {'type': 'pot_turn', 'index': 0, 'value': -1},
            ],
          },
          {
            'actions': [
              {'type': 'pot_turn', 'index': 0, 'value': 4096},
            ],
          },
          {
            'actions': [
              {'type': 'pot_turn', 'index': 3, 'value': 0},
            ],
          },
          {
            'actions': [
              {'type': 'wait', 'duration_ms': 1001},
            ],
          },
          {
            'actions': [
              for (var i = 0; i < 3; i++) {'type': 'wait', 'duration_ms': 1000},
            ],
          },
          {
            'actions': [
              {'type': 'push', 'index': '1'},
            ],
          },
          {
            'actions': [
              {'type': 'encoder_turn', 'index': 0, 'delta': 1.0},
            ],
          },
          {
            'actions': [
              {'type': 'push', 'index': 0, 'extra': true},
            ],
          },
          {
            'actions': [
              {'type': 'unknown', 'index': 0},
            ],
          },
          {
            'actions': [
              {'type': 'push', 'index': 0},
              {'type': 'pot_turn', 'index': 0, 'value': 4096},
            ],
          },
          {
            'actions': [
              {'type': 'push', 'index': 0},
            ],
            'session_id': 'not allowed',
          },
        ];
        for (final request in invalid) {
          final response = await call('remote_control', request, chat: chat);
          expect(response['success'], isFalse, reason: '$request => $response');
          expect(wire.remoteAttempts, isEmpty, reason: '$request');
          expect(cubit.remoteControlState.sessionId, isNull);
        }
      },
    , tags: ['regression']);

    test(
      '$facade gates unavailable firmware, offline, demo, and non-writer managers',
      () async {
        final states = [
          _connected(wire.manager, version: '1.18.99'),
          _connected(wire.manager, version: 'unknown'),
          _connected(wire.manager, offline: true),
          _connected(wire.manager, demo: true),
          _connected(_NonWriter()),
          const DistingState.initial(),
        ];
        for (final state in states) {
          cubit.emit(state);
          final available = await call('remote_state', {}, chat: chat);
          expect(available['available'], isFalse);
          expect(available['unavailable_reason'], isNotEmpty);
          final response = await call('remote_control', {
            'actions': [
              {'type': 'push', 'index': 0},
            ],
          }, chat: chat);
          expect(response['success'], isFalse, reason: '$response');
          expect(wire.remoteAttempts, isEmpty);
        }
      },
    );
  }

  test(
    'declared cumulative encoder and wait limits are accepted exactly',
    () async {
      final response = await call('remote_control', {
        'actions': [
          {'type': 'encoder_turn', 'index': 0, 'delta': 1024},
          {'type': 'wait', 'duration_ms': 1000},
          {'type': 'encoder_turn', 'index': 1, 'delta': -1024},
          {'type': 'wait', 'duration_ms': 1000},
        ],
      });
      expect(response['success'], isTrue, reason: '$response');
      final totals = [0, 0];
      for (final frame in wire.remotePackets) {
        expect(frame[7], 3);
        final raw = frame[9];
        totals[frame[8]] += raw >= 64 ? raw - 128 : raw;
      }
      expect(totals, [1024, -1024]);
    },
  );

  test(
    'an existing UI host is refused without taking its session or releasing its hold',
    () async {
      final token = cubit.openRemoteSession();
      final state = await call('remote_state', {});
      expect(state['busy'], isTrue);
      final response = await call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 1},
        ],
      });
      expect(response['success'], isFalse);
      expect(cubit.remoteControlState.sessionId, token);
      expect(wire.remoteAttempts, isEmpty);
      await cubit.closeRemoteSession(token);
    },
  );

  test(
    'cancellation releases its hold and drops later turns, then permits another call',
    () async {
      final pushed = Completer<void>();
      wire.onSend = (packet) {
        if (packet[7] == 1 && !pushed.isCompleted) pushed.complete();
      };
      final active = call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 4},
          {'type': 'wait', 'duration_ms': 1000},
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      await pushed.future.timeout(const Duration(seconds: 2));
      await registry.cancelRemoteControl();
      final response = await active;
      expect(response['success'], isFalse);
      expect(wire.remotePackets, [
        remoteFrame([1, 4]),
        remoteFrame([2, 4]),
      ]);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      final next = await call('remote_control', {
        'actions': [
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      expect(next['success'], isTrue, reason: '$next');
    },
  , tags: ['regression']);

  test(
    'two registry clients cannot take ownership of an active gesture',
    () async {
      final other = ToolRegistry(cubit);
      final pushed = Completer<void>();
      wire.onSend = (packet) {
        if (packet[7] == 1 && !pushed.isCompleted) pushed.complete();
      };
      final active = call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 4},
          {'type': 'wait', 'duration_ms': 1000},
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      try {
        await pushed.future.timeout(const Duration(seconds: 2));
        final token = cubit.remoteControlState.sessionId;
        final refused =
            jsonDecode(
                  await other.executeTool('remote_control', {
                    'actions': [
                      {'type': 'pot_turn', 'index': 0, 'value': 0},
                    ],
                  }),
                )
                as Map;
        expect(refused['success'], isFalse);
        expect(refused['error'], contains('busy'));
        expect(cubit.remoteControlState.sessionId, token);
        await registry.cancelRemoteControl();
        expect((await active)['success'], isFalse);
        expect(wire.remotePackets, [
          remoteFrame([1, 4]),
          remoteFrame([2, 4]),
        ]);
      } finally {
        await other.dispose();
      }
    },
  , tags: ['regression']);

  test(
    'registry disposal cancels held gesture and refuses future remote writes',
    () async {
      final pushed = Completer<void>();
      wire.onSend = (packet) {
        if (packet[7] == 1 && !pushed.isCompleted) pushed.complete();
      };
      final active = call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 5},
          {'type': 'wait', 'duration_ms': 1000},
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      await pushed.future.timeout(const Duration(seconds: 2));
      await registry.dispose();
      expect((await active)['success'], isFalse);
      final next = await call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 1},
        ],
      });
      expect(next['success'], isFalse);
      expect(next['error'], contains('disposed'));
      expect((await call('remote_state', {}))['available'], isFalse);
      expect(wire.remotePackets, [
        remoteFrame([1, 5]),
        remoteFrame([2, 5]),
      ]);
    },
  , tags: ['regression']);

  test(
    'six second gesture deadline and two second cleanup budget terminate a blocked writer',
    () {
      final writer = _StalledWriter();
      final blocked = Completer<void>();
      final actions = <RemoteAction>[];
      when(
        () => writer.requestRemoteAction(
          any(),
          cancellation: any(named: 'cancellation'),
        ),
      ).thenAnswer((invocation) {
        final action = invocation.positionalArguments.single as RemoteAction;
        actions.add(action);
        return action is RemoteEncoderTurn
            ? blocked.future
            : Future<void>.value();
      });
      fakeAsync((clock) {
        cubit.emit(_connected(writer));
        Map<String, dynamic>? result;
        call('remote_control', {
          'actions': [
            {'type': 'push', 'index': 4},
            {'type': 'encoder_turn', 'index': 0, 'delta': 1},
            {'type': 'pot_turn', 'index': 0, 'value': 0},
          ],
        }).then((value) => result = value);
        clock.flushMicrotasks();
        expect(actions.map((action) => action.runtimeType), [
          RemotePush,
          RemoteEncoderTurn,
        ]);
        clock.elapse(const Duration(milliseconds: 5999));
        expect(result, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        expect(
          result,
          isNull,
          reason: 'cleanup gets its own bounded two second budget',
        );
        clock.elapse(const Duration(milliseconds: 1999));
        expect(result, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        expect(result?['success'], isFalse);
        expect(result?['error'], contains('deadline'));
        expect(result?['release_status'], 'unknown');
        expect(result?['acknowledged'], isFalse);
        expect(actions.whereType<RemotePotTurn>(), isEmpty);
        blocked.complete();
        clock.flushMicrotasks();
        expect(
          actions.whereType<RemotePotTurn>(),
          isEmpty,
          reason: 'later completion cannot resume cancelled gesture',
        );
      });
    },
  , tags: ['regression']);

  test(
    'transport and cleanup failures report unknown release without hardware acknowledgement',
    () async {
      wire.onSend = (packet) {
        if (packet[7] == 1) wire.failRemoteSend = true;
      };
      final response = await call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 4},
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      expect(response['success'], isFalse, reason: '$response');
      expect(response['release_status'], 'unknown');
      expect(response['cleanup_error'], contains('unknown'));
      final state = await call('remote_state', {});
      expect(state['commanded']['pending_release_controls'], contains(4));
      expect(response['acknowledged'], isFalse);
      expect(response['hardware_reported'], isNull);
      expect(wire.remotePackets, [
        remoteFrame([1, 4]),
      ]);
      expect(wire.remoteAttempts, anyElement(equals(remoteFrame([2, 4]))));
      wire.failRemoteSend = false;
    },
  , tags: ['regression']);

  test(
    'disconnect during a wait drops later actions and reports unknown release',
    () async {
      final pushed = Completer<void>();
      wire.onSend = (packet) {
        if (packet[7] == 1 && !pushed.isCompleted) pushed.complete();
      };
      final active = call('remote_control', {
        'actions': [
          {'type': 'push', 'index': 4},
          {'type': 'wait', 'duration_ms': 20},
          {'type': 'encoder_turn', 'index': 0, 'delta': 1},
        ],
      });
      await pushed.future.timeout(const Duration(seconds: 2));
      cubit.emit(const DistingState.initial());
      final response = await active;
      expect(response['success'], isFalse, reason: '$response');
      expect(response['release_status'], 'unknown');
      expect(wire.remotePackets.where((packet) => packet[7] == 3), isEmpty);
      expect((await call('remote_state', {}))['available'], isFalse);
    },
  , tags: ['regression']);

  test(
    'actual MCP HTTP lists remote schemas and executes the registered control tool',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = HttpClient();
      McpServerService.initialize(distingCubit: cubit);
      final service = McpServerService.instance;
      try {
        await service.start(port: 0, bindAddress: InternetAddress.loopbackIPv4);
        final port = service.boundPort!;
        final initialize = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'capabilities': {},
            'clientInfo': {'name': 'remote-test', 'version': '1.0'},
          },
        });
        final session = initialize.$1.headers.value('mcp-session-id')!;
        expect(initialize.$2['result'], isNotNull);
        final notification = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, session: session);
        expect(notification.$1.statusCode, HttpStatus.accepted);
        final listing = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
          'params': {},
        }, session: session);
        final tools = (listing.$2['result']['tools'] as List).cast<Map>();
        expect(
          tools.map((tool) => tool['name']),
          containsAll(['remote_state', 'remote_control']),
        );
        final schema =
            tools.singleWhere(
                  (tool) => tool['name'] == 'remote_control',
                )['inputSchema']
                as Map;
        expect(schema, registry.findByName('remote_control')!.inputSchema);
        expect(
          tools.singleWhere(
            (tool) => tool['name'] == 'remote_state',
          )['inputSchema'],
          registry.findByName('remote_state')!.inputSchema,
        );
        expect(schema['properties']['actions']['maxItems'], 32);
        final beforeInvalid = wire.remoteAttempts.length;
        for (final arguments in [
          {
            'actions': [
              {'type': 'encoder_turn', 'index': 2, 'delta': 1},
            ],
          },
          {
            'actions': [
              {'type': 'pot_turn', 'index': 3, 'value': 0},
            ],
          },
          {
            'actions': [
              {'type': 'wait'},
            ],
          },
          {
            'actions': [
              {'type': 'push', 'index': 0, 'delta': 1},
            ],
          },
          {
            'actions': [
              {'type': 'wait', 'duration_ms': 0},
            ],
            'extra': true,
          },
        ]) {
          final invalid = await _rpc(client, port, {
            'jsonrpc': '2.0',
            'id': 99,
            'method': 'tools/call',
            'params': {'name': 'remote_control', 'arguments': arguments},
          }, session: session);
          final result = invalid.$2['result'] as Map?;
          expect(
            invalid.$2['error'] != null || result?['isError'] == true,
            isTrue,
            reason: '${invalid.$2}',
          );
          expect(wire.remoteAttempts.length, beforeInvalid);
        }
        final execution = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'remote_control',
            'arguments': {
              'actions': [
                {'type': 'push', 'index': 0},
                {'type': 'encoder_turn', 'index': 1, 'delta': 2},
                {'type': 'release', 'index': 0},
              ],
            },
          },
        }, session: session);
        final content = execution.$2['result']['content'] as List;
        final result = jsonDecode(content.single['text'] as String) as Map;
        expect(result['success'], isTrue, reason: '$result');
        expect(result['acknowledged'], isFalse);
        expect(wire.remotePackets, [
          remoteFrame([1, 0]),
          remoteFrame([3, 1, 2]),
          remoteFrame([2, 0]),
        ]);
        // A second actual MCP client keeps its independent registry after the
        // first client's DELETE cancels a gesture which currently holds a key.
        final secondInit = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2025-06-18',
            'capabilities': {},
            'clientInfo': {'name': 'remote-second-test', 'version': '1.0'},
          },
        });
        final secondSession = secondInit.$1.headers.value('mcp-session-id')!;
        await _rpc(client, port, {
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
        }, session: secondSession);
        wire.sentPackets.clear();
        final pushed = Completer<void>();
        wire.onSend = (frame) {
          if (frame[7] == 1 && !pushed.isCompleted) pushed.complete();
        };
        final activeCall = _rpc(
          client,
          port,
          {
            'jsonrpc': '2.0',
            'id': 5,
            'method': 'tools/call',
            'params': {
              'name': 'remote_control',
              'arguments': {
                'actions': [
                  {'type': 'push', 'index': 4},
                  {'type': 'wait', 'duration_ms': 1000},
                  {'type': 'encoder_turn', 'index': 0, 'delta': 1},
                ],
              },
            },
          },
          session: session,
        ).then<Object?>((value) => value, onError: (Object error) => error);
        await pushed.future.timeout(const Duration(seconds: 2));
        final delete = await client.deleteUrl(
          Uri.parse('http://127.0.0.1:$port/mcp'),
        );
        delete.headers.set('mcp-session-id', session);
        final deleted = await delete.close();
        expect(deleted.statusCode, HttpStatus.ok);
        await deleted.drain<void>();
        final cancelledMessage = await activeCall;
        if (cancelledMessage is (HttpClientResponse, Map<String, dynamic>)) {
          final cancelledContent =
              cancelledMessage.$2['result']['content'] as List;
          final cancelled =
              jsonDecode(cancelledContent.single['text'] as String) as Map;
          expect(cancelled['success'], isFalse, reason: '$cancelled');
        } else {
          // DELETE may terminate the SSE stream before its cancelled tool can
          // deliver a JSON-RPC result. Its physical cleanup is asserted below.
          expect(
            cancelledMessage,
            anyOf(
              isA<StateError>(),
              isA<HttpException>(),
              isA<SocketException>(),
            ),
          );
        }
        expect(wire.remotePackets, [
          remoteFrame([1, 4]),
          remoteFrame([2, 4]),
        ]);
        final secondCall = await _rpc(client, port, {
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'tools/call',
          'params': {
            'name': 'remote_control',
            'arguments': {
              'actions': [
                {'type': 'encoder_turn', 'index': 1, 'delta': 2},
              ],
            },
          },
        }, session: secondSession);
        final secondContent = secondCall.$2['result']['content'] as List;
        expect(
          (jsonDecode(secondContent.single['text'] as String)
              as Map)['success'],
          isTrue,
        );
        expect(wire.remotePackets.last, remoteFrame([3, 1, 2]));

        // Stopping the server must also release a live hold and prevent the
        // remaining turn even when its HTTP stream is closed during teardown.
        wire.sentPackets.clear();
        final stopPushed = Completer<void>();
        wire.onSend = (frame) {
          if (frame[7] == 1 && !stopPushed.isCompleted) stopPushed.complete();
        };
        final stoppingCall = _rpc(
          client,
          port,
          {
            'jsonrpc': '2.0',
            'id': 7,
            'method': 'tools/call',
            'params': {
              'name': 'remote_control',
              'arguments': {
                'actions': [
                  {'type': 'push', 'index': 5},
                  {'type': 'wait', 'duration_ms': 1000},
                  {'type': 'encoder_turn', 'index': 0, 'delta': 1},
                ],
              },
            },
          },
          session: secondSession,
        ).then<Object?>((value) => value, onError: (Object error) => error);
        await stopPushed.future.timeout(const Duration(seconds: 2));
        await service.stop();
        await stoppingCall;
        expect(wire.remotePackets, [
          remoteFrame([1, 5]),
          remoteFrame([2, 5]),
        ]);
        expect(cubit.remoteControlState.sessionId, isNull);
        expect(cubit.remoteControlState.heldControls, isEmpty);
      } finally {
        await service.stop();
        client.close(force: true);
        HttpOverrides.global = previous;
      }
    },
  , tags: ['regression']);
}

Future<(HttpClientResponse, Map<String, dynamic>)> _rpc(
  HttpClient client,
  int port,
  Map<String, dynamic> body, {
  String? session,
}) async {
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
  request.headers.set(
    HttpHeaders.acceptHeader,
    'application/json, text/event-stream',
  );
  request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  if (session != null) request.headers.set('mcp-session-id', session);
  request.write(jsonEncode(body));
  final response = await request.close().timeout(const Duration(seconds: 5));
  final text = await utf8
      .decodeStream(response)
      .timeout(const Duration(seconds: 5));
  if (text.isEmpty) return (response, <String, dynamic>{});
  if (response.headers.contentType?.mimeType == 'application/json') {
    return (response, (jsonDecode(text) as Map).cast<String, dynamic>());
  }
  for (final block in text.split(RegExp(r'\r?\n\r?\n'))) {
    final data = block
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trimLeft())
        .join('\n')
        .trim();
    if (data.isEmpty) continue;
    final decoded = jsonDecode(data);
    if (decoded is Map && decoded['jsonrpc'] == '2.0') {
      return (response, decoded.cast<String, dynamic>());
    }
  }
  throw StateError('No JSON-RPC response found');
}
