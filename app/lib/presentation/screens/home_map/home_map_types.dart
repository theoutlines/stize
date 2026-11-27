part of '../home_map_screen.dart';

// Small value types of the home map: the focused line and the levels of the
// sheet / panel (stop, My stops, Settings, Feedback, the guide).

/// A line whose route is currently highlighted on the home map (the inline
/// alternative to pushing a separate route screen).
class _LineFocus {
  const _LineFocus({
    required this.line,
    required this.type,
    required this.origin,
    required this.destination,
    required this.polyline,
    required this.stops,
    this.scheduled = false,
  });

  final String line;
  final VehicleType type;
  final String origin;
  final String destination;
  final List<List<double>> polyline; // [[lat, lon], ...]
  final List<Stop> stops;

  /// Opened from a tap on a schedule-predicted object — the panel notes it.
  final bool scheduled;
}
