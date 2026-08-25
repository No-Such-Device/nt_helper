import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/file_parameter_editor.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: '$name/', attributes: 0x10, date: 0, time: 0, size: 0);

DirectoryEntry _file(String name, {int size = 128}) =>
    DirectoryEntry(name: name, attributes: 0x20, date: 0, time: 0, size: size);

void main() {
  late _MockDistingCubit cubit;
  late _MockDistingMidiManager manager;
  late Map<String, DirectoryListing> sampleTree;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.17.0'));
  });

  setUp(() {
    cubit = _MockDistingCubit();
    manager = _MockDistingMidiManager();
    when(() => cubit.state).thenReturn(DistingStateInitial());
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.disting()).thenReturn(manager);
    when(() => cubit.refreshSlot(any())).thenAnswer((_) async {});
    sampleTree = _chimeraSampleTree();
    _stubChimeraSampleTree(manager, sampleTree);
  });

  testWidgets('Chimera folder picker uses recursive NT sample folder values', (
    tester,
  ) async {
    final writtenValues = <int>[];

    await _pumpEditor(
      tester,
      cubit: cubit,
      slot: _chimeraSlot(),
      parameterNumber: 0,
      onValueChanged: writtenValues.add,
    );

    expect(find.text('Breaks/Lion'), findsOneWidget);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drums/Beef'));
    await tester.pumpAndSettle();

    expect(writtenValues.single, 0);
  });

  testWidgets(
    'NT folder values follow device-response breadth-first catalogue order',
    (tester) async {
      final writtenValues = <int>[];

      await _pumpEditor(
        tester,
        cubit: cubit,
        slot: _chimeraSlot(lionFolderValue: 1),
        parameterNumber: 0,
        onValueChanged: writtenValues.add,
      );

      expect(find.text('Breaks/Lion'), findsOneWidget);

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breaks/Lion').last);
      await tester.pumpAndSettle();

      expect(writtenValues.single, 1);
    },
  );

  testWidgets(
    'exact Folder and Sample pair follows the same recursive catalogue',
    (tester) async {
      await _pumpEditors(
        tester,
        cubit: cubit,
        slot: _capicolaSlot(),
        parameterNumbers: const [0, 1],
      );

      expect(find.text('Breaks/Lion'), findsOneWidget);
      expect(find.text('lion-a'), findsOneWidget);
    },
  );

  testWidgets('NT folder string blocks a mismatched reconstructed catalogue', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      cubit: cubit,
      slot: _capicolaSlot(folderString: 'Multisamples/K_HMU_Soft'),
      parameterNumber: 0,
    );

    expect(find.text('Multisamples/K_HMU_Soft'), findsOneWidget);

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Folder catalogue order does not match the NT at value 1. '
        'Refresh to retry.',
      ),
      findsWidgets,
    );
    expect(find.text('Breaks/Lion'), findsNothing);
  });

  testWidgets('Chimera editors share one recursive sample directory scan', (
    tester,
  ) async {
    final slot = _chimeraSlot();

    await _pumpEditors(
      tester,
      cubit: cubit,
      slot: slot,
      parameterNumbers: const [0, 1],
    );

    verify(() => manager.requestDirectoryListing('/samples')).called(1);
  });

  testWidgets('Chimera sample browser can refresh its cached directory tree', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      cubit: cubit,
      slot: _chimeraSlot(),
      parameterNumber: 0,
    );

    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh'), findsNothing);

    sampleTree['/samples'] = DirectoryListing(
      entries: [_dir('Breaks'), _dir('Fresh')],
    );
    sampleTree['/samples/Fresh'] = DirectoryListing(entries: [_dir('Nested')]);
    sampleTree['/samples/Fresh/Nested'] = DirectoryListing(
      entries: [_file('new.wav')],
    );

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Fresh/Nested'), findsOneWidget);
    verify(() => cubit.refreshSlot(0)).called(1);
    verify(() => manager.requestDirectoryListing('/samples')).called(2);
    verify(() => manager.requestDirectoryListing('/samples/Breaks')).called(2);
  });

  testWidgets(
    'Chimera Goat sample loads its corresponding folder and writes zero-based file values',
    (tester) async {
      final writtenValues = <int>[];

      await _pumpEditor(
        tester,
        cubit: cubit,
        slot: _chimeraSlot(),
        parameterNumber: 3,
        onValueChanged: writtenValues.add,
      );

      expect(find.text('goat-a'), findsOneWidget);
      expect(find.text('lion-a'), findsNothing);

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(find.text('goat-a'), findsWidgets);
      expect(find.text('goat-b'), findsOneWidget);
      expect(find.text('lion-a'), findsNothing);

      await tester.tap(find.text('goat-b'));
      await tester.pumpAndSettle();

      expect(writtenValues.single, 1);
    },
  );

  testWidgets(
    'Chimera Beef sample maps None to zero and the first file to one',
    (tester) async {
      final writtenValues = <int>[];

      await _pumpEditor(
        tester,
        cubit: cubit,
        slot: _chimeraSlot(),
        parameterNumber: 5,
        onValueChanged: writtenValues.add,
      );

      expect(find.text('None'), findsOneWidget);
      expect(find.text('kick-a'), findsNothing);

      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();

      expect(find.text('kick-a'), findsOneWidget);
      expect(find.text('kick-b'), findsOneWidget);

      await tester.tap(find.text('kick-a'));
      await tester.pumpAndSettle();

      expect(writtenValues.single, 1);
    },
  );
}

