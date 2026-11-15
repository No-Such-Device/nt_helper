import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/ui/poly_multisample/poly_multisample_builder_cubit.dart';
import 'package:path/path.dart' as p;

class PolySamplesLandingView extends StatelessWidget {
  const PolySamplesLandingView({
    super.key,
    required this.state,
    required this.onOpenHardware,
    required this.onOpenLocal,
    required this.onImport,
    required this.onOpenRecent,
    required this.onStartEmptyDraft,
  });

  final PolyMultisampleBuilderState state;
  final VoidCallback onOpenHardware;
  final VoidCallback onOpenLocal;
  final VoidCallback onImport;
  final VoidCallback? onOpenRecent;
  final VoidCallback onStartEmptyDraft;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Build or edit a Disting NT multisample folder',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _SourceCard(
                        icon: Icons.sd_storage,
                        title: 'NT Hardware',
                        description: 'Browse /samples on the connected module',
                        onTap: onOpenHardware,
                      ),
                      _SourceCard(
                        icon: Icons.folder_open,
                        title: 'Local Folder',
                        description:
                            'Open a multisample folder on this computer',
                        onTap: onOpenLocal,
                      ),
                      _SourceCard(
                        icon: Icons.file_upload,
                        title: 'Import Files',
                        description: 'Stage WAVs or a Decent Sampler preset',
                        onTap: onImport,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (onOpenRecent != null && state.lastLocalFolder != null)
                    TextButton.icon(
                      onPressed: onOpenRecent,
                      icon: const Icon(Icons.history),
                      label: Text(
                        'Recent: ${p.basename(state.lastLocalFolder!)}',
                      ),
                    ),
                  TextButton(
                    onPressed: onStartEmptyDraft,
                    child: const Text('Start empty draft'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PolyHardwareFolderList extends StatelessWidget {
  const PolyHardwareFolderList({
    super.key,
    required this.folders,
    required this.onOpen,
    required this.onBack,
  });

  final List<String> folders;
  final ValueChanged<String> onOpen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to sample sources',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Semantics(
                header: true,
                child: Text(
                  'Sample folders on /samples',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: folders.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                leading: const Icon(Icons.folder),
                title: Text(folder),
                onTap: () => onOpen(folder),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PolyLargeFolderView extends StatelessWidget {
  const PolyLargeFolderView({
    super.key,
    required this.messages,
    required this.onChooseSmaller,
    required this.onImportSubset,
  });

  final List<String> messages;
  final VoidCallback onChooseSmaller;
  final VoidCallback onImportSubset;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber),
                        const SizedBox(width: 8),
                        Semantics(
                          header: true,
                          child: Text(
                            'Large sample folder',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final message in messages) Text(message),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: onChooseSmaller,
                          child: const Text('Choose smaller folder'),
                        ),
                        FilledButton(
                          onPressed: onImportSubset,
                          child: const Text('Import subset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 160,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 40),
                const Spacer(),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(description, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
