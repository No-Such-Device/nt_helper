import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/core/routing/routing_service_locator.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/debug_poly_sample_upload_command.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/startup_controller.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/ui/startup_recovery_app.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/node_positions_persistence_service.dart';
import 'package:nt_helper/services/settings_service.dart' show SettingsService;
import 'package:nt_helper/services/startup_log_service.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';
import 'package:nt_helper/services/zoom_hotkey_service.dart';
import 'package:nt_helper/ui/video_popup_app.dart';
import 'package:nt_helper/util/in_app_logger.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// Define the static MethodChannel
const MethodChannel _windowEventsChannel = MethodChannel(
  'com.nt_helper.app/window_events',
);

const MethodChannel _zoomHotkeysChannel = MethodChannel(
  'com.nt_helper.app/zoom_hotkeys',
);

void _videoPopupDebugLog(String message) {
  if (kDebugMode) {
    debugPrint('[VIDEO_POPUP_DART] $message');
  }
}

/// Manages window bounds persistence - saves on every move/resize
class _WindowBoundsManager with WindowListener {
  static const _keyX = 'window_x';
  static const _keyY = 'window_y';
  static const _keyWidth = 'window_width';
  static const _keyHeight = 'window_height';

  SharedPreferences? _prefs;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    windowManager.addListener(this);
  }

  /// Load saved bounds, returns null if none saved
  static Future<Rect?> loadBounds(SharedPreferences prefs) async {
    final x = prefs.getDouble(_keyX);
    final y = prefs.getDouble(_keyY);
    final width = prefs.getDouble(_keyWidth);
    final height = prefs.getDouble(_keyHeight);

    if (x != null && y != null && width != null && height != null) {
      if (width > 0 && height > 0) {
        return Rect.fromLTWH(x, y, width, height);
      }
    }
    return null;
  }

  Future<void> _saveBounds() async {
    if (_prefs == null) return;
    final bounds = await windowManager.getBounds();
    await Future.wait([
      _prefs!.setDouble(_keyX, bounds.left),
      _prefs!.setDouble(_keyY, bounds.top),
      _prefs!.setDouble(_keyWidth, bounds.width),
      _prefs!.setDouble(_keyHeight, bounds.height),
    ]);
  }

  @override
  void onWindowMoved() => _saveBounds();

  @override
  void onWindowResized() => _saveBounds();
}

final _windowBoundsManager = _WindowBoundsManager();

bool _hasRunAppSuccessfully = false;
StartupController? _startup;
bool get _processClosing => _startup?.closed ?? false;

void main(List<String> args) {
  StartupLogService.initialize();
  StartupLogService.log('main() entered');

  runZonedGuarded(
    () async {
      await _bootstrapApp(args);
    },
    (error, stackTrace) {
      final isStartupError = !_hasRunAppSuccessfully;
      StartupLogService.logError(
        isStartupError
            ? 'UNCAUGHT startup zone error'
            : 'UNCAUGHT app zone error after startup',
        error,
        stackTrace,
      );
      if (isStartupError) {
        _showStartupFailure(error, stackTrace);
      }
    },
  );
}

