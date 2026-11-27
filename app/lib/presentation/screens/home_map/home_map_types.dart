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

/// A level in the context slot's chain.
sealed class _SlotLevel {
  const _SlotLevel();
}

class _StopLevel extends _SlotLevel {
  const _StopLevel(this.id, this.name);
  final String id;
  final String? name;
}

class _MyStopsLevel extends _SlotLevel {
  const _MyStopsLevel();
}

class _SettingsLevel extends _SlotLevel {
  const _SettingsLevel();
}

class _FeedbackLevel extends _SlotLevel {
  const _FeedbackLevel({this.form = false});
  final bool form;
}

class _GuideLevel extends _SlotLevel {
  const _GuideLevel(this.page);
  final GuidePage page;
}
