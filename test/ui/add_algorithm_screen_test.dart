import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/ui/add_algorithm_screen.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/db/database.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDistingCubit extends Mock implements DistingCubit {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late MockDistingCubit mockCubit;
  late MockDistingMidiManager mockDistingMidi;
  late FirmwareVersion mockFirmwareVersion;
  late AlgorithmInfo mockFactoryAlgorithm;
  late AlgorithmInfo mockUnloadedPlugin;
  late AlgorithmInfo mockLoadedPlugin;
  late AlgorithmInfo mockZeroDefaultAlgorithm;
  late AlgorithmInfo mockBooleanAlgorithm;
  late AlgorithmInfo mockTypeThreeAlgorithm;
  late AppDatabase database;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // Initialize database and AlgorithmMetadataService for tests
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);

    // Register fallback values for mocktail
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(
      AlgorithmInfo(
        algorithmIndex: 0,
        guid: '_fallback',
        name: '_fallback',
        specifications: const [],
      ),
    );
    registerFallbackValue(<int>[]);
  });

  tearDownAll(() async {
    await database.close();
  });

  setUp(() {
    mockCubit = MockDistingCubit();
    mockDistingMidi = MockDistingMidiManager();
    mockFirmwareVersion = FirmwareVersion('1.10.0');

    // Create mock algorithms for testing
    mockFactoryAlgorithm = AlgorithmInfo(
      algorithmIndex: 0,
      guid: 'clck',
      name: 'Clock',
      specifications: const [],
      isLoaded: true, // Factory algorithms are always loaded
    );

    mockUnloadedPlugin = AlgorithmInfo(
      algorithmIndex: 1,
      guid: 'TestPlugin',
      name: 'Test Plugin',
      specifications: const [],
      isPlugin: true,
      isLoaded: false, // Plugin not loaded
    );

    mockLoadedPlugin = AlgorithmInfo(
      algorithmIndex: 2,
      guid: 'TestPlugin',
      name: 'Test Plugin',
      specifications: [
        Specification(
          name: 'Spec 1',
          min: 0,
          max: 10,
          defaultValue: 5,
          type: 0,
        ),
        Specification(
          name: 'Spec 2',
          min: -5,
          max: 5,
          defaultValue: 0,
          type: 0,
        ),
      ],
      isPlugin: true,
      isLoaded: true, // Plugin loaded with specifications
    );

    mockZeroDefaultAlgorithm = AlgorithmInfo(
      algorithmIndex: 3,
      guid: 'samc',
      name: 'Sample Player (Clocked)',
      specifications: [
        Specification(
          name: 'Record time',
          min: 0,
          max: 60,
          defaultValue: 0,
          type: 1,
        ),
      ],
      isLoaded: true,
    );

    mockBooleanAlgorithm = AlgorithmInfo(
      algorithmIndex: 4,
      guid: 'delt',
      name: 'Delay (Tape)',
      specifications: [
        Specification(name: 'Stereo', min: 0, max: 1, defaultValue: 0, type: 2),
      ],
      isLoaded: true,
    );

    mockTypeThreeAlgorithm = AlgorithmInfo(
      algorithmIndex: 5,
      guid: 'tpfz',
      name: 'Typed Numeric',
      specifications: [
        Specification(
          name: 'History',
          min: 1,
          max: 20,
          defaultValue: 4,
          type: 3,
        ),
      ],
      isLoaded: true,
    );
  });

  Widget createTestWidget({bool disableAnimations = false}) {
    return MaterialApp(
      builder: disableAnimations
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : null,
      home: BlocProvider<DistingCubit>.value(
        value: mockCubit,
        child: const AddAlgorithmScreen(),
      ),
    );
  }

  Widget createRouteTestWidget(ValueChanged<Object?> onResult) {
    return MaterialApp(
      home: BlocProvider<DistingCubit>.value(
        value: mockCubit,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider<DistingCubit>.value(
                        value: mockCubit,
                        child: const AddAlgorithmScreen(),
                      ),
                    ),
                  );
                  onResult(result);
                },
                child: const Text('Open Add Algorithm'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  DistingState synchronizedWith(
    List<AlgorithmInfo> algorithms, {
    int slotCount = 0,
    bool offline = false,
  }) {
    return DistingState.synchronized(
      disting: mockDistingMidi,
      distingVersion: '',
      firmwareVersion: mockFirmwareVersion,
      presetName: 'Test Preset',
      algorithms: algorithms,
      slots: List.generate(
        slotCount,
        (i) => Slot(
          algorithm: Algorithm(
            algorithmIndex: i,
            guid: 'placeholder',
            name: 'Slot $i',
          ),
          routing: RoutingInfo.filler(),
          pages: ParameterPages(algorithmIndex: i, pages: const []),
          parameters: const [],
          values: const [],
          enums: const [],
          mappings: const [],
          valueStrings: const [],
        ),
      ),
      unitStrings: const [],
      inputDevice: null,
      outputDevice: null,
      loading: false,
      offline: offline,
      screenshot: null,
      demo: false,
      videoStream: null,
    );
  }

  group('AddAlgorithmScreen Plugin Loading', () {
    testWidgets('displays Load Plugin button for unloaded plugin', (
      tester,
    ) async {
      // Arrange
      when(() => mockCubit.state).thenReturn(
        DistingState.synchronized(
          disting: mockDistingMidi,
          distingVersion: '',
          firmwareVersion: mockFirmwareVersion,
          presetName: 'Test Preset',
          algorithms: [mockFactoryAlgorithm, mockUnloadedPlugin],
          slots: const [],
          unitStrings: const [],
          inputDevice: null,
          outputDevice: null,
          loading: false,
          offline: false,
          screenshot: null,
          demo: false,
          videoStream: null,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.loadPlugin('TestPlugin'),
      ).thenAnswer((_) async => null);

      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Select the unloaded plugin
      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Load Plugin'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsNothing,
      );

      // Verify button is enabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Load Plugin'),
      );
      expect(button.onPressed, isNotNull);
      verify(() => mockCubit.loadPlugin('TestPlugin')).called(1);
    });

    testWidgets('displays Add Algorithm button for loaded plugin', (
      tester,
    ) async {
      // Arrange
      when(() => mockCubit.state).thenReturn(
        DistingState.synchronized(
          disting: mockDistingMidi,
          distingVersion: '',
          firmwareVersion: mockFirmwareVersion,
          presetName: 'Test Preset',
          algorithms: [mockFactoryAlgorithm, mockLoadedPlugin],
          slots: const [],
          unitStrings: const [],
          inputDevice: null,
          outputDevice: null,
          loading: false,
          offline: false,
          screenshot: null,
          demo: false,
          videoStream: null,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Select the loaded plugin
      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );
      expect(find.text('Load Plugin'), findsNothing);

      // Verify button is enabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('displays Add Algorithm button for factory algorithm', (
      tester,
    ) async {
      // Arrange
      when(() => mockCubit.state).thenReturn(
        DistingState.synchronized(
          disting: mockDistingMidi,
          distingVersion: '',
          firmwareVersion: mockFirmwareVersion,
          presetName: 'Test Preset',
          algorithms: [mockFactoryAlgorithm],
          slots: const [],
          unitStrings: const [],
          inputDevice: null,
          outputDevice: null,
          loading: false,
          offline: false,
          screenshot: null,
          demo: false,
          videoStream: null,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Select the factory algorithm
      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();

      // Assert
      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );
      expect(find.text('Load Plugin'), findsNothing);
    });

    testWidgets('uses in-range zero specification default in dialog', (
      tester,
    ) async {
      when(() => mockCubit.state).thenReturn(
        DistingState.synchronized(
          disting: mockDistingMidi,
          distingVersion: '',
          firmwareVersion: mockFirmwareVersion,
          presetName: 'Test Preset',
          algorithms: [mockZeroDefaultAlgorithm],
          slots: const [],
          unitStrings: const [],
          inputDevice: null,
          outputDevice: null,
          loading: false,
          offline: false,
          screenshot: null,
          demo: false,
          videoStream: null,
        ),
      );
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sample Player (Clocked)'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('samc_spec_0')), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      final specField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('samc_spec_0')),
      );
      expect(specField.controller?.text, '0');
    });

    testWidgets('shows specification dialog after Add Algorithm is pressed', (
      tester,
    ) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('TestPlugin_spec_0')), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      expect(find.text('Configure Test Plugin'), findsOneWidget);
      expect(find.text('2 specifications required'), findsOneWidget);
      expect(find.byKey(const ValueKey('TestPlugin_spec_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('TestPlugin_spec_1')), findsOneWidget);
    });

    testWidgets('Cancel closes specification dialog without popping picker', (
      tester,
    ) async {
      Object? routeResult = 'not-set';
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createRouteTestWidget((result) {
          routeResult = result;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Algorithm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AddAlgorithmScreen), findsOneWidget);
      expect(find.text('Test Plugin'), findsOneWidget);
      expect(routeResult, 'not-set');
    });

    testWidgets('Add returns algorithm and specification values', (
      tester,
    ) async {
      Object? routeResult;
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createRouteTestWidget((result) {
          routeResult = result;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Algorithm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('TestPlugin_spec_0')),
        '7',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      final result = routeResult as Map<String, dynamic>;
      expect(result['algorithm'], mockLoadedPlugin);
      expect(result['specValues'], [7, 0]);
      expect(result['addBypassed'], isFalse);
    });

    testWidgets('boolean specification renders as switch and submits 1', (
      tester,
    ) async {
      Object? routeResult;
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockBooleanAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createRouteTestWidget((result) {
          routeResult = result;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Algorithm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delay (Tape)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      final result = routeResult as Map<String, dynamic>;
      expect(result['specValues'], [1]);
    });

    testWidgets('type 3 specification remains numeric', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockTypeThreeAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Typed Numeric'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(const ValueKey('tpfz_spec_0')), findsOneWidget);
    });

    testWidgets('invalid numeric input blocks Add', (tester) async {
      Object? routeResult = 'not-set';
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createRouteTestWidget((result) {
          routeResult = result;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Algorithm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('TestPlugin_spec_0')),
        '99',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Spec 1 must be between 0 and 10'), findsOneWidget);
      expect(find.text('Configure Test Plugin'), findsOneWidget);
      expect(routeResult, 'not-set');
    });

    testWidgets(
      'offline mode allows cached specification values to be edited',
      (tester) async {
        Object? routeResult;
        when(
          () => mockCubit.state,
        ).thenReturn(synchronizedWith([mockLoadedPlugin], offline: true));
        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

        await tester.pumpWidget(
          createRouteTestWidget((result) {
            routeResult = result;
          }),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Add Algorithm'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Plugin'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
        await tester.pumpAndSettle();

        final specField = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('TestPlugin_spec_0')),
            matching: find.byType(TextField),
          ),
        );
        expect(specField.readOnly, isFalse);

        await tester.enterText(
          find.byKey(const ValueKey('TestPlugin_spec_0')),
          '7',
        );

        await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
        await tester.pumpAndSettle();

        final result = routeResult as Map<String, dynamic>;
        expect(result['specValues'], [7, 0]);
      },
    );

    testWidgets('specification dialog exposes accessible semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockBooleanAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delay (Tape)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Algorithm'));
      await tester.pumpAndSettle();

      final titleNode = tester.getSemantics(
        find.text('Configure Delay (Tape)'),
      );
      expect(titleNode.flagsCollection.isHeader, isTrue);

      final switchTileNode = tester.getSemantics(find.byType(SwitchListTile));
      expect(switchTileNode.label, contains('Stereo'));
      final hasSwitchStateSemantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any(
            (widget) =>
                widget.properties.hint == 'Off sends 0, on sends 1' &&
                widget.properties.toggled == false,
          );
      expect(hasSwitchStateSemantics, isTrue);

      expect(
        tester.getSemantics(find.widgetWithText(TextButton, 'Cancel')).label,
        'Cancel',
      );
      expect(
        tester.getSemantics(find.widgetWithText(ElevatedButton, 'Add')).label,
        'Add',
      );
      semantics.dispose();
    });

    group('Plugin Loading Workflow', () {
      testWidgets('selection automatically loads a plugin', (tester) async {
        // This is the key test for the bug fix

        // Initial state: unloaded plugin
        when(() => mockCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDistingMidi,
            distingVersion: '',
            firmwareVersion: mockFirmwareVersion,
            presetName: 'Test Preset',
            algorithms: [mockUnloadedPlugin],
            slots: const [],
            unitStrings: const [],
            inputDevice: null,
            outputDevice: null,
            loading: false,
            offline: false,
            screenshot: null,
            demo: false,
            videoStream: null,
          ),
        );

        // Mock successful plugin loading
        when(
          () => mockCubit.loadPlugin('TestPlugin'),
        ).thenAnswer((_) async => mockLoadedPlugin);

        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select the unloaded plugin
        await tester.tap(find.text('Test Plugin'));
        await tester.pumpAndSettle();

        // Loading was triggered by selection; no separate button press is needed.
        expect(
          find.widgetWithText(ElevatedButton, 'Add Algorithm'),
          findsOneWidget,
        );
        expect(find.text('Load Plugin'), findsNothing);

        // Verify loadPlugin was called
        verify(() => mockCubit.loadPlugin('TestPlugin')).called(1);
      });

      testWidgets('handles plugin loading failure gracefully', (tester) async {
        // Initial state: unloaded plugin
        when(() => mockCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDistingMidi,
            distingVersion: '',
            firmwareVersion: mockFirmwareVersion,
            presetName: 'Test Preset',
            algorithms: [mockUnloadedPlugin],
            slots: const [],
            unitStrings: const [],
            inputDevice: null,
            outputDevice: null,
            loading: false,
            offline: false,
            screenshot: null,
            demo: false,
            videoStream: null,
          ),
        );

        // Mock failed plugin loading
        when(
          () => mockCubit.loadPlugin('TestPlugin'),
        ).thenAnswer((_) async => null);

        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select the unloaded plugin
        await tester.tap(find.text('Test Plugin'));
        await tester.pumpAndSettle();

        // Assert: Button should still show "Load Plugin" since loading failed
        expect(find.text('Load Plugin'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Add Algorithm'),
          findsNothing,
        );

        // Check for error snackbar
        expect(find.text('Failed to load Test Plugin'), findsOneWidget);

        // Verify loadPlugin was called
        verify(() => mockCubit.loadPlugin('TestPlugin')).called(1);
      });

      testWidgets('shows loading snackbar during plugin load', (tester) async {
        // Initial state: unloaded plugin
        when(() => mockCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDistingMidi,
            distingVersion: '',
            firmwareVersion: mockFirmwareVersion,
            presetName: 'Test Preset',
            algorithms: [mockUnloadedPlugin],
            slots: const [],
            unitStrings: const [],
            inputDevice: null,
            outputDevice: null,
            loading: false,
            offline: false,
            screenshot: null,
            demo: false,
            videoStream: null,
          ),
        );

        // Mock delayed plugin loading
        final completer = Completer<AlgorithmInfo?>();
        when(
          () => mockCubit.loadPlugin('TestPlugin'),
        ).thenAnswer((_) => completer.future);

        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select the unloaded plugin
        await tester.tap(find.text('Test Plugin'));
        await tester.pump(); // Start the automatic async operation

        // Assert: Loading snackbar should be visible
        expect(find.text('Loading plugin Test Plugin...'), findsOneWidget);

        // Complete the loading
        completer.complete(mockLoadedPlugin);
        await tester.pumpAndSettle();

        // Assert: Loading snackbar should be dismissed (no success snackbar shown)
        expect(find.text('Loading plugin Test Plugin...'), findsNothing);

        // Verify loadPlugin was called
        verify(() => mockCubit.loadPlugin('TestPlugin')).called(1);
      });
    });

    group('Plugin Type Detection', () {
      testWidgets('correctly identifies factory algorithms vs plugins', (
        tester,
      ) async {
        when(() => mockCubit.state).thenReturn(
          DistingState.synchronized(
            disting: mockDistingMidi,
            distingVersion: '',
            firmwareVersion: mockFirmwareVersion,
            presetName: 'Test Preset',
            algorithms: [mockFactoryAlgorithm, mockUnloadedPlugin],
            slots: const [],
            unitStrings: const [],
            inputDevice: null,
            outputDevice: null,
            loading: false,
            offline: false,
            screenshot: null,
            demo: false,
            videoStream: null,
          ),
        );
        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
        when(
          () => mockCubit.loadPlugin('TestPlugin'),
        ).thenAnswer((_) async => null);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Factory algorithm (lowercase GUID) should show extension icon for community plugins only
        await tester.tap(find.text('Clock'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(ElevatedButton, 'Add Algorithm'),
          findsOneWidget,
        );

        // Plugin (uppercase GUID) should show load button when unloaded
        await tester.tap(find.text('Test Plugin'));
        await tester.pumpAndSettle();
        expect(find.text('Load Plugin'), findsOneWidget);
      });
    });
  });

  group('AddAlgorithmScreen Stay-open option', () {
    DistingState synchronizedWith(
      List<AlgorithmInfo> algorithms, {
      int slotCount = 0,
    }) {
      return DistingState.synchronized(
        disting: mockDistingMidi,
        distingVersion: '',
        firmwareVersion: mockFirmwareVersion,
        presetName: 'Test Preset',
        algorithms: algorithms,
        slots: List.generate(
          slotCount,
          (i) => Slot(
            algorithm: Algorithm(
              algorithmIndex: i,
              guid: 'placeholder',
              name: 'Slot $i',
            ),
            routing: RoutingInfo.filler(),
            pages: ParameterPages(algorithmIndex: i, pages: const []),
            parameters: const [],
            values: const [],
            enums: const [],
            mappings: const [],
            valueStrings: const [],
          ),
        ),
        unitStrings: const [],
        inputDevice: null,
        outputDevice: null,
        loading: false,
        offline: false,
        screenshot: null,
        demo: false,
        videoStream: null,
      );
    }

    testWidgets('Add Another button appears alongside Add Algorithm '
        'after a loaded algorithm is selected', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // No Add Another button visible before selecting
      expect(find.widgetWithText(ElevatedButton, 'Add Another'), findsNothing);

      // Select algorithm
      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Add Another'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Add Another disables add actions and prevents duplicate submissions '
      'while verification is pending',
      (tester) async {
        final addCompleter = Completer<void>();
        addTearDown(() {
          if (!addCompleter.isCompleted) addCompleter.complete();
        });
        when(
          () => mockCubit.state,
        ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
        when(
          () => mockCubit.onAlgorithmSelected(
            any(),
            any(),
            addBypassed: any(named: 'addBypassed'),
          ),
        ).thenAnswer((_) => addCompleter.future);

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clock'));
        await tester.pumpAndSettle();

        final addAnother = find.widgetWithText(ElevatedButton, 'Add Another');
        await tester.tap(addAnother);
        await tester.tap(addAnother);
        await tester.pump();

        verify(
          () => mockCubit.onAlgorithmSelected(
            any(that: predicate<AlgorithmInfo>((a) => a.guid == 'clck')),
            any(),
            addBypassed: false,
          ),
        ).called(1);
        expect(
          tester
              .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Add Algorithm'),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Adding...'), findsOneWidget);
        final addingButton = find.ancestor(
          of: find.text('Adding...'),
          matching: find.byType(ElevatedButton),
        );
        expect(tester.widget<ElevatedButton>(addingButton).onPressed, isNull);
        expect(
          find.byKey(const ValueKey('add_another_progress_indicator')),
          findsOneWidget,
        );
        final progressSemantics = tester.widget<Semantics>(
          find.byKey(const ValueKey('add_another_progress_semantics')),
        );
        expect(progressSemantics.properties.liveRegion, isTrue);
        expect(progressSemantics.properties.label, 'Adding algorithm');

        addCompleter.complete();
        await tester.pumpAndSettle();

        expect(find.text('Clock added'), findsNothing);
        expect(find.text('Select Algorithm'), findsOneWidget);
      },
    );

    testWidgets('bottom actions use a brief state transition', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const ValueKey('algorithm_action_switcher')),
      );
      expect(switcher.duration, const Duration(milliseconds: 180));
      expect(switcher.reverseDuration, const Duration(milliseconds: 120));

      await tester.tap(find.text('Clock'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('add_algorithm_actions')),
        findsOneWidget,
      );
    });

    testWidgets('bottom actions respect reduced motion', (tester) async {
      final addCompleter = Completer<void>();
      addTearDown(() {
        if (!addCompleter.isCompleted) addCompleter.complete();
      });
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      ).thenAnswer((_) => addCompleter.future);

      await tester.pumpWidget(createTestWidget(disableAnimations: true));
      await tester.pumpAndSettle();

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byKey(const ValueKey('algorithm_action_switcher')),
      );
      expect(switcher.duration, Duration.zero);
      expect(switcher.reverseDuration, Duration.zero);

      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Another'));
      await tester.pump();

      expect(find.text('Adding...'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add_another_progress_indicator')),
        findsNothing,
      );
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

      addCompleter.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Shift changes add button labels while held', (tester) async {
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm Bypassed'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Add Another Bypassed'),
        findsOneWidget,
      );

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(ElevatedButton, 'Add Another'),
        findsOneWidget,
      );
    });

    testWidgets('Add Algorithm returns addBypassed when Shift is held', (
      tester,
    ) async {
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
      Object? routeResult;
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(
        createRouteTestWidget((result) {
          routeResult = result;
        }),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Algorithm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Add Algorithm Bypassed'),
      );
      await tester.pumpAndSettle();

      final result = routeResult as Map<String, dynamic>;
      expect(result['algorithm'], mockFactoryAlgorithm);
      expect(result['specValues'], isEmpty);
      expect(result['addBypassed'], isTrue);
    });

    testWidgets('Add Another adds, clears selection, '
        'and stays open without a success SnackBar', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Another'));
      await tester.pumpAndSettle();

      // Cubit add was invoked exactly once
      verify(
        () => mockCubit.onAlgorithmSelected(
          any(that: predicate<AlgorithmInfo>((a) => a.guid == 'clck')),
          any(),
          addBypassed: false,
        ),
      ).called(1);

      // Selection was cleared (button reverts to disabled "Select Algorithm")
      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsNothing,
      );
      expect(find.text('Select Algorithm'), findsOneWidget);

      // Success feedback does not cover the picker controls.
      expect(find.text('Clock added'), findsNothing);

      // Picker is still open (AppBar title still visible)
      expect(find.text('Add Algorithm'), findsOneWidget);
    });

    testWidgets('Add Another with specs waits for dialog Add', (tester) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Another'));
      await tester.pumpAndSettle();

      verifyNever(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      );
      expect(find.text('Configure Test Plugin'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('TestPlugin_spec_0')),
        '6',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      verify(
        () => mockCubit.onAlgorithmSelected(
          any(that: predicate<AlgorithmInfo>((a) => a.guid == 'TestPlugin')),
          any(that: equals([6, 0])),
          addBypassed: false,
        ),
      ).called(1);
      expect(find.text('Test Plugin added'), findsNothing);
      expect(find.text('Select Algorithm'), findsOneWidget);
    });

    testWidgets('Add Another preserves bypass intent through specs dialog', (
      tester,
    ) async {
      addTearDown(() async {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      });
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockLoadedPlugin]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Plugin'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Add Another Bypassed'),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('TestPlugin_spec_0')),
        '6',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      verify(
        () => mockCubit.onAlgorithmSelected(
          any(that: predicate<AlgorithmInfo>((a) => a.guid == 'TestPlugin')),
          any(that: equals([6, 0])),
          addBypassed: true,
        ),
      ).called(1);
    });

    testWidgets('Add Another shows generic error when add verification fails', (
      tester,
    ) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockCubit.onAlgorithmSelected(
          any(),
          any(),
          addBypassed: any(named: 'addBypassed'),
        ),
      ).thenAnswer((_) async => throw const AlgorithmAddFailedException());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Another'));
      await tester.pumpAndSettle();

      expect(find.text(algorithmAddFailedMessage), findsOneWidget);
      expect(find.text('Clock added'), findsNothing);
      expect(
        find.widgetWithText(ElevatedButton, 'Add Another'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Add Another clears selection after confirmed add with bypass failure',
      (tester) async {
        addTearDown(() async {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        });
        when(
          () => mockCubit.state,
        ).thenReturn(synchronizedWith([mockFactoryAlgorithm]));
        when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());
        when(
          () => mockCubit.onAlgorithmSelected(any(), any(), addBypassed: true),
        ).thenAnswer(
          (_) async => throw const AlgorithmAddBypassFailedException(),
        );

        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clock'));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Add Another Bypassed'),
        );
        await tester.pumpAndSettle();

        expect(find.text(algorithmAddBypassFailedMessage), findsOneWidget);
        expect(find.text('Select Algorithm'), findsOneWidget);
        expect(
          find.widgetWithText(ElevatedButton, 'Add Another Bypassed'),
          findsNothing,
        );
        verify(
          () => mockCubit.onAlgorithmSelected(
            any(that: predicate<AlgorithmInfo>((a) => a.guid == 'clck')),
            any(),
            addBypassed: true,
          ),
        ).called(1);
      },
    );

    testWidgets('Add Another button hidden when slot cap is reached', (
      tester,
    ) async {
      when(
        () => mockCubit.state,
      ).thenReturn(synchronizedWith([mockFactoryAlgorithm], slotCount: 40));
      when(() => mockCubit.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clock'));
      await tester.pumpAndSettle();

      // Add Algorithm is still rendered (existing behavior unchanged)
      expect(
        find.widgetWithText(ElevatedButton, 'Add Algorithm'),
        findsOneWidget,
      );
      // But the Add Another button is gone
      expect(find.widgetWithText(ElevatedButton, 'Add Another'), findsNothing);
    });
  });
}
