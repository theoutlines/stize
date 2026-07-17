import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/trajectory_point.dart';
import 'route_path.dart';

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
  TimedTrajectory._(this._path, this._waypoints, this._segments, this._asOf,
      this._dispDist, this._lastAdvance);

  RoutePath _path;
  List<_Waypoint> _waypoints; // distance ↑, eta ↑; the first eta is ~0
  List<_Segment> _segments; // one per waypoint pair; the dwell-aware shape
  DateTime _asOf;
  double _dispDist;
  double _dispVel = 0; // displayed speed along the path (m/s) — a state variable
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

  // ---------------------------------------------------------------------------
  // Stop dwell — the shape of motion *between* two plan waypoints.
  //
  // Plan waypoints 1..N are the stations ahead of the vehicle (waypoint 0 is its
  // current GPS), and each carries the upstream's live "seconds until the vehicle
  // is there". That estimate already accounts for the vehicle stopping at the
  // stations along the way — so the time a dwell needs is *already in the plan's
  // budget*. Interpolating a segment linearly (what we did before) spends that
  // budget as an even glide that never stops, which is both less plausible and no
  // more honest: between two waypoints the plan asserts only the endpoints, so
  // the in-between shape is ours to choose either way.
  //
  // So: the waypoints — position *and* time — are inviolable, and the dwell only
  // reshapes the curve between them. The vehicle reaches stop k at eta[k] (real
  // data), dwells, drives on, and reaches stop k+1 at eta[k+1] (real data). Total
  // plan time cannot drift, by construction rather than by tuning, and none of
  // the honesty rules (the staleness gate, the distance horizon) are touched.
  //
  // Each segment gets a trapezoid speed profile — dwell, accelerate, cruise,
  // brake to a standstill exactly at the next stop. The braking matters: the
  // marker's own catch-up limiter only brakes *reactively*, so a profile that
  // cruised into a stop would sail ~24 m past it before pulling up. Making the
  // *target* brake into the stop is what puts the marker at the stop.
  //
  // Segment 0 (GPS → first stop ahead) is a special case: it gets no leading
  // dwell and a flying start, because waypoint 0 is wherever the vehicle happens
  // to be — mid-block, at speed. A fresh plan arrives every poll, so starting
  // segment 0 from rest would plant a fake standstill mid-block on every poll:
  // exactly the artefact this feature exists to remove.
  //
  // Tuning lives here and nowhere else.
  static const double _dwellSeconds = 3.0; // pause at a stop
  // Accel/brake rate for the *plan's* shape — a real bus figure, deliberately
  // far gentler than [_maxCatchUpAccel] (3.0), which is the marker's chase
  // dynamics and answers to smoothness, not realism. Keep the two apart.
  //
  // It's a *preference*, not a fixed rate, because a segment's geometry can
  // simply forbid it: covering 237 m in 27 s from a standstill to a standstill
  // needs ≥1.65 m/s² no matter how we shape it — at 1.2 even the best
  // (triangular) profile falls ~19 m short. A fixed gentle rate would therefore
  // silently drop every brisk segment back to the old even glide — the feature
  // quietly doing nothing exactly where the vehicle is moving fastest. So each
  // segment uses the gentlest rate that actually fits, starting from the
  // preference, and only gives up past [_maxProfileAccel] (a hard bus can pull
  // ~2.5 m/s²; beyond that we'd be animating a fiction).
  static const double _profileAccel = 1.2; // m/s², preferred
  static const double _maxProfileAccel = 2.5; // m/s², past this → even glide

  // Plausibility ceiling on the cruise speed a shaped segment may reach.
  //
  // A dwell's seconds have to come out of the segment, so the cruise between
  // stops is always a little faster than the even glide it replaces. On a calm
  // segment that's nothing (~6.0 → 6.4 m/s). But as a segment approaches the
  // accel limit its profile degenerates toward a triangle — no cruise at all,
  // just up and straight back down — whose peak runs to ~2× the segment average.
  // A brisk 230 m / 27 s hop then peaks near 69 km/h: a bus that rockets between
  // stops is no more believable than one that never stops at all, and we'd have
  // traded one implausibility for another. Past this ceiling the segment keeps
  // the old even glide instead.
  static const double _maxProfileSpeed = 16.7; // m/s ≈ 60 km/h

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

  // Builds the per-segment shapes for a projected plan. Segment 0 starts at the
  // vehicle's GPS — mid-block and already rolling — so it gets a flying start;
  // every later segment starts at a stop and so opens with a dwell.
  static List<_Segment> _buildSegments(List<_Waypoint> wps) {
    final segs = <_Segment>[];
    for (var i = 0; i < wps.length - 1; i++) {
      final a = wps[i], b = wps[i + 1];
      segs.add(_Segment.solve(
        t0: a.etaSeconds,
        t1: b.etaSeconds,
        d0: a.dist,
        d1: b.dist,
        flyingStart: i == 0,
        dwellSeconds: _dwellSeconds,
        preferredAccel: _profileAccel,
        maxAccel: _maxProfileAccel,
        maxSpeed: _maxProfileSpeed,
      ));
    }
    // A segment brakes to a standstill at its far end. That's only true if the
    // vehicle actually stands there — i.e. if the next segment starts from rest
    // (any trapezoid does; an even glide does not). Braking into a stop the next
    // segment then leaves at full speed strands the marker metres behind the
    // plan, and it makes the distance up with exactly the catch-up surge this
    // feature is meant to remove: measured at 52 km/h out of a stop whose plan
    // says 32. So where the next segment glides, this one glides too.
    //
    // The last segment has no successor to contradict it, and the marker clamps
    // at the plan's end anyway, so it keeps its braking.
    for (var i = segs.length - 2; i >= 0; i--) {
      if (segs[i].kind == _SegmentKind.linear) continue;
      if (segs[i + 1].kind == _SegmentKind.linear) segs[i] = segs[i].asGlide();
    }
    return segs;
  }

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
        ? math.min(_maxCatchUpSpeed,
            math.min(math.sqrt(2 * _maxCatchUpAccel * gap), _catchUpGain * gap))
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
    final v = (_gatedTarget(now.add(const Duration(milliseconds: 250))) -
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
      if ((dist - _waypoints[i].dist).abs() <= _stationRadiusMeters) return true;
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
    if (_dispDist >= _horizonDist - _epsilonMeters) return false;
    final elapsed = _targetElapsed(now);
    if (elapsed <= 0) return false; // stale board: settled at the fix
    return elapsed < _waypoints.last.etaSeconds; // plan not yet spent
  }

  // Projects each plan point onto [path], keeping only strictly-forward,
  // strictly-later waypoints (a projection can fold a point back on a looped
  // route; a recomputed ETA can tie). Needs ≥2 to be usable.
  static List<_Waypoint>? _project(RoutePath path, List<TrajectoryPoint> plan) {
    if (!path.isUsable || plan.length < 2) return null;
    final wps = <_Waypoint>[];
    double? near;
    for (final p in plan) {
      final d = path.project(ll.LatLng(p.lat, p.lon), near: near);
      near = d;
      final eta = p.etaSeconds.toDouble();
      if (wps.isEmpty) {
        wps.add(_Waypoint(d, eta));
        continue;
      }
      final last = wps.last;
      if (d > last.dist + _epsilonMeters && eta > last.etaSeconds) {
        wps.add(_Waypoint(d, eta));
      }
    }
    return wps.length >= 2 ? wps : null;
  }

  static double _elapsedSeconds(DateTime asOf, DateTime now) {
    final s = now.difference(asOf).inMicroseconds / 1e6;
    return s < 0 ? 0 : s;
  }

  // Distance for an elapsed time, clamped to the plan's ends: the containing
  // segment's own shape (dwell → accelerate → cruise → brake into the stop).
  static double _distAtElapsed(
      List<_Segment> segs, List<_Waypoint> wps, double elapsed) {
    if (elapsed <= wps.first.etaSeconds) return wps.first.dist;
    if (elapsed >= wps.last.etaSeconds) return wps.last.dist;
    // Linear scan is fine: plans are short (≤ ~80 points).
    for (final s in segs) {
      if (elapsed <= s.t1) return s.distAt(elapsed);
    }
    return wps.last.dist;
  }
}

