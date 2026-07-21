import type { Env } from "../env";
import type { AnalyticsBucket, LineAnalyticsResponse } from "../types";
import type { RawArrival } from "./transitProvider";
import { getFlagMemoized } from "./featureFlags";
import type { WaitUntilCtx } from "./swrCache";
import { getLineByNumber, getLineDirectionEndpoints, getScheduleMeta, getStopSchedule } from "./gtfsData";
import { resolveDirectionRouteId } from "./direction";
import { activeServices, belgradeNow, type StopSchedule } from "./schedule";

// How long raw observations are kept before the aggregator prunes them. The
// rolled-up metrics survive; only the bulky raw rows are dropped.
const RAW_RETENTION_DAYS = 30;

// Aggregation reads only raw newer than the last run, plus this much extra
// history so a windowed metric (headway/speed) whose earlier half sits just
// before the boundary is still computed correctly. Must cover the widest window
// filter below: headway gap < 7200s and speed dt < 1800s → 7200s is enough.
const AGG_LOOKBACK_SECONDS = 7200;

// Max observed_at span processed per aggregate() invocation. On a fresh backfill
// the whole retained raw (hundreds of k rows, ~12M row-reads) can't fit one Cron
// invocation — it dies mid-write and never advances the watermark (see
// 2026-07-21-prod-backfill-verify.md). So each run processes AT MOST this much
// time, advances `last_run` to the window end, and the backfill CONVERGES over
// several bounded runs; once caught up the daily run is a light increment.
// Runtime-tunable (KV, no redeploy) so the window can be narrowed if a run still
// can't finish.
const AGG_WINDOW_KV_KEY = "config:agg_backfill_window_s";
const AGG_WINDOW_DEFAULT_SECONDS = 86400; // 1 day

async function resolveAggWindowSeconds(env: Env): Promise<number> {
  const raw = await env.STIGLA_KV.get(AGG_WINDOW_KV_KEY);
  if (raw === null) return AGG_WINDOW_DEFAULT_SECONDS;
  const n = parseInt(raw, 10);
  return Number.isNaN(n) || n <= 0 ? AGG_WINDOW_DEFAULT_SECONDS : n;
}

// D1 caps bound parameters at 100 per statement — far below SQLite's own 999
// default. The 2026-07-13 fix chunked by a fixed 40 *rows*, which for a 7-column
// insert is 280 params (2.8× the real cap): still "too many SQL variables". So
// the chunk must be derived from the column count, not a magic row constant.
const D1_MAX_BOUND_PARAMS = 100;

// Raw-observation columns. `direction_route_id` (v2) is the line direction the
// vehicle was on, resolved on the arrivals path — nullable when it can't be told.
const RAW_OBSERVATION_COLUMNS = [
  "line",
  "stop_id",
  "garage_no",
  "vehicle_id",
  "eta_minutes",
  "stops_remaining",
  "observed_at",
  "direction_route_id",
] as const;

// agg_line_dir_time columns written by the aggregate (sched_delay_* are left at
// their defaults here — populated in a follow-up step — so they're not listed).
const AGG_LINE_DIR_TIME_COLUMNS = [
  "line",
  "direction_route_id",
  "dow",
  "hour",
  "samples",
  "arrivals",
  "headway_count",
  "headway_secs_sum",
  "hb0",
  "hb1",
  "hb2",
  "hb3",
  "hb4",
  "hb5",
  "hb6",
  "hb7",
  "hb8",
  "hb9",
  "hb10",
  "hb11",
  "speed_count",
  "speed_stops_per_min_sum",
  "updated_at",
] as const;

const AGG_VEHICLE_LINE_COLUMNS = [
  "vehicle_id",
  "line",
  "samples",
  "arrivals",
  "first_seen",
  "last_seen",
  "updated_at",
] as const;

const AGG_VEHICLE_LINE_DOW_COLUMNS = [
  "vehicle_id",
  "line",
  "dow",
  "samples",
  "arrivals",
  "speed_count",
  "speed_stops_per_min_sum",
  "updated_at",
] as const;

// Headway-histogram bucket upper bounds (seconds). A gap falls in bucket i where
// it's the first bound it's below; anything ≥ the last bound is the top bucket.
// 11 bounds → 12 buckets (hb0..hb11), matching migration 0006.
export const HEADWAY_BUCKET_BOUNDS_SECS = [
  120, 180, 240, 300, 360, 480, 600, 900, 1200, 1800, 3600,
] as const;
export const HEADWAY_BUCKET_COUNT = HEADWAY_BUCKET_BOUNDS_SECS.length + 1; // 12

