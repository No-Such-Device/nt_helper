import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/services/ipad_firmware_session.dart';
import 'package:path/path.dart' as path;

/// Backend selection belongs at composition time, not in the firmware views.
sealed class FirmwareUpdateProvider {
  const FirmwareUpdateProvider();

  Map<FlashStage, (int, int)> get stageRanges => const {
    FlashStage.sdpConnect: (0, 5),
    FlashStage.blCheck: (5, 10),
    FlashStage.sdpUpload: (10, 40),
    FlashStage.configure: (40, 50),
    FlashStage.write: (50, 95),
    FlashStage.reset: (95, 100),
    FlashStage.complete: (100, 100),
    FlashStage.programmingComplete: (100, 100),
  };

  int overallPercent(FlashProgress progress) {
    final (start, end) = stageRanges[progress.stage]!;
    return (start + (end - start) * progress.percent / 100).round();
  }
}

final class DesktopFirmwareUpdateProvider extends FirmwareUpdateProvider {
  final FlashToolManager toolManager;
  final FlashToolBridge bridge;

  const DesktopFirmwareUpdateProvider({
    required this.toolManager,
    required this.bridge,
  });
}

final class IpadFirmwareUpdateProvider extends FirmwareUpdateProvider {
  final IpadFirmwareSession session;

  const IpadFirmwareUpdateProvider({required this.session});

  @override
  Map<FlashStage, (int, int)> get stageRanges => {
    ...super.stageRanges,
    FlashStage.sdpUpload: (5, 40),
    FlashStage.blCheck: (40, 45),
    FlashStage.configure: (45, 50),
  };
}

/// A local ZIP source can feed either backend; it is not a USB transport.
final class FileFirmwareProvider {
  final FirmwareVersionService versionService;
  final Future<List<int>?> Function(String) read;

  const FileFirmwareProvider({
    required this.versionService,
    required this.read,
  });

  Future<PreparedFirmwarePackage> prepareForIpad(String filePath) async {
    final bytes = await read(filePath);
    if (bytes == null) {
      throw const FirmwareDownloadException('Selected file does not exist');
    }
    final version =
        RegExp(r'(\d+\.\d+\.\d+(?:[-.]?beta\d*)?)', caseSensitive: false)
            .firstMatch(path.basenameWithoutExtension(filePath))
            ?.group(1)
            ?.toLowerCase();
    final release = FirmwareRelease(
      version: version ?? 'local',
      releaseDate: DateTime.fromMillisecondsSinceEpoch(0),
      changelog: const [],
      downloadUrl: '',
    );
    return versionService.prepareIpadPackageBytes(
      release,
      bytes,
      allowLocalFile: true,
    );
  }
}
