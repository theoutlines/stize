import type { Env } from "../env";
import type { WaitUntilCtx } from "./swrCache";
import { getFlag, setFlag } from "./featureFlags";
import { getArrivals } from "./arrivals";
import { belgradeNow } from "./schedule";

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

// KV keys — runtime-tunable knobs only, exactly like `config:nearby_schedule_stops`.
const KV_INTERVAL_DAY = "config:sweep_interval_day_seconds";
const KV_INTERVAL_NIGHT = "config:sweep_interval_night_seconds";

// D1 `sweep_state` keys — the sweep's durable rotation/breaker state (NOT KV).
const STATE_CURSOR = "cursor";
const STATE_BREAKER = "breaker";

// Adaptive-skip margin. Our OWN sweep touches each sentinel once per
// `cycleSeconds`, so any observation fresher than (cycle − this margin) must be
// organic (user) traffic. The margin keeps the sweep from ever mistaking its own
// last visit (~cycleSeconds old) for organic traffic and skipping it, which
// would stall the rotation. Comfortably larger than any per-tick cron jitter.
const SKIP_MARGIN_SECONDS = 300;

// Conservative start tempo (owner-chosen 2026-07-20). Day: one sentinel / 20s.
// Night 01:00–05:00: paused (a night interval of 0 means "don't sweep"). These
// are only the DEFAULTS for an unset key; an explicit KV value always wins, so
// the tempo is raised (target: 11s daytime) without touching this code.
const DEFAULT_INTERVAL_DAY_SECONDS = 20;
const DEFAULT_INTERVAL_NIGHT_SECONDS = 0; // 0 == paused
const NIGHT_START_HOUR = 1; // 01:00 Belgrade
const NIGHT_END_HOUR = 5; // 05:00 Belgrade

// A cron tick covers 60s. `perTick = round(60 / interval)` sentinels keeps the
// stated cadence (20s → 3/tick). Bounded so a fat-fingered tiny interval can't
// blow the Worker's per-invocation subrequest/CPU budget in one tick.
const MAX_SENTINELS_PER_TICK = 20;

// Circuit-breaker: this many consecutive non-JSON/error sweeps trip it. On trip
// the sweep flips its own flag OFF (no redeploy) and logs a signal.
const BREAKER_THRESHOLD = 5;