export function headwayBucket(gapSecs: number): number {
  for (let i = 0; i < HEADWAY_BUCKET_BOUNDS_SECS.length; i++) {
    if (gapSecs < HEADWAY_BUCKET_BOUNDS_SECS[i]) return i;
  }
  return HEADWAY_BUCKET_BOUNDS_SECS.length;
}

// GTFS minutes ≥ 1440 are "after midnight" (schedule.ts uses the same constant).
const OVERNIGHT_MINUTES = 1440;
// How far an observed arrival may sit from a scheduled departure and still be
// attributed to it. Beyond this we can't tell which trip it was → no delay.
const SCHED_MATCH_TOLERANCE_MIN = 30;

/**
 * Signed delay in seconds of an observed arrival vs the nearest scheduled
 * departure at its stop (positive = late), or null when none is within
 * tolerance. Times are local minutes-of-day; the ±1440 shifts let an arrival in
 * the small hours match a scheduled overnight trip (and vice-versa) across the
 * midnight wrap.
 */
export function schedDelaySeconds(
  observedMin: number,
  scheduledMins: number[],
  toleranceMin: number = SCHED_MATCH_TOLERANCE_MIN,
): number | null {
  let bestSigned: number | null = null;
  let bestAbs = Infinity;
  for (const s of scheduledMins) {
    for (const cand of [s, s - OVERNIGHT_MINUTES, s + OVERNIGHT_MINUTES]) {
      const d = observedMin - cand;
      const abs = Math.abs(d);
      if (abs < bestAbs) {
        bestAbs = abs;
        bestSigned = d;
      }
    }
  }
  if (bestSigned === null || bestAbs > toleranceMin) return null;
  return Math.round(bestSigned * 60);
}

/**
 * Largest row count that keeps a multi-row INSERT within D1's bound-parameter
 * cap, given how many columns (= bind params) each row carries. Floors so the
 * chunk never exceeds the cap; never returns 0 even for an absurdly wide row.
 */
export function maxRowsPerInsert(columnsPerRow: number): number {
  return Math.max(1, Math.floor(D1_MAX_BOUND_PARAMS / columnsPerRow));
}

/**
 * Insert many rows into `table(columns)` as chunked multi-row statements, each
 * kept under D1's per-statement bound-parameter cap. The single choke point for
 * every analytics insert so the "too many SQL variables" bug can't come back one
 * table at a time. Exported so the product-analytics logger shares the chunker.
 */
export async function chunkedInsert(
  db: D1Database,
  table: string,
  columns: readonly string[],
  rows: readonly (string | number | null)[][],
): Promise<void> {
  if (rows.length === 0) return;
  const rowsPerChunk = maxRowsPerInsert(columns.length);
  const rowPlaceholder = `(${columns.map(() => "?").join(",")})`;
  const columnList = columns.join(",");
  for (let i = 0; i < rows.length; i += rowsPerChunk) {
    const chunk = rows.slice(i, i + rowsPerChunk);
    const placeholders = chunk.map(() => rowPlaceholder).join(",");
    const binds = chunk.flat();
    await db
      .prepare(`INSERT INTO ${table} (${columnList}) VALUES ${placeholders}`)
      .bind(...binds)
      .run();
  }
}

/**
 * Normalised vehicle id, or null when the garage number doesn't identify a real
 * vehicle. The source emits placeholder ids `P1..P999` (recycled across
 * vehicles); those are junk for per-vehicle reasoning. Anything else (real
 * `P#####` ids) is trusted as-is. Mirrors the SQL in 0002_vehicle_id.sql.
 */
export function vehicleIdOf(garageNo: string | null): string | null {
  if (!garageNo) return null;
  const m = /^P(\d+)$/.exec(garageNo);
  if (m && Number(m[1]) < 1000) return null;
  return garageNo;
}

/**
 * The line direction a live vehicle is on, resolved from its own route geometry
 * exactly as the map does (lib/direction.ts). Falls back to the line's canonical
 * route_id when the direction can't be told (no GPS / unresolvable), or null
 * when we don't even know the line. Cached lookups keep a busy stop's fan-out
 * from re-loading GTFS per row.
 */
async function resolveObservationDirection(env: Env, r: RawArrival): Promise<string | null> {
  const lineMeta = await getLineByNumber(env, r.lineNumber);
  const canonical = lineMeta?.route_id ?? null;
  if (!r.gps) return canonical;
  const directions = await getLineDirectionEndpoints(env, r.lineNumber);
  return resolveDirectionRouteId(r.routeStations, directions) ?? canonical;
}

