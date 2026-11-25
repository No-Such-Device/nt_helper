import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:nt_helper/ui/widgets/algorithm_visual_style_container.dart';

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
    int selectedIndex = 0,
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
          body: Container(
            width: 250,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(width: 1)),
            ),
            child: AlgorithmListView(
              slots: slots,
              selectedIndex: selectedIndex,
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('styled slots render the NT overview style without an icon', (
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

    expect(find.byIcon(Icons.format_shapes_rounded), findsNothing);
    expect(find.byKey(const ValueKey('algorithm-style-0')), findsNothing);

    final betaPreview = tester.widget<AlgorithmVisualStyleContainer>(
      find.byKey(const ValueKey('algorithm-style-preview-1')),
    );
    expect(betaPreview.style, const AlgorithmVisualStyle(lineAbove: true));
    expect(
      tester.getSemantics(find.text('Beta')).label,
      contains('line above'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('unstyled slots keep their ordinary list presentation', (
    tester,
  ) async {
    final slots = [_slot(0, 'Alpha')];

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.17.9', offline: false),
    );
    final preview = tester.widget<AlgorithmVisualStyleContainer>(
      find.byKey(const ValueKey('algorithm-style-preview-0')),
    );
    expect(preview.style.hasCustomStyle, isFalse);
    expect(find.byIcon(Icons.format_shapes_rounded), findsNothing);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('algorithm-style-preview-0')),
        matching: find.byKey(const ValueKey('algorithm-style-box')),
      ),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.border, isNotNull);
  });

  testWidgets('sidebar boxes keep their left edge and a 12px divider gap', (
    tester,
  ) async {
    final slots = [_slot(0, 'Alpha'), _slot(1, 'Beta')];
    final initialBoxRects = <Rect>[];

    for (final selectedIndex in [0, 1]) {
      await tester.pumpWidget(
        buildWidget(
          slots: slots,
          firmwareVersion: '1.18.0',
          offline: false,
          selectedIndex: selectedIndex,
        ),
      );

      final list = find.byType(ListView);
      final listRect = tester.getRect(list);
      expect(listRect.width, 249);
      expect(
        tester.widget<ListView>(list).padding,
        const EdgeInsets.fromLTRB(4, 8, 0, 8),
      );
      for (var index = 0; index < slots.length; index++) {
        final preview = find.byKey(ValueKey('algorithm-style-preview-$index'));
        final boxRect = tester.getRect(
          find.descendant(
            of: preview,
            matching: find.byKey(const ValueKey('algorithm-style-box')),
          ),
        );
        final tile = tester.widget<ListTile>(
          find.descendant(of: preview, matching: find.byType(ListTile)),
        );
        expect(tile.selected, index == selectedIndex);
        expect(tile.contentPadding, const EdgeInsets.symmetric(horizontal: 12));
        expect(boxRect.left - listRect.left, 8);
        expect(listRect.right - boxRect.right, 12);
        expect(
          tester.getRect(find.text(slots[index].algorithm.name)).left,
          boxRect.left + 12,
        );
        if (selectedIndex == 0) {
          initialBoxRects.add(boxRect);
        } else {
          expect(boxRect, initialBoxRects[index]);
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('offline style is simulated in the desktop algorithm list', (
    tester,
  ) async {
    final slots = [
      _slot(
        0,
        'Alpha',
        visualStyle: const AlgorithmVisualStyle(
          leftIndent: 3,
          rightIndent: 2,
          lineBelow: true,
          bracket: AlgorithmVisualBracket.close,
        ),
      ),
    ];

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.15.0', offline: true),
    );

    final preview = tester.widget<AlgorithmVisualStyleContainer>(
      find.byKey(const ValueKey('algorithm-style-preview-0')),
    );
    expect(preview.style.leftIndent, 3);
    expect(preview.style.rightIndent, 2);
    expect(preview.style.lineBelow, isTrue);
    expect(preview.style.bracket, AlgorithmVisualBracket.close);
    final indentPadding = tester.widget<Padding>(
      find.descendant(
        of: find.byKey(const ValueKey('algorithm-style-preview-0')),
        matching: find.byKey(const ValueKey('algorithm-style-indent')),
      ),
    );
    expect(indentPadding.padding, const EdgeInsets.only(left: 15, right: 10));
    final containerRect = tester.getRect(
      find.byKey(const ValueKey('algorithm-style-preview-0')),
    );
    final algorithmBoxRect = tester.getRect(find.byType(ListTile));
    expect(algorithmBoxRect.left - containerRect.left, 15);
    expect(containerRect.right - algorithmBoxRect.right, 18);
    expect(find.byIcon(Icons.format_shapes_rounded), findsNothing);
  });

  testWidgets('adjacent bracket rows share an edge for a continuous line', (
    tester,
  ) async {
    final slots = [
      _slot(
        0,
        'Open',
        visualStyle: const AlgorithmVisualStyle(
          bracket: AlgorithmVisualBracket.open,
        ),
      ),
      _slot(
        1,
        'Renamed line',
        guid: 'pywt',
        visualStyle: const AlgorithmVisualStyle(
          bracket: AlgorithmVisualBracket.line,
        ),
      ),
      _slot(
        2,
        'Close',
        visualStyle: const AlgorithmVisualStyle(
          bracket: AlgorithmVisualBracket.close,
        ),
      ),
    ];

    await tester.pumpWidget(
      buildWidget(slots: slots, firmwareVersion: '1.18.0', offline: false),
    );

    final openRect = tester.getRect(
      find.byKey(const ValueKey('algorithm-style-preview-0')),
    );
    final lineRect = tester.getRect(
      find.byKey(const ValueKey('algorithm-style-preview-1')),
    );
    final closeRect = tester.getRect(
      find.byKey(const ValueKey('algorithm-style-preview-2')),
    );

    expect(find.text('Poly Wavetable'), findsOneWidget);
    expect(openRect.bottom, lineRect.top);
    expect(lineRect.bottom, closeRect.top);
  });
}

Slot _slot(
  int index,
  String name, {
  String? guid,
  AlgorithmVisualStyle? visualStyle,
}) => Slot(
  algorithm: Algorithm(
    algorithmIndex: index,
    guid: guid ?? 'guid-$index',
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
