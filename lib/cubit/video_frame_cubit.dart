import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/video_frame_state.dart';
import 'package:nt_helper/services/debug_service.dart';

class VideoFrameCubit extends Cubit<VideoFrameState> {
  VideoFrameCubit() : super(const VideoFrameState.initial());

  StreamSubscription<dynamic>? _frameSubscription;
  DateTime? _lastFrameTime;
  int _frameCounter = 0;
  final List<double> _fpsBuffer = [];
  static const int _fpsBufferSize = 10;
  final DebugService _debugService = DebugService();

  void _debugLog(String message) {
    _debugService.addLocalMessage('[VideoFrameCubit] $message');
  }

  /// Connect to a video stream and start receiving frames
  void connectToStream(Stream<dynamic> videoStream) {
    _debugLog('Connecting to video stream');

    // Cancel any existing subscription
    _frameSubscription?.cancel();

    // Reset counters
    _frameCounter = 0;
    _lastFrameTime = null;
    _fpsBuffer.clear();

    // Subscribe to the video stream
    _frameSubscription = videoStream.listen(
      _onFrameReceived,
      onError: (error) {
        _debugLog('Stream error: $error');
        _debugLog('Stream error type: ${error.runtimeType}');
        emit(const VideoFrameState.initial());
      },
      onDone: () {
        _debugLog(
          'Stream ended - this means the native side cancelled the stream',
        );
        emit(const VideoFrameState.initial());
      },
      cancelOnError: false, // Don't cancel on errors, keep trying
    );

    _debugLog('Stream subscription created successfully');
  }

  /// Handle incoming video frame
  void _onFrameReceived(dynamic data) {
    _debugLog(
      'Frame received: ${data.runtimeType}, size: ${data is Uint8List ? data.length : 'unknown'}',
    );

    // Handle FlutterStandardTypedData from iOS
    Uint8List frameData;
    try {
      if (data is Uint8List) {
        frameData = data;
        _debugLog('Data is already Uint8List, length: ${frameData.length}');
      } else if (data.runtimeType.toString() == 'FlutterStandardTypedData') {
        // Extract bytes from FlutterStandardTypedData
        final typedData = data as dynamic;
        frameData = typedData.data as Uint8List;
        _debugLog(
          'Extracted Uint8List from FlutterStandardTypedData, length: ${frameData.length}',
        );
      } else {
        _debugLog('ERROR: Unexpected data type: ${data.runtimeType}');
        return;
      }

      // USB video is BMP; the SysEx screenshot fallback returns PNG.
      final isPng =
          frameData.length >= 8 &&
          listEquals(frameData.sublist(0, 8), [
            137,
            80,
            78,
            71,
            13,
            10,
            26,
            10,
          ]);
      if (!isPng && frameData.length < 54) {
        _debugLog(
          'ERROR: Frame data too small for BMP (${frameData.length} bytes, need at least 54)',
        );
        return;
      }

      // Check BMP header
      if (!isPng && (frameData[0] != 0x42 || frameData[1] != 0x4D)) {
        _debugLog(
          'ERROR: Invalid BMP header: [${frameData[0]}, ${frameData[1]}] (expected [66, 77])',
        );
        return;
      }

      _debugLog(
        'BMP validation passed - header: [${frameData[0]}, ${frameData[1]}], size: ${frameData.length}',
      );
    } catch (e) {
      _debugLog('ERROR: Failed to extract or validate frame data: $e');
      _debugLog('Error stack trace: ${StackTrace.current}');
      return;
    }

    final now = DateTime.now();
    _frameCounter++;

    // Calculate FPS
    double currentFps = 0.0;
    if (_lastFrameTime != null) {
      final timeDiff = now.difference(_lastFrameTime!).inMicroseconds;
      if (timeDiff > 0) {
        final instantFps = 1000000.0 / timeDiff; // Convert microseconds to FPS
        _fpsBuffer.add(instantFps);

        // Keep buffer size limited
        if (_fpsBuffer.length > _fpsBufferSize) {
          _fpsBuffer.removeAt(0);
        }

        // Calculate average FPS
        currentFps = _fpsBuffer.reduce((a, b) => a + b) / _fpsBuffer.length;
      }
    }

    _lastFrameTime = now;

    // Emit new frame state
    try {
      emit(
        VideoFrameState(
          frameData: frameData,
          frameCounter: _frameCounter,
          lastFrameTime: now,
          fps: currentFps,
        ),
      );
      _debugLog(
        'Frame #$_frameCounter processed successfully, FPS: ${currentFps.toStringAsFixed(1)}',
      );
    } catch (e) {
      _debugLog('ERROR: Failed to emit frame state: $e');
      _debugLog('Emit error stack trace: ${StackTrace.current}');
      return;
    }
  }

  /// Disconnect from the video stream
  void disconnect() {
    _debugLog('Disconnecting from video stream');
    if (_frameSubscription != null) {
      _debugLog('Cancelling frame subscription');
      _frameSubscription?.cancel();
      _frameSubscription = null;
    } else {
      _debugLog('No active frame subscription to cancel');
    }
    emit(const VideoFrameState.initial());
  }

  @override
  Future<void> close() {
    _frameSubscription?.cancel();
    return super.close();
  }
}
