import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

/// Desktop-specific feedback service that provides visual and audio alternatives
/// to haptic feedback for platforms where physical feedback is not available.
///
/// This service provides:
/// - Visual feedback through brief color changes, highlights, and animations
/// - Audio feedback through system sounds and simple tones
/// - Configuration options to enable/disable each feedback type
///
/// Usage:
/// ```dart
/// final desktop = DesktopFeedbackService();
/// await desktop.lightVisualFeedback(context); // Brief highlight
/// await desktop.mediumAudioFeedback(); // System sound
/// ```
class DesktopFeedbackService {
  static DesktopFeedbackService? _instance;

  bool _visualFeedbackEnabled = true;
  bool _audioFeedbackEnabled = true;

  /// Private constructor for singleton pattern
  DesktopFeedbackService._internal();

  /// Factory constructor that returns singleton instance
  factory DesktopFeedbackService() {
    _instance ??= DesktopFeedbackService._internal();
    return _instance!;
  }

  /// Whether the current platform supports desktop feedback
  bool get isDesktopPlatform {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Whether visual feedback is currently enabled
  bool get isVisualFeedbackEnabled => _visualFeedbackEnabled;

  /// Whether audio feedback is currently enabled
  bool get isAudioFeedbackEnabled => _audioFeedbackEnabled;

  /// Enable or disable visual feedback
  void setVisualFeedbackEnabled(bool enabled) {
    _visualFeedbackEnabled = enabled;
  }

  /// Enable or disable audio feedback
  void setAudioFeedbackEnabled(bool enabled) {
    _audioFeedbackEnabled = enabled;
  }

  /// Light visual feedback - subtle highlight or glow effect
  /// Used for hover states and minor interactions
  Future<void> lightVisualFeedback(
    BuildContext? context, {
    Widget? target,
  }) async {
    if (!_visualFeedbackEnabled || !isDesktopPlatform || context == null) {
      return;
    }

    try {
      // Create a brief overlay effect
      _showFeedbackOverlay(
        context,
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        const Duration(milliseconds: 100),
        target: target,
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Medium visual feedback - noticeable color change or pulse
  /// Used for successful actions and confirmations
  Future<void> mediumVisualFeedback(
    BuildContext? context, {
    Widget? target,
  }) async {
    if (!_visualFeedbackEnabled || !isDesktopPlatform || context == null) {
      return;
    }

    try {
      // Create a more prominent pulse effect
      _showFeedbackOverlay(
        context,
        context.appColors.success.color.withValues(alpha: 0.2),
        const Duration(milliseconds: 200),
        target: target,
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Heavy visual feedback - strong visual indication
  /// Used for important actions and major state changes
  Future<void> heavyVisualFeedback(
    BuildContext? context, {
    Widget? target,
  }) async {
    if (!_visualFeedbackEnabled || !isDesktopPlatform || context == null) {
      return;
    }

    try {
      // Create a strong pulsing effect
      _showFeedbackOverlay(
        context,
        context.appColors.warning.color.withValues(alpha: 0.3),
        const Duration(milliseconds: 300),
        target: target,
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Error visual feedback - red flash or shake effect
  /// Used for invalid actions and error conditions
  Future<void> errorVisualFeedback(
    BuildContext? context, {
    Widget? target,
  }) async {
    if (!_visualFeedbackEnabled || !isDesktopPlatform || context == null) {
      return;
    }

    try {
      // Create a brief red flash effect
      _showFeedbackOverlay(
        context,
        Theme.of(context).colorScheme.error.withValues(alpha: 0.25),
        const Duration(milliseconds: 150),
        target: target,
      );
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Light audio feedback - subtle system sound
  /// Used for hover states and minor interactions
  Future<void> lightAudioFeedback() async {
    if (!_audioFeedbackEnabled || !isDesktopPlatform) return;

    try {
      // Use system click sound for light feedback
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Medium audio feedback - standard system sound
  /// Used for successful actions and confirmations
  Future<void> mediumAudioFeedback() async {
    if (!_audioFeedbackEnabled || !isDesktopPlatform) return;

    try {
      // Use system alert sound for medium feedback
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Heavy audio feedback - prominent system sound
  /// Used for important actions and major state changes
  Future<void> heavyAudioFeedback() async {
    if (!_audioFeedbackEnabled || !isDesktopPlatform) return;

    try {
      // Use system alert sound for heavy feedback (could be enhanced with custom sounds)
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Error audio feedback - error system sound
  /// Used for invalid actions and error conditions
  Future<void> errorAudioFeedback() async {
    if (!_audioFeedbackEnabled || !isDesktopPlatform) return;

    try {
      // Use system alert sound for error feedback
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Combined visual and audio feedback methods

  /// Combined light feedback (visual + audio)
  Future<void> lightFeedback(BuildContext? context, {Widget? target}) async {
    await Future.wait([
      lightVisualFeedback(context, target: target),
      lightAudioFeedback(),
    ]);
  }

  /// Combined medium feedback (visual + audio)
  Future<void> mediumFeedback(BuildContext? context, {Widget? target}) async {
    await Future.wait([
      mediumVisualFeedback(context, target: target),
      mediumAudioFeedback(),
    ]);
  }

  /// Combined heavy feedback (visual + audio)
  Future<void> heavyFeedback(BuildContext? context, {Widget? target}) async {
    await Future.wait([
      heavyVisualFeedback(context, target: target),
      heavyAudioFeedback(),
    ]);
  }

  /// Combined error feedback (visual + audio)
  Future<void> errorFeedback(BuildContext? context, {Widget? target}) async {
    await Future.wait([
      errorVisualFeedback(context, target: target),
      errorAudioFeedback(),
    ]);
  }

  /// Private method to show visual feedback overlay
  void _showFeedbackOverlay(
    BuildContext context,
    Color color,
    Duration duration, {
    Widget? target,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => AnimatedContainer(
        duration: duration,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: target,
      ),
    );

    overlay.insert(entry);

    // Remove the overlay after the duration
    Timer(duration, () {
      entry.remove();
    });
  }

  /// Get configuration information for debugging
  Map<String, dynamic> getConfigInfo() {
    return {
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'isDesktopPlatform': isDesktopPlatform,
      'visualFeedbackEnabled': isVisualFeedbackEnabled,
      'audioFeedbackEnabled': isAudioFeedbackEnabled,
      'hasInstance': _instance != null,
    };
  }
}

/// Extension for easy access to desktop feedback service
extension DesktopFeedbackExtension on BuildContext {
  /// Get the desktop feedback service instance
  DesktopFeedbackService get desktopFeedback => DesktopFeedbackService();
}
