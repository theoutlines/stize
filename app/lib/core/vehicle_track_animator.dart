import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/arrival.dart';
import '../domain/models/trajectory_point.dart';
import '../domain/models/vehicle_type.dart';
import 'route_path.dart';
import 'timed_trajectory.dart';

class VehicleTrack {
  VehicleTrack(
    this.to, {
    required this.line,
    required this.type,
    this.heading,
    this.path,
  }) : from = to {
    if (path != null) {
      final d = path!.project(to);
      fromDist = d;
      toDist = d;
    }
  }

  ll.LatLng from;
  ll.LatLng to;

  /// Line number and type, carried so the marker can render an informative
  /// badge without re-looking-up the arrival.
  final String line;
  final VehicleType type;

  /// Travel direction in degrees (0 = north, clockwise), or null if unknown.
  /// Used only as a fallback heading when there's no route [path]; with a path
  /// the heading is derived from the path tangent so it always matches motion.
  double? heading;

  /// The vehicle's route geometry, when known. When present, the marker moves
  /// *along* this path between updates instead of in a straight line (X5).
  RoutePath? path;

  /// Distance-along [path] (metres) the animation eases between. Unused in the
  /// straight-line fallback.
  double fromDist = 0;
  double toDist = 0;

  /// Time-driven player over the backend's forward timing plan (timed-trajectory
  /// feature). When present it *supersedes* the from/to ease: the marker is
  /// driven forward by wall-clock along the plan instead of easing to the last
  /// fix and stopping. Null when there's no plan (feature off / none usable), in
  /// which case the conservative from/to behaviour above applies unchanged.
  TimedTrajectory? timed;

  /// Wall-clock time of the last update in which the vehicle actually moved.
  /// "Looks stuck" is derived from how long ago this was (time-based, so a burst
  /// of extra refreshes from panning can't make a vehicle read stuck early).
  late DateTime lastMovedAt;

  /// How many consecutive updates the vehicle has been *absent* from the feed.
  /// A short absence is a data blip, not the end of a trip, so the marker is
  /// held (and faded) for a grace period before being dropped (X6).
  int missingCount = 0;
}

/// One vehicle position update fed into [VehicleTrackAnimator.syncSamples].
class VehicleSample {
  const VehicleSample({
    required this.key,
    required this.position,
    required this.line,
    required this.type,
    this.heading,
    this.path,
    this.trajectory,
    this.asOf,
  });

  final String key;
  final ll.LatLng position;
  final String line;
  final VehicleType type;
  final double? heading;

  /// The vehicle's route geometry, if the caller could resolve it.
  final RoutePath? path;

  /// The backend's forward timing plan and the as-of time it's anchored to. The
  /// caller passes these only when the timed-trajectory feature is on and a plan
  /// is available; the marker then animates by time instead of easing to the
  /// last fix. Requires [path] to be projected onto the road geometry.
  final List<TrajectoryPoint>? trajectory;
  final DateTime? asOf;
}

/// Pure interpolation logic behind the live-tracking map, kept separate from
/// the widget tree so it can be unit-tested without spinning up a real map.
///
/// Two guarantees hold the tracking together:
///  * **Move along the route, not through buildings (X5).** When a vehicle's
///    route [RoutePath] is known, its displayed position eases along that path
///    between successive real fixes (projected onto the path), and its heading
///    comes from the path tangent so the arrow always matches the motion. With
///    no path we fall back to a conservative straight-line ease.
///  * **Never run ahead of the real vehicle (F1).** The marker only ever eases
///    toward a position/along-distance the vehicle has *already* reported — it
///    never extrapolates forward — so on-screen it lags rather than races.
///  * **Don't flicker on a data blip (X6).** A vehicle missing from one or two
///    updates is held on its last known position (and faded) for a grace period
///    before its marker is removed.
class VehicleTrackAnimator {
  VehicleTrackAnimator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Wall clock, injectable for tests.
  final DateTime Function() _clock;

  final Map<String, VehicleTrack> _tracks = {};

  Map<String, VehicleTrack> get tracks => _tracks;

  // A vehicle whose reported position hasn't moved beyond this between updates
  // is treated as not having moved (~11 m either way).
  static const _stillEpsilon = 1e-4; // degrees, straight-line fallback
  static const _stillMeters = 12.0; // path mode

