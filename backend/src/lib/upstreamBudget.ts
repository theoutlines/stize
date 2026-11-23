import type { Env } from "../env";
import type { WaitUntilCtx } from "./swrCache";
import { getFlagMemoized } from "./featureFlags";
import { kvGetCached } from "./kvCache";

// ---------------------------------------------------------------------------
// Upstream request budget + degradation breaker (polite-client pacing).
//
// One shared, worker-global meter of ACTUAL upstream fetches (never cache hits),
// persisted in D1 `upstream_meter` (a per-minute ring, migration 0009; was the
// per-fetch `upstream_events` log, migration 0008). It backs three things, all
// gated by the `upstream_budget` flag so the whole mechanism ships dormant:
//
//   1. Request budget — a rolling-hour count of upstream fetches, split live vs
//      sweep. The sentinel sweep is allowed to fetch only while the hour's total
//      leaves a reserved headroom for the live path. The LIVE PATH IS NEVER GATED
//      by the budget — when the budget is tight only the sweep stands down. This is
//      the whole point: analytics is nice-to-have, live arrivals are not.
//
//   2. Degradation breaker — the old breaker only saw ticks where every fetch
//      FAILED, so a source that answered "slow-but-200", or served non-JSON on a
//      warm cache key (SWR hands back stale, no error), went unnoticed. This adds
//      two signals measured across ALL fetches (live + sweep) in a short window:
//      p95 latency, and the share of non-JSON/empty responses. Either over its
//      threshold flips `analytics_sweep` OFF. No auto-return — re-enabling is manual.
//
//   3. Observability — /admin/sweep/status reads these same numbers so the owner
//      can see req/hr and breaker health without `wrangler tail`.
//
// Storage is D1, never KV: this is fetch-cadence machine state and the sweep
// already writes to this DB (KV vs D1 principle — feature-flags.md / migration 0007).
// ---------------------------------------------------------------------------

export type UpstreamKind = "live" | "sweep";

// Outcome of one upstream round-trip. `json` is the only healthy one; everything
// else counts toward the breaker's "non-JSON/empty" share. `empty` is a valid
// JSON array with no rows — usually a genuinely quiet stop, but a source under a
// challenge can also return empties, so it is counted (the threshold + min-sample
// gate keep legitimate quiet stops from tripping the breaker).
export type UpstreamOutcome = "json" | "empty" | "non_json" | "http_error" | "network_error";

export interface UpstreamEvent {
  kind: UpstreamKind;
  latencyMs: number;
  outcome: UpstreamOutcome;
}

// --- KV config knobs (runtime-tunable, no redeploy) -------------------------
const KV_BUDGET_HOURLY = "config:upstream_budget_hourly";
const KV_LIVE_RESERVE_HOURLY = "config:upstream_live_reserve_hourly";
const KV_JITTER_SECONDS = "config:sweep_jitter_seconds";
const KV_BREAKER_LATENCY_P95_MS = "config:breaker_latency_p95_ms";
const KV_BREAKER_NON_JSON_FRACTION = "config:breaker_non_json_fraction";
const KV_BREAKER_WINDOW_SECONDS = "config:breaker_window_seconds";
const KV_BREAKER_MIN_SAMPLES = "config:breaker_min_samples";

// Defaults. The budget ceiling is a STARTING value (owner-approved 2026-07-21,
// staged): turn `upstream_budget` on first with the sweep still off, read the real
// live req/hr from /admin/sweep/status over a peak day, then set the ceiling in KV.
// At the 60s sweep tempo the sweep adds ≤60 fetches/hr, so the budget is a backstop
// against a future tempo bump colliding with a live spike — the tempo is the
// primary limiter, the budget is the ceiling that makes the 2026-07-21 class of
// incident impossible.
export const DEFAULT_BUDGET_HOURLY = 1200;
export const DEFAULT_LIVE_RESERVE_HOURLY = 300;
export const DEFAULT_JITTER_SECONDS = 10;

