import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/ui/firmware/firmware_update_screen.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_page.dart';

void main() {
  group('Semantics announcements', () {
    late List<Object?> accessibilityMessages;

    setUp(() {
      accessibilityMessages = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            Object? message,
          ) async {
            accessibilityMessages.add(message);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          );
    });

    testWidgets('metadata sync announces progress, success, and failure', (
      tester,
    ) async {
      final wrapper = _TestMetadataSyncCubitWrapper(
        const MetadataSyncState.idle(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataSyncAnnouncementListener(
              bloc: wrapper.cubit,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      wrapper.push(
        const MetadataSyncState.syncingMetadata(
          progress: 0.3,
          mainMessage: 'Syncing algorithms',
          subMessage: 'Step 3 of 10',
        ),
      );
      await tester.pump();

      wrapper.push(const MetadataSyncState.metadataSyncSuccess('Done'));
      await tester.pump();

      wrapper.push(
        const MetadataSyncState.metadataSyncFailure('Network timeout'),
      );
      await tester.pump();

      final payload = accessibilityMessages.map((m) => m.toString()).join('\n');
      expect(payload, contains('Syncing algorithms'));
      expect(payload, contains('Metadata sync complete'));
      expect(payload, contains('Metadata sync failed: Network timeout'));

      await wrapper.close();
    });

    testWidgets('firmware update announces progress, success, and error', (
      tester,
    ) async {
      final wrapper = _TestFirmwareUpdateCubitWrapper(
        const FirmwareUpdateState.initial(currentVersion: '1.0.0'),
      );
      final release = FirmwareRelease(
        version: '1.2.0',
        releaseDate: DateTime(2026, 1, 1),
        changelog: const ['Fixes'],
        downloadUrl: 'https://example.com/fw.zip',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FirmwareUpdateAnnouncementListener(
              bloc: wrapper.cubit,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      wrapper.push(
        FirmwareUpdateState.downloading(version: release, progress: 0.42),
      );
      await tester.pump();

      wrapper.push(const FirmwareUpdateState.success(newVersion: '1.2.0'));
      await tester.pump();

      wrapper.push(
        const FirmwareUpdateState.verifyingMidi(newVersion: '1.2.0'),
      );
      await tester.pump();

      wrapper.push(
        const FirmwareUpdateState.midiRecoveryRequired(
          newVersion: '1.2.0',
          isWindows: true,
        ),
      );
      await tester.pump();

      wrapper.push(
        const FirmwareUpdateState.error(message: 'Checksum mismatch'),
      );
      await tester.pump();

      final payload = accessibilityMessages.map((m) => m.toString()).join('\n');
      expect(payload, contains('Downloading firmware: 42%'));
      expect(payload, contains('Firmware update complete'));
      expect(payload, contains('Waiting for Disting NT'));
      expect(payload, contains('did not return to MIDI'));
      expect(payload, contains('Firmware update error: Checksum mismatch'));

      await wrapper.close();
    });
  });
}

class _MockMetadataSyncCubit extends MockCubit<MetadataSyncState>
    implements MetadataSyncCubit {}

class _TestMetadataSyncCubitWrapper {
  final _MockMetadataSyncCubit _mock = _MockMetadataSyncCubit();
  final _controller = StreamController<MetadataSyncState>.broadcast();

  _TestMetadataSyncCubitWrapper(MetadataSyncState initialState) {
    whenListen(_mock, _controller.stream, initialState: initialState);
  }

  MetadataSyncCubit get cubit => _mock;

  void push(MetadataSyncState state) {
    _controller.add(state);
  }

  Future<void> close() async {
    await _controller.close();
    await _mock.close();
  }
}

class _MockFirmwareUpdateCubit extends MockCubit<FirmwareUpdateState>
    implements FirmwareUpdateCubit {}

class _TestFirmwareUpdateCubitWrapper {
  final _MockFirmwareUpdateCubit _mock = _MockFirmwareUpdateCubit();
  final _controller = StreamController<FirmwareUpdateState>.broadcast();

  _TestFirmwareUpdateCubitWrapper(FirmwareUpdateState initialState) {
    whenListen(_mock, _controller.stream, initialState: initialState);
  }

  FirmwareUpdateCubit get cubit => _mock;

  void push(FirmwareUpdateState state) {
    _controller.add(state);
  }

  Future<void> close() async {
    await _controller.close();
    await _mock.close();
  }
}
