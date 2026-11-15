import 'package:material_ui/material_ui.dart';

/// Fixed recovery slots: Retry feedback never moves the title or controls.
class GalleryRecoveryPanel extends StatelessWidget {
  const GalleryRecoveryPanel({
    super.key,
    required this.message,
    required this.retrying,
    required this.onRetry,
  });
  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 560,
      height: 280,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text('Gallery temporarily unavailable'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    '$message\nYour library and local file installation remain usable.',
                  ),
                ),
              ),
              SizedBox(
                height: 32,
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    retrying
                        ? 'Retrying gallery transfer…'
                        : 'Gallery transfer incomplete',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  autofocus: true,
                  onPressed: retrying ? null : onRetry,
                  child: const Text('Retry gallery transfer'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
