import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/services/library_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nt_helper/services/startup_controller.dart';

/// Displays recovery controls only after a startup failure. Successful storage
/// preparation is silent; admission and close ownership remain in the controller.
class StartupRecoveryApp extends StatefulWidget {
  const StartupRecoveryApp({
    super.key,
    required this.controller,
    required this.normalBuilder,
  });
  final StartupController controller;
  final WidgetBuilder normalBuilder;

  @override
  State<StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<StartupRecoveryApp> {
  String? _lastAnnouncement;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.controller.close();
        return AppExitResponse.exit;
      },
    );
  }

  void _changed() {
    if (!mounted) return;
    final controller = widget.controller;
    final message = controller.closed
        ? 'Closing library'
        : controller.ready
        ? 'Library ready${controller.location == null ? '' : ' at ${controller.location}'}'
        : controller.busy
        ? 'Opening library. Please wait'
        : controller.failure == null
        ? 'Preparing library'
        : 'Library unavailable. ${_failureMessage(controller.failure!)}';
    if (message != _lastAnnouncement) {
      _lastAnnouncement = message;
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          TextDirection.ltr,
        ),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.ready) return widget.normalBuilder(context);
    return DistingApp(startupPage: _RecoveryPage(controller: controller));
  }
}

/// A database-independent route in the real application shell. Recovery uses
/// its Navigator's dialog overlay, never a second standalone MaterialApp.
class _RecoveryPage extends StatefulWidget {
  const _RecoveryPage({required this.controller});

  final StartupController controller;

  @override
  State<_RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<_RecoveryPage> {
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRecovery);
    _scheduleRecovery();
  }

  @override
  void didUpdateWidget(_RecoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_scheduleRecovery);
      widget.controller.addListener(_scheduleRecovery);
    }
    _scheduleRecovery();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRecovery);
    super.dispose();
  }

  void _scheduleRecovery() {
    if (widget.controller.failure == null || _dialogShowing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dialogShowing || widget.controller.closed) return;
      _dialogShowing = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: false,
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (_, _) => _RecoveryDialog(controller: widget.controller),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('nt_helper')),
    body: const SizedBox.expand(),
  );
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog({required this.controller});

  final StartupController controller;

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  bool _showDetails = true;
  bool _choosing = false;
  String _version = 'unavailable';

  StartupController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      // Version metadata is helpful in reports, never a startup prerequisite.
    }
  }

  String get _details =>
      _errorDetails(controller.failure!, _version, controller.location);

  Future<void> _chooseLibrary() async {
    setState(() => _choosing = true);
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Choose saved library',
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'sqlite3', 'db'],
      );
      final path = result?.files.single.path;
      if (path != null && mounted && !controller.closed) {
        await controller.retry(importSource: File(path));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not choose a library: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _startFresh() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Semantics(
          header: true,
          child: const Text('Start with an empty library?'),
        ),
        content: const Text(
          'Saved presets will not appear in the new library. Existing library and recovery files will be kept. Your disting NT hardware will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && !controller.closed) {
      await controller.retry(startFresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = controller.failure;
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 512,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    'Unable to open your library',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'nt_helper could not open its saved presets and cached data. Your disting NT hardware has not been changed.',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Semantics(
                      liveRegion: true,
                      child: SelectableText(
                        failure == null
                            ? 'Preparing storage.'
                            : '${_failureMessage(failure)}\n\n'
                                  'If Retry does not help, copy the error details and send them to nt_helper support. Do not delete or move library files.'
                                  '${_showDetails ? '\n\n$_details' : ''}',
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _showDetails = !_showDetails),
                        child: Text(
                          _showDetails ? 'Hide details' : 'Show details',
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Copy error details',
                        onPressed: failure == null
                            ? null
                            : () => unawaited(
                                Clipboard.setData(
                                  ClipboardData(text: _details),
                                ),
                              ),
                        icon: const Icon(
                          Icons.copy,
                          semanticLabel: 'Copy error details',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 24,
                  child: controller.busy
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Opening library',
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Opening library…'),
                          ],
                        )
                      : Text(
                          controller.closed
                              ? 'Closing…'
                              : failure == null
                              ? 'Ready to open'
                              : 'Library not opened',
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: Visibility(
                    visible: controller.canImport,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed:
                              !controller.canImport ||
                                  controller.busy ||
                                  _choosing
                              ? null
                              : _chooseLibrary,
                          child: const Text('Choose library…'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed:
                              !controller.canImport ||
                                  controller.busy ||
                                  _choosing
                              ? null
                              : _startFresh,
                          child: const Text('Start fresh…'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: FilledButton(
                        autofocus: true,
                        onPressed:
                            controller.canRetry &&
                                !controller.busy &&
                                !_choosing
                            ? () => unawaited(controller.retry())
                            : null,
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Visibility(
                        visible: controller.canSelectAccess,
                        maintainState: true,
                        maintainAnimation: true,
                        maintainSize: true,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: OutlinedButton(
                            onPressed: !controller.busy && !_choosing
                                ? () => unawaited(
                                    controller.retry(
                                      selectLegacyDirectory: true,
                                    ),
                                  )
                                : null,
                            child: const Text('Allow folder access…'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _errorDetails(Object failure, String version, String? location) =>
    'nt_helper library startup failure\n'
    'App: $version\n'
    'OS: ${Platform.operatingSystemVersion}\n'
    'Architecture: ${Abi.current()}\n'
    '${location == null ? '' : 'Library: $location\n'}\n$failure';

String _failureMessage(Object failure) => failure is LibraryImportException
    ? failure.message
    : 'nt_helper could not open your library. Select Retry. If this continues, contact support with the error details. No library files have been deleted.';