/**
 * Log the arrivals we just fetched from the source into the analytics history.
 *
 * Flag-gated (`analytics_collect`) and meant to be called inside `ctx.waitUntil`
 * from the *fresh-fetch* path only — so it records exactly the data we already
 * pulled to serve the user, adding **zero** load on the source. Every arrival is
 * logged (a missing garage number is fine — still valid for line-level metrics).
 * `garage_no` is stored raw; `vehicle_id` is the normalised id (null for
 * missing/junk); `direction_route_id` is the resolved line direction (v2).
 */
export async function logObservations(
  env: Env,
  ctx: WaitUntilCtx,
  stopId: string,
  raw: RawArrival[],
): Promise<void> {
  if (!(await getFlagMemoized(env, ctx, "analytics_collect"))) return;
  if (raw.length === 0) return;

  const now = Math.floor(Date.now() / 1000);
  const rows: (string | number | null)[][] = [];
  for (const r of raw) {
    rows.push([
      r.lineNumber,
      stopId,
      r.garageNo,
      vehicleIdOf(r.garageNo),
      r.etaSeconds != null ? Math.round(r.etaSeconds / 60) : null,
      r.stopsRemaining,
      now,
      await resolveObservationDirection(env, r),
    ]);
  }
  await chunkedInsert(env.STIGLA_ANALYTICS_DB, "raw_observations", RAW_OBSERVATION_COLUMNS, rows);
}

// One (line, direction, dow, hour) bucket accumulated during an aggregate run.
interface Bucket {
  line: string;
  dir: string;
  dow: number;
  hour: number;
  samples: number;
  arrivals: number;
  headway_count: number;
  headway_secs_sum: number;
  hist: number[]; // length HEADWAY_BUCKET_COUNT
  speed_count: number;
  speed_stops_per_min_sum: number;
}

const emptyBucket = (line: string, dir: string, dow: number, hour: number): Bucket => ({
  line,
  dir,
  dow,
  hour,
  samples: 0,
  arrivals: 0,
  headway_count: 0,
  headway_secs_sum: 0,
  hist: new Array(HEADWAY_BUCKET_COUNT).fill(0),
  speed_count: 0,
  speed_stops_per_min_sum: 0,
});

// The 12 `SUM(CASE WHEN gap < bound THEN 1 ELSE 0 END)` histogram columns, built
// from the shared bucket bounds so the SQL and headwayBucket() can never drift.
function headwayHistogramSelect(): string {
  const cols: string[] = [];
  let prev = "0";
  for (let i = 0; i < HEADWAY_BUCKET_BOUNDS_SECS.length; i++) {
    const hi = HEADWAY_BUCKET_BOUNDS_SECS[i];
    cols.push(`SUM(CASE WHEN gap >= ${prev} AND gap < ${hi} THEN 1 ELSE 0 END) AS hb${i}`);
    prev = String(hi);
  }
  cols.push(
    `SUM(CASE WHEN gap >= ${prev} THEN 1 ELSE 0 END) AS hb${HEADWAY_BUCKET_BOUNDS_SECS.length}`,
  );
  return cols.join(", ");
}

/**
 * Roll raw observations up into `agg_line_dir_time` (per line × direction × dow ×
 * hour) and the per-vehicle tables, then prune old raw. **Windowed & incremental**:
 * each invocation processes at most one `config:agg_backfill_window_s` slice of
 * `observed_at` (default 1 day) starting at the `last_run` watermark, ADDS its
 * contributions to the existing buckets (additive/mergeable by design), and
 * advances the watermark to the window end. So the FIRST backfill converges over
 * several bounded runs instead of dying in one over-budget invocation, and once
 * caught up the daily run is a light increment (window end clamps to `now`).
 *
 * Progress is monotonic: the watermark only ever moves FORWARD, and to the end of
 * the slice this run actually processed. A run that can't advance (no raw at all)
 * leaves the data untouched. `caughtUp` is true once the window reached `now`.
 */
