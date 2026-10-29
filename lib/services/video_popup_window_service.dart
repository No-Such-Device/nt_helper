import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/video_popup_remote_contract.dart';

class VideoPopupWindowService {
  VideoPopupWindowService._();

  @visibleForTesting
  VideoPopupWindowService({
    required bool windowsNative,
    BinaryMessenger? binaryMessenger,
  }) : _windowsNativeOverride = windowsNative,
       _nativeChannelOverride = MethodChannel(
         'nt_helper/windows_video_popup',
         const StandardMethodCodec(),
         binaryMessenger,
       );

  bool? _windowsNativeOverride;
  MethodChannel? _nativeChannelOverride;
  MethodChannel get _nativeChannel =>
      _nativeChannelOverride ?? _windowsNativeChannel;
  bool get _usesWindowsNative => _windowsNativeOverride ?? Platform.isWindows;
  static final VideoPopupWindowService instance = VideoPopupWindowService._();
  static const windowType = 'video-popup';
  static const windowsNativeEntryPointArg = 'windows_video_popup';
  static const raiseMethod = 'raiseVideoPopup';
  static const _channel = WindowMethodChannel(
    'nt_helper/video_popup',
    mode: ChannelMode.unidirectional,
  );
  static const _windowsNativeChannel = MethodChannel(
    'nt_helper/windows_video_popup',
  );

  DistingCubit? _cubit;
  bool _handlerRegistered = false;
  String? _remoteHost;
  String? _remoteWindow;
  String? _remoteSession;
  int _revision = 0;
  StreamSubscription<void>? _windowsSubscription;

  static String get windowArguments => jsonEncode({'type': windowType});

  static bool isVideoPopupArguments(String arguments) {
    if (arguments.isEmpty) return false;
    try {
      final decoded = jsonDecode(arguments);
      return decoded is Map && decoded['type'] == windowType;
    } catch (_) {
      return false;
    }
  }

  static bool isWindowsNativeVideoPopupArguments(List<String> args) =>
      args.length >= 2 &&
      args.first == windowsNativeEntryPointArg &&
      isVideoPopupArguments(args[1]);

  bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> registerMainCubit(DistingCubit cubit) async {
    if (!identical(_cubit, cubit)) await _detachRemoteHost();
    _cubit = cubit;
    await _ensureHandlerRegistered();
  }

  Future<bool> open(DistingCubit cubit) async {
    if (!isSupported) return false;
    await registerMainCubit(cubit);
    if (_usesWindowsNative) {
      return await _nativeChannel.invokeMethod<bool>('openOrFocus', {
            'arguments': windowArguments,
          }) ??
          true;
    }
    final existing = await _findExistingWindow();
    if (existing != null) {
      await existing.show();
      try {
        await existing.invokeMethod(raiseMethod);
      } on MissingPluginException {
        // Older running popup instances may not have the raise handler yet.
      }
      return true;
    }
    await WindowController.create(
      WindowConfiguration(arguments: windowArguments, hiddenAtLaunch: true),
    );
    return true;
  }

  Future<void> _ensureHandlerRegistered() async {
    if (_handlerRegistered) return;
    if (_usesWindowsNative) {
      _nativeChannel.setMethodCallHandler(_handleMethodCall);
    } else {
      await _channel.setMethodCallHandler(_handleMethodCall);
      _windowsSubscription = onWindowsChanged.listen((_) {
        // Cleanup failures are retained in the connection authority's state.
        unawaited(_checkDestroyedWindow().catchError((Object _) {}));
      });
    }
    _handlerRegistered = true;
  }

  Future<WindowController?> _findExistingWindow() async {
    for (final controller in await WindowController.getAll()) {
      if (isVideoPopupArguments(controller.arguments)) return controller;
    }
    return null;
  }

  Future<void> _checkDestroyedWindow() async {
    final host = _remoteHost;
    final window = _remoteWindow;
    if (host == null || window == null) return;
    final windows = await WindowController.getAll();
    if (host != _remoteHost || windows.any((w) => w.windowId == window)) return;
    await _detachRemoteHost();
  }

  Future<void> _detachRemoteHost() async {
    final session = _remoteSession;
    _remoteHost = null;
    _remoteWindow = null;
    _remoteSession = null;
    if (session != null) await _cubit?.closeRemoteSession(session);
  }

