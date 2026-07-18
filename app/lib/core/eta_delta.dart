import '../domain/models/arrival.dart';
import 'arrival_display.dart';

/// Minimum shift of the *absolute* predicted arrival instant that counts as a
/// real reforecast worth flagging with a change badge (G1).
///
/// Below this it's just sub-minute quantisation jitter: the upstream rounds ETA
/// to whole minutes, and the board's as-of clock advances ~30s between polls, so
/// the reconstructed arrival instant wobbles by up to half a minute even when the
/// underlying prediction is unchanged. Applied symmetrically to both directions
/// (arriving sooner ↓ and later ↑) so the badge is honest about a genuine slip in
/// either direction, not just the monotonic count-down of a ticking clock.
const Duration kEtaChangeThreshold = Duration(seconds: 45);

/// Outcome of diffing one arrivals board against the previous poll's absolute
/// arrival instants.
class EtaDeltaResult {
  const EtaDeltaResult(this.arrivalTimes, this.deltas);

  /// Absolute predicted arrival instant per live vehicle (keyed by garage
  /// number), carried forward as the baseline for the next poll.
  final Map<String, DateTime> arrivalTimes;

  /// Signed change in whole minutes per live vehicle whose arrival instant moved
  /// by at least the threshold since the previous poll. Positive = now arriving
  /// *later* (↑), negative = *sooner* (↓). Vehicles below the threshold — the
  /// common case of the clock merely ticking — are absent, so no badge shows.
  final Map<String, int> deltas;
}

/// Decide which live rows earned an ETA-change badge by diffing a refreshed
/// [board] against the [previous] poll's absolute arrival instants.
///
/// The badge must flag a genuine *reforecast*, not the mere passing of time.
/// Diffing the displayed count-down ("18 min") is what produced the false signal:
/// every row's minutes roll over together roughly once a minute, so the whole
/// board flashed "↓ 1 min" in unison — a generator of noise that trains users to
/// distrust the badge. Instead we diff the *absolute* predicted arrival instant
/// (board's as-of time + the ETA it reported then): "arriving 15:42:30" is the
/// same prediction on the next poll even though its count-down now reads 17
/// instead of 18, so the ticking clock alone moves nothing.
///
/// Rules:
///  * **Live rows only.** An Expected placeholder or a Scheduled timetable
///    fallback isn't a tracked, moving vehicle, so it never earns a badge.
///  * **Keyed by garage number.** A row whose vehicle changed between polls has
///    no shared prediction to diff; a live row lacking a garage id has no stable
///    identity to compare, so both are skipped.
///  * **Symmetric threshold.** Only a shift of at least [threshold] in either
///    direction counts; anything smaller is quantisation noise, not news.
EtaDeltaResult diffEtaDeltas(
  Map<String, DateTime> previous,
  ArrivalsBoard board, {
  Duration threshold = kEtaChangeThreshold,
}) {
  final arrivalTimes = <String, DateTime>{};
  final deltas = <String, int>{};
  for (final a in board.arrivals) {
    if (arrivalRowStatus(a) != ArrivalRowStatus.live || a.garageNo == null) {
      continue;
    }
    final key = a.garageNo!;
    // Absolute predicted arrival = the board's as-of time + the ETA it reported
    // then. Invariant to the passing of time; only a genuine reforecast moves it.
    final arrivalAt = board.updatedAt.add(Duration(minutes: a.etaMinutes));
    arrivalTimes[key] = arrivalAt;
    final before = previous[key];
    if (before == null) continue; // first sighting of this vehicle — no baseline.
    final shift = arrivalAt.difference(before);
    if (shift.abs() < threshold) continue;
    // Round the shift to whole minutes for the glanceable badge. A change past
    // the (sub-minute) threshold must never round down to 0 and vanish, so floor
    // it to the sign's single minute.
    final minutes = (shift.inSeconds / 60).round();
    deltas[key] = minutes != 0 ? minutes : shift.inSeconds.sign;
  }
  return EtaDeltaResult(arrivalTimes, deltas);
}
