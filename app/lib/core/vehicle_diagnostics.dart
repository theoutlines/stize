import 'timed_trajectory.dart';

/// Text lines for the staging-only map diagnostics overlay (see
/// `DiagnosticsOverlay`). Pure functions of the followed vehicle's timing
/// player, so they can be read and tested without a map. Each returns a dash
/// form when nothing is being followed.

/// The followed vehicle's catch-up: live gap (metres behind the plan's
/// predicted-now spot), the plan's own speed against the marker's, and the live
/// board age. Tracking is healthy when `plan` and `vel` sit on top of each other
/// with gap ≈ 0: `vel` swinging around a steady `plan` means the catch-up loop
/// oscillates, both swinging together means the plan does. `HOLD` means the
/// board passed 45 s, so the marker stopped predicting and stands still.
String catchUpDiagLine(TimedTrajectory? timed, DateTime now) {
  if (timed == null) return 'VEH catchUp gap - plan - vel - age -';
  final age = timed.boardAgeSeconds(now);
  return 'VEH catchUp gap ${timed.catchUpGap(now).toStringAsFixed(2)}m '
      'plan ${timed.planSpeed(now).toStringAsFixed(2)} '
      'vel ${timed.displaySpeed.toStringAsFixed(2)}m/s '
      'age ${age.toStringAsFixed(0)}s${timed.isStale(now) ? " HOLD" : ""}';
}

/// The pause gate's decision for the next few stops, so the owner sees WHY a
/// pause fires (or doesn't): `+42m` ahead, projection moved off its true spot
/// by `off8m`, on/off-shape, and DWELL vs glide.
String dwellDiagLine(TimedTrajectory? timed) {
  if (timed == null) return 'VEH dwell -';
  final stops = timed.upcomingStopDiag();
  if (stops.isEmpty) return 'VEH dwell (no stops ahead)';
  final parts = stops.map(
    (s) =>
        '+${s.aheadM.toStringAsFixed(0)}m off${s.offShapeM.toStringAsFixed(0)}m '
        '${s.onShape ? "on" : "OFF"}→${s.dwells ? "DWELL" : "glide"}',
  );
  return 'VEH dwell ${parts.join("  ")}';
}

/// The followed marker's standstill, explained as an event: once its display
/// speed drops below 0.5 m/s, name the cause. Mutually exclusive, in order:
///   HOLD      the board is stale (>45 s): pinned to the last fix on purpose.
///   GLIDE-END coasting to rest at the plan's end while a late board buffers.
///   spent     the plan is exhausted (end or distance horizon reached).
///   DWELL     the plan itself predicts a standstill here: a real stop pause.
///   CONTOUR   the plan still moves but the marker doesn't: a catch-up fault
///             (a mid-block standstill with no dwell).
String stopCauseDiagLine(TimedTrajectory? timed, DateTime now) {
  if (timed == null) return 'VEH stopWhy -';
  final vel = timed.displaySpeed;
  final pos = timed.position;
  final at =
      '@${pos.latitude.toStringAsFixed(5)},'
      '${pos.longitude.toStringAsFixed(5)}';
  if (vel >= 0.5) return 'VEH stopWhy moving ${vel.toStringAsFixed(2)}m/s';
  final plan = timed.planSpeed(now);
  final gap = timed.catchUpGap(now);
  final ahead = timed.upcomingStopDiag(count: 1);
  final near = ahead.isEmpty ? null : ahead.first;
  final String cause;
  if (timed.isStale(now)) {
    cause =
        'HOLD stale board '
        '(age ${timed.boardAgeSeconds(now).toStringAsFixed(0)}s>45) — pinned to fix';
  } else if (timed.isGliding(now)) {
    cause =
        'GLIDE-END coasting to rest at plan end '
        '(vel ${vel.toStringAsFixed(2)}m/s, buffering a late board)';
  } else if (!timed.isPlaying(now)) {
    cause = 'plan spent (end/horizon reached)';
  } else if (plan < 0.5) {
    cause = near == null
        ? 'DWELL: plan standstill (no stop info)'
        : 'DWELL: plan stopped +${near.aheadM.toStringAsFixed(0)}m '
              'off${near.offShapeM.toStringAsFixed(0)}m '
              '${near.dwells ? "dwell" : "glide?!"}';
  } else {
    cause =
        'CONTOUR: plan ${plan.toStringAsFixed(2)}m/s but vel '
        '${vel.toStringAsFixed(2)}, gap ${gap.toStringAsFixed(1)}m — parked off-plan';
  }
  return 'VEH stopWhy $cause $at';
}

/// How stale the vehicles' REAL fixes are, against how stale their boards
/// claim to be. `as_of` is the backend's last successful fetch, so re-fetching
/// a board the upstream hasn't refreshed re-stamps it young while the fix
/// underneath is minutes old. Read-only evidence for whether the backend
/// should stop re-stamping.
String fixAgeDiagLine(({int total, int over45, int over90}) s) {
  if (s.total == 0) return 'VEH fixAge -';
  return 'VEH fixAge >45s ${s.over45}/${s.total} '
      '>90s ${s.over90}/${s.total} (real fix age, not as_of)';
}

/// How old each recent board was when it landed, and how many of those doomed
/// the marker to a freeze before the next one (> 15 s).
String boardAgeDiagLine(List<int> polls) {
  if (polls.isEmpty) return 'VEH boardAge@poll -';
  final doomed = polls.where((a) => a > 15).length;
  final worst = polls.reduce((a, b) => a > b ? a : b);
  return 'VEH boardAge@poll ${polls.join(",")} '
      'max ${worst}s freeze-bound $doomed/${polls.length}';
}
