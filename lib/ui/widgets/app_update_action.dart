import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/app_update_service.dart';
import 'package:nt_helper/ui/widgets/app_update_dialog.dart';

/// A non-blocking update entry point, independent of the MIDI connection.
class AppUpdateAction extends StatefulWidget {
  const AppUpdateAction({super.key, required this.updateService});

  /// Borrowed from the page so the updater can outlive connection-screen changes.
  final AppUpdateService updateService;

  @override
  State<AppUpdateAction> createState() => _AppUpdateActionState();
}

class _AppUpdateActionState extends State<AppUpdateAction> {
  AppRelease? _release;
  bool _checking = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.updateService.isSupported) unawaited(_check());
    });
  }

  Future<void> _check({bool forceRefresh = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final release = await widget.updateService.checkForUpdate(
        forceRefresh: forceRefresh,
      );
      if (mounted) setState(() => _release = release);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check for app updates: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdate() async {
    final release = _release;
    if (release == null || _dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => AppUpdateDialog(
          release: release,
          updateService: widget.updateService,
        ),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.updateService.isSupported) return const SizedBox.shrink();
    final release = _release;
    final label = _checking
        ? 'Checking for app updates'
        : release == null
        ? 'Check for app updates'
        : 'Update NT Helper to ${release.version}';
    return MergeSemantics(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: SizedBox.square(
          dimension: 48,
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: IconButton(
              onPressed: _checking
                  ? null
                  : release == null
                  ? () => _check(forceRefresh: true)
                  : _showUpdate,
              icon: ExcludeSemantics(
                child: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Badge(
                        isLabelVisible: release != null,
                        child: Icon(
                          Icons.system_update_alt,
                          color: release == null
                              ? null
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
