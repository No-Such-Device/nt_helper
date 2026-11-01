import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import '../../services/mcp_ipad_settings.dart';
import '../../services/mcp_lan_policy.dart';
import '../../services/mcp_server_service.dart';
import '../../services/settings_service.dart';

/// Explicit Settings commands, not a saved enable switch.
class McpIpadSettingsPanel extends StatefulWidget {
  const McpIpadSettingsPanel({super.key, required this.service});
  final McpServerService service;

  @override
  State<McpIpadSettingsPanel> createState() => _McpIpadSettingsPanelState();
}

class _McpIpadSettingsPanelState extends State<McpIpadSettingsPanel> {
  final _peers = TextEditingController();
  McpLanSnapshot? _snapshot;
  int? _index;
  String? _address;
  bool _loading = true;
  bool _busy = false;
  bool _accepted = false;
  bool _reveal = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = SettingsService().mcpIpadConfiguration;
    _index = saved?.interfaceIndex;
    _address = saved?.address;
    _peers.text = saved?.peers.join(', ') ?? '';
    widget.service.addListener(_changed);
    unawaited(_load());
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() => _reveal = false);
    _announce(
      'iPad LAN MCP: ${widget.service.ipadState.name}. ${widget.service.ipadReason ?? ''}',
    );
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      unawaited(widget.service.disableIpad());
      setState(() {
        _loading = true;
        _snapshot = null;
      });
    }
    try {
      final snapshot = await widget.service.ipadSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot.isPad ? snapshot : null;
        _loading = false;
        _error = snapshot.isPad ? null : 'Native iPad identity is required.';
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'LAN context unavailable. Check Wi-Fi/Ethernet and refresh explicitly.';
        });
        _announce(_error!);
      }
    }
  }

  McpLanPolicy _policy() => McpLanPolicy.select(
    _snapshot!,
    interfaceIndex: _index ?? 0,
    address: _address ?? '',
    peers: _peers.text.split(RegExp(r'[,\s]+')).where((p) => p.isNotEmpty),
  );

  void _edited() {
    // Revocation begins synchronously, even if the edit is later canceled.
    unawaited(widget.service.disableIpad());
    setState(() {
      _reveal = false;
      _accepted = false;
      _error = null;
    });
  }

  Future<void> _enable() async {
    if (_snapshot == null || !_accepted) return;
    McpLanPolicy policy;
    try {
      policy = _policy();
    } on FormatException {
      setState(
        () => _error =
            'Select a current address and 1–8 exact numeric peers in its CIDR; no self, network or broadcast addresses.',
      );
      _announce(_error!);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _reveal = false;
    });
    await widget.service.enableIpad(
      policy: policy,
      persistSettings: () => SettingsService().setMcpIpadConfiguration(
        McpIpadSettings.fromPolicy(policy),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy(bool token) async {
    final value = token
        ? widget.service.ipadToken
        : widget.service.ipadEndpoint;
    if (!widget.service.isRunning || value == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Clipboard unavailable. Reveal and configure the client manually.',
        );
        _announce(_error!);
      }
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    _peers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.ipadSupported) return const SizedBox.shrink();
    final candidates = <DropdownMenuItem<String>>[];
    for (final interface in _snapshot?.interfaces ?? <McpLanInterface>[]) {
      if (!interface.isPhysicalLan) continue;
      for (final entry in interface.addresses.where((e) => e.isSelectable)) {
        candidates.add(
          DropdownMenuItem(
            value: '${interface.index}|${entry.address.text}',
            child: Text(
              '${entry.address.text}/${entry.prefix} (${interface.name})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
    final selection = _address == null ? null : '$_index|$_address';
    if (selection != null && !candidates.any((c) => c.value == selection)) {
      candidates.add(
        DropdownMenuItem(
          value: selection,
          enabled: false,
          child: const Text('Saved address unavailable — select explicitly'),
        ),
      );
    }
    final service = widget.service;
    final running = service.isRunning;
    final status = 'iPad LAN MCP: ${service.ipadState.name.toUpperCase()}';
    final reason =
        service.ipadReason ??
        'Foreground only. Saved settings and app restart stay OFF.';
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('iPad LAN MCP')),
          const Text(
            'Plain HTTP is not encrypted. On-path observers can capture, replay and modify bearer credentials, commands and results, including preset/MIDI data. Private-address filtering is not encryption. A client may send data to its AI provider. Revocation cannot undo past effects.\n\n'
            'App consent is not an OS Local Network grant or client authentication. Inbound TCP does not itself require that permission; no prompt is promised. A running listener proves neither an OS grant nor remote reachability.\n\n'
            'Keep the app foreground. Background/lock, observed network changes and restart require Settings re-enable and a fresh token; re-pair your client after each. DHCP changes require checking address and exact peers.\n\n'
            'Only physical Wi-Fi/Ethernet RFC1918 or supported unscoped ULA, and 1–8 exact same-subnet peers. No global/link-local-only IPv6, browser/cloud connector, DNS/proxy/redirect or direct Tailscale support. Interface metadata cannot prove physical ingress or VPN identity; routers can forward remote traffic and unobserved changes remain a risk.',
          ),
          SizedBox(
            height: 120,
            child: Semantics(
              key: const ValueKey('ipad-mcp-state'),
              container: true,
              liveRegion: true,
              child: Text(
                '$status\n$reason',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(selection),
            initialValue: selection,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'LAN address and connected CIDR',
            ),
            items: candidates,
            onChanged: _loading
                ? null
                : (value) {
                    _edited();
                    final parts = value!.split('|');
                    setState(() {
                      _index = int.parse(parts.first);
                      _address = parts.last;
                    });
                  },
          ),
          OutlinedButton(
            onPressed: _loading ? null : () => _load(refresh: true),
            child: const Text('Refresh LAN addresses / retry context'),
          ),
          TextField(
            controller: _peers,
            decoration: const InputDecoration(
              labelText: 'Exact client addresses',
              hintText: 'Comma or space separated, 1–8 peers',
            ),
            onChanged: (_) => _edited(),
          ),
          SizedBox(
            height: 100,
            child: Semantics(
              key: const ValueKey('ipad-mcp-validation'),
              container: true,
              liveRegion: true,
              child: Text(
                _error ??
                    (_loading
                        ? 'Loading LAN context…'
                        : candidates.isEmpty
                        ? 'No eligible physical LAN address. Check network and refresh.'
                        : 'Select one address; confirm exact peers in its connected CIDR.'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _accepted,
            onChanged: (value) => setState(() => _accepted = value!),
            title: const Text(
              'I understand plaintext and re-pairing risks; enable this foreground interval.',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _loading || _busy || !_accepted ? null : _enable,
                child: const Text('Enable / retry in Settings'),
              ),
              OutlinedButton(
                onPressed: () => service.disableIpad(),
                child: const Text('Disable'),
              ),
              OutlinedButton(
                onPressed: running && !_busy && _accepted ? _enable : null,
                child: const Text('Regenerate token'),
              ),
            ],
          ),
          SizedBox(
            height: 56,
            child: Text(
              running
                  ? service.ipadEndpoint!
                  : 'Endpoint unavailable while not running',
              maxLines: 2,
            ),
          ),
          SizedBox(
            height: 64,
            child: Text(
              running && _reveal
                  ? service.ipadToken!
                  : 'Token hidden (memory only)',
              maxLines: 2,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: running
                    ? () => setState(() => _reveal = !_reveal)
                    : null,
                child: Text(_reveal ? 'Hide token' : 'Reveal token'),
              ),
              TextButton(
                onPressed: running ? () => _copy(false) : null,
                child: const Text('Copy endpoint'),
              ),
              TextButton(
                onPressed: running ? () => _copy(true) : null,
                child: const Text('Copy token'),
              ),
            ],
          ),
          const Text(
            'Credentials are never saved or auto-copied. Revocation clears app references, not guaranteed heap or clipboard erasure. Configure a native mcp_dart 2.4.0 client (protocol 2025-06-18, useServerDiscover:false) with Authorization: Bearer in requestInit on POST, GET and DELETE, never in the URL.',
          ),
        ],
      ),
    );
  }
}
