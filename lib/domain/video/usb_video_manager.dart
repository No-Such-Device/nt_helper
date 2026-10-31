import 'dart:async';

import 'package:clock/clock.dart';

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:nt_helper/domain/video/usb_device_info.dart';
import 'package:nt_helper/domain/video/video_stream_state.dart';
import 'package:nt_helper/services/platform_channels/usb_video_channel.dart';
import 'package:nt_helper/services/debug_service.dart';

class UsbVideoManager {
  final UsbVideoChannel _channel;
  final Clock _clock = clock;
  final DebugService _debugService = DebugService();

  UsbVideoManager({
    UsbVideoChannel? channel,
    Future<Uint8List?> Function()? takeScreenshot,
  }) : _channel = channel ?? UsbVideoChannel(),
       _takeScreenshot = takeScreenshot;

  final Future<Uint8List?> Function()? _takeScreenshot;
  StreamController<Uint8List>? _screenshotController;
  Timer? _screenshotTimer;
  int _screenshotGeneration = 0;
  StreamController<VideoStreamState>? _stateController;
  Timer? _recoveryTimer;
  Timer? _stallWatchdogTimer;
  bool _disposed = false;
  int _connectionGeneration = 0;
  String? _lastConnectedDeviceId;
  DateTime? _lastFrameReceivedTime;
  Duration _currentBackoffDuration = _minBackoffDuration;

  Stream<VideoStreamState> get stateStream =>
      _stateController?.stream ?? const Stream.empty();

  VideoStreamState _currentState = const VideoStreamState.disconnected();
  VideoStreamState get currentState => _currentState;

  static const int distintgVendorId = 0x16C0; // Expert Sleepers vendor ID

  // Exponential backoff configuration
  static const Duration _minBackoffDuration = Duration(seconds: 2);
  static const Duration _maxBackoffDuration = Duration(seconds: 60);

  // Stall detection: consider stalled if no frames for this duration
  static const Duration _stallThreshold = Duration(seconds: 3);
  static const Duration _stallCheckInterval = Duration(seconds: 1);

  void _debugLog(String message) {
    _debugService.addLocalMessage('[UsbVideoManager] $message');
  }

  Future<void> initialize() async {
    _stateController ??= StreamController<VideoStreamState>.broadcast();
    _updateState(const VideoStreamState.disconnected());
  }

  Future<bool> isSupported() async {
    try {
      final supported = await _channel.isSupported();
      _debugLog('isSupported() returned: $supported');
      return supported;
    } catch (e) {
      _debugLog('ERROR checking video support: $e');
      return false;
    }
  }

  Future<List<UsbDeviceInfo>> listUsbCameras() async {
    try {
      final devices = await _channel.listUsbCameras();
      for (var _ in devices) {}
      return devices;
    } catch (e) {
      return [];
    }
  }

  Future<UsbDeviceInfo?> findDistingNT() async {
    final devices = await listUsbCameras();
    try {
      return devices.firstWhere((device) => device.isDistingNT);
    } catch (e) {
      // No Disting NT found
      return null;
    }
  }

  Future<void> connectToDevice(String deviceId) async {
    if (_disposed) return;
    final generation = ++_connectionGeneration;
    _stopScreenshotFallback();
    try {
      _debugLog('Connecting to device: $deviceId');
      _updateState(const VideoStreamState.connecting());

      // Request permission if needed (Android)
      final hasPermission = await _channel.requestUsbPermission(deviceId);
      if (_disposed || generation != _connectionGeneration) return;
      _debugLog('USB permission: $hasPermission');
      if (!hasPermission) {
        _updateState(const VideoStreamState.error('USB permission denied'));
        _startRecoveryTimer();
        return;
      }

      // Start video stream
      _debugLog('Starting video stream...');
      final videoStream = _channel.startVideoStream(deviceId);

      // Add debug monitoring to the stream and track frame reception
      final monitoredStream = videoStream.map((data) {
        _debugLog(
          'Received frame data: ${data?.runtimeType} ${data is Uint8List ? data.length : 'unknown'} bytes',
        );
        // Track frame reception time for stall detection
        _onFrameReceived();
        return data;
      });

      // Wait a moment to ensure the platform channel is fully set up
      await Future.delayed(const Duration(milliseconds: 100));
      if (_disposed || generation != _connectionGeneration) return;

      // Store the device ID for recovery attempts
      _lastConnectedDeviceId = deviceId;

      // Stop any recovery timer since we're now connected
      _stopRecoveryTimer();

      // Treat the stream as "alive" from now so a missing first-frame is
      // detected as a stall by the watchdog.
      _lastFrameReceivedTime = _clock.now();

      // Start stall watchdog to detect if frames stop coming
      _startStallWatchdog();

      // Set to streaming state with monitored stream
      _updateState(
        VideoStreamState.streaming(
          videoStream: monitoredStream,
          width: 256, // Disting NT display width
          height: 64, // Disting NT display height
          fps: 30.0, // Target FPS (matches native throttling)
        ),
      );
    } catch (e) {
      if (_disposed || generation != _connectionGeneration) return;
      _updateState(
        VideoStreamState.error('Device disconnected or unavailable'),
      );
      _startRecoveryTimer();
    }
  }