// Breaker defaults (owner-approved starting values; tune from live). A healthy
// JSON board answers in well under a second; a degrading source drags into
// multiple seconds while still returning 200. 30% non-JSON over the window catches
// a partial/ramping challenge long before it's total. Both require a minimum
// sample count so a couple of noisy responses can't trip it.
export const DEFAULT_BREAKER_LATENCY_P95_MS = 3000;
export const DEFAULT_BREAKER_NON_JSON_FRACTION = 0.3;
export const DEFAULT_BREAKER_WINDOW_SECONDS = 300; // 5 min
export const DEFAULT_BREAKER_MIN_SAMPLES = 20;

// The meter is a fixed-size ring of per-minute buckets (migration 0009): one row
// per (minute slot, kind), upserted in place — 1 row written per fetch and no
// DELETE ever. The ring must cover the widest read window (the rolling-hour
// budget, the breaker window); 3h leaves headroom for a widened breaker window.
export const METER_RING_MINUTES = 180;

// Latency histogram upper edges (ms) — bucket i holds latency <= EDGES[i] (and
// > EDGES[i-1]); the last bucket is everything above the last edge. Mirrors the
// lb0..lb12 columns. The breaker's p95 is exact when its threshold is an edge.
export const LATENCY_EDGES_MS = [250, 500, 750, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 7500, 10000] as const;
const LATENCY_BUCKETS = LATENCY_EDGES_MS.length + 1;
const LB_COLS = Array.from({ length: LATENCY_BUCKETS }, (_, i) => `lb${i}`);

/** Histogram bucket index for one latency (0..LATENCY_BUCKETS-1). */
export function latencyBucket(latencyMs: number): number {
  for (let i = 0; i < LATENCY_EDGES_MS.length; i++) {
    if (latencyMs <= LATENCY_EDGES_MS[i]) return i;
  }
  return LATENCY_EDGES_MS.length;
}

// First unix minute a trailing window of `windowSeconds` covers, clamped to the ring.
function windowStartMinute(now: number, windowSeconds: number): number {
  const nowMinute = Math.floor(now / 60);
  const span = Math.min(METER_RING_MINUTES - 1, Math.ceil(windowSeconds / 60));
  return nowMinute - span;
}

function parseIntKv(raw: string | null, fallback: number): number {
  if (raw === null) return fallback;
  const n = parseInt(raw, 10);
  return Number.isNaN(n) || n < 0 ? fallback : n;
}

function parseFloatKv(raw: string | null, fallback: number): number {
  if (raw === null) return fallback;
  const n = parseFloat(raw);
  return Number.isNaN(n) || n < 0 ? fallback : n;
}

export interface BudgetConfig {
  ceiling: number;
  liveReserve: number;
}

export interface BreakerConfig {
  latencyP95Ms: number;
  nonJsonFraction: number;
  windowSeconds: number;
  minSamples: number;
}

export async function resolveBudgetConfig(env: Env): Promise<BudgetConfig> {
  const [ceilingRaw, reserveRaw] = await Promise.all([
    kvGetCached(env, KV_BUDGET_HOURLY),
    kvGetCached(env, KV_LIVE_RESERVE_HOURLY),
  ]);
  return {
    ceiling: parseIntKv(ceilingRaw, DEFAULT_BUDGET_HOURLY),
    liveReserve: parseIntKv(reserveRaw, DEFAULT_LIVE_RESERVE_HOURLY),
  };
}

export async function resolveJitterSeconds(env: Env): Promise<number> {
  return parseIntKv(await kvGetCached(env, KV_JITTER_SECONDS), DEFAULT_JITTER_SECONDS);
}

export async function resolveBreakerConfig(env: Env): Promise<BreakerConfig> {
  const [p95, frac, win, min] = await Promise.all([
    kvGetCached(env, KV_BREAKER_LATENCY_P95_MS),
    kvGetCached(env, KV_BREAKER_NON_JSON_FRACTION),
    kvGetCached(env, KV_BREAKER_WINDOW_SECONDS),
    kvGetCached(env, KV_BREAKER_MIN_SAMPLES),
  ]);
  return {
    latencyP95Ms: parseIntKv(p95, DEFAULT_BREAKER_LATENCY_P95_MS),
    nonJsonFraction: parseFloatKv(frac, DEFAULT_BREAKER_NON_JSON_FRACTION),
    windowSeconds: parseIntKv(win, DEFAULT_BREAKER_WINDOW_SECONDS),
    minSamples: parseIntKv(min, DEFAULT_BREAKER_MIN_SAMPLES),
  };
}