  // How long a vehicle must sit still before it reads as "looks stuck" and its
  // marker turns red (E4). Kept generous — a bus legitimately dwells at a stop,
  // a terminus, or a long red light — so we only flag a genuine multi-minute
  // stall, and it's time-based so extra refreshes (panning) can't trip it early.
  static const _stuckAfter = Duration(minutes: 2);

  // Keep a vanished vehicle on its last position for this many missing updates
  // before dropping it (X6 grace period). At ~30s/update this holds a blinked-
  // out vehicle ~2 min, faded, rather than popping it off the instant the
  // reconstruction drops it from one fan-out.
  static const _graceThreshold = 4;

  // Never let a marker jump more than this toward a new fix in a single update:
  // excess distance is deferred to later updates so the marker eases at a
  // plausible speed and always *lags* reality instead of teleporting or racing
  // ahead (#6). ~500 m/update ≈ 60 km/h at a 30s cadence — above any real city
  // transit speed, so genuine movement is untouched; only data jumps are tamed.
  static const _maxAdvanceMeters = 500.0;

  // Beyond this the backlog is so large the track is almost certainly wrong
  // (route re-match, long feed gap): snap to the real fix rather than crawl for
  // minutes.
  static const _snapMeters = 2000.0;

  static String keyFor(Arrival a) => a.garageNo ?? '${a.line}-${a.routeId}';

  /// Call when new arrivals data lands. [currentT] is the animation
  /// controller's value (0..1) *before* it gets reset, so an in-flight
  /// vehicle's current interpolated spot becomes its new starting point.
  void sync(
    List<Arrival> arrivals,
    double currentT, {
    DateTime? now,
    DateTime? asOf,
    RoutePath? Function(String line)? pathFor,
  }) {
    syncSamples([
      for (final a in arrivals)
        if (a.gps != null)
          VehicleSample(
            key: keyFor(a),
            position: ll.LatLng(a.gps!.lat, a.gps!.lon),
            line: a.line,
            type: a.vehicleType,
            heading: a.heading,
            // Timed-trajectory playback kicks in only when the caller supplies
            // the route geometry and the board's as-of time; otherwise these are
            // null and the marker eases conservatively as before.
            path: pathFor?.call(a.line),
            trajectory: a.trajectory,
            asOf: asOf,
          ),
    ], currentT, now: now);
  }

