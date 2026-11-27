import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/trajectory_point.dart';
import 'route_path.dart';

part 'timed_trajectory_plan.dart';

/// A time-driven player over a vehicle's forward timing plan (the backend
/// `trajectory`: where the vehicle will be and when, anchored at an as-of time),
/// projected onto the route's road geometry.
///
/// It turns "as-of time + planned (position, eta) waypoints" into a *displayed*
/// distance-along the route at any wall-clock instant. Three guarantees, taken
/// from the reference behaviour and the owner's brief:
///   * **Forward only.** The displayed distance is monotonic non-decreasing —
///     a fresher plan that recalculates ETAs shorter or longer never rewinds the
///     marker. When the plan says the vehicle is *behind* where the marker
///     already shows (we overran), the marker holds and waits instead of
///     reversing.
///   * **No teleport.** When a new plan puts the vehicle further ahead, the
///     marker converges smoothly (exponential approach) rather than snapping.
///   * **Never past the plan.** The displayed distance is clamped to the plan's
///     final waypoint, so the marker never runs beyond the last known point.
///
/// Pure and widget-free so it can be unit-tested without a map. All time comes
/// in as arguments, so tests drive it with a virtual clock.
class TimedTrajectory {
  TimedTrajectory._(
    this._path,
    this._waypoints,
    this._segments,
    this._asOf,
    this._dispDist,
    this._lastAdvance,
  );

  RoutePath _path;
  List<_Waypoint> _waypoints; // distance ↑, eta ↑; the first eta is ~0
  List<_Segment> _segments; // one per waypoint pair; the dwell-aware shape
  DateTime _asOf;
  double _dispDist;
  double _dispVel =
      0; // displayed speed along the path (m/s) — a state variable
  DateTime _lastAdvance;

  // Catch-up dynamics. The marker chases the plan's *predicted-now* spot, which
  // moves forward at the plan's own speed. To close the residual gap without the
  // periodic lurch an exponential approach produced (its velocity is maximal at
  // the instant each poll reveals the gap → a velocity step = a visible jerk),
  // the closing motion is acceleration-limited and velocity-continuous:
  //
  //   * The marker rides the plan speed as a *feed-forward* term, so once caught
  //     up it tracks the ramp with ~zero lag and no fresh gap re-appears each
  //     poll (which is what re-triggered the jerk).
  //   * On top of that it closes the position gap at a speed that is capped
  //     ([_maxCatchUpSpeed], an even cruise) and eased down to zero as it arrives
  //     (a sqrt profile → decelerate at [_maxCatchUpAccel], no jolt on arrival).
  //   * Velocity itself may change by at most [_maxCatchUpAccel]·dt per step, so
  //     it eases *in* when a gap appears and can never step discontinuously — the
  //     jerk is gone by construction (bounded acceleration ⇒ continuous velocity).
  //
  // Tuned for a transit marker: ~3 m/s² feels smooth (not a snap, not a crawl),
  // and an 18 m/s cap recovers even a large stale-recovery gap in a few seconds
  // while never cruising implausibly fast.
  static const double _maxCatchUpAccel = 3.0; // m/s²
  static const double _maxCatchUpSpeed = 18.0; // m/s, closing speed cap
  // Small-gap closing gain (1/s): the marker closes a residual gap on a ~0.5 s
  // time constant. Bounds the loop's gain where the sqrt profile's would run to
  // infinity, which is what let it chatter at a standstill-close gap.
  static const double _catchUpGain = 2.0;

  // A plan step shorter than this (metres) isn't worth treating as motion.
  static const double _epsilonMeters = 0.5;

  // Below this plan speed the vehicle counts as standing still (≈1 km/h). Used
  // by [hasForwardMotion] — the ticker, the stuck heuristic and the spiderfy
  // gate. Well under any real service speed, and every case that must read as
  // stopped (a stale board, the plan's end, the horizon) puts the target's speed
  // at exactly zero, so nothing sits near this threshold in practice.
  static const double _minMotionSpeed = 0.3; // m/s

