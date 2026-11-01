import 'mcp_lan_policy.dart';

/// A saved selection and warning receipt, never permission to start a listener.
class McpIpadSettings {
  const McpIpadSettings({
    required this.interfaceIndex,
    required this.address,
    required this.peers,
  });

  final int interfaceIndex;
  final String address;
  final List<String> peers;

  factory McpIpadSettings.fromPolicy(McpLanPolicy policy) => McpIpadSettings(
    interfaceIndex: policy.interfaceIndex,
    address: policy.address.text,
    peers: policy.peers.map((p) => p.text).toList(),
  );

  static McpIpadSettings? decode(Object? value) {
    if (value is! Map ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['consentVersion'] is! int ||
        value['consentVersion'] != 1 ||
        value['interfaceIndex'] is! int ||
        (value['interfaceIndex'] as int) < 1 ||
        value['address'] is! String ||
        value['peers'] is! List) {
      return null;
    }
    final peers = value['peers'] as List;
    if (peers.isEmpty || peers.length > 8 || peers.any((p) => p is! String)) {
      return null;
    }
    try {
      final address = LanAddress.parse(value['address'] as String);
      final parsed = peers.cast<String>().map(LanAddress.parse).toList();
      if (!address.isEligible || parsed.any((p) => !p.isEligible)) return null;
      return McpIpadSettings(
        interfaceIndex: value['interfaceIndex'] as int,
        address: address.text,
        peers: List.unmodifiable(parsed.map((p) => p.text)),
      );
    } on FormatException {
      return null;
    }
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'consentVersion': 1,
    'interfaceIndex': interfaceIndex,
    'address': address,
    'peers': peers,
  };
}
