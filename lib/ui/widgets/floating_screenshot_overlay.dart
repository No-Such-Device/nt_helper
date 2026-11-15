import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart'; // Import for Clipboard
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/ui/widgets/draggable_resizable_overlay.dart';
import 'package:pasteboard/pasteboard.dart';

class FloatingScreenshotOverlay extends StatefulWidget {
  final OverlayEntry overlayEntry;
  final DistingCubit cubit;

  const FloatingScreenshotOverlay({
    super.key,
    required this.overlayEntry,
    required this.cubit,
  });

  @override
  State<FloatingScreenshotOverlay> createState() =>
      _FloatingScreenshotOverlayState();
}

class _FloatingScreenshotOverlayState extends State<FloatingScreenshotOverlay> {
  Timer? _updateTimer;
  Uint8List? _screenshot;
  @override
  void initState() {
    super.initState();
    _startUpdateTimer();
    _fetchScreenshot();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchScreenshot();
    });
  }

  void _fetchScreenshot() async {
    await widget.cubit.updateScreenshot();

    // Safely access screenshot using maybeMap
    final screenshot = switch (widget.cubit.state) {
      DistingStateSynchronized(screenshot: final s) => s,
      _ => null,
    };

    if (mounted) {
      setState(() {
        _screenshot = screenshot;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    if (_screenshot != null) {
      Pasteboard.writeImage(_screenshot);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableResizableOverlay(
      overlayEntry: widget.overlayEntry,
      child: _FloatingScreenshotContent(
        cubit: widget.cubit,
        overlayEntry: widget.overlayEntry,
        screenshot: _screenshot,
        onCopyToClipboard: _copyToClipboard,
      ),
    );
  }
}

class _FloatingScreenshotContent extends StatelessWidget {
  final DistingCubit cubit;
  final OverlayEntry overlayEntry;
  final Uint8List? screenshot;
  final VoidCallback onCopyToClipboard;

  const _FloatingScreenshotContent({
    required this.cubit,
    required this.overlayEntry,
    required this.screenshot,
    required this.onCopyToClipboard,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Stack(
          children: [
            // Main screenshot content
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: screenshot != null
                  ? Semantics(
                      label: 'Disting NT screen capture. Long press to copy to clipboard.',
                      image: true,
                      child: GestureDetector(
                        onLongPress: onCopyToClipboard,
                        child: SizedBox.expand(
                          child: Image.memory(
                            screenshot!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),

            // Controls positioned on the right side
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    semanticLabel: 'Close screenshot overlay',
                  ),
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () {
                    overlayEntry.remove();
                  },
                  tooltip: 'Close',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