Map<String, DirectoryListing> _chimeraSampleTree() {
  return <String, DirectoryListing>{
    '/samples': DirectoryListing(entries: [_dir('Drums'), _dir('Breaks')]),
    '/samples/Breaks': DirectoryListing(entries: [_dir('Lion'), _dir('Goat')]),
    '/samples/Breaks/Goat': DirectoryListing(
      entries: [_file('goat-b.wav'), _file('goat-a.wav')],
    ),
    '/samples/Breaks/Lion': DirectoryListing(
      entries: [_file('lion-b.wav'), _file('lion-a.wav')],
    ),
    '/samples/Drums': DirectoryListing(entries: [_dir('Beef')]),
    '/samples/Drums/Beef': DirectoryListing(
      entries: [_file('kick-b.wav'), _file('kick-a.wav')],
    ),
  };
}

void _stubChimeraSampleTree(
  _MockDistingMidiManager manager,
  Map<String, DirectoryListing> listings,
) {
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

Future<void> _pumpEditors(
  WidgetTester tester, {
  required DistingCubit cubit,
  required Slot slot,
  required List<int> parameterNumbers,
}) async {
  final editors = parameterNumbers.map((parameterNumber) {
    final editor = ParameterEditorRegistry.findEditorFor(
      slot: slot,
      parameterInfo: slot.parameters[parameterNumber],
      parameterNumber: parameterNumber,
      currentValue: slot.values[parameterNumber].value,
      onValueChanged: (_) {},
    );
    expect(editor, isA<FileParameterEditor>());
    return editor!;
  }).toList();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: SizedBox(width: 520, child: Column(children: editors)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Slot _chimeraSlot({
  int lionFolderValue = 1,
  int lionSampleValue = 0,
  int goatFolderValue = 2,
  int goatSampleValue = 0,
  int beefFolderValue = 0,
  int kickSampleValue = 0,
}) {
  final parameterValues = [
    lionFolderValue,
    lionSampleValue,
    goatFolderValue,
    goatSampleValue,
    beefFolderValue,
    kickSampleValue,
  ];

  return Slot(
    algorithm: Algorithm(algorithmIndex: 0, guid: 'Chim', name: 'Chimera'),
    routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(algorithmIndex: 0, pages: []),
    parameters: [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 2,
        defaultValue: 0,
        unit: ParameterUnits.modernHasStrings,
        name: 'Lion folder',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 1,
        min: 0,
        max: 1,
        defaultValue: 0,
        unit: ParameterUnits.modernConfirm,
        name: 'Lion sample',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 2,
        min: 0,
        max: 2,
        defaultValue: 0,
        unit: ParameterUnits.modernHasStrings,
        name: 'Goat folder',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 3,
        min: 0,
        max: 1,
        defaultValue: 0,
        unit: ParameterUnits.modernConfirm,
        name: 'Goat sample',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 4,
        min: 0,
        max: 2,
        defaultValue: 0,
        unit: ParameterUnits.modernHasStrings,
        name: 'Beef folder',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 5,
        min: 0,
        max: 2,
        defaultValue: 0,
        unit: ParameterUnits.modernConfirm,
        name: 'Kick sample',
        powerOfTen: 0,
      ),
    ],
    values: List.generate(
      parameterValues.length,
      (index) => ParameterValue(
        algorithmIndex: 0,
        parameterNumber: index,
        value: parameterValues[index],
      ),
    ),
    enums: List.generate(
      parameterValues.length,
      (index) => ParameterEnumStrings(
        algorithmIndex: 0,
        parameterNumber: index,
        values: const [],
      ),
    ),
    mappings: List.generate(
      parameterValues.length,
      (index) => Mapping(
        algorithmIndex: 0,
        parameterNumber: index,
        packedMappingData: PackedMappingData.filler(),
      ),
    ),
    valueStrings: List.generate(
      parameterValues.length,
      (index) => ParameterValueString(
        algorithmIndex: 0,
        parameterNumber: index,
        value: '',
      ),
    ),
  );
}

Slot _capicolaSlot({String? folderString}) {
  return Slot(
    algorithm: Algorithm(algorithmIndex: 0, guid: 'ThCa', name: 'Capicola'),
    routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(algorithmIndex: 0, pages: []),
    parameters: [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 2,
        defaultValue: 0,
        unit: ParameterUnits.modernHasStrings,
        name: 'Folder',
        powerOfTen: 0,
      ),
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 1,
        min: 0,
        max: 1,
        defaultValue: 0,
        unit: ParameterUnits.modernConfirm,
        name: 'Sample',
        powerOfTen: 0,
      ),
    ],
    values: [
      ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
      ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 0),
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
      folderString == null
          ? ParameterValueString.filler()
          : ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: folderString,
            ),
      ParameterValueString.filler(),
    ],
  );
}
