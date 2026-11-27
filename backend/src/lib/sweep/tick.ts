import type { Env } from "../../env";
import type { WaitUntilCtx } from "../swrCache";
import { getFlag, setFlag } from "../featureFlags";
import { getArrivals } from "../arrivals";
import { belgradeNow } from "../schedule";
import { degradationMetrics, evaluateDegradation, resolveBreakerConfig, resolveBudgetConfig, resolveJitterSeconds, rollingCounts, sweepBudgetDecision, type DegradationMetrics } from "../upstreamBudget";
import { kvGetCached } from "../kvCache";

import { KV_INTERVAL_DAY, KV_INTERVAL_NIGHT, STATE_CURSOR, SKIP_MARGIN_SECONDS, DEFAULT_INTERVAL_DAY_SECONDS, DEFAULT_INTERVAL_NIGHT_SECONDS, MAX_SENTINELS_PER_TICK, loadSentinels, isNightHour, parseInterval, type SweepMeterSnapshot, type SweepTickResult, type SweepTickOptions } from "./config";
import { persistState, readSweepState, recordTrip } from "./state";
import { latestObservationPerStop } from "./status";

// ---------------------------------------------------------------------------
// Sentinel sweep — citywide transport-history collection.
//
// Demand-driven logging only ever refreshes the stops users actually open, so
// history collapses onto a couple of commute corridors. The sweep fixes that:
// one arrivals fetch for a mid-route stop returns every vehicle heading to it
// (GPS + garage_no + all_stations), so one well-placed "sentinel" per
// line×direction observes that direction's active fleet. A slow Cron rotation
// over ~160 sentinels therefore samples the whole city.
//
// It adds ZERO new source-calling code: it drives the existing SWR/arrivals
// path (lib/arrivals.ts), which already logs what it fetches (lib/analytics.ts)
// and shares cache keys with user traffic (a sweep landing on a hot stop is a
// free cache hit). The only knob that faces the source is the tempo, and that
// lives entirely in KV (no redeploy).
//
// Safety: the whole thing is gated by the `analytics_sweep` flag (OFF on prod
// until a tempo is chosen; OFF is the killswitch). A circuit-breaker flips that
// flag OFF after repeated non-JSON/error responses (an upstream challenge or
// outage) — user traffic matters more than analytics. And if the state it needs
// (cursor in D1 / config in KV) can't be read, the sweep stays SILENT rather
// than running on fabricated defaults.
//
// State split — KV vs D1: the human-flipped knobs (the flag + the tempo config)
// live in KV, the no-redeploy mechanism. The sweep's own durable STATE (rotation
// cursor + circuit-breaker) lives in D1 (`sweep_state`, migration 0007). It used
// to sit in KV too, but a minute-cadence writer (2 writes/tick, ~2400/day) blew
// KV's free 1000-writes/day budget 2.4× (the 2026-07-21 alert). D1's write
// budget is ~100k/day and the sweep already writes raw_observations there, so
// per-tick state writes are trivially cheap. Principle: KV = manual knobs/flags;
// minute-cadence automation state = D1.
// ---------------------------------------------------------------------------

export const defaultSleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

/**
 * One sweep tick — call once per Cron minute (and from the staging admin
 * endpoint). Reads its state from KV; if that read fails the tick is a silent
 * no-op (never runs on fabricated defaults). Fetches a small batch of sentinels
 * through the normal arrivals/SWR path, which logs observations as a side
 * effect. Advances the rotation cursor and updates the circuit-breaker.
 */
