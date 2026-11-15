import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:nt_helper/services/desktop_feedback_service.dart';
import 'package:nt_helper/services/settings_service.dart';

/// Interface for haptic feedback functionality across different platforms.
abstract class IHapticFeedbackService {
  /// Light impact feedback for subtle interactions (e.g., hovering over valid targets)
  Future<void> lightImpact([BuildContext? context]);

  /// Medium impact feedback for standard interactions (e.g., successful connections)
  Future<void> mediumImpact([BuildContext? context]);

  /// Heavy impact feedback for significant interactions (e.g., important actions)
  Future<void> heavyImpact([BuildContext? context]);

  /// Error feedback for invalid actions or failures
  Future<void> errorFeedback([BuildContext? context]);

  /// Check if haptic feedback is available on the current platform
  bool get isHapticsSupported;

  /// Check if the service is currently enabled
  bool get isEnabled;

  /// Enable or disable haptic feedback
  void setEnabled(bool enabled);
}

/// Platform-aware haptic feedback service that provides appropriate feedback
/// mechanisms for different platforms.
///
/// On mobile platforms (iOS/Android), uses native haptic feedback APIs.
/// On desktop platforms (Windows/macOS/Linux), provides fallback mechanisms
/// or no-op implementations that can be extended with visual/audio feedback.
///
/// Usage:
/// ```dart
/// final haptics = HapticFeedbackService();
/// await haptics.lightImpact(); // Provides appropriate feedback for platform
/// ```
class HapticFeedbackService implements IHapticFeedbackService {
  static HapticFeedbackService? _instance;
  late final DesktopFeedbackService _desktopFeedback;
  late final SettingsService _settings;

  /// Private constructor for singleton pattern
  HapticFeedbackService._internal() {
    _desktopFeedback = DesktopFeedbackService();
    _settings = SettingsService();
  }

  /// Factory constructor that returns singleton instance
  factory HapticFeedbackService() {
    _instance ??= HapticFeedbackService._internal();
    return _instance!;
  }

  /// Whether haptic feedback is supported on the current platform
  @override
  bool get isHapticsSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  /// Whether haptic feedback is currently enabled
  @override
  bool get isEnabled => _settings.hapticsEnabled;

  /// Enable or disable haptic feedback
  @override
  void setEnabled(bool enabled) {
    _settings.setHapticsEnabled(enabled);
  }

  /// Light impact feedback for subtle interactions
  ///
  /// Used for:
  /// - Hovering over valid connection targets
  /// - Port selection highlighting
  /// - Minor UI interactions
  @override
  Future<void> lightImpact([BuildContext? context]) async {
    if (!isEnabled) return;

    try {
      if (isHapticsSupported && (Platform.isIOS || Platform.isAndroid)) {
        await Haptics.vibrate(HapticsType.light);
      } else if (_desktopFeedback.isDesktopPlatform) {
        // Use desktop fallback feedback
        await _desktopFeedback.lightFeedback(context);
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Medium impact feedback for standard interactions
  ///
  /// Used for:
  /// - Successfully creating connections
  /// - Port tap interactions
  /// - Standard UI confirmations
  @override
  Future<void> mediumImpact([BuildContext? context]) async {
    if (!isEnabled) return;

    try {
      if (isHapticsSupported && (Platform.isIOS || Platform.isAndroid)) {
        await Haptics.vibrate(HapticsType.medium);
      } else if (_desktopFeedback.isDesktopPlatform) {
        // Use desktop fallback feedback
        await _desktopFeedback.mediumFeedback(context);
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Heavy impact feedback for significant interactions
  ///
  /// Used for:
  /// - Important actions or confirmations
  /// - Major state changes
  /// - Drag operations start/end
  @override
  Future<void> heavyImpact([BuildContext? context]) async {
    if (!isEnabled) return;

    try {
      if (isHapticsSupported && (Platform.isIOS || Platform.isAndroid)) {
        await Haptics.vibrate(HapticsType.heavy);
      } else if (_desktopFeedback.isDesktopPlatform) {
        // Use desktop fallback feedback
        await _desktopFeedback.heavyFeedback(context);
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Error feedback for invalid actions or failures
  ///
  /// Used for:
  /// - Invalid connection attempts
  /// - Constraint violations
  /// - Error conditions
  @override
  Future<void> errorFeedback([BuildContext? context]) async {
    if (!isEnabled) return;

    try {
      if (isHapticsSupported && (Platform.isIOS || Platform.isAndroid)) {
        // Use error vibration pattern for feedback
        await Haptics.vibrate(HapticsType.error);
      } else if (_desktopFeedback.isDesktopPlatform) {
        // Use desktop fallback feedback
        await _desktopFeedback.errorFeedback(context);
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  /// Convenience method for selection click feedback (backward compatibility)
  /// Uses medium impact for general selection interactions
  Future<void> selectionClick([BuildContext? context]) async {
    await mediumImpact(context);
  }

  /// Access to desktop feedback service for advanced configuration
  DesktopFeedbackService get desktopFeedback => _desktopFeedback;

  /// Enable or disable visual feedback for desktop platforms
  void setVisualFeedbackEnabled(bool enabled) {
    _desktopFeedback.setVisualFeedbackEnabled(enabled);
  }

  /// Enable or disable audio feedback for desktop platforms
  void setAudioFeedbackEnabled(bool enabled) {
    _desktopFeedback.setAudioFeedbackEnabled(enabled);
  }

  /// Get platform information for debugging
  Map<String, dynamic> getPlatformInfo() {
    return {
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'isHapticsSupported': isHapticsSupported,
      'isEnabled': isEnabled,
      'hasInstance': _instance != null,
      'desktopFeedback': _desktopFeedback.getConfigInfo(),
    };
  }
}

/// Extension for easy access to haptic feedback service
extension HapticFeedbackExtension on BuildContext {
  /// Get the haptic feedback service instance
  HapticFeedbackService get haptics => HapticFeedbackService();
}
