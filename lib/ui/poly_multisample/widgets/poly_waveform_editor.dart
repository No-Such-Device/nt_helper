import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/poly_multisample/poly_audio_preview_service.dart';
import 'package:nt_helper/poly_multisample/wav_metadata.dart';

enum PolyWaveformEditorMode { loop, trim }

class PolyWaveformEditor extends StatefulWidget {
  const PolyWaveformEditor({
    super.key,
    required this.overview,
    required this.mode,
    required this.startFrame,
    required this.endFrame,
    required this.onChanged,
    this.loopStartFrame,
    this.loopEndFrame,
    this.onLoopChanged,
    this.fadeInFrames = 0,
    this.fadeOutFrames = 0,
    this.fadeInCurve = WavFadeCurve.linear,
    this.fadeOutCurve = WavFadeCurve.linear,
    this.fadeInStrength = 0.5,
    this.fadeOutStrength = 0.5,
    this.playback,
    this.height = 120,
  });

  final WavOverview overview;
  final PolyWaveformEditorMode mode;
  final int? startFrame;
  final int? endFrame;
  final void Function(int startFrame, int endFrame) onChanged;
  final int? loopStartFrame;
  final int? loopEndFrame;
  final void Function(int loopStartFrame, int loopEndFrame)? onLoopChanged;
  final int fadeInFrames;
  final int fadeOutFrames;
  final WavFadeCurve fadeInCurve;
  final WavFadeCurve fadeOutCurve;
  final double fadeInStrength;
  final double fadeOutStrength;
  final PolyAudioPreviewSourcePlayback? playback;
  final double height;

  @override
  State<PolyWaveformEditor> createState() => _PolyWaveformEditorState();
}

