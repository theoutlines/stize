// Client-side timetable fallback: a Dart port of the backend's
// `upcomingScheduled` (backend/src/lib/schedule.ts). Used when the API worker
// itself can't answer (e.g. the daily Workers request quota is exhausted at
// Expo-scale traffic): the per-stop timetable files under /gtfs/schedule/ are
// static assets, served without invoking the worker, so the stop board can
// still show planned departures. Keep the selection rules in step with the
// backend so the two fallbacks read the same.

/// Belgrade wall-clock "now": today's and yesterday's ISO dates plus minutes
/// since local midnight (schedule minutes are local time).
class BelgradeNow {
  const BelgradeNow(this.dateISO, this.yesterdayISO, this.minutes);
  final String dateISO;
  final String yesterdayISO;
  final int minutes;
}

DateTime _lastSunday(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, last.day - (last.weekday % 7));
}

/// Europe/Belgrade offset for a UTC instant: CET (+1), CEST (+2) from the last
/// Sunday of March 01:00 UTC to the last Sunday of October 01:00 UTC (EU rule).
Duration belgradeOffset(DateTime utc) {
  final y = utc.year;
  final start = _lastSunday(y, 3).add(const Duration(hours: 1));
  final end = _lastSunday(y, 10).add(const Duration(hours: 1));
  final summer = !utc.isBefore(start) && utc.isBefore(end);
  return Duration(hours: summer ? 2 : 1);
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

BelgradeNow belgradeNow(DateTime instant) {
  final utc = instant.toUtc();
  final local = utc.add(belgradeOffset(utc));
  final yUtc = utc.subtract(const Duration(days: 1));
  final yLocal = yUtc.add(belgradeOffset(yUtc));
  return BelgradeNow(_iso(local), _iso(yLocal), local.hour * 60 + local.minute);
}

const _dow = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

/// Active service ids for a date: weekday base services, then the date's
/// calendar exceptions (removes first, then adds).
Set<String> activeServices(String dateISO, Map<String, dynamic> meta) {
  final d = DateTime.parse('${dateISO}T00:00:00Z');
  final dow = _dow[d.weekday % 7];
  final active = <String>{};
  final services = (meta['services'] as Map?)?.cast<String, dynamic>() ?? const {};
  services.forEach((id, days) {
    if (((days as Map)[dow] ?? 0) == 1) active.add(id);
  });
  final ex = ((meta['exceptions'] as Map?) ?? const {})[dateISO] as Map?;
  if (ex != null) {
    for (final s in (ex['remove'] as List? ?? const [])) {
      active.remove(s as String);
    }
    for (final s in (ex['add'] as List? ?? const [])) {
      active.add(s as String);
    }
  }
  return active;
}

class PlannedDeparture {
  const PlannedDeparture(this.line, this.routeId, this.dir, this.etaMinutes);
  final String line;
  final String routeId;
  final String dir;
  final int etaMinutes;
}

const _overnight = 1440;

/// Upcoming planned departures at a stop: per line, the next [minTrips] or
/// everything within [windowMinutes] (whichever is more), capped at
/// [maxPerLine] and never beyond [maxEtaMinutes]. Sorted by ETA.
List<PlannedDeparture> upcomingScheduled(
  Map<String, dynamic> schedule,
  Map<String, dynamic> meta,
  BelgradeNow now, {
  int minTrips = 3,
  int windowMinutes = 90,
  int maxPerLine = 10,
  int maxEtaMinutes = 180,
}) {
  final today = activeServices(now.dateISO, meta);
  final yest = activeServices(now.yesterdayISO, meta);
  final out = <PlannedDeparture>[];
  for (final raw in (schedule['deps'] as List? ?? const [])) {
    final dep = raw as Map<String, dynamic>;
    final etas = <int>[];
    (dep['svc'] as Map).forEach((svc, mins) {
      final list = (mins as List).cast<num>();
      if (today.contains(svc)) {
        for (final t in list) {
          if (t >= now.minutes) etas.add(t.toInt() - now.minutes);
        }
      }
      if (yest.contains(svc)) {
        for (final t in list) {
          if (t >= _overnight) {
            final local = t.toInt() - _overnight;
            if (local >= now.minutes) etas.add(local - now.minutes);
          }
        }
      }
    });
    etas.sort();
    var taken = 0;
    for (var i = 0; i < etas.length && taken < maxPerLine; i++) {
      if (etas[i] > maxEtaMinutes) break;
      if (i < minTrips || etas[i] <= windowMinutes) {
        out.add(PlannedDeparture(
          dep['line'] as String,
          dep['route_id'] as String,
          dep['dir'] as String,
          etas[i],
        ));
        taken++;
      } else {
        break;
      }
    }
  }
  out.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
  return out;
}

/// Planned interval per direction (`route_id`) at a stop around [now]: the
/// median gap between this direction's timetabled departures from 30 min ago to
/// 90 min ahead. Only directions with at least two gaps in that window and a
/// median of at most [maxMinutes] (an hour) are returned: a sparse line is better told by
/// its next departure time than by an "every N min" that is barely true.
Map<String, int> plannedHeadways(
  Map<String, dynamic> schedule,
  Map<String, dynamic> meta,
  BelgradeNow now, {
  int maxMinutes = 60,
}) {
  final today = activeServices(now.dateISO, meta);
  final yest = activeServices(now.yesterdayISO, meta);
  final lo = now.minutes - 30;
  final hi = now.minutes + 90;
  final out = <String, int>{};
  for (final raw in (schedule['deps'] as List? ?? const [])) {
    final dep = raw as Map<String, dynamic>;
    final times = <int>{};
    (dep['svc'] as Map).forEach((svc, mins) {
      for (final t in (mins as List).cast<num>()) {
        final v = t.toInt();
        if (today.contains(svc) && v >= lo && v <= hi) times.add(v);
        if (yest.contains(svc) && v >= _overnight) {
          final local = v - _overnight;
          if (local >= lo && local <= hi) times.add(local);
        }
      }
    });
    if (times.length < 3) continue;
    final sorted = times.toList()..sort();
    final gaps = <int>[
      for (var i = 1; i < sorted.length; i++) sorted[i] - sorted[i - 1],
    ]..sort();
    final median = gaps[gaps.length ~/ 2];
    if (median <= 0 || median > maxMinutes) continue;
    out[dep['route_id'] as String] = median;
  }
  return out;
}
