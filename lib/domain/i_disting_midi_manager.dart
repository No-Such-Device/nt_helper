import 'dart:async';
import 'dart:typed_data';

import 'package:nt_helper/db/daos/presets_dao.dart' show FullPresetDetails;

import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/models/slot_count_info.dart';

/// Optional extended 0x60 capability implemented by live MIDI managers.
abstract interface class SlotCountInfoProvider {
  Future<SlotCountInfo?> requestSlotCountInfo({
    Duration? timeout,
    int? maxRetries,
  });
}

/// Optional firmware-1.18 capability implemented by live MIDI managers.
abstract interface class AlgorithmVisualStyleWriter {
  Future<void> requestSetAlgorithmVisualStyle(
    int algorithmIndex,
    AlgorithmVisualStyle style,
  );
}

/// Abstract interface for Disting MIDI communication.
/// Allows for mocking or different implementations.
abstract class IDistingMidiManager {
  // Lifecycle
  void dispose();

  // Requests (returning Futures)
  Future<int?> requestNumberOfAlgorithms();
  Future<AlgorithmInfo?> requestAlgorithmInfo(int index);
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  });
  Future<String?> requestVersionString();
  Future<String?> requestPresetName();
  Future<List<String>?> requestUnitStrings();
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex);
  Future<ParameterInfo?> requestParameterInfo(
    int algorithmIndex,
    int parameterNumber,
  );
  Future<ParameterPages?> requestParameterPages(int algorithmIndex);
  Future<AllParameterValues?> requestAllParameterValues(int algorithmIndex);
  Future<ParameterEnumStrings?> requestParameterEnumStrings(
    int algorithmIndex,
    int parameterNumber,
  );
  Future<Mapping?> requestMappings(int algorithmIndex, int parameterNumber);
  Future<RoutingInfo?> requestRoutingInformation(int algorithmIndex);
  Future<ParameterValueString?> requestParameterValueString(
    int algorithmIndex,
    int parameterNumber,
  );
  Future<ParameterValue?> requestParameterValue(
    int algorithmIndex,
    int parameterNumber,
  );
  Future<Algorithm?> requestAlgorithmGuid(int algorithmIndex);
  Future<OutputModeUsage?> requestOutputModeUsage(
    int algorithmIndex,
    int parameterNumber,
  );
  Future<Uint8List?>
  encodeTakeScreenshot(); // Assuming this belongs here, might need adjustment
  Future<CpuUsage?> requestCpuUsage();

  // Actions (may return Future<void> or void)
  Future<void> requestWake();
  Future<void> requestReboot();
  Future<void> requestEnterBootloader();
  Future<void> setParameterValue(
    int algorithmIndex,
    int parameterNumber,
    int value,
  );
  Future<void> setParameterString(
    int algorithmIndex,
    int parameterNumber,
    String value,
  );
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  );
  Future<void> requestRemoveAlgorithm(int algorithmIndex);
  Future<void> requestLoadPlugin(String guid);
  Future<void> requestSetFocus(int algorithmIndex, int parameterNumber);
  Future<void> requestSetPresetName(String newName);
  Future<void> requestSavePreset({int option});
  Future<void> requestMoveAlgorithmUp(int algorithmIndex);
  Future<void> requestMoveAlgorithmDown(int algorithmIndex);
  Future<void> requestNewPreset();
  Future<void> requestLoadPreset(String name, bool append);
  Future<void> requestSetMapping(
    int algorithmIndex,
    int parameterNumber,
    PackedMappingData data,
  );

  /// Sets the performance page assignment for a parameter.
  ///
  /// - [slotIndex]: Slot index (0-39)
  /// - [parameterNumber]: Parameter number within the algorithm
  /// - [perfPageIndex]: Performance page index (0-30, where 0 = not assigned)
  Future<void> setPerformancePageMapping(
    int slotIndex,
    int parameterNumber,
    int perfPageIndex,
  );
  Future<void> requestSendSlotName(int algorithmIndex, String newName);
  Future<void> requestSetDisplayMode(DisplayMode displayMode);
  Future<void> requestSetRealTimeClock(int unixTimeSeconds);
  Future<FullPresetDetails?> requestCurrentPresetDetails();

  // Lua Operations
  Future<String?> executeLua(String luaScript);
  Future<String?> installLua(int algorithmIndex, String luaScript);

  // SD Card Operations
  Future<DirectoryListing?> requestDirectoryListing(String path);
  Future<Uint8List?> requestFileDownload(String path);

  /// Compatibility helper only.
  ///
  /// The Disting NT SD-card download protocol returns whole files and has no
  /// offset/count request fields. Live implementations must not send invented
  /// chunked download SysEx messages.
  Future<Uint8List?> requestFileDownloadChunk(
    String path,
    int position,
    int count,
  );
  Future<SdCardStatus?> requestFileDelete(String path);
  Future<SdCardStatus?> requestFileRename(String fromPath, String toPath);
  Future<SdCardStatus?> requestFileUpload(String path, Uint8List data);
  Future<SdCardStatus?> requestFileUploadChunk(
    String path,
    Uint8List data,
    int position, {
    bool createAlways = false,
  });
  Future<SdCardStatus?> requestDirectoryCreate(String path);
  Future<void> requestRescanPlugins();
  Future<void> requestRemountSd();

  // Performance Page Items (firmware v1.16+)
  Future<PerformancePageItem?> requestPerfPageItem(int itemIndex);
  Future<void> setPerfPageItem(PerformancePageItem item);

  // Scala/Tuning Operations
  Future<void> requestSclFile(String filePath);
  Future<void> requestKbmFile(String filePath);

  // Backup Operations
  Future<void> backupPlugins(
    String backupDirectory, {
    void Function(double progress, String currentFile)? onProgress,
  });

  // CC notification callback (optional - no-op for offline/mock managers)
  void setCcCallback(void Function(int channel, int cc, int value)? callback) {}
  void clearCcCallback() {}

  // Diagnostics (optional - returns null for offline/mock managers)
  /// Returns overall scheduler diagnostics including RTT stats.
  Map<String, dynamic>? getSchedulerDiagnostics() => null;

  /// Returns RTT statistics broken down by message type.
  Map<String, Map<String, dynamic>>? getRttStatsByMessageType() => null;

  /// Returns slow Algorithm Info requests by algorithm index (>50ms).
  Map<int, double>? getSlowAlgorithmInfo() => null;
}