class _Waypoint {
  const _Waypoint(this.dist, this.etaSeconds);
  final double dist;
  final double etaSeconds;
}

/// The distance-vs-time shape *within* one plan segment (waypoint k → k+1).
///
/// Both endpoints are fixed by the plan: the vehicle is at [d0] at [t0] and at
/// [d1] at [t1], whatever shape connects them. Three shapes, chosen at build
/// time so the per-frame read stays a couple of comparisons:
///
///   * **trapezoid** — dwell at the stop, accelerate, cruise, brake to a halt at
///     the next stop. The normal case.
///   * **flying** — cruise, then brake to a halt at the stop. Segment 0 only,
///     where the vehicle starts mid-block at speed.
///   * **linear** — the old even glide. The fallback for a segment whose
///     distance can't be covered in its time at [TimedTrajectory._profileAccel]
///     (an implausibly fast plan): rather than invent a shape that doesn't fit,
///     keep the previous behaviour for that segment.
enum _SegmentKind { linear, flying, trapezoid }

class _Segment {
  _Segment._(this.t0, this.t1, this.d0, this.d1, this.kind, this.dwell, this.v,
      this.accel);

  final double t0, t1; // plan times of the two waypoints (s, from as-of)
  final double d0, d1; // distances-along of the two waypoints (m)
  final _SegmentKind kind;
  final double dwell; // leading pause at waypoint k (s); 0 unless trapezoid
  final double v; // cruise speed (m/s); unused when linear
  final double accel; // accel/brake rate (m/s²); unused when linear

