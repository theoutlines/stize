import type { Env } from "../env";
import type { AnalyticsBucket, LineAnalyticsResponse } from "../types";
import type { RawArrival } from "./transitProvider";
import { getFlagMemoized } from "./featureFlags";
import type { WaitUntilCtx } from "./swrCache";

// How long raw observations are kept before the aggregator prunes them. The
// rolled-up per-line metrics survive; only the bulky raw rows are dropped.
const RAW_RETENTION_DAYS = 30;

// D1 caps bound parameters at 100 per statement — far below SQLite's own 999
// default. The 2026-07-13 fix chunked by a fixed 40 *rows*, which for a 7-column
// insert is 280 params (2.8× the real cap): still "too many SQL variables". So
// the chunk must be derived from the column count, not a magic row constant.
const D1_MAX_BOUND_PARAMS = 100;

// Column lists for every analytics insert, kept next to the chunker so the
// rows-per-statement is always computed from the true width.
const RAW_OBSERVATION_COLUMNS = [
  "line",
  "stop_id",
  "garage_no",
  "vehicle_id",
  "eta_minutes",
  "stops_remaining",
  "observed_at",
] as const;

const AGG_LINE_TIME_COLUMNS = [
  "line",
  "dow",
  "hour",
  "samples",
  "arrivals",
  "headway_count",
  "headway_secs_sum",
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
 * every analytics insert (raw observations, aggregates, future tables) so the
 * "too many SQL variables" bug can't come back one table at a time. Exported so
 * the product-analytics logger (lib/productAnalytics.ts) shares the same chunker.
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
 * Log the arrivals we just fetched from the source into the analytics history.
 *
 * Flag-gated (`analytics_collect`) and meant to be called inside
 * `ctx.waitUntil` from the *fresh-fetch* path only — so it records exactly the
 * data we already pulled to serve the user, adding **zero** load on the source.
 * The flag read is memoized per invocation (keyed by `ctx`): a map fan-out logs
 * many stops in one request but reads the flag from KV once, not per stop.
 *
 * Every arrival is logged (a missing garage number is fine — the observation is
 * still valid for line-level metrics). `garage_no` is stored raw; `vehicle_id`
 * is the normalised id (null for missing/junk) used for all per-vehicle work.
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
  const rows = raw.map((r) => [
    r.lineNumber,
    stopId,
    r.garageNo,
    vehicleIdOf(r.garageNo),
    r.etaSeconds != null ? Math.round(r.etaSeconds / 60) : null,
    r.stopsRemaining,
    now,
  ]);
  await chunkedInsert(env.STIGLA_ANALYTICS_DB, "raw_observations", RAW_OBSERVATION_COLUMNS, rows);
}

interface Bucket {
  samples: number;
  arrivals: number;
  headway_count: number;
  headway_secs_sum: number;
  speed_count: number;
  speed_stops_per_min_sum: number;
}

const emptyBucket = (): Bucket => ({
  samples: 0,
  arrivals: 0,
  headway_count: 0,
  headway_secs_sum: 0,
  speed_count: 0,
  speed_stops_per_min_sum: 0,
});

/**
 * Roll raw observations up into `agg_line_time` (per line × day-of-week × hour)
 * and prune raw older than the retention window. Idempotent: it fully recomputes
 * the aggregates from the raw still on hand, so re-running is safe. Runs on the
 * daily cron. All three real metrics are computed in SQL via window functions:
 *  - activity/arrivals  (counts)
 *  - real headways      (gaps between successive distinct vehicles at a stop)
 *  - speed              (stops closed per minute between a vehicle's own fixes)
 */
