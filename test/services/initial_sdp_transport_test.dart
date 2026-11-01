import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/initial_sdp_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.example.nt_helper/initial_sdp');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  // REQ-004: existing desktop/MIDI tests do not exercise this channel and cannot
  // establish that it exposes only no-payload initial status operations.
  test(
    'REQ-004 channel sends only fixed operations without payloads',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return switch (call.method) {
          'availability' => {'driverObserved': false},
          'errorStatus' => {
            'stage': 'response',
            'hab': 0x56787856,
            'status': 0xf0f0f0f0,
          },
          _ => null,
        };
      });
      final transport = MethodChannelInitialSdpTransport();
      expect(await transport.availability(), {'driverObserved': false});
      await transport.observe();
      await transport.connect();
      final response = await transport.errorStatus();
      expect(response.hab, 0x56787856);
      expect(response.status, 0xf0f0f0f0);
      await transport.close();
      expect(calls.map((call) => call.method), [
        'availability',
        'observe',
        'connect',
        'errorStatus',
        'close',
      ]);
      expect(calls.every((call) => call.arguments == null), isTrue);
    },
  );

  // REQ-004: native boundary tests cannot protect the Dart consumer from
  // interpreting detection/connection or invalid channel data as a response.
  test('REQ-004 malformed and failed queries never become responses', () async {
    final transport = MethodChannelInitialSdpTransport();
    for (final reply in [
      null,
      {'stage': 'detected'},
      {'stage': 'connected', 'hab': 1, 'status': 2},
      {'stage': 'response', 'hab': 'invalid', 'status': 2},
      {'stage': 'response', 'hab': 1},
    ]) {
      messenger.setMockMethodCallHandler(methods, (_) async => reply);
      await expectLater(transport.errorStatus(), throwsFormatException);
    }
    messenger.setMockMethodCallHandler(methods, (_) async {
      throw PlatformException(code: 'query', message: 'USB disconnected');
    });
    await expectLater(
      transport.errorStatus(),
      throwsA(isA<PlatformException>()),
    );
  });
}
