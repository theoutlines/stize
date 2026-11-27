import '../../../domain/models/geocode_result.dart';
import '../../../domain/models/line_info.dart';
import '../../../domain/models/stop.dart';

/// The map's search: whether search mode is on, the results shown, and which
/// answer may still land.
///
/// Every keystroke makes the answers to earlier queries stale, so a slow
/// answer for "79" can't overwrite the results for "790". The `search_used`
/// event is logged once per session (a session ends when the query is
/// cleared), not once per debounced keystroke.
class SearchSession {
  /// Search mode is on (the results list replaces the panel content).
  bool active = false;
  List<Stop> stops = const [];
  List<LineInfo> lines = const [];
  List<GeocodeResult> places = const [];

  bool _logged = false;
  int _query = 0;

  bool get hasResults =>
      stops.isNotEmpty || lines.isNotEmpty || places.isNotEmpty;

  /// The query changed (a keystroke): search mode on, earlier answers stale.
  void typed() {
    active = true;
    _query++;
  }

  /// A ticket for the query being run now; pass it back to [apply].
  int get ticket => _query;

  /// True once per session: log `search_used` now.
  bool firstUse() {
    if (_logged) return false;
    _logged = true;
    return true;
  }

  /// Show the answer for [ticket], unless a newer query made it stale.
  /// Returns whether it was applied.
  bool apply(
    int ticket, {
    required List<Stop> stops,
    required List<LineInfo> lines,
    required List<GeocodeResult> places,
  }) {
    if (ticket != _query) return false;
    this.stops = stops;
    this.lines = lines;
    this.places = places;
    return true;
  }

  /// The query was cleared: search mode off, no results, a new session.
  void clear() {
    active = false;
    stops = const [];
    lines = const [];
    places = const [];
    _logged = false;
    _query++;
  }
}
