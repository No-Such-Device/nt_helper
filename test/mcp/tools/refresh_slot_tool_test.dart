import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';

class _MockDistingController extends Mock implements DistingController {}

class _MockDistingCubit extends Mock implements DistingCubit {}

void main() {
  late _MockDistingController controller;
  late _MockDistingCubit cubit;
  late MCPAlgorithmTools tools;

  setUp(() {
    controller = _MockDistingController();
    cubit = _MockDistingCubit();
    tools = MCPAlgorithmTools(controller, cubit);
  });

  test('refreshes hardware before returning the compact slot', () async {
    when(() => controller.isSynchronized).thenReturn(true);
    when(() => controller.refreshSlot(3)).thenAnswer((_) async {});
    when(() => controller.getAlgorithmInSlot(3)).thenAnswer((_) async => null);

    final result = jsonDecode(await tools.refreshSlot(3));

    expect(result['success'], isTrue);
    expect(result['refreshed'], isTrue);
    expect(result['slot_index'], 3);
    expect(result['slot']['slot_index'], 3);
    verify(() => controller.refreshSlot(3)).called(1);
  });

  test('does not refresh when the device is not synchronized', () async {
    when(() => controller.isSynchronized).thenReturn(false);

    final result = jsonDecode(await tools.refreshSlot(0));

    expect(result['success'], isFalse);
    expect(result['error'], contains('not synchronized'));
    verifyNever(() => controller.refreshSlot(any()));
  });

  test('registers the explicit slot refresh tool', () {
    final entry = ToolRegistry(cubit).findByName('refresh_slot');

    expect(entry, isNotNull);
    expect(entry!.description, contains('re-read'));
    expect(entry.inputSchema['required'], ['slot_index']);
  });
}