interface Breaker {
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

export interface SweepTickResult {
  ran: boolean;
  reason: string; // why it did / didn't sweep — surfaced in cron logs
  swept: string[]; // stop ids actually fetched
  skipped: number; // sentinels skipped by the adaptive filter this tick
  failures: number; // live-board failures this tick
}

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
): Promise<SweepTickResult> {
  const noop = (reason: string): SweepTickResult => ({
    ran: false,
    reason,
    swept: [],
    skipped: 0,
    failures: 0,
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
      env.STIGLA_KV.get(KV_INTERVAL_DAY),
      env.STIGLA_KV.get(KV_INTERVAL_NIGHT),
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

  // Adaptive skip: drop a sentinel that organic (user) traffic already refreshed
  // within the current cycle — re-fetching it adds nothing and the SWR layer
  // would only serve a cache hit anyway. Derived purely from `raw_observations`:
  // our own sweep touches each sentinel once per `cycleSeconds`, so any
  // observation fresher than (cycle − SKIP_MARGIN_SECONDS) must be organic. The
  // margin means the sweep never mistakes its own last visit for organic traffic,
  // so it can't skip itself into a stall. No separate visit-state to persist.
  // Best-effort: any failure here just means we don't skip (safe).
  const nowSec = Math.floor(now.getTime() / 1000);
  const toFetch = [...batch];
  let skipped = 0;
  try {
    const lastObs = await latestObservationPerStop(env, batch);
    const skipOlderThan = cycleSeconds - SKIP_MARGIN_SECONDS;
    if (skipOlderThan > 0) {
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

  // Fetch each kept sentinel through the normal arrivals path. Schedule fallback
  // is OFF (map-fan-out style) — it would fan out extra subrequests and the
  // sweep only needs the live board's vehicles. logObservations runs inside on a
  // real refresh, so this is also the write path.
  let failures = 0;
  const swept: string[] = [];
  for (const stopId of toFetch) {
    try {
      const board = await getArrivals(env, ctx, stopId, { includeSchedule: false });
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
  // non-fatal (we already did one honest batch); log and move on.
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
  };
}

// Latest observation time per stop, for the adaptive-skip check. One small
// indexed query over the batch (a handful of stops).
async function latestObservationPerStop(env: Env, stopIds: string[]): Promise<Map<string, number>> {
  if (stopIds.length === 0) return new Map();
  const placeholders = stopIds.map(() => "?").join(",");
  const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
    `SELECT stop_id, MAX(observed_at) AS last FROM raw_observations
     WHERE stop_id IN (${placeholders}) GROUP BY stop_id`,
  )
    .bind(...stopIds)
    .all<{ stop_id: string; last: number }>();
  return new Map(results.map((r) => [r.stop_id, r.last]));
}

// --- D1 sweep_state accessors (see migration 0007). One tiny key/value row per
// state key; per-tick reads/writes are trivially cheap on D1's write budget. ---
async function readSweepState(env: Env, key: string): Promise<string | null> {
  const row = await env.STIGLA_ANALYTICS_DB.prepare(
    "SELECT value FROM sweep_state WHERE key = ?",
  )
    .bind(key)
    .first<{ value: string }>();
  return row?.value ?? null;
}

async function writeSweepState(env: Env, key: string, value: string): Promise<void> {
  await env.STIGLA_ANALYTICS_DB.prepare(
    `INSERT INTO sweep_state (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  )
    .bind(key, value, Math.floor(Date.now() / 1000))
    .run();
}

async function persistState(
  env: Env,
  nextCursor: number,
  failures: number,
  attempted: number,
): Promise<void> {
  await writeSweepState(env, STATE_CURSOR, String(nextCursor));
  await updateBreaker(env, failures, attempted);
}

/**
 * Circuit-breaker. A tick that attempted fetches and got ONLY failures counts
 * as a consecutive failure; any success resets the counter. On reaching the
 * threshold the breaker flips `analytics_sweep` OFF (no redeploy) so the sweep
 * stops itself, and logs a signal for the report channel. A tick that fetched
 * nothing (all skipped) leaves the counter untouched.
 */
async function updateBreaker(env: Env, failures: number, attempted: number): Promise<void> {
  if (attempted === 0) return;
  let breaker: Breaker;
  try {
    const raw = await readSweepState(env, STATE_BREAKER);
    breaker = raw ? (JSON.parse(raw) as Breaker) : { consecutiveFailures: 0, trippedAt: null };
  } catch {
    breaker = { consecutiveFailures: 0, trippedAt: null };
  }

  const allFailed = failures >= attempted;
  if (!allFailed) {
    if (breaker.consecutiveFailures !== 0) {
      await writeSweepState(env, STATE_BREAKER, JSON.stringify({ consecutiveFailures: 0, trippedAt: null }));
    }
    return;
  }

  breaker.consecutiveFailures += 1;
  if (breaker.consecutiveFailures >= BREAKER_THRESHOLD) {
    breaker.trippedAt = Math.floor(Date.now() / 1000);
    await setFlag(env, "analytics_sweep", false);
    // Loud, machine-greppable signal for the report channel / tail.
    console.error(
      `SWEEP_CIRCUIT_BREAKER_TRIPPED: ${breaker.consecutiveFailures} consecutive failed sweeps; ` +
        `analytics_sweep flipped OFF. Source likely challenging/down — investigate before re-enabling.`,
    );
  }
  await writeSweepState(env, STATE_BREAKER, JSON.stringify(breaker));
}