  // How close to a station the marker must be for a standstill to be truthful,
  // and how much of the plan's speed it keeps when it must wait somewhere else.
  //
  // The marker can be held back anywhere: a fresh fix routinely lands *behind*
  // where a 30 s prediction had drawn it (the upstream's ETAs are optimistic, so
  // the plan runs ahead of the real vehicle), and forward-only forbids rewinding.
  // Measured on a real line-5 plan whose vehicle runs 20% slow: the marker froze
  // for 6.8 s at 42 m from the nearest stop, and 27 s at 35% slow. Pre-existing —
  // main does the same, and worse (it also froze 50–88 m out on an *on-plan*
  // vehicle) — but harmless until stop dwells made a standstill mean something.
  static const double _stationRadiusMeters = 20.0;
  static const double _crawlFraction = 0.25;

  // Glide-out at the end of the known plan. When the plan's predicted-now spot
  // reaches the horizon (the plan is spent, or the 900 m extrapolation cap binds)
  // while the marker is still moving — a late board is the common case, its median
  // gap under 2 s — the marker used to hard-zero its speed at the horizon, a
  // visible halt-колом on the перегон. Instead it bleeds the residual speed to
  // rest with an exponential decay: the last metres of the plan, presented
  // smoothly. The marker approaches the horizon from behind and never predicts
  // past it, so this is presentation, not route extrapolation; a fresh board
  // clears the glide and the PRESERVED _dispVel resumes the chase with continuous
  // velocity (the contour's C1 contract). If no board comes it reaches rest and
  // honestly stops (PLAN_END, as before). A modeled stop the trapezoid brakes
  // into is NOT a glide: there the marker is already at rest (_dispVel ≈ 0), the
  // guard below skips it, and the dwell stands. Staleness is untouched — a stale
  // board still hard-holds at the fix.
  //
  // τ ≈ 0.7 s eases a typical 3–10 m/s cruise to rest in ~2–2.5 s (t = τ·ln(v/vₑ)).
  // The marker coasts forward along the route while it decays, a bounded few metres
  // past the plan's last point — the decay itself limits the distance (∫v·e^{-t/τ}
  // = v·τ, ~7 m for a 10 m/s cruise); [_glideCoastMeters] is only a hard safety cap
  // so a freak speed can't run the marker away past the end.
  static const double _glideTauSeconds = 0.7; // exponential decay time constant
  static const double _glideRestSpeed =
      0.2; // m/s; at/below this the glide is done
  static const double _glideCoastMeters =
      20.0; // hard cap on coast past the plan end
  // How close to the horizon the marker enters the glide — the "last N metres" of
  // the brief. Must exceed one frame's travel so a fast approach can't leap the
  // horizon in a single step and skip the decay (18 m/s cap × a coarse 0.25 s tick
  // ≈ 4.5 m); the display ticks far finer in practice.
  static const double _glideEnterMeters = 6.0;

  // Continuous prediction while the board is fresh, hard-stopped once it isn't.
  //
  // The plan is a forward (position, eta) table anchored at `as_of`; the marker
  // chases `plan[now - as_of]` — the vehicle's *predicted current* spot — so on
  // healthy 30s data it moves continuously across the whole poll interval (the
  // reference apps do exactly this) instead of leading a short bridge and then
  // sitting until the next batch, which read as the whole city freezing and
  // reviving in lockstep.
  //
  // The upstream board's `as_of` can go badly stale (upstream 503s under load →
  // SWR serves a frozen board, so `now - as_of` grows unbounded). Predicting
  // that unbounded gap from a frozen anchor is exactly what made markers "fly
  // while the vehicle is parked". The defence is NOT a short prediction window —
  // it's the [_stalenessSeconds] gate: while the fix is fresh we predict the
  // full elapsed time; once it's older than the gate (the board isn't
  // refreshing) we stop predicting and hold at the fix. The gate (45s) sits
  // above the 30s poll cadence, so healthy data never touches it (continuous
  // motion) while a frozen board is caught within one gate-width (hold, never
  // fly). [_maxAheadMeters] is the matching distance belt — the furthest the
  // marker may lead within that window, so an implausibly fast plan can't
  // outrun the gate.
  static const double _stalenessSeconds = 45;
  static const double _maxAheadMeters = 900;

