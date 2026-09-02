import 'package:flutter/material.dart';

/// Central construction point for every nt_helper Material theme.
abstract final class AppTheme {
  /// The original light-theme teal, now used as the single Material 3 seed for
  /// light, dark, and high-contrast themes.
  static const Color defaultSeedColor = Color(0xFF00BFA5);

  static ThemeData build({
    required Color seedColor,
    required Brightness brightness,
    double contrastLevel = 0,
  }) {
    final opaqueSeed = Color(0xFF000000 | (seedColor.toARGB32() & 0x00FFFFFF));
    final colorScheme = ColorScheme.fromSeed(
      seedColor: opaqueSeed,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      brightness: brightness,
      contrastLevel: contrastLevel,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[
        AppThemeColors.fromColorScheme(
          colorScheme,
          contrastLevel: contrastLevel,
        ),
      ],
      appBarTheme: AppBarTheme(
        elevation: 4,
        shadowColor: colorScheme.shadow,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      tabBarTheme: TabBarThemeData(
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.secondary, width: 2),
        ),
        labelColor: colorScheme.secondary,
        unselectedLabelColor: colorScheme.secondary.withAlpha(170),
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
      ),
    );
  }
}

/// A foreground/background pair for categorical and domain colours.
@immutable
class AppColorPair {
  const AppColorPair({required this.color, required this.onColor});

  final Color color;
  final Color onColor;

  static AppColorPair lerp(AppColorPair a, AppColorPair b, double t) {
    return AppColorPair(
      color: Color.lerp(a.color, b.color, t)!,
      onColor: Color.lerp(a.onColor, b.onColor, t)!,
    );
  }
}

/// A complete semantic colour role, including its container variant.
@immutable
class AppColorRole extends AppColorPair {
  const AppColorRole({
    required super.color,
    required super.onColor,
    required this.container,
    required this.onContainer,
  });

  final Color container;
  final Color onContainer;

  static AppColorRole lerp(AppColorRole a, AppColorRole b, double t) {
    return AppColorRole(
      color: Color.lerp(a.color, b.color, t)!,
      onColor: Color.lerp(a.onColor, b.onColor, t)!,
      container: Color.lerp(a.container, b.container, t)!,
      onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
    );
  }
}

