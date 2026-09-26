import 'package:flutter/material.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';

/// Status text for a root-duplicate cleanup outcome, or null when skipped.
String? pluginCleanupMessage(PluginCleanupOutcome outcome) => switch (outcome) {
  PluginCleanupSkipped() => null,
  PluginCleanupRemoved(:final path) => 'Removed duplicate plugin $path',
  PluginCleanupDeletionFailed(:final path) =>
    'Could not remove duplicate plugin $path. Delete it from the SD card.',
  PluginCleanupCouldNotBeVerified(:final path) =>
    'Kept $path: could not confirm it is a duplicate. '
        'Remove it from the SD card if it is an old copy.',
};

/// Shows a brief notice (removed) or warning (deletion failed, could not be
/// verified) as live-region status text. Does nothing for skipped outcomes.
void showPluginCleanupNotice(
  ScaffoldMessengerState messenger,
  PluginCleanupOutcome outcome,
  ColorScheme colorScheme,
) {
  final message = pluginCleanupMessage(outcome);
  if (message == null) return;
  final isWarning = outcome is! PluginCleanupRemoved;
  messenger.showSnackBar(
    SnackBar(
      content: Semantics(liveRegion: true, child: Text(message)),
      backgroundColor: isWarning ? colorScheme.error : null,
      duration: Duration(seconds: isWarning ? 8 : 4),
    ),
  );
}
