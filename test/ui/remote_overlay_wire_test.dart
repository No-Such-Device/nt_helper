import 'dart:ui'
    show
        PointerDeviceKind,
        ViewFocusEvent,
        ViewFocusState,
        ViewFocusDirection,
        Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/video_popup_app.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';
import 'package:nt_helper/ui/widgets/floating_video_overlay.dart';
import 'package:nt_helper/ui/widgets/remote_control_cluster.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/memory_wire_harness.dart';
import '../test_helpers/popup_channel_harness.dart';
import '../test_helpers/video_input_harness.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Presets extends Mock implements PresetsDao {}

class _Platform extends Mock implements PlatformInteractionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  late DistingCubit cubit;
  late MemoryWireHarness wire;
  late VideoInputHarness video;

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({
      'show_debug_panel': false,
      'cpu_monitor_enabled': false,
      'request_timeout_ms': 1000,
      'inter_message_delay_ms': 0,
      'video_popup_native_window_enabled': false,
    });
    await SettingsService().init();
    wire = MemoryWireHarness(autoMemoryStatus: 3);
    video = VideoInputHarness()..install();
    final database = _Database();
    final metadata = _Metadata();
    final presets = _Presets();
    when(() => database.metadataDao).thenReturn(metadata);
    when(() => database.presetsDao).thenReturn(presets);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    when(() => presets.getTemplates()).thenAnswer((_) async => []);
    cubit = DistingCubit(
      database,
      midiCommand: wire.midi,
      isWindowsOverride: true,
    );
    cubit.emit(
      DistingState.synchronized(
        disting: wire.manager,
        distingVersion: '1.19.0',
        firmwareVersion: FirmwareVersion('1.19.0'),
        presetName: 'Remote test',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );
  }

  tearDown(() async {
    await cubit.close();
    await wire.close();
    video.uninstall();
  });

  Future<void> flush(WidgetTester tester) async {
    // Preserve virtual time while avoiding 30 full widget repaints.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      cubit.remoteControlState.pending,
      isFalse,
      reason: wire.sentPackets.toString(),
    );
  }

  Finder control(int index) => find.byKey(ValueKey('remote-control-$index'));
  List<List<int>> payloads() => wire.remotePackets
      .map((packet) => packet.sublist(7, packet.length - 1))
      .toList();

  Future<void> open(WidgetTester tester) async {
    await initialize();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    McpServerService.initialize(distingCubit: cubit);
    final platform = _Platform();
    when(() => platform.isMobilePlatform()).thenReturn(false);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DistingCubit>.value(
          value: cubit,
          child: SynchronizedScreen(
            distingVersion: '1.19.0',
            firmwareVersion: FirmwareVersion('1.19.0'),
            slots: const [],
            algorithms: const [],
            units: const [],
            presetName: 'Remote test',
            screenshot: Uint8List(0),
            loading: false,
            platformService: platform,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Video'));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await video.sendFrame();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('stable_frame')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
    await flush(tester);
    expect(find.byType(RemoteControlCluster), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Close overlay'));
    await flush(tester);
    expect(find.byType(FloatingVideoOverlay), findsNothing);
    await tester.runAsync(() => cubit.stopVideoStream());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> wheel(WidgetTester tester, int pushIndex, double delta) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(
          find
              .descendant(
                of: control(pushIndex),
                matching: find.byType(CustomPaint),
              )
              .first,
        ),
        scrollDelta: Offset(0, delta),
      ),
    );
    await flush(tester);
  }

  testWidgets(
    'production Video controls expose all nine distinct momentary wire targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      expect(wire.remotePackets, isEmpty);
      const names = [
        'Button 1',
        'Button 2',
        'Button 3',
        'Button 4',
        'Left pot',
        'Center pot',
        'Right pot',
        'Left encoder',
        'Right encoder',
      ];
      for (var i = 0; i < 9; i++) {
        final pointer = await tester.startGesture(tester.getCenter(control(i)));
        await flush(tester);
        expect(payloads().last, [1, i]);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(names[i]))
              .getSemanticsData()
              .value,
          contains('Pressed'),
        );
        expect(
          find.descendant(of: control(i), matching: find.text('Pressed')),
          findsNothing,
        );
        await pointer.up();
        await flush(tester);
        expect(payloads().last, [2, i]);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(names[i]))
              .getSemanticsData()
              .value,
          contains('Released'),
        );
      }
      expect(payloads(), [
        for (var i = 0; i < 9; i++) ...[
          [1, i],
          [2, i],
        ],
      ]);
      expect(find.text('Hold'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      await close(tester);
      semantics.dispose();
    },
  );

  testWidgets(
    'all rotary targets distinguish wheel from pushed drag and preserve chords',
    (tester) async {
      await open(tester);
      for (var index = 4; index < 9; index++) {
        final before = payloads().length;
        await wheel(tester, index, -1);
        await wheel(tester, index, 1);
        expect(
          payloads().sublist(before),
          index < 7
              ? [
                  [4, index - 4, 0x20, 0x10],
                  [4, index - 4, 0, 0x10],
                ]
              : [
                  [3, index - 7, 1],
                  [3, index - 7, 0x7F],
                ],
        );
        final start = tester.getCenter(control(index));
        final pointer = await tester.startGesture(start);
        await flush(tester);
        await pointer.moveBy(Offset(0, index < 7 ? -1 : -6));
        await flush(tester);
        await pointer.up();
        await flush(tester);
        expect(
          payloads().sublist(before + 2),
          index < 7
              ? [
                  [1, index],
                  [4, index - 4, 0x18, 0x10],
                  [2, index],
                ]
              : [
                  [1, index],
                  [3, index - 7, 1],
                  [2, index],
                ],
        );
      }
      final before = payloads().length;
      final button4 = await tester.startGesture(
        tester.getCenter(control(3)),
        pointer: 30,
      );
      await flush(tester);
      final button1 = await tester.startGesture(
        tester.getCenter(control(0)),
        pointer: 31,
      );
      await flush(tester);
      await wheel(tester, 7, -1);
      await button4.up();
      await flush(tester);
      expect(cubit.remoteControlState.heldControls, {0});
      await button1.up();
      await flush(tester);
      expect(payloads().sublist(before), [
        [1, 3],
        [1, 0],
        [3, 0, 1],
        [2, 3],
        [2, 0],
      ]);
      await close(tester);
    },
  );

  testWidgets(
    'each pot is silent at midpoint, retains adjustments and clamps without wrapping',
    (tester) async {
      await open(tester);
      for (var index = 4; index <= 6; index++) {
        expect(
          find.descendant(
            of: control(index),
            matching: find.text('Local 2048'),
          ),
          findsNothing,
        );
        await tester.tap(control(index));
        await flush(tester);
        expect(payloads().where((p) => p.first == 4), isEmpty);
      }
      // Rebuild and fold/reopen cannot initialize a hardware position.
      await video.sendFrame();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(payloads().where((p) => p.first == 4), isEmpty);
      for (var index = 4; index <= 6; index++) {
        await wheel(tester, index, 1);
        expect(payloads().last, [4, index - 4, 0x60, 0x0F]);
        await wheel(tester, index, -1);
        expect(payloads().last, [4, index - 4, 0, 0x10]);
        final pointer = await tester.startGesture(
          tester.getCenter(control(index)),
        );
        await flush(tester);
        await pointer.moveBy(const Offset(0, -1));
        await flush(tester);
        expect(payloads().last, [4, index - 4, 0x18, 0x10]);
        await pointer.moveBy(const Offset(0, -200));
        await flush(tester);
        expect(payloads().last, [4, index - 4, 0x7F, 0x1F]);
        await pointer.moveBy(const Offset(0, -200));
        await flush(tester);
        expect(cubit.remoteControlState.potValues[index - 4], 4095);
        await pointer.moveBy(const Offset(0, 400));
        await flush(tester);
        expect(payloads().last, [4, index - 4, 0, 0]);
        await pointer.moveBy(const Offset(0, 400));
        await flush(tester);
        expect(cubit.remoteControlState.potValues[index - 4], 0);
        await pointer.up();
        await flush(tester);
        await wheel(tester, index, -1);
        expect(payloads().last, [4, index - 4, 32, 0]);
      }
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [32, 32, 32]);
      await close(tester);
    },
  );

  testWidgets(
    'both encoders retain fractional drag remainder and split signed movement totals',
    (tester) async {
      await open(tester);
      for (var index = 7; index < 9; index++) {
        final before = payloads().length;
        for (var n = 0; n < 5; n++) {
          await wheel(tester, index, -1);
        }
        for (var n = 0; n < 5; n++) {
          await wheel(tester, index, 1);
        }
        expect(payloads().sublist(before), [
          for (var n = 0; n < 5; n++) [3, index - 7, 1],
          for (var n = 0; n < 5; n++) [3, index - 7, 0x7F],
        ]);
        final pointer = await tester.startGesture(
          tester.getCenter(control(index)),
        );
        await flush(tester);
        final dragStart = payloads().length;
        await pointer.moveBy(const Offset(0, -2.5));
        await flush(tester);
        expect(payloads().length, dragStart);
        await pointer.moveBy(const Offset(0, -3.5));
        await flush(tester);
        expect(payloads().last, [3, index - 7, 1]);
        await pointer.moveBy(const Offset(0, 6));
        await flush(tester);
        expect(payloads().last, [3, index - 7, 0x7F]);
        await pointer.moveBy(const Offset(0, -30));
        await flush(tester);
        expect(payloads().last, [3, index - 7, 5]);
        await pointer.moveBy(const Offset(0, 30));
        await flush(tester);
        expect(payloads().last, [3, index - 7, 0x7B]);
        final largeStart = payloads().length;
        await pointer.moveBy(const Offset(0, -780)); // +130 => 63 + 63 + 4
        await flush(tester);
        await pointer.moveBy(const Offset(0, 780)); // -130 => -64 -64 -2
        await flush(tester);
        expect(payloads().sublist(largeStart), [
          [3, index - 7, 63],
          [3, index - 7, 63],
          [3, index - 7, 4],
          [3, index - 7, 64],
          [3, index - 7, 64],
          [3, index - 7, 126],
        ]);
        await pointer.up();
        await flush(tester);
      }
      await close(tester);
    },
  );

  testWidgets(
    'keyboard holds, arrows, duplicate events and pointer capture/focus cleanup',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      for (var index = 0; index < 9; index++) {
        await tester.tap(control(index));
        await flush(tester);
        final before = payloads().length;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
        await flush(tester);
        expect(payloads().sublist(before), [
          [1, index],
        ]);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await flush(tester);
        expect(payloads().sublist(before), [
          [1, index],
          [2, index],
        ]);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
        await flush(tester);
        if (index >= 4) {
          final turnsStart = payloads().length;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await flush(tester);
          expect(
            payloads().sublist(turnsStart),
            index < 7
                ? [
                    [4, index - 4, 32, 16],
                    [4, index - 4, 64, 16],
                    [4, index - 4, 32, 16],
                    [4, index - 4, 0, 16],
                  ]
                : [
                    [3, index - 7, 1],
                    [3, index - 7, 1],
                    [3, index - 7, 127],
                    [3, index - 7, 127],
                  ],
          );
          expect(cubit.remoteControlState.heldControls, {index});
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
        await flush(tester);
        expect(cubit.remoteControlState.heldControls, isEmpty);
      }
      // Focused button 4 can remain keyboard-held while the encoder wheels.
      await tester.tap(control(3));
      await flush(tester);
      final chordStart = payloads().length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await flush(tester);
      await wheel(tester, 7, -1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await flush(tester);
      expect(payloads().sublist(chordStart), [
        [1, 3],
        [3, 0, 1],
        [2, 3],
      ]);
      for (final index in [0, 7]) {
        final pointer = await tester.startGesture(
          tester.getCenter(control(index)),
          pointer: 100 + index,
        );
        await flush(tester);
        final beforeCancel = payloads().length;
        await pointer.cancel();
        await tester.sendEventToBinding(
          PointerCancelEvent(pointer: 100 + index),
        );
        await flush(tester);
        expect(payloads().sublist(beforeCancel), [
          [2, index],
        ]);
        final outside = await tester.startGesture(
          tester.getCenter(control(index)),
        );
        await flush(tester);
        await outside.moveBy(const Offset(600, 0));
        await outside.up();
        await flush(tester);
        expect(payloads().last, [2, index]);
        expect(cubit.remoteControlState.heldControls, isEmpty);
      }
      await tester.tap(control(3));
      await flush(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await flush(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await flush(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await flush(tester);
      expect(payloads().last, [2, 3]);
      // Button/capture loss followed by cancel and up terminates only once.
      final lost = await tester.startGesture(
        tester.getCenter(control(8)),
        pointer: 200,
      );
      await flush(tester);
      final lostStart = payloads().length;
      await tester.sendEventToBinding(
        PointerMoveEvent(
          pointer: 200,
          position: tester.getCenter(control(8)),
          buttons: 0,
        ),
      );
      await lost.cancel();
      await tester.sendEventToBinding(const PointerUpEvent(pointer: 200));
      await flush(tester);
      expect(payloads().sublist(lostStart), [
        [2, 8],
      ]);
      await close(tester);
      semantics.dispose();
    },
  );

  testWidgets(
    'fold, hide, view focus loss and close clean holds without resetting local pots',
    (tester) async {
      await open(tester);
      await wheel(tester, 4, -1);
      final button = await tester.startGesture(
        tester.getCenter(control(3)),
        pointer: 300,
      );
      await flush(tester);
      final knob = await tester.startGesture(
        tester.getCenter(control(7)),
        pointer: 301,
      );
      await flush(tester);
      final foldStart = payloads().length;
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(payloads().sublist(foldStart), [
        [2, 3],
        [2, 7],
      ]);
      await button.up();
      await knob.cancel();
      await flush(tester);
      expect(payloads().length, foldStart + 2);
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [2080, 2048, 2048]);
      expect(payloads().length, foldStart + 2);

      final held = await tester.startGesture(
        tester.getCenter(control(0)),
        pointer: 302,
      );
      await flush(tester);
      final hideStart = payloads().length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await flush(tester);
      expect(payloads().sublist(hideStart), [
        [2, 0],
      ]);
      expect(cubit.remoteControlState.heldControls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await held.up();
      await flush(tester);

      final focusHeld = await tester.startGesture(
        tester.getCenter(control(8)),
        pointer: 303,
      );
      await flush(tester);
      final focusStart = payloads().length;
      final viewId = tester.view.viewId;
      for (var i = 0; i < 2; i++) {
        tester.binding.handleViewFocusChanged(
          ViewFocusEvent(
            viewId: viewId,
            state: ViewFocusState.unfocused,
            direction: ViewFocusDirection.undefined,
          ),
        );
      }
      await flush(tester);
      expect(payloads().sublist(focusStart), [
        [2, 8],
      ]);
      tester.binding.handleViewFocusChanged(
        ViewFocusEvent(
          viewId: viewId,
          state: ViewFocusState.focused,
          direction: ViewFocusDirection.undefined,
        ),
      );
      await focusHeld.up();
      await flush(tester);
      final closeHeld = await tester.startGesture(
        tester.getCenter(control(1)),
        pointer: 304,
      );
      await flush(tester);
      final closeStart = payloads().length;
      await tester.tap(find.byTooltip('Close overlay'));
      await flush(tester);
      expect(payloads().sublist(closeStart), [
        [2, 1],
      ]);
      await closeHeld.up();
      await tester.runAsync(() => cubit.stopVideoStream());
      await tester.tap(find.byTooltip('Video'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await video.sendFrame();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [2080, 2048, 2048]);
      expect(payloads().length, closeStart + 1);
      await close(tester);
    },
  );

  for (final closeOverlay in [false, true]) {
    testWidgets(
      '${closeOverlay ? 'close' : 'fold'} reports failed cleanup after removing controls without duplicate releases',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final announcements = <Object?>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          (message) async {
            announcements.add(message);
            return null;
          },
        );
        addTearDown(
          () => messenger.setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
        );
        await open(tester);
        final held = await tester.startGesture(
          tester.getCenter(control(3)),
          pointer: 400,
        );
        await flush(tester);
        expect(payloads(), [
          [1, 3],
        ]);
        expect(cubit.remoteControlState.heldControls, {3});

        wire.failRemoteSend = true;
        await tester.tap(
          closeOverlay
              ? find.byTooltip('Close overlay')
              : find.byKey(const ValueKey('video-remote-fold')),
        );
        await flush(tester);
        expect(find.byType(RemoteControlCluster), findsNothing);
        expect(
          find.byType(FloatingVideoOverlay),
          closeOverlay ? findsNothing : findsOneWidget,
        );
        expect(cubit.remoteControlState.heldControls, isEmpty);
        expect(cubit.remoteControlState.sessionId, isNull);
        final error = cubit.remoteControlState.error!;
        expect(error, contains('device release is unknown'));
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(error),
          ),
          findsOneWidget,
        );
        expect(
          announcements.where((message) => message.toString().contains(error)),
          hasLength(1),
        );

        await held.cancel();
        await tester.sendEventToBinding(const PointerUpEvent(pointer: 400));
        await flush(tester);
        expect(payloads(), [
          [1, 3],
        ]);
        verify(
          () => wire.midi.sendData(
            any(
              that: predicate<Uint8List>(
                (packet) =>
                    packet.length > 8 && packet[6] == 0x78 && packet[7] == 2,
              ),
            ),
            deviceId: any(named: 'deviceId'),
          ),
        ).called(1);
        expect(
          announcements.where((message) => message.toString().contains(error)),
          hasLength(1),
        );
        ScaffoldMessenger.of(
          tester.element(find.byType(SynchronizedScreen)),
        ).hideCurrentSnackBar();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(error), findsNothing);
        expect(tester.takeException(), isNull);
        if (closeOverlay) {
          await tester.runAsync(() => cubit.stopVideoStream());
        } else {
          await close(tester);
        }
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'both production hosts retain independent pots; replacement rejects old UI work and resets locally',
    (tester) async {
      await open(tester);
      final screenApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j <= i; j++) {
          await wheel(tester, i + 4, -1);
        }
      }
      expect(cubit.remoteControlState.potValues, [2080, 2112, 2144]);
      final before = payloads().length;
      await tester.tap(find.byTooltip('Close overlay'));
      await flush(tester);
      await tester.runAsync(() => cubit.stopVideoStream());
      final channels = PopupChannelHarness(false);
      await channels.install(cubit);
      addTearDown(channels.dispose);
      await tester.pumpWidget(
        const MaterialApp(home: VideoPopupWindow(windowsNative: false)),
      );
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [2080, 2112, 2144]);
      expect(payloads().length, before);
      await wheel(tester, 5, 1);
      expect(cubit.remoteControlState.potValues, [2080, 2080, 2144]);
      await tester.pumpWidget(const SizedBox.shrink());
      await flush(tester);
      await tester.pumpWidget(screenApp);
      await tester.pump();
      await tester.tap(find.byTooltip('Video'));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await video.sendFrame();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [2080, 2080, 2144]);
      expect(payloads().length, before + 1);
      final held = await tester.startGesture(tester.getCenter(control(7)));
      await flush(tester);
      final old = cubit.remoteControlState.sessionId!;
      final replacedAt = payloads().length;
      cubit.emit(
        (cubit.state as DistingStateSynchronized).copyWith(
          disting: wire.replaceManager(),
        ),
      );
      await flush(tester);
      expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
      await held.moveBy(const Offset(0, -6));
      await held.up();
      await flush(tester);
      await expectLater(cubit.adjustRemotePot(old, 0, 32), throwsStateError);
      expect(payloads().length, replacedAt);
      for (var i = 4; i < 7; i++) {
        expect(
          find.descendant(of: control(i), matching: find.text('Local 2048')),
          findsNothing,
        );
      }
      await close(tester);
    },
  );

  testWidgets(
    'overlay open-host firmware and connection matrix is explanatory and silent when gated',
    (tester) async {
      await open(tester);
      final live = cubit.state as DistingStateSynchronized;
      for (final version in [
        '1.19beta',
        '1.19.0beta',
        '1.19.0',
        '1.20.0',
        '2.0.0',
      ]) {
        cubit.emit(live.copyWith(firmwareVersion: FirmwareVersion(version)));
        await flush(tester);
        final before = payloads().length;
        await wheel(tester, 7, -1);
        expect(payloads().sublist(before), [
          [3, 0, 1],
        ], reason: version);
      }
      for (final state in [
        live.copyWith(firmwareVersion: FirmwareVersion('1.18.9')),
        live.copyWith(firmwareVersion: FirmwareVersion('')),
        live.copyWith(firmwareVersion: FirmwareVersion('unknown')),
        live.copyWith(demo: true),
        live.copyWith(offline: true),
        const DistingState.initial(),
      ]) {
        cubit.emit(state);
        await flush(tester);
        final cluster = tester.widget<RemoteControlCluster>(
          find.byType(RemoteControlCluster),
        );
        expect(cluster.state.available, isFalse);
        expect(cluster.state.unavailableReason, isNotEmpty);
        final before = payloads().length;
        await wheel(tester, 7, -1);
        await tester.tap(control(0));
        await flush(tester);
        expect(payloads().length, before);
      }
      cubit.emit(live);
      await flush(tester);
      await close(tester);
    },
  );

  testWidgets(
    'both overlay fold states keep geometry through pending/frame/unavailable/error updates at constrained sizes',
    (tester) async {
      await open(tester);
      final live = cubit.state as DistingStateSynchronized;
      final fold = find.byKey(const ValueKey('video-remote-fold'));
      for (final size in [const Size(1200, 800), const Size(320, 240)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        for (final expanded in [true, false]) {
          if (!expanded) {
            await tester.tap(fold);
            await flush(tester);
          }
          final screen = tester.getRect(find.byType(FloatingVideoContent));
          final toolbar = tester.getRect(fold);
          final bounds = expanded
              ? [for (var i = 0; i < 9; i++) tester.getRect(control(i))]
              : <Rect>[];
          void stable() {
            expect(tester.getRect(find.byType(FloatingVideoContent)), screen);
            expect(tester.getRect(fold), toolbar);
            if (expanded) {
              expect([
                for (var i = 0; i < 9; i++) tester.getRect(control(i)),
              ], bounds);
            }
          }

          await video.sendFrame();
          await tester.pump();
          stable();
          final session =
              cubit.remoteControlState.sessionId ?? cubit.openRemoteSession();
          final version = wire.manager.requestVersionString();
          await tester.pump();
          final queued = cubit.sendRemoteAction(
            session,
            const RemoteEncoderTurn(0, 1),
          );
          for (var i = 0; i < 2; i++) {
            await tester.pump(const Duration(milliseconds: 5));
          }
          expect(cubit.remoteControlState.pending, isTrue);
          stable();
          wire.incoming.add(
            MidiPacket(
              Uint8List.fromList([
                0xF0,
                0,
                0x21,
                0x27,
                0x6D,
                memoryWireSysExId,
                0x32,
                ...'1.19.0'.codeUnits,
                0,
                0xF7,
              ]),
              0,
              wire.device,
            ),
          );
          await flush(tester);
          await version;
          await queued;
          stable();
          wire.failRemoteSend = true;
          final failure = cubit
              .sendRemoteAction(session, const RemoteEncoderTurn(0, 1))
              .catchError((Object _) {});
          await flush(tester);
          await failure;
          stable();
          wire.failRemoteSend = false;
          ScaffoldMessenger.of(
            tester.element(find.byType(SynchronizedScreen)),
          ).removeCurrentSnackBar();
          cubit.emit(live.copyWith(offline: true));
          await flush(tester);
          stable();
          cubit.emit(live);
          await flush(tester);
          stable();
        }
        await tester.tap(fold);
        await flush(tester);
      }
      await close(tester);
    },
  );

  for (final popupResult in ['success', 'throw', 'unsupported']) {
    testWidgets(
      'production Video prefers native popup and falls back on $popupResult',
      (tester) async {
        await open(tester);
        await tester.tap(find.byTooltip('Close overlay'));
        await flush(tester);
        await tester.runAsync(() => cubit.stopVideoStream());
        await SettingsService().setVideoPopupNativeWindowEnabled(true);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channels = MethodChannel(
          'mixin.one/desktop_multi_window/channels',
        );
        const desktop = MethodChannel('mixin.one/desktop_multi_window');
        var created = 0;
        messenger.setMockMethodCallHandler(channels, (_) async => null);
        messenger.setMockMethodCallHandler(desktop, (call) async {
          if (call.method == 'getAllWindows') return [];
          if (call.method == 'createWindow') {
            created++;
            if (popupResult == 'throw') {
              throw PlatformException(code: 'popup_failed');
            }
            if (popupResult == 'unsupported') throw MissingPluginException();
            return 'popup-preferred';
          }
          return null;
        });
        addTearDown(() async {
          await VideoPopupWindowService.instance.dispose();
          messenger.setMockMethodCallHandler(channels, null);
          messenger.setMockMethodCallHandler(desktop, null);
        });
        await tester.tap(find.byTooltip('Video'));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(created, 1);
        expect(
          find.byType(FloatingVideoOverlay),
          popupResult == 'success' ? findsNothing : findsOneWidget,
        );
        if (popupResult != 'success') await close(tester);
      },
    );
  }

  testWidgets(
    'feedback and frames keep geometry stable; constrained controls remain keyboard-reachable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final announcements = <Object?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (message) async {
          announcements.add(message);
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
      );
      await open(tester);
      final screen = tester.getRect(find.byType(FloatingVideoContent));
      final bounds = [
        for (var index = 0; index < 9; index++) tester.getRect(control(index)),
      ];
      expect(bounds[0].top, lessThan(bounds[1].top));
      expect(bounds[3].top, lessThan(bounds[2].top));
      expect(bounds[4].top, lessThan(bounds[7].top));
      expect(bounds.every((rect) => rect.top >= screen.bottom), isTrue);
      final buttonFace = find
          .descendant(of: control(0), matching: find.byType(CustomPaint))
          .first;
      expect(
        tester.getSize(buttonFace).shortestSide,
        36,
      ); // Prototype face was 18 (+ border).
      final encoder = tester
          .getSemantics(find.bySemanticsLabel('Left encoder'))
          .getSemanticsData();
      expect(encoder.value, 'Relative adjustment, Released');
      expect(encoder.increasedValue, 'Increase');
      final foldSemantics = tester
          .getSemantics(find.byKey(const ValueKey('video-remote-fold')))
          .getSemanticsData();
      expect(foldSemantics.flagsCollection.isExpanded, Tristate.isTrue);
      await video.sendFrame();
      await tester.pump();
      await wheel(tester, 4, -1);
      final pressed = await tester.startGesture(tester.getCenter(control(0)));
      await flush(tester);
      await pressed.up();
      await flush(tester);
      cubit.emit(
        (cubit.state as DistingStateSynchronized).copyWith(offline: true),
      );
      await flush(tester);
      expect(
        find.bySemanticsLabel('Remote control is unavailable in offline mode.'),
        findsOneWidget,
      );
      final silentStart = payloads().length;
      await wheel(tester, 7, -1);
      expect(payloads().length, silentStart);
      expect(tester.getRect(find.byType(FloatingVideoContent)), screen);
      expect([
        for (var index = 0; index < 9; index++) tester.getRect(control(index)),
      ], bounds);
      cubit.emit(
        (cubit.state as DistingStateSynchronized).copyWith(offline: false),
      );
      await flush(tester);
      wire.failRemoteSend = true;
      await wheel(tester, 7, -1);
      expect(
        cubit.remoteControlState.error,
        contains('device state is unknown'),
      );
      expect(payloads().length, silentStart);
      expect(tester.getRect(find.byType(FloatingVideoContent)), screen);
      expect([
        for (var index = 0; index < 9; index++) tester.getRect(control(index)),
      ], bounds);
      expect(announcements.toString(), contains('unavailable in offline mode'));
      expect(announcements.toString(), contains('device state is unknown'));
      wire.failRemoteSend = false;
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('video-remote-fold')))
            .getSemanticsData()
            .flagsCollection
            .isExpanded,
        Tristate.isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('video-remote-fold')));
      await flush(tester);
      tester.view.physicalSize = const Size(320, 240);
      await tester.pump();
      // Actual Tab traversal scrolls the narrow cluster without shrinking targets.
      FocusNode node(int index) => tester
          .widget<Focus>(
            find
                .descendant(of: control(index), matching: find.byType(Focus))
                .first,
          )
          .focusNode!;
      node(0).requestFocus();
      final reached = <int>{};
      for (var attempt = 0; attempt < 24 && reached.length < 9; attempt++) {
        await tester.pump();
        await tester.pump();
        for (var index = 0; index < 9; index++) {
          if (!node(index).hasPrimaryFocus) continue;
          reached.add(index);
          expect(
            tester
                .getRect(control(index))
                .overlaps(const Rect.fromLTWH(0, 0, 320, 240)),
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await flush(tester);
          expect(payloads().last, [2, index]);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      expect(reached, {0, 1, 2, 3, 4, 5, 6, 7, 8});
      await close(tester);
      semantics.dispose();
    },
  );
}
