import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

const _algorithmGuid = 'RSPC';

typedef _WidgetDeviceFixture = ({
  List<int> specifications,
  List<String> parameterNames,
  List<int> parameterValues,
  List<PackedMappingData> mappings,
  List<int> routing,
});

class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

final class _WidgetRespecificationManager extends Mock
    implements IDistingMidiManager, AlgorithmRespecificationWriter {
  List<int> deviceSpecifications = [1];
  final List<List<int>> mutations = [];
  final List<Duration?> readbackTimeouts = [];
  final List<int?> readbackMaxRetries = [];
  final List<bool> readbackRejectAmbiguous = [];
  final Completer<Algorithm?> lateReadback = Completer<Algorithm?>();
  Completer<ParameterPages?>? hydrationPagesGate;
  List<int>? specificationsReturnedAfterMutation;
  _WidgetDeviceFixture? fixtureReturnedAfterMutation;
  _WidgetDeviceFixture? _deviceFixture;
  bool missingReadback = false;
  bool failHydration = false;
  int hydrationRequests = 0;
  int ordinaryRefreshRequests = 0;

  @override
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  }) async {
    ordinaryRefreshRequests++;
    return 1;
  }

  @override
  Future<String?> requestPresetName() async => 'Respecification widget fixture';

  @override
  Future<void> requestRespecifyAlgorithm(
    int algorithmIndex,
    List<int> specifications,
  ) async {
    mutations.add(List<int>.from(specifications));
    final returnedFixture = fixtureReturnedAfterMutation;
    if (returnedFixture != null) {
      _deviceFixture = returnedFixture;
      deviceSpecifications = List<int>.from(returnedFixture.specifications);
    } else {
      deviceSpecifications = List<int>.from(
        specificationsReturnedAfterMutation ?? specifications,
      );
    }
  }

  @override
  Future<Algorithm?> requestAlgorithmGuid(
    int algorithmIndex, {
    Duration? timeout,
    int? maxRetries,
    DistingRequestCancellation? cancellation,
    bool rejectAmbiguousResponse = false,
  }) {
    if (cancellation == null) {
      hydrationRequests++;
      return Future<Algorithm?>.value(_deviceAlgorithm());
    }

    readbackTimeouts.add(timeout);
    readbackMaxRetries.add(maxRetries);
    readbackRejectAmbiguous.add(rejectAmbiguousResponse);
    if (!missingReadback) {
      return Future<Algorithm?>.value(_deviceAlgorithm());
    }

    return Future.any<Algorithm?>([
      lateReadback.future,
      Future<Algorithm?>.delayed(timeout ?? const Duration(seconds: 1)),
    ]);
  }

  @override
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex) async {
    return NumParameters(
      algorithmIndex: algorithmIndex,
      numParameters: _deviceParameterCount,
    );
  }

  @override
  Future<ParameterPages?> requestParameterPages(int algorithmIndex) {
    if (failHydration) return Future<ParameterPages?>.value();
    final pages = ParameterPages(
      algorithmIndex: algorithmIndex,
      pages: [
        ParameterPage(
          name: 'Device page',
          parameters: List<int>.generate(
            _deviceParameterCount,
            (index) => index,
          ),
        ),
      ],
    );
    return hydrationPagesGate?.future ?? Future<ParameterPages?>.value(pages);
  }

  @override
  Future<AllParameterValues?> requestAllParameterValues(
    int algorithmIndex,
  ) async {
    return AllParameterValues(
      algorithmIndex: algorithmIndex,
      values: List<ParameterValue>.generate(
        _deviceParameterCount,
        (index) => ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: index,
          value: _deviceValue(index),
        ),
      ),
    );
  }

  @override
  Future<ParameterInfo?> requestParameterInfo(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    return ParameterInfo(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      min: 0,
      max: 100,
      defaultValue: _deviceValue(parameterNumber),
      unit: 0,
      name: _deviceParameterName(parameterNumber),
      powerOfTen: 0,
      ioFlags: parameterNumber == 1 ? 8 : 0,
    );
  }

  @override
  Future<Mapping?> requestMappings(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    return Mapping(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      packedMappingData: _deviceMapping(parameterNumber),
    );
  }

  @override
  Future<OutputModeUsage?> requestOutputModeUsage(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    return OutputModeUsage(
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      affectedParameterNumbers: const [0],
    );
  }

  @override
  Future<RoutingInfo?> requestRoutingInformation(int algorithmIndex) async {
    return RoutingInfo(
      algorithmIndex: algorithmIndex,
      routingInfo: List<int>.from(
        _deviceFixture?.routing ?? List<int>.filled(6, 4),
      ),
    );
  }

  Algorithm _deviceAlgorithm() => Algorithm(
    algorithmIndex: 0,
    guid: _algorithmGuid,
    name: 'Shape fixture',
    specifications: List<int>.from(
      _deviceFixture?.specifications ?? deviceSpecifications,
    ),
    hasAuthoritativeSpecifications: true,
  );

  int get _deviceParameterCount =>
      _deviceFixture?.parameterNames.length ?? deviceSpecifications.single;

  int _deviceValue(int parameterNumber) {
    final fixture = _deviceFixture;
    if (fixture != null) return fixture.parameterValues[parameterNumber];
    if (deviceSpecifications.single == 2) {
      return parameterNumber == 0 ? 11 : 77;
    }
    return 12;
  }

  String _deviceParameterName(int parameterNumber) {
    final fixture = _deviceFixture;
    if (fixture != null) return fixture.parameterNames[parameterNumber];
    return parameterNumber == 0
        ? 'Existing device value'
        : 'Added device default';
  }

  PackedMappingData _deviceMapping(int parameterNumber) {
    final fixture = _deviceFixture;
    if (fixture != null) return fixture.mappings[parameterNumber];
    return PackedMappingData.filler().copyWith(
      version: 6,
      midiChannel: 2,
      midiCC: parameterNumber == 0 ? 12 : 74,
      isMidiEnabled: true,
      midiMin: 0,
      midiMax: 127,
    );
  }
}