/**
 * Record one actual upstream fetch. Called ONLY from the fresh-fetch path (never
 * a cache hit) and only when `upstream_budget` is on — the caller checks the flag.
 * Best-effort: a metering failure must never affect the response, so callers run
 * this inside `ctx.waitUntil(...).catch(...)`.
 *
 * One upsert into the minute's ring slot (1 row written). If the slot still holds
 * an older minute (the ring wrapped), every counter is reset to this event instead
 * of added to — the ring stays bounded without a DELETE.
 */
export async function recordUpstreamEvent(
  env: Env,
  event: UpstreamEvent,
  now: number = Math.floor(Date.now() / 1000),
): Promise<void> {
  const minute = Math.floor(now / 60);
  const bucket = latencyBucket(Math.max(0, Math.round(event.latencyMs)));
  const lbValues = LB_COLS.map((_, i) => (i === bucket ? 1 : 0));
  const sameMinute = "upstream_meter.minute = excluded.minute";
  const sets = ["n", "non_json", ...LB_COLS]
    .map((c) => `${c} = CASE WHEN ${sameMinute} THEN upstream_meter.${c} + excluded.${c} ELSE excluded.${c} END`)
    .join(", ");
  await env.STIGLA_ANALYTICS_DB.prepare(
    `INSERT INTO upstream_meter (slot, kind, minute, n, non_json, ${LB_COLS.join(", ")})
     VALUES (?, ?, ?, 1, ?, ${LB_COLS.map(() => "?").join(", ")})
     ON CONFLICT(slot, kind) DO UPDATE SET ${sets}, minute = excluded.minute`,
  )
    .bind(minute % METER_RING_MINUTES, event.kind, minute, event.outcome === "json" ? 0 : 1, ...lbValues)
    .run();
}

export interface RollingCounts {
  live: number;
  sweep: number;
  total: number;
}

/**
 * Upstream fetch counts over the trailing `windowSeconds` (default 1h), by kind.
 * Minute granularity: the window is widened to whole minutes (at most +59s).
 */
export async function rollingCounts(
  env: Env,
  windowSeconds = 3600,
  now: number = Math.floor(Date.now() / 1000),
): Promise<RollingCounts> {
  const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
    "SELECT kind, SUM(n) AS n FROM upstream_meter WHERE minute >= ? AND minute <= ? GROUP BY kind",
  )
    .bind(windowStartMinute(now, windowSeconds), Math.floor(now / 60))
    .all<{ kind: string; n: number }>();
  let live = 0;
  let sweep = 0;
  for (const r of results) {
    if (r.kind === "sweep") sweep = r.n ?? 0;
    else if (r.kind === "live") live = r.n ?? 0;
  }
  return { live, sweep, total: live + sweep };
}

export interface DegradationMetrics {
  samples: number;
  p95LatencyMs: number | null; // null when there are no samples
  nonJsonFraction: number; // 0..1; 0 when there are no samples
}

/**
 * p95 latency + non-JSON/empty share over the trailing `windowSeconds`.
 *
 * p95 is nearest-rank over the latency histogram and reported as the UPPER edge
 * of the bucket holding that rank (the open-ended last bucket reports last edge +
 * 1). So `p95 > threshold` is exact when the threshold is a bucket edge, and errs
 * towards tripping (never towards missing a degradation) when it isn't.
 */
