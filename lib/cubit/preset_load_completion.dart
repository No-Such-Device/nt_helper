import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';

/// Waits for the Disting NT to finish applying a preset file.
///
/// The NT does not acknowledge a preset load. It reports the new preset name
/// at once and builds the algorithms afterwards, so a sync started right after
/// the request reads an empty or partial preset. This polls the slot count
/// until it reaches the count in the preset file, or stops changing when that
/// count is unknown or never reached (for example, a missing plug-in).
class PresetLoadCompletion {
  const PresetLoadCompletion({
    this.pollInterval = const Duration(milliseconds: 250),
    this.timeout = const Duration(seconds: 30),
    this.unknownTargetSettle = const Duration(seconds: 3),
    this.unmetTargetSettle = const Duration(seconds: 10),
    this.fileReadTimeout = const Duration(seconds: 5),
    this.slotCountReadTimeout = const Duration(seconds: 2),
  });

  final Duration pollInterval;
  final Duration timeout;

  /// How long an unchanged count is trusted when the file could not be read.
  final Duration unknownTargetSettle;

  /// How long an unchanged count below the file's slot count is trusted.
  final Duration unmetTargetSettle;
  final Duration fileReadTimeout;
  final Duration slotCountReadTimeout;

  /// The number of slots in the preset file at [path], or null when the file
  /// cannot be read or parsed.
  Future<int?> readPresetSlotCount(
    IDistingMidiManager disting,
    String path,
  ) async {
    try {
      final bytes = await disting
          .requestFileDownload(path)
          .timeout(fileReadTimeout);
      if (bytes == null) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final slots = decoded['slots'];
      return slots is List ? slots.length : null;
    } catch (_) {
      return null;
    }
  }

  /// Polls until the device reports [targetSlotCount] slots on two consecutive
  /// reads, or until the count settles, or until [timeout]. Returns the last
  /// count read, or null when none was read or [isCurrent] became false.
  Future<int?> waitForSlots(
    IDistingMidiManager disting, {
    required int? targetSlotCount,
    required bool Function() isCurrent,
    void Function(int slotCount)? onSlotCount,
  }) async {
    final stopwatch = clock.stopwatch()..start();
    final settle = targetSlotCount == null
        ? unknownTargetSettle
        : unmetTargetSettle;
    int? lastCount;
    var lastChange = Duration.zero;
    var targetReads = 0;

    while (true) {
      if (!isCurrent()) return null;
      final count = await _readSlotCount(disting);
      if (!isCurrent()) return null;
      final elapsed = stopwatch.elapsed;

      if (count != null) {
        if (count != lastCount) {
          lastCount = count;
          lastChange = elapsed;
          targetReads = 0;
          onSlotCount?.call(count);
        }
        if (targetSlotCount != null && count >= targetSlotCount) {
          targetReads++;
          if (targetReads >= 2) return count;
        } else if (elapsed - lastChange >= settle) {
          return count;
        }
      }

      if (elapsed >= timeout) return lastCount;
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<int?> _readSlotCount(IDistingMidiManager disting) async {
    try {
      return await disting.requestNumAlgorithmsInPreset(
        timeout: slotCountReadTimeout,
        maxRetries: 0,
      );
    } catch (_) {
      return null;
    }
  }
}