  // The elapsed time used to place the *target* along the plan: the full time
  // since the fix while it's fresh (continuous prediction), and zero (sit at the
  // fix) once it's stale. This — not the raw `now - as_of` used unconditionally —
  // is what the marker chases, so a stale/frozen board can't fly it forward: the
  // moment the fix ages past the gate the target collapses back to the fix and
  // the forward-only [advance] simply holds (never lurches or rewinds).
  double _targetElapsed(DateTime now) => _gatedElapsed(_asOf, now);

  static double _gatedElapsed(DateTime asOf, DateTime now) {
    final age = _elapsedSeconds(asOf, now);
    if (age > _stalenessSeconds) return 0; // stale board: don't predict, hold
    return age; // fresh board: predict the full elapsed time (continuous)
  }

  /// Builds a player, or null when the plan/path can't form a usable monotone
  /// distance-vs-time table (needs a usable path and ≥2 strictly-forward points).
  static TimedTrajectory? build({
    required RoutePath path,
    required List<TrajectoryPoint> plan,
    required DateTime asOf,
    required DateTime now,
  }) {
    final wps = _project(path, plan);
    if (wps == null) return null;
    // Appear at the *predicted current* spot — the fix (plan point 0) projected
    // forward by the gated elapsed time — so a vehicle entering the viewport
    // mid-interval shows up where it actually is, not at a stale GPS point it
    // then races to catch up to (a visible forward lurch on every appearance,
    // worse the wider the prediction window). The gate keeps this honest: a
    // stale board (age past the gate) projects zero, so it still appears AT the
    // fix and holds — never flying in from a frozen anchor. Bounded to the
    // distance horizon as a belt against an implausibly fast plan.
    final segs = _buildSegments(wps);
    final gated = _gatedElapsed(asOf, now);
    var dispDist = _distAtElapsed(segs, wps, gated);
    final horizon = wps.first.dist + _maxAheadMeters;
    if (dispDist > horizon) dispDist = horizon;
    return TimedTrajectory._(path, wps, segs, asOf, dispDist, now);
  }

  /// Adopts a fresher plan without ever moving the marker backward: the current
  /// displayed distance is preserved (only clamped down if the new plan is
  /// shorter than where we already are). Returns false — leaving the old plan
  /// untouched — when the new plan can't be projected.
  bool updatePlan({
    required RoutePath path,
    required List<TrajectoryPoint> plan,
    required DateTime asOf,
    required DateTime now,
  }) {
    final wps = _project(path, plan);
    if (wps == null) return false;
    // When the *geometry itself* changes — the plan-point fallback upgrading to
    // the road shape, or a fresh fallback path — a raw distance-along on the old
    // path means nothing on the new one. Capture the current geographic position
    // first and re-anchor onto the new geometry at the same spot, so the upgrade
    // is seamless instead of jumping. Same-path updates keep the shown distance
    // (monotonic, never rewind).
    final pathChanged = !identical(path, _path);
    final ll.LatLng? geoBefore = pathChanged ? position : null;
    _path = path;
    _waypoints = wps;
    _segments = _buildSegments(wps);
    _asOf = asOf;
    _lastAdvance = now;
    if (geoBefore != null) {
      _dispDist = path.project(geoBefore);
    }
    // Never rewind: keep the shown distance, only clamp into the new plan's end.
    final end = wps.last.dist;
    if (_dispDist > end) _dispDist = end;
    return true;
  }

