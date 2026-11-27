import type { Env } from "../../env";

// Shared pieces of the transport analytics: config read from KV, D1 column
// lists and insert helpers, headway buckets, the schedule-delay match.

// Raw observations are kept INDEFINITELY — there is no retention prune. The
// account lives on the D1 free tier, where rows_written (100k/day) is the scarce
// resource and storage (5 GB) is not: every DELETE costs a written row per deleted
// row, so a 30-day prune would double the lifetime cost of every observation (and
// the 510k-row backlog alone would burn ~5 days of budget). See
// docs/reports/2026-10-05-d1-write-budget.md.

// Aggregation reads only raw newer than the last run, plus this much extra
// history so a windowed metric (headway/speed) whose earlier half sits just
// before the boundary is still computed correctly. Must cover the widest window
// filter below: headway gap < 7200s and speed dt < 1800s → 7200s is enough.
export const AGG_LOOKBACK_SECONDS = 7200;

// Max observed_at span processed per aggregate() invocation. On a fresh backfill
// the whole retained raw (hundreds of k rows, ~12M row-reads) can't fit one Cron
// invocation — it dies mid-write and never advances the watermark (see
// 2026-07-21-prod-backfill-verify.md). So each run processes AT MOST this much
// time, advances `last_run` to the window end, and the backfill CONVERGES over
// several bounded runs; once caught up the daily run is a light increment.
// Runtime-tunable (KV, no redeploy) so the window can be narrowed if a run still
// can't finish.
export const AGG_WINDOW_KV_KEY = "config:agg_backfill_window_s";
export const AGG_WINDOW_DEFAULT_SECONDS = 86400; // 1 day

// Watermark drift guard. The daily cron advances the watermark by AT MOST one
// window; once it fell behind by more than a window (a missed/failed run) it
// stayed exactly that far behind forever — each run moved it one day while a day
// passed — so `caughtUp` never came true (2026-10-05: lag ~35h before every run).
// When the whole remaining backlog is small, take it in one window and catch up.
// The bound is a raw ROW count (what the aggregate's CPU/read cost scales with),
// not a time span: a heavy organic day is ~16k rows. Runtime-tunable.
export const AGG_CATCHUP_ROWS_KV_KEY = "config:agg_catchup_max_rows";
export const AGG_CATCHUP_ROWS_DEFAULT = 50_000;

export async function resolveAggCatchupRows(env: Env): Promise<number> {
  const raw = await env.STIGLA_KV.get(AGG_CATCHUP_ROWS_KV_KEY);
  if (raw === null) return AGG_CATCHUP_ROWS_DEFAULT;
  const n = parseInt(raw, 10);
  return Number.isNaN(n) || n < 0 ? AGG_CATCHUP_ROWS_DEFAULT : n;
}

export async function resolveAggWindowSeconds(env: Env): Promise<number> {
  const raw = await env.STIGLA_KV.get(AGG_WINDOW_KV_KEY);
  if (raw === null) return AGG_WINDOW_DEFAULT_SECONDS;
  const n = parseInt(raw, 10);
  return Number.isNaN(n) || n <= 0 ? AGG_WINDOW_DEFAULT_SECONDS : n;
}

// D1 caps bound parameters at 100 per statement — far below SQLite's own 999
// default. The 2026-07-13 fix chunked by a fixed 40 *rows*, which for a 7-column
// insert is 280 params (2.8× the real cap): still "too many SQL variables". So
// the chunk must be derived from the column count, not a magic row constant.
export const D1_MAX_BOUND_PARAMS = 100;

// agg_line_dir_time columns written by the aggregate (sched_delay_* are left at
// their defaults here — populated in a follow-up step — so they're not listed).
export const AGG_LINE_DIR_TIME_COLUMNS = [
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

export const AGG_VEHICLE_LINE_COLUMNS = [
  "vehicle_id",
  "line",
  "samples",
  "arrivals",
  "first_seen",
  "last_seen",
  "updated_at",
] as const;

export const AGG_VEHICLE_LINE_DOW_COLUMNS = [
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
export const OVERNIGHT_MINUTES = 1440;
// How far an observed arrival may sit from a scheduled departure and still be
// attributed to it. Beyond this we can't tell which trip it was → no delay.
export const SCHED_MATCH_TOLERANCE_MIN = 30;

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

// --- v3 source: arrival events (the transport analytics spec (internal)) ---------------
// Collection now writes only the moment a vehicle reaches a stop, one row per
// (5-min slot, stop, vehicle), into `arrival_events` (migration 0010). The
// aggregate queries below were written against `raw_observations`; this
// subquery exposes the events under the same column names, pre-filtered by
// the slot primary key so the scan stays an indexed range. `stops_remaining`
// is 0 by definition, so the speed passes (which need several fixes of one
// vehicle approaching one stop) find no pairs: speed is out of v3 until it is
// derived from events at consecutive stops. The old `raw_observations` table is
// kept frozen as an archive and no longer read or written.
export const EVENT_SLOT_SECONDS = 300;
export function eventsIn(lo: number, hi: number): string {
  const a = Math.floor(Math.max(0, lo) / EVENT_SLOT_SECONDS) - 1;
  const b = Math.floor(hi / EVENT_SLOT_SECONDS) + 1;
  return `(SELECT line, stop_id, garage_no, vehicle_id, 0 AS eta_minutes,
      0 AS stops_remaining, observed_at, direction_route_id
    FROM arrival_events WHERE slot BETWEEN ${a} AND ${b})`;
}

// One (line, direction, dow, hour) bucket accumulated during an aggregate run.
