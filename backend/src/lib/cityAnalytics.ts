import type { Env } from "../env";
import { kvCacheRemember, kvGetCached } from "./kvCache";

// City section summary (the transport analytics spec (internal), "City section"): one
// precomputed JSON for the whole city, folded from agg_line_dir_time.
//
// Read cost is the reason it is precomputed: folding the table scans every row
// (lines × directions × 168 hour cells, tens of thousands). That runs once per
// daily aggregate (and once on a cold KV miss), never per request; requests
// read one KV key through the in-isolate cache.

export const CITY_KV_KEY = "analytics:city:v1";
const CITY_KV_TTL_SECONDS = 2 * 24 * 3600; // outlives one missed daily run

// Aggregates are bucketed by UTC dow/hour. The page speaks Belgrade time; data
// spans summer (UTC+2) and winter (UTC+1), so a fixed +1h shift is the honest
// middle: at worst a cell is off by one hour for the summer part.
const LOCAL_OFFSET_HOURS = 1;

// Evening for "longest real intervals": 21:00 to 00:59 local.
const EVENING_LOCAL_HOURS = new Set([21, 22, 23, 0]);

export type CityCell = {
  dow: number; // 0=Sun..6=Sat, Belgrade time
  hour: number; // 0..23, Belgrade time
  arrivals: number;
  delay_count: number;
  mean_delay_secs: number | null;
  headway_count: number;
  mean_headway_secs: number | null;
};

export type CityLine = {
  line: string;
  arrivals: number;
  delay_count: number;
  mean_delay_secs: number | null;
  headway_count: number;
  mean_headway_secs: number | null;
  evening_headway_count: number;
  evening_mean_headway_secs: number | null;
};

export type CitySummary = {
  computed_at: number; // unix seconds
  aggregated_to: number | null; // agg_state.last_run
  totals: {
    arrivals: number;
    delay_count: number;
    mean_delay_secs: number | null;
    headway_count: number;
    mean_headway_secs: number | null;
  };
  grid: CityCell[];
  lines: CityLine[];
};

type Row = {
  line: string;
  dow: number;
  hour: number;
  arrivals: number;
  headway_count: number;
  headway_secs_sum: number;
  sched_delay_count: number;
  sched_delay_secs_sum: number;
};

const mean = (sum: number, n: number) => (n > 0 ? Math.round(sum / n) : null);

/** Shift a UTC (dow, hour) bucket to Belgrade time. */
export function toLocal(dow: number, hour: number): { dow: number; hour: number } {
  const h = hour + LOCAL_OFFSET_HOURS;
  return { dow: (dow + Math.floor(h / 24) + 7) % 7, hour: ((h % 24) + 24) % 24 };
}

/** Fold aggregate rows (one per line × dow × hour, directions already summed). */
export function foldCity(rows: Row[], now: number, aggregatedTo: number | null): CitySummary {
  const cells = new Map<string, { a: number; dc: number; ds: number; hc: number; hs: number; dow: number; hour: number }>();
  const lines = new Map<string, { a: number; dc: number; ds: number; hc: number; hs: number; ec: number; es: number }>();
  const t = { a: 0, dc: 0, ds: 0, hc: 0, hs: 0 };
  for (const r of rows) {
    const { dow, hour } = toLocal(r.dow, r.hour);
    const key = `${dow}:${hour}`;
    const c = cells.get(key) ?? { a: 0, dc: 0, ds: 0, hc: 0, hs: 0, dow, hour };
    c.a += r.arrivals;
    c.dc += r.sched_delay_count;
    c.ds += r.sched_delay_secs_sum;
    c.hc += r.headway_count;
    c.hs += r.headway_secs_sum;
    cells.set(key, c);

    const l = lines.get(r.line) ?? { a: 0, dc: 0, ds: 0, hc: 0, hs: 0, ec: 0, es: 0 };
    l.a += r.arrivals;
    l.dc += r.sched_delay_count;
    l.ds += r.sched_delay_secs_sum;
    l.hc += r.headway_count;
    l.hs += r.headway_secs_sum;
    if (EVENING_LOCAL_HOURS.has(hour)) {
      l.ec += r.headway_count;
      l.es += r.headway_secs_sum;
    }
    lines.set(r.line, l);

    t.a += r.arrivals;
    t.dc += r.sched_delay_count;
    t.ds += r.sched_delay_secs_sum;
    t.hc += r.headway_count;
    t.hs += r.headway_secs_sum;
  }
  return {
    computed_at: now,
    aggregated_to: aggregatedTo,
    totals: {
      arrivals: t.a,
      delay_count: t.dc,
      mean_delay_secs: mean(t.ds, t.dc),
      headway_count: t.hc,
      mean_headway_secs: mean(t.hs, t.hc),
    },
    grid: [...cells.values()]
      .sort((x, y) => x.dow - y.dow || x.hour - y.hour)
      .map((c) => ({
        dow: c.dow,
        hour: c.hour,
        arrivals: c.a,
        delay_count: c.dc,
        mean_delay_secs: mean(c.ds, c.dc),
        headway_count: c.hc,
        mean_headway_secs: mean(c.hs, c.hc),
      })),
    lines: [...lines.entries()]
      .filter(([, l]) => l.a > 0)
      .sort((x, y) => y[1].a - x[1].a)
      .map(([line, l]) => ({
        line,
        arrivals: l.a,
        delay_count: l.dc,
        mean_delay_secs: mean(l.ds, l.dc),
        headway_count: l.hc,
        mean_headway_secs: mean(l.hs, l.hc),
        evening_headway_count: l.ec,
        evening_mean_headway_secs: mean(l.es, l.ec),
      })),
  };
}

/** Scan the aggregate table once and fold it. The only D1 read path here. */
export async function computeCitySummary(env: Env, now = Math.floor(Date.now() / 1000)): Promise<CitySummary> {
  const db = env.STIGLA_ANALYTICS_DB;
  const { results } = await db
    .prepare(
      `SELECT line, dow, hour,
              SUM(arrivals) AS arrivals,
              SUM(headway_count) AS headway_count, SUM(headway_secs_sum) AS headway_secs_sum,
              SUM(sched_delay_count) AS sched_delay_count, SUM(sched_delay_secs_sum) AS sched_delay_secs_sum
       FROM agg_line_dir_time
       GROUP BY line, dow, hour`,
    )
    .all<Row>();
  const lastRun = await db.prepare("SELECT value FROM agg_state WHERE key = 'last_run'").first<{ value: string }>();
  return foldCity(results, now, lastRun ? Number(lastRun.value) : null);
}

/** Recompute and store (called after the daily aggregate). */
export async function refreshCitySummary(env: Env): Promise<CitySummary> {
  const s = await computeCitySummary(env);
  const json = JSON.stringify(s);
  await env.STIGLA_KV.put(CITY_KV_KEY, json, { expirationTtl: CITY_KV_TTL_SECONDS });
  kvCacheRemember(env, CITY_KV_KEY, json);
  return s;
}

/**
 * The stored summary; on a cold miss compute it once (unless D1 reads are
 * constrained, then an empty summary) and store it.
 */
export async function getCitySummary(env: Env, readsAllowed: boolean): Promise<CitySummary> {
  const cached = await kvGetCached(env, CITY_KV_KEY);
  if (cached) return JSON.parse(cached) as CitySummary;
  if (!readsAllowed) return foldCity([], Math.floor(Date.now() / 1000), null);
  return refreshCitySummary(env);
}
