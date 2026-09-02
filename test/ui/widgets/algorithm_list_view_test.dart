import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/widgets/algorithm_list_view.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() => database.close());

  Widget buildWidget({
    required List<Slot> slots,
    required String firmwareVersion,
    required bool offline,
  }) {
    final cubit = _MockDistingCubit();
    final state = DistingState.synchronized(
      disting: _MockDistingMidiManager(),
      distingVersion: firmwareVersion,
      firmwareVersion: FirmwareVersion(firmwareVersion),
      presetName: 'Test',
      algorithms: const [],
      slots: slots,
      unitStrings: const [],
      offline: offline,
    );
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

    return MaterialApp(
      home: BlocProvider<DistingCubit>.value(
        value: cubit,
        child: Scaffold(
          body: SizedBox(
            width: 280,
            child: AlgorithmListView(
              slots: slots,
              selectedIndex: 0,
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('each firmware 1.18 slot has a direct decoration control', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final slots = [
      _slot(0, 'Alpha'),
      _slot(
        1,
        'Beta',
        visualStyle: const AlgorithmVisualStyle(lineAbove: true),
      ),
    ];

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.18.0beta', offline: false),
    );

    final alphaButton = find.byKey(const ValueKey('algorithm-decoration-0'));
    final betaButton = find.byKey(const ValueKey('algorithm-decoration-1'));
    expect(alphaButton, findsOneWidget);
    expect(betaButton, findsOneWidget);
    expect(find.byTooltip('Decorate slot 1: Alpha'), findsOneWidget);
    expect(find.bySemanticsLabel('Decorate Alpha'), findsOneWidget);

    final betaIcon = tester.widget<Icon>(
      find.descendant(
        of: betaButton,
        matching: find.byIcon(Icons.format_shapes_rounded),
      ),
    );
    expect(
      betaIcon.color,
      Theme.of(tester.element(betaButton)).colorScheme.primary,
    );

    await tester.tap(
      find.descendant(of: alphaButton, matching: find.byType(IconButton)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Algorithm Decoration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('decoration controls require online firmware 1.18 or newer', (
    tester,
  ) async {
    final slots = [_slot(0, 'Alpha')];

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.17.9', offline: false),
    );
    expect(find.byKey(const ValueKey('algorithm-decoration-0')), findsNothing);

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.18.0', offline: true),
    );
    expect(find.byKey(const ValueKey('algorithm-decoration-0')), findsNothing);
  });
}

Slot _slot(int index, String name, {AlgorithmVisualStyle? visualStyle}) => Slot(
  algorithm: Algorithm(
    algorithmIndex: index,
    guid: 'guid-$index',
    name: name,
    visualStyle: visualStyle,
  ),
  routing: RoutingInfo.filler(),
  pages: ParameterPages(algorithmIndex: index, pages: const []),
  parameters: const [],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
