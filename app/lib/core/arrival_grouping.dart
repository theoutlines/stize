import '../domain/models/arrival.dart';
import '../domain/models/vehicle_type.dart';
import 'arrival_display.dart';

/// One entry in the rendered arrivals list. After grouping, a stop's board is a
/// flat list of these: live/expected vehicles keep their own row
/// ([ArrivalRow]); the schedule fallback of a line×direction is folded into a
/// single [ScheduledGroupCell].
sealed class ArrivalListEntry {
  const ArrivalListEntry();
}

/// A single vehicle row — [ArrivalRowStatus.live] or [ArrivalRowStatus.expected].
/// Rendered exactly as before (Fleet-ID, clickability, follow for live). The
/// original board index is kept so the caller can pair fleet info / ETA deltas
/// it computed against the untouched `arrivals` list.
class ArrivalRow extends ArrivalListEntry {
  const ArrivalRow(this.arrival, this.index, {this.laterEtaMinutes = const []});

  final Arrival arrival;
  final int index;

  /// After [foldLiveByDirection]: ETAs (minutes) of the later live vehicles of
  /// the same line×direction that this card now stands for, ascending. Empty
  /// for an unfolded row.
  final List<int> laterEtaMinutes;
}

/// The collapsed schedule fallback for one line×direction: instead of N
/// Scheduled rows, a single cell that shows the nearest ETA plus up to two more
/// ("картина целиком", not a full timetable). Only carries scheduled ETAs that
/// survived live-horizon suppression, nearest first, capped at [maxTimes].
class ScheduledGroupCell extends ArrivalListEntry {
  const ScheduledGroupCell({
    required this.line,
    required this.vehicleType,
    required this.etaMinutes,
  });

  final String line;
  final VehicleType vehicleType;

  /// Surviving scheduled ETAs (minutes), ascending, at most [maxTimes] entries.
  /// First is the "nearest" shown large; the rest are the muted follow-ups.
  final List<int> etaMinutes;
}

/// Most times a collapsed cell ever shows: nearest + next two. A collapse is a
/// glance at the picture, never the full schedule.
const int kMaxScheduledTimes = 3;

/// The direction key an arrival groups under. The backend-resolved travel
/// direction ([Arrival.directionRouteId]) when present, else the canonical
/// [Arrival.routeId] — so a line running two directions through one stop forms
/// two groups, and rows with no resolved direction still group sanely.
String _directionKey(Arrival a) => a.directionRouteId ?? a.routeId;

String _groupKey(Arrival a) => '${a.line}${_directionKey(a)}';

