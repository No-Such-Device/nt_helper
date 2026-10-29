import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/video_popup_window_service.dart';

/// Exercises the installed WindowMethodChannel codec/dispatch and the native
/// MethodChannel contract. Windows C++ result forwarding is checked separately.
final class PopupChannelHarness {
  PopupChannelHarness(this.windows);
  final bool windows;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late final mainMessenger = TestDefaultBinaryMessenger(messenger);
  late final service = VideoPopupWindowService(
    windowsNative: windows,
    binaryMessenger: mainMessenger,
  );
  static const native = MethodChannel('nt_helper/windows_video_popup');
  static const desktop = MethodChannel('mixin.one/desktop_multi_window');
  static const channels = MethodChannel(
    'mixin.one/desktop_multi_window/channels',
  );
  static const manager = MethodChannel('window_manager');
  final calls = <MethodCall>[];
  Map<String, dynamic>? lastAction;
  bool failChannel = false;
  bool windowExists = true;
  Object? openResult = true;
  double height = 320;

  Future<Object?> incoming(
    TestDefaultBinaryMessenger target,
    String name,
    MethodCall call,
  ) async {
    final reply = Completer<ByteData?>();
    await target.handlePlatformMessage(
      name,
      const StandardMethodCodec().encodeMethodCall(call),
      reply.complete,
    );
    final bytes = await reply.future;
    if (bytes == null) throw MissingPluginException();
    return const StandardMethodCodec().decodeEnvelope(bytes);
  }

  Future<Object?> toMain(String method, Object? arguments) => windows
      ? incoming(mainMessenger, native.name, MethodCall(method, arguments))
      : incoming(
          messenger,
          channels.name,
          MethodCall('methodCall', {
            'channel': 'nt_helper/video_popup',
            'method': method,
            'arguments': arguments,
          }),
        );

  Future<Object?> lifecycle(String event) => windows
      ? incoming(messenger, native.name, MethodCall('remoteLifecycle', event))
      : incoming(
          messenger,
          manager.name,
          MethodCall('onEvent', {'eventName': event}),
        );

  Future<void> install(DistingCubit cubit) async {
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'registerMethodHandler' ||
          call.method == 'unregisterMethodHandler') {
        return null;
      }
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final method = args['method'] as String;
      final inner = args['arguments'];
      calls.add(MethodCall(method, inner));
      if (method == 'getHardwareScreenshot') return toMain(method, inner);
      if (method.startsWith('remote')) {
        if (method == 'remoteAction') {
          lastAction = Map<String, dynamic>.from(inner as Map);
        }
        if (failChannel) {
          throw PlatformException(code: 'injected_channel_failure');
        }
        return toMain(method, inner);
      }
      return incoming(messenger, channels.name, MethodCall('methodCall', args));
    });
    messenger.setMockMethodCallHandler(
      desktop,
      (call) async => switch (call.method) {
        'getWindowDefinition' => {
          'windowId': 'popup-test',
          'windowArgument': VideoPopupWindowService.windowArguments,
        },
        'getAllWindows' =>
          windowExists
              ? [
                  {
                    'windowId': 'popup-test',
                    'windowArgument': VideoPopupWindowService.windowArguments,
                  },
                ]
              : [],
        'createWindow' => 'popup-test',
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(manager, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getSize' => {'width': 384.0, 'height': height},
        'getBounds' => {'x': 0.0, 'y': 0.0, 'width': 384.0, 'height': height},
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      if (call.method == 'openOrFocus') return openResult;
      if (call.method.startsWith('remote')) {
        if (call.method == 'remoteAction') {
          lastAction = Map<String, dynamic>.from(call.arguments as Map);
        }
        if (failChannel) {
          throw PlatformException(code: 'injected_channel_failure');
        }
        return toMain(call.method, call.arguments);
      }
      if (call.method == 'setDisplayMode' ||
          call.method == 'getHardwareScreenshot') {
        return toMain(call.method, call.arguments);
      }
      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': 384.0, 'height': height};
      }
      return true;
    });
    await service.registerMainCubit(cubit);
  }

  Future<void> destroyed() async {
    windowExists = false;
    await incoming(
      messenger,
      desktop.name,
      const MethodCall('onWindowsChanged'),
    );
  }

  Future<void> dispose() async {
    await service.dispose();
    for (final channel in [native, desktop, channels, manager]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
