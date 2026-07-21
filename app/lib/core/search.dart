import '../domain/models/line_info.dart';
import '../domain/models/nearby_arrival.dart';
import '../domain/models/stop.dart';

/// Shared search logic for BOTH breakpoints (owner C#4: one fork of query
/// matching + ranking; the UI hosts differ — the desktop panel top bar vs the
/// mobile nearby sheet header — the logic does not).
///
/// The desktop persistent search and the mobile nearby search both fan out to
/// the same stop/line(/place) repositories (see `globalSearchProvider`); the
/// nearby sheet additionally narrows the already-fetched nearby list. This file
/// holds the pure pieces so they're unit-testable without a live map or network.

/// Case-insensitive substring filter over the nearby groups (line / destination
/// / stop name) — the old mobile "filter lines nearby" behaviour, lifted out of
/// `NearbyView` so it's shared and tested. Empty query ⇒ the list unchanged.
List<NearbyGroup> filterNearbyGroups(List<NearbyGroup> groups, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return groups;
  return [
    for (final g in groups)
      if (g.line.toLowerCase().contains(q) ||
          (g.destination ?? '').toLowerCase().contains(q) ||
          g.stopName.toLowerCase().contains(q))
        g,
  ];
}

/// The stop/line (and, on desktop, place) results of one global query. Places
/// are desktop-only in the nearby merge; kept here so both hosts share the type.
class GlobalSearchResults {
  const GlobalSearchResults({
    this.stops = const [],
    this.lines = const [],
  });

  final List<Stop> stops;
  final List<LineInfo> lines;

  bool get isEmpty => stops.isEmpty && lines.isEmpty;
}

/// A single row in the unified nearby-sheet search results.
sealed class SearchRow {
  const SearchRow();
}

/// A live nearby match (the preserved "filter lines nearby" use case).
class NearbySearchRow extends SearchRow {
  const NearbySearchRow(this.group);
  final NearbyGroup group;
}

/// A global stop result (opens the stop context, like on desktop).
class StopSearchRow extends SearchRow {
  const StopSearchRow(this.stop);
  final Stop stop;
}

/// A global line result (opens the line, like on desktop).
class LineSearchRow extends SearchRow {
  const LineSearchRow(this.line);
  final LineInfo line;
}

/// Merge the two sources into ONE ordered list: every nearby match ranks ABOVE
/// every global result for the same query (owner C#3 — nearby first preserves
/// the old filter). Global stops precede global lines. A global result already
/// surfaced as a nearby match (same stop id / same line) is dropped so it isn't
/// shown twice.
List<SearchRow> mergeNearbyThenGlobal({
  required List<NearbyGroup> nearby,
  required List<Stop> stops,
  required List<LineInfo> lines,
}) {
  final nearbyStopIds = {for (final g in nearby) g.stopId};
  final nearbyLines = {for (final g in nearby) g.line};
  return [
    for (final g in nearby) NearbySearchRow(g),
    for (final s in stops)
      if (!nearbyStopIds.contains(s.stopId)) StopSearchRow(s),
    for (final l in lines)
      if (!nearbyLines.contains(l.line)) LineSearchRow(l),
  ];
}
