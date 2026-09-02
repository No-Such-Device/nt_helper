import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/clipboard_selectable_tab.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

Slot _slot(int index, String guid, String name) => Slot(
  algorithm: Algorithm(algorithmIndex: index, guid: guid, name: name),
  routing: RoutingInfo.filler(),
  pages: ParameterPages(algorithmIndex: index, pages: const []),
  parameters: const [],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

void main() {
  group('SynchronizedScreen algorithm clipboard', () {
    late MockDistingCubit mockCubit;
    late MockDistingMidiManager mockMidiManager;
    late MockPlatformInteractionService mockPlatformService;
    late AppDatabase database;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      mockCubit = MockDistingCubit();
      mockMidiManager = MockDistingMidiManager();
      mockPlatformService = MockPlatformInteractionService();
      database = AppDatabase.forTesting(NativeDatabase.memory());
      await AlgorithmMetadataService().initialize(database);
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(guid: 'G1', name: 'Alpha', numSpecifications: 0),
        AlgorithmEntry(guid: 'G2', name: 'Beta', numSpecifications: 0),
        AlgorithmEntry(guid: 'G3', name: 'Gamma', numSpecifications: 0),
      ]);
      when(() => mockCubit.checkpoints).thenReturn([]);
      when(
        () => mockCubit.cpuUsageStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.database).thenReturn(database);
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(false);
      McpServerService.initialize(distingCubit: mockCubit);
    });

    tearDown(() async {
      await database.close();
    });

    Widget buildWidget(
      List<Slot> slots, {
      String firmwareVersion = '1.10.0',
      bool offline = true,
    }) {
      final state = DistingStateSynchronized(
        disting: mockMidiManager,
        distingVersion: firmwareVersion,
        firmwareVersion: FirmwareVersion(firmwareVersion),
        presetName: 'Test Preset',
        algorithms: const [],
        slots: slots,
        unitStrings: const [],
        offline: offline,
      );
      when(() => mockCubit.state).thenReturn(state);
      when(() => mockCubit.stream).thenAnswer((_) => Stream.value(state));
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: SynchronizedScreen(
            distingVersion: firmwareVersion,
            firmwareVersion: FirmwareVersion(firmwareVersion),
            slots: slots,
            algorithms: const [],
            units: const [],
            presetName: 'Test Preset',
            screenshot: Uint8List(0),
            loading: false,
            platformService: mockPlatformService,
          ),
        ),
      );
    }

    testWidgets('top toolbar opens decoration editor for selected algorithm', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(
          [_slot(0, 'G1', 'Alpha')],
          firmwareVersion: '1.18.0',
          offline: false,
        ),
      );

      final button = find.byKey(const ValueKey('toolbar-algorithm-decoration'));
      expect(button, findsOneWidget);
      expect(find.byTooltip('Decorate selected algorithm'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('Algorithm Decoration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('top toolbar exposes offline decoration preview', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget(
          [_slot(0, 'G1', 'Alpha')],
          firmwareVersion: '1.15.0',
          offline: true,
        ),
      );

      final button = find.byKey(const ValueKey('toolbar-algorithm-decoration'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.textContaining('Offline preview'), findsOneWidget);
    });

    testWidgets('slot tabs expose shift-click hint via semantics on desktop', (
      tester,
    ) async {
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(false);
      await tester.pumpWidget(
        buildWidget([_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')]),
      );

      final node = tester.getSemantics(find.text('Alpha'));
      expect(node.hint, contains('Shift-click'));
    });

    testWidgets('mobile slot tabs omit shift-click hint', (tester) async {
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(true);
      await tester.pumpWidget(buildWidget([_slot(0, 'G1', 'Alpha')]));

      final node = tester.getSemantics(find.text('Alpha'));
      expect(node.hint, isNot(contains('Shift-click')));
    });

    testWidgets('Mod+C with no selection shows a guidance snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget([_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')]),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Select slot tabs with shift-click'),
        findsOneWidget,
      );
      expect(await database.presetsDao.clipboardSlotCount(), 0);
    });

    testWidgets('Mod+V with empty clipboard shows empty-clipboard snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget([_slot(0, 'G1', 'Alpha')]));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Algorithm clipboard is empty'),
        findsOneWidget,
      );
    });

    testWidgets('shift-click toggles slots into the selection (top tabs)', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget([
          _slot(0, 'G1', 'Alpha'),
          _slot(1, 'G2', 'Beta'),
          _slot(2, 'G3', 'Gamma'),
        ]),
      );

      bool isTabSelected(String label) {
        final element = tester.element(find.text(label));
        final state = element
            .findAncestorStateOfType<ClipboardSelectableTabState>();
        return state?.selected ?? false;
      }

      // None clipboard-selected initially.
      expect(isTabSelected('Alpha'), isFalse);
      expect(isTabSelected('Gamma'), isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.tap(find.text('Gamma'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(isTabSelected('Alpha'), isTrue);
      expect(isTabSelected('Gamma'), isTrue);
      expect(isTabSelected('Beta'), isFalse);

      // Shift-click Alpha again to deselect it (toggle off).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(isTabSelected('Alpha'), isFalse);
      expect(isTabSelected('Gamma'), isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('Escape clears shift-click selection without copying', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget([_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')]),
      );

      bool isTabSelected(String label) {
        final element = tester.element(find.text(label));
        final state = element
            .findAncestorStateOfType<ClipboardSelectableTabState>();
        return state?.selected ?? false;
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(isTabSelected('Alpha'), isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(isTabSelected('Alpha'), isFalse);
      expect(await database.presetsDao.clipboardSlotCount(), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('shift-click then Mod+C copies the selected slot to the DB', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildWidget([_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')]),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      final clipboard = await database.presetsDao.getClipboardTemplate();
      expect(clipboard, isNotNull);
      expect(clipboard!.slots.single.slot.algorithmGuid, 'G2');
    });
  });

  group('SynchronizedScreen algorithm clipboard (side list, wide screen)', () {
    late MockDistingCubit mockCubit;
    late MockDistingMidiManager mockMidiManager;
    late MockPlatformInteractionService mockPlatformService;
    late AppDatabase database;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      mockCubit = MockDistingCubit();
      mockMidiManager = MockDistingMidiManager();
      mockPlatformService = MockPlatformInteractionService();
      database = AppDatabase.forTesting(NativeDatabase.memory());
      await AlgorithmMetadataService().initialize(database);
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(guid: 'G1', name: 'Alpha', numSpecifications: 0),
        AlgorithmEntry(guid: 'G2', name: 'Beta', numSpecifications: 0),
        AlgorithmEntry(guid: 'G3', name: 'Gamma', numSpecifications: 0),
      ]);
      when(() => mockCubit.checkpoints).thenReturn([]);
      when(
        () => mockCubit.cpuUsageStream,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockCubit.database).thenReturn(database);
      when(() => mockPlatformService.isMobilePlatform()).thenReturn(false);
      McpServerService.initialize(distingCubit: mockCubit);
    });

    tearDown(() async {
      await database.close();
    });

    Widget buildWidget(List<Slot> slots) {
      final state = DistingStateSynchronized(
        disting: mockMidiManager,
        distingVersion: '1.10.0',
        firmwareVersion: FirmwareVersion('1.10.0'),
        presetName: 'Test Preset',
        algorithms: const [],
        slots: slots,
        unitStrings: const [],
        offline: true,
      );
      when(() => mockCubit.state).thenReturn(state);
      when(() => mockCubit.stream).thenAnswer((_) => Stream.value(state));
      return MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: mockCubit,
          child: SynchronizedScreen(
            distingVersion: '1.10.0',
            firmwareVersion: FirmwareVersion('1.10.0'),
            slots: slots,
            algorithms: const [],
            units: const [],
            presetName: 'Test Preset',
            screenshot: Uint8List(0),
            loading: false,
            platformService: mockPlatformService,
          ),
        ),
      );
    }

    testWidgets('shift-click side-list tiles multi-selects them', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildWidget([
          _slot(0, 'G1', 'Alpha'),
          _slot(1, 'G2', 'Beta'),
          _slot(2, 'G3', 'Gamma'),
        ]),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await tester.tap(find.text('Gamma'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      // Both tiles now report selected via the public ClipboardSelectableTab
      // state (no decoration sniffing).
      bool isTileSelected(String label) {
        final element = tester.element(find.text(label));
        final state = element
            .findAncestorStateOfType<ClipboardSelectableTabState>();
        return state?.selected ?? false;
      }

      expect(isTileSelected('Beta'), isTrue);
      expect(isTileSelected('Gamma'), isTrue);
      expect(isTileSelected('Alpha'), isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('side-list shift-click then Mod+C copies the selection', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildWidget([_slot(0, 'G1', 'Alpha'), _slot(1, 'G2', 'Beta')]),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      final clipboard = await database.presetsDao.getClipboardTemplate();
      expect(clipboard, isNotNull);
      expect(clipboard!.slots.single.slot.algorithmGuid, 'G2');
    });
  });
}
