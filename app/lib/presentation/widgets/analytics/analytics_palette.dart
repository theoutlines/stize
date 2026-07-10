import 'package:flutter/material.dart';

/// Shared colour language for the analytics charts. Kept separate from the
/// transport-type colours used on the map (blue/orange/red) — this is a
/// different context: a diverging good→bad reliability scale plus a single-hue
/// density ramp. Both are tuned to read in light and dark themes.
class AnalyticsPalette {
  const AnalyticsPalette._();

  /// Diverging reliability scale: t=0 → green (good), 0.5 → amber, 1 → red.
  /// Used for punctuality and interval heatmaps.
  static Color reliability(double t) {
    final v = t.clamp(0.0, 1.0);
    const green = Color(0xFF2E9E5B);
    const amber = Color(0xFFE6A817);
    const red = Color(0xFFD3402B);
    return v < 0.5
        ? Color.lerp(green, amber, v * 2)!
        : Color.lerp(amber, red, (v - 0.5) * 2)!;
  }

  /// Single-hue density ramp (GitHub-contributions style): faint → accent.
  /// t=0 is an empty/low cell, t=1 the busiest.
  static Color intensity(BuildContext context, double t) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final accent = scheme.primary;
    return Color.lerp(base, accent, 0.15 + t.clamp(0.0, 1.0) * 0.85)!;
  }

  /// Colour for an empty cell (no observations in that slot).
  static Color empty(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);

  static const seriesA = Color(0xFF3B6FD4);
  static const seriesB = Color(0xFFE6612C);
}
