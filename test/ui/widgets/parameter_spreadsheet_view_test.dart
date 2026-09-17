import 'dart:ui' show Tristate;

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
import 'package:nt_helper/ui/widgets/algorithm_controller/lua_algorithm_controller_view.dart';
import 'package:nt_helper/ui/widgets/parameter_spreadsheet_view.dart';
import 'package:drift/native.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  late MockDistingCubit cubit;
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() async {
    await database.close();
  });

  setUp(() {
    cubit = MockDistingCubit();
    when(() => cubit.checkpoints).thenReturn([]);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.cpuUsageStream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.supportsMemoryUsage).thenReturn(false);
    when(
      () => cubit.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((_) async {});
    when(() => cubit.scheduleParameterRefresh(any())).thenReturn(null);
    McpServerService.initialize(distingCubit: cubit);
  });

  Widget wrapSheet(Slot slot) {
    final state = _state(slot);
    when(() => cubit.state).thenReturn(state);
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ).copyWith(tertiary: Colors.orange),
      ),
      home: BlocProvider<DistingCubit>.value(
        value: cubit,
        child: Scaffold(
          body: ParameterSpreadsheetView(
            slot: slot,
            slotIndex: 0,
            units: const ['Hz', 'BPM', '%'],
            pages: slot.pages,
          ),
        ),
      ),
    );
  }

  group('ParameterSpreadsheetView', () {
    testWidgets('shows only numeric editable enabled parameters', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSheet(_mixedSlot()));
      await tester.pumpAndSettle();

      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Level'), findsOneWidget);
      expect(find.text('Mode'), findsNothing);
      expect(find.text('Enabled'), findsNothing);
      expect(find.text('Root Note'), findsNothing);
      expect(find.text('Tempo'), findsNothing);
      expect(find.text('Disabled Gain'), findsNothing);
    });

    testWidgets('omits the host-owned Bypass row', (tester) async {
      final slot = _slot([
        _parameter(0, 'Bypass', value: 0, min: 0, max: 1),
        _parameter(1, 'Level', value: 20),
      ]);

      await tester.pumpWidget(wrapSheet(slot));
      await tester.pumpAndSettle();

      expect(find.text('Bypass'), findsNothing);
      expect(find.text('Level'), findsOneWidget);
    });

    testWidgets('typing a number starts editing and replaces the cell text', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '5');
    });

    testWidgets('invalid replacement characters do not start editing', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Enter commits and selects the next cell', (tester) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('10 Hz'));
      await tester.enterText(find.byType(TextField), '15');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 15,
          userIsChangingTheValue: false,
        ),
      ).called(1);
      verify(() => cubit.scheduleParameterRefresh(0)).called(1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '20');
    });

    testWidgets('Tab and Shift+Tab commit and move with wrapping', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('20'));
      await tester.enterText(find.byType(TextField), '25');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 1,
          value: 25,
          userIsChangingTheValue: false,
        ),
      ).called(1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final firstEdit = tester.widget<TextField>(find.byType(TextField));
      expect(firstEdit.controller!.text, '10');

      await tester.enterText(find.byType(TextField), '11');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 11,
          userIsChangingTheValue: false,
        ),
      ).called(1);
    });

    testWidgets('arrow keys commit and move while editing', (tester) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('10 Hz'));
      await tester.enterText(find.byType(TextField), '12');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      verify(
        () => cubit.updateParameterValue(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 12,
          userIsChangingTheValue: false,
        ),
      ).called(1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '20');
    });

    testWidgets('invalid numeric text stays editing with an accessible error', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(wrapSheet(_signedSlot()));
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('0'));
      await tester.enterText(find.byType(TextField), '-');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verifyNever(
        () => cubit.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Invalid value'), findsOneWidget);

      final node = tester.getSemantics(find.byType(TextField));
      final data = node.getSemanticsData();
      expect(data.value, contains('Invalid value'));
      expect(data.hint, contains('Invalid value'));

      semanticsHandle.dispose();
    });

    testWidgets('Escape cancels without submitting or navigating', (
      tester,
    ) async {
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('10 Hz'));
      await tester.enterText(find.byType(TextField), '99');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      verifyNever(
        () => cubit.updateParameterValue(
          algorithmIndex: any(named: 'algorithmIndex'),
          parameterNumber: any(named: 'parameterNumber'),
          value: any(named: 'value'),
          userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
        ),
      );
      expect(find.byType(TextField), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '10');
    });

    testWidgets('value cells expose accessible labels and values', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.text('10 Hz'));
      final data = node.getSemanticsData();
      expect(data.label, contains('Edit Frequency value'));
      expect(data.value, contains('10 Hz'));
      expect(data.flagsCollection.isTextField, isTrue);
      expect(data.flagsCollection.isSelected == Tristate.isTrue, isTrue);

      semanticsHandle.dispose();
    });

    testWidgets('semantic tap starts editing the selected value cell', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(wrapSheet(_simpleSlot()));
      await tester.pumpAndSettle();

      tester.semantics.tap(
        find.semantics.byLabel(RegExp('Edit Frequency value')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      semanticsHandle.dispose();
    });

    testWidgets('keyboard movement keeps offscreen selected rows visible', (
      tester,
    ) async {
      final slot = _manyNumericSlot();
      final state = _state(slot);
      when(() => cubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: Scaffold(
              body: SizedBox(
                height: 120,
                child: ParameterSpreadsheetView(
                  slot: slot,
                  slotIndex: 0,
                  units: const ['Hz', 'BPM', '%'],
                  pages: slot.pages,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 8; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }

      expect(find.text('Parameter 8'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, '8');
    });

    testWidgets('digit entry does not invoke ancestor digit shortcuts', (
      tester,
    ) async {
      var shortcutInvocations = 0;
      final slot = _simpleSlot();
      final state = _state(slot);
      when(() => cubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.digit2): _DigitIntent(),
            },
            child: Actions(
              actions: {
                _DigitIntent: CallbackAction<_DigitIntent>(
                  onInvoke: (_) {
                    shortcutInvocations++;
                    return null;
                  },
                ),
              },
              child: BlocProvider<DistingCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: ParameterSpreadsheetView(
                    slot: slot,
                    slotIndex: 0,
                    units: const ['Hz', 'BPM', '%'],
                    pages: slot.pages,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('10 Hz'));
      expect(find.byType(TextField), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();

      expect(shortcutInvocations, 0);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('global shortcuts do not fire while a value is being edited', (
      tester,
    ) async {
      var shortcutInvocations = 0;
      final slot = _simpleSlot();
      final state = _state(slot);
      when(() => cubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _DigitIntent(),
            },
            child: Actions(
              actions: {
                _DigitIntent: CallbackAction<_DigitIntent>(
                  onInvoke: (_) {
                    shortcutInvocations++;
                    return null;
                  },
                ),
              },
              child: BlocProvider<DistingCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: ParameterSpreadsheetView(
                    slot: slot,
                    slotIndex: 0,
                    units: const ['Hz', 'BPM', '%'],
                    pages: slot.pages,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _doubleTap(tester, find.text('10 Hz'));
      expect(find.byType(TextField), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(shortcutInvocations, 0);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('global shortcuts still fire when a value cell is selected', (
      tester,
    ) async {
      var shortcutInvocations = 0;
      final slot = _simpleSlot();
      final state = _state(slot);
      when(() => cubit.state).thenReturn(state);

      await tester.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _DigitIntent(),
            },
            child: Actions(
              actions: {
                _DigitIntent: CallbackAction<_DigitIntent>(
                  onInvoke: (_) {
                    shortcutInvocations++;
                    return null;
                  },
                ),
              },
              child: BlocProvider<DistingCubit>.value(
                value: cubit,
                child: Scaffold(
                  body: ParameterSpreadsheetView(
                    slot: slot,
                    slotIndex: 0,
                    units: const ['Hz', 'BPM', '%'],
                    pages: slot.pages,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(shortcutInvocations, 1);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('SynchronizedScreen spreadsheet toggle', () {
    testWidgets('secondary action bar toggle switches the current slot body', (
      tester,
    ) async {
      final platformService = MockPlatformInteractionService();
      final slot = _simpleSlot();
      final state = _state(slot);
      when(() => platformService.isMobilePlatform()).thenReturn(true);
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: SynchronizedScreen(
              slots: [slot],
              algorithms: [
                AlgorithmInfo(
                  algorithmIndex: 0,
                  name: 'Test Algorithm',
                  guid: 'test',
                  specifications: const [],
                ),
              ],
              units: const ['Hz', 'BPM', '%'],
              presetName: 'Test Preset',
              distingVersion: '1.16.0',
              firmwareVersion: FirmwareVersion('1.16.0'),
              screenshot: Uint8List(0),
              loading: false,
              platformService: platformService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ParameterSpreadsheetView), findsNothing);
      expect(find.byTooltip('Spreadsheet parameter editor'), findsOneWidget);
      expect(find.byTooltip('Collapse all'), findsOneWidget);

      final spreadsheetCenter = tester.getCenter(
        find.byTooltip('Spreadsheet parameter editor'),
      );
      final collapseCenter = tester.getCenter(find.byTooltip('Collapse all'));
      expect(spreadsheetCenter.dx, lessThan(collapseCenter.dx));
      expect((spreadsheetCenter.dy - collapseCenter.dy).abs(), lessThan(2));

      await tester.tap(find.byTooltip('Spreadsheet parameter editor'));
      await tester.pumpAndSettle();

      expect(find.byType(ParameterSpreadsheetView), findsOneWidget);
      expect(find.byTooltip('Standard parameter editor'), findsOneWidget);

      final semanticsHandle = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Show spreadsheet parameter editor'),
      );
      final data = node.getSemanticsData();
      expect(data.label, contains('Show spreadsheet parameter editor'));
      expect(data.flagsCollection.isSelected == Tristate.isTrue, isTrue);
      semanticsHandle.dispose();
    });

    testWidgets('Lua section state and hotkeys survive Routing rebuild', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final platformService = MockPlatformInteractionService();
      final slot = _euclideanSlot();
      final state = _state(slot);
      when(() => platformService.isMobilePlatform()).thenReturn(false);
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: SynchronizedScreen(
              slots: [slot],
              algorithms: state.algorithms,
              units: const ['Hz', 'BPM', '%'],
              presetName: 'Test Preset',
              distingVersion: '1.17.0',
              firmwareVersion: FirmwareVersion('1.17.0'),
              screenshot: Uint8List(0),
              loading: false,
              platformService: platformService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('slot-editor-mode-controller')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LuaAlgorithmControllerView), findsOneWidget);

      List<ExpansionTile> controllerSections() {
        return tester
            .widgetList<ExpansionTile>(
              find.descendant(
                of: find.byType(LuaAlgorithmControllerView),
                matching: find.byType(ExpansionTile),
              ),
            )
            .toList();
      }

      expect(controllerSections(), hasLength(2));
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        everyElement(isTrue),
      );

      await tester.tap(find.byTooltip('Collapse all'));
      await tester.pumpAndSettle();
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        everyElement(isFalse),
      );

      await tester.tap(find.text('Channel 2'));
      await tester.pumpAndSettle();
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isFalse, isTrue],
      );

      await tester.tap(find.byTooltip('Routing mode'));
      await tester.pumpAndSettle();
      expect(find.byType(LuaAlgorithmControllerView), findsOneWidget);
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isFalse, isTrue],
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('slot-editor-mode-controller')),
            )
            .isSelected,
        isTrue,
      );

      await tester.tap(find.byTooltip('Routing mode'));
      await tester.pumpAndSettle();
      expect(find.byType(LuaAlgorithmControllerView), findsOneWidget);
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isFalse, isTrue],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isTrue, isFalse],
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pumpAndSettle();
      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isTrue, isFalse],
      );
    });

    testWidgets('digit 6 opens Quad Mixer Channel 4 in controller mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final platformService = MockPlatformInteractionService();
      final slot = _quadMixerSlot();
      final state = _state(slot);
      when(() => platformService.isMobilePlatform()).thenReturn(false);
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: SynchronizedScreen(
              slots: [slot],
              algorithms: state.algorithms,
              units: const ['Hz', 'BPM', '%'],
              presetName: 'Test Preset',
              distingVersion: '1.17.0',
              firmwareVersion: FirmwareVersion('1.17.0'),
              screenshot: Uint8List(0),
              loading: false,
              platformService: platformService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('slot-editor-mode-controller')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse all'));
      await tester.pumpAndSettle();

      List<ExpansionTile> controllerSections() {
        return tester
            .widgetList<ExpansionTile>(
              find.descendant(
                of: find.byType(LuaAlgorithmControllerView),
                matching: find.byType(ExpansionTile),
              ),
            )
            .toList();
      }

      expect(
        controllerSections().map((section) => section.title),
        hasLength(6),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pumpAndSettle();

      expect(
        controllerSections().map((section) => section.controller!.isExpanded),
        [isFalse, isFalse, isFalse, isFalse, isFalse, isTrue],
      );
    });
  });
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

DistingStateSynchronized _state(Slot slot) {
  return DistingStateSynchronized(
    disting: MockDistingMidiManager(),
    distingVersion: '1.16.0',
    firmwareVersion: FirmwareVersion('1.16.0'),
    presetName: 'Test Preset',
    algorithms: [
      AlgorithmInfo(
        algorithmIndex: slot.algorithm.algorithmIndex,
        name: slot.algorithm.name,
        guid: slot.algorithm.guid,
        specifications: const [],
      ),
    ],
    slots: [slot],
    unitStrings: const ['Hz', 'BPM', '%'],
  );
}

Slot _simpleSlot() {
  return _slot([
    _parameter(0, 'Frequency', value: 10, unit: 1),
    _parameter(1, 'Level', value: 20),
  ]);
}

Slot _euclideanSlot({int channelCount = 2}) {
  return _slot(
    [
      _parameter(
        0,
        'Bypass',
        value: 0,
        min: 0,
        max: 1,
        defaultValue: 0,
        enumValues: const ['Off', 'On'],
      ),
      for (var channel = 1; channel <= channelCount; channel++) ...[
        _parameter(
          (channel - 1) * 4 + 1,
          '$channel:Enable',
          value: 1,
          min: 0,
          max: 1,
          defaultValue: 0,
          enumValues: const ['Off', 'On'],
        ),
        _parameter(
          (channel - 1) * 4 + 2,
          '$channel:Steps',
          value: channel == 1 ? 16 : 12,
          min: 1,
          max: 32,
          defaultValue: 16,
        ),
        _parameter(
          (channel - 1) * 4 + 3,
          '$channel:Pulses',
          value: channel == 1 ? 4 : 5,
          min: 1,
          max: 32,
          defaultValue: 4,
        ),
        _parameter(
          (channel - 1) * 4 + 4,
          '$channel:Rotation',
          value: channel == 1 ? 0 : 2,
          min: 0,
          max: 32,
        ),
      ],
    ],
    algorithm: Algorithm(
      algorithmIndex: 0,
      guid: 'eucp',
      name: 'Euclidean Patterns',
      specifications: [channelCount],
    ),
    pages: [
      ParameterPage(
        name: 'Patterns',
        parameters: [
          for (var number = 1; number <= channelCount * 4; number++) number,
        ],
      ),
      ParameterPage(name: 'Algorithm', parameters: const [0]),
    ],
  );
}

Slot _quadMixerSlot() {
  final fixtures = <_ParameterFixture>[
    _parameter(
      0,
      'Bypass',
      value: 0,
      min: 0,
      max: 1,
      defaultValue: 0,
      enumValues: const ['Off', 'On'],
    ),
    _parameter(1, 'Overall gain', value: 100, min: 0, max: 200),
  ];
  final channelPages = <ParameterPage>[];
  for (var channel = 1; channel <= 4; channel++) {
    final firstNumber = 2 + (channel - 1) * 4;
    fixtures.addAll([
      _parameter(firstNumber, '$channel:Gain', value: 100, min: 0, max: 200),
      _parameter(
        firstNumber + 1,
        '$channel:Coordinates',
        value: 0,
        min: 0,
        max: 1,
        enumValues: const ['Cartesian', 'Polar'],
      ),
      _parameter(
        firstNumber + 2,
        '$channel:X',
        value: 0,
        min: -100,
        max: 100,
      ),
      _parameter(
        firstNumber + 3,
        '$channel:Y',
        value: 0,
        min: -100,
        max: 100,
      ),
    ]);
    channelPages.add(
      ParameterPage(
        name: 'Channel $channel',
        parameters: [
          firstNumber,
          firstNumber + 1,
          firstNumber + 2,
          firstNumber + 3,
        ],
      ),
    );
  }

  return _slot(
    fixtures,
    algorithm: Algorithm(
      algorithmIndex: 0,
      guid: 'quad',
      name: 'Quadraphonic Mixer',
      specifications: const [4],
    ),
    pages: [
      ParameterPage(name: 'Output mix', parameters: const [1]),
      ...channelPages,
      ParameterPage(name: 'Algorithm', parameters: const [0]),
    ],
  );
}

Slot _signedSlot() {
  return _slot([
    _parameter(0, 'Pan', value: 0, min: -100, max: 100),
    _parameter(1, 'Level', value: 20),
  ]);
}

Slot _mixedSlot() {
  return _slot([
    _parameter(0, 'Frequency', value: 10, unit: 1),
    _parameter(1, 'Mode', value: 0, enumValues: const ['A', 'B']),
    _parameter(2, 'Enabled', value: 1, enumValues: const ['Off', 'On']),
    _parameter(3, 'Root Note', value: 60),
    _parameter(4, 'Tempo', value: 120, unit: 14),
    _parameter(5, 'Disabled Gain', value: 50, disabled: true),
    _parameter(6, 'Level', value: 20),
  ]);
}

Slot _manyNumericSlot() {
  return _slot([
    for (var i = 0; i < 12; i++) _parameter(i, 'Parameter $i', value: i),
  ]);
}

Slot _slot(
  List<_ParameterFixture> fixtures, {
  List<ParameterPage>? pages,
  Algorithm? algorithm,
}) {
  return Slot(
    algorithm:
        algorithm ?? Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
    routing: RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: 0,
      pages:
          pages ??
          [
            ParameterPage(
              name: 'Main',
              parameters: [for (final fixture in fixtures) fixture.number],
            ),
          ],
    ),
    parameters: [
      for (final fixture in fixtures)
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: fixture.number,
          min: fixture.min,
          max: fixture.max,
          defaultValue: fixture.defaultValue,
          unit: fixture.unit,
          name: fixture.name,
          powerOfTen: fixture.powerOfTen,
        ),
    ],
    values: [
      for (final fixture in fixtures)
        ParameterValue(
          algorithmIndex: 0,
          parameterNumber: fixture.number,
          value: fixture.value,
          isDisabled: fixture.disabled,
        ),
    ],
    enums: [
      for (final fixture in fixtures)
        fixture.enumValues == null
            ? ParameterEnumStrings.filler()
            : ParameterEnumStrings(
                algorithmIndex: 0,
                parameterNumber: fixture.number,
                values: fixture.enumValues!,
              ),
    ],
    mappings: [for (final _ in fixtures) Mapping.filler()],
    valueStrings: [for (final _ in fixtures) ParameterValueString.filler()],
  );
}

_ParameterFixture _parameter(
  int number,
  String name, {
  required int value,
  int min = 0,
  int max = 100,
  int defaultValue = 0,
  int unit = 0,
  int powerOfTen = 0,
  bool disabled = false,
  List<String>? enumValues,
}) {
  return _ParameterFixture(
    number: number,
    name: name,
    value: value,
    min: min,
    max: max,
    defaultValue: defaultValue,
    unit: unit,
    powerOfTen: powerOfTen,
    disabled: disabled,
    enumValues: enumValues,
  );
}

class _ParameterFixture {
  final int number;
  final String name;
  final int value;
  final int min;
  final int max;
  final int defaultValue;
  final int unit;
  final int powerOfTen;
  final bool disabled;
  final List<String>? enumValues;

  const _ParameterFixture({
    required this.number,
    required this.name,
    required this.value,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.unit,
    required this.powerOfTen,
    required this.disabled,
    this.enumValues,
  });
}

class _DigitIntent extends Intent {
  const _DigitIntent();
}
