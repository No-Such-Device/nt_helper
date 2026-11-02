import 'package:flutter/material.dart';
import 'package:nt_helper/services/ipad_local_network.dart';

/// One opt-in switch. Endpoint/status space stays fixed while native network
/// information loads, so settings controls do not jump.
class IpadMcpSettings extends StatefulWidget {
  const IpadMcpSettings({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<IpadMcpSettings> createState() => _IpadMcpSettingsState();
}

class _IpadMcpSettingsState extends State<IpadMcpSettings> {
  IpadLocalNetwork? _network;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final network = await IpadLocalNetwork.read();
      if (mounted) setState(() => _network = network);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Local network information unavailable.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = _network;
    final status =
        _error ??
        (network == null
            ? 'Checking local network…'
            : !network.isIpad
            ? 'MCP on iOS is available on iPad.'
            : network.subnets.isEmpty
            ? 'Connect to Wi-Fi or Ethernet, then reopen Settings.'
            : network.subnets.map((s) => s.endpoint).join('\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: const Text('Enable MCP on iPad'),
          subtitle: const Text(
            'Allow any device on this iPad’s local subnet. '
            'HTTP is unencrypted; use a trusted network and keep the app open.',
          ),
          value: widget.value,
          onChanged: network?.isIpad == true || widget.value
              ? widget.onChanged
              : null,
          contentPadding: EdgeInsets.zero,
        ),
        SizedBox(
          height: 72,
          child: Semantics(
            liveRegion: true,
            child: Tooltip(
              message: status,
              child: SelectableText(status, maxLines: 3),
            ),
          ),
        ),
      ],
    );
  }
}
