import 'package:flutter/material.dart';

/// MapTiler vector map styles used across the app.
///
/// The API key is a *client* key (it necessarily ships inside the built
/// app/web bundle so the renderer can fetch tiles) — it is injected at build
/// time via `--dart-define=MAPTILER_KEY=...` and never hardcoded or committed.
/// Restrict it by allowed origins in the MapTiler dashboard, not by hiding it.
class MapStyle {
  const MapStyle._();

  static const _key = String.fromEnvironment('MAPTILER_KEY');

  /// Whether a MapTiler key was provided at build time.
  static bool get hasKey => _key.isNotEmpty;

  // Clean navigator-style base maps with a matching dark variant. This is a
  // starting point — final visual tuning is done in the MapTiler editor.
  static const _lightStyle = 'streets-v2';
  static const _darkStyle = 'streets-v2-dark';

  static String _url(String style) =>
      'https://api.maptiler.com/maps/$style/style.json?key=$_key';

  static String light() => _url(_lightStyle);

  static String dark() => _url(_darkStyle);

  /// The style URL that matches the given UI brightness, so the map follows the
  /// app's light/dark theme.
  static String forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark() : light();
}
