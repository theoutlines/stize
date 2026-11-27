import type { Env } from "../../env";

// The sweep's knobs, state keys and limits.

// KV keys — runtime-tunable knobs only, exactly like `config:nearby_schedule_stops`.
export const KV_INTERVAL_DAY = "config:sweep_interval_day_seconds";
export const KV_INTERVAL_NIGHT = "config:sweep_interval_night_seconds";

// D1 `sweep_state` keys — the sweep's durable rotation/breaker state (NOT KV).
export const STATE_CURSOR = "cursor";
export const STATE_BREAKER = "breaker";
// The last time a breaker switched the sweep off, and why. Written only on a trip
// (one row), so /admin/sweep/status answers "why is the sweep off?" without the
// logs, which prod keeps at a 20% sample and can drop the one line that says so.
export const STATE_LAST_TRIP = "last_trip";

export interface LastTrip {
  at: number; // unix seconds
  kind: "degradation" | "failures";
  reason: string;
}

// Adaptive-skip margin. Our OWN sweep touches each sentinel once per
// `cycleSeconds`, so any observation fresher than (cycle − this margin) must be
// organic (user) traffic. The margin keeps the sweep from ever mistaking its own
// last visit (~cycleSeconds old) for organic traffic and skipping it, which
// would stall the rotation. Comfortably larger than any per-tick cron jitter.
export const SKIP_MARGIN_SECONDS = 300;

// Reduced-tempo safe return (2026-07-21). Day: one sentinel / 60s (was 20s).
// Citywide coverage is nice-to-have and its speed doesn't matter, so the sweep
// comes back gentle; full tempo is only ever a deliberate config bump. Night
// 01:00–05:00: paused (a night interval of 0 means "don't sweep"). These are only
// the DEFAULTS for an unset key; an explicit KV value always wins, so the tempo is
// changed via `config:sweep_interval_day_seconds` without touching this code.
// (An explicit prod KV value from the old 20s tempo would override this default —
// the enable checklist deletes/sets that key to land on 60s.)
export const DEFAULT_INTERVAL_DAY_SECONDS = 60;
export const DEFAULT_INTERVAL_NIGHT_SECONDS = 0; // 0 == paused
export const NIGHT_START_HOUR = 1; // 01:00 Belgrade
export const NIGHT_END_HOUR = 5; // 05:00 Belgrade

// A cron tick covers 60s. `perTick = round(60 / interval)` sentinels keeps the
// stated cadence (20s → 3/tick). Bounded so a fat-fingered tiny interval can't
// blow the Worker's per-invocation subrequest/CPU budget in one tick.
export const MAX_SENTINELS_PER_TICK = 20;

// Circuit-breaker: this many consecutive non-JSON/error sweeps trip it. On trip
// the sweep flips its own flag OFF (no redeploy) and logs a signal.
export const BREAKER_THRESHOLD = 5;

export interface Breaker {
  consecutiveFailures: number;
  trippedAt: number | null;
}

// Sentinel list is a static asset (built by scripts/build-sentinels.mjs). It
// changes only on redeploy, so cache it for the isolate's lifetime.
let sentinelCache: string[] | null = null;
export async function loadSentinels(env: Env): Promise<string[]> {
  if (sentinelCache) return sentinelCache;
  const res = await env.ASSETS.fetch(new URL("/gtfs/sentinels.json", "https://assets.internal"));
  if (!res.ok) throw new Error(`Failed to load sentinels.json: ${res.status}`);
  const body = (await res.json()) as { stops: string[] };
  sentinelCache = body.stops;
  return sentinelCache;
}

/** Is `hour` (Belgrade local) inside the paused night window [01:00, 05:00)? */
export function isNightHour(hour: number): boolean {
  return hour >= NIGHT_START_HOUR && hour < NIGHT_END_HOUR;
}

// Parse a KV interval value. `null` (key unset) → the provided default; a bad
// value → default (fail safe, never NaN); a valid non-negative int wins.
export function parseInterval(raw: string | null, fallback: number): number {
  if (raw === null) return fallback;
  const n = parseInt(raw, 10);
  if (Number.isNaN(n) || n < 0) return fallback;
  return n;
}

export interface SweepMeterSnapshot {
  liveHr: number; // live upstream fetches in the trailing hour
  sweepHr: number; // sweep upstream fetches in the trailing hour
  ceiling: number; // configured hourly budget ceiling
  sweepCeiling: number; // ceiling − live reserve; sweep must stay at/under this
  p95LatencyMs: number | null; // breaker-window p95, null if no samples
  nonJsonFraction: number; // breaker-window non-JSON/empty share (0..1)
  samples: number; // breaker-window sample count
}

export interface SweepTickResult {
  ran: boolean;
  reason: string; // why it did / didn't sweep — surfaced in cron logs
  swept: string[]; // stop ids actually fetched
  skipped: number; // sentinels skipped by the adaptive filter this tick
  failures: number; // live-board failures this tick
  jitterMs?: number; // randomized pre-fetch delay actually applied this tick
  // Present when the `upstream_budget` meter is on — the numbers behind the
  // budget/breaker decision, for the cron log line and /admin/sweep/status.
  meter?: SweepMeterSnapshot;
}

export interface SweepTickOptions {
  // Apply the randomized pre-fetch delay (jitter). The per-minute cron sets this
  // so upstream hits don't land on a fixed phase; the staging admin endpoint
  // leaves it off so a manual tick returns promptly.
  applyJitter?: boolean;
  // Injectable for tests (deterministic delay / no real wait).
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}
