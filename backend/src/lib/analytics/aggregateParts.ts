import type { Env } from "../../env";
import { getScheduleMeta, getStopSchedule } from "../gtfsData";
import { activeServices, belgradeNow, type StopSchedule } from "../schedule";
import { AGG_VEHICLE_LINE_COLUMNS, AGG_VEHICLE_LINE_DOW_COLUMNS, OVERNIGHT_MINUTES, schedDelaySeconds, eventsIn } from "./shared";

// The roll-up's per-vehicle and schedule-delay parts, and the batch upsert.

export async function aggregateVehicles(
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
       FROM ${eventsIn(lo, hi)}
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
       FROM ${eventsIn(lo, hi)}
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
         FROM ${eventsIn(windowStart, hi)}
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
  const key = (v: string, l: string, d: number) => `${v}\u0000${l}\u0000${d}`;
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

export interface SchedBucket {
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
export async function aggregateSchedDelay(
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
       FROM ${eventsIn(lo, hi)}
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

export async function batchUpsert(
  db: D1Database,
  sql: string,
  rows: (string | number)[][],
): Promise<void> {
  const BATCH = 50;
  for (let i = 0; i < rows.length; i += BATCH) {
    await db.batch(rows.slice(i, i + BATCH).map((r) => db.prepare(sql).bind(...r)));
  }
}