  /// Get the raw video stream for direct consumption by VideoFrameCubit
  Stream<dynamic>? getRawVideoStream() {
    return _currentState.maybeWhen(
      streaming: (stream, width, height, fps) => stream,
      orElse: () => null,
    );
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    final generation = ++_connectionGeneration;
    _stopScreenshotFallback();
    _stopRecoveryTimer();
    _stopStallWatchdog();
    try {
      await _channel.stopVideoStream();
      if (_disposed || generation != _connectionGeneration) return;
      _stopRecoveryTimer();
      _stopStallWatchdog();
      _lastFrameReceivedTime = null;
      _resetBackoff();
      _updateState(const VideoStreamState.disconnected());
    } catch (e) {
      // Intentionally empty
    }
  }

  Future<void> autoConnect() async {
    if (_disposed) return;
    final generation = ++_connectionGeneration;
    _stopScreenshotFallback();
    // First check if video is supported on this platform
    final supported = await isSupported();
    if (_disposed || generation != _connectionGeneration) return;
    if (!supported) {
      _updateState(
        const VideoStreamState.error(
          'USB video not supported on this platform',
        ),
      );
      return;
    }

    final distingNT = await findDistingNT();
    if (_disposed || generation != _connectionGeneration) return;
    if (distingNT != null) {
      await connectToDevice(distingNT.deviceId);
    } else {
      _updateState(const VideoStreamState.error('Disting NT video not found'));
    }
  }

  void _updateState(
    VideoStreamState newState, {
    bool allowScreenshotFallback = true,
  }) {
    if (_disposed) return;
    if (allowScreenshotFallback &&
        _takeScreenshot != null &&
        newState.maybeWhen(error: (_) => true, orElse: () => false)) {
      _startScreenshotFallback();
      return;
    }
    _currentState = newState;
    _stateController?.add(newState);
  }

  // Use the existing display stream, but only request the next screenshot after
  // the previous capture completes. Closing a host cancels pending refreshes and
  // invalidates any in-flight response.
  void _startScreenshotFallback() {
    if (_disposed || _screenshotController != null) return;
    _stopRecoveryTimer();
    _stopStallWatchdog();
    final generation = ++_screenshotGeneration;
    final controller = StreamController<Uint8List>(
      onListen: () => unawaited(_pollScreenshot(generation)),
      onCancel: _stopScreenshotFallback,
    );
    _screenshotController = controller;
    _updateState(
      VideoStreamState.streaming(
        videoStream: controller.stream,
        width: 266,
        height: 74,
        fps: 1,
      ),
    );
  }

  Future<void> _pollScreenshot(int generation) async {
    if (generation != _screenshotGeneration) return;
    try {
      final screenshot = await _takeScreenshot!();
      if (generation != _screenshotGeneration) return;
      if (screenshot == null || screenshot.isEmpty) {
        throw StateError('Screenshot unavailable');
      }
      _screenshotController?.add(screenshot);
      _screenshotTimer = Timer(const Duration(seconds: 1), () {
        unawaited(_pollScreenshot(generation));
      });
    } catch (_) {
      if (generation != _screenshotGeneration) return;
      _stopScreenshotFallback();
      _updateState(
        const VideoStreamState.error(
          'USB video unavailable and screenshot capture failed',
        ),
        allowScreenshotFallback: false,
      );
    }
  }

  void _stopScreenshotFallback() {
    _screenshotGeneration++;
    _screenshotTimer?.cancel();
    _screenshotTimer = null;
    final controller = _screenshotController;
    _screenshotController = null;
    unawaited(controller?.close());
  }

