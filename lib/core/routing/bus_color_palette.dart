import 'package:flutter/material.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Deterministic colors for bus "wires" in the Bus Lanes view.
///
/// Each bus has a stable base hue, spread via the golden angle so adjacent bus
/// numbers look distinct, with a loose per-category tint (inputs/outputs/aux).
/// Within a single bus:
/// - an empty wire is a pale, desaturated tint ([empty]);
/// - each Replace starts a new "session" whose tone is visibly shifted
///   ([sessionColor]) so a cap reads as a fresh signal;
/// - additional Add writers in a session darken the tone ([withAddDepth]).
class BusColorPalette {
  BusColorPalette._();

  static const double _goldenAngle = 137.508;

  /// Base hue (0-360) for a bus. A per-group offset keeps physical inputs
  /// (1-12), physical outputs (13-20) and aux/ES-5 (21+) trending toward
  /// different parts of the wheel while the golden-angle term keeps individual
  /// buses distinct.
  static double _hue(int bus, DeviceIoProfile profile) {
    final groupOffset = profile.isInput(bus)
        ? 90.0 // greens
        : profile.isOutput(bus)
        ? 0.0 // reds/oranges
        : 210.0; // blues/purples
    return (groupOffset + bus * _goldenAngle) % 360.0;
  }

  static HSLColor _baseHsl(int bus, bool isDark, DeviceIoProfile profile) =>
      HSLColor.fromAHSL(
        1.0,
        _hue(bus, profile),
        isDark ? 0.55 : 0.65,
        isDark ? 0.62 : 0.45,
      );

  /// The bus's representative color (for legends/labels and the first session).
  static Color baseColor(
    int bus, {
    bool isDark = false,
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) => _baseHsl(bus, isDark, deviceIoProfile).toColor();

  /// Color for a signal, keyed by its origination order (which output started
  /// it) rather than the bus it travels on. Spread via the golden angle so
  /// distinct signals look distinct; a Replace originates a new signal → new
  /// color.
  static Color signalColor(int signalId, {bool isDark = false}) {
    final hue = (signalId * _goldenAngle) % 360.0;
    return HSLColor.fromAHSL(
      1.0,
      hue,
      isDark ? 0.55 : 0.68,
      isDark ? 0.60 : 0.46,
    ).toColor();
  }

  /// The theme-provided neutral tube colour for a bus carrying no signal.
  static Color empty(int bus, {required Color neutralColor}) => neutralColor;

  /// Color for a contiguous driven segment ("session"). Each Replace increments
  /// [sessionIndex], shifting the tone noticeably so the cap + restart is
  /// obvious while the wire stays recognizably the same bus.
  static Color sessionColor(
    int bus,
    int sessionIndex, {
    bool isDark = false,
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    final h = _baseHsl(bus, isDark, deviceIoProfile);
    final hueShift = sessionIndex * 48.0;
    final lightBump = sessionIndex.isOdd ? (isDark ? 0.12 : -0.10) : 0.0;
    return h
        .withHue((h.hue + hueShift) % 360.0)
        .withLightness((h.lightness + lightBump).clamp(0.15, 0.85).toDouble())
        .toColor();
  }

  /// Each Add writer makes the tube denser — darker and more saturated — since
  /// more signal stacks more "ink" onto the bus.
  /// [addCount] is the number of Add writers beyond the first contributor.
  static Color withAddDepth(Color color, int addCount, {bool isDark = false}) {
    if (addCount <= 0) return color;
    final h = HSLColor.fromColor(color);
    final l = (h.lightness - 0.09 * addCount).clamp(isDark ? 0.18 : 0.12, 1.0);
    final s = (h.saturation + 0.08 * addCount).clamp(0.0, 1.0);
    return h.withLightness(l.toDouble()).withSaturation(s.toDouble()).toColor();
  }
}