  /// Advances the displayed distance toward where the plan says the vehicle is
  /// *now*. Forward-only: holds (never reverses) when the plan is behind the
  /// marker, converges smoothly when it's ahead, clamps at the plan's end.
  ///
  /// The motion is acceleration-limited and velocity-continuous (see the class
  /// notes): it rides the plan speed as a feed-forward term and closes any
  /// residual gap with an eased, capped closing speed, so it never lurches.
  void advance(DateTime now) {
    final horizon = _horizonDist;
    final target = _gatedTarget(now);
    final dt = now.difference(_lastAdvance).inMicroseconds / 1e6;
    _lastAdvance = now;
    if (dt <= 0) return;

    // Feed-forward: how fast the *target itself* is moving right now (0 when the
    // board is stale — the target is pinned to the fix — or when it has reached
    // the horizon/plan end). Measured on the same gated model so all those
    // hold-cases fall out automatically.
    final planVel = _targetSpeed(now);

    // Glide-out: the plan no longer carries us forward (its spot has reached the
    // horizon) but the marker still has speed. Ease it to rest with an exponential
    // decay instead of the hard zero this used to do at the horizon (see the
    // constants). Preempts the catch-up law entirely for these frames; _dispVel is
    // never stepped discontinuously, so a fresh board that clears the glide resumes
    // the chase velocity-continuously.
    if (_isGliding(now)) {
      _dispVel *= math.exp(-dt / _glideTauSeconds);
      if (_dispVel < _glideRestSpeed) _dispVel = 0;
      var next = _dispDist + _dispVel * dt;
      // Coast a bounded distance past the plan's last point along the route shape;
      // the decay is the real limiter, the cap is only a safety belt. Forward-only
      // (the normal path's guard) then keeps this coasted position — it never
      // rewinds back to the horizon when the glide comes to rest.
      final coastCap = horizon + _glideCoastMeters;
      if (next > coastCap) {
        next = coastCap;
        _dispVel = 0;
      }
      _dispDist = next;
      return;
    }

    // Target speed for this frame: ride the plan speed, plus a term that erases
    // the position gap — eased so arrival has no jolt (cruise at the cap when
    // far, sqrt ramp-down when near → decelerate at _maxCatchUpAccel).
    //
    // This law must stay CONTINUOUS in `gap`, and the feed-forward must survive
    // at gap≈0. It used to do neither: within [_epsilonMeters] (0.5 m) of the
    // target it commanded a dead stop, throwing the plan's speed away.
    //
    // That cliff fired on EVERY frame. Tracking perfectly does not mean gap==0:
    // `target` is read at the end of the step, so a marker exactly on plan sits
    // one frame behind it — gap settles at planVel·dt, which at 60 fps and a
    // 1.3 m/s tram is ~22 mm, forever under the 0.5 m cliff. So the marker
    // braked, fell behind, crossed the epsilon, sprinted back, arrived, braked:
    // a limit cycle, gap pinned at the epsilon, speed sawing between ~0 and ~2×
    // the plan. Every trough on a slow segment reaches zero, so the marker also
    // appears to *stop mid-block*, at no stop at all — which is exactly the
    // "markers freeze somewhere random" this looked like a data problem.
    // Measured on a real line-5 plan (real GTFS shape, real 30 s refresh, frame
    // resolution) over a flat-cruise window: marker 0.00–4.68 m/s with 89
    // near-zero frames, against a plan asking for a steady 3.1 then 1.31.
    final gap = target - _dispDist;
    // Ahead of us: ease in and close it. Behind us (we overran): pull back
    // gently, never past a standstill — the marker waits, it never reverses.
    //
    // Near zero the law has to be *proportional*, not sqrt: sqrt's slope is
    // infinite at gap→0, so a hair of overshoot commands a disproportionate
    // correction and the loop chatters against the acceleration limiter (27% of
    // plan speed, measured, with the gap already at ~1 mm). So take whichever
    // term is gentler — proportional close in (finite gain, ~0.5 s constant),
    // the sqrt braking profile further out where it's the one that matters.
    //
    // Behind us, the pull-back may cancel the plan speed outright and stop the
    // marker dead — but only where a standstill is *true*. A stopped marker says
    // "this vehicle is at a stop", and mid-block that is a lie, now more than
    // ever: with stop dwells rendered, a standstill is how the map says "stop".
    // So off-station the pull-back is floored short of a standstill and the
    // marker crawls instead. It still converges — the plan closes the gap at its
    // own speed while the marker gives up [_crawlFraction] of it — and "slowing
    // down" is an honest picture of what is happening: the fresh fix put the
    // vehicle behind where we had drawn it, and forward-only forbids rewinding,
    // so the marker waits for the plan to catch up. Waiting is right; freezing
    // mid-block is the wrong way to show it.
    //
    // The floor never invents motion: it scales with planVel, so a plan that is
    // itself stopped (a dwell, a stale board) still holds the marker still.
    final holdFloor = gap < 0 && !_nearStation(_dispDist)
        ? -(1 - _crawlFraction) * planVel
        : -planVel;
    final closing = gap > 0
        ? math.min(
            _maxCatchUpSpeed,
            math.min(math.sqrt(2 * _maxCatchUpAccel * gap), _catchUpGain * gap),
          )
        : math.max(_catchUpGain * gap, holdFloor);
    double desiredVel = planVel + closing;
    // Never *command* a speed that would fly past the target in one step. Since
    // `target` is the end-of-step position, that ceiling is exactly gap/dt — and
    // it is not a throttle: in steady tracking gap IS planVel·dt, so gap/dt is
    // the plan speed. It also lands coarse (test-sized) steps on the target.
    if (gap > 0 && desiredVel > gap / dt) desiredVel = gap / dt;
    if (desiredVel < 0) desiredVel = 0;

    // Acceleration limit — the velocity may change by at most _maxCatchUpAccel·dt
    // per step. This is the ease-in when a gap appears and guarantees a
    // continuous velocity (no step ⇒ no jerk). One update only, so |Δv| is truly
    // bounded. Never negative (forward-only).
    final maxDv = _maxCatchUpAccel * dt;
    _dispVel += (desiredVel - _dispVel).clamp(-maxDv, maxDv);
    if (_dispVel < 0) _dispVel = 0;

    var next = _dispDist + _dispVel * dt;
    if (next >= horizon) {
      next = horizon;
      _dispVel = 0;
    }
    if (next < _dispDist) {
      next = _dispDist; // forward-only: hold when the plan is behind us
      _dispVel = 0;
    }
    _dispDist = next;
  }

