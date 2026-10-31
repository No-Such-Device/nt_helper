import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/video_frame_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/video_popup_app.dart';
import 'package:nt_helper/ui/widgets/floating_video_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/popup_channel_harness.dart';
import '../test_helpers/remote_wire_harness.dart';
import '../test_helpers/video_input_harness.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(Uint8List(0)));

  for (final host in ['overlay', 'desktop popup', 'Windows popup']) {
    testWidgets('$host uses refreshed SysEx screenshots when USB video is off', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'cpu_monitor_enabled': false});
      await SettingsService().init();
      final video = VideoInputHarness()..available = false;
      video.install();
      final wire = RemoteWireHarness();
      final db = _Database();
      final metadata = _Metadata();
      when(() => db.metadataDao).thenReturn(metadata);
      when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
      final manager = _Manager();
      final pixels = img.Image(width: 266, height: 74)
        ..setPixelRgb(5, 5, 0, 255, 255);
      final png = Uint8List.fromList(img.encodePng(pixels));
      var screenshots = 0;
      when(() => manager.requestWake()).thenAnswer((_) async {});
      when(() => manager.encodeTakeScreenshot()).thenAnswer((_) async {
        screenshots++;
        return png;
      });
      final cubit = DistingCubit(
        db,
        midiCommand: wire.midi,
        isWindowsOverride: true,
      );
      cubit.emit(
        DistingState.synchronized(
          disting: manager,
          distingVersion: '1.19.0',
          firmwareVersion: FirmwareVersion('1.19.0'),
          presetName: 'Fallback',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
        ),
      );
      final frameCubit = VideoFrameCubit();
      PopupChannelHarness? channels;
      OverlayEntry? entry;
      if (host == 'overlay') {
        entry = OverlayEntry(
          builder: (_) => FloatingVideoOverlay(
            overlayEntry: entry!,
            cubit: cubit,
            videoFrameCubit: frameCubit,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: Overlay(initialEntries: [entry])),
          ),
        );
      } else {
        channels = PopupChannelHarness(host == 'Windows popup');
        await channels.install(cubit);
        await tester.pumpWidget(
          MaterialApp(
            home: VideoPopupWindow(windowsNative: host == 'Windows popup'),
          ),
        );
      }
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        // Overlay disposal owns its initial entries.
        await channels?.dispose();
        await frameCubit.close();
        await cubit.close();
        await wire.close();
        video.uninstall();
      });
      final semantics = tester.ensureSemantics();
      try {
        final content = host == 'overlay'
            ? find.byType(FloatingVideoContent)
            : find.byType(VideoPopupContent);
        // Let the overlay's existing post-layout positioning finish first.
        await tester.pump();
        final before = tester.getRect(content);
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(screenshots, greaterThanOrEqualTo(1));
        final frame = find.byKey(
          ValueKey(host == 'overlay' ? 'stable_frame' : 'video_popup_frame'),
        );
        expect(frame, findsOneWidget);
        expect((tester.widget<Image>(frame).image as MemoryImage).bytes, png);
        expect(tester.getRect(content), before);
        expect(
          find.bySemanticsLabel(
            'Disting NT display. Long press to copy frame to clipboard.',
          ),
          findsOneWidget,
        );
        final firstCount = screenshots;
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(screenshots, greaterThan(firstCount));
        expect(tester.getRect(content), before);

        // MCP remains independent of the missing camera and uses the same wake/capture authority.
        final registry = ToolRegistry(cubit);
        final response = jsonDecode(
          await registry.executeTool('show_screen', {}),
        );
        expect(response['type'], 'image/png');
        expect(response['data'], base64Encode(png));
        await registry.dispose();
        verify(() => manager.requestWake()).called(screenshots);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final stoppedCount = screenshots;
        await tester.pump(const Duration(seconds: 3));
        expect(screenshots, stoppedCount);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