/// Theme-managed colours that have meaning beyond Material's standard roles.
///
/// Semantic hues remain recognisable while their tones and foregrounds adapt
/// to light, dark, and high-contrast themes. Indexed palettes preserve the
/// existing performance-page and step-sequencer visual identities without
/// scattering literals throughout widgets and painters.
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.categorical,
    required this.sequencer,
    required this.audioPort,
    required this.cvPort,
    required this.gatePort,
    required this.clockPort,
    required this.unknownPort,
    required this.backwardConnection,
    required this.emptyBus,
  });

  final AppColorRole success;
  final AppColorRole warning;
  final AppColorRole info;
  final List<AppColorPair> categorical;
  final List<AppColorPair> sequencer;
  final AppColorPair audioPort;
  final AppColorPair cvPort;
  final AppColorPair gatePort;
  final AppColorPair clockPort;
  final AppColorPair unknownPort;
  final Color backwardConnection;
  final Color emptyBus;

  /// Fixed high-contrast colours used to simulate the disting NT display.
  static const Color ntDisplaySurface = Color(0xFF101010);
  static const Color ntDisplayForeground = Color(0xFFF5F5F5);

  static const Color _successSeed = Color(0xFF2E7D32);
  static const Color _warningSeed = Color(0xFFEF6C00);
  static const Color _infoSeed = Color(0xFF1565C0);

  static const List<Color> _categoricalSeeds = <Color>[
    Color(0xFF2196F3),
    Color(0xFF4CAF50),
    Color(0xFFFF9800),
    Color(0xFF9C27B0),
    Color(0xFFF44336),
  ];

  static const List<Color> _sequencerSeeds = <Color>[
    Color(0xFF14B8A6), // Pitch
    Color(0xFF10B981), // Velocity
    Color(0xFF8B5CF6), // Mod
    Color(0xFFF97316), // Division
    Color(0xFF3B82F6), // Pattern
    Color(0xFFEAB308), // Ties
    Color(0xFFEF4444), // Mute
    Color(0xFFEC4899), // Skip
    Color(0xFFF59E0B), // Reset
    Color(0xFF06B6D4), // Repeat
  ];

  factory AppThemeColors.fromColorScheme(
    ColorScheme colorScheme, {
    double contrastLevel = 0,
  }) {
    final brightness = colorScheme.brightness;
    final success = _roleFor(
      _successSeed,
      brightness,
      contrastLevel: contrastLevel,
    );
    final warning = _roleFor(
      _warningSeed,
      brightness,
      contrastLevel: contrastLevel,
    );
    final info = _roleFor(_infoSeed, brightness, contrastLevel: contrastLevel);
    final categorical = _categoricalSeeds
        .map((seed) => _pairFor(seed, brightness, contrastLevel: contrastLevel))
        .toList(growable: false);
    final sequencer = _sequencerSeeds
        .map((seed) => _pairFor(seed, brightness, contrastLevel: contrastLevel))
        .toList(growable: false);

    return AppThemeColors(
      success: success,
      warning: warning,
      info: info,
      categorical: categorical,
      sequencer: sequencer,
      audioPort: categorical[0],
      cvPort: categorical[2],
      gatePort: success,
      clockPort: categorical[3],
      unknownPort: AppColorPair(
        color: colorScheme.outline,
        onColor: colorScheme.surface,
      ),
      backwardConnection: warning.color,
      emptyBus: colorScheme.outlineVariant,
    );
  }

  static AppColorRole _roleFor(
    Color seed,
    Brightness brightness, {
    required double contrastLevel,
  }) {
    final scheme = _schemeFor(seed, brightness, contrastLevel: contrastLevel);
    return AppColorRole(
      color: scheme.primary,
      onColor: scheme.onPrimary,
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
    );
  }

  static AppColorPair _pairFor(
    Color seed,
    Brightness brightness, {
    required double contrastLevel,
  }) {
    final scheme = _schemeFor(seed, brightness, contrastLevel: contrastLevel);
    return AppColorPair(color: scheme.primary, onColor: scheme.onPrimary);
  }

  static ColorScheme _schemeFor(
    Color seed,
    Brightness brightness, {
    required double contrastLevel,
  }) {
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      contrastLevel: contrastLevel,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
  }

  AppColorPair categoricalAt(int index) {
    return categorical[index % categorical.length];
  }

  Color categoricalOnColor(Color color) {
    for (final pair in categorical) {
      if (pair.color.toARGB32() == color.toARGB32()) return pair.onColor;
    }
    return unknownPort.onColor;
  }

  AppColorPair sequencerAt(int index) {
    return sequencer[index % sequencer.length];
  }

  @override
  AppThemeColors copyWith({
    AppColorRole? success,
    AppColorRole? warning,
    AppColorRole? info,
    List<AppColorPair>? categorical,
    List<AppColorPair>? sequencer,
    AppColorPair? audioPort,
    AppColorPair? cvPort,
    AppColorPair? gatePort,
    AppColorPair? clockPort,
    AppColorPair? unknownPort,
    Color? backwardConnection,
    Color? emptyBus,
  }) {
    return AppThemeColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      categorical: categorical ?? this.categorical,
      sequencer: sequencer ?? this.sequencer,
      audioPort: audioPort ?? this.audioPort,
      cvPort: cvPort ?? this.cvPort,
      gatePort: gatePort ?? this.gatePort,
      clockPort: clockPort ?? this.clockPort,
      unknownPort: unknownPort ?? this.unknownPort,
      backwardConnection: backwardConnection ?? this.backwardConnection,
      emptyBus: emptyBus ?? this.emptyBus,
    );
  }

  @override
  AppThemeColors lerp(covariant AppThemeColors? other, double t) {
    if (other == null) return this;
    return AppThemeColors(
      success: AppColorRole.lerp(success, other.success, t),
      warning: AppColorRole.lerp(warning, other.warning, t),
      info: AppColorRole.lerp(info, other.info, t),
      categorical: _lerpPairs(categorical, other.categorical, t),
      sequencer: _lerpPairs(sequencer, other.sequencer, t),
      audioPort: AppColorPair.lerp(audioPort, other.audioPort, t),
      cvPort: AppColorPair.lerp(cvPort, other.cvPort, t),
      gatePort: AppColorPair.lerp(gatePort, other.gatePort, t),
      clockPort: AppColorPair.lerp(clockPort, other.clockPort, t),
      unknownPort: AppColorPair.lerp(unknownPort, other.unknownPort, t),
      backwardConnection: Color.lerp(
        backwardConnection,
        other.backwardConnection,
        t,
      )!,
      emptyBus: Color.lerp(emptyBus, other.emptyBus, t)!,
    );
  }

  static List<AppColorPair> _lerpPairs(
    List<AppColorPair> a,
    List<AppColorPair> b,
    double t,
  ) {
    assert(a.length == b.length);
    return List<AppColorPair>.generate(
      a.length,
      (index) => AppColorPair.lerp(a[index], b[index], t),
      growable: false,
    );
  }
}

extension AppThemeDataExtension on ThemeData {
  AppThemeColors get appColors =>
      extension<AppThemeColors>() ??
      AppThemeColors.fromColorScheme(colorScheme);
}

extension AppThemeContextExtension on BuildContext {
  AppThemeColors get appColors => Theme.of(this).appColors;
}