  /// Generic form of [sync] for any moving-vehicle source (e.g. the map-wide
  /// "vehicles in the visible area" feed). Same conservative-easing rule.
  void syncSamples(
    Iterable<VehicleSample> samples,
    double currentT, {
    DateTime? now,
  }) {
    final at = now ?? _clock();
    final seen = <String>{};
    for (final s in samples) {
      seen.add(s.key);
      final existing = _tracks[s.key];
      if (existing == null) {
        final track = VehicleTrack(
          s.position,
          line: s.line,
          type: s.type,
          heading: s.heading,
          path: s.path,
        )..lastMovedAt = at;
        _applyTimedPlan(track, s, at);
        _tracks[s.key] = track;
        continue;
      }

      existing.missingCount = 0;
      // Timed-trajectory mode (feature on + a usable plan) supersedes the
      // conservative from/to ease: the marker plays the plan forward by time,
      // and a fresher plan corrects it without ever rewinding (see
      // TimedTrajectory). When there's no plan we fall through to the ease below.
      if (_applyTimedPlan(existing, s, at)) {
        if (s.heading != null) existing.heading = s.heading;
        existing.path ??= s.path;
        continue;
      }
      // A vehicle that had a plan but no longer does (feature flipped off, or the
      // plan dropped out): abandon timed mode and resume conservative easing from
      // wherever the marker currently shows.
      if (existing.timed != null) {
        existing.from = existing.timed!.position;
        existing.to = existing.timed!.position;
        final p = existing.path;
        if (p != null && p.isUsable) {
          final d = p.project(existing.timed!.position);
          existing.fromDist = d;
          existing.toDist = d;
        }
        existing.timed = null;
      }
      // A path may only have become available on a later update; when it does,
      // there's no prior distance-along to anchor the projection to yet.
      final justAdoptedPath = existing.path == null && s.path != null;
      existing.path ??= s.path;
      if (s.heading != null) existing.heading = s.heading;

      final path = existing.path;
      if (path != null && path.isUsable) {
        // Project near where the vehicle was last, so a fix doesn't snap onto a
        // parallel/looped leg of the route a few metres away (F1). On the very
        // first path-tracked fix we have no such anchor, so project globally.
        final newDist = path.project(
          s.position,
          near: justAdoptedPath ? null : existing.toDist,
        );
        if (justAdoptedPath) {
          // Snap onto the route where the vehicle actually is instead of
          // sweeping the marker along the whole path from its origin.
          existing.fromDist = newDist;
          existing.toDist = newDist;
          existing.from = path.pointAt(newDist);
          existing.to = s.position;
          existing.lastMovedAt = at;
          continue;
        }
        final curDist = _lerpD(existing.fromDist, existing.toDist, currentT);
        if ((newDist - existing.toDist).abs() >= _stillMeters) {
          existing.lastMovedAt = at;
        }
        // Cap how far the marker advances toward the new fix this update so it
        // never teleports or races; the leftover is picked up next update, so
        // it catches up gradually and stays behind reality (#6).
        final advance = newDist - curDist;
        var target = newDist;
        if (advance > _snapMeters) {
          target = newDist; // backlog too large to be real — snap.
        } else if (advance > _maxAdvanceMeters) {
          target = curDist + _maxAdvanceMeters;
        }
        existing.fromDist = curDist;
        existing.toDist = target;
        existing.from = path.pointAt(curDist);
        existing.to = s.position;
      } else {
        if (!_isSamePlace(existing.to, s.position)) {
          existing.lastMovedAt = at;
        }
        existing.from = _interpolate(existing.from, existing.to, currentT);
        existing.to = s.position;
      }
    }

    // Grace period: age out vehicles missing from this update rather than
    // dropping them the instant they blink out of the feed (X6).
    for (final entry in _tracks.entries) {
      if (!seen.contains(entry.key)) entry.value.missingCount++;
    }
    _tracks.removeWhere(
      (key, t) => !seen.contains(key) && t.missingCount > _graceThreshold,
    );
  }

  /// Build or refresh a track's timed-trajectory player from a sample, returning
  /// whether timed mode is active afterwards. Needs a plan, its as-of time, and a
  /// usable route path projected onto the road geometry; without all three the
  /// track stays in (or falls back to) the conservative from/to ease.
  bool _applyTimedPlan(VehicleTrack track, VehicleSample s, DateTime at) {
    final plan = s.trajectory;
    final path = s.path;
    if (plan == null || plan.length < 2 || path == null || !path.isUsable || s.asOf == null) {
      return false;
    }
    final existing = track.timed;
    if (existing == null) {
      final built = TimedTrajectory.build(
        path: path,
        plan: plan,
        asOf: s.asOf!,
        now: at,
      );
      if (built == null) return false;
      track.timed = built;
      track.path = path;
    } else {
      // A failed re-projection leaves the previous plan playing rather than
      // dropping to a jump — timed mode stays active either way.
      if (existing.updatePlan(path: path, plan: plan, asOf: s.asOf!, now: at)) {
        track.path = path;
      }
    }
    // Only a plan that still projects motion counts as "moved" — a vehicle
    // parked at the end of its plan ages toward "looks stuck" as before.
    if (track.timed!.hasForwardMotion(at)) track.lastMovedAt = at;
    return true;
  }

  /// Step every timed track's displayed position forward to [now]. Called once
  /// per sampler tick by the map before it reads positions, so the per-frame
  /// advance happens exactly once (reads stay pure). No-op for tracks without a
  /// plan. Returns whether any timed track still has motion to render.
  bool advanceTimed(DateTime now) {
    var moving = false;
    for (final t in _tracks.values) {
      final timed = t.timed;
      if (timed == null) continue;
      timed.advance(now);
      if (timed.hasForwardMotion(now)) {
        moving = true;
        t.lastMovedAt = now;
      }
    }
    return moving;
  }

