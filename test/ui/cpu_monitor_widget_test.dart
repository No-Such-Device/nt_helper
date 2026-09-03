import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/cpu_monitor_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDistingCubit cubit;
  late StreamController<DistingState> stateController;
  late StreamController<CpuUsage?> cpuUsageController;

  DistingStateSynchronized synchronizedState() {
    return DistingStateSynchronized(
      disting: _MockDistingMidiManager(),
      distingVersion: 'NT',
      firmwareVersion: FirmwareVersion('1.10'),
      presetName: 'Test',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();

    cubit = _MockDistingCubit();
    stateController = StreamController<DistingState>.broadcast();
    cpuUsageController = StreamController<CpuUsage?>.broadcast();

    when(() => cubit.state).thenReturn(synchronizedState());
    when(() => cubit.stream).thenAnswer((_) => stateController.stream);
    when(
      () => cubit.cpuUsageStream,
    ).thenAnswer((_) => cpuUsageController.stream);
    when(() => cubit.resumeCpuMonitoring()).thenReturn(null);
    when(() => cubit.pauseCpuMonitoring()).thenReturn(null);
  });

  tearDown(() async {
    await stateController.close();
    await cpuUsageController.close();
  });

  testWidgets('uses static placeholder before first CPU sample', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: const CpuMonitorWidget(),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('--% | --%'), findsOneWidget);
  });

  testWidgets('keeps last CPU sample across null updates', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: const CpuMonitorWidget(),
          ),
        ),
      ),
    );

    cpuUsageController.add(CpuUsage(cpu1: 12, cpu2: 34, slotUsages: const []));
    await tester.pump();

    expect(find.text('12% | 34%'), findsOneWidget);

    cpuUsageController.add(null);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('12% | 34%'), findsOneWidget);
  });

  testWidgets('labels CPU values by their actual meaning', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: const CpuMonitorWidget(),
          ),
        ),
      ),
    );

    cpuUsageController.add(
      CpuUsage(cpu1: 12, cpu2: 34, slotUsages: const [5, 6]),
    );
    await tester.pump();

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      'CPU Usage:\n'
      'Audio thread: 12%\n'
      'Overall CPU: 34%\n'
      '\n'
      'Algorithm Slots:\n'
      'Slot 1: 5%\n'
      'Slot 2: 6%',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'CPU usage: Audio thread 12%, Overall CPU 34%',
      ),
      findsOneWidget,
    );
  });

  testWidgets('pauses and hides while chat panel is open', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: const CpuMonitorWidget(),
          ),
        ),
      ),
    );

    expect(find.text('--% | --%'), findsOneWidget);
    verify(() => cubit.resumeCpuMonitoring()).called(1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: const CpuMonitorWidget(paused: true),
          ),
        ),
      ),
    );

    expect(find.text('--% | --%'), findsNothing);
    expect(find.byType(CpuMonitorWidget), findsOneWidget);
    verify(() => cubit.pauseCpuMonitoring()).called(1);
  });
}
