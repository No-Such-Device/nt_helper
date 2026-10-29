import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/video_frame_cubit.dart';
import 'package:nt_helper/cubit/video_frame_state.dart';
import 'package:nt_helper/domain/video/video_stream_state.dart';
import 'package:nt_helper/domain/video/usb_device_info.dart';
import 'package:nt_helper/domain/video/usb_video_manager.dart';
import 'package:nt_helper/services/platform_channels/usb_video_channel.dart';

class _Channel extends Mock implements UsbVideoChannel {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 266, height: 74)),
  );
  final bmp = Uint8List.fromList(
    img.encodeBmp(img.Image(width: 256, height: 64)),
  );
  const device = UsbDeviceInfo(
    deviceId: 'nt',
    productName: 'NT',
    vendorId: 0x16C0,
    productId: 1,
    isDistingNT: true,
  );
  late _Channel channel;
  late UsbVideoManager manager;
  late VideoFrameCubit frames;
  late StreamSubscription<dynamic> stateSubscription;
  late StreamController<Uint8List> usb;
  late Future<Uint8List?> Function() capture;
  var requests = 0;

  Future<void> initialize() async {
    channel = _Channel();
    usb = StreamController<Uint8List>.broadcast();
    when(() => channel.isSupported()).thenAnswer((_) async => true);
    when(() => channel.listUsbCameras()).thenAnswer((_) async => []);
    when(
      () => channel.requestUsbPermission('nt'),
    ).thenAnswer((_) async => true);
    when(() => channel.startVideoStream('nt')).thenAnswer((_) => usb.stream);
    when(() => channel.stopVideoStream()).thenAnswer((_) async {});
    when(() => channel.dispose()).thenAnswer((_) async {});
    requests = 0;
    capture = () async => png;
    manager = UsbVideoManager(
      channel: channel,
      takeScreenshot: () {
        requests++;
        return capture();
      },
    );
    frames = VideoFrameCubit();
    await manager.initialize();
    stateSubscription = manager.stateStream.listen((state) {
      final stream = state.maybeWhen(
        streaming: (stream, _, _, _) => stream,
        orElse: () => null,
      );
      if (stream != null) {
        frames.connectToStream(stream);
      } else {
        frames.disconnect();
      }
    });
  }

  tearDown(() async {
    await stateSubscription.cancel();
    await frames.close();
    await manager.dispose();
    await usb.close();
  });

  for (final supported in [true, false]) {
    testWidgets(
      'no camera falls back to PNG (platform supported: $supported)',
      (tester) async {
        await initialize();
        when(() => channel.isSupported()).thenAnswer((_) async => supported);
        await manager.autoConnect();
        await tester.pump();
        expect(requests, 1);
        expect(
          frames.state.maybeWhen((data, _, _, _) => data, orElse: () => null),
          png,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(requests, 2);
        verifyNever(() => channel.startVideoStream(any()));
        await manager.disconnect();
        await tester.pump(const Duration(seconds: 5));
        expect(requests, 2);
      },
    );
  }

  testWidgets(
    'healthy USB stays preferred; a stalled feed triggers screenshot fallback',
    (tester) async {
      await initialize();
      when(() => channel.listUsbCameras()).thenAnswer((_) async => [device]);
      final started = manager.autoConnect();
      await tester.pump(const Duration(milliseconds: 100));
      await started;
      usb.add(bmp);
      await tester.pump();
      expect(
        frames.state.maybeWhen((data, _, _, _) => data, orElse: () => null),
        bmp,
      );
      expect(requests, 0);
      // The production watchdog uses wall time as well as its periodic timer.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 4)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(requests, 1);
      expect(
        frames.state.maybeWhen((data, _, _, _) => data, orElse: () => null),
        png,
      );
      verify(() => channel.stopVideoStream()).called(1);
      await manager.disconnect();
    },
  );

  testWidgets(
    'missing first USB frame also falls back after the watchdog deadline',
    (tester) async {
      await initialize();
      when(() => channel.listUsbCameras()).thenAnswer((_) async => [device]);
      final started = manager.autoConnect();
      await tester.pump(const Duration(milliseconds: 100));
      await started;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 4)),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(requests, 1);
      expect(
        frames.state.maybeWhen((data, _, _, _) => data, orElse: () => null),
        png,
      );
      await manager.disconnect();
    },
  );

  testWidgets(
    'slow captures never overlap and late disconnect responses are ignored',
    (tester) async {
      await initialize();
      final pending = Completer<Uint8List?>();
      capture = () => pending.future;
      await manager.autoConnect();
      await tester.pump(const Duration(seconds: 10));
      expect(requests, 1);
      await manager.disconnect();
      pending.complete(png);
      await tester.pump(const Duration(seconds: 10));
      expect(requests, 1);
      expect(
        manager.currentState.maybeWhen(
          disconnected: () => true,
          orElse: () => false,
        ),
        isTrue,
      );
      expect(
        frames.state.maybeWhen(null, initial: () => true, orElse: () => false),
        isTrue,
      );
    },
  );

  for (final failure in ['null', 'empty', 'exception']) {
    testWidgets(
      'failed screenshot ($failure) exposes a retryable error without polling',
      (tester) async {
        await initialize();
        capture = () async => switch (failure) {
          'null' => null,
          'empty' => Uint8List(0),
          _ => throw StateError('Injected capture failure'),
        };
        await manager.autoConnect();
        await tester.pump();
        expect(
          manager.currentState.maybeWhen(
            error: (message) => message,
            orElse: () => null,
          ),
          contains('screenshot capture failed'),
        );
        await tester.pump(const Duration(seconds: 10));
        expect(requests, 1);
        capture = () async => png;
        await manager.autoConnect();
        await tester.pump();
        expect(requests, 2);
        expect(
          frames.state.maybeWhen((data, _, _, _) => data, orElse: () => null),
          png,
        );
        await manager.disconnect();
      },
    );
  }
}