export async function aggregate(
  env: Env,
  now: number = Math.floor(Date.now() / 1000),
): Promise<{ buckets: number; from: number; to: number; caughtUp: boolean }> {
  const db = env.STIGLA_ANALYTICS_DB;

  const lastRunRow = await db
    .prepare("SELECT value FROM agg_state WHERE key = 'last_run'")
    .first<{ value: string }>();
  const lastRun = lastRunRow ? Number(lastRunRow.value) : 0;
  const fresh = lastRun === 0;

  // Where this run starts. On a fresh backfill anchor just before the OLDEST raw
  // row (not epoch 0 — otherwise the first windows land on decades of empty time)
  // and clear the aggregate tables once for a clean slate. Otherwise resume at the
  // watermark.
  let cursor: number;
  if (fresh) {
    const oldest = await db
      .prepare("SELECT MIN(observed_at) AS m FROM raw_observations")
      .first<{ m: number | null }>();
    if (!oldest || oldest.m == null) {
      // No raw at all — nothing to roll up. Pin the watermark to `now` so the next
      // run is a normal (empty) increment rather than another fresh anchor scan.
      await db
        .prepare("INSERT OR REPLACE INTO agg_state (key, value) VALUES ('last_run', ?)")
        .bind(String(now))
        .run();
      return { buckets: 0, from: now, to: now, caughtUp: true };
    }
    cursor = oldest.m - 1;
    await db.batch([
      db.prepare("DELETE FROM agg_line_dir_time"),
      db.prepare("DELETE FROM agg_vehicle_line"),
      db.prepare("DELETE FROM agg_vehicle_line_dow"),
    ]);
  } else {
    cursor = lastRun;
  }

  // This run's window: (cursor, windowEnd]. Bounded by the runtime-tunable slice
  // so one over-budget invocation can't happen; clamped to `now` once caught up.
  const windowSize = await resolveAggWindowSeconds(env);
  const windowEnd = Math.min(now, cursor + windowSize);
  const caughtUp = windowEnd >= now;
  // Lookback so a headway/speed pair straddling the window's start still resolves.
  const windowStart = Math.max(0, cursor - AGG_LOOKBACK_SECONDS);

  const map = new Map<string, Bucket>();
  const at = (line: string, dir: string, dow: number, hour: number): Bucket => {
    const k = `${line} ${dir} ${dow} ${hour}`;
    let b = map.get(k);
    if (!b) map.set(k, (b = emptyBucket(line, dir, dow, hour)));
    return b;
  };

  // Activity — NEW rows only (no window straddle, so no lookback needed).
  const activity = await db
    .prepare(
      `SELECT line, COALESCE(direction_route_id, '') AS dir,
         CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
         CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
         COUNT(*) AS samples,
         SUM(CASE WHEN stops_remaining = 0 THEN 1 ELSE 0 END) AS arrivals
       FROM raw_observations
       WHERE observed_at > ? AND observed_at <= ?
       GROUP BY line, dir, dow, hour`,
    )
    .bind(cursor, windowEnd)
    .all<{ line: string; dir: string; dow: number; hour: number; samples: number; arrivals: number }>();
  for (const r of activity.results) {
    const b = at(r.line, r.dir, r.dow, r.hour);
    b.samples += r.samples;
    b.arrivals += r.arrivals ?? 0;
  }

  // Speed — read the lookback window so LAG has the earlier fix, but only count
  // pairs whose LATER fix is new (observed_at > cursor) to avoid double-counting.
  const speed = await db
    .prepare(
      `SELECT line, dir, dow, hour, COUNT(*) AS n, SUM(sp) AS s FROM (
         SELECT line, COALESCE(direction_route_id, '') AS dir,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
           (LAG(stops_remaining) OVER w - stops_remaining) * 60.0
             / (observed_at - LAG(observed_at) OVER w) AS sp,
           (observed_at - LAG(observed_at) OVER w) AS dt,
           (LAG(stops_remaining) OVER w - stops_remaining) AS dstops,
           observed_at AS oa
         FROM raw_observations
         WHERE observed_at > ? AND observed_at <= ?
           AND stops_remaining IS NOT NULL AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, vehicle_id, stop_id ORDER BY observed_at)
       )
       WHERE dt > 20 AND dt < 1800 AND dstops > 0 AND oa > ?
       GROUP BY line, dir, dow, hour`,
    )
    .bind(windowStart, windowEnd, cursor)
    .all<{ line: string; dir: string; dow: number; hour: number; n: number; s: number }>();
  for (const r of speed.results) {
    const b = at(r.line, r.dir, r.dow, r.hour);
    b.speed_count += r.n;
    b.speed_stops_per_min_sum += r.s ?? 0;
  }

  // Headway + histogram — same lookback + new-pair filter. Partitioned by
  // direction too (a stop usually serves one direction, but be exact).
  const headway = await db
    .prepare(
      `SELECT line, dir, dow, hour, COUNT(*) AS n, SUM(gap) AS s, ${headwayHistogramSelect()} FROM (
         SELECT line, COALESCE(direction_route_id, '') AS dir,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
           observed_at - LAG(observed_at) OVER w AS gap,
           observed_at AS oa,
           vehicle_id, LAG(vehicle_id) OVER w AS prev_g
         FROM raw_observations
         WHERE observed_at > ? AND observed_at <= ?
           AND stops_remaining = 0 AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, COALESCE(direction_route_id, ''), stop_id ORDER BY observed_at)
       )
       WHERE gap > 60 AND gap < 7200 AND vehicle_id <> prev_g AND oa > ?
       GROUP BY line, dir, dow, hour`,
    )
    .bind(windowStart, windowEnd, cursor)
    .all<
      { line: string; dir: string; dow: number; hour: number; n: number; s: number } & Record<
        `hb${number}`,
        number
      >
    >();
  for (const r of headway.results) {
    const b = at(r.line, r.dir, r.dow, r.hour);
    b.headway_count += r.n;
    b.headway_secs_sum += r.s ?? 0;
    for (let i = 0; i < HEADWAY_BUCKET_COUNT; i++) {
      b.hist[i] += (r as Record<string, number>)[`hb${i}`] ?? 0;
    }
  }

  // --- ATOMIC commit: every bucket UPSERT for this window PLUS the watermark
  // advance go in ONE db.batch() (a single D1 transaction). So the run either
  // commits its window AND moves the watermark, or does neither — it can NEVER
  // leave buckets written without advancing the watermark, which the next run
  // would then re-add (the 2026-07-21 double-count: repeated CPU-limit kills
  // between the bucket write and a separate watermark write inflated samples to
  // 2.5× the raw count). The CPU-heavy part (the window-function scans above) runs
  // BEFORE this batch, so a resource-limit kill there just leaves the watermark
  // unmoved and the next run safely reprocesses the same slice from scratch.
  // Buckets per bounded window are a few hundred (line×dir×dow×hour for one time
  // slice) — well within a single batch; narrow config:agg_backfill_window_s if a
  // window's write set ever grows too large.
  const cols = AGG_LINE_DIR_TIME_COLUMNS.join(",");
  const ph = AGG_LINE_DIR_TIME_COLUMNS.map(() => "?").join(",");
  const upsertSql = `INSERT INTO agg_line_dir_time (${cols}) VALUES (${ph}) ON CONFLICT(line,direction_route_id,dow,hour) DO UPDATE SET ${AGG_UPSERT_SET}`;
  const writes = [...map.values()].map((b) => db.prepare(upsertSql).bind(...bucketRow(b, now)));
  writes.push(
    db
      .prepare("INSERT OR REPLACE INTO agg_state (key, value) VALUES ('last_run', ?)")
      .bind(String(windowEnd)),
  );
  await db.batch(writes);

  // Secondary metrics — per-vehicle + schedule-delay. BEST-EFFORT, and deliberately
  // AFTER the watermark has already advanced: they add onto agg rows for THIS
  // window, so if the run dies here the next run (watermark already past this slice)
  // won't reprocess it — the secondary data is simply MISSING for this window, never
  // double-counted. A thrown error is likewise swallowed (secondary; not worth
  // stalling the whole aggregate). They read raw before the prune below.
  try {
    await aggregateVehicles(db, now, cursor, windowEnd, windowStart);
  } catch (e) {
    console.error("analytics per-vehicle pass failed (continuing without it)", e);
  }
  try {
    await aggregateSchedDelay(env, db, now, cursor, windowEnd);
  } catch (e) {
    console.error("analytics sched_delay pass failed (continuing without it)", e);
  }

  // Prune old raw ONLY once caught up — while still catching up, rows older than
  // retention may not have been aggregated into their window yet, and pruning them
  // would drop history unread. (Retention is 30d and current raw is <30d, so this
  // is belt-and-braces, but keep it correct.)
  if (caughtUp) {
    await db
      .prepare("DELETE FROM raw_observations WHERE observed_at < ?")
      .bind(now - RAW_RETENTION_DAYS * 86400)
      .run();
  }

  return { buckets: map.size, from: cursor, to: windowEnd, caughtUp };
}