  // The gated, horizon-clamped target distance the marker chases at [now].
  double _gatedTarget(DateTime now) {
    final t = _distAtElapsed(_segments, _waypoints, _targetElapsed(now));
    final horizon = _horizonDist;
    return t > horizon ? horizon : t;
  }

  // The target's own forward speed (m/s) at [now], via a short finite difference
  // on the same gated model — automatically 0 when stale or clamped (nothing to
  // feed forward), non-negative otherwise.
  double _targetSpeed(DateTime now) {
    const eps = 0.25; // s
    final v =
        (_gatedTarget(now.add(const Duration(milliseconds: 250))) -
            _gatedTarget(now)) /
        eps;
    return v > 0 ? v : 0;
  }

  /// The distance the plan puts the vehicle at, at [now] — the curve the marker
  /// chases, before any chase dynamics. Exposed so tests can compare the plan
  /// against the marker directly instead of inferring one from the other.
  @visibleForTesting
  double targetDistanceAt(DateTime now) => _gatedTarget(now);

  /// The plan's own speed at [now] (m/s) — what the marker feeds forward. Paired
  /// with [displaySpeed] in the staging overlay, it separates a jittery *plan*
  /// from a jittery *chase loop*.
  double planSpeed(DateTime now) => _targetSpeed(now);

  // Whether the marker is coasting out the end of the plan right now: the plan's
  // predicted-now spot has reached the horizon (spent, or the extrapolation cap)
  // so it no longer feeds motion forward, yet the marker still carries speed to
  // bleed. Excludes a stale board (held at the fix) and a marker already at rest
  // (a modeled stop the trapezoid braked into — the dwell stands, no glide).
  bool _isGliding(DateTime now) {
    if (isStale(now)) return false;
    if (_dispVel <= _glideRestSpeed) return false;
    // The plan no longer carries us forward — its predicted-now spot has reached
    // the horizon (spent, or the 900 m extrapolation cap), so its feed-forward
    // speed is ~0 — and the marker, within the last N metres of that horizon, is
    // still moving. That is the plan running out under a still-cruising marker: the
    // hard-zero here was the halt-колом. The rest-speed guard above means a marker
    // that arrived at rest (a trapezoid-braked stop) does NOT glide — the dwell
    // stands. Deliberately NOT the marker OVERRUNNING the plan into its last stop
    // while the plan still has time (planVel > 0): that is the separate OVERRAN
    // phenomenon (a fresh board landed the vehicle behind the marker), out of this
    // change's scope.
    return _targetSpeed(now) <= _minMotionSpeed &&
        _dispDist >= _horizonDist - _glideEnterMeters;
  }

