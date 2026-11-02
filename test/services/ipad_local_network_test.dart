import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/ipad_local_network.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Desktop MCP coverage has no native netmask data or iPad opt-in setting.
  // These protect the requested subnet restriction, not generic private ranges.
  test(
    'iPad opt-in defaults off even with a restored desktop MCP preference',
    () async {
      SharedPreferences.setMockInitialValues({'mcp_enabled': true});
      final settings = SettingsService();
      await settings.init();
      expect(settings.ipadMcpEnabled, isFalse);
      await settings.setIpadMcpEnabled(true);
      await settings.init();
      expect(settings.ipadMcpEnabled, isTrue);
    },
  );

  test('same subnet uses the actual IPv4 mask rather than assuming /24', () {
    final subnet = LocalSubnet(
      InternetAddress('192.168.2.7'),
      InternetAddress('255.255.254.0'),
    );
    expect(subnet.contains(InternetAddress('192.168.3.99')), isTrue);
    expect(subnet.contains(InternetAddress('192.168.4.7')), isFalse);
    expect(subnet.contains(InternetAddress('10.0.0.8')), isFalse);
    expect(subnet.contains(InternetAddress('127.0.0.1')), isFalse);
    final narrow = LocalSubnet(
      InternetAddress('192.168.2.7'),
      InternetAddress('255.255.255.128'),
    );
    expect(narrow.contains(InternetAddress('192.168.2.127')), isTrue);
    expect(narrow.contains(InternetAddress('192.168.2.128')), isFalse);
  });

  test('dual-stack peers retain the IPv4 subnet restriction', () {
    final subnet = LocalSubnet(
      InternetAddress('192.168.2.7'),
      InternetAddress('255.255.255.0'),
    );
    expect(subnet.contains(InternetAddress('::ffff:192.168.2.8')), isTrue);
    expect(subnet.contains(InternetAddress('::ffff:192.168.3.8')), isFalse);
    expect(subnet.contains(InternetAddress('fd00::8')), isFalse);
  });

  test('IPv6 peers must share the interface IPv6 prefix', () {
    final subnet = LocalSubnet(
      InternetAddress('fd12:3456:789a:1::7'),
      InternetAddress('ffff:ffff:ffff:ffff::'),
    );
    expect(subnet.contains(InternetAddress('fd12:3456:789a:1::99')), isTrue);
    expect(subnet.contains(InternetAddress('fd12:3456:789a:2::99')), isFalse);
    expect(subnet.contains(InternetAddress('192.168.2.8')), isFalse);
  });

  test('invalid or unrestricted native masks fail closed', () {
    for (final mask in ['0.0.0.0', '255.0.255.0', 'ffff::']) {
      final subnet = LocalSubnet(
        InternetAddress('192.168.2.7'),
        InternetAddress(mask),
      );
      expect(subnet.contains(InternetAddress('192.168.2.8')), isFalse);
    }
    const missing = IpadLocalNetwork(isIpad: true, subnets: []);
    expect(missing.allows(null), isFalse);
  });

  test(
    'native channel decodes current interface address and netmask',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(IpadLocalNetwork.channel, (
        call,
      ) async {
        expect(call.method, 'addresses');
        return {
          'isIpad': true,
          'networks': [
            {
              'address': [192, 168, 2, 7],
              'netmask': [255, 255, 254, 0],
            },
          ],
        };
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(IpadLocalNetwork.channel, null),
      );
      final network = await IpadLocalNetwork.read();
      expect(network.isIpad, isTrue);
      expect(
        network.subnets.single.contains(InternetAddress('192.168.3.8')),
        isTrue,
      );
      expect(network.subnets.single.endpoint, 'http://192.168.2.7:3847/mcp');
    },
  );
}