const AGG_UPSERT_SET =
  "samples=samples+excluded.samples, arrivals=arrivals+excluded.arrivals, " +
  "headway_count=headway_count+excluded.headway_count, headway_secs_sum=headway_secs_sum+excluded.headway_secs_sum, " +
  Array.from({ length: HEADWAY_BUCKET_COUNT }, (_, i) => `hb${i}=hb${i}+excluded.hb${i}`).join(", ") +
  ", speed_count=speed_count+excluded.speed_count, " +
  "speed_stops_per_min_sum=speed_stops_per_min_sum+excluded.speed_stops_per_min_sum, " +
  "updated_at=excluded.updated_at";

function bucketRow(b: Bucket, now: number): (string | number)[] {
  return [b.line, b.dir, b.dow, b.hour, b.samples, b.arrivals, b.headway_count, b.headway_secs_sum, ...b.hist, b.speed_count, b.speed_stops_per_min_sum, now];
}

/**
 * Per-vehicle aggregates, incremental. Totals/arrivals are additive; first_seen
 * takes the min and last_seen the max, so merging a new window is exact. Real
 * vehicles only (NULL vehicle_id excluded). Reads only new rows (activity) or the
 * lookback window (speed), mirroring the line-level aggregate.
 */
async function aggregateVehicles(
  db: D1Database,
  now: number,
  lo: number,
  hi: number,
  windowStart: number,
): Promise<void> {
  const pairs = await db
    .prepare(
      `SELECT vehicle_id, line, COUNT(*) AS samples,
          SUM(CASE WHEN stops_remaining = 0 THEN 1 ELSE 0 END) AS arrivals,
          MIN(observed_at) AS first_seen, MAX(observed_at) AS last_seen
       FROM raw_observations
       WHERE observed_at > ? AND observed_at <= ? AND vehicle_id IS NOT NULL
       GROUP BY vehicle_id, line`,
    )
    .bind(lo, hi)
    .all<{
      vehicle_id: string;
      line: string;
      samples: number;
      arrivals: number;
      first_seen: number;
      last_seen: number;
    }>();

  const dowActivity = await db
    .prepare(
      `SELECT vehicle_id, line,
          CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
          COUNT(*) AS samples,
          SUM(CASE WHEN stops_remaining = 0 THEN 1 ELSE 0 END) AS arrivals
       FROM raw_observations
       WHERE observed_at > ? AND observed_at <= ? AND vehicle_id IS NOT NULL
       GROUP BY vehicle_id, line, dow`,
    )
    .bind(lo, hi)
    .all<{ vehicle_id: string; line: string; dow: number; samples: number; arrivals: number }>();

  const dowSpeed = await db
    .prepare(
      `SELECT vehicle_id, line, dow, COUNT(*) AS n, SUM(sp) AS s FROM (
         SELECT vehicle_id, line,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           (LAG(stops_remaining) OVER w - stops_remaining) * 60.0
             / (observed_at - LAG(observed_at) OVER w) AS sp,
           (observed_at - LAG(observed_at) OVER w) AS dt,
           (LAG(stops_remaining) OVER w - stops_remaining) AS dstops,
           observed_at AS oa
         FROM raw_observations
         WHERE observed_at > ? AND observed_at <= ?
           AND stops_remaining IS NOT NULL AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, vehicle_id, stop_id ORDER BY observed_at)
       )
       WHERE dt > 20 AND dt < 1800 AND dstops > 0 AND oa > ?
       GROUP BY vehicle_id, line, dow`,
    )
    .bind(windowStart, hi, lo)
    .all<{ vehicle_id: string; line: string; dow: number; n: number; s: number }>();

  const dowMap = new Map<
    string,
    { vehicle_id: string; line: string; dow: number; samples: number; arrivals: number; speedCount: number; speedSum: number }
  >();
  const key = (v: string, l: string, d: number) => `${v} ${l} ${d}`;
  for (const r of dowActivity.results) {
    dowMap.set(key(r.vehicle_id, r.line, r.dow), {
      vehicle_id: r.vehicle_id,
      line: r.line,
      dow: r.dow,
      samples: r.samples,
      arrivals: r.arrivals ?? 0,
      speedCount: 0,
      speedSum: 0,
    });
  }
  for (const r of dowSpeed.results) {
    let b = dowMap.get(key(r.vehicle_id, r.line, r.dow));
    if (!b) {
      // A speed pair straddling the boundary can land in a (v,line,dow) with no
      // new activity rows — still a real measurement to record.
      dowMap.set(key(r.vehicle_id, r.line, r.dow), (b = {
        vehicle_id: r.vehicle_id,
        line: r.line,
        dow: r.dow,
        samples: 0,
        arrivals: 0,
        speedCount: 0,
        speedSum: 0,
      }));
    }
    b.speedCount += r.n;
    b.speedSum += r.s ?? 0;
  }

  const vlSql =
    `INSERT INTO agg_vehicle_line (${AGG_VEHICLE_LINE_COLUMNS.join(",")}) ` +
    `VALUES (${AGG_VEHICLE_LINE_COLUMNS.map(() => "?").join(",")}) ` +
    "ON CONFLICT(vehicle_id,line) DO UPDATE SET samples=samples+excluded.samples, " +
    "arrivals=arrivals+excluded.arrivals, first_seen=MIN(first_seen,excluded.first_seen), " +
    "last_seen=MAX(last_seen,excluded.last_seen), updated_at=excluded.updated_at";
  const vldSql =
    `INSERT INTO agg_vehicle_line_dow (${AGG_VEHICLE_LINE_DOW_COLUMNS.join(",")}) ` +
    `VALUES (${AGG_VEHICLE_LINE_DOW_COLUMNS.map(() => "?").join(",")}) ` +
    "ON CONFLICT(vehicle_id,line,dow) DO UPDATE SET samples=samples+excluded.samples, " +
    "arrivals=arrivals+excluded.arrivals, speed_count=speed_count+excluded.speed_count, " +
    "speed_stops_per_min_sum=speed_stops_per_min_sum+excluded.speed_stops_per_min_sum, " +
    "updated_at=excluded.updated_at";

  await batchUpsert(
    db,
    vlSql,
    pairs.results.map((p) => [p.vehicle_id, p.line, p.samples, p.arrivals ?? 0, p.first_seen, p.last_seen, now]),
  );
  await batchUpsert(
    db,
    vldSql,
    [...dowMap.values()].map((b) => [b.vehicle_id, b.line, b.dow, b.samples, b.arrivals, b.speedCount, b.speedSum, now]),
  );
}

