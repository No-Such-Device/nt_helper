import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/file_parameter_editor.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: '$name/', attributes: 0x10, date: 0, time: 0, size: 0);

DirectoryEntry _plainFolderCandidate(String name) =>
    DirectoryEntry(name: name, attributes: 0, date: 0, time: 0, size: 0);

DirectoryEntry _file(String name, {int size = 128}) =>
    DirectoryEntry(name: name, attributes: 0x20, date: 0, time: 0, size: size);

void main() {
  late _MockDistingCubit cubit;
  late _MockDistingMidiManager manager;

  setUp(() {
    cubit = _MockDistingCubit();
    manager = _MockDistingMidiManager();
    when(() => cubit.state).thenReturn(DistingStateInitial());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.disting()).thenReturn(manager);
    _stubSampleTree(manager);
  });

  group('FileParameterEditor Poly Multisample folder/sample helpers', () {
    testWidgets(
      'pymu Folder value 0 resolves to first alphabetic playable folder',
      (tester) async {
        final slot = _polySlot(guid: 'pymu', folderMin: 0, folderValue: 0);

        await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 0);

        expect(find.text('ZTop'), findsOneWidget);
        expect(find.text('Multisample/BoC Alpha'), findsNothing);
      },
    );

    testWidgets(
      'pyms Folder value 1 resolves to first alphabetic playable folder',
      (tester) async {
        final slot = _polySlot(guid: 'pyms', folderMin: 1, folderValue: 1);

        await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 0);

        expect(find.text('ZTop'), findsOneWidget);
      },
    );

    testWidgets(
      'raw SD response order is alphabetized before folder values are assigned',
      (tester) async {
        when(() => manager.requestDirectoryListing('/samples')).thenAnswer(
          (_) async => DirectoryListing(
            entries: [
              _dir('TSSD_Free_Wav'),
              _dir('12VoltPunch_Wav_Free'),
              _dir('!LABS Soft Pno - PedOn'),
              _dir('Blofeld_Drums_Samples'),
            ],
          ),
        );
        for (final folder in const [
          'TSSD_Free_Wav',
          '12VoltPunch_Wav_Free',
          '!LABS Soft Pno - PedOn',
          'Blofeld_Drums_Samples',
        ]) {
          when(
            () => manager.requestDirectoryListing('/samples/$folder'),
          ).thenAnswer(
            (_) async => DirectoryListing(entries: [_file('sample.wav')]),
          );
        }
        final slot = _polySlot(
          guid: 'pymu',
          folderMin: 0,
          folderValue: 0,
          folderMax: 3,
        );

        await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 0);

        expect(find.text('!LABS Soft Pno - PedOn'), findsOneWidget);
        expect(find.text('TSSD_Free_Wav'), findsNothing);
      },
    );

    testWidgets(
      'nested playable folders follow NT breadth-first order and write matching value',
      (tester) async {
        final writtenValues = <int>[];
        final slot = _polySlot(guid: 'pymu', folderMin: 0, folderValue: 2);

        await _pumpEditor(
          tester,
          cubit: cubit,
          slot: slot,
          parameterNumber: 0,
          onValueChanged: writtenValues.add,
        );

        expect(find.text('Multisample/BoC Beta'), findsOneWidget);

        await tester.tap(find.text('Browse'));
        await tester.pumpAndSettle();

        expect(find.text('Multisample'), findsNothing);
        expect(find.text('Multisample/BoC Alpha'), findsWidgets);
        expect(find.text('Multisample/BoC Beta'), findsWidgets);
        expect(find.text('.Hidden'), findsNothing);

        await tester.tap(find.text('Multisample/BoC Beta').last);
        await tester.pumpAndSettle();

        expect(writtenValues.single, 2);
      },
    );

    testWidgets(
      'folder enumeration blocks a partial catalogue when a child listing fails',
      (tester) async {
        when(
          () => manager.requestDirectoryListing('/samples/Multisample'),
        ).thenThrow(Exception('directory listing failed'));
        final slot = _polySlot(guid: 'pymu', folderMin: 0, folderValue: 0);

        await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 0);

        expect(find.text('Folder 1'), findsOneWidget);

        await tester.tap(find.text('Browse'));
        await tester.pumpAndSettle();

        expect(find.text('Multisample'), findsNothing);
        expect(find.text('ZTop'), findsNothing);
        expect(
          find.text(
            'Folder catalogue incomplete: an NT directory listing failed. Refresh to retry.',
          ),
          findsWidgets,
        );
      },
    );

    testWidgets('plain Multisamples folder candidate is enumerated', (
      tester,
    ) async {
      when(() => manager.requestDirectoryListing('/samples')).thenAnswer(
        (_) async => DirectoryListing(
          entries: [
            _dir('ZTop'),
            _plainFolderCandidate('Multisamples'),
            _dir('Multisample'),
          ],
        ),
      );
      when(
        () => manager.requestDirectoryListing('/samples/Multisamples'),
      ).thenAnswer(
        (_) async => DirectoryListing(entries: [_file('Playable.wav')]),
      );
      final slot = _polySlot(
        guid: 'pymu',
        folderMin: 0,
        folderValue: 0,
        folderMax: 4,
      );

      await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 0);

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(find.text('Multisamples'), findsWidgets);
    });

    testWidgets('Sample value 0 displays Multisample instead of first file', (
      tester,
    ) async {
      final slot = _polySlot(guid: 'pymu', folderMin: 0, folderValue: 2);

      await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 1);

      expect(find.text('Multisample'), findsOneWidget);
      expect(find.text('Alpha_C3'), findsNothing);
    });

    testWidgets('negative Sample value displays Multisample defensively', (
      tester,
    ) async {
      final slot = _polySlot(
        guid: 'pymu',
        folderMin: 0,
        folderValue: 1,
        sampleValue: -1,
      );

      await _pumpEditor(tester, cubit: cubit, slot: slot, parameterNumber: 1);

      expect(find.text('Multisample'), findsOneWidget);
    });

    testWidgets('first real sample in selected nested folder writes value 1', (
      tester,
    ) async {
      final writtenValues = <int>[];
      final slot = _polySlot(guid: 'pymu', folderMin: 0, folderValue: 1);

      await _pumpEditor(
        tester,
        cubit: cubit,
        slot: slot,
        parameterNumber: 1,
        onValueChanged: writtenValues.add,
      );

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(find.text('Multisample'), findsWidgets);
      expect(find.text('Alpha_C3'), findsOneWidget);
      expect(find.text('Beta_C3'), findsOneWidget);

      await tester.tap(find.text('Alpha_C3'));
      await tester.pumpAndSettle();

      expect(writtenValues.single, 1);
    });
  });
}