  /// Whether a vehicle currently reads as stuck (hasn't actually moved for at
  /// least [_stuckAfter]). Unknown keys are treated as moving.
  bool isStuck(String key) {
    final t = _tracks[key];
    if (t == null) return false;
    return _clock().difference(t.lastMovedAt) >= _stuckAfter;
  }

  /// Display opacity for a vehicle: fully opaque while present, then fading
  /// gently over the grace period once it goes missing rather than vanishing
  /// abruptly (X6).
  double opacityFor(String key) {
    final missing = _tracks[key]?.missingCount ?? 0;
    if (missing <= 0) return 1.0;
    const fade = <int, double>{1: 0.7, 2: 0.55, 3: 0.4};
    return fade[missing] ?? 0.28;
  }

  VehicleTrack? trackFor(String key) => _tracks[key];

  /// Whether any track still has motion left to play out toward its target —
  /// i.e. the display position differs from the latest real fix it eases toward.
  /// Drives "idle = zero frames" (thermal): when this is false there is nothing
  /// to animate, so the caller can leave the ticker stopped instead of spinning
  /// the marker layer at frame rate over a set of stationary vehicles.
  bool get hasPendingMotion {
    final now = _clock();
    for (final t in _tracks.values) {
      final timed = t.timed;
      if (timed != null) {
        if (timed.hasForwardMotion(now)) return true;
        continue; // a timed track's ease fields are stale — don't consult them
      }
      final path = t.path;
      if (path != null && path.isUsable) {
        if ((t.toDist - t.fromDist).abs() > _stillMeters) return true;
      } else if (!_isSamePlace(t.from, t.to)) {
        return true;
      }
    }
    return false;
  }

  /// Shift every track's "last moved" wall-clock time forward by [by]. Called on
  /// resume from a backgrounded tab: while hidden the app is frozen (no ticks,
  /// no polling), so that frozen span must not count toward the "looks stuck"
  /// heuristic — otherwise every vehicle would read stuck the moment the user
  /// comes back after a couple of minutes away.
  void shiftClock(Duration by) {
    if (by <= Duration.zero) return;
    for (final t in _tracks.values) {
      t.lastMovedAt = t.lastMovedAt.add(by);
    }
  }

  /// Drop every track immediately, bypassing the grace period — for a hard
  /// reset like zooming out past the vehicle layer, where holding stale markers
  /// would be wrong.
  void clear() => _tracks.clear();

  static bool _isSamePlace(ll.LatLng a, ll.LatLng b) =>
      (a.latitude - b.latitude).abs() < _stillEpsilon &&
      (a.longitude - b.longitude).abs() < _stillEpsilon;

  ll.LatLng positionOf(String key, double t) {
    final track = _tracks[key]!;
    final timed = track.timed;
    if (timed != null) return timed.position;
    final path = track.path;
    if (path != null && path.isUsable) {
      return path.pointAt(_lerpD(track.fromDist, track.toDist, t));
    }
    return _interpolate(track.from, track.to, t);
  }

  /// The heading to draw for a vehicle at animation time [t]: along the route
  /// tangent (matching the on-screen motion) when a path is known, else the
  /// provider-supplied fallback heading.
  double? headingAt(String key, double t) {
    final track = _tracks[key];
    if (track == null) return null;
    final timed = track.timed;
    if (timed != null) return timed.heading;
    final path = track.path;
    if (path != null && path.isUsable) {
      final cur = _lerpD(track.fromDist, track.toDist, t);
      // Smoothed bearing so the direction arrow turns continuously through a
      // curve rather than snapping at each ~15 m vertex (zigzag on the symbol
      // layer's offset arrow). Same look-ahead as the timed player.
      return path.headingAtSmoothed(cur, forward: track.toDist >= track.fromDist);
    }
    return track.heading;
  }

  Iterable<MapEntry<String, ll.LatLng>> currentPositions(double t) {
    return _tracks.keys.map((key) => MapEntry(key, positionOf(key, t)));
  }

  static double _lerpD(double from, double to, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    return from + (to - from) * clampedT;
  }

  static ll.LatLng _interpolate(ll.LatLng from, ll.LatLng to, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    return ll.LatLng(
      from.latitude + (to.latitude - from.latitude) * clampedT,
      from.longitude + (to.longitude - from.longitude) * clampedT,
    );
  }
}
