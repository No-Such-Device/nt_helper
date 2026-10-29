import 'dart:async';
import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:nt_helper/cubit/video_frame_cubit.dart';
import 'package:nt_helper/cubit/video_frame_state.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/video/usb_video_manager.dart';
import 'package:nt_helper/domain/video/video_stream_state.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';
import 'package:nt_helper/services/video_popup_remote_contract.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:nt_helper/models/remote_control_state.dart';
import 'package:nt_helper/ui/widgets/remote_control_cluster.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/contextual_help_tooltip_scope.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:window_manager/window_manager.dart';

const _windowsVideoPopupChannel = MethodChannel(
  'nt_helper/windows_video_popup',
);

void _videoPopupLog(String message) {
  if (kDebugMode) {
    debugPrint('[VIDEO_POPUP_DART] $message');
  }
}

class VideoPopupApp extends StatelessWidget {
  const VideoPopupApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();
    return ValueListenableBuilder<Color>(
      valueListenable: settings.themeSeedColorNotifier,
      builder: (context, seedColor, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        darkTheme: AppTheme.build(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        highContrastTheme: AppTheme.build(
          seedColor: seedColor,
          brightness: Brightness.light,
          contrastLevel: 1,
        ),
        highContrastDarkTheme: AppTheme.build(
          seedColor: seedColor,
          brightness: Brightness.dark,
          contrastLevel: 1,
        ),
        themeMode: ThemeMode.system,
        builder: (context, child) =>
            ContextualHelpTooltipScope(child: child ?? const SizedBox.shrink()),
        home: const VideoPopupWindow(),
      ),
    );
  }
}

class VideoPopupWindow extends StatefulWidget {
  const VideoPopupWindow({super.key, this.windowsNative});

  /// Allows software contract checks of both platform adapters.
  final bool? windowsNative;

  @override
  State<VideoPopupWindow> createState() => _VideoPopupWindowState();
}

