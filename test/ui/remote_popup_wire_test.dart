import 'dart:ui'
    show
        PointerDeviceKind,
        Tristate,
        ViewFocusEvent,
        ViewFocusState,
        ViewFocusDirection;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/video_popup_remote_contract.dart';
import 'package:nt_helper/ui/video_popup_app.dart';
import 'package:nt_helper/ui/widgets/remote_control_cluster.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/popup_channel_harness.dart';
import '../test_helpers/remote_wire_harness.dart';
import '../test_helpers/video_input_harness.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));
  for (final windows in [false, true]) {
    group(
      windows
          ? 'Windows native MethodChannel'
          : 'desktop_multi_window WindowMethodChannel',
      () {
        late DistingCubit cubit;
        late RemoteWireHarness wire;
        late PopupChannelHarness channels;
        late VideoInputHarness video;
        late DistingStateSynchronized live;
        Future<void> initialize() async {
          SharedPreferences.setMockInitialValues({
            'cpu_monitor_enabled': false,
            'inter_message_delay_ms': 0,
          });
          await SettingsService().init();
          wire = RemoteWireHarness();
          final db = _Database();
          final metadata = _Metadata();
          when(() => db.metadataDao).thenReturn(metadata);
          when(
            () => metadata.hasCachedAlgorithms(),
          ).thenAnswer((_) async => false);
          cubit = DistingCubit(
            db,
            midiCommand: wire.midi,
            isWindowsOverride: true,
          );
          live =
              DistingState.synchronized(
                    disting: wire.manager,
                    distingVersion: '1.19.0',
                    firmwareVersion: FirmwareVersion('1.19.0'),
                    presetName: 'Remote',
                    algorithms: const [],
                    slots: const [],
                    unitStrings: const [],
                  )
                  as DistingStateSynchronized;
          cubit.emit(live);
          channels = PopupChannelHarness(windows);
          await channels.install(cubit);
          video = VideoInputHarness()..install();
        }

        tearDown(() async {
          await channels.dispose();
          if (!cubit.isClosed) await cubit.close();
          await wire.close();
          video.uninstall();
        });
        Finder control(int i) => find.byKey(ValueKey('remote-control-$i'));
        Finder getFold() => find.byKey(const ValueKey('video-remote-fold'));
        List<List<int>> payloads() =>
            wire.remotePackets.map((p) => p.sublist(7, p.length - 1)).toList();
        Future<void> flush(WidgetTester tester, {bool poll = false}) async {
          // Model the ongoing camera feed during long input/geometry scenarios.
          await video.sendFrame();
          if (poll) await tester.pump(const Duration(milliseconds: 200));
          // Drain channel/timer work across a few frames, not 30 repaints.
          // Keep the same 30 ms of virtual time for input coalescing.
          for (var i = 0; i < 3; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
        }

        Future<void> mount(WidgetTester tester) async {
          await tester.pumpWidget(
            MaterialApp(home: VideoPopupWindow(windowsNative: windows)),
          );
          await flush(tester, poll: true);
        }

        Future<void> open(WidgetTester tester) async {
          await initialize();
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = const Size(600, 480);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await flush(tester);
          });
          await mount(tester);
          expect(wire.remotePackets, isEmpty);
          await tester.tap(getFold());
          await flush(tester);
          expect(find.byType(RemoteControlCluster), findsOneWidget);
        }

        Future<void> wheel(WidgetTester tester, int index, double dy) async {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: tester.getCenter(
                find
                    .descendant(
                      of: control(index),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              ),
              scrollDelta: Offset(0, dy),
            ),
          );
          await flush(tester);
        }

        testWidgets(
          'Magic Mouse pan zoom hover and held scrolling send turns without synthetic press or release',
          (tester) async {
            await open(tester);
            tester.binding.handleViewFocusChanged(
              ViewFocusEvent(
                viewId: tester.view.viewId,
                state: ViewFocusState.unfocused,
                direction: ViewFocusDirection.undefined,
              ),
            );
            await flush(tester, poll: true);
            Future<void> smooth(int index, List<double> deltas) async {
              final position = tester.getCenter(
                find
                    .descendant(
                      of: control(index),
                      matching: find.byType(CustomPaint),
                    )
                    .first,
              );
              const pointer = 90;
              await tester.sendEventToBinding(
                PointerPanZoomStartEvent(
                  pointer: pointer,
                  device: 9,
                  position: position,
                ),
              );
              var pan = Offset.zero;
              for (final dy in deltas) {
                pan += Offset(0, dy);
                await tester.sendEventToBinding(
                  PointerPanZoomUpdateEvent(
                    pointer: pointer,
                    device: 9,
                    position: position,
                    pan: pan,
                    panDelta: Offset(0, dy),
                  ),
                );
                await flush(tester);
              }
              await tester.sendEventToBinding(
                PointerPanZoomEndEvent(
                  pointer: pointer,
                  device: 9,
                  position: position,
                ),
              );
              await flush(tester);
            }

            final before = payloads().length;
            await smooth(4, [-2, -1, -2, -1]);
            expect(payloads().sublist(before), [
              [4, 0, 48, 16],
              [4, 0, 72, 16],
              [4, 0, 120, 16],
              [4, 0, 16, 17],
            ]);
            expect(cubit.remoteControlState.heldControls, isEmpty);
            final encoderAt = payloads().length;
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().length, encoderAt);
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().length, encoderAt);
            await smooth(7, [-2, -1, -2, -1]);
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().length, encoderAt);
            await smooth(7, [-2, -1, -2, -1]);
            await smooth(7, [-2]);
            expect(payloads().sublist(encoderAt), [
              [3, 0, 1],
            ]);
            tester.binding.handleViewFocusChanged(
              ViewFocusEvent(
                viewId: tester.view.viewId,
                state: ViewFocusState.focused,
                direction: ViewFocusDirection.undefined,
              ),
            );
            await flush(tester, poll: true);
            final heldAt = payloads().length;
            final held = await tester.startGesture(
              tester.getCenter(control(7)),
              kind: PointerDeviceKind.mouse,
            );
            await flush(tester);
            await held.moveBy(const Offset(0, -12));
            await flush(tester);
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().sublist(heldAt), [
              [1, 7],
            ]);
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().sublist(heldAt), [
              [1, 7],
            ]);
            await smooth(7, [-2, -1, -2, -1]);
            await smooth(7, [-2, -1, -2, -1]);
            expect(payloads().sublist(heldAt), [
              [1, 7],
            ]);
            await smooth(7, [-2, -1, -2, -1]);
            await smooth(7, [-2]);
            expect(cubit.remoteControlState.heldControls, {7});
            await held.up();
            await flush(tester);
            expect(payloads().sublist(heldAt), [
              [1, 7],
              [3, 0, 1],
              [2, 7],
            ]);
            // A below-threshold smooth gesture must not cancel a held mouse push.
            final shortHeld = await tester.startGesture(
              tester.getCenter(control(7)),
              kind: PointerDeviceKind.mouse,
            );
            await flush(tester);
            await smooth(7, [-0.25]);
            expect(cubit.remoteControlState.heldControls, {7});
            await shortHeld.up();
            await flush(tester);
            expect(cubit.remoteControlState.heldControls, isEmpty);
          },
        );

        if (!windows) {
          testWidgets(
            'mouse press routes outside popup bounds and releases once',
            (tester) async {
              await open(tester);
              for (final index in [0, 7]) {
                final before = payloads().length;
                final start = tester.getCenter(control(index));
                final held = await tester.startGesture(
                  start,
                  kind: PointerDeviceKind.mouse,
                );
                await flush(tester);
                await held.moveTo(Offset(900, start.dy));
                await flush(tester);
                expect(cubit.remoteControlState.heldControls, {index});
                await held.up();
                await flush(tester);
                expect(payloads().sublist(before), [
                  [1, index],
                  [2, index],
                ]);
                expect(cubit.remoteControlState.heldControls, isEmpty);
              }
            },
          );

          testWidgets(
            'expanded native minimum width fits all controls at the boundary and survives reload',
            (tester) async {
              await open(tester);
              final minimum =
                  channels.calls
                          .where((call) => call.method == 'setMinimumSize')
                          .last
                          .arguments
                      as Map;
              expect(minimum['width'], 356);
              tester.view.physicalSize = const Size(356, 352);
              await flush(tester);
              final strip = tester.getRect(find.byType(RemoteControlCluster));
              for (var index = 0; index < 9; index++) {
                final target = tester.getRect(control(index));
                expect(target.left, greaterThanOrEqualTo(strip.left + 8));
                expect(target.right, lessThanOrEqualTo(strip.right - 8));
              }
              final callsBefore = channels.calls
                  .where((call) => call.method == 'setMinimumSize')
                  .length;
              final reload = tester.binding.reassembleApplication();
              await tester.pump();
              await flush(tester);
              await reload;
              final minimumCalls = channels.calls
                  .where((call) => call.method == 'setMinimumSize')
                  .toList();
              expect(minimumCalls.length, greaterThan(callsBefore));
              expect((minimumCalls.last.arguments as Map)['width'], 356);
            },
          );
        }

        testWidgets(
          'hover mouse wheel turns unfocused pots without push; held wheel preserves press and release',
          (tester) async {
            await open(tester);
            tester.binding.handleViewFocusChanged(
              ViewFocusEvent(
                viewId: tester.view.viewId,
                state: ViewFocusState.unfocused,
                direction: ViewFocusDirection.undefined,
              ),
            );
            await flush(tester, poll: true);
            expect(cubit.remoteControlState.heldControls, isEmpty);
            final before = payloads().length;
            for (var index = 4; index < 7; index++) {
              await wheel(tester, index, -12);
            }
            expect(payloads().sublist(before), [
              [4, 0, 0x20, 0x10],
              [4, 1, 0x20, 0x10],
              [4, 2, 0x20, 0x10],
            ]);
            expect(cubit.remoteControlState.heldControls, isEmpty);
            tester.binding.handleViewFocusChanged(
              ViewFocusEvent(
                viewId: tester.view.viewId,
                state: ViewFocusState.focused,
                direction: ViewFocusDirection.undefined,
              ),
            );
            await flush(tester, poll: true);
            final heldAt = payloads().length;
            final held = await tester.startGesture(
              tester.getCenter(control(4)),
              kind: PointerDeviceKind.mouse,
            );
            await flush(tester);
            await wheel(tester, 4, -12);
            expect(cubit.remoteControlState.heldControls, {4});
            await held.up();
            await flush(tester);
            expect(payloads().sublist(heldAt), [
              [1, 4],
              [4, 0, 0x40, 0x10],
              [2, 4],
            ]);
            expect(cubit.remoteControlState.heldControls, isEmpty);
          },
        );

        testWidgets(
          'real UI actions/results, independent pot retention, host changes and reconnect isolation',
          (tester) async {
            await open(tester);
            for (var i = 0; i < 3; i++) {
              for (var j = 0; j <= i; j++) {
                await wheel(tester, i + 4, -1);
              }
            }
            expect(cubit.remoteControlState.potValues, [2080, 2112, 2144]);
            final old = Map<String, dynamic>.from(channels.lastAction!);
            final before = payloads().length;
            await tester.tap(getFold());
            await flush(tester);
            await tester.tap(getFold());
            await flush(tester);
            expect(cubit.remoteControlState.potValues, [2080, 2112, 2144]);
            await tester.pumpWidget(const SizedBox.shrink());
            await flush(tester);
            // Another host uses the same main connection and independent retained values.
            final overlay = cubit.openRemoteSession();
            final adjustment = cubit.adjustRemotePot(overlay, 1, -32);
            await flush(tester);
            await adjustment;
            final cleanup = cubit.closeRemoteSession(overlay);
            await flush(tester);
            await cleanup;
            await mount(tester);
            await tester.tap(getFold());
            await flush(tester);
            expect(cubit.remoteControlState.potValues, [2080, 2080, 2144]);
            expect(payloads().length, before + 1);
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.action, old),
              throwsA(isA<PlatformException>()),
            );
            final oldCurrent = Map<String, dynamic>.from(channels.lastAction!);
            cubit.emit(live.copyWith(disting: wire.replaceManager()));
            await flush(tester, poll: true);
            expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
            for (var i = 4; i < 7; i++) {
              expect(
                find.descendant(
                  of: control(i),
                  matching: find.text('Local 2048'),
                ),
                findsNothing,
              );
            }
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.action, oldCurrent),
              throwsA(isA<PlatformException>()),
            );
            expect(payloads().length, before + 1);
            await wheel(tester, 4, -1);
            expect(payloads().last, [4, 0, 32, 16]);
          },
        );

        testWidgets(
          'nine pushes and pointer/key/capture/focus/fold/hide/close termination produce single releases',
          (tester) async {
            final semantics = tester.ensureSemantics();
            await open(tester);
            for (var index = 0; index < 9; index++) {
              final before = payloads().length;
              final held = await tester.startGesture(
                tester.getCenter(control(index)),
                pointer: 10 + index,
              );
              await flush(tester);
              expect(
                find.descendant(
                  of: control(index),
                  matching: find.text('Pressed'),
                ),
                findsNothing,
              );
              await held.moveBy(const Offset(700, 0));
              await held.up();
              await flush(tester);
              expect(payloads().sublist(before), [
                [1, index],
                [2, index],
              ]);
              await tester.tap(control(index));
              await flush(tester);
              final keys = payloads().length;
              await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
              await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
              await flush(tester);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
              await flush(tester);
              expect(payloads().sublist(keys), [
                [1, index],
                [2, index],
              ]);
            }
            for (final index in [0, 7]) {
              for (final end in [
                'cancel',
                'capture',
                'focus',
                'fold',
                'hide',
                'close',
              ]) {
                final held = await tester.startGesture(
                  tester.getCenter(control(index)),
                  pointer: 100,
                );
                await flush(tester);
                final before = payloads().length;
                switch (end) {
                  case 'cancel':
                    await held.cancel();
                  case 'capture':
                    await tester.sendEventToBinding(
                      PointerMoveEvent(
                        pointer: 100,
                        position: tester.getCenter(control(index)),
                        buttons: 0,
                      ),
                    );
                    await held.cancel();
                  case 'focus':
                    tester.binding.handleViewFocusChanged(
                      ViewFocusEvent(
                        viewId: tester.view.viewId,
                        state: ViewFocusState.unfocused,
                        direction: ViewFocusDirection.undefined,
                      ),
                    );
                  case 'fold':
                    await tester.tap(getFold());
                  case 'hide':
                    tester.binding.handleAppLifecycleStateChanged(
                      AppLifecycleState.hidden,
                    );
                  case 'close':
                    await tester.pumpWidget(const SizedBox.shrink());
                }
                await flush(tester);
                expect(payloads().sublist(before), [
                  [2, index],
                ], reason: end);
                expect(cubit.remoteControlState.heldControls, isEmpty);
                if (end == 'cancel' || end == 'capture') {
                  await tester.sendEventToBinding(
                    const PointerUpEvent(pointer: 100),
                  );
                } else {
                  await held.up();
                }
                await flush(tester);
                expect(payloads().length, before + 1);
                switch (end) {
                  case 'focus':
                    tester.binding.handleViewFocusChanged(
                      ViewFocusEvent(
                        viewId: tester.view.viewId,
                        state: ViewFocusState.focused,
                        direction: ViewFocusDirection.undefined,
                      ),
                    );
                  case 'fold':
                    await tester.tap(getFold());
                  case 'hide':
                    tester.binding.handleAppLifecycleStateChanged(
                      AppLifecycleState.resumed,
                    );
                  case 'close':
                    await mount(tester);
                    await tester.tap(getFold());
                }
                await flush(tester, poll: true);
              }
            }
            // Backend-specific native/window notifications also terminate the host.
            final held = await tester.startGesture(
              tester.getCenter(control(3)),
            );
            await flush(tester);
            final notification = windows
                ? channels.lifecycle('hide')
                : channels.destroyed();
            await flush(tester);
            await notification;
            expect(payloads().last, [2, 3]);
            expect(cubit.remoteControlState.heldControls, isEmpty);
            await held.up();
            semantics.dispose();
          },
        );

        testWidgets(
          'complete firmware/mode matrix updates the open host and invalid payloads never write',
          (tester) async {
            await open(tester);
            for (final version in [
              '1.19beta',
              '1.19.0beta',
              '1.19.0',
              '1.20.0',
              '2.0.0',
            ]) {
              cubit.emit(
                live.copyWith(firmwareVersion: FirmwareVersion(version)),
              );
              await flush(tester, poll: true);
              final before = payloads().length;
              await wheel(tester, 7, -1);
              expect(payloads().sublist(before), [
                [3, 0, 1],
              ], reason: version);
            }
            final old = Map<String, dynamic>.from(channels.lastAction!);
            for (final state in [
              live.copyWith(firmwareVersion: FirmwareVersion('1.18.9')),
              live.copyWith(firmwareVersion: FirmwareVersion('')),
              live.copyWith(firmwareVersion: FirmwareVersion('unknown')),
              live.copyWith(demo: true),
              live.copyWith(offline: true),
              const DistingState.initial(),
            ]) {
              cubit.emit(state);
              await flush(tester, poll: true);
              final cluster = tester.widget<RemoteControlCluster>(
                find.byType(RemoteControlCluster),
              );
              expect(cluster.state.available, isFalse);
              expect(cluster.state.unavailableReason, isNotEmpty);
              final before = payloads().length;
              await wheel(tester, 7, -1);
              await tester.tap(control(0));
              await flush(tester);
              await expectLater(
                channels.toMain(VideoPopupRemoteContract.action, old),
                throwsA(isA<PlatformException>()),
              );
              expect(payloads().length, before);
            }
            cubit.emit(live);
            await flush(tester, poll: true);
            for (final action in [
              null,
              {'type': 'push', 'index': 9},
              {'type': 'pot', 'index': 0, 'value': 4096},
              {'type': 'pot', 'index': 0, 'value': 1.0},
              {'type': 'encoder', 'index': 2, 'value': 1},
              {'type': 'unknown', 'index': 0},
            ]) {
              await expectLater(
                channels.toMain(VideoPopupRemoteContract.action, {
                  ...old,
                  'action': action,
                }),
                throwsA(isA<PlatformException>()),
              );
            }
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.action, 'invalid'),
              throwsA(isA<PlatformException>()),
            );
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.read, {'hostId': ''}),
              throwsA(isA<PlatformException>()),
            );
          },
        );

        testWidgets(
          'frame/value/pressed/unavailable/pending/error geometry, reference shape, semantics and hidden-toolbar keyboard access',
          (tester) async {
            final semantics = tester.ensureSemantics();
            final announcements = <Object?>[];
            channels.messenger.setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              (m) async {
                announcements.add(m);
                return null;
              },
            );
            addTearDown(
              () => channels.messenger.setMockDecodedMessageHandler<Object?>(
                SystemChannels.accessibility,
                null,
              ),
            );
            await open(tester);
            for (final size in [
              const Size(1200, 480),
              const Size(600, 480),
              const Size(256, 180),
            ]) {
              tester.view.physicalSize = size;
              await tester.pump();
              for (final expanded in [true, false]) {
                if (!expanded) {
                  await tester.tap(getFold());
                  await flush(tester);
                }
                final screen = tester.getRect(
                  find.byKey(const ValueKey('popup-video-bounds')),
                );
                final bounds = expanded
                    ? [for (var i = 0; i < 9; i++) tester.getRect(control(i))]
                    : <Rect>[];
                if (expanded) {
                  expect(bounds[0].top, lessThan(bounds[1].top));
                  expect(bounds[3].top, lessThan(bounds[2].top));
                  expect(bounds[4].top, lessThan(bounds[7].top));
                  expect(bounds.every((r) => r.top >= screen.bottom), isTrue);
                  // Frozen prototype: tactile face 18px + 2px border; production 36px,
                  // ridged pots above unmarked encoders, inset lower side buttons.
                  expect(
                    tester
                        .getSize(
                          find
                              .descendant(
                                of: control(0),
                                matching: find.byType(CustomPaint),
                              )
                              .first,
                        )
                        .width,
                    36,
                  );
                  final clusterBounds = tester.getRect(
                    find.byType(RemoteControlCluster),
                  );
                  expect(clusterBounds.width, size.width);
                  // Wider video windows must not enlarge or spread the group.
                  expect(bounds[4].width, 76);
                  expect(bounds[5].left - bounds[4].left, 76);
                  expect(bounds[6].left - bounds[5].left, 76);
                  if (size.width >= 356) {
                    expect(
                      (bounds[0].left + bounds[3].right) / 2,
                      closeTo(clusterBounds.center.dx, 0.01),
                    );
                  }
                  expect(clusterBounds.height, lessThanOrEqualTo(168));
                  expect(bounds[4].top - clusterBounds.top, closeTo(12, 0.01));
                  final face = tester.getRect(
                    find
                        .descendant(
                          of: control(4),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  );
                  expect(face.width, closeTo(56, 0.01));
                  expect(find.text('NT remote controls'), findsNothing);
                  expect(
                    find.text('Local inputs, not hardware positions'),
                    findsNothing,
                  );
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
                  for (final name in names) {
                    expect(find.bySemanticsLabel(name), findsOneWidget);
                  }
                  expect(
                    tester
                        .getSemantics(find.bySemanticsLabel('Left pot'))
                        .getSemanticsData()
                        .value,
                    'Released',
                  );
                  expect(
                    tester
                        .getSemantics(find.bySemanticsLabel('Left encoder'))
                        .getSemanticsData()
                        .value,
                    contains('Relative adjustment'),
                  );
                  expect(find.text('Hold'), findsNothing);
                  expect(find.byType(Slider), findsNothing);
                }
                await video.sendFrame();
                await flush(tester);
                cubit.emit(live.copyWith(offline: true));
                await flush(tester, poll: true);
                expect(
                  tester.getRect(
                    find.byKey(const ValueKey('popup-video-bounds')),
                  ),
                  screen,
                );
                if (expanded) {
                  expect([
                    for (var i = 0; i < 9; i++) tester.getRect(control(i)),
                  ], bounds);
                }
                cubit.emit(live);
                await flush(tester, poll: true);
                if (expanded && size.width > 300) {
                  final held = await tester.startGesture(
                    tester.getCenter(control(0)),
                  );
                  await tester.pump();
                  expect(tester.getRect(control(0)), bounds[0]);
                  await flush(tester);
                  await held.up();
                  await flush(tester);
                  await wheel(tester, 4, -1);
                  expect(
                    tester.getRect(
                      find.byKey(const ValueKey('popup-video-bounds')),
                    ),
                    screen,
                  );
                  wire.failRemoteSend = true;
                  await wheel(tester, 7, -1);
                  expect(
                    announcements.toString(),
                    contains('device state is unknown'),
                  );
                  expect(
                    tester.getRect(
                      find.byKey(const ValueKey('popup-video-bounds')),
                    ),
                    screen,
                  );
                  expect([
                    for (var i = 0; i < 9; i++) tester.getRect(control(i)),
                  ], bounds);
                  wire.failRemoteSend = false;
                }
                if (expanded && size.width <= 300) {
                  final session = cubit.remoteControlState.sessionId!;
                  final adjustment = cubit.adjustRemotePot(session, 0, 32);
                  await flush(tester, poll: true);
                  await adjustment;
                  wire.failRemoteSend = true;
                  final failure = cubit
                      .sendRemoteAction(session, const RemoteEncoderTurn(0, 1))
                      .catchError((Object _) {});
                  await flush(tester, poll: true);
                  await failure;
                  expect(
                    tester.getRect(
                      find.byKey(const ValueKey('popup-video-bounds')),
                    ),
                    screen,
                  );
                  expect([
                    for (var i = 0; i < 9; i++) tester.getRect(control(i)),
                  ], bounds);
                  wire.failRemoteSend = false;
                  ScaffoldMessenger.of(
                    tester.element(find.byType(VideoPopupWindow)),
                  ).removeCurrentSnackBar();
                }
                expect(
                  tester
                      .getSemantics(getFold())
                      .getSemanticsData()
                      .flagsCollection
                      .isExpanded,
                  expanded ? Tristate.isTrue : Tristate.isFalse,
                );
              }
              await tester.tap(getFold());
              await flush(tester);
            }
            // Tab reaches every control and scrolls constrained contents into view.
            FocusNode node(int i) => tester
                .widget<Focus>(
                  find
                      .descendant(of: control(i), matching: find.byType(Focus))
                      .first,
                )
                .focusNode!;
            node(0).requestFocus();
            final reached = <int>{};
            for (var n = 0; n < 24 && reached.length < 9; n++) {
              await flush(tester);
              for (var i = 0; i < 9; i++) {
                if (node(i).hasPrimaryFocus) reached.add(i);
              }
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            }
            expect(reached, {0, 1, 2, 3, 4, 5, 6, 7, 8});
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump(const Duration(seconds: 11));
            await flush(tester);
            var foldReached = false;
            for (var i = 0; i < 18 && !foldReached; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await flush(tester);
              foldReached = Focus.of(
                tester.element(find.text('Remote')),
              ).hasPrimaryFocus;
            }
            expect(foldReached, isTrue);
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.getRect(getFold()).top, greaterThanOrEqualTo(0));
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await flush(tester);
            expect(find.byType(RemoteControlCluster), findsNothing);
            expect(tester.takeException(), isNull);
            expect(
              announcements.toString(),
              contains('unavailable in offline mode'),
            );
            semantics.dispose();
          },
        );

        testWidgets(
          'backend close, unavailable main, pinning/display actions and original video path',
          (tester) async {
            await open(tester);
            await video.sendFrame();
            await flush(tester);
            expect(
              find.byKey(const ValueKey('video_popup_frame')),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Keep video window on top'));
            await flush(tester);
            expect(SettingsService().videoPopupAlwaysOnTop, isTrue);
            expect(
              channels.calls.any((c) => c.method == 'setAlwaysOnTop'),
              isTrue,
            );
            await tester.tap(find.byTooltip('Algorithm UI'));
            await flush(tester);
            expect(
              wire.sentPackets.any(
                (p) =>
                    p[6] == DistingNTRequestMessageType.setDisplayMode.value &&
                    p[7] == DisplayMode.algorithmUI.value,
              ),
              isTrue,
            );
            if (windows) {
              channels.openResult = false;
              expect(await channels.service.open(cubit), isFalse);
            }
            final held = await tester.startGesture(
              tester.getCenter(control(3)),
            );
            await flush(tester);
            final host = channels.lastAction!['hostId'];
            final close = channels.lifecycle('close');
            await flush(tester);
            await close;
            expect(payloads(), [
              [1, 3],
              [2, 3],
            ]);
            await held.up();
            await flush(tester);
            await tester.runAsync(() => cubit.close());
            await flush(tester);
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.read, {'hostId': host}),
              throwsA(isA<PlatformException>()),
            );
            expect(payloads(), [
              [1, 3],
              [2, 3],
            ]);
          },
        );

        testWidgets(
          'pending input geometry and late old-connection results cannot overwrite the replacement host',
          (tester) async {
            await open(tester);
            final screen = tester.getRect(
              find.byKey(const ValueKey('popup-video-bounds')),
            );
            final bounds = [
              for (var i = 0; i < 9; i++) tester.getRect(control(i)),
            ];
            final version = wire.manager.requestVersionString();
            await flush(tester);
            final held = await tester.startGesture(
              tester.getCenter(control(7)),
            );
            await flush(tester, poll: true);
            expect(
              tester
                  .widget<RemoteControlCluster>(
                    find.byType(RemoteControlCluster),
                  )
                  .state
                  .pending,
              isTrue,
            );
            expect(
              tester.getRect(find.byKey(const ValueKey('popup-video-bounds'))),
              screen,
            );
            expect([
              for (var i = 0; i < 9; i++) tester.getRect(control(i)),
            ], bounds);
            final oldAction = Map<String, dynamic>.from(channels.lastAction!);
            cubit.emit(live.copyWith(disting: wire.replaceManager()));
            await flush(tester, poll: true);
            wire.injectVersion();
            await flush(tester);
            await version;
            await held.moveBy(const Offset(0, -6));
            await held.up();
            await flush(tester);
            expect(cubit.remoteControlState.error, isNull);
            expect(cubit.remoteControlState.potValues, [2048, 2048, 2048]);
            expect(wire.remotePackets, isEmpty);
            await expectLater(
              channels.toMain(VideoPopupRemoteContract.action, oldAction),
              throwsA(isA<PlatformException>()),
            );
            await wheel(tester, 7, -1);
            expect(payloads(), [
              [3, 0, 1],
            ]);
          },
        );

        testWidgets(
          'channel failure clears holds, announces unknown state and disposed callbacks cannot send',
          (tester) async {
            await open(tester);
            final held = await tester.startGesture(
              tester.getCenter(control(7)),
            );
            await flush(tester);
            channels.failChannel = true;
            await held.moveBy(const Offset(0, -6));
            await flush(tester);
            expect(find.textContaining('Remote input failed'), findsWidgets);
            expect(
              tester
                  .widget<RemoteControlCluster>(
                    find.byType(RemoteControlCluster),
                  )
                  .state
                  .heldControls,
              isEmpty,
            );
            channels.failChannel = false;
            await tester.tap(getFold());
            await flush(tester);
            expect(payloads(), [
              [1, 7],
              [2, 7],
            ]);
            await tester.pumpWidget(const SizedBox.shrink());
            await flush(tester);
            final before = payloads().length;
            await held.up();
            await tester.pump(const Duration(seconds: 1));
            expect(payloads().length, before);
            expect(tester.takeException(), isNull);
          },
        );
      },
    );
  }
}
