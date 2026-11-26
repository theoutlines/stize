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

final _codeQuery = RegExp(r'^\d{1,4}$');
const _maxCodeMatches = 10;

/// Stop search over a local list (the offline cache), the same contract as the
/// backend's `searchStopsIn` (gtfsData.ts): for an all-digit query the stop
/// with that sign number first, then numbers starting with it (typing 8 → 83 →
/// 830 narrows live), then name matches ("Blok 25" for "25"). Max 50.
List<Stop> searchStopsLocal(List<Stop> stops, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final byCode = <Stop>[];
  if (_codeQuery.hasMatch(q)) {
    final n = '${int.parse(q)}';
    final exact = <Stop>[];
    final prefix = <Stop>[];
    for (final s in stops) {
      final code = s.code;
      if (code == null) continue;
      if (code == n) {
        exact.add(s);
      } else if (code.startsWith(n)) {
        prefix.add(s);
      }
    }
    prefix.sort((a, b) => int.parse(a.stopId).compareTo(int.parse(b.stopId)));
    byCode
      ..addAll(exact)
      ..addAll(prefix.take(_maxCodeMatches));
  }
  final seen = {for (final s in byCode) s.stopId};
  return [
    ...byCode,
    for (final s in stops)
      if (!seen.contains(s.stopId) && s.name.toLowerCase().contains(q)) s,
  ].take(50).toList();
}

/// The stop/line (and, on desktop, place) results of one global query. Places
/// are desktop-only in the nearby merge; kept here so both hosts share the type.
class GlobalSearchResults {
  const GlobalSearchResults({this.stops = const [], this.lines = const []});

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