export async function aggregate(env: Env): Promise<{ buckets: number }> {
  const db = env.STIGLA_ANALYTICS_DB;
  const now = Math.floor(Date.now() / 1000);
  const map = new Map<string, Bucket>();
  const at = (line: string, dow: number, hour: number): Bucket => {
    const k = `${line}|${dow}|${hour}`;
    let b = map.get(k);
    if (!b) map.set(k, (b = emptyBucket()));
    return b;
  };

  const activity = await db
    .prepare(
      `SELECT line,
         CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
         CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
         COUNT(*) AS samples,
         SUM(CASE WHEN stops_remaining = 0 THEN 1 ELSE 0 END) AS arrivals
       FROM raw_observations
       GROUP BY line, dow, hour`,
    )
    .all<{ line: string; dow: number; hour: number; samples: number; arrivals: number }>();
  for (const r of activity.results) {
    const b = at(r.line, r.dow, r.hour);
    b.samples += r.samples;
    b.arrivals += r.arrivals ?? 0;
  }

  const speed = await db
    .prepare(
      `SELECT line, dow, hour, COUNT(*) AS n, SUM(sp) AS s FROM (
         SELECT line,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
           (LAG(stops_remaining) OVER w - stops_remaining) * 60.0
             / (observed_at - LAG(observed_at) OVER w) AS sp,
           (observed_at - LAG(observed_at) OVER w) AS dt,
           (LAG(stops_remaining) OVER w - stops_remaining) AS dstops
         FROM raw_observations
         WHERE stops_remaining IS NOT NULL AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, vehicle_id, stop_id ORDER BY observed_at)
       )
       WHERE dt > 20 AND dt < 1800 AND dstops > 0
       GROUP BY line, dow, hour`,
    )
    .all<{ line: string; dow: number; hour: number; n: number; s: number }>();
  for (const r of speed.results) {
    const b = at(r.line, r.dow, r.hour);
    b.speed_count += r.n;
    b.speed_stops_per_min_sum += r.s ?? 0;
  }

  const headway = await db
    .prepare(
      `SELECT line, dow, hour, COUNT(*) AS n, SUM(gap) AS s FROM (
         SELECT line,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           CAST(strftime('%H', observed_at, 'unixepoch') AS INTEGER) AS hour,
           observed_at - LAG(observed_at) OVER w AS gap,
           vehicle_id, LAG(vehicle_id) OVER w AS prev_g
         FROM raw_observations
         WHERE stops_remaining = 0 AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, stop_id ORDER BY observed_at)
       )
       WHERE gap > 60 AND gap < 7200 AND vehicle_id <> prev_g
       GROUP BY line, dow, hour`,
    )
    .all<{ line: string; dow: number; hour: number; n: number; s: number }>();
  for (const r of headway.results) {
    const b = at(r.line, r.dow, r.hour);
    b.headway_count += r.n;
    b.headway_secs_sum += r.s ?? 0;
  }

  // Rewrite the aggregate table from the freshly computed buckets.
  await db.prepare("DELETE FROM agg_line_time").run();
  await chunkedInsert(
    db,
    "agg_line_time",
    AGG_LINE_TIME_COLUMNS,
    [...map.entries()].map(([key, b]) => {
      const [line, dow, hour] = key.split("|");
      return [
        line,
        Number(dow),
        Number(hour),
        b.samples,
        b.arrivals,
        b.headway_count,
        b.headway_secs_sum,
        b.speed_count,
        b.speed_stops_per_min_sum,
        now,
      ];
    }),
  );

  // Per-vehicle aggregates — computed BEFORE pruning the raw rows they read.
  await aggregateVehicles(db, now);

  await db
    .prepare("DELETE FROM raw_observations WHERE observed_at < ?")
    .bind(now - RAW_RETENTION_DAYS * 86400)
    .run();
  await db
    .prepare("INSERT OR REPLACE INTO agg_state (key, value) VALUES ('last_run', ?)")
    .bind(String(now))
    .run();

  return { buckets: map.size };
}

/**
 * Roll raw observations up into the per-vehicle tables: `agg_vehicle_line`
 * (totals + first/last seen per vehicle×line) and `agg_vehicle_line_dow` (the
 * same by day-of-week, plus speed). Real vehicles only — rows with a NULL
 * vehicle_id (junk/placeholder or missing garage number) are excluded here,
 * though they still count for the line-level activity above.
 */
