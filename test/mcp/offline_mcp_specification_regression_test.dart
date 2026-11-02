import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/metadata_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late DistingCubit cubit;
  late ToolRegistry registry;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    expect(
      await MetadataImportService(database).importFromJson(
        await File('assets/metadata/full_metadata.json').readAsString(),
      ),
      isTrue,
    );
    await AlgorithmMetadataService().initialize(database);
  });

  setUp(() async {
    cubit = DistingCubit(database, midiCommand: MockMidiCommand());
    await cubit.goOffline();
    registry = ToolRegistry(cubit);
  });

  tearDown(() async {
    await cubit.close();
  });

  tearDownAll(() async {
    await database.close();
  });

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> args,
  ) async =>
      jsonDecode(await registry.executeTool(name, args))
          as Map<String, dynamic>;

  Future<void> waitForParameters(int index, int count) async {
    bool ready(DistingState state) =>
        state is DistingStateSynchronized &&
        state.slots.length > index &&
        state.slots[index].parameters.length == count;
    if (ready(cubit.state)) return;
    await cubit.stream
        .firstWhere(ready)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            final current = cubit.state as DistingStateSynchronized;
            throw StateError(
              'Expected slot $index to have $count parameters; actual '
              '${current.slots.map((slot) => '${slot.algorithm.guid}:${slot.parameters.length}').toList()}',
            );
          },
        );
  }

  Future<void> createTwoChannels() async {
    final response = await call('new', {
      'name': 'Two channel attenuverter',
      'algorithms': [
        {
          'guid': 'attn',
          'specifications': [2],
        },
      ],
    });
    expect(response['success'], isTrue, reason: '$response');
    await waitForParameters(0, 21);
    final state = cubit.state as DistingStateSynchronized;
    expect(state.slots, hasLength(1));
    expect(state.slots.single.algorithm.specifications, [2]);
    expect(state.slots.single.parameters, hasLength(21));
  }

  test('built-in chat new preserves explicit Channels 2', () async {
    final bridge = ToolBridgeService(registry);
    final response =
        jsonDecode(
              await bridge.executeTool('new', {
                'name': 'Chat two channels',
                'algorithms': [
                  {
                    'guid': 'attn',
                    'specifications': [2],
                  },
                ],
              }),
            )
            as Map<String, dynamic>;
    expect(response['success'], isTrue, reason: '$response');
    await waitForParameters(0, 21);
    final slot = (cubit.state as DistingStateSynchronized).slots.single;
    expect(slot.algorithm.specifications, [2]);
    expect(slot.parameters, hasLength(21));
    final definitions = bridge.toolDefinitions;
    final schema = definitions
        .singleWhere((tool) => tool.name == 'new')
        .inputSchema;
    expect(
      schema['properties']['algorithms']['items']['properties']['specifications']['items']['type'],
      'integer',
    );
  });

  test(
    'built-in chat rejects invalid explicit specs without appending',
    () async {
      final bridge = ToolBridgeService(registry);
      for (final invalid in <List<dynamic>>[
        [0],
        [13],
        [2, 3],
        ['2'],
      ]) {
        final response =
            jsonDecode(
                  await bridge.executeTool('add', {
                    'guid': 'attn',
                    'specifications': invalid,
                  }),
                )
                as Map<String, dynamic>;
        expect(response['success'], isFalse, reason: '$response');
        expect((cubit.state as DistingStateSynchronized).slots, isEmpty);
      }
    },
  );

  test('MCP new honors Channels 2 and exposes expanded defaults', () async {
    await createTwoChannels();
    final state = cubit.state as DistingStateSynchronized;
    final slot = state.slots.single;
    final values = {
      for (final value in slot.values) value.parameterNumber: value.value,
    };
    expect(slot.parameters[11].name, '2:Input');
    expect(slot.parameters[20].name, '2:Gain');
    expect(values[1], 1);
    expect(values[11], 1);
    expect(values[2], 1);
    expect(values[12], 0);
    expect(values[8], 0);
    expect(values[18], 0);
    expect(values[3], 1000);
    expect(values[13], 1000);
    expect(values[4], 0);
    expect(values[14], 0);
    final channels = state.algorithms
        .singleWhere((algorithm) => algorithm.guid == 'attn')
        .specifications
        .single;
    expect(channels.min, 1);
    expect(channels.max, 12);
    expect(channels.defaultValue, 1);
  });

  test(
    'MCP add accepts both declared channel bounds with matching shapes',
    () async {
      for (final channels in [1, 12]) {
        final response = await call('add', {
          'guid': 'attn',
          'specifications': [channels],
        });
        expect(response['success'], isTrue, reason: '$response');
        await waitForParameters(channels == 1 ? 0 : 1, 1 + channels * 10);
        final slot = (cubit.state as DistingStateSynchronized).slots.last;
        expect(slot.algorithm.specifications, [channels]);
        expect(slot.parameters, hasLength(1 + channels * 10));
        expect(slot.parameters.last.name, '$channels:Gain');
      }
    },
  );

  test(
    'MCP edit preserves None outputs and routes inputs 3 and 4 in place',
    () async {
      await createTwoChannels();
      final response = await call('edit_slot', {
        'slot_index': 0,
        'data': {
          'parameters': [
            {'parameter_number': 1, 'value': 'Input 3'},
            {'parameter_number': 11, 'value': 'Input 4'},
            {'parameter_number': 12, 'value': 'On'},
            {'parameter_number': 8, 'value': 'None'},
            {'parameter_number': 18, 'value': 'None'},
          ],
        },
      });
      expect(response['success'], isTrue, reason: '$response');
      final state = cubit.state as DistingStateSynchronized;
      final slot = state.slots.single;
      expect(slot.algorithm.specifications, [2]);
      final values = {
        for (final value in slot.values) value.parameterNumber: value.value,
      };
      expect(values[1], 3);
      expect(values[11], 4);
      expect(values[8], 0);
      expect(values[18], 0);
      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: state.deviceIoProfile,
      );
      final replacements = routing.outputPorts.where(
        (port) => port.outputMode == OutputMode.replace,
      );
      expect(replacements.map((port) => port.busValue), containsAll([3, 4]));
    },
  );

  test(
    'MCP new keeps distinct specification shapes for repeated algorithms',
    () async {
      final response = await call('new', {
        'name': 'Distinct channel counts',
        'algorithms': [
          {
            'guid': 'attn',
            'specifications': [2],
          },
          {
            'guid': 'attn',
            'specifications': [3],
          },
        ],
      });
      expect(response['success'], isTrue, reason: '$response');
      await waitForParameters(0, 21);
      await waitForParameters(1, 31);
      final slots = (cubit.state as DistingStateSynchronized).slots;
      expect(slots.map((slot) => slot.algorithm.specifications), [
        [2],
        [3],
      ]);
      expect(slots[0].parameters.last.name, '2:Gain');
      expect(slots[1].parameters.last.name, '3:Gain');
    },
  );

  test(
    'same GUID unsupported specification edit rejects before any mutation',
    () async {
      await createTwoChannels();
      final original = (cubit.state as DistingStateSynchronized).slots.single;
      final response = await call('edit_slot', {
        'slot_index': 0,
        'data': {
          'algorithm': {
            'guid': 'attn',
            'specifications': [3],
          },
          'name': 'Must not change',
          'parameters': [
            {'parameter_number': 1, 'value': 'Input 3'},
          ],
        },
      });
      expect(response['success'], isFalse, reason: '$response');
      final current = (cubit.state as DistingStateSynchronized).slots.single;
      expect(current.algorithm.specifications, [2]);
      expect(current.algorithm.name, original.algorithm.name);
      expect(
        current.values.map((value) => value.value),
        original.values.map((value) => value.value),
      );
      expect(current.parameters, hasLength(21));
    },
  );

  test(
    'MCP replacement honors Channels 2 and retains its middle slot',
    () async {
      final created = await call('new', {
        'name': 'Replacement position',
        'algorithms': [
          {'guid': 'clck'},
          {'guid': 'note'},
          {'guid': 'lfo '},
        ],
      });
      expect(created['success'], isTrue, reason: '$created');
      bool presetReady(DistingState state) =>
          state is DistingStateSynchronized &&
          state.slots.length == 3 &&
          state.slots.every((slot) => slot.parameters.isNotEmpty);
      if (!presetReady(cubit.state)) {
        await cubit.stream
            .firstWhere(presetReady)
            .timeout(const Duration(seconds: 5));
      }
      final response = await call('edit_slot', {
        'slot_index': 1,
        'data': {
          'algorithm': {
            'guid': 'attn',
            'specifications': [2],
          },
        },
      });
      expect(response['success'], isTrue, reason: '$response');
      await waitForParameters(1, 21);
      final slots = (cubit.state as DistingStateSynchronized).slots;
      expect(slots.map((slot) => slot.algorithm.guid), [
        'clck',
        'attn',
        'lfo ',
      ]);
      expect(slots[1].algorithm.specifications, [2]);
      expect(slots[1].parameters.last.name, '2:Gain');
    },
  );

  for (final target in [0, 1]) {
    test(
      'MCP add Channels 2 at position $target preserves surrounding slots',
      () async {
        final created = await call('new', {
          'name': 'Insertion position',
          'algorithms': [
            {'guid': 'clck'},
            {'guid': 'note'},
            {'guid': 'lfo '},
          ],
        });
        expect(created['success'], isTrue, reason: '$created');
        bool presetReady(DistingState state) =>
            state is DistingStateSynchronized &&
            state.slots.length == 3 &&
            state.slots.every((slot) => slot.parameters.isNotEmpty);
        if (!presetReady(cubit.state)) {
          await cubit.stream
              .firstWhere(presetReady)
              .timeout(const Duration(seconds: 5));
        }
        final response = await call('add', {
          'guid': 'attn',
          'specifications': [2],
          'slot_index': target,
        });
        expect(response['success'], isTrue, reason: '$response');
        await waitForParameters(target, 21);
        final slots = (cubit.state as DistingStateSynchronized).slots;
        final expected = ['clck', 'note', 'lfo ']..insert(target, 'attn');
        expect(slots.map((slot) => slot.algorithm.guid), expected);
        expect(slots[target].algorithm.specifications, [2]);
        expect(slots[target].parameters.last.name, '2:Gain');
      },
    );
  }

  for (final builtInChat in [false, true]) {
    test(
      '${builtInChat ? 'built-in chat' : 'MCP'} invalid new batch preserves current preset',
      () async {
        await createTwoChannels();
        final original = cubit.state as DistingStateSynchronized;
        final args = <String, dynamic>{
          'name': 'Must not replace existing preset',
          'algorithms': [
            {
              'guid': 'attn',
              'specifications': [3],
            },
            {
              'guid': 'attn',
              'specifications': [13],
            },
          ],
        };
        final response = builtInChat
            ? jsonDecode(
                    await ToolBridgeService(registry).executeTool('new', args),
                  )
                  as Map<String, dynamic>
            : await call('new', args);
        expect(response['success'], isFalse, reason: '$response');
        final current = cubit.state as DistingStateSynchronized;
        expect(current.presetName, original.presetName);
        expect(current.slots, hasLength(1));
        expect(current.slots.single.algorithm.specifications, [2]);
        expect(
          current.slots.single.values.map((value) => value.value),
          original.slots.single.values.map((value) => value.value),
        );
      },
    );
  }

  test(
    'MCP new with unavailable nondefault shape preserves current preset',
    () async {
      await createTwoChannels();
      final original = cubit.state as DistingStateSynchronized;
      await (database.delete(
        database.algorithmRepeatGrammars,
      )..where((row) => row.algorithmGuid.equals('attn'))).go();
      final response = await call('new', {
        'name': 'Unsupported new preset',
        'algorithms': [
          {
            'guid': 'attn',
            'specifications': [3],
          },
        ],
      });
      expect(response['success'], isFalse, reason: '$response');
      final current = cubit.state as DistingStateSynchronized;
      expect(current.presetName, original.presetName);
      expect(current.slots, hasLength(1));
      expect(current.slots.single.algorithm.specifications, [2]);
      expect(
        current.slots.single.values.map((value) => value.value),
        original.slots.single.values.map((value) => value.value),
      );
    },
  tags: ['regression']);

  for (final corrupt in [false, true]) {
    test(
      'MCP add rejects explicit nondefault specs with ${corrupt ? 'corrupt' : 'missing'} grammar without mutation',
      () async {
        if (corrupt) {
          await (database.update(
            database.algorithmRepeatGrammars,
          )..where((row) => row.algorithmGuid.equals('attn'))).write(
            const AlgorithmRepeatGrammarsCompanion(grammarJson: Value('{')),
          );
        } else {
          await (database.delete(
            database.algorithmRepeatGrammars,
          )..where((row) => row.algorithmGuid.equals('attn'))).go();
        }
        final response = await call('add', {
          'guid': 'attn',
          'specifications': [3],
        });
        expect(response['success'], isFalse, reason: '$response');
        expect((cubit.state as DistingStateSynchronized).slots, isEmpty);
      },
    );
  }

  for (final invalid in <List<dynamic>>[
    [0],
    [13],
    [2, 3],
    ['2'],
  ]) {
    test(
      'MCP add rejects invalid specifications $invalid without appending',
      () async {
        final response = await call('add', {
          'guid': 'attn',
          'specifications': invalid,
        });
        expect(response['success'], isFalse, reason: '$response');
        expect((cubit.state as DistingStateSynchronized).slots, isEmpty);
      },
    );
  }
}
