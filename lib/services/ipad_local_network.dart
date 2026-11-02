import 'dart:io';

import 'package:flutter/services.dart';

/// A live Wi-Fi/Ethernet address and its actual interface netmask, not a guessed
/// /24 or a list of private-address ranges.
class LocalSubnet {
  LocalSubnet(this.address, this.netmask);

  final InternetAddress address;
  final InternetAddress netmask;

  static List<int> _bytes(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 16 &&
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 255 &&
        bytes[11] == 255) {
      return bytes.sublist(12);
    }
    return bytes;
  }

  bool contains(InternetAddress peer) {
    final own = _bytes(address);
    final mask = _bytes(netmask);
    final remote = _bytes(peer);
    if (own.length != mask.length ||
        own.length != remote.length ||
        mask.every((byte) => byte == 0)) {
      return false;
    }
    // Reject malformed/noncontiguous masks rather than broadening access.
    var foundZero = false;
    for (final byte in mask) {
      for (var bit = 7; bit >= 0; bit--) {
        if ((byte & (1 << bit)) == 0) {
          foundZero = true;
        } else if (foundZero) {
          return false;
        }
      }
    }
    for (var i = 0; i < own.length; i++) {
      if ((remote[i] & mask[i]) != (own[i] & mask[i])) {
        return false;
      }
    }
    return true;
  }

  String get endpoint =>
      'http://${address.type == InternetAddressType.IPv6 ? '[${address.address}]' : address.address}:3847/mcp';
}

class IpadLocalNetwork {
  const IpadLocalNetwork({required this.isIpad, required this.subnets});

  final bool isIpad;
  final List<LocalSubnet> subnets;
  static const channel = MethodChannel('dev.nosuch.nt_helper/local_network');

  static Future<IpadLocalNetwork> read() async {
    final result = await channel.invokeMapMethod<String, dynamic>('addresses');
    final networks = result?['networks'] as List<dynamic>? ?? const [];
    return IpadLocalNetwork(
      isIpad: result?['isIpad'] == true,
      subnets: networks.map((entry) {
        final map = Map<String, dynamic>.from(entry as Map);
        return LocalSubnet(
          InternetAddress.fromRawAddress(
            Uint8List.fromList(List<int>.from(map['address'] as List)),
          ),
          InternetAddress.fromRawAddress(
            Uint8List.fromList(List<int>.from(map['netmask'] as List)),
          ),
        );
      }).toList(),
    );
  }

  bool allows(HttpConnectionInfo? connection) =>
      isIpad &&
      connection != null &&
      subnets.any((subnet) => subnet.contains(connection.remoteAddress));
}