  /// Whether the marker is gliding to rest at the end of the known plan (see
  /// [_isGliding]) — a distinct state from a mid-block catch-up standstill, so the
  /// staging overlay can name it (GLIDE-END) rather than a contour fault.
  bool isGliding(DateTime now) => _isGliding(now);

  /// Per-stop gate diagnostics for the staging overlay: the next [count] plan
  /// stations ahead of the marker, each with how far the shape projection moved
  /// it (m), whether that passes the on-shape tolerance, whether the segment
  /// leaving it dwells or glides, and how far ahead it is (m). Lets the owner see
  /// on screen exactly what the pause gate decided for a followed vehicle.
  List<({double aheadM, double offShapeM, bool onShape, bool dwells})>
  upcomingStopDiag({int count = 3}) {
    final out =
        <({double aheadM, double offShapeM, bool onShape, bool dwells})>[];
    for (var i = 0; i < _waypoints.length && out.length < count; i++) {
      final wp = _waypoints[i];
      final ahead = wp.dist - _dispDist;
      if (ahead < -5) continue; // already behind the marker
      out.add((
        aheadM: ahead,
        offShapeM: wp.offShapeMeters,
        onShape: wp.onShape,
        // The dwell (if any) happens at the START of the segment leaving this
        // station; a glided segment has dwell 0.
        dwells: (i < _segments.length ? _segments[i].dwell : 0) > 0,
      ));
    }
    return out;
  }

  double get displayDistance => _dispDist;
  double get endDistance => _waypoints.last.dist;

  /// Displayed speed along the path (m/s) — a diagnostics read-out for the
  /// catch-up instrumentation (staging overlay).
  double get displaySpeed => _dispVel;

  /// The as-of time of the board this plan came from. Lets the caller keep the
  /// freshest of several boards for the same vehicle.
  DateTime get boardAsOf => _asOf;

  /// Age of the board this plan came from at [now] (s) — the `now − as_of` the
  /// staleness gate is measured on. A read-out for the staging overlay: it's the
  /// quantity that decides when the marker stops predicting and holds.
  double boardAgeSeconds(DateTime now) => _elapsedSeconds(_asOf, now);

  /// Whether the board has aged past the staleness gate at [now] — i.e. the
  /// marker has stopped predicting and is holding wherever it stood.
  bool isStale(DateTime now) => boardAgeSeconds(now) > _stalenessSeconds;

  /// How far behind the plan's predicted-now spot the marker currently is (m,
  /// never negative) — the live "catch-up distance" for the staging overlay.
  double catchUpGap(DateTime now) {
    final gap = _gatedTarget(now) - _dispDist;
    return gap > 0 ? gap : 0;
  }

  // The furthest distance-along the marker may predict to right now: the plan's
  // end, but no more than [_maxAheadMeters] past the last fix (waypoint 0). Keeps
  // extrapolation restrained when fresh fixes stop coming.
  double get _horizonDist {
    final byDistance = _waypoints.first.dist + _maxAheadMeters;
    final end = endDistance;
    return byDistance < end ? byDistance : end;
  }

  // Whether [dist] is close enough to one of the plan's stations for a
  // standstill there to be honest. Waypoint 0 is the vehicle's GPS, not a
  // station, so it doesn't count.
  bool _nearStation(double dist) {
    for (var i = 1; i < _waypoints.length; i++) {
      if ((dist - _waypoints[i].dist).abs() <= _stationRadiusMeters)
        return true;
    }
    return false;
  }

  ll.LatLng get position => _path.pointAt(_dispDist);
  // Smoothed (look-ahead) bearing: turns continuously through a curve so the
  // direction arrow rotates smoothly instead of snapping vertex-to-vertex (which
  // reads as a zigzag on a road-accurate, ~15 m-spaced GTFS shape).
  double get heading => _path.headingAtSmoothed(_dispDist, forward: true);

