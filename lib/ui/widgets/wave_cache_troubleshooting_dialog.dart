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
            ? 'Deleting wave cache files and remounting the SD card'
            : 'Searching the SD card for wave cache files',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              deleting
                  ? 'Deleting cache files and remounting the SD card…'
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
          'distingNT.wavcache file in the same folder.',
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plan.isGlobal) ...[
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
        if (plan.cachePaths.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPathSection('Cache files to delete', plan.cachePaths),
          const SizedBox(height: 12),
          Text(
            'Confirming will permanently delete '
            '$cacheCount ${cacheCount == 1 ? 'cache file' : 'cache files'} '
            'and remount the SD card so the Disting NT rebuilds its sample cache.',
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
            'Matching folders without a cache',
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
    final deletedCount = result.deletedCachePaths.length;
    final failedCount = result.failedCachePaths.length;
    final success = deletedCount > 0 && result.remountRequested;
    final title = success
        ? 'Wave cache reset complete'
        : deletedCount > 0
        ? 'Cache deleted, but SD remount failed'
        : 'No cache files were deleted';

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
                ? '$deletedCount ${deletedCount == 1 ? 'cache file was' : 'cache files were'} deleted and the SD card remount was requested.'
                : deletedCount > 0
                ? '$deletedCount ${deletedCount == 1 ? 'cache file was' : 'cache files were'} deleted. Use System > Remount SD Card before testing the sample again.'
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
              '$failedCount ${failedCount == 1 ? 'cache file could' : 'cache files could'} not be deleted:',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 4),
            ...result.failedCachePaths.entries.map(
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
        if (plan.cachePaths.isNotEmpty)
          FilledButton(
            key: const Key('wave-cache-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: _deleteAndRemount,
            child: Text(
              'Delete ${plan.cachePaths.length} '
              '${plan.cachePaths.length == 1 ? 'cache' : 'caches'} and remount',
            ),
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
        plan.cachePaths.isEmpty
            ? 'Search complete. No wave cache files are ready to delete.'
            : 'Search complete. ${plan.cachePaths.length} wave cache files are ready for review.',
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
    if (plan == null || plan.cachePaths.isEmpty) return;

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
          ? 'Wave cache deletion complete. The SD card is remounting.'
          : 'Wave cache deletion did not complete. The SD card was not remounted.',
    );
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
