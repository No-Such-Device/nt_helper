import 'package:material_ui/material_ui.dart';
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

/// Only exceptional cleanup outcomes use a snackbar. Successful/skipped cleanup
/// stays silent; normal installation state already communicates completion.
void showPluginCleanupNotice(
  ScaffoldMessengerState messenger,
  PluginCleanupOutcome outcome,
  ColorScheme colorScheme,
) {
  final message = pluginCleanupMessage(outcome);
  if (message == null || outcome is PluginCleanupRemoved) return;
  messenger.showSnackBar(
    SnackBar(
      content: Semantics(liveRegion: true, child: Text(message)),
      backgroundColor: colorScheme.error,
      duration: const Duration(seconds: 8),
    ),
  );
}