async function aggregateVehicles(db: D1Database, now: number): Promise<void> {
  const pairs = await db
    .prepare(
      `SELECT vehicle_id, line, COUNT(*) AS samples,
          SUM(CASE WHEN stops_remaining = 0 THEN 1 ELSE 0 END) AS arrivals,
          MIN(observed_at) AS first_seen, MAX(observed_at) AS last_seen
       FROM raw_observations WHERE vehicle_id IS NOT NULL
       GROUP BY vehicle_id, line`,
    )
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
       FROM raw_observations WHERE vehicle_id IS NOT NULL
       GROUP BY vehicle_id, line, dow`,
    )
    .all<{ vehicle_id: string; line: string; dow: number; samples: number; arrivals: number }>();

  const dowSpeed = await db
    .prepare(
      `SELECT vehicle_id, line, dow, COUNT(*) AS n, SUM(sp) AS s FROM (
         SELECT vehicle_id, line,
           CAST(strftime('%w', observed_at, 'unixepoch') AS INTEGER) AS dow,
           (LAG(stops_remaining) OVER w - stops_remaining) * 60.0
             / (observed_at - LAG(observed_at) OVER w) AS sp,
           (observed_at - LAG(observed_at) OVER w) AS dt,
           (LAG(stops_remaining) OVER w - stops_remaining) AS dstops
         FROM raw_observations
         WHERE stops_remaining IS NOT NULL AND vehicle_id IS NOT NULL
         WINDOW w AS (PARTITION BY line, vehicle_id, stop_id ORDER BY observed_at)
       )
       WHERE dt > 20 AND dt < 1800 AND dstops > 0
       GROUP BY vehicle_id, line, dow`,
    )
    .all<{ vehicle_id: string; line: string; dow: number; n: number; s: number }>();

  const dowMap = new Map<
    string,
    { vehicle_id: string; line: string; dow: number; samples: number; arrivals: number; speedCount: number; speedSum: number }
  >();
  const key = (v: string, l: string, d: number) => `${v}|${l}|${d}`;
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
    const b = dowMap.get(key(r.vehicle_id, r.line, r.dow));
    if (b) {
      b.speedCount += r.n;
      b.speedSum += r.s ?? 0;
    }
  }

  await db.prepare("DELETE FROM agg_vehicle_line").run();
  await db.prepare("DELETE FROM agg_vehicle_line_dow").run();

  await chunkedInsert(
    db,
    "agg_vehicle_line",
    AGG_VEHICLE_LINE_COLUMNS,
    pairs.results.map((p) => [
      p.vehicle_id,
      p.line,
      p.samples,
      p.arrivals ?? 0,
      p.first_seen,
      p.last_seen,
      now,
    ]),
  );

  await chunkedInsert(
    db,
    "agg_vehicle_line_dow",
    AGG_VEHICLE_LINE_DOW_COLUMNS,
    [...dowMap.values()].map((b) => [
      b.vehicle_id,
      b.line,
      b.dow,
      b.samples,
      b.arrivals,
      b.speedCount,
      b.speedSum,
      now,
    ]),
  );
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

/** Serve a line's rolled-up analytics: folded into per-hour and per-dow views. */
export async function getLineAnalytics(env: Env, line: string): Promise<LineAnalyticsResponse> {
  const db = env.STIGLA_ANALYTICS_DB;
  const { results } = await db
    .prepare(
      `SELECT dow, hour, samples, arrivals, headway_count, headway_secs_sum,
              speed_count, speed_stops_per_min_sum
       FROM agg_line_time WHERE line = ?`,
    )
    .bind(line)
    .all<AggRow>();

  const fold = (size: number, keyOf: (r: AggRow) => number): AnalyticsBucket[] => {
    const acc = Array.from({ length: size }, (_, key) => ({ key, ...emptyBucket() }));
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
