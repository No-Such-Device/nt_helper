import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_update_provider.dart';
import 'package:nt_helper/services/firmware_version_service.dart';

import '../test_helpers/ipad_firmware.dart';

void main() {
  late FirmwareVersionService service;
  setUp(() => service = FirmwareVersionService());
  tearDown(() => service.dispose());

  test(
    'iPad progress remains monotonic when loader upload precedes flashloader detection',
    () async {
      final session = ControlledIpadSession();
      addTearDown(session.dispose);
      final provider = IpadFirmwareUpdateProvider(session: session);
      final progress = [
        for (final stage in [
          FlashStage.sdpConnect,
          FlashStage.sdpUpload,
          FlashStage.blCheck,
          FlashStage.configure,
          FlashStage.write,
          FlashStage.reset,
          FlashStage.programmingComplete,
        ])
          for (final percent in [0, 100])
            provider.overallPercent(
              FlashProgress(stage: stage, percent: percent, message: ''),
            ),
      ];
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(progress.last, 100);
    },
  );

  test(
    'local beta source snapshots validated bytes without downloading a stable release',
    () async {
      var bytes = ipadPackageBytes();
      final provider = FileFirmwareProvider(
        versionService: service,
        read: (_) async => bytes,
      );
      final prepared = await provider.prepareForIpad(
        '/files/distingNT_1.20.0beta2.zip',
      );
      addTearDown(
        () => File(prepared.packagePath).parent.delete(recursive: true),
      );
      bytes = [0];
      expect(prepared.version, '1.20.0beta2');
      expect(prepared.loader, ipadImage());
      expect(prepared.application, ipadImage(application: true));
      expect(
        await File(prepared.packagePath).readAsBytes(),
        ipadPackageBytes(),
      );
      expect(
        FirmwareVersionService.matchesApplicationVersion(
          'v1.20.0beta2\n2026-11-04',
          prepared.version,
        ),
        isTrue,
      );
      expect(
        FirmwareVersionService.matchesApplicationVersion(
          '1.20.0',
          prepared.version,
        ),
        isFalse,
      );
      expect(
        FirmwareVersionService.matchesApplicationVersion(
          '1.20.0beta3',
          prepared.version,
        ),
        isFalse,
      );
    },
  );

  test('unversioned local ZIP remains explicitly unverified', () async {
    final provider = FileFirmwareProvider(
      versionService: service,
      read: (_) async => ipadPackageBytes(),
    );
    final prepared = await provider.prepareForIpad('/files/firmware.zip');
    addTearDown(
      () => File(prepared.packagePath).parent.delete(recursive: true),
    );
    expect(prepared.version, 'local');
    expect(
      FirmwareVersionService.matchesApplicationVersion(
        '1.20.0',
        prepared.version,
      ),
      isFalse,
    );
  });

  for (final key in ['duplicate MANIFEST.json', 'signed application CSF']) {
    test('local beta source still rejects $key before USB handoff', () async {
      final provider = FileFirmwareProvider(
        versionService: service,
        read: (_) async => invalidIpadPackages()[key],
      );
      await expectLater(
        provider.prepareForIpad('/files/1.20.0beta2.zip'),
        throwsA(isA<FirmwareDownloadException>()),
      );
    });
  }

  test(
    'downloaded release validation does not silently opt into local beta policy',
    () {
      final beta = FirmwareRelease(
        version: '1.20.0beta2',
        releaseDate: DateTime(2026),
        changelog: const [],
        downloadUrl: '',
      );
      expect(
        () => FirmwareVersionService.validateIpadPackage(
          beta,
          '/beta.zip',
          ipadPackageBytes(),
        ),
        throwsA(isA<FirmwareDownloadException>()),
      );
    },
  );
}