void _stubSampleTree(_MockDistingMidiManager manager) {
  final listings = <String, DirectoryListing>{
    '/samples': DirectoryListing(
      entries: [_dir('ZTop'), _dir('Multisample'), _dir('.Hidden')],
    ),
    '/samples/Multisample': DirectoryListing(
      entries: [_dir('BoC Beta'), _dir('BoC Alpha'), _dir('.Trash')],
    ),
    '/samples/Multisample/BoC Alpha': DirectoryListing(
      entries: [
        _file('Beta_C3.wav'),
        _file('Alpha_C3.wav'),
        _file('.DS_Store'),
      ],
    ),
    '/samples/Multisample/BoC Beta': DirectoryListing(
      entries: [_file('Gamma_C3.wav')],
    ),
    '/samples/ZTop': DirectoryListing(entries: [_file('Top.wav')]),
  };

  when(() => manager.requestDirectoryListing(any())).thenAnswer((invocation) {
    final path = invocation.positionalArguments.single as String;
    return Future.value(listings[path] ?? DirectoryListing(entries: const []));
  });
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required DistingCubit cubit,
  required Slot slot,
  required int parameterNumber,
  ValueChanged<int>? onValueChanged,
}) async {
  final editor = ParameterEditorRegistry.findEditorFor(
    slot: slot,
    parameterInfo: slot.parameters[parameterNumber],
    parameterNumber: parameterNumber,
    currentValue: slot.values[parameterNumber].value,
    onValueChanged: onValueChanged ?? (_) {},
  );
  expect(editor, isA<FileParameterEditor>());

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: SizedBox(width: 520, child: editor),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Slot _polySlot({
  required String guid,
  required int folderMin,
  required int folderValue,
  int? folderMax,
  int sampleValue = 0,
}) {
  final algorithmName = guid == 'pyms'
      ? 'Poly Multisample (legacy)'
      : 'Poly Multisample';
  return Slot(
    algorithm: Algorithm(algorithmIndex: 0, guid: guid, name: algorithmName),
    routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(algorithmIndex: 0, pages: []),
    parameters: [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: folderMin,
        max: folderMax ?? folderMin + 3,
        defaultValue: folderMin,
        unit: ParameterUnits.modernHasStrings,
        name: 'Folder',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 1,
        min: -1,
        max: 100,
        defaultValue: 0,
        unit: ParameterUnits.modernHasStrings,
        name: 'Sample',
        powerOfTen: 0,
      ),
    ],
    values: [
      ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: folderValue),
      ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: sampleValue),
    ],
    enums: [ParameterEnumStrings.filler(), ParameterEnumStrings.filler()],
    mappings: [
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler(),
      ),
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 1,
        packedMappingData: PackedMappingData.filler(),
      ),
    ],
    valueStrings: [
      ParameterValueString.filler(),
      ParameterValueString.filler(),
    ],
  );
}
