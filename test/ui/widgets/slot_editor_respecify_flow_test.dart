import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

const _algorithmGuid = 'RSPC';

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
  bool missingReadback = false;
  bool failHydration = false;
  int hydrationRequests = 0;

  @override
  Future<void> requestRespecifyAlgorithm(
    int algorithmIndex,
    List<int> specifications,
  ) async {
    mutations.add(List<int>.from(specifications));
    deviceSpecifications = List<int>.from(
      specificationsReturnedAfterMutation ?? specifications,
    );
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
      numParameters: deviceSpecifications.single,
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
            deviceSpecifications.single,
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
        deviceSpecifications.single,
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
      name: parameterNumber == 0
          ? 'Existing device value'
          : 'Added device default',
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
      packedMappingData: PackedMappingData.filler().copyWith(
        version: 6,
        midiChannel: 2,
        midiCC: parameterNumber == 0 ? 12 : 74,
        isMidiEnabled: true,
        midiMin: 0,
        midiMax: 127,
      ),
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
      routingInfo: List<int>.filled(6, 4),
    );
  }

  Algorithm _deviceAlgorithm() => Algorithm(
    algorithmIndex: 0,
    guid: _algorithmGuid,
    name: 'Shape fixture',
    specifications: List<int>.from(deviceSpecifications),
    hasAuthoritativeSpecifications: true,
  );

  int _deviceValue(int parameterNumber) {
    if (deviceSpecifications.single == 2) {
      return parameterNumber == 0 ? 11 : 77;
    }
    return 12;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DistingCubit cubit;
  late _WidgetRespecificationManager manager;
  late AlgorithmControllerSectionController controllerSections;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    ParameterEditorRegistry.setFirmwareVersion(FirmwareVersion('1.19.0'));
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
    manager = _WidgetRespecificationManager();
    cubit = DistingCubit(
      database,
      midiCommand: MockMidiCommand(),
      isWindowsOverride: true,
    )..emit(_synchronizedState(manager));
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
        find.text('The device did not apply the proposed specifications.'),
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
      await tester.pumpWidget(_slotEditorHarness(cubit, controllerSections));
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
        find.text('Unable to verify refreshed slot data.'),
        findsOneWidget,
      );
      expect(manager.mutations, hasLength(1));
      expect(manager.hydrationRequests, 0);
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
