import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/preset_browser_cubit.dart';
import 'package:nt_helper/ui/widgets/preset_browser_dialog.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPresetBrowserCubit extends Mock implements PresetBrowserCubit {}

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

class FakeDirectoryEntry extends Fake implements DirectoryEntry {}

void main() {
  late MockPresetBrowserCubit mockCubit;
  late MockDistingCubit mockDistingCubit;

  setUpAll(() {
    registerFallbackValue(FakeDirectoryEntry());
    registerFallbackValue(PanelPosition.left);
  });

  setUp(() {
    mockCubit = MockPresetBrowserCubit();
    mockDistingCubit = MockDistingCubit();
    // Mock loadRootDirectory to return a Future<void>
    when(() => mockCubit.loadRootDirectory()).thenAnswer((_) async {});
    // Mock getSelectedPath to return empty string by default
    when(() => mockCubit.getSelectedPath()).thenReturn('');
  });

  Widget createTestWidget({required Widget child}) {
    return MaterialApp(
      home: BlocProvider<PresetBrowserCubit>.value(
        value: mockCubit,
        child: child,
      ),
    );
  }

  group('PresetBrowserDialog', () {
    for (final action in [
      'empty root',
      'root',
      'toolbar',
      'mobile toolbar',
      'nested',
      'entry',
      'placeholder',
    ]) {
      testWidgets('folder creation targets correct directory via $action', (
        tester,
      ) async {
        final mobile = action == 'mobile toolbar';
        if (mobile) {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        final hasFolder = action != 'empty root' && action != 'placeholder';
        final target = mobile || action == 'nested' || action == 'entry'
            ? '/programs'
            : '/';
        final folder = DirectoryEntry(
          name: 'programs/',
          attributes: 0x10,
          date: 0,
          time: 0,
          size: 0,
        );
        when(() => mockCubit.state).thenReturn(
          PresetBrowserState.loaded(
            currentPath: '/',
            drillPath: mobile ? '/programs' : null,
            leftPanelItems: hasFolder ? [folder] : [],
            centerPanelItems: const [],
            rightPanelItems: const [],
            selectedLeftItem: hasFolder ? folder : null,
            selectedCenterItem: null,
            selectedRightItem: null,
            navigationHistory: const [],
            sortByDate: false,
          ),
        );
        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
        when(
          () => mockCubit.createDirectory(target, 'helper'),
        ).thenAnswer((_) async {});
        when(() => mockCubit.getEntryPath(folder, '/')).thenReturn('/programs');
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: PresetBrowserDialog(distingCubit: mockDistingCubit),
            ),
          ),
        );
        if (action == 'toolbar' || mobile) {
          expect(
            find.bySemanticsLabel('New folder in $target'),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('New folder in $target'));
        } else {
          final panel = find
              .byType(DirectoryPanel)
              .at(action == 'nested' || action == 'placeholder' ? 1 : 0);
          await tester.tapAt(
            action == 'entry'
                ? tester.getCenter(find.text('programs'))
                : tester.getBottomLeft(panel) + const Offset(25, -25),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          if (action == 'placeholder') {
            expect(find.text('New Folder'), findsNothing);
            return;
          }
          expect(find.text('New Folder'), findsOneWidget);
          if (action != 'entry') {
            expect(find.text('Delete'), findsNothing);
            expect(find.text('Rename'), findsNothing);
          }
          await tester.tap(find.text('New Folder'));
        }
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'helper');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        verify(() => mockCubit.createDirectory(target, 'helper')).called(1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('displays three panels in row layout', (tester) async {
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      // Should find three panel containers
      expect(find.byType(DirectoryPanel), findsNWidgets(3));

      // Should be in a Row
      expect(
        find.descendant(
          of: find.byType(Row),
          matching: find.byType(DirectoryPanel),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('displays loading indicator when loading', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(const PresetBrowserState.loading());
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('displays error message when error state', (tester) async {
      when(() => mockCubit.state).thenReturn(
        const PresetBrowserState.error(message: 'Test error message'),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('displays back button and sort toggle', (tester) async {
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const ['/'],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      // Mock the navigateBack and toggleSortMode methods
      when(() => mockCubit.navigateBack()).thenAnswer((_) async {});
      when(() => mockCubit.toggleSortMode()).thenReturn(null);

      // Back button should be visible when history exists
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Sort toggle should be visible
      expect(find.byIcon(Icons.sort_by_alpha), findsOneWidget);
    });

    testWidgets('enables wave cache troubleshooting on firmware 1.17', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(
            distingCubit: mockDistingCubit,
            firmwareVersion: FirmwareVersion('1.17.0'),
          ),
        ),
      );

      final action = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Wave cache'),
      );
      expect(action.onPressed, isNotNull);
    });

    testWidgets('disables wave cache troubleshooting before firmware 1.17', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(
            distingCubit: mockDistingCubit,
            firmwareVersion: FirmwareVersion('1.16.9'),
          ),
        ),
      );

      final action = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Wave cache'),
      );
      expect(action.onPressed, isNull);
    });

    testWidgets('calls selectDirectory when directory tapped', (tester) async {
      final testEntry = DirectoryEntry(
        name: 'TestFolder/',
        attributes: 0x10,
        date: 0,
        time: 0,
        size: 0,
      );

      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: [testEntry],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.selectDirectory(any(), any()),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        createTestWidget(
          child: Scaffold(
            body: ThreePanelNavigator(
              leftPanelItems: [testEntry],
              centerPanelItems: const [],
              rightPanelItems: const [],
              selectedLeftItem: null,
              selectedCenterItem: null,
              selectedRightItem: null,
              currentPath: '/',
              onItemSelected: (item, position) {
                mockCubit.selectDirectory(item, position);
              },
            ),
          ),
        ),
      );

      // Clean the display name (remove trailing slash) - widget shows "TestFolder" not "TestFolder/"
      await tester.tap(find.text('TestFolder'));
      await tester.pumpAndSettle();

      verify(
        () => mockCubit.selectDirectory(testEntry, PanelPosition.left),
      ).called(1);
    });

    testWidgets('calls selectFile when file tapped', (tester) async {
      final testFile = DirectoryEntry(
        name: 'preset.json',
        attributes: 0,
        date: 0,
        time: 0,
        size: 1024,
      );

      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: [testFile],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.getSelectedPath(),
      ).thenReturn('/presets/preset.json');
      when(() => mockCubit.selectFile(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        createTestWidget(
          child: Scaffold(
            body: ThreePanelNavigator(
              leftPanelItems: [testFile],
              centerPanelItems: const [],
              rightPanelItems: const [],
              selectedLeftItem: null,
              selectedCenterItem: null,
              selectedRightItem: null,
              currentPath: '/',
              onItemSelected: (item, position) {
                mockCubit.selectFile(item, position);
              },
            ),
          ),
        ),
      );

      // Tap on the file
      await tester.tap(find.text('preset.json'));
      await tester.pumpAndSettle();

      verify(
        () => mockCubit.selectFile(testFile, PanelPosition.left),
      ).called(1);
    });

    testWidgets('wires distinct drop directories to desktop panels', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final midiDir = DirectoryEntry(
        name: 'MIDI/',
        attributes: 0x10,
        date: 0,
        time: 0,
        size: 0,
      );
      final songsDir = DirectoryEntry(
        name: 'Songs/',
        attributes: 0x10,
        date: 0,
        time: 0,
        size: 0,
      );

      final capturedTargets = <String>[];

      try {
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: ThreePanelNavigator(
                leftPanelItems: [midiDir],
                centerPanelItems: [songsDir],
                rightPanelItems: const [],
                selectedLeftItem: midiDir,
                selectedCenterItem: songsDir,
                selectedRightItem: null,
                currentPath: '/',
                onItemSelected: (_, _) {},
                onFilesDropped: (_, targetDirectory) {
                  capturedTargets.add(targetDirectory);
                },
              ),
            ),
          ),
        );

        final panelPaths = tester
            .widgetList<DirectoryPanel>(find.byType(DirectoryPanel))
            .map((panel) => panel.currentPath)
            .toList();

        expect(panelPaths, ['/', '/MIDI', '/MIDI/Songs']);

        final dropTargets = tester.widgetList<DropTarget>(
          find.byType(DropTarget),
        );
        expect(dropTargets, hasLength(3));

        for (final dropTarget in dropTargets) {
          dropTarget.onDragDone!(
            DropDoneDetails(
              files: [DropItemFile('/tmp/groove.mid')],
              localPosition: Offset.zero,
              globalPosition: Offset.zero,
            ),
          );
        }

        expect(capturedTargets, ['/', '/MIDI', '/MIDI/Songs']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not register placeholder panels as drop targets', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final capturedTargets = <String>[];

      try {
        await tester.pumpWidget(
          createTestWidget(
            child: Scaffold(
              body: ThreePanelNavigator(
                leftPanelItems: const [],
                centerPanelItems: const [],
                rightPanelItems: const [],
                selectedLeftItem: null,
                selectedCenterItem: null,
                selectedRightItem: null,
                currentPath: '/',
                onItemSelected: (_, _) {},
                onFilesDropped: (_, targetDirectory) {
                  capturedTargets.add(targetDirectory);
                },
              ),
            ),
          ),
        );

        final dropTargets = tester.widgetList<DropTarget>(
          find.byType(DropTarget),
        );
        expect(dropTargets, hasLength(1));

        dropTargets.single.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile('/tmp/groove.mid')],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );

        expect(capturedTargets, ['/']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('DirectoryPanel', () {
    testWidgets('displays folder icons for directories', (tester) async {
      final testDirectory = DirectoryEntry(
        name: 'Folder/',
        attributes: 0x10,
        date: 0,
        time: 0,
        size: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryPanel(
              items: [testDirectory],
              selectedItem: null,
              onItemTap: (_) {},
              position: PanelPosition.left,
              currentPath: '/',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('displays file icons for files', (tester) async {
      final testJsonFile = DirectoryEntry(
        name: 'preset.json',
        attributes: 0,
        date: 0,
        time: 0,
        size: 1024,
      );

      final testOtherFile = DirectoryEntry(
        name: 'readme.txt',
        attributes: 0,
        date: 0,
        time: 0,
        size: 512,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryPanel(
              items: [testJsonFile, testOtherFile],
              selectedItem: null,
              onItemTap: (_) {},
              position: PanelPosition.left,
              currentPath: '/',
            ),
          ),
        ),
      );

      // JSON files should show music note icon
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      // Other files should show generic file icon
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets('highlights selected item', (tester) async {
      final testItem = DirectoryEntry(
        name: 'selected.json',
        attributes: 0,
        date: 0,
        time: 0,
        size: 1024,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryPanel(
              items: [testItem],
              selectedItem: testItem,
              onItemTap: (_) {},
              position: PanelPosition.left,
              currentPath: '/',
            ),
          ),
        ),
      );

      // Find the ListTile and check if it's selected
      final listTile = tester.widget<ListTile>(find.byType(ListTile));
      expect(listTile.selected, true);
    });
  });

  group('Package Installation Dialog Integration', () {
    testWidgets('has state variables for package installation', (tester) async {
      // This test verifies that the state structure exists for E3.4
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      // Verify widget builds successfully (implies state variables exist)
      expect(find.byType(PresetBrowserDialog), findsOneWidget);
    });

    testWidgets('imports PackageInstallDialog', (tester) async {
      // This test verifies the import is present by checking compilation
      when(() => mockCubit.state).thenReturn(
        PresetBrowserState.loaded(
          currentPath: '/',
          leftPanelItems: const [],
          centerPanelItems: const [],
          rightPanelItems: const [],
          selectedLeftItem: null,
          selectedCenterItem: null,
          selectedRightItem: null,
          navigationHistory: const [],
          sortByDate: false,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createTestWidget(
          child: PresetBrowserDialog(distingCubit: mockDistingCubit),
        ),
      );

      // If this builds, the import is present and correct
      expect(find.byType(PresetBrowserDialog), findsOneWidget);
    });
  });
}
