import type { Env } from "../../env";
import type { ArrivalDto } from "../../types";
import { FIX_HEARTBEAT_MS, FROZEN_MOVE_M } from "./config";

// The last-fix table: recordVehicleFixes, fired from the arrivals refresh.

export interface VehicleFixRow {
  garage_no: string;
  line: string;
  direction_route_id: string | null;
  vehicle_type: string | null;
  lat: number;
  lon: number;
  stops_remaining: number | null;
  moved_at: number;
  seen_at: number;
  board_at: number;
}

// Approx metre→degree at Belgrade latitude, for the SQL bounding-box "moved"
// proxy (avoids a haversine in SQL). 30 m ≈ 0.00027° lat, ≈ 0.00038° lon.
export const DEG_LAT_30M = FROZEN_MOVE_M / 111_000;
export const DEG_LON_30M = FROZEN_MOVE_M / (111_000 * Math.cos((44.8 * Math.PI) / 180));

/**
 * Upsert one board's live vehicles into the last-fix table. `moved_at` is bumped
 * only when the fix actually moved (>=~30 m by bounding box) or `stops_remaining`
 * changed. Idempotent and batched; safe to fire-and-forget from ctx.waitUntil.
 *
 * Write budget (D1 free tier, rows_written is the scarce resource — see
 * docs/reports/2026-10-05-d1-write-budget.md). A row update costs 2 written rows
 * (row + the `seen_at` index), and the same vehicle sits on the boards of many
 * stops, so this used to rewrite every vehicle on every board (~23% of all D1
 * writes). Now:
 *   • only TRAM-line vehicles are recorded — jams and bus substitutions are
 *     computed for tram lines only, and the feed-health gate works on the same
 *     tram sample (`vehicle_type` here is the LINE's type, so a substitute bus on
 *     a tram line is still recorded);
 *   • an existing row is rewritten only on a REAL change: a newer board AND
 *     (moved >=30 m, or a different line/direction, or the heartbeat is due).
 *     `stops_remaining` alone does not trigger a write — it is relative to the
 *     stop whose board carried the fix, so it differs between the boards of two
 *     stops even for a parked vehicle.
 * The table is bounded by the tram fleet (one row per garage, upserted in place),
 * so there is no prune — a DELETE would only churn rows that get re-inserted.
 */
export async function recordVehicleFixes(
  env: Env,
  boardAt: number,
  arrivals: ArrivalDto[],
  now: number,
): Promise<void> {
  const db = env.STIGLA_ANALYTICS_DB;
  const moved =
    `(abs(excluded.lat - vehicle_fixes.lat) > ${DEG_LAT_30M}` +
    ` OR abs(excluded.lon - vehicle_fixes.lon) > ${DEG_LON_30M})`;
  const stmt = db.prepare(
    `INSERT INTO vehicle_fixes
       (garage_no, line, direction_route_id, vehicle_type, lat, lon, stops_remaining, moved_at, seen_at, board_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?9)
     ON CONFLICT(garage_no) DO UPDATE SET
       line = excluded.line,
       direction_route_id = excluded.direction_route_id,
       vehicle_type = excluded.vehicle_type,
       moved_at = CASE
         WHEN ${moved}
           OR excluded.stops_remaining IS NOT vehicle_fixes.stops_remaining
         THEN excluded.seen_at
         ELSE vehicle_fixes.moved_at END,
       lat = excluded.lat,
       lon = excluded.lon,
       stops_remaining = excluded.stops_remaining,
       seen_at = excluded.seen_at,
       board_at = excluded.board_at
     WHERE excluded.board_at > vehicle_fixes.board_at
       AND (${moved}
         OR excluded.line IS NOT vehicle_fixes.line
         OR excluded.direction_route_id IS NOT vehicle_fixes.direction_route_id
         OR excluded.seen_at - vehicle_fixes.seen_at >= ${FIX_HEARTBEAT_MS})`,
  );

  const batch = [];
  const seen = new Set<string>();
  for (const a of arrivals) {
    if (a.source === "scheduled" || !a.gps || !a.garage_no) continue;
    if (a.vehicle_type !== "tram") continue; // jams are tram-only (see above)
    if (seen.has(a.garage_no)) continue; // one row per garage per board
    seen.add(a.garage_no);
    batch.push(
      stmt.bind(
        a.garage_no,
        a.line,
        a.direction_route_id ?? a.route_id ?? null,
        a.vehicle_type,
        a.gps.lat,
        a.gps.lon,
        a.stops_remaining,
        now,
        boardAt,
      ),
    );
  }
  if (batch.length === 0) return;
  await db.batch(batch);
}