class _VideoPopupWindowState extends State<VideoPopupWindow>
    with WindowListener, WidgetsBindingObserver {
  final SettingsService _settings = SettingsService();
  late final UsbVideoManager _videoManager = UsbVideoManager(
    takeScreenshot: _getHardwareScreenshot,
  );
  final VideoFrameCubit _videoFrameCubit = VideoFrameCubit();
  StreamSubscription<VideoStreamState>? _videoStateSubscription;
  Future<void>? _videoStartup;
  Stream<dynamic>? _connectedStream;
  Uint8List? _lastFrame;
  Uint8List? _displayFrame;
  bool _alwaysOnTop = SettingsService.defaultVideoPopupAlwaysOnTop;
  bool _toolbarVisible = true;
  bool _toolbarHovering = false;
  Timer? _toolbarHideTimer;
  bool _toolbarFocused = false;
  bool _remoteExpanded = false;
  bool _foreground = true;
  bool _focused = true;
  bool _reading = false;
  bool _opening = false;
  bool _ready = false;
  bool _closing = false;
  bool _disposed = false;
  int _generation = 0;
  int _revision = -1;
  late final String _hostId = 'popup-${DateTime.now().microsecondsSinceEpoch}';
  String? _windowId;
  WindowController? _controller;
  Timer? _remoteTimer;
  Future<void> _wheelTail = Future<void>.value();
  RemoteControlState _remote = RemoteControlState(
    unavailableReason: 'Waiting for the main connection authority.',
  );
  String? _channelError;
  bool get _windowsNative => widget.windowsNative ?? Platform.isWindows;
  bool get _active => _foreground && _focused && !_closing;

  static const _channel = WindowMethodChannel(
    'nt_helper/video_popup',
    mode: ChannelMode.unidirectional,
  );

  @override
  void initState() {
    super.initState();
    _alwaysOnTop = _settings.videoPopupAlwaysOnTop;
    _videoPopupLog(
      'VideoPopupWindow.initState platform=${Platform.operatingSystem} '
      'alwaysOnTop=$_alwaysOnTop',
    );
    WidgetsBinding.instance.addObserver(this);
    if (!_windowsNative) windowManager.addListener(this);
    unawaited(_configureWindow());
    unawaited(_configureWindowController().catchError(_reportChannelError));
    _videoStartup = _startVideo();
    _startToolbarHideTimer();
  }

  @override
  void reassemble() {
    super.reassemble();
    unawaited(_sizeForRemote().catchError(_reportChannelError));
  }

  Future<void> _configureWindow() async {
    if (!_windowsNative) await windowManager.setPreventClose(true);
    if (!_windowsNative && _alwaysOnTop) {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _configureWindowController() async {
    if (_windowsNative) {
      _windowsVideoPopupChannel.setMethodCallHandler(_handleWindowsMethod);
    } else {
      final controller = await WindowController.fromCurrentEngine();
      if (!mounted) return;
      _controller = controller;
      _windowId = controller.windowId;
      await controller.setWindowMethodHandler(_handleWindowMethod);
    }
    if (!mounted) return;
    await _request(VideoPopupRemoteContract.acquire);
    if (!mounted) return;
    _ready = true;
    // State remains owned by the main engine. Polling uses the existing
    // request/result channels, including when capability changes while open.
    _remoteTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      unawaited(_refreshRemote());
    });
  }

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    switch (call.method) {
      case VideoPopupWindowService.raiseMethod:
        _foreground = true;
        _focused = true;
        await _request(VideoPopupRemoteContract.acquire);
        await _refreshRemote();
        await raiseVideoPopupWindow();
        return true;
      default:
        throw MissingPluginException(
          'Unknown video popup method ${call.method}',
        );
    }
  }

  Future<dynamic> _handleWindowsMethod(MethodCall call) async {
    switch (call.method) {
      case 'remoteLifecycle':
        final event = call.arguments;
        if (event == 'close') {
          _closing = true;
          await _endRemote(detach: true);
        } else if (event == 'hide' || event == 'blur') {
          _focused = false;
          await _endRemote();
        } else if (event == 'focus' || event == 'show') {
          _focused = true;
          _foreground = true;
          await _refreshRemote();
        }
        return true;
      case 'boundsChanged':
        final bounds = _rectFromMap(call.arguments);
        _videoPopupLog(
          'VideoPopupWindow received boundsChanged raw=${call.arguments} '
          'parsed=$bounds',
        );
        if (bounds != null) {
          await _settings.setVideoPopupBounds(bounds);
        }
        return true;
      default:
        throw MissingPluginException(
          'Unknown Windows video popup method ${call.method}',
        );
    }
  }

  Future<void> _startVideo() async {
    await _videoManager.initialize();
    if (!mounted || _disposed) return;
    _videoStateSubscription = _videoManager.stateStream.listen(
      _onVideoStateChanged,
    );
    await _videoManager.autoConnect();
    _onVideoStateChanged(_videoManager.currentState);
  }

  void _onVideoStateChanged(VideoStreamState videoState) {
    if (!mounted || _disposed) return;
    final stream = videoState.maybeWhen(
      streaming: (videoStream, width, height, fps) => videoStream,
      orElse: () => null,
    );

    if (stream == null) {
      _connectedStream = null;
      _videoFrameCubit.disconnect();
      if (mounted) setState(() {});
      return;
    }

    if (!identical(stream, _connectedStream)) {
      _connectedStream = stream;
      _videoFrameCubit.connectToStream(stream);
    }
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _getHardwareScreenshot() async {
    if (_windowsNative) {
      return _windowsVideoPopupChannel.invokeMethod<Uint8List>(
        'getHardwareScreenshot',
      );
    }
    return _channel.invokeMethod<Uint8List>('getHardwareScreenshot');
  }

  Future<void> _setDisplayMode(DisplayMode mode) async {
    if (_windowsNative) {
      _videoPopupLog('setDisplayMode via Windows native channel mode=$mode');
      await _windowsVideoPopupChannel.invokeMethod('setDisplayMode', mode.name);
    } else {
      await _channel.invokeMethod('setDisplayMode', mode.name);
    }
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_alwaysOnTop;
    if (_windowsNative) {
      _videoPopupLog('setAlwaysOnTop via Windows native channel next=$next');
      await _windowsVideoPopupChannel.invokeMethod('setAlwaysOnTop', {
        'alwaysOnTop': next,
      });
    } else {
      await windowManager.setAlwaysOnTop(next);
    }
    await _settings.setVideoPopupAlwaysOnTop(next);
    if (mounted) {
      setState(() {
        _alwaysOnTop = next;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    final frame = _lastFrame;
    if (frame == null) return;
    Pasteboard.writeImage(frame);
  }

  Future<void> _saveBounds() async {
    final bounds = _windowsNative
        ? await getWindowsVideoPopupBounds()
        : await windowManager.getBounds();
    await _settings.setVideoPopupBounds(bounds);
  }

  @override
  void onWindowMoved() => unawaited(_saveBounds());

  @override
  void onWindowResized() => unawaited(_saveBounds());

  @override
  void onWindowClose() => unawaited(_closeWindow());

  Future<void> _closeWindow() async {
    _focused = false;
    try {
      await _endRemote(detach: !Platform.isLinux);
      await _saveBounds();
    } finally {
      if (Platform.isLinux) {
        await windowManager.hide();
      } else {
        await windowManager.destroy();
      }
    }
  }

  @override
  void onWindowBlur() {
    _focused = false;
    unawaited(_endRemote());
  }

  @override
  void onWindowFocus() {
    _focused = true;
    unawaited(_refreshRemote());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_active) {
      unawaited(_refreshRemote());
    } else {
      unawaited(_endRemote());
    }
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _focused = event.state == ViewFocusState.focused;
    if (_active) {
      unawaited(_refreshRemote());
    } else {
      unawaited(_endRemote());
    }
  }

  Future<Object?> _invoke(String method, Object? arguments) => _windowsNative
      ? _windowsVideoPopupChannel.invokeMethod(method, arguments)
      : _channel.invokeMethod(method, arguments);

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  void _reportChannelError(Object error) {
    if (!mounted || _disposed) return;
    final authoritativeFailure = switch (error) {
      PlatformException(code: 'remote_failed') ||
      WindowChannelException(code: 'remote_failed') => _remote.error,
      _ => null,
    };
    if (authoritativeFailure != null) {
      unawaited(
        _invoke(VideoPopupRemoteContract.close, {
          'hostId': _hostId,
        }).catchError((Object _) => null),
      );
      return; // The authoritative snapshot already announced this failure.
    }
    final message = 'Remote input failed; device state is unknown. $error';
    if (_channelError == message) return;
    setState(() {
      _channelError = message;
      _remote = RemoteControlState(
        connectionId: _remote.connectionId,
        potValues: _remote.potValues,
        unavailableReason: _remote.unavailableReason,
        error: message,
      );
    });
    _announce(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
    // A lost result may follow a delivered push. Cleanup is best-effort on the
    // original host; never retry the gesture or claim a hardware release.
    unawaited(
      _invoke(VideoPopupRemoteContract.close, {
        'hostId': _hostId,
      }).catchError((Object _) => null),
    );
  }

  Future<void> _request(
    String method, [
    Map<String, Object?> extra = const {},
  ]) async {
    final generation = _generation;
    Object? result;
    try {
      result = await _invoke(method, {
        'hostId': _hostId,
        if (_windowId != null) 'windowId': _windowId,
        ...extra,
      });
    } catch (error) {
      if (!mounted || _disposed || generation != _generation) return;
      final details = switch (error) {
        PlatformException(:final details) => details,
        WindowChannelException(:final details) => details,
        _ => null,
      };
      if (details != null) _acceptSnapshot(details);
      if (extra['connectionId'] != null &&
          extra['connectionId'] != _remote.connectionId) {
        return;
      }
      if (extra['sessionId'] != null &&
          extra['sessionId'] != _remote.sessionId &&
          _remote.error == null) {
        return;
      }
      rethrow;
    }
    if (!mounted || _disposed || generation != _generation) return;
    _acceptSnapshot(result);
  }

  void _acceptSnapshot(Object? result) {
    final data = VideoPopupRemoteContract.map(result);
    if (data['hostId'] != _hostId) {
      throw const FormatException('Stale remote host response.');
    }
    final next = VideoPopupRemoteContract.decodeSnapshot(data);
    final revision = VideoPopupRemoteContract.integer(data, 'revision');
    if (revision <= _revision) return;
    _revision = revision;
    final previous = _remote;
    setState(() {
      _remote = _channelError == null
          ? next
          : RemoteControlState(
              connectionId: next.connectionId,
              potValues: next.potValues,
              unavailableReason: next.unavailableReason,
              error: _channelError,
            );
    });
    if (_channelError == null &&
        next.error != null &&
        next.error != previous.error) {
      _announce(next.error!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            next.error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } else if (next.unavailableReason != null &&
        next.unavailableReason != previous.unavailableReason) {
      _announce(next.unavailableReason!);
    }
  }

  Future<void> _refreshRemote() async {
    if (!_ready || !mounted || _reading || _closing) return;
    _reading = true;
    try {
      await _request(VideoPopupRemoteContract.read);
      if (mounted &&
          _remoteExpanded &&
          _active &&
          _remote.available &&
          _remote.sessionId == null &&
          _remote.error == null &&
          !_opening) {
        _opening = true;
        try {
          await _request(VideoPopupRemoteContract.open, {
            'connectionId': _remote.connectionId,
          });
        } finally {
          _opening = false;
        }
      }
    } catch (error) {
      _reportChannelError(error);
    } finally {
      _reading = false;
    }
  }

  Future<void> _endRemote({bool detach = false}) async {
    _generation++;
    if (mounted && !_disposed) {
      setState(
        () => _remote = RemoteControlState(
          connectionId: _remote.connectionId,
          potValues: _remote.potValues,
          unavailableReason: _remote.unavailableReason,
          error: _remote.error,
        ),
      );
    }
    try {
      await _request(
        detach
            ? VideoPopupRemoteContract.detach
            : VideoPopupRemoteContract.close,
      );
    } catch (error) {
      _reportChannelError(error);
    }
  }

  void _sendRemote(RemoteAction action) {
    if (!_active || !_remoteExpanded || _remote.sessionId == null) return;
    unawaited(
      _request(VideoPopupRemoteContract.action, {
        'connectionId': _remote.connectionId,
        'sessionId': _remote.sessionId,
        'action': VideoPopupRemoteContract.encodeAction(action),
      }).catchError(_reportChannelError),
    );
  }

  void _wheelRemote(int pushIndex, int adjustment) {
    final generation = _generation;
    final connectionId = _remote.connectionId;
    _wheelTail = _wheelTail
        .then<void>((_) async {
          bool current() =>
              mounted &&
              !_disposed &&
              !_closing &&
              _remoteExpanded &&
              generation == _generation &&
              connectionId == _remote.connectionId;
          if (!current()) return;
          if (_remote.sessionId == null) {
            await _request(VideoPopupRemoteContract.read);
            if (!current() || !_remote.available || _remote.error != null) {
              return;
            }
            await _request(VideoPopupRemoteContract.open, {
              'connectionId': _remote.connectionId,
            });
          }
          if (!current() || !_remote.available || _remote.sessionId == null) {
            return;
          }
          await _request(VideoPopupRemoteContract.action, {
            'connectionId': _remote.connectionId,
            'sessionId': _remote.sessionId,
            'action': pushIndex < 7
                ? {
                    'type': 'potAdjustment',
                    'index': pushIndex - 4,
                    'value': adjustment,
                  }
                : VideoPopupRemoteContract.encodeAction(
                    RemoteEncoderTurn(pushIndex - 7, adjustment),
                  ),
          });
        })
        .catchError(_reportChannelError);
  }

  void _adjustPot(int index, int adjustment) {
    if (!_active || !_remoteExpanded || _remote.sessionId == null) return;
    unawaited(
      _request(VideoPopupRemoteContract.action, {
        'connectionId': _remote.connectionId,
        'sessionId': _remote.sessionId,
        'action': {
          'type': 'potAdjustment',
          'index': index,
          'value': adjustment,
        },
      }).catchError(_reportChannelError),
    );
  }

  void _toggleRemote() {
    setState(() {
      _remoteExpanded = !_remoteExpanded;
      if (_remoteExpanded) _channelError = null;
    });
    _announce(
      _remoteExpanded ? 'Remote controls expanded' : 'Remote controls folded',
    );
    unawaited(_remoteExpanded ? _openRemoteExplicitly() : _endRemote());
    unawaited(_sizeForRemote().catchError(_reportChannelError));
  }

  Future<void> _openRemoteExplicitly() async {
    if (!_ready || !_active) return;
    try {
      await _request(VideoPopupRemoteContract.read);
      if (!mounted || !_active || !_remoteExpanded || !_remote.available) {
        return;
      }
      await _request(VideoPopupRemoteContract.open, {
        'connectionId': _remote.connectionId,
      });
    } catch (error) {
      _reportChannelError(error);
    }
  }

  Future<void> _sizeForRemote() async {
    if (_windowsNative) {
      await _windowsVideoPopupChannel.invokeMethod(
        'setRemoteExpanded',
        _remoteExpanded,
      );
    } else {
      final minimum = Size(
        _remoteExpanded ? RemoteControlCluster.width : 256,
        _remoteExpanded ? 352 : 100,
      );
      await windowManager.setMinimumSize(minimum);
      if (!mounted || !_remoteExpanded) return;
      final size = await windowManager.getSize();
      if (!mounted || !_remoteExpanded) return;
      if (size.width < minimum.width || size.height < minimum.height) {
        await windowManager.setSize(
          Size(
            size.width < minimum.width ? minimum.width : size.width,
            size.height < minimum.height ? minimum.height : size.height,
          ),
        );
      }
    }
  }

  void _startToolbarHideTimer({Duration? delay}) {
    if (_settings.videoToolbarAlwaysVisible ||
        _toolbarHovering ||
        _toolbarFocused) {
      return;
    }
    _toolbarHideTimer?.cancel();
    _toolbarHideTimer = Timer(delay ?? const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _toolbarVisible = false;
        });
      }
    });
  }

  void _showToolbar() {
    _toolbarHideTimer?.cancel();
    if (!_toolbarVisible) {
      setState(() {
        _toolbarVisible = true;
      });
    }
    _startToolbarHideTimer();
  }

  @override
  void dispose() {
    _disposed = true;
    _closing = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _remoteTimer?.cancel();
    unawaited(_endRemote(detach: true));
    if (_windowsNative) {
      _windowsVideoPopupChannel.setMethodCallHandler(null);
    } else {
      windowManager.removeListener(this);
      unawaited(_controller?.setWindowMethodHandler(null));
    }
    _toolbarHideTimer?.cancel();
    _videoStateSubscription?.cancel();
    _videoFrameCubit.disconnect();
    unawaited(_videoFrameCubit.close());
    // Initialization can still be awaiting the existing platform stream. Do not
    // close its state controller underneath that asynchronous startup.
    unawaited(
      _videoStartup?.then(
        (_) => _videoManager.dispose(),
        onError: (Object _) => _videoManager.dispose(),
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _settings.videoToolbarAlwaysVisibleNotifier,
      builder: (context, alwaysShowToolbar, _) {
        final showToolbar =
            alwaysShowToolbar ||
            _toolbarVisible ||
            _toolbarFocused ||
            MediaQuery.of(context).accessibleNavigation;

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: MouseRegion(
              onEnter: (_) {
                _toolbarHovering = true;
                _showToolbar();
              },
              onExit: (_) {
                _toolbarHovering = false;
                _startToolbarHideTimer(
                  delay: const Duration(milliseconds: 350),
                );
              },
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    top: 36,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final remoteHeight = _remoteExpanded
                            ? (constraints.maxHeight - 64).clamp(
                                0.0,
                                RemoteControlCluster.height,
                              )
                            : 0.0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SizedBox.expand(
                                key: const ValueKey('popup-video-bounds'),
                                child: VideoPopupContent(
                                  manager: _videoManager,
                                  videoFrameCubit: _videoFrameCubit,
                                  displayFrame: _displayFrame,
                                  onCopyToClipboard: _copyToClipboard,
                                  onFrameUpdate: (frameData) {
                                    final stableBytes = Uint8List.fromList(
                                      frameData,
                                    );
                                    final previousFrame = _displayFrame;
                                    _lastFrame = stableBytes;
                                    _displayFrame = stableBytes;
                                    if (previousFrame != null) {
                                      MemoryImage(previousFrame).evict();
                                    }
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) setState(() {});
                                        });
                                  },
                                ),
                              ),
                            ),
                            if (_remoteExpanded)
                              SizedBox(
                                height: remoteHeight,
                                child: RemoteControlCluster(
                                  state: _remote,
                                  onAction: _sendRemote,
                                  onPotAdjustment: _adjustPot,
                                  onWheelAdjustment: _wheelRemote,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36,
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (focused) {
                        setState(() => _toolbarFocused = focused);
                        if (focused) {
                          _showToolbar();
                        } else {
                          _startToolbarHideTimer();
                        }
                      },
                      child: IgnorePointer(
                        ignoring: !showToolbar,
                        child: ClipRect(
                          child: AnimatedSlide(
                            offset: showToolbar
                                ? Offset.zero
                                : const Offset(0, -1),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: VideoPopupTopBar(
                              alwaysOnTop: _alwaysOnTop,
                              onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                              onSetDisplayMode: _setDisplayMode,
                              remoteExpanded: _remoteExpanded,
                              onToggleRemote: _toggleRemote,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class VideoPopupTopBar extends StatelessWidget {
  const VideoPopupTopBar({
    super.key,
    required this.alwaysOnTop,
    required this.onToggleAlwaysOnTop,
    required this.onSetDisplayMode,
    this.remoteExpanded = false,
    this.onToggleRemote,
  });

  final bool alwaysOnTop;
  final VoidCallback onToggleAlwaysOnTop;
  final ValueChanged<DisplayMode> onSetDisplayMode;
  final bool remoteExpanded;
  final VoidCallback? onToggleRemote;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _displayModeButton(
                    Icons.list_alt_rounded,
                    'Parameter View',
                    DisplayMode.parameters,
                  ),
                  _displayModeButton(
                    Icons.line_axis_rounded,
                    'Algorithm UI',
                    DisplayMode.algorithmUI,
                  ),
                  _displayModeButton(
                    Icons.line_weight_rounded,
                    'Overview UI',
                    DisplayMode.overview,
                  ),
                  _displayModeButton(
                    Icons.leaderboard_rounded,
                    'Overview VU Meters',
                    DisplayMode.overviewVUs,
                  ),
                ],
              ),
            ),
            if (onToggleRemote != null)
              MergeSemantics(
                child: Semantics(
                  expanded: remoteExpanded,
                  child: TextButton.icon(
                    key: const ValueKey('video-remote-fold'),
                    onPressed: onToggleRemote,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12),
                      fixedSize: const Size(80, 36),
                      minimumSize: const Size(80, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: Icon(
                      remoteExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                    label: const Text('Remote'),
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Keep video window on top',
              icon: Icon(
                alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                size: 18,
                color: Colors.white,
              ),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                minimumSize: const Size(36, 36),
                maximumSize: const Size(36, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              isSelected: alwaysOnTop,
              onPressed: onToggleAlwaysOnTop,
            ),
          ],
        ),
      ),
    );
  }

  Widget _displayModeButton(IconData icon, String tooltip, DisplayMode mode) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: Colors.white),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        maximumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => onSetDisplayMode(mode),
    );
  }
}

class VideoPopupContent extends StatelessWidget {
  const VideoPopupContent({
    super.key,
    required this.manager,
    required this.videoFrameCubit,
    required this.displayFrame,
    required this.onCopyToClipboard,
    required this.onFrameUpdate,
  });

  final UsbVideoManager manager;
  final VideoFrameCubit videoFrameCubit;
  final Uint8List? displayFrame;
  final VoidCallback onCopyToClipboard;
  final ValueChanged<Uint8List> onFrameUpdate;

  static const int _fadeInFrames = 8;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VideoFrameCubit, VideoFrameState>(
      bloc: videoFrameCubit,
      builder: (context, frameState) {
        return frameState.when((frameData, frameCounter, lastFrameTime, fps) {
          if (frameData != null && frameData.length > 10) {
            onFrameUpdate(frameData);
          }

          final bytesToDisplay = displayFrame ?? frameData;
          if (bytesToDisplay == null) {
            return _buildStatus(context);
          }

          final framesIntoFade = frameCounter.clamp(0, _fadeInFrames);
          final fadeT = (framesIntoFade / _fadeInFrames).clamp(0.0, 1.0);
          final opacity = 0.3 + 0.7 * Curves.easeOut.transform(fadeT);

          return Semantics(
            label: 'Disting NT display. Long press to copy frame to clipboard.',
            child: GestureDetector(
              onLongPress: onCopyToClipboard,
              child: SizedBox.expand(
                child: RepaintBoundary(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Opacity(
                      opacity: opacity,
                      child: Image.memory(
                        bytesToDisplay,
                        key: const ValueKey('video_popup_frame'),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }, initial: () => _buildStatus(context));
      },
    );
  }

  Widget _buildStatus(BuildContext context) {
    final state = manager.currentState;
    final errorMessage = state.maybeWhen(
      error: (message) => message,
      orElse: () => null,
    );
    final isConnecting = state.maybeWhen(
      connecting: () => true,
      orElse: () => false,
    );

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: errorMessage == null
            ? Semantics(
                liveRegion: true,
                label: isConnecting
                    ? 'Connecting to Disting NT video'
                    : 'Waiting for Disting NT video',
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      errorMessage,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => unawaited(manager.autoConnect()),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

Future<void> configureVideoPopupWindow() async {
  final settings = SettingsService();
  final bounds = Rect.fromLTWH(
    settings.videoPopupBoundsX,
    settings.videoPopupBoundsY,
    settings.videoPopupBoundsWidth,
    settings.videoPopupBoundsHeight,
  );

  final hasSavedPosition = bounds.left >= 0 && bounds.top >= 0;
  const minSize = Size(256, 100);
  final initialSize = Size(
    bounds.width.clamp(minSize.width, 1024).toDouble(),
    bounds.height.clamp(minSize.height, 320).toDouble(),
  );

  if (Platform.isWindows) {
    _videoPopupLog(
      'configureVideoPopupWindow via Windows native channel '
      'hasSavedPosition=$hasSavedPosition bounds=$bounds '
      'initialSize=$initialSize '
      'alwaysOnTop=${settings.videoPopupAlwaysOnTop}',
    );
    await _windowsVideoPopupChannel.invokeMethod('configureVideoPopup', {
      'x': hasSavedPosition ? bounds.left : null,
      'y': hasSavedPosition ? bounds.top : null,
      'width': initialSize.width,
      'height': initialSize.height,
      'center': !hasSavedPosition,
      'alwaysOnTop': settings.videoPopupAlwaysOnTop,
      'title': 'Disting NT Video',
    });
    return;
  }

  final options = WindowOptions(
    size: initialSize,
    minimumSize: minSize,
    center: !hasSavedPosition,
    backgroundColor: Colors.black,
    skipTaskbar: false,
    title: 'Disting NT Video',
    alwaysOnTop: settings.videoPopupAlwaysOnTop ? true : null,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    if (Platform.isLinux) {
      await windowManager.setPreventClose(true);
    }
    if (hasSavedPosition) {
      await windowManager.setBounds(bounds);
    }
    await windowManager.show();
    await raiseVideoPopupWindow();
  });
}

Future<void> raiseVideoPopupWindow() async {
  if (Platform.isWindows) {
    _videoPopupLog('raiseVideoPopupWindow via Windows native channel');
    await _windowsVideoPopupChannel.invokeMethod('raiseCurrentWindow');
    return;
  }
  await windowManager.focus();
}

Future<Rect> getWindowsVideoPopupBounds() async {
  final result = await _windowsVideoPopupChannel
      .invokeMapMethod<String, dynamic>('getBounds');
  final bounds = _rectFromMap(result);
  _videoPopupLog('getWindowsVideoPopupBounds raw=$result parsed=$bounds');
  if (bounds != null) return bounds;
  return Rect.zero;
}

Rect? _rectFromMap(Object? value) {
  if (value is! Map) {
    return null;
  }

  final x = (value['x'] as num?)?.toDouble();
  final y = (value['y'] as num?)?.toDouble();
  final width = (value['width'] as num?)?.toDouble();
  final height = (value['height'] as num?)?.toDouble();
  if (x == null || y == null || width == null || height == null) {
    return null;
  }
  return Rect.fromLTWH(x, y, width, height);
}
