import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late _MockDistingCubit cubit;
  late _MockDistingMidiManager manager;
  late MCPAlgorithmTools tools;

  setUp(() {
    cubit = _MockDistingCubit();
    manager = _MockDistingMidiManager();
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: manager,
        distingVersion: '1.18.0',
        firmwareVersion: FirmwareVersion('1.18.0'),
        presetName: 'Directory test',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );
    tools = MCPAlgorithmTools(DistingControllerImpl(cubit), cubit);
  });

  test('preserves the exact order returned by the NT', () async {
    when(
      () => manager.requestDirectoryListing('/samples/Multisamples'),
    ).thenAnswer(
      (_) async => DirectoryListing(
        entries: [
          DirectoryEntry(
            name: 'K_HMU_Soft/',
            attributes: 0x10,
            date: 3,
            time: 4,
            size: 0,
          ),
          DirectoryEntry(
            name: 'BoC_Apart/',
            attributes: 0x10,
            date: 1,
            time: 2,
            size: 0,
          ),
          DirectoryEntry(
            name: 'notes.txt',
            attributes: 0x20,
            date: 5,
            time: 6,
            size: 123,
          ),
        ],
      ),
    );

    final result =
        jsonDecode(
              await tools.listSdDirectory({
                'path': '/samples/Multisamples/',
                'offset': 1,
                'limit': 2,
              }),
            )
            as Map<String, dynamic>;

    expect(result['path'], '/samples/Multisamples');
    expect(result['order'], 'device_response');
    expect(result['total'], 3);
    expect(result['offset'], 1);
    expect(result['count'], 2);
    expect(result['has_more'], isFalse);
    expect((result['entries'] as List).map((entry) => entry['name']), [
      'BoC_Apart/',
      'notes.txt',
    ]);
    expect((result['entries'] as List).map((entry) => entry['ordinal']), [
      1,
      2,
    ]);
    expect((result['entries'] as List).first['is_directory'], isTrue);
    expect((result['entries'] as List).last['size'], 123);
    verify(
      () => manager.requestDirectoryListing('/samples/Multisamples'),
    ).called(1);
  });

  test('returns an exact next call for a bounded page', () async {
    when(() => manager.requestDirectoryListing('/samples')).thenAnswer(
      (_) async => DirectoryListing(
        entries: List.generate(
          3,
          (index) => DirectoryEntry(
            name: 'Folder $index/',
            attributes: 0x10,
            date: 0,
            time: 0,
            size: 0,
          ),
        ),
      ),
    );

    final result =
        jsonDecode(
              await tools.listSdDirectory({
                'path': '/samples',
                'offset': 0,
                'limit': 2,
              }),
            )
            as Map<String, dynamic>;

    expect(result['has_more'], isTrue);
    expect(result['next'], {
      'tool': 'list_sd_directory',
      'arguments': {'path': '/samples', 'offset': 2, 'limit': 2},
    });
  });

  test('rejects relative paths without touching the device', () async {
    final result =
        jsonDecode(await tools.listSdDirectory({'path': 'samples'}))
            as Map<String, dynamic>;

    expect(result['success'], isFalse);
    expect(result['error'], contains('absolute'));
    verifyNever(() => manager.requestDirectoryListing(any()));
  });

  test('registers the read-only SD directory tool', () {
    final entry = ToolRegistry(cubit).findByName('list_sd_directory');

    expect(entry, isNotNull);
    expect(entry!.description, contains('device response order'));
    expect(entry.inputSchema['required'], ['path']);
  });
}
