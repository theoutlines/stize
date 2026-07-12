import 'package:latlong2/latlong.dart' as ll;

/// Pure helpers for tracking the user's own position from a live location
/// stream. Kept free of Flutter/geolocator so the staleness and easing rules
/// are unit-testable in isolation (same spirit as `vehicle_track_animator`,
/// but far simpler — here fixes are *frequent*, so there is no "don't overshoot
/// the last fix" machinery, just a short ease and a watchdog).

/// Straight-line interpolation between two geographic points. Used to ease the
/// "my position" marker from where it is drawn toward the newest fix; [t] is the
/// animation value in `[0, 1]`.
ll.LatLng lerpLatLng(ll.LatLng from, ll.LatLng to, double t) {
  final c = t.clamp(0.0, 1.0);
  return ll.LatLng(
    from.latitude + (to.latitude - from.latitude) * c,
    from.longitude + (to.longitude - from.longitude) * c,
  );
}

/// Whether a live position subscription should be torn down and recreated.
///
/// `watchPosition` (web / iOS Safari especially) can quietly stall after the
/// tab loses and regains visibility — it stops emitting without erroring. When
/// the screen becomes active again we recreate the subscription if nothing has
/// arrived for [staleThreshold], measured from the later of the last fix and the
/// moment we subscribed (so a subscription that has simply not produced its
/// first fix yet isn't torn down prematurely).
///
/// Returns false whenever the screen isn't active — a backgrounded/hidden
/// stream is paused deliberately and must not be resurrected here.
bool shouldResubscribe({
  required bool active,
  required DateTime? lastFixAt,
  required DateTime subscribedAt,
  required DateTime now,
  required Duration staleThreshold,
}) {
  if (!active) return false;
  final reference = (lastFixAt != null && lastFixAt.isAfter(subscribedAt))
      ? lastFixAt
      : subscribedAt;
  return now.difference(reference) >= staleThreshold;
}
