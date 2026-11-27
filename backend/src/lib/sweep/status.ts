import type { Env } from "../../env";
import { getFlag } from "../featureFlags";
import { belgradeNow } from "../schedule";
import { degradationMetrics, evaluateDegradation, resolveBreakerConfig, resolveBudgetConfig, resolveJitterSeconds, rollingCounts, sweepBudgetDecision } from "../upstreamBudget";
import { kvGetCached } from "../kvCache";

import { readSweepState } from "./state";
import { BREAKER_THRESHOLD, DEFAULT_INTERVAL_DAY_SECONDS, DEFAULT_INTERVAL_NIGHT_SECONDS, KV_INTERVAL_DAY, KV_INTERVAL_NIGHT, type LastTrip, MAX_SENTINELS_PER_TICK, STATE_BREAKER, STATE_LAST_TRIP, isNightHour, parseInterval } from "./config";

// --- Observability read-out ------------------------------------------------
// A single object for GET /api/v1/admin/sweep/status: everything an operator needs
// to see req/hr, remaining budget, and breaker health WITHOUT `wrangler tail`. No
// secrets/tokens anywhere in it — only counts, config values, and derived metrics.

export interface SweepStatus {
  now: number;
  flags: { analytics_sweep: boolean; upstream_budget: boolean };
  night_now: boolean;
  interval: { day_seconds: number; night_seconds: number; jitter_seconds: number };
  budget: {
    ceiling_hourly: number;
    live_reserve_hourly: number;
    sweep_ceiling_hourly: number;
    live_req_hr: number;
    sweep_req_hr: number;
    total_req_hr: number;
    remaining_for_sweep: number;
    sweep_allowed_now: boolean;
  };
  breaker: {
    // degradation (new): p95 latency + non-JSON share over the window
    window_seconds: number;
    samples: number;
    p95_latency_ms: number | null;
    p95_latency_threshold_ms: number;
    non_json_fraction: number;
    non_json_fraction_threshold: number;
    degradation_would_trip: boolean;
    degradation_reason: string | null;
    // consecutive-all-failed (existing)
    consecutive_failures: number;
    threshold: number;
    tripped_at: number | null;
    // the last trip of either breaker (null = never recorded)
    last_trip: LastTrip | null;
  };
}

export interface SweepBreakerState {
  consecutiveFailures: number;
  trippedAt: number | null;
}

export async function readBreakerState(env: Env): Promise<SweepBreakerState> {
  try {
    const raw = await readSweepState(env, STATE_BREAKER);
    return raw ? (JSON.parse(raw) as SweepBreakerState) : { consecutiveFailures: 0, trippedAt: null };
  } catch {
    return { consecutiveFailures: 0, trippedAt: null };
  }
}

export async function sweepStatus(
  env: Env,
  now: Date = new Date(),
): Promise<SweepStatus> {
  const nowSec = Math.floor(now.getTime() / 1000);
  const hour = Math.floor(belgradeNow(now).minutes / 60);

  const [sweepFlag, meterFlag, dayRaw, nightRaw, jitterSeconds, budget, breakerCfg, breakerState] =
    await Promise.all([
      getFlag(env, "analytics_sweep").catch(() => false),
      getFlag(env, "upstream_budget").catch(() => false),
      kvGetCached(env, KV_INTERVAL_DAY),
      kvGetCached(env, KV_INTERVAL_NIGHT),
      resolveJitterSeconds(env),
      resolveBudgetConfig(env),
      resolveBreakerConfig(env),
      readBreakerState(env),
    ]);
  let lastTrip: LastTrip | null = null;
  try {
    const raw = await readSweepState(env, STATE_LAST_TRIP);
    lastTrip = raw ? (JSON.parse(raw) as LastTrip) : null;
  } catch {
    lastTrip = null;
  }

  const [counts, metrics] = await Promise.all([
    rollingCounts(env, 3600, nowSec),
    degradationMetrics(env, breakerCfg.windowSeconds, nowSec),
  ]);

  const daySeconds = parseInterval(dayRaw, DEFAULT_INTERVAL_DAY_SECONDS);
  const nightSeconds = parseInterval(nightRaw, DEFAULT_INTERVAL_NIGHT_SECONDS);
  const activeInterval = isNightHour(hour) ? nightSeconds : daySeconds;
  const perTick =
    activeInterval > 0
      ? Math.min(MAX_SENTINELS_PER_TICK, Math.max(1, Math.round(60 / activeInterval)))
      : 0;

  const decision = sweepBudgetDecision(counts, perTick || 1, budget);
  const verdict = evaluateDegradation(metrics, breakerCfg);

  return {
    now: nowSec,
    flags: { analytics_sweep: sweepFlag, upstream_budget: meterFlag },
    night_now: isNightHour(hour),
    interval: { day_seconds: daySeconds, night_seconds: nightSeconds, jitter_seconds: jitterSeconds },
    budget: {
      ceiling_hourly: budget.ceiling,
      live_reserve_hourly: budget.liveReserve,
      sweep_ceiling_hourly: decision.sweepCeiling,
      live_req_hr: counts.live,
      sweep_req_hr: counts.sweep,
      total_req_hr: counts.total,
      remaining_for_sweep: Math.max(0, decision.sweepCeiling - counts.total),
      sweep_allowed_now: decision.allowed,
    },
    breaker: {
      window_seconds: breakerCfg.windowSeconds,
      samples: metrics.samples,
      p95_latency_ms: metrics.p95LatencyMs,
      p95_latency_threshold_ms: breakerCfg.latencyP95Ms,
      non_json_fraction: Number(metrics.nonJsonFraction.toFixed(3)),
      non_json_fraction_threshold: breakerCfg.nonJsonFraction,
      degradation_would_trip: verdict.tripped,
      degradation_reason: verdict.reason,
      consecutive_failures: breakerState.consecutiveFailures,
      threshold: BREAKER_THRESHOLD,
      tripped_at: breakerState.trippedAt,
      last_trip: lastTrip,
    },
  };
}

// Latest observation time per stop, for the adaptive-skip check, bounded to the
// skip horizon (`since`): anything older can't make a sentinel skippable anyway.
// Reads the one-row-per-stop `stop_last_observed` table (migration 0009) by
// primary key — exactly one row per sentinel, instead of the old
// `raw_observations WHERE stop_id IN (...)` that no index could serve (a full scan
// of all retained raw, ~540k rows_read, on every minute tick).
export async function latestObservationPerStop(
  env: Env,
  stopIds: string[],
  since: number,
): Promise<Map<string, number>> {
  if (stopIds.length === 0) return new Map();
  const placeholders = stopIds.map(() => "?").join(",");
  const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
    `SELECT stop_id, observed_at AS last FROM stop_last_observed
     WHERE stop_id IN (${placeholders}) AND observed_at > ?`,
  )
    .bind(...stopIds, since)
    .all<{ stop_id: string; last: number }>();
  return new Map(results.map((r) => [r.stop_id, r.last]));
}