  void _startRecoveryTimer() {
    if (_disposed) return;
    _stopRecoveryTimer(); // Cancel any existing timer

    _debugLog(
      'Starting recovery timer with ${_currentBackoffDuration.inSeconds}s backoff',
    );

    final generation = _connectionGeneration;
    _recoveryTimer = Timer(_currentBackoffDuration, () async {
      if (_disposed || generation != _connectionGeneration) return;
      // Only attempt recovery if we're in error state
      if (!_currentState.maybeWhen(error: (_) => true, orElse: () => false)) {
        _stopRecoveryTimer();
        return;
      }

      // Increase backoff for next attempt (exponential, capped at max)
      _currentBackoffDuration = Duration(
        milliseconds: (_currentBackoffDuration.inMilliseconds * 2).clamp(
          _minBackoffDuration.inMilliseconds,
          _maxBackoffDuration.inMilliseconds,
        ),
      );

      // Try to reconnect to the last known device if it's still a Disting NT
      if (_lastConnectedDeviceId != null) {
        final devices = await listUsbCameras();
        if (_disposed || generation != _connectionGeneration) return;
        final targetDevice = devices
            .where((d) => d.deviceId == _lastConnectedDeviceId && d.isDistingNT)
            .firstOrNull;

        if (targetDevice != null) {
          await connectToDevice(_lastConnectedDeviceId!);
          return;
        }
      }

      // Fallback: try to find any Disting NT
      await autoConnect();

      // If still in error state after autoConnect, schedule another attempt
      if (_currentState.maybeWhen(error: (_) => true, orElse: () => false)) {
        _startRecoveryTimer();
      }
    });
  }

  void _stopRecoveryTimer() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
  }

  void _resetBackoff() {
    _currentBackoffDuration = _minBackoffDuration;
    _debugLog('Backoff reset to ${_minBackoffDuration.inSeconds}s');
  }

  /// Called when a frame is received from the video stream
  void _onFrameReceived() {
    final now = _clock.now();
    final wasStalled =
        _lastFrameReceivedTime != null &&
        now.difference(_lastFrameReceivedTime!) > _stallThreshold;

    _lastFrameReceivedTime = now;

    // If we were stalled and frames resumed, reset backoff
    if (wasStalled) {
      _debugLog('Frames resumed after stall - resetting backoff');
      _resetBackoff();
    }
  }

  void _startStallWatchdog() {
    _stopStallWatchdog();

    _stallWatchdogTimer = Timer.periodic(_stallCheckInterval, (timer) {
      // Only check for stalls during streaming state
      final isStreaming = _currentState.maybeWhen(
        streaming: (stream, width, height, fps) => true,
        orElse: () => false,
      );
      if (!isStreaming) {
        return;
      }

      // Check if frames have stalled
      if (_lastFrameReceivedTime != null) {
        final timeSinceLastFrame = _clock.now().difference(
          _lastFrameReceivedTime!,
        );
        if (timeSinceLastFrame > _stallThreshold) {
          _debugLog(
            'Frame stall detected: ${timeSinceLastFrame.inSeconds}s since last frame',
          );
          _handleStall();
        }
      }
    });
  }

  void _stopStallWatchdog() {
    _stallWatchdogTimer?.cancel();
    _stallWatchdogTimer = null;
  }

  Future<void> _handleStall() async {
    final generation = _connectionGeneration;
    _stopStallWatchdog();
    _debugLog('Handling stall - disconnecting and attempting recovery');

    // Stop the current stream
    try {
      await _channel.stopVideoStream();
    } catch (e) {
      _debugLog('Error stopping stream during stall recovery: $e');
    }

    if (_disposed || generation != _connectionGeneration) return;

    // Set error state and start recovery
    _updateState(const VideoStreamState.error('Video stream stalled'));
    _startRecoveryTimer();
  }

  /// Called when app enters background (lifecycle pause)
  Future<void> pauseForLifecycle() async {
    _debugLog('Pausing for app lifecycle event');
    await _channel.pauseStreaming();
  }

  /// Called when app returns to foreground (lifecycle resume)
  Future<void> resumeForLifecycle() async {
    _debugLog('Resuming from app lifecycle event');
    await _channel.resumeStreaming();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connectionGeneration++;
    _stopScreenshotFallback();
    _stopRecoveryTimer();
    _stopStallWatchdog();
    _stateController?.close();
    await _channel.stopVideoStream();
    await _channel.dispose();
  }
}
