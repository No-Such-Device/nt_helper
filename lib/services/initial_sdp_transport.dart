import 'package:flutter/services.dart';

/// Development-only iPad DriverKit boundary. Detection, connection, and protocol
/// response are separate observations; callers must never infer one from another.
abstract interface class InitialSdpTransport {
  Future<Map<String, dynamic>> availability();
  Stream<Map<String, dynamic>> get events;
  Future<void> observe();
  Future<void> connect();
  Future<InitialSdpResponse> errorStatus();
  Future<void> close();
}

class InitialSdpResponse {
  final int hab;
  final int status;

  const InitialSdpResponse({required this.hab, required this.status});
}

/// The native channel is registered only by the isolated development app target.
/// There is deliberately no generic selector, payload, or device-ID API.
class MethodChannelInitialSdpTransport implements InitialSdpTransport {
  static const _methods = MethodChannel('com.example.nt_helper/initial_sdp');
  static const _events = EventChannel(
    'com.example.nt_helper/initial_sdp_events',
  );

  @override
  Future<Map<String, dynamic>> availability() async =>
      (await _methods.invokeMapMethod<String, dynamic>('availability'))!;

  @override
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  @override
  Future<void> observe() => _methods.invokeMethod<void>('observe');

  @override
  Future<void> connect() => _methods.invokeMethod<void>('connect');

  @override
  Future<InitialSdpResponse> errorStatus() async {
    final reply = await _methods.invokeMapMethod<String, dynamic>(
      'errorStatus',
    );
    if (reply == null ||
        reply['stage'] != 'response' ||
        reply['hab'] is! int ||
        reply['status'] is! int) {
      throw const FormatException('Malformed initial SDP status response');
    }
    return InitialSdpResponse(
      hab: reply['hab'] as int,
      status: reply['status'] as int,
    );
  }

  @override
  Future<void> close() => _methods.invokeMethod<void>('close');
}