export async function degradationMetrics(
  env: Env,
  windowSeconds: number,
  now: number = Math.floor(Date.now() / 1000),
): Promise<DegradationMetrics> {
  const row = await env.STIGLA_ANALYTICS_DB.prepare(
    `SELECT SUM(n) AS n, SUM(non_json) AS non_json, ${LB_COLS.map((c) => `SUM(${c}) AS ${c}`).join(", ")}
       FROM upstream_meter WHERE minute >= ? AND minute <= ?`,
  )
    .bind(windowStartMinute(now, windowSeconds), Math.floor(now / 60))
    .first<Record<string, number | null>>();

  const samples = row?.n ?? 0;
  if (!row || samples === 0) return { samples: 0, p95LatencyMs: null, nonJsonFraction: 0 };

  const rank = Math.max(1, Math.ceil(0.95 * samples));
  let cum = 0;
  let p95LatencyMs: number = LATENCY_EDGES_MS[LATENCY_EDGES_MS.length - 1] + 1;
  for (let i = 0; i < LATENCY_BUCKETS; i++) {
    cum += row[LB_COLS[i]] ?? 0;
    if (cum >= rank) {
      p95LatencyMs = i < LATENCY_EDGES_MS.length ? LATENCY_EDGES_MS[i] : LATENCY_EDGES_MS[i - 1] + 1;
      break;
    }
  }
  return { samples, p95LatencyMs, nonJsonFraction: (row.non_json ?? 0) / samples };
}

export interface DegradationVerdict {
  tripped: boolean;
  reason: string | null; // machine-greppable cause when tripped
}

/**
 * Decide whether the source is degraded enough to stand the sweep down. Pure
 * function of the metrics + config so it's unit-testable. Never trips below the
 * minimum sample count (avoids reacting to a couple of noisy responses).
 */
export function evaluateDegradation(
  metrics: DegradationMetrics,
  cfg: BreakerConfig,
): DegradationVerdict {
  if (metrics.samples < cfg.minSamples) return { tripped: false, reason: null };
  if (metrics.p95LatencyMs !== null && metrics.p95LatencyMs > cfg.latencyP95Ms) {
    return {
      tripped: true,
      reason: `p95_latency ${metrics.p95LatencyMs}ms > ${cfg.latencyP95Ms}ms over ${metrics.samples} samples`,
    };
  }
  if (metrics.nonJsonFraction > cfg.nonJsonFraction) {
    const pct = (metrics.nonJsonFraction * 100).toFixed(0);
    const thr = (cfg.nonJsonFraction * 100).toFixed(0);
    return {
      tripped: true,
      reason: `non_json_share ${pct}% > ${thr}% over ${metrics.samples} samples`,
    };
  }
  return { tripped: false, reason: null };
}

export interface SweepBudgetDecision {
  allowed: boolean;
  hourTotal: number;
  ceiling: number;
  liveReserve: number;
  // The largest hour-total at which the sweep may still add its batch.
  sweepCeiling: number;
}

/**
 * May the sweep fetch `perTick` sentinels right now? Only if doing so keeps the
 * rolling-hour total at or below (ceiling − liveReserve) — i.e. the sweep always
 * leaves the reserve free for live traffic. Live never calls this; it is never
 * gated. Pure function so the arithmetic is unit-testable.
 */
export function sweepBudgetDecision(
  counts: RollingCounts,
  perTick: number,
  budget: BudgetConfig,
): SweepBudgetDecision {
  const sweepCeiling = Math.max(0, budget.ceiling - budget.liveReserve);
  return {
    allowed: counts.total + perTick <= sweepCeiling,
    hourTotal: counts.total,
    ceiling: budget.ceiling,
    liveReserve: budget.liveReserve,
    sweepCeiling,
  };
}

/**
 * Convenience for the fresh-fetch path: record an event, but only when the
 * `upstream_budget` flag is on, and always best-effort. Keeps the meter's flag
 * check + error swallowing in one place so callers stay tidy.
 */
export function meterUpstreamFetch(
  env: Env,
  ctx: WaitUntilCtx,
  event: UpstreamEvent,
): void {
  ctx.waitUntil(
    (async () => {
      try {
        if (await getFlagMemoized(env, ctx, "upstream_budget")) await recordUpstreamEvent(env, event);
      } catch (e) {
        console.error("upstream meter failed", e);
      }
    })(),
  );
}