  Future<void> dispose() async {
    await _windowsSubscription?.cancel();
    try {
      await _detachRemoteHost();
    } finally {
      if (_usesWindowsNative) {
        _nativeChannel.setMethodCallHandler(null);
      } else if (_handlerRegistered) {
        await _channel.setMethodCallHandler(null);
      }
      _handlerRegistered = false;
      _cubit = null;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'getHardwareScreenshot') {
      final cubit = _cubit;
      final state = cubit?.state;
      if (cubit == null ||
          cubit.isClosed ||
          state is! DistingStateSynchronized ||
          state.offline ||
          state.demo) {
        throw PlatformException(
          code: 'screenshot_unavailable',
          message: 'Screenshots require a synchronized live device.',
        );
      }
      return cubit.getHardwareScreenshot();
    }
    if (call.method.startsWith('remote')) {
      try {
        return await _handleRemote(call);
      } catch (error) {
        final arguments = call.arguments;
        final host = arguments is Map ? arguments['hostId'] : null;
        throw VideoPopupRemoteContract.failure(
          error,
          details: host is String && _cubit != null
              ? _snapshot(_cubit!, host)
              : null,
        );
      }
    }
    if (call.method == 'setDisplayMode') {
      final mode = DisplayMode.values
          .where((m) => m.name == call.arguments)
          .firstOrNull;
      if (mode == null) {
        throw PlatformException(
          code: 'invalid_display_mode',
          message: 'Unknown display mode: ${call.arguments}',
        );
      }
      _cubit?.setDisplayMode(mode);
      return true;
    }
    throw MissingPluginException('Unknown video popup method ${call.method}');
  }

  Future<Object?> _handleRemote(MethodCall call) async {
    final data = VideoPopupRemoteContract.map(call.arguments);
    final host = VideoPopupRemoteContract.host(data);
    final cubit = _cubit;
    if (cubit == null || cubit.isClosed) {
      throw StateError('The main connection authority is unavailable.');
    }
    if (call.method == VideoPopupRemoteContract.acquire) {
      if (data['windowId'] != null && data['windowId'] is! String) {
        throw const FormatException('Invalid popup window identity.');
      }
      final previous = _remoteSession;
      if (_remoteHost != host) _remoteSession = null;
      _remoteHost = host;
      _remoteWindow = data['windowId'] as String?;
      if (previous != null && _remoteSession == null) {
        await cubit.closeRemoteSession(previous);
        if (_remoteHost != host) {
          throw StateError('The popup host has changed.');
        }
      }
    } else if (_remoteHost != host) {
      throw StateError('The popup host is no longer active.');
    }
    switch (call.method) {
      case VideoPopupRemoteContract.acquire:
      case VideoPopupRemoteContract.read:
        break;
      case VideoPopupRemoteContract.open:
        final state = cubit.remoteControlState;
        if (data['connectionId'] != state.connectionId) {
          throw StateError('The remote connection has changed.');
        }
        if (!state.available) throw StateError(state.unavailableReason!);
        if (_remoteSession == null || _remoteSession != state.sessionId) {
          _remoteSession = cubit.openRemoteSession();
        }
      case VideoPopupRemoteContract.action:
        final payload = VideoPopupRemoteContract.map(data['action']);
        final adjustment = payload['type'] == 'potAdjustment';
        final action = adjustment
            ? null
            : VideoPopupRemoteContract.decodeAction(payload);
        final index = adjustment
            ? VideoPopupRemoteContract.integer(payload, 'index')
            : 0;
        final value = adjustment
            ? VideoPopupRemoteContract.integer(payload, 'value')
            : 0;
        final state = cubit.remoteControlState;
        if (!state.available ||
            data['connectionId'] != state.connectionId ||
            data['sessionId'] != _remoteSession ||
            _remoteSession == null ||
            _remoteSession != state.sessionId) {
          throw StateError(
            state.unavailableReason ?? 'The remote session has changed.',
          );
        }
        if (adjustment) {
          await cubit.adjustRemotePot(_remoteSession!, index, value);
        } else {
          await cubit.sendRemoteAction(_remoteSession!, action!);
        }
      case VideoPopupRemoteContract.close:
      case VideoPopupRemoteContract.detach:
        final session = _remoteSession;
        _remoteSession = null;
        if (call.method == VideoPopupRemoteContract.detach) {
          _remoteHost = null;
          _remoteWindow = null;
        }
        if (session != null) await cubit.closeRemoteSession(session);
      default:
        throw const FormatException('Unknown remote method.');
    }
    return _snapshot(cubit, host);
  }

  Map<String, Object?> _snapshot(DistingCubit cubit, String host) =>
      VideoPopupRemoteContract.snapshot(
        cubit.remoteControlState,
        host,
        ++_revision,
        host == _remoteHost ? _remoteSession : null,
      );
}
