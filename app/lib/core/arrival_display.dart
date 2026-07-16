import '../domain/models/arrival.dart';
import 'live_position.dart';

/// The single honest status every arrival row carries — so no row ever renders
/// blank. Brightness in the UI follows this: [live] is clickable (full opacity
/// + chevron), [expected] and [scheduled] are not (dimmed, no chevron).
enum ArrivalRowStatus {
  /// A genuinely tracked vehicle: live GPS, real garage — followable on the map.
  live,

  /// A valid ETA with no live position yet — the schedule-derived placeholder
  /// class (garage `P1..P999`, pinned to the stop). Honest "Expected", not a
  /// broken live row. Deferred reclassification lives in the arrivals-dedup task.
  expected,

  /// Timetable fallback (`source=scheduled`) — no vehicle at all.
  scheduled,
}

/// Classify a row into its single honest status. Clickability == [live].
ArrivalRowStatus arrivalRowStatus(Arrival arrival) {
  if (arrival.scheduled) return ArrivalRowStatus.scheduled;
  if (arrivalHasLivePosition(arrival)) return ArrivalRowStatus.live;
  return ArrivalRowStatus.expected;
}

/// How to describe an arrival's proximity in the list, deciding whether the
/// upstream `stops_remaining` field can be trusted.
enum ArrivalProximity {
  /// At / arriving at this stop — 0 stops away, and consistent with a near ETA.
  here,

  /// A trustworthy count of stops still to go ("N stops away").
  stopsAway,

  /// `stops_remaining` is absent or junk (0 while the ETA is far) — show no stops
  /// text and let the honest ETA speak for itself.
  unknown,
}

/// The default ETA (minutes) up to which "0 stops away" is believed to mean
/// "here". A vehicle genuinely at/arriving at the stop has an ETA of ~0-2 min.
const int kHereEtaMinutes = 2;

/// Trust `stops_remaining` only when it agrees with the ETA.
///
/// The upstream emits `stops_remaining = 0` as **junk** for a class of rows —
/// notably the schedule-derived placeholder vehicles (garage `P1..P999`) that are
/// pinned to the stop's own coordinate — even when the ETA is 10-20 min. Rendered
/// literally, a bare "0 stops → here" lies (confirmed on Zeleni venac: `706` with
/// garage `P2`, ETA 19 min, stops 0). So:
///
///  * `stops == 0` is shown as [here] ONLY when the ETA is within
///    [hereEtaMinutes] (the two agree); a 0 that contradicts the ETA drops to
///    [unknown] (no stops text — the ETA is the honest signal).
///  * a positive count is trusted as [stopsAway].
///  * null/negative is [unknown].
///
/// Pure so the rule can be unit-tested against the real Zvezdara / Zeleni venac
/// fixtures.
ArrivalProximity arrivalProximity({
  required int? stopsRemaining,
  required int etaMinutes,
  int hereEtaMinutes = kHereEtaMinutes,
}) {
  if (stopsRemaining == null || stopsRemaining < 0) return ArrivalProximity.unknown;
  if (stopsRemaining == 0) {
    return etaMinutes <= hereEtaMinutes
        ? ArrivalProximity.here
        : ArrivalProximity.unknown;
  }
  return ArrivalProximity.stopsAway;
}