/// Turn a stop's raw arrivals into the deduplicated, collapsed display list.
///
/// Rules (see docs/SCHEDULE_FALLBACK_CONTRACT.md → "Правила отображения списка
/// прибытий"):
///
///  1. Group by line × direction.
///  2. Suppress duplicates, two horizons stacked:
///     * **Global** — if the board has *any* live vehicle, every non-live entry
///       (any line) whose ETA is **below the soonest live ETA on the board** is
///       a phantom (a vehicle that would already be visible live if it were
///       real) and is hidden.
///     * **Per line×direction** — on top of that, a group's non-live rows at or
///       before *its own* latest live ETA are the same physical vehicles shown
///       live, and drop out.
///     A board with **no live at all** suppresses nothing (the night/fallback
///     case works as designed).
///  3. Collapse the surviving Scheduled of a group into one cell (nearest + up
///     to two more). Expected rows are NOT collapsed — a placeholder vehicle has
///     a valid per-vehicle ETA, so it keeps its own row.
///  4. Order — **two global sections, not per-group**: first **every live row**
///     of every line, sorted by ETA; then **every non-live** entry (surviving
///     Expected rows and the collapsed Scheduled cells), sorted by nearest ETA.
///     No scheduled/expected entry ever sits above any live row, regardless of
///     line or ETA ("a scheduled bus, however soon its plan, won't beat a bus
///     that's actually running"). Suppression stays scoped to line×direction.
///
/// Pure and independent of widgets so the rule is unit-testable. ETA ties break
/// on the board's original order (it arrives ETA-sorted).
List<ArrivalListEntry> groupArrivals(List<Arrival> arrivals) {
  // Preserve first-seen order of groups for a stable tie-break, and remember
  // each arrival's original index for the caller's fleet/delta pairing.
  final order = <String>[];
  final groups = <String, List<(int, Arrival)>>{};
  for (var i = 0; i < arrivals.length; i++) {
    final a = arrivals[i];
    final key = _groupKey(a);
    (groups[key] ??= (order..add(key), <(int, Arrival)>[]).$2).add((i, a));
  }

  // Global suppression horizon: the soonest live ETA anywhere on the board. Any
  // non-live entry below it — of any line — is a phantom (it would be shown live
  // if it existed), so it's hidden. Null when the board has no live at all, in
  // which case nothing is suppressed (the night/fallback case).
  final allLiveEtas = [
    for (final a in arrivals)
      if (arrivalRowStatus(a) == ArrivalRowStatus.live) a.etaMinutes,
  ];
  final globalHorizon =
      allLiveEtas.isEmpty ? null : allLiveEtas.reduce((a, b) => a < b ? a : b);

  // Two global sections, each sorted by ETA (original board index breaks ties):
  //   liveRows  — every live vehicle of every line;
  //   nonLive   — every surviving Expected row + every collapsed Scheduled cell.
  final liveRows = <(int eta, int idx, ArrivalListEntry entry)>[];
  final nonLive = <(int eta, int idx, ArrivalListEntry entry)>[];

  for (var g = 0; g < order.length; g++) {
    final members = groups[order[g]]!;

    final live = <(int, Arrival)>[];
    final expected = <(int, Arrival)>[];
    final scheduled = <(int, Arrival)>[];
    for (final m in members) {
      switch (arrivalRowStatus(m.$2)) {
        case ArrivalRowStatus.live:
          live.add(m);
        case ArrivalRowStatus.expected:
          expected.add(m);
        case ArrivalRowStatus.scheduled:
          scheduled.add(m);
      }
    }

    // A non-live entry survives only if it clears BOTH horizons:
    //   * global — at/above the board's soonest live ETA (else it's a phantom
    //     of some other running line);
    //   * per line×direction — strictly beyond its own line's latest live ETA
    //     (else it's the same vehicle already shown live).
    final ownHorizon = live.isNotEmpty
        ? live.map((m) => m.$2.etaMinutes).reduce((a, b) => a > b ? a : b)
        : null;
    bool beyondHorizon((int, Arrival) m) {
      final eta = m.$2.etaMinutes;
      if (globalHorizon != null && eta < globalHorizon) return false;
      return ownHorizon == null || eta > ownHorizon;
    }

    final survivingScheduled = scheduled.where(beyondHorizon).toList()
      ..sort((a, b) => a.$2.etaMinutes.compareTo(b.$2.etaMinutes));

    for (final m in live) {
      liveRows.add((m.$2.etaMinutes, m.$1, ArrivalRow(m.$2, m.$1)));
    }
    for (final m in expected.where(beyondHorizon)) {
      nonLive.add((m.$2.etaMinutes, m.$1, ArrivalRow(m.$2, m.$1)));
    }
    if (survivingScheduled.isNotEmpty) {
      nonLive.add((
        survivingScheduled.first.$2.etaMinutes,
        survivingScheduled.first.$1,
        ScheduledGroupCell(
          line: survivingScheduled.first.$2.line,
          vehicleType: survivingScheduled.first.$2.vehicleType,
          etaMinutes: [
            for (final m in survivingScheduled.take(kMaxScheduledTimes))
              m.$2.etaMinutes,
          ],
        ),
      ));
    }
  }

  int byEtaThenIndex(
    (int, int, ArrivalListEntry) a,
    (int, int, ArrivalListEntry) b,
  ) {
    final byEta = a.$1.compareTo(b.$1);
    return byEta != 0 ? byEta : a.$2.compareTo(b.$2);
  }

  liveRows.sort(byEtaThenIndex);
  nonLive.sort(byEtaThenIndex);

  return [
    for (final r in liveRows) r.$3,
    for (final r in nonLive) r.$3,
  ];
}


/// Most later trips a folded live card lists next to its main ETA.
const int kMaxLaterLiveTimes = 2;

/// One card per line×direction (owner, 2026-11-22): keeps the soonest live row
/// of each line×direction where it is and folds that direction's later live
/// vehicles into it as [ArrivalRow.laterEtaMinutes] (at most
/// [kMaxLaterLiveTimes]). Expected rows and scheduled cells pass through.
List<ArrivalListEntry> foldLiveByDirection(List<ArrivalListEntry> entries) {
  final firstAt = <String, int>{};
  final later = <String, List<int>>{};
  final out = <ArrivalListEntry>[];
  for (final e in entries) {
    if (e is ArrivalRow && arrivalRowStatus(e.arrival) == ArrivalRowStatus.live) {
      final key = _groupKey(e.arrival);
      if (firstAt.containsKey(key)) {
        (later[key] ??= <int>[]).add(e.arrival.etaMinutes);
        continue;
      }
      firstAt[key] = out.length;
    }
    out.add(e);
  }
  later.forEach((key, etas) {
    final i = firstAt[key]!;
    final row = out[i] as ArrivalRow;
    out[i] = ArrivalRow(
      row.arrival,
      row.index,
      laterEtaMinutes: (etas..sort()).take(kMaxLaterLiveTimes).toList(),
    );
  });
  return out;
}


/// The destination shown on an arrival card. A line whose headsign IS this
/// stop ends here, so an arrow to this very stop would read as nonsense: show
/// [terminusLabel] ("Konačna") instead. Comparison ignores case, spacing and
/// Serbian diacritics, since headsigns and stop names are typed separately.
String? displayDestination(
    String? destination, String stopName, String terminusLabel) {
  if (destination == null || destination.trim().isEmpty) return destination;
  String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[čć]'), 'c')
      .replaceAll('š', 's')
      .replaceAll('ž', 'z')
      .replaceAll('đ', 'dj')
      .replaceAll(RegExp(r'[^a-z0-9а-я]'), '');
  final d = norm(destination), s = norm(stopName);
  return d.isNotEmpty && d == s ? terminusLabel : destination;
}
