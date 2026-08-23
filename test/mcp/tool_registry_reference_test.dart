import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/tool_reference_store.dart';
import 'package:nt_helper/mcp/tool_registry.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  group('ToolRegistry references', () {
    test(
      'large results become references that can be read and searched',
      () async {
        final largeResult =
            '${'alpha ' * 2000}needle ${'beta ' * 2200}needle tail';
        final registry = ToolRegistry(
          MockDistingCubit(),
          extraEntries: [
            ToolRegistryEntry(
              name: 'large_tool',
              description: 'Returns a large result.',
              inputSchema: const {'properties': {}},
              handler: (_) async => largeResult,
            ),
          ],
        );

        final result =
            jsonDecode(await registry.executeTool('large_tool', {}))
                as Map<String, dynamic>;

        expect(result['success'], isTrue);
        expect(result['type'], 'tool_reference');
        expect(result['tool_name'], 'large_tool');
        expect(result['total_chars'], largeResult.length);
        final referenceId = result['reference_id'] as String;

        final page =
            jsonDecode(
                  await registry.executeTool(ToolReferenceStore.readToolName, {
                    'reference_id': referenceId,
                    'offset': 0,
                    'limit': 64,
                  }),
                )
                as Map<String, dynamic>;

        expect(page['success'], isTrue);
        expect(page['content'], largeResult.substring(0, 64));
        expect(page['has_more'], isTrue);
        expect(page['next_offset'], 64);

        final search =
            jsonDecode(
                  await registry
                      .executeTool(ToolReferenceStore.searchToolName, {
                        'reference_id': referenceId,
                        'query': 'needle',
                        'limit': 2,
                        'context_chars': 8,
                      }),
                )
                as Map<String, dynamic>;

        expect(search['success'], isTrue);
        expect(search['matches'], hasLength(2));
        expect(search['matches'][0]['preview'], contains('needle'));
      },
    );

    test('reference tools are registered in the shared tool list', () {
      final registry = ToolRegistry(MockDistingCubit());
      final names = registry.entries.map((entry) => entry.name).toSet();

      expect(names, contains(ToolReferenceStore.readToolName));
      expect(names, contains(ToolReferenceStore.searchToolName));
    });

    test('preset read and rename tools advertise safe distinct semantics', () {
      final registry = ToolRegistry(MockDistingCubit());
      final getPreset = registry.findByName('get_preset');
      final renamePreset = registry.findByName('rename_preset');

      expect(getPreset, isNotNull);
      expect(getPreset!.description, contains('complete current preset'));
      expect(getPreset.description, contains('without changing it'));
      expect(renamePreset, isNotNull);
      expect(renamePreset!.description, contains('Non-destructively'));
      expect(renamePreset.description, contains('instead of edit_preset'));
      expect(renamePreset.inputSchema['required'], ['name']);
      final properties =
          renamePreset.inputSchema['properties'] as Map<String, dynamic>;
      final name = properties['name'] as Map<String, dynamic>;
      expect(name['minLength'], 1);
      expect(name['maxLength'], 31);
    });
  });
}