  /// Solves the shape for one segment. [flyingStart] picks the segment-0 profile
  /// (no dwell, already at speed); everything else gets a dwell + trapezoid, or
  /// degrades — first by dropping the dwell, then to linear — when the geometry
  /// can't be flown at [accel].
  static _Segment solve({
    required double t0,
    required double t1,
    required double d0,
    required double d1,
    required bool flyingStart,
    required double dwellSeconds,
    required double preferredAccel,
    required double maxAccel,
    required double maxSpeed,
  }) {
    final t = t1 - t0;
    final d = d1 - d0;
    linear() =>
        _Segment._(t0, t1, d0, d1, _SegmentKind.linear, 0, 0, preferredAccel);
    if (t <= 0 || d <= 0) return linear();

    if (flyingStart) {
      // Cruise at v, then brake to 0 over v/a, arriving at d1 exactly at t1:
      //   d = v·t − v²/(2a)  ⇒  v² − 2a·t·v + 2a·d = 0
      // Real iff a·t² ≥ 2d; the smaller root is the one whose cruise phase is
      // non-negative. Use the gentlest rate that fits.
      final a = math.max(preferredAccel, 2 * d / (t * t));
      if (a > maxAccel) return linear();
      final v = a * t - math.sqrt(math.max(0, a * a * t * t - 2 * a * d));
      if (v <= 0 || v > maxSpeed) return linear();
      return _Segment._(t0, t1, d0, d1, _SegmentKind.flying, 0, v, a);
    }

    // Dwell, then accelerate / cruise / brake across the remaining time t':
    //   d = v·t' − v²/a  ⇒  v² − a·t'·v + a·d = 0,  real iff a·t'² ≥ 4d.
    // Degrade in the order that keeps the most: pause at the gentlest rate that
    // fits → drop the pause (which buys back its seconds, so a gentler rate may
    // now fit) → even glide.
    for (final dwell in [dwellSeconds, 0.0]) {
      final tm = t - dwell;
      if (tm <= 0) continue;
      final a = math.max(preferredAccel, 4 * d / (tm * tm));
      if (a > maxAccel) continue;
      final v =
          (a * tm - math.sqrt(math.max(0, a * a * tm * tm - 4 * a * d))) / 2;
      if (v <= 0 || v > maxSpeed) continue;
      return _Segment._(t0, t1, d0, d1, _SegmentKind.trapezoid, dwell, v, a);
    }
    return linear();
  }

  /// This segment reshaped as the plain even glide — used when the segment ahead
  /// turns out to glide, so this one must not brake into a stop the vehicle
  /// doesn't actually stand at.
  _Segment asGlide() =>
      _Segment._(t0, t1, d0, d1, _SegmentKind.linear, 0, 0, accel);

  /// Distance-along at [elapsed], which the caller has already placed inside
  /// [t0]..[t1].
  double distAt(double elapsed) {
    final rel = elapsed - t0;
    if (rel <= 0) return d0;
    if (elapsed >= t1) return d1;
    switch (kind) {
      case _SegmentKind.linear:
        return d0 + (d1 - d0) * (rel / (t1 - t0));
      case _SegmentKind.flying:
        final brake = v / accel;
        final remaining = t1 - elapsed;
        if (remaining <= brake) return d1 - 0.5 * accel * remaining * remaining;
        return d0 + v * rel;
      case _SegmentKind.trapezoid:
        if (rel <= dwell) return d0; // standing at the stop
        final tau = rel - dwell; // time since pulling away
        final ramp = v / accel;
        if (tau <= ramp) return d0 + 0.5 * accel * tau * tau;
        final remaining = t1 - elapsed;
        if (remaining <= ramp) return d1 - 0.5 * accel * remaining * remaining;
        return d0 + 0.5 * v * ramp + v * (tau - ramp);
    }
  }
}