export async function runSweepTick(
  env: Env,
  ctx: WaitUntilCtx,
  now: Date = new Date(),
  opts: SweepTickOptions = {},
): Promise<SweepTickResult> {
  const nowSec = Math.floor(now.getTime() / 1000);
  let meter: SweepMeterSnapshot | undefined;
  const noop = (reason: string): SweepTickResult => ({
    ran: false,
    reason,
    swept: [],
    skipped: 0,
    failures: 0,
    ...(meter ? { meter } : {}),
  });

  // Flag gate / killswitch. Also the breaker's off-switch.
  let enabled: boolean;
  try {
    enabled = await getFlag(env, "analytics_sweep");
  } catch (e) {
    console.error("sweep: flag read failed; standing down", e);
    return noop("flag-read-failed");
  }
  if (!enabled) return noop("disabled");

  // The sweep exists only to feed raw_observations. With collection off (e.g. the
  // D1 budget governor switched `analytics_collect` OFF until 00:00 UTC) every
  // sweep fetch would be pure load on the source with nothing recorded — stand down.
  let collecting: boolean;
  try {
    collecting = await getFlag(env, "analytics_collect");
  } catch (e) {
    console.error("sweep: analytics_collect read failed; standing down", e);
    return noop("flag-read-failed");
  }
  if (!collecting) return noop("collect-off");

  // Request-budget meter + degradation breaker (gated by `upstream_budget`). When
  // the meter is off the sweep still runs, but only the tempo limits it — no budget
  // gate, no latency/non-JSON breaker. Reading the flag is best-effort: treat a read
  // failure as "meter off" and carry on (the tempo alone is safe).
  let meterOn = false;
  try {
    meterOn = await getFlag(env, "upstream_budget");
  } catch (e) {
    console.warn("sweep: upstream_budget flag read failed; running without the guard", e);
  }

  // Budget/breaker inputs, read once at tick start. Reused for the log line and the
  // budget gate below. Best-effort: a metrics read failure must not stand the sweep
  // down (that would make a flaky analytics DB silently starve coverage), so on
  // error we skip the guard for this tick rather than tripping it.
  let budgetCeiling = 0;
  let sweepCeiling = 0;
  let hourTotal = 0;
  if (meterOn) {
    try {
      const breakerCfg = await resolveBreakerConfig(env);
      const [budget, counts, metrics] = await Promise.all([
        resolveBudgetConfig(env),
        rollingCounts(env, 3600, nowSec),
        degradationMetrics(env, breakerCfg.windowSeconds, nowSec),
      ]);
      budgetCeiling = budget.ceiling;
      sweepCeiling = Math.max(0, budget.ceiling - budget.liveReserve);
      hourTotal = counts.total;
      meter = snapshot(counts, budget.ceiling, sweepCeiling, metrics);

      // Degradation breaker: a slow-but-200 source (p95) or a rising non-JSON/empty
      // share flips `analytics_sweep` OFF (no redeploy) and logs a loud signal. No
      // auto-return — re-enabling is always a manual, reviewed step.
      const verdict = evaluateDegradation(metrics, breakerCfg);
      if (verdict.tripped) {
        await setFlag(env, "analytics_sweep", false);
        await recordTrip(env, { at: nowSec, kind: "degradation", reason: verdict.reason ?? "degradation" });
        console.error(
          `SWEEP_DEGRADATION_BREAKER_TRIPPED: ${verdict.reason}; analytics_sweep flipped OFF. ` +
            `Source degrading (slow/non-JSON) — investigate before re-enabling.`,
        );
        return noop(`degradation-breaker: ${verdict.reason}`);
      }
    } catch (e) {
      console.warn("sweep: budget/breaker read failed; sweeping without the guard this tick", e);
      meter = undefined;
      meterOn = false;
    }
  }

  // Night pause is driven by the (possibly overridden) night interval: 0 means
  // "don't sweep at night". Compute the active interval for the current hour.
  const hour = Math.floor(belgradeNow(now).minutes / 60);
  const night = isNightHour(hour);

  // Read config (KV) + cursor (D1). A THROW here means the store is unavailable —
  // stay silent rather than sweeping with defaults (owner constraint). A `null`
  // (unset key) is normal and falls back to the documented default.
  let intervalSeconds: number;
  let cursor: number;
  let sentinels: string[];
  try {
    const [dayRaw, nightRaw, cursorRaw] = await Promise.all([
      kvGetCached(env, KV_INTERVAL_DAY),
      kvGetCached(env, KV_INTERVAL_NIGHT),
      readSweepState(env, STATE_CURSOR),
    ]);
    intervalSeconds = night
      ? parseInterval(nightRaw, DEFAULT_INTERVAL_NIGHT_SECONDS)
      : parseInterval(dayRaw, DEFAULT_INTERVAL_DAY_SECONDS);
    cursor = parseInterval(cursorRaw, 0);
    sentinels = await loadSentinels(env);
  } catch (e) {
    console.error("sweep: KV/state read failed; standing down (not running on defaults)", e);
    return noop("state-read-failed");
  }

  if (intervalSeconds === 0) return noop(night ? "night-paused" : "interval-zero");
  if (sentinels.length === 0) return noop("no-sentinels");

  const perTick = Math.min(MAX_SENTINELS_PER_TICK, Math.max(1, Math.round(60 / intervalSeconds)));
  const cycleSeconds = sentinels.length * intervalSeconds;

  // The batch for this tick: `perTick` stops starting at the cursor, wrapping.
  const batch: string[] = [];
  for (let i = 0; i < perTick; i++) batch.push(sentinels[(cursor + i) % sentinels.length]);

  // Request-budget gate (meter on only). The sweep may fetch only if doing so keeps
  // the rolling-hour upstream total at or below (ceiling − live reserve) — it always
  // leaves the reserve for the live path, which is NEVER gated here. If the budget is
  // tight the tick is a no-op (the cursor does NOT advance, so no sentinel is skipped
  // — the rotation just pauses until live traffic subsides). Reason + numbers go to
  // the log so an operator sees the sweep is backing off, not broken.
  if (meterOn) {
    const decision = sweepBudgetDecision(
      { live: 0, sweep: 0, total: hourTotal },
      perTick,
      { ceiling: budgetCeiling, liveReserve: budgetCeiling - sweepCeiling },
    );
    if (!decision.allowed) {
      return noop(
        `budget-exhausted (hour=${hourTotal} + ${perTick} > sweepCeiling ${sweepCeiling})`,
      );
    }
  }

  // Adaptive skip: drop a sentinel that organic (user) traffic already refreshed
  // within the current cycle — re-fetching it adds nothing and the SWR layer
  // would only serve a cache hit anyway. Derived from `stop_last_observed`:
  // our own sweep touches each sentinel once per `cycleSeconds`, so any
  // observation fresher than (cycle − SKIP_MARGIN_SECONDS) must be organic. The
  // margin means the sweep never mistakes its own last visit for organic traffic,
  // so it can't skip itself into a stall. No separate visit-state to persist.
  // Best-effort: any failure here just means we don't skip (safe).
  const toFetch = [...batch];
  let skipped = 0;
  try {
    const skipOlderThan = cycleSeconds - SKIP_MARGIN_SECONDS;
    if (skipOlderThan > 0) {
      const lastObs = await latestObservationPerStop(env, batch, nowSec - skipOlderThan);
      const kept: string[] = [];
      for (const stopId of batch) {
        const obs = lastObs.get(stopId);
        const organicWithinCycle = obs !== undefined && nowSec - obs < skipOlderThan;
        if (organicWithinCycle) skipped++;
        else kept.push(stopId);
      }
      toFetch.length = 0;
      toFetch.push(...kept);
    }
  } catch (e) {
    console.warn("sweep: adaptive-skip check failed; sweeping full batch", e);
  }

  // Jitter: don't metronome. Delay the batch by a random 0..2×jitter seconds
  // (mean = jitter), so the upstream hit lands at a varying offset within the
  // minute instead of always on the cron's phase. Applied only on the cron path
  // (opts.applyJitter); the staging admin tick skips it so a manual check returns
  // promptly. Skipped when there's nothing to fetch.
  let jitterMs = 0;
  if (opts.applyJitter && toFetch.length > 0) {
    const jitterSeconds = await resolveJitterSeconds(env).catch(() => 0);
    if (jitterSeconds > 0) {
      const rnd = (opts.random ?? Math.random)();
      jitterMs = Math.round(rnd * 2 * jitterSeconds * 1000);
      if (jitterMs > 0) await (opts.sleep ?? defaultSleep)(jitterMs);
    }
  }

  // Fetch each kept sentinel through the normal arrivals path. Schedule fallback
  // is OFF (map-fan-out style) — it would fan out extra subrequests and the
  // sweep only needs the live board's vehicles. logObservations runs inside on a
  // real refresh, so this is also the write path. `kind: "sweep"` tags any upstream
  // fetch this triggers so the request meter counts it against the sweep, not live.
  let failures = 0;
  const swept: string[] = [];
  for (const stopId of toFetch) {
    try {
      const board = await getArrivals(env, ctx, stopId, { includeSchedule: false, kind: "sweep" });
      if (!board || board.service_status === "unavailable") {
        failures++;
      } else {
        swept.push(stopId);
      }
    } catch (e) {
      failures++;
      console.error(`sweep: fetch failed for stop ${stopId}`, e);
    }
  }

  // Advance the cursor by the batch size (not the kept size) so skipped stops
  // aren't retried next tick — they'll come round again next cycle.
  const nextCursor = (cursor + perTick) % sentinels.length;

  // Persist the cursor (D1) and update the breaker. Failure to WRITE here is
  // non-fatal (we already did one honest batch); log and move on. (The upstream
  // meter is a fixed-size ring since migration 0009 — nothing to prune.)
  ctx.waitUntil(
    persistState(env, nextCursor, failures, toFetch.length).catch((e) =>
      console.error("sweep: state persist failed", e),
    ),
  );

  return {
    ran: swept.length > 0 || toFetch.length > 0,
    reason: night ? "night-active" : "day-active",
    swept,
    skipped,
    failures,
    jitterMs,
    ...(meter ? { meter } : {}),
  };
}

// Build the meter snapshot attached to a tick result (log line + /admin status).
export function snapshot(
  counts: { live: number; sweep: number },
  ceiling: number,
  sweepCeiling: number,
  metrics: DegradationMetrics,
): SweepMeterSnapshot {
  return {
    liveHr: counts.live,
    sweepHr: counts.sweep,
    ceiling,
    sweepCeiling,
    p95LatencyMs: metrics.p95LatencyMs,
    nonJsonFraction: metrics.nonJsonFraction,
    samples: metrics.samples,
  };
}
