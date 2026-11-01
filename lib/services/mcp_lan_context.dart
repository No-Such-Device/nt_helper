import 'package:flutter/services.dart';

import 'mcp_lan_policy.dart';

/// Injectable feature boundary. A failed snapshot never supplies fallback context.
abstract interface class McpLanContext {
  Future<McpLanSnapshot> snapshot();
}

class MethodChannelMcpLanContext implements McpLanContext {
  final MethodChannel _channel;
  int _lastGeneration = 0;

  MethodChannelMcpLanContext({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.example.nt_helper/ipad_lan_context');

  Future<bool> isPad() async =>
      await _channel.invokeMethod<Object?>('idiom') == 'pad';

  void watch(void Function(bool failed) onChange) {
    _channel.setMethodCallHandler((call) async {
      onChange(call.method != 'networkChanged');
    });
  }

  void dispose() => _channel.setMethodCallHandler(null);

  @override
  Future<McpLanSnapshot> snapshot() async {
    final snapshot = McpLanSnapshot.decode(
      await _channel.invokeMethod<Object?>('snapshot'),
    );
    if (snapshot.pathGeneration < _lastGeneration) {
      throw const FormatException('Native path generation regressed');
    }
    _lastGeneration = snapshot.pathGeneration;
    return snapshot;
  }
}
