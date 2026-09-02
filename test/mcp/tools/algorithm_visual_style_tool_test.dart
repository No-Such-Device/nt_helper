import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/firmware_version.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AlgorithmVisualStyle());
  });

  test(
    'sets a complete algorithm visual style through the MCP registry',
    () async {
      const expectedStyle = AlgorithmVisualStyle(
        leftIndent: 3,
        rightIndent: 5,
        lineAbove: true,
        lineBelow: false,
        bracket: AlgorithmVisualBracket.open,
      );
      final cubit = _MockDistingCubit();
      when(() => cubit.state).thenReturn(
        DistingState.synchronized(
          disting: _MockDistingMidiManager(),
          distingVersion: '1.18.0beta',
          firmwareVersion: FirmwareVersion('1.18.0beta'),
          presetName: 'Style probe',
          algorithms: const [],
          slots: [_slot()],
          unitStrings: const [],
        ),
      );
      when(
        () => cubit.setAlgorithmVisualStyle(0, expectedStyle),
      ).thenAnswer((_) async {});

      final result =
          jsonDecode(
                await ToolRegistry(
                  cubit,
                ).executeTool('set_algorithm_visual_style', {
                  'slot_index': 0,
                  'left_indent': 3,
                  'right_indent': 5,
                  'line_above': true,
                  'line_below': false,
                  'bracket': 'open',
                }),
              )
              as Map<String, dynamic>;

      expect(result, {
        'success': true,
        'slot_index': 0,
        'visual_style': {
          'left_indent': 3,
          'right_indent': 5,
          'line_above': true,
          'line_below': false,
          'bracket': 'open',
        },
      });
      verify(() => cubit.setAlgorithmVisualStyle(0, expectedStyle)).called(1);
    },
  );

  test('rejects an out-of-range visual style without writing', () async {
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.18.0',
        firmwareVersion: FirmwareVersion('1.18.0'),
        presetName: 'Style probe',
        algorithms: const [],
        slots: [_slot()],
        unitStrings: const [],
      ),
    );

    final result =
        jsonDecode(
              await ToolRegistry(
                cubit,
              ).executeTool('set_algorithm_visual_style', {
                'slot_index': 0,
                'left_indent': 16,
                'right_indent': 0,
                'line_above': false,
                'line_below': false,
                'bracket': 'none',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['error'], contains('left_indent must be between 0 and 15'));
    verifyNever(() => cubit.setAlgorithmVisualStyle(any(), any()));
  });

  test('rejects an unknown bracket mode without writing', () async {
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.18.0',
        firmwareVersion: FirmwareVersion('1.18.0'),
        presetName: 'Style probe',
        algorithms: const [],
        slots: [_slot()],
        unitStrings: const [],
      ),
    );

    final result =
        jsonDecode(
              await ToolRegistry(
                cubit,
              ).executeTool('set_algorithm_visual_style', {
                'slot_index': 0,
                'left_indent': 0,
                'right_indent': 0,
                'line_above': false,
                'line_below': false,
                'bracket': 'nested',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['error'], contains('Unknown bracket mode'));
    verifyNever(() => cubit.setAlgorithmVisualStyle(any(), any()));
  });

  test('rejects an empty slot instead of reporting a false success', () async {
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.18.0',
        firmwareVersion: FirmwareVersion('1.18.0'),
        presetName: 'Style probe',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );

    final result =
        jsonDecode(
              await ToolRegistry(
                cubit,
              ).executeTool('set_algorithm_visual_style', {
                'slot_index': 0,
                'left_indent': 0,
                'right_indent': 0,
                'line_above': false,
                'line_below': false,
                'bracket': 'none',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['error'], contains('Slot 0 is empty'));
    verifyNever(() => cubit.setAlgorithmVisualStyle(any(), any()));
  });

  test('rejects connected firmware older than 1.18', () async {
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.17.2',
        firmwareVersion: FirmwareVersion('1.17.2'),
        presetName: 'Style probe',
        algorithms: const [],
        slots: [_slot()],
        unitStrings: const [],
      ),
    );

    final result =
        jsonDecode(
              await ToolRegistry(
                cubit,
              ).executeTool('set_algorithm_visual_style', {
                'slot_index': 0,
                'left_indent': 0,
                'right_indent': 0,
                'line_above': false,
                'line_below': false,
                'bracket': 'none',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['error'], contains('firmware 1.18 or newer'));
    verifyNever(() => cubit.setAlgorithmVisualStyle(any(), any()));
  });

  test('allows offline visual-style simulation on older firmware', () async {
    const expectedStyle = AlgorithmVisualStyle(
      leftIndent: 2,
      rightIndent: 1,
      lineBelow: true,
      bracket: AlgorithmVisualBracket.close,
    );
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.15.0',
        firmwareVersion: FirmwareVersion('1.15.0'),
        presetName: 'Offline style probe',
        algorithms: const [],
        slots: [_slot()],
        unitStrings: const [],
        offline: true,
      ),
    );
    when(
      () => cubit.setAlgorithmVisualStyle(0, expectedStyle),
    ).thenAnswer((_) async {});

    final result =
        jsonDecode(
              await ToolRegistry(
                cubit,
              ).executeTool('set_algorithm_visual_style', {
                'slot_index': 0,
                'left_indent': 2,
                'right_indent': 1,
                'line_above': false,
                'line_below': true,
                'bracket': 'close',
              }),
            )
            as Map<String, dynamic>;

    expect(result['success'], isTrue);
    expect(result['visual_style'], {
      'left_indent': 2,
      'right_indent': 1,
      'line_above': false,
      'line_below': true,
      'bracket': 'close',
    });
    verify(() => cubit.setAlgorithmVisualStyle(0, expectedStyle)).called(1);
  });
}

Slot _slot() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'swch', name: 'Switchboard'),
  routing: RoutingInfo.filler(),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: const [],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
