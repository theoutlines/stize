import type { Env } from "../env";
import type { AnalyticsBucket, LineAnalyticsResponse } from "../types";
import type { RawArrival } from "./transitProvider";
import { getFlag } from "./featureFlags";

// How long raw observations are kept before the aggregator prunes them. The
// rolled-up per-line metrics survive; only the bulky raw rows are dropped.
const RAW_RETENTION_DAYS = 30;

// D1 caps bound parameters per statement; chunk large writes well under it.
const INSERT_CHUNK = 40;

/**
 * Log the arrivals we just fetched from the source into the analytics history.
 *
 * Flag-gated (`analytics_collect`) and meant to be called inside
 * `ctx.waitUntil` from the *fresh-fetch* path only — so it records exactly the
 * data we already pulled to serve the user, adding **zero** load on the source.
 * Only vehicles with a garage number are kept (the id is needed to derive
 * per-vehicle speed and headways).
 */
export async function logObservations(env: Env, stopId: string, raw: RawArrival[]): Promise<void> {
  if (!(await getFlag(env, "analytics_collect"))) return;
  const rows = raw.filter((r) => r.garageNo);
  if (rows.length === 0) return;

  const now = Math.floor(Date.now() / 1000);
  const placeholders = rows.map(() => "(?,?,?,?,?,?)").join(",");
  const binds: (string | number | null)[] = [];
  for (const r of rows) {
    binds.push(
      r.lineNumber,
      stopId,
      r.garageNo,
      r.etaSeconds != null ? Math.round(r.etaSeconds / 60) : null,
      r.stopsRemaining,
      now,
    );
  }
  await env.STIGLA_ANALYTICS_DB.prepare(
    `INSERT INTO raw_observations (line, stop_id, garage_no, eta_minutes, stops_remaining, observed_at)
     VALUES ${placeholders}`,
  )
    .bind(...binds)
    .run();
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
         WHERE stops_remaining IS NOT NULL
         WINDOW w AS (PARTITION BY line, garage_no, stop_id ORDER BY observed_at)
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
           garage_no, LAG(garage_no) OVER w AS prev_g
         FROM raw_observations
         WHERE stops_remaining = 0
         WINDOW w AS (PARTITION BY line, stop_id ORDER BY observed_at)
       )
       WHERE gap > 60 AND gap < 7200 AND garage_no <> prev_g
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
  const entries = [...map.entries()];
  for (let i = 0; i < entries.length; i += INSERT_CHUNK) {
    const chunk = entries.slice(i, i + INSERT_CHUNK);
    const stmts = chunk.map(([key, b]) => {
      const [line, dow, hour] = key.split("|");
      return db
        .prepare(
          `INSERT INTO agg_line_time
             (line, dow, hour, samples, arrivals, headway_count, headway_secs_sum,
              speed_count, speed_stops_per_min_sum, updated_at)
           VALUES (?,?,?,?,?,?,?,?,?,?)`,
        )
        .bind(
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
        );
    });
    if (stmts.length) await db.batch(stmts);
  }

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
