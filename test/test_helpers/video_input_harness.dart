import 'package:image/image.dart' as img;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replaces only USB platform input. The real video manager/frame Cubit and
/// production Video entry/overlay stay in the test path.
final class VideoInputHarness {
  static const _methods = MethodChannel('com.example.nt_helper/usb_video');
  static const _events = MethodChannel(
    'com.example.nt_helper/usb_video_stream',
  );
  bool available = true;
  final frames = Uint8List.fromList(
    img.encodeBmp(img.Image(width: 256, height: 64)),
  );

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _methods,
      (call) async => switch (call.method) {
        'isSupported' || 'requestUsbPermission' => true,
        'listUsbCameras' =>
          !available
              ? []
              : [
                  {
                    'deviceId': 'test-video',
                    'productName': 'Test NT',
                    'vendorId': 0x16C0,
                    'productId': 1,
                    'isDistingNT': true,
                  },
                ],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(_events, (_) async => null);
  }

  Future<void> sendFrame() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _events.name,
          const StandardMethodCodec().encodeSuccessEnvelope(frames),
          (_) {},
        );
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_events, null);
  }
}
