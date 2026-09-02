import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/slot_editor_action_bar.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(const AlgorithmVisualStyle());
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() => database.close());

  testWidgets(
    'Reset Outputs ignores output-mode parameters when building bus choices',
    (tester) async {
      final profile = DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!;
      final slot = _slotWithOutputAndMode();
      final cubit = _MockDistingCubit();
      final state = DistingState.synchronized(
        disting: _MockDistingMidiManager(),
        distingVersion: '1.20',
        firmwareVersion: FirmwareVersion('1.20'),
        deviceIoProfile: profile,
        presetName: 'Test',
        algorithms: const [],
        slots: [slot],
        unitStrings: const [],
      );
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: Scaffold(
              body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset Outputs'));
      await tester.pumpAndSettle();

      final field = tester.widget<BusSelectionField>(
        find.byType(BusSelectionField),
      );
      expect(field.model.choices.map((choice) => choice.value), profile.buses);
    },
  );

  testWidgets('hides overview styling before firmware 1.18', (tester) async {
    final slot = _slotWithOutputAndMode();
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.17.9',
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Overview Style'), findsNothing);
  });

  testWidgets('edits firmware 1.18 overview styling from the slot menu', (
    tester,
  ) async {
    const initialStyle = AlgorithmVisualStyle(
      leftIndent: 2,
      rightIndent: 4,
      lineAbove: true,
      bracket: AlgorithmVisualBracket.line,
    );
    final baseSlot = _slotWithOutputAndMode();
    final slot = baseSlot.copyWith(
      algorithm: baseSlot.algorithm.copyWith(visualStyle: initialStyle),
    );
    final cubit = _MockDistingCubit();
    when(() => cubit.state).thenReturn(
      _synchronizedState(
        slot: slot,
        manager: _MockDistingMidiManager(),
        firmwareVersion: '1.18.0beta',
      ),
    );
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(
      () => cubit.setAlgorithmVisualStyle(any(), any()),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SlotEditorActionBar(slot: slot, sectionsCollapsed: false),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Overview Style'));
    await tester.pumpAndSettle();

    expect(find.text('Algorithm Overview Style'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('algorithm-style-left-indent')),
          )
          .initialValue,
      2,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('algorithm-style-line-above')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('algorithm-style-line-below')));
    await tester.tap(find.byKey(const ValueKey('algorithm-style-save')));
    await tester.pumpAndSettle();

    verify(
      () => cubit.setAlgorithmVisualStyle(
        0,
        const AlgorithmVisualStyle(
          leftIndent: 2,
          rightIndent: 4,
          lineAbove: true,
          lineBelow: true,
          bracket: AlgorithmVisualBracket.line,
        ),
      ),
    ).called(1);
  });
}

DistingStateSynchronized _synchronizedState({
  required Slot slot,
  required IDistingMidiManager manager,
  required String firmwareVersion,
}) {
  return DistingState.synchronized(
        disting: manager,
        distingVersion: firmwareVersion,
        firmwareVersion: FirmwareVersion(firmwareVersion),
        presetName: 'Test',
        algorithms: const [],
        slots: [slot],
        unitStrings: const [],
      )
      as DistingStateSynchronized;
}

Slot _slotWithOutputAndMode() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 12,
      defaultValue: 5,
      unit: 1,
      name: 'Output A',
      powerOfTen: 0,
      ioFlags: 2,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 1,
      defaultValue: 1,
      unit: 1,
      name: 'Output A mode',
      powerOfTen: 0,
      ioFlags: 8,
    ),
  ],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
