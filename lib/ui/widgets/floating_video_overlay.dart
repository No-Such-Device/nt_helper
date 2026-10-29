import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FlutterView, ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/cubit/video_frame_cubit.dart';
import 'package:nt_helper/cubit/video_frame_state.dart';
import 'package:nt_helper/domain/video/video_stream_state.dart';
import 'package:nt_helper/ui/widgets/draggable_resizable_overlay.dart';
import 'package:nt_helper/ui/widgets/remote_control_cluster.dart';
import 'package:nt_helper/models/remote_control_state.dart';
import 'package:nt_helper/models/remote_action.dart';
import 'package:pasteboard/pasteboard.dart';

class FloatingVideoOverlay extends StatefulWidget {
  final OverlayEntry overlayEntry;
  final DistingCubit cubit;
  final VideoFrameCubit videoFrameCubit;

  const FloatingVideoOverlay({
    super.key,
    required this.overlayEntry,
    required this.cubit,
    required this.videoFrameCubit,
  });

  @override
  State<FloatingVideoOverlay> createState() => _FloatingVideoOverlayState();
}

class _FloatingVideoOverlayState extends State<FloatingVideoOverlay>
    with WidgetsBindingObserver {
  bool _remoteExpanded = false;
  bool _active = true;
  bool _foreground = true;
  bool _viewFocused = true;
  String? _remoteSession;
  late RemoteControlState _remoteState;
  StreamSubscription<RemoteControlState>? _remoteSubscription;
  late ScaffoldMessengerState _scaffoldMessenger;
  late FlutterView _view;
  late TextDirection _textDirection;
  String? _reportedRemoteError;
  Uint8List? _sourceFrame;
  Uint8List? _lastFrame;
  Uint8List? _displayFrame; // Stable frame buffer for display
  StreamSubscription<VideoStreamState?>? _videoStateSubscription;
  Stream<dynamic>? _connectedStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remoteState = widget.cubit.remoteControlState;
    _remoteSubscription = widget.cubit.remoteControlStateStream.listen(
      _onRemoteState,
    );
    _videoStateSubscription = widget.cubit.videoStreamState.listen(
      _onVideoStateChanged,
    );

    // Start video stream when widget is created
    widget.cubit.startVideoStream();
    _onVideoStateChanged(widget.cubit.currentVideoState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cleanup can finish after overlay removal; never look up its context then.
    _scaffoldMessenger = ScaffoldMessenger.of(context);
    _view = View.of(context);
    _textDirection = Directionality.of(context);
  }

  void _onVideoStateChanged(VideoStreamState? videoState) {
    final stream = videoState?.maybeWhen(
      streaming: (videoStream, width, height, fps) => videoStream,
      orElse: () => null,
    );

    if (stream == null) {
      _connectedStream = null;
      widget.videoFrameCubit.disconnect();
      return;
    }

    if (!identical(stream, _connectedStream)) {
      _connectedStream = stream;
      widget.videoFrameCubit.connectToStream(stream);
    }
  }

  void _onRemoteState(RemoteControlState _) {
    if (!mounted) return;
    // Several synchronous inputs can publish before the stream callback runs.
    // Read the current snapshot rather than reopening an already replaced host.
    final state = widget.cubit.remoteControlState;
    final previous = _remoteState;
    _remoteState = state;
    if (_remoteSession != state.sessionId) _remoteSession = null;
    if (_remoteExpanded &&
        _active &&
        _remoteSession == null &&
        state.available &&
        state.sessionId == null &&
        state.error == null) {
      _openRemoteSession();
    }
    setState(() {});
    if (state.error == null) _reportedRemoteError = null;
    if (state.error != null && state.error != previous.error) {
      _showRemoteError(state.error!);
    } else if (_remoteExpanded &&
        state.unavailableReason != null &&
        state.unavailableReason != previous.unavailableReason) {
      _announce(state.unavailableReason!);
    }
  }

  void _showRemoteError(String message) {
    if (!_scaffoldMessenger.mounted || _reportedRemoteError == message) return;
    // The state stream and cleanup future can both report the same failure.
    _reportedRemoteError = message;
    _announce(message);
    _scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _announce(String message) {
    SemanticsService.sendAnnouncement(_view, message, _textDirection);
  }

  void _openRemoteSession() {
    _remoteState = widget.cubit.remoteControlState;
    if (!_remoteState.available ||
        (_remoteSession != null && _remoteSession == _remoteState.sessionId)) {
      return;
    }
    _remoteSession = widget.cubit.openRemoteSession();
    _remoteState = widget.cubit.remoteControlState;
  }

  void _closeRemoteSession() {
    final session = _remoteSession;
    _remoteSession = null;
    if (session != null) {
      final cubit = widget.cubit;
      unawaited(
        cubit.closeRemoteSession(session).catchError((Object _) {
          final error = cubit.remoteControlState.error;
          if (error != null) _showRemoteError(error);
        }),
      );
    }
  }

  void _toggleRemote() {
    setState(() {
      _remoteExpanded = !_remoteExpanded;
      if (_remoteExpanded && _active) {
        _openRemoteSession();
      } else {
        _closeRemoteSession();
      }
    });
    _announce(
      _remoteState.unavailableReason ??
          (_remoteExpanded
              ? 'Remote controls expanded'
              : 'Remote controls folded'),
    );
  }

  void _sendRemote(RemoteAction action) {
    final session = _remoteSession;
    if (session == null) return;
    unawaited(
      widget.cubit.sendRemoteAction(session, action).catchError((Object _) {}),
    );
  }

  void _wheelRemote(int pushIndex, int adjustment) {
    if (!_remoteExpanded || !widget.cubit.remoteControlState.available) return;
    _openRemoteSession();
    if (pushIndex < 7) {
      _adjustPot(pushIndex - 4, adjustment);
    } else {
      _sendRemote(RemoteEncoderTurn(pushIndex - 7, adjustment));
    }
  }

  void _adjustPot(int index, int adjustment) {
    final session = _remoteSession;
    if (session == null) return;
    unawaited(
      widget.cubit
          .adjustRemotePot(session, index, adjustment)
          .catchError((Object _) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateActivity();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _viewFocused = event.state == ViewFocusState.focused;
    _updateActivity();
  }

  void _updateActivity() {
    final active = _foreground && _viewFocused;
    if (active == _active) return;
    _active = active;
    if (_active && _remoteExpanded) {
      _openRemoteSession();
    } else {
      _closeRemoteSession();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remoteSubscription?.cancel();
    _closeRemoteSession();
    _videoStateSubscription?.cancel();
    _videoStateSubscription = null;
    _connectedStream = null;

    // Stop video stream when widget is disposed
    widget.videoFrameCubit.disconnect();
    widget.cubit.stopVideoStream();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    if (_lastFrame != null) {
      Pasteboard.writeImage(_lastFrame);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video frame copied to clipboard')),
        );
      }
    }
  }

  Widget _buildDisplayModeBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          MergeSemantics(
            child: Semantics(
              expanded: _remoteExpanded,
              child: TextButton.icon(
                key: const ValueKey('video-remote-fold'),
                onPressed: _toggleRemote,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: Icon(
                  _remoteExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: const Text('Remote'),
              ),
            ),
          ),
          _displayModeButton(
            Icons.list_alt_rounded,
            'Parameter View',
            DisplayMode.parameters,
          ),
          _displayModeButton(
            Icons.line_axis_rounded,
            'Algorithm UI',
            DisplayMode.algorithmUI,
          ),
          _displayModeButton(
            Icons.line_weight_rounded,
            'Overview UI',
            DisplayMode.overview,
          ),
          _displayModeButton(
            Icons.leaderboard_rounded,
            'Overview VU Meters',
            DisplayMode.overviewVUs,
          ),
        ],
      ),
    );
  }

  Widget _displayModeButton(IconData icon, String tooltip, DisplayMode mode) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: Colors.white),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: IconButton.styleFrom(
        fixedSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => widget.cubit.setDisplayMode(mode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableResizableOverlay(
      overlayEntry: widget.overlayEntry,
      topBar: _buildDisplayModeBar(),
      initialWidth: 384,
      initialHeight: 96,
      minWidth: 280,
      reserveTopBarSpace: true,
      keepControlsVisible: true,
      bottomContentHeight: RemoteControlCluster.height,
      bottomContent: _remoteExpanded
          ? RemoteControlCluster(
              state: RemoteControlState(
                connectionId: _remoteState.connectionId,
                sessionId: _remoteSession == _remoteState.sessionId
                    ? _remoteSession
                    : null,
                unavailableReason: _remoteState.unavailableReason,
                heldControls: _remoteSession == _remoteState.sessionId
                    ? _remoteState.heldControls
                    : const {},
                potValues: _remoteState.potValues,
                pending: _remoteState.pending,
                error: _remoteState.error,
              ),
              onAction: _sendRemote,
              onPotAdjustment: _adjustPot,
              onWheelAdjustment: _wheelRemote,
            )
          : null,
      child: FloatingVideoContent(
        cubit: widget.cubit,
        videoFrameCubit: widget.videoFrameCubit,
        lastFrame: _lastFrame,
        displayFrame: _displayFrame,
        onCopyToClipboard: _copyToClipboard,
        onFrameUpdate: (frameData) {
          // A host rebuild is not a new video frame.
          if (identical(frameData, _sourceFrame)) return;
          _sourceFrame = frameData;
          final stableBytes = Uint8List.fromList(frameData);
          final previousFrame = _displayFrame;

          _lastFrame = stableBytes;
          _displayFrame = stableBytes;

          if (previousFrame != null) {
            MemoryImage(previousFrame).evict();
          }

          // Schedule update for next frame instead of calling setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
  }
}

class FloatingVideoContent extends StatelessWidget {
  final DistingCubit cubit;
  final VideoFrameCubit videoFrameCubit;
  final Uint8List? lastFrame;
  final Uint8List? displayFrame;
  final VoidCallback onCopyToClipboard;
  final ValueChanged<Uint8List> onFrameUpdate;

  static const int _fadeInFrames = 8;

  const FloatingVideoContent({
    super.key,
    required this.cubit,
    required this.videoFrameCubit,
    required this.lastFrame,
    required this.displayFrame,
    required this.onCopyToClipboard,
    required this.onFrameUpdate,
  });

  Widget _buildVideoContent(BuildContext context) {
    // Use VideoFrameCubit for all other platforms
    return BlocBuilder<VideoFrameCubit, VideoFrameState>(
      bloc: videoFrameCubit,
      builder: (context, frameState) {
        return frameState.when(
          // Regular frame state with frame data
          (frameData, frameCounter, lastFrameTime, fps) {
            if (frameData != null && frameData.isNotEmpty) {
              // Validate frame data before using it
              if (frameData.length > 10) {
                // Basic size check
                onFrameUpdate(frameData);
              }
            }

            // Always show the stable display frame
            final bytesToDisplay = displayFrame ?? frameData;
            if (bytesToDisplay != null) {
              // Start at 30% opacity so first frame is visible, fade to 100%
              final framesIntoFade = frameCounter.clamp(0, _fadeInFrames);
              final fadeT = (framesIntoFade / _fadeInFrames).clamp(0.0, 1.0);
              final opacity = 0.3 + 0.7 * Curves.easeOut.transform(fadeT);

              return Semantics(
                label:
                    'Disting NT display. Long press to copy frame to clipboard.',
                child: GestureDetector(
                  onLongPress: onCopyToClipboard,
                  child: SizedBox.expand(
                    child: RepaintBoundary(
                      child: ColoredBox(
                        color: Colors.black,
                        child: Opacity(
                          opacity: opacity,
                          child: Image.memory(
                            bytesToDisplay,
                            key: const ValueKey('stable_frame'),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Text(
                                  'Frame error',
                                  style: TextStyle(color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            } else {
              return const ColoredBox(color: Colors.black);
            }
          },
          // Initial state - check connection status from main cubit
          initial: () {
            return BlocBuilder<DistingCubit, DistingState>(
              bloc: cubit,
              builder: (context, cubitState) {
                final videoState = cubitState.maybeWhen(
                  synchronized:
                      (
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        _,
                        videoStream,
                        _,
                        _,
                        _,
                        _,
                      ) => videoStream,
                  orElse: () => null,
                );

                final errorMessage = videoState?.maybeWhen(
                  error: (message) => message,
                  orElse: () => null,
                );

                if (errorMessage == null) {
                  return const ColoredBox(color: Colors.black);
                }

                return ColoredBox(
                  color: Colors.black,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    builder: (context, opacity, child) =>
                        Opacity(opacity: opacity, child: child),
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final retryButton = TextButton(
                            onPressed: () => cubit.startVideoStream(),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(48, 28),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Retry'),
                          );

                          final message = Text(
                            errorMessage,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                            maxLines: constraints.maxHeight < 96 ? 2 : null,
                            overflow: constraints.maxHeight < 96
                                ? TextOverflow.ellipsis
                                : null,
                            textAlign: TextAlign.center,
                          );

                          if (constraints.maxHeight < 96) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Theme.of(context).colorScheme.error,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(child: message),
                                  const SizedBox(width: 8),
                                  retryButton,
                                ],
                              ),
                            );
                          }

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 8),
                              message,
                              const SizedBox(height: 8),
                              retryButton,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _buildVideoContent(context),
        ),
      ),
    );
  }
}