/// Backwards-compatible extended slot-count request.
///
/// Existing manager adapters only need to implement the legacy count method;
/// live managers implementing [SlotCountInfoProvider] expose bus topology too.
extension SlotCountInfoRequest on IDistingMidiManager {
  Future<SlotCountInfo?> requestSlotCountInfo({
    Duration? timeout,
    int? maxRetries,
  }) async {
    final manager = this;
    if (manager is SlotCountInfoProvider) {
      return (manager as SlotCountInfoProvider).requestSlotCountInfo(
        timeout: timeout,
        maxRetries: maxRetries,
      );
    }
    final slotCount = await requestNumAlgorithmsInPreset(
      timeout: timeout,
      maxRetries: maxRetries,
    );
    return slotCount == null ? null : SlotCountInfo(slotCount: slotCount);
  }
}

extension AlgorithmVisualStyleRequest on IDistingMidiManager {
  Future<void> requestSetAlgorithmVisualStyle(
    int algorithmIndex,
    AlgorithmVisualStyle style,
  ) {
    final manager = this;
    if (manager is AlgorithmVisualStyleWriter) {
      return (manager as AlgorithmVisualStyleWriter)
          .requestSetAlgorithmVisualStyle(algorithmIndex, style);
    }
    return Future<void>.error(
      UnsupportedError('Algorithm visual styling requires live MIDI'),
    );
  }
}
