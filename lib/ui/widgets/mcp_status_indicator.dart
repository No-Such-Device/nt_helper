import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Small round LED indicator for MCP server status with tooltip
class McpStatusIndicator extends StatelessWidget {
  static const int mcpPort = 3847;

  const McpStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService(); // Get SettingsService instance
    final mcpInstance =
        McpServerService.instance; // Get McpServerService instance
    final mcpService = context.watch<McpServerService>();
    final isRunning = mcpService.isRunning;
    final hasError = mcpService.hasError;
    final lastError = mcpService.lastError;

    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    // Determine color based on state: success=running, error=failed,
    // neutral=disabled.
    final Color baseColor;
    final Color highlightColor;
    final Color shadowColor;

    if (isRunning) {
      baseColor = appColors.success.color;
      highlightColor = appColors.success.container;
      shadowColor = Color.lerp(baseColor, scheme.shadow, 0.45)!;
    } else if (hasError) {
      baseColor = scheme.error;
      highlightColor = scheme.errorContainer;
      shadowColor = Color.lerp(baseColor, scheme.shadow, 0.45)!;
    } else {
      baseColor = scheme.outline;
      highlightColor = scheme.outlineVariant;
      shadowColor = Color.lerp(baseColor, scheme.shadow, 0.45)!;
    }

    // Build tooltip message based on state
    final String tooltip;
    if (Platform.isIOS) {
      tooltip = isRunning
          ? 'MCP running on the local subnet. Change in Settings.\n${mcpService.localEndpoints.join('\n')}'
          : hasError
          ? 'MCP failed: $lastError. Change in Settings.'
          : 'MCP is off. Enable in Settings.';
    } else if (isRunning) {
      tooltip =
          'MCP server running at http://localhost:$mcpPort (Tap to disable)';
    } else if (hasError) {
      tooltip = 'MCP server failed: $lastError (Tap to retry)';
    } else {
      tooltip = 'MCP server is disabled (Tap to enable)';
    }

    final semanticLabel = Platform.isIOS
        ? tooltip
        : isRunning
        ? 'MCP server running. Double tap to disable'
        : hasError
        ? 'MCP server error. Double tap to retry'
        : 'MCP server disabled. Double tap to enable';

    return Semantics(
      button: true,
      label: semanticLabel,
      child: IconButton(
        iconSize: 16,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        tooltip: tooltip,
        onPressed: Platform.isIOS
            ? null
            : () async {
                if (!(Platform.isMacOS ||
                    Platform.isWindows ||
                    Platform.isLinux)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "MCP Service can only be toggled on desktop platforms.",
                      ),
                    ),
                  );
                  return;
                }

                final bindAddress = settings.mcpRemoteConnections
                    ? InternetAddress.anyIPv4
                    : InternetAddress.loopbackIPv4;

                if (mcpInstance.hasError) {
                  await mcpInstance.start(bindAddress: bindAddress);
                  return;
                }

                final bool currentMcpSetting = settings.mcpEnabled;
                final newMcpSetting = !currentMcpSetting;
                await settings.setMcpEnabled(newMcpSetting);

                final bool isServerCurrentlyRunning = mcpInstance.isRunning;

                if (newMcpSetting) {
                  if (!isServerCurrentlyRunning) {
                    await mcpInstance.start(bindAddress: bindAddress);
                  }
                } else {
                  if (isServerCurrentlyRunning) {
                    await mcpInstance.stop();
                  }
                }
              },
        icon: ExcludeSemantics(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.4),
                radius: 0.9,
                colors: [highlightColor, baseColor, shadowColor],
                stops: const [0.0, 0.6, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withAlpha(77),
                  blurRadius: 2,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface.withAlpha(179),
                ),
                margin: const EdgeInsets.only(right: 3, bottom: 3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