final class _WidgetDistingCubit extends DistingCubit {
  _WidgetDistingCubit(
    super.database, {
    super.midiCommand,
    super.isWindowsOverride,
  });

  int ordinaryRefreshFetches = 0;

  @override
  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int completed, int total)? onSlotProgress,
  }) async {
    ordinaryRefreshFetches++;
    final manager = disting as _WidgetRespecificationManager;
    onSlotProgress?.call(1, 1);
    return [_deviceReturnedSlot(manager)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late _WidgetDistingCubit cubit;
  late _WidgetRespecificationManager manager;
  late _MockPlatformInteractionService platformService;
  late AlgorithmControllerSectionController controllerSections;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.19.0'));
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
    manager = _WidgetRespecificationManager();
    platformService = _MockPlatformInteractionService();
    when(() => platformService.isMobilePlatform()).thenReturn(true);
    cubit = _WidgetDistingCubit(
      database,
      midiCommand: MockMidiCommand(),
      isWindowsOverride: true,
    )..emit(_synchronizedState(manager));
    McpServerService.initialize(distingCubit: cubit);
    controllerSections = AlgorithmControllerSectionController(
      initiallyCollapsed: false,
    );
  });

  tearDown(() async {
    controllerSections.dispose();
    await cubit.close();
    await database.close();
  });

  testWidgets(
    'one submit waits for authoritative growth then shrink discards stale shape',
    (tester) async {
      final semantics = tester.ensureSemantics();
      manager.hydrationPagesGate = Completer<ParameterPages?>();
      await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
      await tester.pump();

      expect(find.text('Existing device value'), findsOneWidget);
      expect(find.text('Added device default'), findsNothing);

      await _openRespecifyDialog(tester);
      final field = find.byKey(const ValueKey('${_algorithmGuid}_spec_0'));
      await tester.enterText(field, '2');
      await tester.pump();

      expect(manager.mutations, isEmpty, reason: 'editing must not write');

      final submit = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Respecify'),
      );
      submit.onPressed!();
      submit.onPressed!();
      await tester.pump();

      expect(manager.mutations, [
        [2],
      ]);
      expect(find.text('Respecifying…'), findsOneWidget);
      expect(find.text('Refreshing slot data…'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .semanticsLabel,
        'Waiting for slot data',
      );
      expect(
        tester
            .getSemantics(find.text('Respecifying…'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(find.widgetWithText(ElevatedButton, 'Respecify'), findsNothing);

      await tester.pump(const Duration(milliseconds: 999));
      expect(manager.readbackTimeouts, isEmpty);
      expect(find.text('Added device default'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      expect(manager.readbackTimeouts, [const Duration(seconds: 1)]);
      expect(manager.readbackMaxRetries, [1]);
      expect(manager.readbackRejectAmbiguous, [isTrue]);
      expect(manager.hydrationRequests, 1);
      expect(find.text('Respecifying…'), findsOneWidget);
      expect(find.text('Added device default'), findsNothing);

      manager.hydrationPagesGate!.complete(
        ParameterPages(
          algorithmIndex: 0,
          pages: [
            ParameterPage(name: 'Device page', parameters: const [0, 1]),
          ],
        ),
      );
      manager.hydrationPagesGate = null;
      await tester.pump();
      await tester.pumpAndSettle();

      final grown = (cubit.state as DistingStateSynchronized).slots.single;
      expect(grown.algorithm.specifications, [2]);
      expect(grown.parameters.map((parameter) => parameter.name), [
        'Existing device value',
        'Added device default',
      ]);
      expect(grown.parameters[1].defaultValue, 77);
      expect(grown.values.map((value) => value.value), [11, 77]);
      expect(grown.mappings, hasLength(2));
      expect(
        grown.mappings[1].packedMappingData.midiCC,
        74,
        reason: 'the added mapping must be device-returned',
      );
      expect(grown.outputModeMap, const {
        1: [0],
      });
      expect(cubit.getSlotOutputModeUsage(0), const {
        1: [0],
      });
      expect(find.text('Added device default'), findsOneWidget);
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .map((slider) => slider.value),
        contains(77),
      );

      await _openRespecifyDialog(tester);
      final shrinkField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
          matching: find.byType(TextField),
        ),
      );
      expect(shrinkField.controller?.text, '2');
      await tester.enterText(
        find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
        '1',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pump();
      expect(manager.mutations, [
        [2],
        [1],
      ]);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final shrunk = (cubit.state as DistingStateSynchronized).slots.single;
      expect(shrunk.algorithm.specifications, [1]);
      expect(shrunk.parameters.map((parameter) => parameter.name), [
        'Existing device value',
      ]);
      expect(shrunk.values.map((value) => value.value), [12]);
      expect(shrunk.mappings, hasLength(1));
      expect(shrunk.enums, hasLength(1));
      expect(shrunk.valueStrings, hasLength(1));
      expect(shrunk.pages.pages.single.parameters, [0]);
      expect(shrunk.outputModeMap, isEmpty);
      expect(cubit.getSlotOutputModeUsage(0), isEmpty);
      expect(find.text('Added device default'), findsNothing);
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .map((slider) => slider.value),
        isNot(contains(77)),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'conflicting returned indices replace displayed parameters, mappings, and routing',
    (tester) async {
      final insertedMapping = PackedMappingData.filler().copyWith(
        version: 6,
        midiChannel: 3,
        midiCC: 91,
        isMidiEnabled: true,
        midiMin: 0,
        midiMax: 127,
      );
      final shiftedMapping = PackedMappingData.filler().copyWith(
        version: 6,
        midiChannel: 2,
        midiCC: 12,
        isMidiEnabled: true,
        midiMin: 0,
        midiMax: 127,
      );
      manager.fixtureReturnedAfterMutation = (
        specifications: [2],
        parameterNames: [
          'Inserted device parameter',
          'Existing value shifted by device',
        ],
        parameterValues: [77, 10],
        mappings: [insertedMapping, shiftedMapping],
        routing: [9, 8, 7, 6, 5, 4],
      );

      await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
      await tester.pump();

      expect(find.text('Existing device value'), findsOneWidget);
      expect(find.byTooltip('Add mapping'), findsOneWidget);

      await _openRespecifyDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
        '2',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final returned = (cubit.state as DistingStateSynchronized).slots.single;
      expect(returned.algorithm.specifications, [2]);
      expect(returned.parameters.map((parameter) => parameter.name), [
        'Inserted device parameter',
        'Existing value shifted by device',
      ]);
      expect(returned.values.map((value) => value.value), [77, 10]);
      expect(
        returned.mappings.map((mapping) => mapping.packedMappingData.midiCC),
        [91, 12],
      );
      expect(returned.routing.routingInfo, [9, 8, 7, 6, 5, 4]);

      expect(find.text('Existing device value'), findsNothing);
      expect(find.text('Inserted device parameter'), findsOneWidget);
      expect(find.text('Existing value shifted by device'), findsOneWidget);
      expect(find.byTooltip('Edit mapping (active)'), findsNWidgets(2));
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .map((slider) => slider.value),
        containsAll(<double>[77, 10]),
      );
    },
  );

  testWidgets(
    'matching unchanged values establish current state without acknowledgement',
    (tester) async {
      await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
      await tester.pump();

      await _openRespecifyDialog(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pump();

      expect(manager.mutations, [
        [1],
      ]);
      expect(find.text('Respecifying…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        (cubit.state as DistingStateSynchronized)
            .slots
            .single
            .algorithm
            .specifications,
        [1],
      );
      expect(find.text('Respecifying…'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(manager.mutations, hasLength(1));
    },
  );

  testWidgets('invalid range remains in the form and sends no mutation', (
    tester,
  ) async {
    await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
    await tester.pump();

    await _openRespecifyDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
      '4',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
    await tester.pumpAndSettle();

    expect(
      find.text('Parameter count must be between 1 and 3'),
      findsOneWidget,
    );
    expect(find.text('Respecify Shape fixture'), findsOneWidget);
    expect(manager.mutations, isEmpty);
    expect(manager.readbackTimeouts, isEmpty);
  });

  testWidgets(
    'differing device state replaces the proposal and reopens as authoritative',
    (tester) async {
      manager.specificationsReturnedAfterMutation = [2];
      await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
      await tester.pump();

      await _openRespecifyDialog(tester);
      final fieldKey = ValueKey('${_algorithmGuid}_spec_0');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(fieldKey),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '1',
      );
      await tester.enterText(find.byKey(fieldKey), '3');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pump();

      expect(manager.mutations, [
        [3],
      ]);
      expect(find.text('Respecifying…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final returned = (cubit.state as DistingStateSynchronized).slots.single;
      expect(returned.algorithm.specifications, [2]);
      expect(returned.parameters.map((parameter) => parameter.name), [
        'Existing device value',
        'Added device default',
      ]);
      expect(returned.values.map((value) => value.value), [11, 77]);
      expect(manager.hydrationRequests, 1);
      expect(find.text('Respecifying…'), findsNothing);
      expect(find.text('Respecify Shape fixture'), findsNothing);
      expect(
        find.text(
          'The device returned different specifications. Displaying the '
          'returned device state.',
        ),
        findsOneWidget,
      );

      await _openRespecifyDialog(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(fieldKey),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        '2',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        manager.mutations,
        [
          [3],
        ],
        reason: 'reopening must not retain or resend the submitted proposal',
      );
    },
  );

  testWidgets(
    'missing and late readback exits waiting at ten seconds without resending',
    (tester) async {
      manager.missingReadback = true;
      final initialState = cubit.state;
      await tester.pumpWidget(
        _synchronizedScreenHarness(cubit, platformService),
      );
      await tester.pump();
      await _openRespecifyDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
        '2',
      );
      final submit = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Respecify'),
      );
      submit.onPressed!();
      submit.onPressed!();
      await tester.pump();

      expect(manager.mutations, [
        [2],
      ]);
      expect(find.text('Respecifying…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 999));
      expect(manager.readbackTimeouts, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(manager.readbackTimeouts, [const Duration(seconds: 1)]);
      await tester.pump(const Duration(milliseconds: 999));
      expect(manager.readbackTimeouts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(manager.readbackTimeouts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(manager.readbackTimeouts, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(manager.readbackTimeouts, hasLength(2));

      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Respecifying…'), findsNothing);
      expect(find.text('Refreshing slot data…'), findsNothing);
      expect(
        find.text(
          'Unable to verify whether the proposed specifications were applied.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Retry'), findsNothing);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      final refreshButton = find.widgetWithIcon(
        IconButton,
        Icons.refresh_rounded,
      );
      expect(refreshButton, findsOneWidget);
      expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);
      expect(manager.mutations, hasLength(1));
      expect(manager.hydrationRequests, 0);
      expect(manager.ordinaryRefreshRequests, 0);
      expect(cubit.ordinaryRefreshFetches, 0);
      expect(cubit.state, same(initialState));
      expect(
        manager.readbackTimeouts,
        everyElement(const Duration(seconds: 1)),
      );

      manager.lateReadback.complete(
        Algorithm(
          algorithmIndex: 0,
          guid: _algorithmGuid,
          name: 'Shape fixture',
          specifications: const [2],
          hasAuthoritativeSpecifications: true,
        ),
      );
      await tester.pump();
      expect(manager.mutations, hasLength(1));
      expect(manager.hydrationRequests, 0);
      expect(cubit.state, same(initialState));

      await tester.tap(refreshButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(manager.ordinaryRefreshRequests, 1);
      expect(cubit.ordinaryRefreshFetches, 1);
      expect(manager.mutations, hasLength(1));
      final refreshedSlot =
          (cubit.state as DistingStateSynchronized).slots.single;
      expect(refreshedSlot.algorithm.specifications, [2]);
      expect(refreshedSlot.parameters.map((parameter) => parameter.name), [
        'Existing device value',
        'Added device default',
      ]);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    },
  );

  testWidgets('hydration failure exits waiting without showing stale success', (
    tester,
  ) async {
    manager.failHydration = true;
    final initialState = cubit.state;
    await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
    await tester.pump();
    await _openRespecifyDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('${_algorithmGuid}_spec_0')),
      '2',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
    await tester.pump();

    expect(find.text('Respecifying…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Respecifying…'), findsNothing);
    expect(find.text('Refreshing slot data…'), findsNothing);
    expect(find.text('Unable to verify refreshed slot data.'), findsOneWidget);
    expect(manager.mutations, [
      [2],
    ]);
    expect(manager.hydrationRequests, 1);
    expect(cubit.state, same(initialState));
    expect(find.text('Added device default'), findsNothing);
  });
}

Future<void> _openRespecifyDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('slot-editor-more-options')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('slot-editor-respecify')));
  await tester.pumpAndSettle();
}

Widget _slotEditorHarness(
  DistingCubit cubit,
  AlgorithmControllerSectionController controllerSections,
) {
  return MaterialApp(
    home: BlocProvider<DistingCubit>.value(
      value: cubit,
      child: BlocBuilder<DistingCubit, DistingState>(
        builder: (context, state) {
          if (state is! DistingStateSynchronized) {
            return const SizedBox.shrink();
          }
          return Scaffold(
            body: SlotDetailView(
              slot: state.slots.single,
              slotIndex: 0,
              units: state.unitStrings,
              firmwareVersion: state.firmwareVersion,
              algorithmControllerSections: controllerSections,
              editorMode: SlotEditorMode.standard,
              onEditorModeChanged: (_) {},
            ),
          );
        },
      ),
    ),
  );
}

Widget _synchronizedScreenHarness(
  DistingCubit cubit,
  PlatformInteractionService platformService,
) {
  return MaterialApp(
    home: BlocProvider<DistingCubit>.value(
      value: cubit,
      child: BlocBuilder<DistingCubit, DistingState>(
        builder: (context, state) {
          if (state is! DistingStateSynchronized) {
            return const SizedBox.shrink();
          }
          return SynchronizedScreen(
            slots: state.slots,
            algorithms: state.algorithms,
            units: state.unitStrings,
            presetName: state.presetName,
            isDirty: state.isDirty,
            distingVersion: state.distingVersion,
            firmwareVersion: state.firmwareVersion,
            screenshot: state.screenshot,
            loading: state.loading,
            platformService: platformService,
          );
        },
      ),
    ),
  );
}

Slot _deviceReturnedSlot(_WidgetRespecificationManager manager) {
  final parameterCount = manager._deviceParameterCount;
  return Slot(
    algorithm: manager._deviceAlgorithm(),
    routing: RoutingInfo(
      algorithmIndex: 0,
      routingInfo: List<int>.from(
        manager._deviceFixture?.routing ?? List<int>.filled(6, 4),
      ),
    ),
    pages: ParameterPages(
      algorithmIndex: 0,
      pages: [
        ParameterPage(
          name: 'Device page',
          parameters: List<int>.generate(parameterCount, (index) => index),
        ),
      ],
    ),
    parameters: List<ParameterInfo>.generate(
      parameterCount,
      (index) => ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: index,
        min: 0,
        max: 100,
        defaultValue: manager._deviceValue(index),
        unit: 0,
        name: manager._deviceParameterName(index),
        powerOfTen: 0,
        ioFlags: index == 1 ? 8 : 0,
      ),
    ),
    values: List<ParameterValue>.generate(
      parameterCount,
      (index) => ParameterValue(
        algorithmIndex: 0,
        parameterNumber: index,
        value: manager._deviceValue(index),
      ),
    ),
    enums: List<ParameterEnumStrings>.generate(
      parameterCount,
      (_) => ParameterEnumStrings.filler(),
    ),
    mappings: List<Mapping>.generate(
      parameterCount,
      (index) => Mapping(
        algorithmIndex: 0,
        parameterNumber: index,
        packedMappingData: manager._deviceMapping(index),
      ),
    ),
    valueStrings: List<ParameterValueString>.generate(
      parameterCount,
      (_) => ParameterValueString.filler(),
    ),
    parameterCountFromDevice: true,
    parameterPagesFromDevice: true,
    parameterValuesFromDevice: true,
    outputModeMap: parameterCount == 2
        ? const {
            1: [0],
          }
        : const {},
  );
}

DistingStateSynchronized _synchronizedState(
  _WidgetRespecificationManager manager,
) {
  return DistingState.synchronized(
        disting: manager,
        distingVersion: '1.19.0',
        firmwareVersion: FirmwareVersion('1.19.0'),
        presetName: 'Respecification widget fixture',
        algorithms: [
          AlgorithmInfo(
            algorithmIndex: 17,
            guid: _algorithmGuid,
            name: 'Shape fixture',
            specifications: [
              Specification(
                name: 'Parameter count',
                min: 1,
                max: 3,
                defaultValue: 1,
                type: 0,
              ),
            ],
          ),
        ],
        slots: [_initialSlot()],
        unitStrings: const [],
      )
      as DistingStateSynchronized;
}

Slot _initialSlot() {
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: 0,
      guid: _algorithmGuid,
      name: 'Shape fixture',
      specifications: const [1],
      hasAuthoritativeSpecifications: true,
    ),
    routing: RoutingInfo(
      algorithmIndex: 0,
      routingInfo: List<int>.filled(6, 0),
    ),
    pages: ParameterPages(
      algorithmIndex: 0,
      pages: [
        ParameterPage(name: 'Device page', parameters: const [0]),
      ],
    ),
    parameters: [
      ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 10,
        unit: 0,
        name: 'Existing device value',
        powerOfTen: 0,
      ),
    ],
    values: [ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 10)],
    enums: [ParameterEnumStrings.filler()],
    mappings: [
      Mapping(
        algorithmIndex: 0,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler(),
      ),
    ],
    valueStrings: [ParameterValueString.filler()],
    parameterCountFromDevice: true,
    parameterPagesFromDevice: true,
    parameterValuesFromDevice: true,
  );
}