  /// Whether the plan is carrying the vehicle forward at [now] — the "is it
  /// actually going somewhere" question, which is what the "looks stuck"
  /// heuristic wants. A vehicle standing at a stop is, correctly, not moving.
  /// Use [isPlaying] for the ticker and the spiderfy gate: those must count a
  /// stop dwell as motion-in-progress, not as a parked vehicle.
  ///
  /// False once the plan has run out, the horizon is reached, or the board went
  /// stale — in each case the target stops advancing, so its speed is zero.
  ///
  /// Ask the PLAN's speed, never the marker's distance from the target. That
  /// distance is not "how far it has left to go": `target` is read at the end of
  /// the step, so a marker tracking perfectly still sits one frame behind it —
  /// the gap settles at planVel·dt, ~22 mm at 60 fps. Tested against
  /// [_epsilonMeters] (0.5 m) that reports a perfectly-moving vehicle as
  /// *stopped*, on every frame.
  ///
  /// Which is exactly what has been happening. `c5f4547` built pass-through
  /// spiderfy on this predicate when it meant "the plan still has time to run";
  /// `8dab5e9` re-pointed it at the instantaneous gap a day later to serve the
  /// ticker's settle-detection. One predicate, two meanings. Moving vehicles
  /// have read as stationary ever since — and fan apart, which is the contract
  /// this was supposed to enforce. It survived only because the catch-up limit
  /// cycle (fixed alongside) swung the gap across the epsilon a few times a
  /// second, flipping this true often enough to keep the ticker alive and the
  /// fan flickering: markers shoving apart and snapping back as they converge.
  bool hasForwardMotion(DateTime now) {
    if (_isGliding(now))
      return true; // coasting out the plan end IS moving forward
    if (_dispDist >= _horizonDist - _epsilonMeters) return false;
    return _targetSpeed(now) > _minMotionSpeed;
  }

  /// Whether the plan still has anything to render at [now] — motion, or a stop
  /// dwell, or the braking and pulling-away either side of one. Drives the
  /// ticker and the spiderfy gate.
  ///
  /// It has to differ from [hasForwardMotion], in both directions:
  ///   * Park the ticker on a dwell and nothing is left running to end it — the
  ///     three-second pause becomes a permanent freeze. Invisible on a busy map
  ///     (some other vehicle keeps the ticker alive), fatal with a single
  ///     followed one.
  ///   * Fan a dwelling vehicle out and it gets shoved aside on arrival and
  ///     snaps back as it pulls away — a lurch at every stop, which is exactly
  ///     the churn the pass-through spiderfy contract exists to prevent. A dwell
  ///     is stillness that resolves itself; only a genuinely parked vehicle
  ///     (stale board, plan exhausted) is stationary in the sense spiderfy means.
  ///
  /// Deliberately not "speed ≈ 0 or dwelling": the approach to a stop dips under
  /// [_minMotionSpeed] for a fraction of a second *before* the dwell begins, and
  /// that sliver would flicker the fan on and straight back off. The honest test
  /// is simply whether the plan is still live and unfinished. "Idle = zero
  /// frames" is intact — a stale board and a spent plan both still park it.
  bool isPlaying(DateTime now) {
    if (_isGliding(now))
      return true; // keep the ticker alive through the glide-out
    if (_dispDist >= _horizonDist - _epsilonMeters) return false;
    // Gate on staleness, NOT on `elapsed <= 0`. `_targetElapsed` returns 0 in
    // TWO cases: a stale board (held at the fix — correctly not playing) AND a
    // *fresh* board whose age is ~0 (it just landed). Conflating them froze the
    // marker for the frame a fresh board arrived — the ticker parked
    // (hasPendingMotion=false) and it sat mid-block until the next event, even
    // though its brand-new plan was ready to carry it. Ask staleness directly.
    if (isStale(now)) return false; // stale board: held at the fix
    return _targetElapsed(now) < _waypoints.last.etaSeconds; // plan not spent
  }
}
