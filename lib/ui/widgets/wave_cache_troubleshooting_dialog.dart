import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:nt_helper/services/wave_cache_maintenance_service.dart';

class WaveCacheTroubleshootingDialog extends StatefulWidget {
  const WaveCacheTroubleshootingDialog({super.key, required this.service});

  final WaveCacheMaintenanceService service;

  @override
  State<WaveCacheTroubleshootingDialog> createState() =>
      _WaveCacheTroubleshootingDialogState();
}

class _WaveCacheTroubleshootingDialogState
    extends State<WaveCacheTroubleshootingDialog> {
  final _fragmentController = TextEditingController();
  final _fragmentFocusNode = FocusNode(
    debugLabel: 'WaveCacheTroubleshootingDialog.fragment',
  );

  WaveCacheCleanupPlan? _plan;
  WaveCacheCleanupResult? _result;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fragmentController.dispose();
    _fragmentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Semantics(
          header: true,
          child: const Row(
            children: [
              Icon(Icons.troubleshoot),
              SizedBox(width: 8),
              Expanded(child: Text('Wave cache troubleshooting')),
            ],
          ),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: _buildContent(context)),
        ),
        actions: _buildActions(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_busy) {
      final deleting = _plan != null;
      return Semantics(
        liveRegion: true,
        label: deleting
            ? 'Deleting selected files and remounting the SD card'
            : 'Searching the SD card for WAV and cache issues',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              deleting
                  ? 'Deleting selected files and remounting the SD card…'
                  : 'Searching every folder on the SD card…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_result != null) {
      return _buildResult(context, _result!);
    }

    if (_plan != null) {
      return _buildPlan(context, _plan!);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter part of the WAV filename shown on the Disting NT. NT Helper '
          'will search the entire SD card and find the exact '
          'distingNT.wavcache file in the same folder. You can also scan for '
          'zero-byte WAV files that the Disting NT cannot load.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('wave-cache-fragment'),
          controller: _fragmentController,
          focusNode: _fragmentFocusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'WAV filename fragment',
            hintText: 'For example, FM1 - Track 44',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_fragmentController.text.trim().isNotEmpty) {
              _findForFragment();
            }
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Nothing is deleted until the matches are shown and you confirm. '
          'After a successful deletion, NT Helper will remount the SD card so '
          'the Disting NT rebuilds its sample cache.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlan(BuildContext context, WaveCacheCleanupPlan plan) {
    final cacheCount = plan.cachePaths.length;
    final zeroByteWavCount = plan.zeroByteWavPaths.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.isZeroByteWavScan) ...[
          Text(
            zeroByteWavCount == 0
                ? 'No zero-byte WAV files were found.'
                : '$zeroByteWavCount zero-byte WAV ${zeroByteWavCount == 1 ? 'file was' : 'files were'} found.',
          ),
        ] else if (plan.isGlobal) ...[
          Text(
            cacheCount == 0
                ? 'No ${WaveCacheMaintenanceService.cacheFileName} files were found.'
                : '$cacheCount wave cache ${cacheCount == 1 ? 'file was' : 'files were'} found.',
          ),
        ] else ...[
          Text(
            plan.matchedSamplePaths.isEmpty
                ? 'No WAV filenames contain “${plan.sampleFragment}”.'
                : '${plan.matchedSamplePaths.length} matching WAV '
                      '${plan.matchedSamplePaths.length == 1 ? 'file was' : 'files were'} found.',
          ),
          if (plan.matchedSamplePaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPathSection('Matching WAV files', plan.matchedSamplePaths),
          ],
        ],
        if (plan.zeroByteWavPaths.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPathSection(
            'Zero-byte WAV files to delete',
            plan.zeroByteWavPaths,
          ),
        ],
        if (plan.cachePaths.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPathSection('Cache files to delete', plan.cachePaths),
        ],
        if (plan.hasDeletions) ...[
          const SizedBox(height: 12),
          Text(
            'Confirming will permanently delete ${_deletionSummary(plan)} and '
            'remount the SD card so the Disting NT rebuilds its sample cache.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else if (plan.matchedSamplePaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'The matching sample folders do not contain a visible '
            'distingNT.wavcache file, so nothing will be deleted.',
          ),
        ],
        if (plan.directoriesWithoutCache.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildPathSection(
            plan.isZeroByteWavScan
                ? 'Zero-byte WAV folders without a cache'
                : 'Matching folders without a cache',
            plan.directoriesWithoutCache,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResult(BuildContext context, WaveCacheCleanupResult result) {
    final deletedCacheCount = result.deletedCachePaths.length;
    final deletedZeroByteWavCount = result.deletedZeroByteWavPaths.length;
    final deletedCount = deletedCacheCount + deletedZeroByteWavCount;
    final failedEntries = {
      ...result.failedZeroByteWavPaths,
      ...result.failedCachePaths,
    };
    final failedCount = failedEntries.length;
    final success = deletedCount > 0 && result.remountRequested;
    final title = success
        ? deletedZeroByteWavCount > 0
              ? 'Zero-byte WAV repair complete'
              : 'Wave cache reset complete'
        : deletedCount > 0
        ? 'Files deleted, but SD remount failed'
        : 'No files were deleted';
    final deletedSummary = _resultDeletionSummary(result);

    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(
            success
                ? '$deletedSummary ${deletedCount == 1 ? 'was' : 'were'} deleted and the SD card remount was requested.'
                : deletedCount > 0
                ? '$deletedSummary ${deletedCount == 1 ? 'was' : 'were'} deleted. Use System > Remount SD Card before testing the sample again.'
                : 'The SD card was not remounted.',
          ),
          if (result.remountError != null) ...[
            const SizedBox(height: 8),
            Text(
              'SD remount failed: ${result.remountError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (failedCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$failedCount ${failedCount == 1 ? 'file could' : 'files could'} not be deleted:',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 4),
            ...failedEntries.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText('${entry.key}: ${entry.value}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPathSection(String title, List<String> paths) {
    const maxVisiblePaths = 8;
    final visiblePaths = paths.take(maxVisiblePaths);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title)),
        const SizedBox(height: 4),
        ...visiblePaths.map(
          (path) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SelectableText(path),
          ),
        ),
        if (paths.length > maxVisiblePaths)
          Text('…and ${paths.length - maxVisiblePaths} more'),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_busy) return const [];

    final result = _result;
    if (result != null) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(result.remountRequested),
          child: const Text('Done'),
        ),
      ];
    }

    final plan = _plan;
    if (plan != null) {
      return [
        TextButton(onPressed: _startOver, child: const Text('Back')),
        if (plan.hasDeletions)
          FilledButton(
            key: const Key('wave-cache-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _deleteAndRemount,
            child: Text('Delete ${_deletionSummary(plan)} and remount'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
      ];
    }

    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      OutlinedButton(
        key: const Key('wave-cache-find-all'),
        onPressed: _findAll,
        child: const Text('Find all caches'),
      ),
      OutlinedButton(
        key: const Key('wave-cache-find-zero-byte-wavs'),
        onPressed: _findZeroByteWavs,
        child: const Text('Find empty WAVs'),
      ),
      FilledButton(
        key: const Key('wave-cache-find-fragment'),
        onPressed: _fragmentController.text.trim().isEmpty
            ? null
            : _findForFragment,
        child: const Text('Find sample'),
      ),
    ];
  }

  Future<void> _findForFragment() async {
    await _scan(
      () => widget.service.findForSampleFragment(_fragmentController.text),
    );
  }

  Future<void> _findAll() async {
    await _scan(widget.service.findAll);
  }

  Future<void> _findZeroByteWavs() async {
    await _scan(widget.service.findZeroByteWavs);
  }

  Future<void> _scan(Future<WaveCacheCleanupPlan> Function() scan) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = await scan();
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _busy = false;
      });
      _announce(
        plan.hasDeletions
            ? 'Search complete. ${plan.zeroByteWavPaths.length} zero-byte WAV files and ${plan.cachePaths.length} wave cache files are ready for review.'
            : 'Search complete. No files are ready to delete.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not search the SD card: $error';
      });
      _announce(_error!);
    }
  }

  Future<void> _deleteAndRemount() async {
    final plan = _plan;
    if (plan == null || !plan.hasDeletions) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.deleteAndRemount(plan);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
    _announce(
      result.remountRequested
          ? 'File deletion complete. The SD card is remounting.'
          : 'File deletion did not complete. The SD card was not remounted.',
    );
  }

  String _deletionSummary(WaveCacheCleanupPlan plan) {
    final parts = <String>[];
    final zeroByteWavCount = plan.zeroByteWavPaths.length;
    final cacheCount = plan.cachePaths.length;
    if (zeroByteWavCount > 0) {
      parts.add(
        '$zeroByteWavCount ${zeroByteWavCount == 1 ? 'empty WAV' : 'empty WAVs'}',
      );
    }
    if (cacheCount > 0) {
      parts.add('$cacheCount ${cacheCount == 1 ? 'cache' : 'caches'}');
    }
    return parts.join(' and ');
  }

  String _resultDeletionSummary(WaveCacheCleanupResult result) {
    final parts = <String>[];
    final zeroByteWavCount = result.deletedZeroByteWavPaths.length;
    final cacheCount = result.deletedCachePaths.length;
    if (zeroByteWavCount > 0) {
      parts.add(
        '$zeroByteWavCount zero-byte WAV ${zeroByteWavCount == 1 ? 'file' : 'files'}',
      );
    }
    if (cacheCount > 0) {
      parts.add('$cacheCount cache ${cacheCount == 1 ? 'file' : 'files'}');
    }
    return parts.join(' and ');
  }

  void _startOver() {
    setState(() {
      _plan = null;
      _result = null;
      _error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fragmentFocusNode.requestFocus();
    });
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }
}
