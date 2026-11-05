import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget that displays firmware update errors with contextual actions
class FirmwareErrorWidget extends StatelessWidget {
  final FirmwareUpdateStateError state;
  final VoidCallback onReturnToBootloader;
  final VoidCallback onRetryFlash;
  final VoidCallback onTryAgain;
  final VoidCallback? onInstallUdevRules;

  const FirmwareErrorWidget({
    super.key,
    required this.state,
    required this.onReturnToBootloader,
    required this.onRetryFlash,
    required this.onTryAgain,
    this.onInstallUdevRules,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 24),
          Text(
            'Update Failed',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Error message
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                state.message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Primary action button based on error type
          _buildPrimaryActionButton(context),
          const SizedBox(height: 16),

          // Show udev installation instructions for Linux
          if (state.errorType == FirmwareErrorType.udevMissing) ...[
            const _UdevInstructionsSection(),
            const SizedBox(height: 16),
          ],

          // Show sandbox restriction message for macOS
          if (state.errorType == FirmwareErrorType.sandboxRestriction) ...[
            const _SandboxInstructionsSection(),
            const SizedBox(height: 16),
          ],

          // Stuck in bootloader help section
          _BootloaderHelpSection(),
          const SizedBox(height: 16),

          // Forum link
          Center(
            child: TextButton.icon(
              onPressed: _openForum,
              icon: const Icon(Icons.forum, size: 16),
              label: const Text('Expert Sleepers Forum'),
            ),
          ),
          const SizedBox(height: 16),

          // Close button
          Center(
            child: OutlinedButton(
              onPressed: onTryAgain,
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton(BuildContext context) {
    final (label, icon, action) = _getPrimaryAction();

    return FilledButton.icon(
      onPressed: action,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  (String, IconData, VoidCallback) _getPrimaryAction() {
    switch (state.errorType) {
      case FirmwareErrorType.bootloaderConnection:
        return (
          'Re-enter Bootloader Mode',
          Icons.restart_alt,
          onReturnToBootloader,
        );
      case FirmwareErrorType.flashWrite:
        return ('Retry Update', Icons.refresh, onRetryFlash);
      case FirmwareErrorType.udevMissing:
        // Use install callback if available, otherwise fall back to retry
        if (onInstallUdevRules != null) {
          return ('Install USB Rules', Icons.security, onInstallUdevRules!);
        }
        return ('Retry After Installing Rules', Icons.refresh, onRetryFlash);
      case FirmwareErrorType.sandboxRestriction:
        return ('Download Direct Version', Icons.download, _openGitHubReleases);
      case FirmwareErrorType.download:
      case FirmwareErrorType.general:
        return ('Try Again', Icons.refresh, onTryAgain);
    }
  }

  void _openGitHubReleases() async {
    final uri = Uri.parse(
      'https://github.com/thorinside/nt_helper/releases/latest',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openForum() async {
    final uri = Uri.parse('https://forum.expert-sleepers.co.uk/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Get the appropriate action button text based on the failed stage
String getActionButtonText(FlashStage? stage) {
  if (stage == null) return 'Try Again';

  switch (stage) {
    case FlashStage.sdpConnect:
    case FlashStage.blCheck:
      return 'Re-enter Bootloader Mode';
    case FlashStage.sdpUpload:
    case FlashStage.write:
      return 'Retry Update';
    case FlashStage.configure:
    case FlashStage.reset:
    case FlashStage.programmingComplete:
    case FlashStage.complete:
      return 'Try Again';
  }
}

/// Expandable help section for users stuck in bootloader mode
class _BootloaderHelpSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      leading: Icon(Icons.help_outline, color: theme.colorScheme.primary),
      title: const Text('Stuck in bootloader?'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'If your Disting NT is stuck showing "BOOT":',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildHelpStep(context, 1, 'Power off the module'),
              _buildHelpStep(context, 2, 'Wait 5 seconds'),
              _buildHelpStep(context, 3, 'Power on the module'),
              _buildHelpStep(context, 4, 'The module should boot normally'),
              const SizedBox(height: 12),
              Text(
                'If this doesn\'t work, the module may need to be re-flashed. '
                'Visit the Expert Sleepers forum for help.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHelpStep(BuildContext context, int number, String text) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Information card explaining udev rules requirement on Linux
class _UdevInstructionsSection extends StatelessWidget {
  const _UdevInstructionsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'USB Access Required',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Linux requires special permissions to access USB devices for firmware updates. '
              'Click "Install USB Rules" above to install the required udev rules.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'You will be prompted for your password to authorize the installation.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Information card explaining sandbox restrictions on macOS TestFlight/App Store
class _SandboxInstructionsSection extends StatelessWidget {
  const _SandboxInstructionsSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'macOS Sandbox Restriction',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Firmware updates are not available in the TestFlight/App Store version '
              'due to macOS sandbox restrictions.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'To update your Disting NT firmware, please download the direct version '
              'from GitHub Releases. All other features work normally in this version.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Click "Download Direct Version" above to get the unrestricted version.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