class _PolyWaveformEditorState extends State<PolyWaveformEditor>
    with SingleTickerProviderStateMixin {
  _WaveformHandle? _activeHandle;
  var _showFocusHighlight = false;
  var _secondaryDragActive = false;
  late final AnimationController _playheadTicker;

  int get _start => widget.startFrame ?? 0;
  int get _end =>
      widget.endFrame ?? math.max(0, widget.overview.frameCount - 1);
  int? get _loopStart => widget.loopStartFrame;
  int? get _loopEnd => widget.loopEndFrame;

  @override
  void initState() {
    super.initState();
    _playheadTicker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _syncPlayheadTicker();
  }

  @override
  void didUpdateWidget(covariant PolyWaveformEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayheadTicker();
  }

  @override
  void dispose() {
    _playheadTicker.dispose();
    super.dispose();
  }

  void _syncPlayheadTicker() {
    if (widget.playback == null) {
      _playheadTicker.stop();
      return;
    }
    if (!_playheadTicker.isAnimating) {
      _playheadTicker.repeat();
    }
  }

  bool get _loopModifierPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
  }

  void _beginDrag(Offset position, double width, {required bool loopGesture}) {
    final startX = _frameToX(_start, width);
    final endX = _frameToX(_end, width);
    final distances = <_WaveformHandle, double>{};
    if (!loopGesture) {
      distances.addAll({
        _WaveformHandle.start: (position.dx - startX).abs(),
        _WaveformHandle.end: (position.dx - endX).abs(),
      });
    }
    final loopStart = _loopStart;
    final loopEnd = _loopEnd;
    if (loopGesture &&
        widget.onLoopChanged != null &&
        loopStart != null &&
        loopEnd != null) {
      distances[_WaveformHandle.loopStart] =
          (position.dx - _frameToX(loopStart, width)).abs();
      distances[_WaveformHandle.loopEnd] =
          (position.dx - _frameToX(loopEnd, width)).abs();
    }
    if (distances.isEmpty) return;
    final closest = distances.entries.reduce(
      (best, entry) => entry.value < best.value ? entry : best,
    );
    if (closest.value > 24) {
      _activeHandle = null;
      return;
    }
    _activeHandle = closest.key;
  }

  void _updateDrag(Offset position, double width) {
    final handle = _activeHandle;
    if (handle == null) return;
    final maxFrame = math.max(0, widget.overview.frameCount - 1);
    final rawFrame =
        ((position.dx.clamp(0, width) / math.max(1, width)) *
                widget.overview.frameCount)
            .round();
    final snapped = widget.overview.nearestZeroCrossing(rawFrame);
    final start = _start;
    final end = _end;
    switch (handle) {
      case _WaveformHandle.start:
        widget.onChanged(_clampFrame(snapped, 0, end - 1), end);
      case _WaveformHandle.end:
        widget.onChanged(start, _clampFrame(snapped, start + 1, maxFrame));
      case _WaveformHandle.loopStart:
        final loopEnd = _loopEnd;
        if (loopEnd == null || widget.onLoopChanged == null) return;
        widget.onLoopChanged!(_clampFrame(snapped, 0, loopEnd - 1), loopEnd);
      case _WaveformHandle.loopEnd:
        final loopStart = _loopStart;
        if (loopStart == null || widget.onLoopChanged == null) return;
        widget.onLoopChanged!(
          loopStart,
          _clampFrame(snapped, loopStart + 1, maxFrame),
        );
    }
  }

  void _setPoint(
    Offset position,
    double width, {
    bool forceLoopGesture = false,
  }) {
    final maxFrame = math.max(0, widget.overview.frameCount - 1);
    final rawFrame =
        ((position.dx.clamp(0, width) / math.max(1, width)) *
                widget.overview.frameCount)
            .round();
    final frame = widget.overview
        .nearestZeroCrossing(rawFrame)
        .clamp(0, maxFrame)
        .toInt();
    final loopGesture = forceLoopGesture || _loopModifierPressed;
    if (loopGesture && widget.onLoopChanged != null) {
      final start = _loopStart ?? _start;
      final end = _loopEnd ?? _end;
      final mid = (start + end) / 2;
      if (frame <= mid) {
        widget.onLoopChanged!(_clampFrame(frame, 0, end - 1), end);
      } else {
        widget.onLoopChanged!(start, _clampFrame(frame, start + 1, maxFrame));
      }
      return;
    }
    final mid = (_start + _end) / 2;
    if (frame <= mid) {
      widget.onChanged(_clampFrame(frame, 0, _end - 1), _end);
    } else {
      widget.onChanged(_start, _clampFrame(frame, _start + 1, maxFrame));
    }
  }

  int _clampFrame(num value, int lowerBound, int upperBound) {
    final maxFrame = math.max(0, widget.overview.frameCount - 1);
    final lower = lowerBound.clamp(0, maxFrame).toInt();
    final upper = upperBound.clamp(0, maxFrame).toInt();
    if (upper < lower) return lower;
    return value.clamp(lower, upper).toInt();
  }

  double _frameToX(int frame, double width) {
    return (frame / math.max(1, widget.overview.frameCount)) * width;
  }

  void _nudgeStart(int delta) {
    final end = _end;
    final raw = (_start + delta).clamp(0, math.max(0, end - 1)).toInt();
    final snapped = widget.overview.nearestZeroCrossing(raw);
    widget.onChanged(snapped.clamp(0, math.max(0, end - 1)).toInt(), end);
  }

  void _nudgeEnd(int delta) {
    final start = _start;
    final maxFrame = math.max(0, widget.overview.frameCount - 1);
    final raw = (_end + delta).clamp(math.min(maxFrame, start + 1), maxFrame);
    final snapped = widget.overview.nearestZeroCrossing(raw.toInt());
    widget.onChanged(
      start,
      snapped.clamp(math.min(maxFrame, start + 1), maxFrame).toInt(),
    );
  }

  void _nudgeLoopStart(int delta) {
    final loopEnd = _loopEnd;
    final loopStart = _loopStart;
    if (loopStart == null || loopEnd == null || widget.onLoopChanged == null) {
      return;
    }
    final raw = (loopStart + delta).clamp(0, math.max(0, loopEnd - 1)).toInt();
    final snapped = widget.overview.nearestZeroCrossing(raw);
    widget.onLoopChanged!(
      snapped.clamp(0, math.max(0, loopEnd - 1)).toInt(),
      loopEnd,
    );
  }

  void _nudgeLoopEnd(int delta) {
    final loopStart = _loopStart;
    final loopEnd = _loopEnd;
    if (loopStart == null || loopEnd == null || widget.onLoopChanged == null) {
      return;
    }
    final maxFrame = math.max(0, widget.overview.frameCount - 1);
    final raw = (loopEnd + delta).clamp(
      math.min(maxFrame, loopStart + 1),
      maxFrame,
    );
    final snapped = widget.overview.nearestZeroCrossing(raw.toInt());
    widget.onLoopChanged!(
      loopStart,
      snapped.clamp(math.min(maxFrame, loopStart + 1), maxFrame).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loopStart = _loopStart;
    final loopEnd = _loopEnd;
    final playbackFrame = widget.playback?.frameAt(DateTime.now());
    final semanticsValue = [
      'Start $_start frames',
      'end $_end frames',
      if (loopStart != null && loopEnd != null) ...[
        'loop start $loopStart frames',
        'loop end $loopEnd frames',
      ],
      if (playbackFrame != null) 'playback head $playbackFrame frames',
    ].join(', ');
    final customActions = <CustomSemanticsAction, VoidCallback>{
      const CustomSemanticsAction(label: 'Move start earlier'): () =>
          _nudgeStart(-100),
      const CustomSemanticsAction(label: 'Move start later'): () =>
          _nudgeStart(100),
      const CustomSemanticsAction(label: 'Move end earlier'): () =>
          _nudgeEnd(-100),
      const CustomSemanticsAction(label: 'Move end later'): () =>
          _nudgeEnd(100),
      if (loopStart != null && loopEnd != null) ...{
        const CustomSemanticsAction(label: 'Move loop start earlier'): () =>
            _nudgeLoopStart(-100),
        const CustomSemanticsAction(label: 'Move loop start later'): () =>
            _nudgeLoopStart(100),
        const CustomSemanticsAction(label: 'Move loop end earlier'): () =>
            _nudgeLoopEnd(-100),
        const CustomSemanticsAction(label: 'Move loop end later'): () =>
            _nudgeLoopEnd(100),
      },
    };
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            _MoveStartEarlierIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight): _MoveStartLaterIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            _MoveEndEarlierIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            _MoveEndLaterIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            _MoveLoopStartEarlierIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            _MoveLoopStartLaterIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true, shift: true):
            _MoveLoopEndEarlierIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, alt: true, shift: true):
            _MoveLoopEndLaterIntent(),
      },
      actions: {
        _MoveStartEarlierIntent: CallbackAction<_MoveStartEarlierIntent>(
          onInvoke: (_) {
            _nudgeStart(-100);
            return null;
          },
        ),
        _MoveStartLaterIntent: CallbackAction<_MoveStartLaterIntent>(
          onInvoke: (_) {
            _nudgeStart(100);
            return null;
          },
        ),
        _MoveEndEarlierIntent: CallbackAction<_MoveEndEarlierIntent>(
          onInvoke: (_) {
            _nudgeEnd(-100);
            return null;
          },
        ),
        _MoveEndLaterIntent: CallbackAction<_MoveEndLaterIntent>(
          onInvoke: (_) {
            _nudgeEnd(100);
            return null;
          },
        ),
        _MoveLoopStartEarlierIntent:
            CallbackAction<_MoveLoopStartEarlierIntent>(
              onInvoke: (_) {
                _nudgeLoopStart(-100);
                return null;
              },
            ),
        _MoveLoopStartLaterIntent: CallbackAction<_MoveLoopStartLaterIntent>(
          onInvoke: (_) {
            _nudgeLoopStart(100);
            return null;
          },
        ),
        _MoveLoopEndEarlierIntent: CallbackAction<_MoveLoopEndEarlierIntent>(
          onInvoke: (_) {
            _nudgeLoopEnd(-100);
            return null;
          },
        ),
        _MoveLoopEndLaterIntent: CallbackAction<_MoveLoopEndLaterIntent>(
          onInvoke: (_) {
            _nudgeLoopEnd(100);
            return null;
          },
        ),
      },
      onShowFocusHighlight: (value) {
        setState(() {
          _showFocusHighlight = value;
        });
      },
      child: Semantics(
        label: 'Waveform editor',
        value: semanticsValue,
        increasedValue:
            'End ${(_end + 100).clamp(0, math.max(0, widget.overview.frameCount - 1)).toInt()} frames',
        decreasedValue: 'Start ${(_start - 100).clamp(0, _end).toInt()} frames',
        onIncrease: () => _nudgeEnd(100),
        onDecrease: () => _nudgeStart(-100),
        customSemanticsActions: customActions,
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: Listener(
                  onPointerDown: (event) {
                    if (event.buttons & kSecondaryButton == 0) return;
                    Focus.of(context).requestFocus();
                    _beginDrag(event.localPosition, width, loopGesture: true);
                    _secondaryDragActive = _activeHandle != null;
                  },
                  onPointerMove: (event) {
                    if (!_secondaryDragActive ||
                        event.buttons & kSecondaryButton == 0) {
                      return;
                    }
                    _updateDrag(event.localPosition, width);
                  },
                  onPointerUp: (_) {
                    _secondaryDragActive = false;
                    _activeHandle = null;
                  },
                  onPointerCancel: (_) {
                    _secondaryDragActive = false;
                    _activeHandle = null;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => Focus.of(context).requestFocus(),
                    onTapUp: (details) =>
                        _setPoint(details.localPosition, width),
                    onSecondaryTapUp: (details) => _setPoint(
                      details.localPosition,
                      width,
                      forceLoopGesture: true,
                    ),
                    onHorizontalDragStart: (details) {
                      Focus.of(context).requestFocus();
                      _beginDrag(
                        details.localPosition,
                        width,
                        loopGesture: _loopModifierPressed,
                      );
                    },
                    onHorizontalDragUpdate: (details) {
                      _updateDrag(details.localPosition, width);
                    },
                    child: DecoratedBox(
                      key: const ValueKey('poly-waveform-focus-outline'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _showFocusHighlight
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: AnimatedBuilder(
                        animation: _playheadTicker,
                        builder: (context, child) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              CustomPaint(
                                painter: _PolyWaveformPainter(
                                  overview: widget.overview,
                                  mode: widget.mode,
                                  startFrame: _start,
                                  endFrame: _end,
                                  loopStartFrame: _loopStart,
                                  loopEndFrame: _loopEnd,
                                  playbackHeadFrame: widget.playback?.frameAt(
                                    DateTime.now(),
                                  ),
                                  colorScheme: colorScheme,
                                ),
                                child: child,
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    key: const ValueKey(
                                      'poly-waveform-fade-overlay',
                                    ),
                                    painter: _PolyWaveformFadePainter(
                                      overview: widget.overview,
                                      startFrame: _start,
                                      endFrame: _end,
                                      fadeInFrames: widget.fadeInFrames,
                                      fadeOutFrames: widget.fadeOutFrames,
                                      fadeInCurve: widget.fadeInCurve,
                                      fadeOutCurve: widget.fadeOutCurve,
                                      fadeInStrength: widget.fadeInStrength,
                                      fadeOutStrength: widget.fadeOutStrength,
                                      colorScheme: colorScheme,
                                      markerColor:
                                          context.appColors.warning.color,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PolyWaveformFadePainter extends CustomPainter {
  const _PolyWaveformFadePainter({
    required this.overview,
    required this.startFrame,
    required this.endFrame,
    required this.fadeInFrames,
    required this.fadeOutFrames,
    required this.fadeInCurve,
    required this.fadeOutCurve,
    required this.fadeInStrength,
    required this.fadeOutStrength,
    required this.colorScheme,
    required this.markerColor,
  });

  final WavOverview overview;
  final int startFrame;
  final int endFrame;
  final int fadeInFrames;
  final int fadeOutFrames;
  final WavFadeCurve fadeInCurve;
  final WavFadeCurve fadeOutCurve;
  final double fadeInStrength;
  final double fadeOutStrength;
  final ColorScheme colorScheme;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxFrame = math.max(1, overview.frameCount);
    final startX = (startFrame / maxFrame) * size.width;
    final endX = (endFrame / maxFrame) * size.width;
    final selectedRect = Rect.fromLTRB(startX, 0, endX, size.height);
    if (selectedRect.width <= 0) return;

    if (fadeInFrames > 0) {
      _paintFade(
        canvas,
        selectedRect,
        frames: fadeInFrames,
        curve: fadeInCurve,
        strength: fadeInStrength,
        fillColor: colorScheme.secondary.withValues(alpha: 0.18),
        strokeColor: colorScheme.secondary.withValues(alpha: 0.9),
        fromStart: true,
      );
    }
    if (fadeOutFrames > 0) {
      _paintFade(
        canvas,
        selectedRect,
        frames: fadeOutFrames,
        curve: fadeOutCurve,
        strength: fadeOutStrength,
        fillColor: colorScheme.tertiary.withValues(alpha: 0.18),
        strokeColor: colorScheme.tertiary.withValues(alpha: 0.9),
        fromStart: false,
      );
    }

    final fadeLinePaint = Paint()
      ..color = markerColor.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    if (fadeInFrames > 0 && startX > 0) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX, size.height),
        fadeLinePaint,
      );
    }
    if (fadeOutFrames > 0 && endX > 0 && endX < size.width) {
      canvas.drawLine(
        Offset(endX, 0),
        Offset(endX, size.height),
        fadeLinePaint,
      );
    }
  }

  void _paintFade(
    Canvas canvas,
    Rect selectedRect, {
    required int frames,
    required WavFadeCurve curve,
    required double strength,
    required Color fillColor,
    required Color strokeColor,
    required bool fromStart,
  }) {
    final width = selectedRect.width;
    if (width <= 0) return;
    final fadeWidth = math.min(
      width,
      (frames / math.max(1, overview.frameCount)) * width,
    );
    if (fadeWidth <= 0) return;
    final fadeRect = fromStart
        ? Rect.fromLTWH(
            selectedRect.left,
            selectedRect.top,
            fadeWidth,
            selectedRect.height,
          )
        : Rect.fromLTWH(
            selectedRect.right - fadeWidth,
            selectedRect.top,
            fadeWidth,
            selectedRect.height,
          );
    final steps = math.max(8, fadeWidth.round());
    final path = Path()..moveTo(fadeRect.left, fadeRect.bottom);
    for (var index = 0; index <= steps; index++) {
      final t = index / steps;
      final x = fromStart
          ? fadeRect.left + fadeRect.width * t
          : fadeRect.right - fadeRect.width * t;
      final envelope = fromStart
          ? WavFadeShaper.apply(t, curve, strength: strength)
          : 1 - WavFadeShaper.apply(1 - t, curve, strength: strength);
      final y = fadeRect.bottom - envelope * fadeRect.height;
      path.lineTo(x, y);
    }
    path
      ..lineTo(fadeRect.right, fadeRect.bottom)
      ..close();

    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(path, fillPaint);

    final strokePath = Path();
    for (var index = 0; index <= steps; index++) {
      final t = index / steps;
      final x = fromStart
          ? fadeRect.left + fadeRect.width * t
          : fadeRect.right - fadeRect.width * t;
      final envelope = fromStart
          ? WavFadeShaper.apply(t, curve, strength: strength)
          : 1 - WavFadeShaper.apply(1 - t, curve, strength: strength);
      final y = fadeRect.bottom - envelope * fadeRect.height;
      if (index == 0) {
        strokePath.moveTo(x, y);
      } else {
        strokePath.lineTo(x, y);
      }
    }
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(strokePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _PolyWaveformFadePainter oldDelegate) {
    return oldDelegate.overview != overview ||
        oldDelegate.startFrame != startFrame ||
        oldDelegate.endFrame != endFrame ||
        oldDelegate.fadeInFrames != fadeInFrames ||
        oldDelegate.fadeOutFrames != fadeOutFrames ||
        oldDelegate.fadeInCurve != fadeInCurve ||
        oldDelegate.fadeOutCurve != fadeOutCurve ||
        oldDelegate.fadeInStrength != fadeInStrength ||
        oldDelegate.fadeOutStrength != fadeOutStrength ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _MoveStartEarlierIntent extends Intent {
  const _MoveStartEarlierIntent();
}

class _MoveStartLaterIntent extends Intent {
  const _MoveStartLaterIntent();
}

class _MoveEndEarlierIntent extends Intent {
  const _MoveEndEarlierIntent();
}

class _MoveEndLaterIntent extends Intent {
  const _MoveEndLaterIntent();
}

class _MoveLoopStartEarlierIntent extends Intent {
  const _MoveLoopStartEarlierIntent();
}

class _MoveLoopStartLaterIntent extends Intent {
  const _MoveLoopStartLaterIntent();
}

class _MoveLoopEndEarlierIntent extends Intent {
  const _MoveLoopEndEarlierIntent();
}

class _MoveLoopEndLaterIntent extends Intent {
  const _MoveLoopEndLaterIntent();
}

enum _WaveformHandle { start, end, loopStart, loopEnd }

class _PolyWaveformPainter extends CustomPainter {
  const _PolyWaveformPainter({
    required this.overview,
    required this.mode,
    required this.startFrame,
    required this.endFrame,
    required this.loopStartFrame,
    required this.loopEndFrame,
    required this.playbackHeadFrame,
    required this.colorScheme,
  });

  final WavOverview overview;
  final PolyWaveformEditorMode mode;
  final int startFrame;
  final int endFrame;
  final int? loopStartFrame;
  final int? loopEndFrame;
  final int? playbackHeadFrame;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final maxFrame = math.max(1, overview.frameCount);
    final startX = (startFrame / maxFrame) * size.width;
    final endX = (endFrame / maxFrame) * size.width;
    final selectedRect = Rect.fromLTRB(startX, 0, endX, size.height);
    switch (mode) {
      case PolyWaveformEditorMode.loop:
        canvas.drawRect(
          selectedRect,
          Paint()..color = colorScheme.tertiary.withValues(alpha: 0.25),
        );
      case PolyWaveformEditorMode.trim:
        final shade = Paint()
          ..color = colorScheme.onSurface.withValues(alpha: 0.25);
        canvas.drawRect(Rect.fromLTRB(0, 0, startX, size.height), shade);
        canvas.drawRect(Rect.fromLTRB(endX, 0, size.width, size.height), shade);
    }
    final loopStart = loopStartFrame;
    final loopEnd = loopEndFrame;
    if (loopStart != null && loopEnd != null) {
      final loopStartX = (loopStart / maxFrame) * size.width;
      final loopEndX = (loopEnd / maxFrame) * size.width;
      canvas.drawRect(
        Rect.fromLTRB(loopStartX, 0, loopEndX, size.height),
        Paint()..color = colorScheme.tertiary.withValues(alpha: 0.18),
      );
      final loopPaint = Paint()
        ..color = colorScheme.tertiary
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(loopStartX, 0),
        Offset(loopStartX, size.height),
        loopPaint,
      );
      canvas.drawLine(
        Offset(loopEndX, 0),
        Offset(loopEndX, size.height),
        loopPaint,
      );
    }

    final waveformPaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 1;
    final centerY = size.height / 2;
    final halfHeight = size.height / 2;
    for (var i = 0; i < overview.peaks.length; i++) {
      final peak = overview.peaks[i];
      final x = overview.peaks.length <= 1
          ? 0.0
          : (i / (overview.peaks.length - 1)) * size.width;
      final y0 = centerY - peak.max.clamp(-1.0, 1.0) * halfHeight;
      final y1 = centerY - peak.min.clamp(-1.0, 1.0) * halfHeight;
      canvas.drawLine(Offset(x, y0), Offset(x, y1), waveformPaint);
    }

    final handlePaint = Paint()
      ..color = colorScheme.tertiary
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(startX, 0),
      Offset(startX, size.height),
      handlePaint,
    );
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), handlePaint);

    final playbackHead = playbackHeadFrame;
    if (playbackHead != null) {
      final playbackX =
          (playbackHead.clamp(0, overview.frameCount) / maxFrame) * size.width;
      final playbackPaint = Paint()
        ..color = colorScheme.secondary
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(playbackX, 0),
        Offset(playbackX, size.height),
        playbackPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PolyWaveformPainter oldDelegate) {
    return oldDelegate.overview != overview ||
        oldDelegate.mode != mode ||
        oldDelegate.startFrame != startFrame ||
        oldDelegate.endFrame != endFrame ||
        oldDelegate.loopStartFrame != loopStartFrame ||
        oldDelegate.loopEndFrame != loopEndFrame ||
        oldDelegate.playbackHeadFrame != playbackHeadFrame ||
        oldDelegate.colorScheme != colorScheme;
  }
}
