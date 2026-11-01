import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/mcp_lan_context.dart';
import 'package:nt_helper/services/mcp_lan_policy.dart';

List<int> bytes(String address) => InternetAddress(address).rawAddress.toList();
List<int> mask(int bits, int length) => List.generate(
  length,
  (i) => bits >= (i + 1) * 8
      ? 255
      : bits <= i * 8
      ? 0
      : (255 << (8 - (bits - i * 8))) & 255,
);
Map<String, Object?> nativeAddress(String ip, int prefix, {int scope = 0}) => {
  'family': ip.contains(':') ? 'ipv6' : 'ipv4',
  'bytes': bytes(ip),
  'mask': mask(prefix, ip.contains(':') ? 16 : 4),
  'prefix': prefix,
  'scopeId': scope,
};
Map<String, Object?> interface({String ip = '192.168.2.1', int prefix = 23}) =>
    {
      'index': 7,
      'name': 'not-a-wifi-name',
      'type': 'wifi',
      'flags': 0x41,
      'addresses': <Object?>[nativeAddress(ip, prefix)],
    };
Map<String, Object?> snapshot({String ip = '192.168.2.1', int prefix = 23}) => {
  'version': 1,
  'idiom': 'pad',
  'pathGeneration': 3,
  'pathCurrent': true,
  'interfaces': <Object?>[interface(ip: ip, prefix: prefix)],
};
McpLanPolicy select(Map<String, Object?> data, String ip, List<String> peers) =>
    McpLanPolicy.select(
      McpLanSnapshot.decode(data),
      interfaceIndex: 7,
      address: ip,
      peers: peers,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AC-001/006: snapshot-only fixtures do not prove identity discovery without
  // LAN availability or the unsolicited native invalidation channel.
  test(
    'AC-001 AC-006 native identity is exact pad and observed changes are delivered',
    () async {
      const channel = MethodChannel('com.example.nt_helper/ipad_lan_context');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final provider = MethodChannelMcpLanContext(channel: channel);
      final changes = <bool>[];
      provider.watch(changes.add);
      for (final identity in [
        'pad',
        'phone',
        'other',
        'unknown',
        null,
        true,
        1,
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'idiom');
          return identity;
        });
        expect(await provider.isPad(), identity == 'pad');
      }
      Future<void> event(String method) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) => done.complete(),
        );
        await done.future;
      }

      await event('networkChanged');
      await event('monitorFailed');
      expect(changes, [false, true]);
      provider.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  // REQ-003 / AC-002: existing HTTP tests have no native CIDR or exact-peer policy.
  test('AC-002 accept table uses native CIDR, including /23, /31 and ULA', () {
    for (final row in [
      ('10.0.0.1', 8, '10.255.255.254'),
      ('172.16.0.1', 12, '172.31.255.254'),
      ('192.168.2.1', 23, '192.168.3.2'),
      ('192.168.2.0', 31, '192.168.2.1'),
      ('fd12:3456::1', 64, 'fd12:3456::2'),
      ('fd7a:115c:a1e1::1', 48, 'fd7a:115c:a1e1::2'),
      ('fd80::1', 9, 'fdff::2'),
      ('fd12::', 127, 'fd12::1'),
    ]) {
      final policy = select(snapshot(ip: row.$1, prefix: row.$2), row.$1, [
        row.$3,
      ]);
      expect(policy.prefix, row.$2, reason: '$row');
      expect(
        policy.allowsPeer(LanAddress.parse(row.$3)),
        isTrue,
        reason: '$row',
      );
      expect(policy.allowsPeer(LanAddress.parse(row.$1)), isFalse);
    }
  });

  // AC-002: successful /23 alone cannot detect inferred /24 or host boundary errors.
  test(
    'AC-002 reject table covers subnet, self, network, broadcast and host-only masks',
    () {
      for (final row in [
        ('192.168.2.1', 24, '192.168.3.2'),
        ('192.168.2.1', 23, '192.168.2.0'),
        ('192.168.2.1', 23, '192.168.3.255'),
        ('192.168.2.1', 23, '192.168.2.1'),
        ('192.168.2.0', 31, '192.168.2.2'),
        ('192.168.2.1', 32, '192.168.2.2'),
        ('fd12::1', 128, 'fd12::2'),
        ('192.168.2.1', 24, 'fd12::2'),
      ]) {
        expect(
          () => select(snapshot(ip: row.$1, prefix: row.$2), row.$1, [row.$3]),
          throwsFormatException,
          reason: '$row',
        );
      }
    },
  );

  // AC-002: private-looking addresses are not proof of an eligible whole block.
  test(
    'AC-002 rejects every excluded pool and blocks overlapping eligible pools',
    () {
      for (final ip in [
        '0.0.0.0',
        '127.0.0.1',
        '224.0.0.1',
        '255.255.255.255',
        '8.8.8.8',
        '100.64.0.1',
        '169.254.1.1',
        '192.0.2.1',
        '240.0.0.1',
        '::',
        '::1',
        'ff02::1',
        '2001:db8::1',
        'fe80::1',
        'fc00::1',
        'fd7a:115c:a1e0::1',
        '::ffff:127.0.0.1',
        '::ffff:8.8.8.8',
      ]) {
        expect(LanAddress.parse(ip).isEligible, isFalse, reason: ip);
        final peerBytes = bytes(ip)..last = 2;
        final peer = InternetAddress.fromRawAddress(
          Uint8List.fromList(peerBytes),
        ).address;
        expect(
          () => select(
            snapshot(
              ip: ip,
              prefix: ip.contains(':')
                  ? (ip.startsWith('::ffff:') ? 120 : 64)
                  : 24,
            ),
            ip,
            [peer],
          ),
          throwsFormatException,
          reason: ip,
        );
        expect(
          () => select(snapshot(), '192.168.2.1', [ip]),
          throwsFormatException,
          reason: ip,
        );
      }
      for (final row in [
        ('10.1.1.1', 7),
        ('172.16.1.1', 11),
        ('192.168.2.1', 15),
        ('fd12::1', 7),
        ('fd12::1', 8),
        ('fd7a:115c:a1e1::1', 47),
      ]) {
        expect(
          () => select(snapshot(ip: row.$1, prefix: row.$2), row.$1, [
            row.$1.replaceFirst(RegExp(r'1$'), '2'),
          ]),
          throwsFormatException,
          reason: '$row',
        );
      }
    },
  );

  // AC-002: permissive numeric parsers accept ambiguous IPv4; HTTP tests do not exercise input.
  test(
    'AC-002 strict parsing rejects names, prefixes, ranges, zones and ambiguous numbers',
    () {
      for (final input in [
        'localhost',
        '192.168.2.2/24',
        '192.168.2.2-3',
        '192.168.2',
        '3232236034',
        '0300.168.2.2',
        '0xc0.168.2.2',
        '192.168.002.2',
        '+192.168.2.2',
        '192.168.2.256',
        ' 192.168.2.2',
        '192.168.2.2\n',
        '[fd12::2]',
        'fd12::2%0',
        'fd12::2%en0',
        '::ffff:192.168.002.2',
        '192.168.2.2:3847',
        'fd12:::2',
      ]) {
        expect(
          () => LanAddress.parse(input),
          throwsFormatException,
          reason: input,
        );
      }
    },
  );

  // AC-002: canonical peer equality and explicit scope must survive mapped normalization.
  test(
    'AC-002 normalizes mapped peers, deduplicates exact peers and enforces 1 to 8',
    () {
      final policy = select(snapshot(), '192.168.2.1', [
        '192.168.2.2',
        '::ffff:192.168.2.2',
      ]);
      expect(policy.peers, hasLength(1));
      expect(policy.allowsPeer(LanAddress.parse('::ffff:c0a8:202')), isTrue);
      expect(policy.allowsPeer(LanAddress.parse('192.168.2.3')), isFalse);
      expect(
        policy.allowsPeer(
          LanAddress.native('ipv6', bytes('::ffff:192.168.2.2'), 7),
        ),
        isFalse,
      );
      expect(
        select(snapshot(), '192.168.2.1', List.filled(10, '192.168.2.2')).peers,
        hasLength(1),
      );
      expect(
        select(
          snapshot(),
          '192.168.2.1',
          List.generate(8, (i) => '192.168.2.${i + 2}'),
        ).peers,
        hasLength(8),
      );
      for (final peers in [
        <String>[],
        List.generate(9, (i) => '192.168.2.${i + 2}'),
      ]) {
        expect(
          () => select(snapshot(), '192.168.2.1', peers),
          throwsFormatException,
        );
      }
      final mapped = snapshot(ip: '::ffff:192.168.2.1', prefix: 119);
      expect(select(mapped, '192.168.2.1', ['192.168.3.2']).prefix, 23);
      expect(
        () => select(
          snapshot(ip: '::ffff:192.168.2.1', prefix: 95),
          '192.168.2.1',
          ['192.168.2.2'],
        ),
        throwsFormatException,
      );
      for (final ip in ['fd12::1', '::ffff:192.168.2.1']) {
        final data = snapshot(ip: ip, prefix: ip.startsWith('fd') ? 64 : 120);
        final iface = (data['interfaces'] as List).single as Map;
        (iface['addresses'] as List).single['scopeId'] = 7;
        expect(
          () => select(data, ip, [
            ip.startsWith('fd') ? 'fd12::2' : '192.168.2.2',
          ]),
          throwsFormatException,
        );
        final observed = LanAddress.native('ipv6', bytes(ip), 7);
        expect(observed.scopeId, 7);
        expect(observed.isEligible, isFalse);
        expect(observed.sameAddress(LanAddress.parse(ip)), isFalse);
      }
    },
  );

  // AC-002: native corruption cannot be covered by valid address tables.
  test(
    'AC-002 rejects malformed native masks, versions, flags, types and duplicate identity',
    () {
      final mutations = <void Function(Map<String, Object?>, Map, Map)>[
        (s, i, a) => s['version'] = 2,
        (s, i, a) => s['version'] = true,
        (s, i, a) => s['pathCurrent'] = false,
        (s, i, a) => s['pathGeneration'] = 0,
        (s, i, a) => i['index'] = 0,
        (s, i, a) => i['name'] = '',
        (s, i, a) => i['flags'] = 1,
        (s, i, a) => i['flags'] = 0x40,
        (s, i, a) => i['flags'] = 0x49,
        (s, i, a) => i['flags'] = 0x51,
        (s, i, a) => i['type'] = 'cellular',
        (s, i, a) => i['type'] = 'other',
        (s, i, a) => a['family'] = 'unknown',
        (s, i, a) => a['bytes'] = [192, 168, 2, 256],
        (s, i, a) => a['scopeId'] = null,
        (s, i, a) => a['mask'] = [255, 0, 255, 0],
        (s, i, a) => a['mask'] = [255, 255, 255],
        (s, i, a) => a['prefix'] = 24,
        (s, i, a) => (s['interfaces'] as List).add({
          ...interface(ip: '::ffff:192.168.2.1', prefix: 119),
          'index': 8,
          'name': 'mapped-alias',
        }),
        (s, i, a) => (s['interfaces'] as List).add(Map.of(i)),
        (s, i, a) => (s['interfaces'] as List).add({...i, 'index': 8}),
        (s, i, a) =>
            (s['interfaces'] as List).add({...i, 'index': 8, 'name': 'other'}),
      ];
      for (var n = 0; n < mutations.length; n++) {
        final data = snapshot();
        final iface = (data['interfaces'] as List).single as Map;
        final address = (iface['addresses'] as List).single as Map;
        mutations[n](data, iface, address);
        expect(
          () => select(data, '192.168.2.1', ['192.168.2.2']),
          throwsFormatException,
          reason: 'mutation $n',
        );
      }
      expect(
        () => select(snapshot(), '192.168.2.99', ['192.168.2.2']),
        throwsFormatException,
      );
      expect(
        () => McpLanPolicy.select(
          McpLanSnapshot.decode(snapshot()),
          interfaceIndex: 8,
          address: '192.168.2.1',
          peers: ['192.168.2.2'],
        ),
        throwsFormatException,
      );
    },
  );

  // Native idiom supports AC-001; only identity eligibility is in this slice, not Settings/binds.
  test(
    'REQ-003 native pad identity is required, independent of interface spelling/order',
    () {
      for (final idiom in ['phone', 'other', 'unknown', null]) {
        expect(
          () => select(snapshot()..['idiom'] = idiom, '192.168.2.1', [
            '192.168.2.2',
          ]),
          throwsFormatException,
        );
      }
      final wired = snapshot();
      ((wired['interfaces'] as List).single as Map)['type'] = 'wiredEthernet';
      expect(select(wired, '192.168.2.1', ['192.168.2.2']).interfaceIndex, 7);
      final data = snapshot();
      (data['interfaces'] as List).insert(0, {
        ...interface(ip: '10.0.0.1', prefix: 24),
        'index': 9,
        'name': 'en0',
        'type': 'wiredEthernet',
      });
      expect(select(data, '192.168.2.1', ['192.168.2.2']).interfaceIndex, 7);
    },
  );

  // AC-002: fixtures decoded directly cannot prove the injectable channel or regression guard.
  test(
    'AC-002 channel decodes native context and rejects path generation regression and bridge failure',
    () async {
      const channel = MethodChannel('com.example.nt_helper/ipad_lan_context');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? reply = snapshot();
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'snapshot');
        return reply;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final provider = MethodChannelMcpLanContext(channel: channel);
      expect((await provider.snapshot()).pathGeneration, 3);
      reply = snapshot()..['pathGeneration'] = 2;
      await expectLater(provider.snapshot(), throwsFormatException);
      reply = null;
      await expectLater(provider.snapshot(), throwsFormatException);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await expectLater(provider.snapshot(), throwsA(isA<PlatformException>()));
    },
  );
}