interface SchedBucket {
  line: string;
  dir: string;
  dow: number;
  hour: number;
  count: number;
  sum: number;
}

/**
 * Match each NEW arrival (stops_remaining = 0) to the nearest scheduled
 * departure of its line/direction at that stop, and roll the signed delay into
 * agg_line_dir_time's sched_delay_* columns. Bucketed by the SAME (UTC) dow/hour
 * the activity pass uses so it lands in the same row; the schedule MATCH uses
 * Belgrade-local time + the active service calendar. Rows without a schedule /
 * without a match within tolerance contribute nothing (delay unknown, not zero).
 */
async function aggregateSchedDelay(
  env: Env,
  db: D1Database,
  now: number,
  lo: number,
  hi: number,
): Promise<void> {
  const meta = await getScheduleMeta(env);
  if (!meta) return;

  const arrivals = await db
    .prepare(
      `SELECT stop_id, line, COALESCE(direction_route_id, '') AS dir, observed_at
       FROM raw_observations
       WHERE observed_at > ? AND observed_at <= ? AND stops_remaining = 0`,
    )
    .bind(lo, hi)
    .all<{ stop_id: string; line: string; dir: string; observed_at: number }>();
  if (arrivals.results.length === 0) return;

  const schedCache = new Map<string, StopSchedule | null>();
  const buckets = new Map<string, SchedBucket>();

  // The scheduled-departure minutes for a given (stop, line, dir, service-day) are
  // identical for EVERY arrival that shares them, so memoise them. Without this the
  // match is O(arrivals × all-departures-at-stop): a mega-hub with an anomalous
  // arrival count (e.g. stop 21577 had 3789 arrivals on 2026-07-17) makes one
  // window's sched pass blow the Worker CPU limit. Memoised, the departure scan
  // runs once per (line, dir, day) instead of once per arrival.
  const minsMemo = new Map<string, number[]>();
  const activeMemo = new Map<string, Set<string>>();
  const activeFor = (dateISO: string): Set<string> => {
    let a = activeMemo.get(dateISO);
    if (!a) activeMemo.set(dateISO, (a = activeServices(dateISO, meta)));
    return a;
  };

  for (const a of arrivals.results) {
    let sched = schedCache.get(a.stop_id);
    if (sched === undefined) {
      sched = await getStopSchedule(env, a.stop_id);
      schedCache.set(a.stop_id, sched);
    }
    if (!sched) continue;

    const d = new Date(a.observed_at * 1000);
    const ctx = belgradeNow(d);

    const memoKey = `${a.stop_id}|${a.line}|${a.dir}|${ctx.dateISO}`;
    let mins = minsMemo.get(memoKey);
    if (mins === undefined) {
      const active = activeFor(ctx.dateISO);
      const yestActive = activeFor(ctx.yesterdayISO);
      mins = [];
      for (const dep of sched.deps) {
        if (dep.line !== a.line) continue;
        // Match direction when we know it; when the row predates direction logging
        // (dir === '') fall back to any direction of the line at this stop.
        if (a.dir !== "" && dep.route_id !== a.dir) continue;
        for (const [svc, m] of Object.entries(dep.svc)) {
          if (active.has(svc)) for (const t of m) mins.push(t);
          // Yesterday's overnight trips (>= 1440) run in today's small hours;
          // schedDelaySeconds' ±1440 shift lines them up.
          if (yestActive.has(svc)) for (const t of m) if (t >= OVERNIGHT_MINUTES) mins.push(t);
        }
      }
      minsMemo.set(memoKey, mins);
    }
    if (mins.length === 0) continue;

    const delay = schedDelaySeconds(ctx.minutes, mins);
    if (delay === null) continue;

    const dow = d.getUTCDay();
    const hour = d.getUTCHours();
    const key = `${a.line} ${a.dir} ${dow} ${hour}`;
    let b = buckets.get(key);
    if (!b) buckets.set(key, (b = { line: a.line, dir: a.dir, dow, hour, count: 0, sum: 0 }));
    b.count += 1;
    b.sum += delay;
  }

  if (buckets.size === 0) return;
  const sql =
    "INSERT INTO agg_line_dir_time (line,direction_route_id,dow,hour,sched_delay_count,sched_delay_secs_sum,updated_at) " +
    "VALUES (?,?,?,?,?,?,?) ON CONFLICT(line,direction_route_id,dow,hour) DO UPDATE SET " +
    "sched_delay_count=sched_delay_count+excluded.sched_delay_count, " +
    "sched_delay_secs_sum=sched_delay_secs_sum+excluded.sched_delay_secs_sum, updated_at=excluded.updated_at";
  await batchUpsert(
    db,
    sql,
    [...buckets.values()].map((b) => [b.line, b.dir, b.dow, b.hour, b.count, b.sum, now]),
  );
}

