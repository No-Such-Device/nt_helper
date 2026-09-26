/// Result of removing a root-folder duplicate after a C++ plugin was
/// installed into a subfolder of `/programs/plug-ins`.
sealed class PluginCleanupOutcome {
  const PluginCleanupOutcome();
}

/// Cleanup did not apply (root, Lua or 3pot install, no same-named root
/// file, or no GUID readable from the installed plugin).
class PluginCleanupSkipped extends PluginCleanupOutcome {
  const PluginCleanupSkipped();
}

/// A confirmed duplicate at [path] was deleted.
class PluginCleanupRemoved extends PluginCleanupOutcome {
  const PluginCleanupRemoved(this.path);
  final String path;
}

/// A confirmed duplicate at [path] could not be deleted and still needs removal.
class PluginCleanupDeletionFailed extends PluginCleanupOutcome {
  const PluginCleanupDeletionFailed(this.path);
  final String path;
}

/// The same-named root file at [path] was kept because its identity could not
/// be confirmed.
class PluginCleanupCouldNotBeVerified extends PluginCleanupOutcome {
  const PluginCleanupCouldNotBeVerified(this.path);
  final String path;
}
