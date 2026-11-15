import 'package:material_ui/material_ui.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';

enum _UpdateState { readyToDownload, downloading, installing, done, error }

class AppUpdateDialog extends StatefulWidget {
  final AppRelease release;
  final AppUpdateService updateService;

  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.updateService,
  });

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateState _state = _UpdateState.readyToDownload;
  double _downloadProgress = 0;
  String _errorMessage = '';
  String _doneMessage = '';
  bool _canRestart = false;
  String? _openFolderPath;

  Future<void> _startDownloadAndInstall() async {
    setState(() {
      _state = _UpdateState.downloading;
      _downloadProgress = 0;
    });

    try {
      final updatePath = await widget.updateService.downloadUpdate(
        widget.release,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
      );

      if (!mounted) return;

      setState(() => _state = _UpdateState.installing);

      final result = await widget.updateService.installUpdate(updatePath);

      if (!mounted) return;

      if (result.outcome == InstallOutcome.error) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = result.message;
        });
      } else {
        setState(() {
          _state = _UpdateState.done;
          _doneMessage = result.message;
          _canRestart = result.outcome == InstallOutcome.needsRestart;
          _openFolderPath = result.folderPath;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _restartApp() async {
    await AppUpdateService.relaunchApp();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Semantics(header: true, child: const Text('Update Available')),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GptMarkdown(
                  widget.release.body.isNotEmpty
                      ? widget.release.body
                      : 'No release notes available.',
                  textDirection: Directionality.of(context),
                  html: false,
                  isStreaming: false,
                  styleSheet: const GptMarkdownStyleSheet(
                    codeBlock: CodeBlockStyle(
                      showCopyButton: false,
                      showLanguageLabel: false,
                    ),
                  ),
                  onLinkTap: (url, title) => launchUrl(Uri.parse(url)),
                ),
              ),
            ),
            if (_state == _UpdateState.downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 4),
              Text(
                'Downloading... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_state == _UpdateState.installing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                'Installing update...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_state == _UpdateState.error) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 60),
                child: SingleChildScrollView(
                  child: Text(
                    _errorMessage.length > 200
                        ? '${_errorMessage.substring(0, 200)}...'
                        : _errorMessage,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
            if (_state == _UpdateState.done) ...[
              const SizedBox(height: 12),
              Text(
                _doneMessage,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _state == _UpdateState.downloading ||
                  _state == _UpdateState.installing
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_state == _UpdateState.readyToDownload ||
            _state == _UpdateState.error)
          FilledButton(
            onPressed: _startDownloadAndInstall,
            child: const Text('Download & Install'),
          ),
        if (_state == _UpdateState.done && _canRestart)
          FilledButton(
            onPressed: _restartApp,
            child: const Text('Restart Now'),
          ),
        if (_state == _UpdateState.done && _openFolderPath != null)
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.directory(_openFolderPath!)),
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
          ),
      ],
    );
  }
}
