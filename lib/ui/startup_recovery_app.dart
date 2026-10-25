import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/services/macos_library_storage.dart';
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
        ? '${_recoveryMessage(controller.recovery)}Library ready${controller.location == null ? '' : ' at ${controller.location}'}'
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

  StartupController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final failure = controller.failure;
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 460,
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
                                  '${_showDetails ? '\n\n${_errorDetails(failure)}' : ''}',
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
                                  ClipboardData(text: _errorDetails(failure)),
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
                Row(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: FilledButton(
                        autofocus: true,
                        onPressed: controller.canRetry && !controller.busy
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
                            onPressed: !controller.busy
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

String _errorDetails(Object failure) =>
    'nt_helper library startup failure\n'
    'OS: ${Platform.operatingSystemVersion}\n'
    'Architecture: ${Abi.current()}\n\n$failure';

String _failureMessage(Object failure) {
  if (failure is! StorageFailure) {
    return 'An unexpected error prevented nt_helper from opening your library. Select Retry. If this continues, contact support with the error details.';
  }
  return switch (failure.kind) {
    StorageFailureKind.access =>
      'nt_helper could not access a library file or folder. Check the report below for a missing file or a permission error. For permission errors, check nt_helper’s access in System Settings → Privacy & Security → Files and Folders, then Retry.',
    StorageFailureKind.busy =>
      'Another operation is using the library. Close any other running copy of nt_helper, then Retry.',
    StorageFailureKind.io =>
      'nt_helper could not read or write a library file. Check that your disk is connected and has free space, then Retry.',
    StorageFailureKind.native =>
      'The database could not be opened. This does not necessarily mean it is damaged. Select Retry; if this continues, send the error details to support.',
    StorageFailureKind.unsupportedSchema =>
      'This library uses a database version this app cannot open. Install the latest nt_helper version. Do not delete your library.',
    StorageFailureKind.uncertain =>
      'nt_helper could not determine which saved library files are safe to use. The report below explains what it found. Please send these details to support so we can help recover access.',
    StorageFailureKind.damaged =>
      'The library database appears damaged and automatic recovery could not finish. Please send the error details to support. Do not delete your library files.',
  };
}

String _recoveryMessage(LibraryRecovery? recovery) => switch (recovery) {
  LibraryRecovery.repaired =>
    'The library was safely repaired in a separate copy. Originals and recovery files are retained. ',
  LibraryRecovery.freshAfterDamage =>
    'The previous library was not recovered. Originals and recovery files are retained. A fresh library was opened after confirmed database damage and unsuccessful safe repair. ',
  null => '',
};