async function batchUpsert(
  db: D1Database,
  sql: string,
  rows: (string | number)[][],
): Promise<void> {
  const BATCH = 50;
  for (let i = 0; i < rows.length; i += BATCH) {
    await db.batch(rows.slice(i, i + BATCH).map((r) => db.prepare(sql).bind(...r)));
  }
}

interface AggRow {
  dow: number;
  hour: number;
  samples: number;
  arrivals: number;
  headway_count: number;
  headway_secs_sum: number;
  speed_count: number;
  speed_stops_per_min_sum: number;
}

const emptyFold = () => ({
  samples: 0,
  arrivals: 0,
  headway_count: 0,
  headway_secs_sum: 0,
  speed_count: 0,
  speed_stops_per_min_sum: 0,
});

/**
 * Serve a line's rolled-up analytics, folded into per-hour and per-dow views.
 * Reads agg_line_dir_time and folds ACROSS directions so the response shape is
 * unchanged (the draft screens keep working) — the per-direction split and the
 * headway histogram are stored for later features, not exposed here yet.
 */
export async function getLineAnalytics(env: Env, line: string): Promise<LineAnalyticsResponse> {
  const db = env.STIGLA_ANALYTICS_DB;
  // Fold directions in SQL: sum every metric per (dow, hour) across directions.
  const { results } = await db
    .prepare(
      `SELECT dow, hour,
              SUM(samples) AS samples, SUM(arrivals) AS arrivals,
              SUM(headway_count) AS headway_count, SUM(headway_secs_sum) AS headway_secs_sum,
              SUM(speed_count) AS speed_count, SUM(speed_stops_per_min_sum) AS speed_stops_per_min_sum
       FROM agg_line_dir_time WHERE line = ?
       GROUP BY dow, hour`,
    )
    .bind(line)
    .all<AggRow>();

  const fold = (size: number, keyOf: (r: AggRow) => number): AnalyticsBucket[] => {
    const acc = Array.from({ length: size }, (_, key) => ({ key, ...emptyFold() }));
    for (const r of results) {
      const b = acc[keyOf(r)];
      b.samples += r.samples;
      b.arrivals += r.arrivals;
      b.headway_count += r.headway_count;
      b.headway_secs_sum += r.headway_secs_sum;
      b.speed_count += r.speed_count;
      b.speed_stops_per_min_sum += r.speed_stops_per_min_sum;
    }
    return acc.map((b) => ({
      key: b.key,
      samples: b.samples,
      arrivals: b.arrivals,
      mean_headway_secs: b.headway_count ? Math.round(b.headway_secs_sum / b.headway_count) : null,
      mean_speed_stops_per_min: b.speed_count
        ? Number((b.speed_stops_per_min_sum / b.speed_count).toFixed(3))
        : null,
    }));
  };

  const lastRun = await db
    .prepare("SELECT value FROM agg_state WHERE key = 'last_run'")
    .first<{ value: string }>();

  return {
    line,
    total_samples: results.reduce((a, r) => a + r.samples, 0),
    by_hour: fold(24, (r) => r.hour),
    by_dow: fold(7, (r) => r.dow),
    grid: results.map((r) => ({
      dow: r.dow,
      hour: r.hour,
      samples: r.samples,
      arrivals: r.arrivals,
      mean_headway_secs: r.headway_count ? Math.round(r.headway_secs_sum / r.headway_count) : null,
      mean_speed_stops_per_min: r.speed_count
        ? Number((r.speed_stops_per_min_sum / r.speed_count).toFixed(3))
        : null,
    })),
    updated_at: lastRun ? Number(lastRun.value) : null,
    punctuality: null,
  };
}
