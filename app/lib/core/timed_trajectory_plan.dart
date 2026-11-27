part of 'timed_trajectory.dart';

// The plan side of [TimedTrajectory]: projecting a board's plan points onto the
// road shape, and the dwell-aware distance-vs-time shape between them. Pure
// maths, no displayed state; the player in timed_trajectory.dart rides it.

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
// Pause at a stop. Raised 3 s → 6 s (2026-07-18, owner call) to make the dwell
// read as a real halt. NOT 10 s: measured on real plans, a 10 s dwell squeezed
// the trapezoid's cruise into an implausible sprint (target hit ~158 m/s in
// tight segments) and re-tripped the catch-up oscillation / fake-standstill
// guards; 6 s keeps the drop-rate near the 3 s baseline and those guards green.
const double _dwellSeconds = 6.0;

// A station whose projection onto the route shape lands within this of its
// true position counts as "on the shape" — the shape reaches the stop, so a
// dwell there is truthful. Past it the shape doesn't cover the stop and the
// dwell is suppressed (see _buildSegments). Absorbs normal projection slack
// and stop-vs-shape offset without admitting the hundreds-of-metres misses of
// an uncovered variant.
// Calibration 2026-07-18 (по прод-замеру): стопы с проекцией 26-28 м — реальные
// стопы кривоватых shape, не мусор; 32 м покрывает эту жёлтую зону с запасом и
// при этом не дотягивается до 50 м+ выбросов по-настоящему неверного варианта.
const double _stopOnShapeToleranceMeters = 32.0;

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
const double _profileAccel = 1.2; // m/s², preferred

const double _maxProfileAccel = 2.5; // m/s², past this → even glide

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
const double _maxProfileSpeed = 16.7; // m/s ≈ 60 km/h

// Builds the per-segment shapes for a projected plan. Segment 0 starts at the
// vehicle's GPS — mid-block and already rolling — so it gets a flying start;
// every later segment starts at a stop and so opens with a dwell.
List<_Segment> _buildSegments(List<_Waypoint> wps) {
  final segs = <_Segment>[];
  for (var i = 0; i < wps.length - 1; i++) {
    final a = wps[i], b = wps[i + 1];
    // Shape only pauses/brakes at stops the shape actually reaches. If either
    // endpoint is off-shape (a variant the GTFS geometry doesn't cover), the
    // projection put the "stop" hundreds of metres from any real one — a dwell
    // or brake there would stop the marker where no stop exists. Glide it
    // instead: fewer pauses on those lines, but honest. (The track itself is
    // still wrong on those sections — a separate GTFS-shape fix, see the roadmap.)
    segs.add(
      _Segment.solve(
        t0: a.etaSeconds,
        t1: b.etaSeconds,
        d0: a.dist,
        d1: b.dist,
        flyingStart: i == 0,
        dwellSeconds: (a.onShape && b.onShape) ? _dwellSeconds : 0,
        shape: a.onShape && b.onShape,
        preferredAccel: _profileAccel,
        maxAccel: _maxProfileAccel,
        maxSpeed: _maxProfileSpeed,
      ),
    );
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

// Projects each plan point onto [path], keeping only strictly-forward,
// strictly-later waypoints (a projection can fold a point back on a looped
// route; a recomputed ETA can tie). Needs ≥2 to be usable.
List<_Waypoint>? _project(RoutePath path, List<TrajectoryPoint> plan) {
  if (!path.isUsable || plan.length < 2) return null;
  final wps = <_Waypoint>[];
  double? near;
  for (final p in plan) {
    final planPos = ll.LatLng(p.lat, p.lon);
    final d = path.project(planPos, near: near);
    near = d;
    // How far the projection had to move the station to land it on the shape.
    final offShape = const ll.Distance().as(
      ll.LengthUnit.Meter,
      planPos,
      path.pointAt(d),
    );
    final onShape = offShape <= _stopOnShapeToleranceMeters;
    final eta = p.etaSeconds.toDouble();
    if (wps.isEmpty) {
      wps.add(_Waypoint(d, eta, offShape, onShape));
      continue;
    }
    final last = wps.last;
    if (d > last.dist + TimedTrajectory._epsilonMeters &&
        eta > last.etaSeconds) {
      wps.add(_Waypoint(d, eta, offShape, onShape));
    }
  }
  return wps.length >= 2 ? wps : null;
}

double _elapsedSeconds(DateTime asOf, DateTime now) {
  final s = now.difference(asOf).inMicroseconds / 1e6;
  return s < 0 ? 0 : s;
}

// Distance for an elapsed time, clamped to the plan's ends: the containing
// segment's own shape (dwell → accelerate → cruise → brake into the stop).
double _distAtElapsed(
  List<_Segment> segs,
  List<_Waypoint> wps,
  double elapsed,
) {
  if (elapsed <= wps.first.etaSeconds) return wps.first.dist;
  if (elapsed >= wps.last.etaSeconds) return wps.last.dist;
  // Linear scan is fine: plans are short (≤ ~80 points).
  for (final s in segs) {
    if (elapsed <= s.t1) return s.distAt(elapsed);
  }
  return wps.last.dist;
}

class _Waypoint {
  const _Waypoint(
    this.dist,
    this.etaSeconds,
    this.offShapeMeters,
    this.onShape,
  );
  final double dist;
  final double etaSeconds;
  // How far projecting this station onto the route shape had to move it (for the
  // staging overlay), and whether that passed the on-shape tolerance. Small when
  // the shape passes through the stop; large (hundreds of m) when it doesn't
  // cover it (a route variant / bad geometry) — a dwell there would pause the
  // marker where no stop exists, so we glide such segments.
  final double offShapeMeters;
  final bool onShape;
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
  _Segment._(
    this.t0,
    this.t1,
    this.d0,
    this.d1,
    this.kind,
    this.dwell,
    this.v,
    this.accel,
  );

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
    required bool shape,
    required double preferredAccel,
    required double maxAccel,
    required double maxSpeed,
  }) {
    final t = t1 - t0;
    final d = d1 - d0;
    linear() =>
        _Segment._(t0, t1, d0, d1, _SegmentKind.linear, 0, 0, preferredAccel);
    // Off-shape endpoint: the shape doesn't reach this stop, so there is nothing
    // real to pause or brake at — glide straight through.
    if (!shape) return linear();
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
