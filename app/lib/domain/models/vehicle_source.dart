/// Where a moving object's position comes from — the *state/source* of the same
/// typed object, orthogonal to its [VehicleType]/kind:
///
///  * [live]      — a real GPS fix from the live feed (bright).
///  * [scheduled] — no live stream for this trip right now, so its position is
///    predicted from the GTFS timetable (`stop_times`) played along the route
///    shape by the *same* timed-trajectory math that drives live objects. Drawn
///    semi-transparently so it reads as "by schedule, not a live position".
///
/// Part of the hybrid live+schedule display (flag `schedule_fallback`). Parsed
/// tolerantly: anything other than an explicit "scheduled" is treated as live,
/// so a backend that doesn't emit `source` yet keeps the old behaviour.
enum VehicleSource {
  live,
  scheduled;

  static VehicleSource fromApi(Object? value) =>
      value == 'scheduled' ? VehicleSource.scheduled : VehicleSource.live;
}
