import 'dart:io';
import 'dart:typed_data';

Never _invalid(String reason) => throw FormatException(reason);

int _integer(Object? value, String field, {int min = 0, int max = 0xffffffff}) {
  if (value is! int || value < min || value > max) _invalid('Invalid $field');
  return value;
}

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) _invalid('Missing native context');
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List) _invalid('Missing native list');
  return value;
}

List<int> _bytes(Object? value, int length) {
  final values = _list(value);
  if (values.length != length) _invalid('Invalid address or mask length');
  return List.unmodifiable(values.map((v) => _integer(v, 'byte', max: 255)));
}

bool _same(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

int _prefix(List<int> mask) {
  var count = 0;
  var zero = false;
  for (final byte in mask) {
    for (var bit = 7; bit >= 0; bit--) {
      if ((byte & (1 << bit)) == 0) {
        zero = true;
      } else {
        if (zero) _invalid('Noncontiguous native mask');
        count++;
      }
    }
  }
  return count;
}

/// Numeric bytes only: construction never resolves a hostname or removes a zone.
class LanAddress {
  final List<int> bytes;
  final int scopeId;
  LanAddress._(List<int> bytes, this.scopeId)
    : bytes = List.unmodifiable(bytes);

  static bool _mapped(List<int> b) =>
      b.length == 16 &&
      b.take(10).every((v) => v == 0) &&
      b[10] == 255 &&
      b[11] == 255;

  factory LanAddress.native(String family, List<int> bytes, int scopeId) {
    if (scopeId < 0) _invalid('Invalid address scope');
    final length = switch (family) {
      'ipv4' => 4,
      'ipv6' => 16,
      _ => 0,
    };
    if (length == 0 ||
        bytes.length != length ||
        bytes.any((b) => b < 0 || b > 255)) {
      _invalid('Unsupported native address family');
    }
    return LanAddress._(_mapped(bytes) ? bytes.sublist(12) : bytes, scopeId);
  }

  factory LanAddress.parse(String value) {
    if (value.isEmpty || !RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(value)) {
      _invalid('Enter an exact numeric address without a zone');
    }
    if (!value.contains(':') || value.contains('.')) {
      final dotted = value.substring(value.lastIndexOf(':') + 1);
      final parts = dotted.split('.');
      if (parts.length != 4 ||
          parts.any(
            (p) =>
                !RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(p) ||
                int.parse(p) > 255,
          )) {
        _invalid('Use unambiguous dotted-decimal IPv4');
      }
    }
    final parsed = InternetAddress.tryParse(value);
    if (parsed == null) _invalid('Invalid numeric address');
    return LanAddress.native(
      parsed.type == InternetAddressType.IPv4 ? 'ipv4' : 'ipv6',
      parsed.rawAddress,
      0,
    );
  }

  String get key => bytes.join('.');
  String get text =>
      InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address;
  bool sameAddress(LanAddress other) =>
      scopeId == other.scopeId && _same(bytes, other.bytes);

  bool get isEligible =>
      scopeId == 0 &&
      (bytes.length == 4
          ? bytes[0] == 10 ||
                (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
                (bytes[0] == 192 && bytes[1] == 168)
          : bytes[0] == 0xfd && !_tailscaleBlock(bytes));

  static bool _tailscaleBlock(List<int> b) =>
      _same(b.take(6).toList(), [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0]);
}

class McpLanNativeAddress {
  final LanAddress address;
  final List<int> mask;
  final int prefix;

  McpLanNativeAddress._(this.address, this.mask, this.prefix);

  /// Reuse the admission pool/mask rules for the Settings address list.
  bool get isSelectable {
    final b = address.bytes;
    final poolPrefix = b.length == 16
        ? 8
        : b[0] == 10
        ? 8
        : b[0] == 172
        ? 12
        : 16;
    final network = List.generate(b.length, (i) => b[i] & mask[i]);
    return address.isEligible &&
        prefix >= poolPrefix &&
        prefix < b.length * 8 &&
        !(b.length == 16 && McpLanPolicy._overlapsTailscale(network, prefix));
  }

  factory McpLanNativeAddress.decode(Object? value) {
    final data = _map(value);
    final family = data['family'];
    final length = switch (family) {
      'ipv4' => 4,
      'ipv6' => 16,
      _ => 0,
    };
    if (length == 0) _invalid('Unsupported native family');
    final raw = _bytes(data['bytes'], length);
    var mask = _bytes(data['mask'], length);
    var prefix = _prefix(mask);
    if (_integer(data['prefix'], 'prefix', max: length * 8) != prefix) {
      _invalid('Contradictory native prefix');
    }
    final address = LanAddress.native(
      family as String,
      raw,
      _integer(data['scopeId'], 'scope'),
    );
    if (address.bytes.length != length) {
      if (prefix < 96) _invalid('Mapped mask crosses IPv4 boundary');
      mask = List.unmodifiable(mask.sublist(12));
      prefix -= 96;
    }
    return McpLanNativeAddress._(address, mask, prefix);
  }
}

class McpLanInterface {
  final int index;
  final String name;
  final String type;
  final int flags;
  final List<McpLanNativeAddress> addresses;

  McpLanInterface._(
    this.index,
    this.name,
    this.type,
    this.flags,
    this.addresses,
  );

  factory McpLanInterface.decode(Object? value) {
    final data = _map(value);
    final name = data['name'];
    final type = data['type'];
    if (name is! String || name.isEmpty || type is! String) {
      _invalid('Missing interface identity');
    }
    return McpLanInterface._(
      _integer(data['index'], 'interface index', min: 1),
      name,
      type,
      _integer(data['flags'], 'interface flags'),
      List.unmodifiable(
        _list(data['addresses']).map(McpLanNativeAddress.decode),
      ),
    );
  }

  // Darwin IFF_UP, IFF_RUNNING, IFF_LOOPBACK, IFF_POINTOPOINT.
  bool get isPhysicalLan =>
      (type == 'wifi' || type == 'wiredEthernet') &&
      flags & 0x41 == 0x41 &&
      flags & 0x18 == 0;
}

/// Versioned, immutable native provenance; no interface-order or name heuristics.
class McpLanSnapshot {
  final String idiom;
  final int pathGeneration;
  final List<McpLanInterface> interfaces;

  McpLanSnapshot._(this.idiom, this.pathGeneration, this.interfaces);

  factory McpLanSnapshot.decode(Object? value) {
    final data = _map(value);
    if (data['version'] is! int ||
        data['version'] != 1 ||
        data['pathCurrent'] != true) {
      _invalid('Unsupported or stale native context');
    }
    final idiom = data['idiom'];
    if (idiom is! String ||
        !['pad', 'phone', 'other', 'unknown'].contains(idiom)) {
      _invalid('Unknown native idiom');
    }
    final interfaces = _list(
      data['interfaces'],
    ).map(McpLanInterface.decode).toList();
    final indices = <int>{};
    final names = <String>{};
    final addresses = <String>{};
    for (final interface in interfaces) {
      if (!indices.add(interface.index) || !names.add(interface.name)) {
        _invalid('Ambiguous or duplicate native interface');
      }
      for (final entry in interface.addresses) {
        if (!addresses.add(entry.address.key)) {
          _invalid('Duplicate native address');
        }
      }
    }
    return McpLanSnapshot._(
      idiom,
      _integer(data['pathGeneration'], 'path generation', min: 1),
      List.unmodifiable(interfaces),
    );
  }

  bool get isPad => idiom == 'pad';
}

/// A single explicitly selected native address and a bounded exact-peer allowlist.
class McpLanPolicy {
  final int pathGeneration;
  final int interfaceIndex;
  final String interfaceName;
  final LanAddress address;
  final List<int> mask;
  final int prefix;
  final List<LanAddress> peers;

  McpLanPolicy._(
    McpLanSnapshot snapshot,
    McpLanInterface interface,
    McpLanNativeAddress selected,
    this.peers,
  ) : pathGeneration = snapshot.pathGeneration,
      interfaceIndex = interface.index,
      interfaceName = interface.name,
      address = selected.address,
      mask = selected.mask,
      prefix = selected.prefix;

  factory McpLanPolicy.select(
    McpLanSnapshot snapshot, {
    required int interfaceIndex,
    required String address,
    required Iterable<String> peers,
  }) {
    if (!snapshot.isPad) _invalid('This profile requires native iPad identity');
    final selectedAddress = LanAddress.parse(address);
    final interfaces = snapshot.interfaces.where(
      (i) => i.index == interfaceIndex,
    );
    if (interfaces.length != 1 || !interfaces.single.isPhysicalLan) {
      _invalid('Selected physical LAN interface is unavailable');
    }
    final interface = interfaces.single;
    final matches = interface.addresses.where(
      (a) => a.address.sameAddress(selectedAddress),
    );
    if (matches.length != 1) _invalid('Selected address is unavailable');
    final selected = matches.single;
    final b = selected.address.bytes;
    final network = List.generate(b.length, (i) => b[i] & selected.mask[i]);
    final end = List.generate(
      b.length,
      (i) => network[i] | (255 ^ selected.mask[i]),
    );
    // Each eligible pool is a single CIDR; IPv6 must also avoid any intersection
    // with the excluded /48, even when neither endpoint lies inside that /48.
    if (!selected.isSelectable) {
      _invalid('Connected block leaves the eligible address pool');
    }
    final unique = <String, LanAddress>{};
    for (final input in peers) {
      final peer = LanAddress.parse(input);
      final p = peer.bytes;
      if (!peer.isEligible ||
          p.length != b.length ||
          peer.sameAddress(selected.address) ||
          !Iterable<int>.generate(
            b.length,
          ).every((i) => (p[i] & selected.mask[i]) == network[i]) ||
          (b.length == 4 &&
              selected.prefix <= 30 &&
              (_same(p, network) || _same(p, end)))) {
        _invalid(
          'Peer must be a distinct eligible host in the connected block',
        );
      }
      unique[peer.key] = peer;
      if (unique.length > 8) {
        _invalid('At most eight exact peers are supported');
      }
    }
    if (unique.isEmpty) _invalid('At least one exact peer is required');
    return McpLanPolicy._(
      snapshot,
      interface,
      selected,
      List.unmodifiable(unique.values),
    );
  }

  static bool _overlapsTailscale(List<int> network, int prefix) {
    const excluded = [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0];
    for (var bit = 0; bit < prefix && bit < 48; bit++) {
      final flag = 1 << (7 - bit % 8);
      if ((network[bit ~/ 8] & flag) != (excluded[bit ~/ 8] & flag)) {
        return false;
      }
    }
    return true;
  }

  bool allowsPeer(LanAddress peer) => peers.any((p) => p.sameAddress(peer));
}
