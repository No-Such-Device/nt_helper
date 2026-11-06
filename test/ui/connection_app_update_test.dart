import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/app_update_service.dart';
import 'package:nt_helper/ui/widgets/app_update_action.dart';
import 'package:nt_helper/ui/widgets/app_update_dialog.dart';

class _Updates extends Mock implements AppUpdateService {}

class _Disting extends MockCubit<DistingState> implements DistingCubit {}

void main() {
  final release = AppRelease(
    version: '3.0.0',
    tagName: 'v3.0.0',
    body: 'Release notes',
    publishedAt: DateTime(2026, 1, 1),
    platformAssets: const {},
  );
  final input = MidiDevice('input', 'Input', MidiDeviceType.serial, true);
  final output = MidiDevice('output', 'Output', MidiDeviceType.serial, false);
  late _Updates service;
  late _Disting cubit;

  setUp(() {
    service = _Updates();
    cubit = _Disting();
    when(() => service.isSupported).thenReturn(true);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => cubit.state).thenReturn(
      DistingState.selectDevice(
        inputDevices: [input],
        outputDevices: [output],
        canWorkOffline: true,
        selectedInputDevice: input,
        selectedOutputDevice: output,
      ),
    );
    when(
      () => cubit.connectToDevices(input, output, 0),
    ).thenAnswer((_) async {});
  });

  Future<void> showPage(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: DistingPage(appUpdateService: service),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'update discovery before synchronization preserves connection controls, keyboard access and live semantics',
    (tester) async {
      final pending = Completer<AppRelease?>();
      when(
        () => service.checkForUpdate(forceRefresh: false),
      ).thenAnswer((_) => pending.future);
      await showPage(tester);
      final semantics = tester.ensureSemantics();
      final inputRect = tester.getRect(
        find.byKey(const ValueKey('input-midi-device-dropdown')),
      );
      final connect = find.widgetWithText(FilledButton, 'Connect');
      final connectRect = tester.getRect(connect);
      final settingsRect = tester.getRect(find.byTooltip('Settings'));
      final actionRect = tester.getRect(find.byType(AppUpdateAction));
      expect(find.byTooltip('Checking for app updates'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.settings))
            .onPressed,
        isNotNull,
      );
      expect(tester.widget<FilledButton>(connect).onPressed, isNotNull);
      await tester.tap(connect);
      verify(() => cubit.connectToDevices(input, output, 0)).called(1);
      pending.complete(release);
      await tester.pumpAndSettle();
      final update = find.byTooltip('Update NT Helper to 3.0.0');
      expect(update, findsOneWidget);
      expect(
        tester.getSemantics(find.byType(AppUpdateAction)).label,
        contains('Update NT Helper to 3.0.0'),
      );
      expect(
        tester
            .getSemantics(find.byType(AppUpdateAction))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      expect(tester.getRect(find.byType(AppUpdateAction)), actionRect);
      expect(
        tester.getRect(
          find.byKey(const ValueKey('input-midi-device-dropdown')),
        ),
        inputRect,
      );
      expect(tester.getRect(connect), connectRect);
      expect(tester.getRect(find.byTooltip('Settings')), settingsRect);
      Focus.of(tester.element(find.byType(Badge))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateDialog), findsOneWidget);
      semantics.dispose();
    },
    tags: ['regression'],
  );

  testWidgets(
    'available update downloads and offers Restart Now without a MIDI connection',
    (tester) async {
      when(() => cubit.state).thenReturn(
        const DistingState.selectDevice(
          inputDevices: [],
          outputDevices: [],
          canWorkOffline: false,
        ),
      );
      when(
        () => service.checkForUpdate(forceRefresh: false),
      ).thenAnswer((_) async => release);
      final download = Completer<String>();
      when(
        () => service.downloadUpdate(
          release,
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) {
        (invocation.namedArguments[#onProgress] as void Function(double))(0.5);
        return download.future;
      });
      when(() => service.installUpdate('/download/update.zip')).thenAnswer(
        (_) async => const InstallResult(
          outcome: InstallOutcome.needsRestart,
          message: 'Update installed. Restart to use the new version.',
        ),
      );
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Update NT Helper to 3.0.0'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<AppUpdateDialog>(
        find.byType(AppUpdateDialog),
      );
      expect(dialog.release, same(release));
      expect(dialog.updateService, same(service));
      await tester.tap(find.text('Download & Install'));
      await tester.pump();
      expect(find.text('Downloading... 50%'), findsOneWidget);
      download.complete('/download/update.zip');
      await tester.pumpAndSettle();
      verify(() => service.installUpdate('/download/update.zip')).called(1);
      expect(find.text('Restart Now'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Restart Now'),
            )
            .onPressed,
        isNotNull,
      );
      // Do not invoke the real process-relaunch/exit operation in a widget test.
      verifyNever(() => cubit.connectToDevices(input, output, 0));
    },
    tags: ['regression'],
  );

  testWidgets(
    'manual connection-screen check forces refresh after no update was found',
    (tester) async {
      when(
        () => service.checkForUpdate(forceRefresh: false),
      ).thenAnswer((_) async => null);
      when(
        () => service.checkForUpdate(forceRefresh: true),
      ).thenAnswer((_) async => release);
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      await tester.tap(find.byTooltip('Check for app updates'));
      await tester.pumpAndSettle();
      verify(() => service.checkForUpdate(forceRefresh: false)).called(1);
      verify(() => service.checkForUpdate(forceRefresh: true)).called(1);
      expect(find.byTooltip('Update NT Helper to 3.0.0'), findsOneWidget);
      expect(find.byType(AppUpdateDialog), findsNothing);
    },
    tags: ['regression'],
  );

  testWidgets(
    'unsupported distribution hides the action and never checks for updates',
    (tester) async {
      when(() => service.isSupported).thenReturn(false);
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Check for app updates'), findsNothing);
      expect(find.byTooltip('Checking for app updates'), findsNothing);
      verifyNever(
        () => service.checkForUpdate(forceRefresh: any(named: 'forceRefresh')),
      );
    },
    tags: ['regression'],
  );

  testWidgets(
    'update check errors allow retry without disabling MIDI connection',
    (tester) async {
      when(
        () => service.checkForUpdate(forceRefresh: false),
      ).thenThrow(StateError('check failed'));
      when(
        () => service.checkForUpdate(forceRefresh: true),
      ).thenAnswer((_) async => release);
      await showPage(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not check for app updates:'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Check for app updates'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Update NT Helper to 3.0.0'), findsOneWidget);
    },
    tags: ['regression'],
  );

  testWidgets(
    'late update result after leaving connection screen is ignored without closing the borrowed service',
    (tester) async {
      final pending = Completer<AppRelease?>();
      when(
        () => service.checkForUpdate(forceRefresh: false),
      ).thenAnswer((_) => pending.future);
      await showPage(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(release);
      await tester.pump();
      expect(tester.takeException(), isNull);
      verifyNever(() => service.dispose());
    },
    tags: ['regression'],
  );
}
