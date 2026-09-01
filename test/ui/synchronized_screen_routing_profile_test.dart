import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDown(() => database.close());

  testWidgets('reorder preview uses the connected device profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cubit = _MockDistingCubit();
    final platform = _MockPlatformInteractionService();
    final slots = [_readerSlot(), _writerSlot()];
    final state = DistingState.synchronized(
      disting: _MockDistingMidiManager(),
      distingVersion: '1.15',
      firmwareVersion: FirmwareVersion('1.15'),
      deviceIoProfile: DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!,
      presetName: 'Test',
      algorithms: const [],
      slots: slots,
      unitStrings: const [],
    );
    when(() => platform.isMobilePlatform()).thenReturn(false);
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => Stream.value(state));
    when(() => cubit.cpuUsageStream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.checkpoints).thenReturn([]);
    when(() => cubit.database).thenReturn(database);
    McpServerService.initialize(distingCubit: cubit);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: SynchronizedScreen(
            slots: slots,
            algorithms: const [],
            units: const [],
            presetName: 'Test',
            distingVersion: '1.15',
            firmwareVersion: FirmwareVersion('1.15'),
            screenshot: Uint8List(0),
            loading: false,
            platformService: platform,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Routing mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<RoutingEditorViewMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bus Lanes'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Reorder algorithms to fix bus flow'),
      findsOneWidget,
    );
  });
}

Slot _readerSlot() =>
    _slot(index: 0, parameter: _parameter(index: 0, ioFlags: 1, name: 'Input'));

Slot _writerSlot() => _slot(
  index: 1,
  parameter: _parameter(index: 1, ioFlags: 2, name: 'Output'),
);

ParameterInfo _parameter({
  required int index,
  required int ioFlags,
  required String name,
}) => ParameterInfo(
  algorithmIndex: index,
  parameterNumber: 0,
  min: 0,
  max: 12,
  defaultValue: 5,
  unit: 1,
  name: name,
  powerOfTen: 0,
  ioFlags: ioFlags,
);

Slot _slot({required int index, required ParameterInfo parameter}) => Slot(
  algorithm: Algorithm(algorithmIndex: index, guid: 'test$index', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: index, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: index, pages: const []),
  parameters: [parameter],
  values: [ParameterValue(algorithmIndex: index, parameterNumber: 0, value: 5)],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
