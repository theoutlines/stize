import type { Env } from "../../env";
import { aggregateSchedDelay, aggregateVehicles } from "./aggregateParts";
import { AGG_LINE_DIR_TIME_COLUMNS, AGG_LOOKBACK_SECONDS, HEADWAY_BUCKET_BOUNDS_SECS, HEADWAY_BUCKET_COUNT, eventsIn, resolveAggCatchupRows, resolveAggWindowSeconds } from "./shared";

// The roll-up of raw arrival events into per-line, per-hour metrics.

export interface Bucket {
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

export const emptyBucket = (line: string, dir: string, dow: number, hour: number): Bucket => ({
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
export function headwayHistogramSelect(): string {
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
 * hour) and the per-vehicle tables. **Windowed & incremental**:
 * each invocation processes at most one `config:agg_backfill_window_s` slice of
 * `observed_at` (default 1 day) starting at the `last_run` watermark, ADDS its
 * contributions to the existing buckets (additive/mergeable by design), and
 * advances the watermark to the window end. So the FIRST backfill converges over
 * several bounded runs instead of dying in one over-budget invocation, and once
 * caught up the daily run is a light increment (window end clamps to `now`). If
 * it is behind by more than a window but the whole backlog is under
 * `config:agg_catchup_max_rows`, it takes the backlog in one go (drift guard).
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
      .prepare("SELECT MIN(observed_at) AS m FROM arrival_events WHERE slot = (SELECT MIN(slot) FROM arrival_events)")
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
  let windowEnd = Math.min(now, cursor + windowSize);
  if (windowEnd < now) {
    // Behind by more than one window: if the entire backlog is small enough, take
    // it all now (see AGG_CATCHUP_ROWS_KV_KEY) so the watermark can't drift.
    const backlog = await db
      .prepare(`SELECT COUNT(*) AS n FROM ${eventsIn(cursor, now)} WHERE observed_at > ? AND observed_at <= ?`)
      .bind(cursor, now)
      .first<{ n: number }>();
    if ((backlog?.n ?? 0) <= (await resolveAggCatchupRows(env))) windowEnd = now;
  }
  const caughtUp = windowEnd >= now;
  // Lookback so a headway/speed pair straddling the window's start still resolves.
  const windowStart = Math.max(0, cursor - AGG_LOOKBACK_SECONDS);

  const map = new Map<string, Bucket>();
  const at = (line: string, dir: string, dow: number, hour: number): Bucket => {
    const k = `${line}\u0000${dir}\u0000${dow}\u0000${hour}`;
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
       FROM ${eventsIn(cursor, windowEnd)}
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
         FROM ${eventsIn(windowStart, windowEnd)}
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
         FROM ${eventsIn(windowStart, windowEnd)}
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
  // stalling the whole aggregate).
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

  // No raw prune: raw is kept indefinitely (see the note at the top of this file).

  return { buckets: map.size, from: cursor, to: windowEnd, caughtUp };
}

export const AGG_UPSERT_SET =
  "samples=samples+excluded.samples, arrivals=arrivals+excluded.arrivals, " +
  "headway_count=headway_count+excluded.headway_count, headway_secs_sum=headway_secs_sum+excluded.headway_secs_sum, " +
  Array.from({ length: HEADWAY_BUCKET_COUNT }, (_, i) => `hb${i}=hb${i}+excluded.hb${i}`).join(", ") +
  ", speed_count=speed_count+excluded.speed_count, " +
  "speed_stops_per_min_sum=speed_stops_per_min_sum+excluded.speed_stops_per_min_sum, " +
  "updated_at=excluded.updated_at";

export function bucketRow(b: Bucket, now: number): (string | number)[] {
  return [b.line, b.dir, b.dow, b.hour, b.samples, b.arrivals, b.headway_count, b.headway_secs_sum, ...b.hist, b.speed_count, b.speed_stops_per_min_sum, now];
}

/**
 * Per-vehicle aggregates, incremental. Totals/arrivals are additive; first_seen
 * takes the min and last_seen the max, so merging a new window is exact. Real
 * vehicles only (NULL vehicle_id excluded). Reads only new rows (activity) or the
 * lookback window (speed), mirroring the line-level aggregate.
 */