Future<void> _bootstrapApp(List<String> args) async {
  _installGlobalErrorHandlers();

  StartupLogService.traceSync(
    'WidgetsFlutterBinding.ensureInitialized',
    WidgetsFlutterBinding.ensureInitialized,
  );

  if (Platform.isWindows) {
    _videoPopupDebugLog('main() Windows args=$args');
  }

  if (isDebugPolySampleUploadCommand(args)) {
    await StartupLogService.traceAsync(
      'SettingsService.init',
      SettingsService().init,
    );
    try {
      exitCode = await runDebugPolySampleUploadCommand(args);
    } catch (error, stackTrace) {
      StartupLogService.logError(
        'Debug poly sample upload failed',
        error,
        stackTrace,
      );
      stderr.writeln('Debug poly sample upload failed: $error');
      exitCode = 1;
    }
    exit(exitCode);
  }

  if (Platform.isWindows &&
      VideoPopupWindowService.isWindowsNativeVideoPopupArguments(args)) {
    _videoPopupDebugLog('main(): detected Windows native video popup args');
    await _bootstrapVideoPopupWindow();
    return;
  }

  if (_isDesktop) {
    try {
      final windowController = await StartupLogService.traceAsync(
        'WindowController.fromCurrentEngine',
        WindowController.fromCurrentEngine,
      );
      if (VideoPopupWindowService.isVideoPopupArguments(
        windowController.arguments,
      )) {
        _videoPopupDebugLog(
          'main(): detected desktop_multi_window '
          'video popup arguments=${windowController.arguments}',
        );
        await _bootstrapVideoPopupWindow();
        return;
      }
    } catch (error, stackTrace) {
      StartupLogService.logError(
        'Unable to inspect multi-window arguments; continuing main startup',
        error,
        stackTrace,
      );
    }
  }

  final opener = StartupStorageOpener();
  final startup = StartupController(
    open: opener.open,
    libraryLocation: () => opener.location,
    canSelectLegacyDirectory: () => opener.legacyAccessDirectory != null,
    activationSteps: [
      (database) => AlgorithmMetadataService().initialize(database),
      (_) => RoutingServiceLocator.setup(),
    ],
  );

  _startup = startup;
  // Install before any storage await, including the first attempt.
  _windowEventsChannel.setMethodCallHandler((call) async {
    if (call.method != 'windowWillClose') return null;
    // Invalidates pending admission and window-show callbacks immediately.
    final settled = startup.close();
    try {
      await settled;
    } finally {
      try {
        if (_isDesktop) await McpServerService.instance.stop();
      } finally {
        await RoutingServiceLocator.reset();
      }
    }
    return true;
  });

  // Initialize window_manager on desktop platforms
  Rect? savedBounds;
  if (_isDesktop) {
    await StartupLogService.traceAsync(
      'windowManager.ensureInitialized',
      windowManager.ensureInitialized,
    );

    // Load saved window position/size
    final prefs = await StartupLogService.traceAsync(
      'SharedPreferences.getInstance',
      SharedPreferences.getInstance,
    );
    savedBounds = await StartupLogService.traceAsync(
      'WindowBoundsManager.loadBounds',
      () => _WindowBoundsManager.loadBounds(prefs),
    );
    StartupLogService.log('Saved window bounds: ${savedBounds ?? 'none'}');

    // Initialize bounds manager to save on move/resize
    await StartupLogService.traceAsync(
      'WindowBoundsManager.init',
      () => _windowBoundsManager.init(prefs),
    );

    final initialSize = savedBounds?.size ?? const Size(720, 1080);
    StartupLogService.log('Initial window size: $initialSize');

    // Configure window options but DON'T show yet - wait for first frame
    WindowOptions windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: const Size(640, 720),
      center: savedBounds == null,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    // Set up the window but don't show yet
    // We'll set bounds and show after first frame renders to avoid white flash
    await StartupLogService.traceAsync(
      'windowManager.waitUntilReadyToShow',
      () => windowManager.waitUntilReadyToShow(windowOptions, () async {
        // Set position immediately in this callback (before show)
        if (savedBounds != null) {
          StartupLogService.log('Applying saved window bounds: $savedBounds');
          await windowManager.setBounds(savedBounds);
        }
      }),
    );
  }

  await SettingsService().init();
  if (_processClosing) return;
  await NodePositionsPersistenceService().init();
  if (_processClosing) return;

  runApp(
    StartupRecoveryApp(
      controller: startup,
      normalBuilder: (_) => MultiProvider(
        providers: [
          RepositoryProvider<AppDatabase>.value(value: startup.database),
          ChangeNotifierProvider(create: (_) => InAppLogger()),
        ],
        child: const DistingApp(),
      ),
    ),
  );
  _hasRunAppSuccessfully = true;

  // The recovery shell, not storage readiness, controls first window visibility.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_processClosing) return;
    if (_isDesktop) unawaited(_showDesktopWindow('library recovery'));
    unawaited(startup.retry());
  });

  _zoomHotkeysChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'zoomIn':
        ZoomHotkeyService.instance.dispatch(ZoomHotkeyAction.zoomIn);
        break;
      case 'zoomOut':
        ZoomHotkeyService.instance.dispatch(ZoomHotkeyAction.zoomOut);
        break;
      case 'resetZoom':
        ZoomHotkeyService.instance.dispatch(ZoomHotkeyAction.resetZoom);
        break;
    }
    return null;
  });
  StartupLogService.log('Zoom hotkeys MethodChannel handler installed');
  StartupLogService.log('Startup bootstrap completed');
}

Future<void> _bootstrapVideoPopupWindow() async {
  _videoPopupDebugLog(
    '_bootstrapVideoPopupWindow() platform=${Platform.operatingSystem}',
  );
  if (!Platform.isWindows) {
    await StartupLogService.traceAsync(
      'windowManager.ensureInitialized',
      windowManager.ensureInitialized,
    );
  }
  await StartupLogService.traceAsync(
    'SettingsService.init',
    SettingsService().init,
  );
  runApp(const VideoPopupApp());
  _hasRunAppSuccessfully = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      StartupLogService.traceAsync(
        'configureVideoPopupWindow',
        configureVideoPopupWindow,
      ),
    );
  });
}

bool get _isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

void _installGlobalErrorHandlers() {
  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    StartupLogService.logError(
      'Flutter framework error',
      details.exception,
      details.stack ?? StackTrace.current,
    );
    (previousFlutterErrorHandler ?? FlutterError.presentError).call(details);
  };

  final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    StartupLogService.logError(
      'PlatformDispatcher uncaught error',
      error,
      stackTrace,
    );
    return previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
  };

  StartupLogService.log('Global error handlers installed');
}

Future<void> _showDesktopWindow(String reason) async {
  if (_processClosing) return;
  try {
    if (Platform.isWindows) {
      _videoPopupDebugLog('_showDesktopWindow start reason=$reason');
    }
    await windowManager.ensureInitialized();
    if (_processClosing) return;
    await windowManager.show();
    if (_processClosing) return;
    await windowManager.focus();
    if (Platform.isWindows) {
      _videoPopupDebugLog('_showDesktopWindow done reason=$reason');
    }
    StartupLogService.log('Desktop window shown for $reason');
  } catch (error, stackTrace) {
    StartupLogService.logError(
      'Unable to show desktop window for $reason',
      error,
      stackTrace,
    );
  }
}

void _showStartupFailure(Object error, StackTrace stackTrace) {
  if (_processClosing) return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(_StartupFailureApp(error: error, stackTrace: stackTrace));
    if (_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showDesktopWindow('startup failure'));
      });
    }
  } catch (secondaryError, secondaryStackTrace) {
    StartupLogService.logError(
      'Unable to display startup failure screen',
      secondaryError,
      secondaryStackTrace,
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    final logPath = StartupLogService.logPath ?? 'unknown';

    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    'nt_helper failed to start',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Process setup could not complete. The operation details and startup log are shown below. No replacement library was admitted.',
                ),
                const SizedBox(height: 12),
                SelectableText('Startup log: $logPath'),
                const SizedBox(height: 24),
                SelectableText('Error: $error'),
                const SizedBox(height: 16),
                SelectableText('Stack trace:\n$stackTrace'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
