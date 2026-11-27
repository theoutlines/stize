import { EVENT_SLOT_SECONDS } from "./shared";
import type { Env } from "../../env";
import type { RawArrival } from "../transitProvider";
import { getFlagMemoized } from "../featureFlags";
import type { WaitUntilCtx } from "../swrCache";
import { getLineByNumber, getLineDirectionEndpoints } from "../gtfsData";
import { resolveDirectionRouteId } from "../direction";

// Writing raw arrival observations (the request path).

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
export async function resolveObservationDirection(env: Env, r: RawArrival): Promise<string | null> {
  const lineMeta = await getLineByNumber(env, r.lineNumber);
  const canonical = lineMeta?.route_id ?? null;
  if (!r.gps) return canonical;
  const directions = await getLineDirectionEndpoints(env, r.lineNumber);
  return resolveDirectionRouteId(r.routeStations, directions) ?? canonical;
}

/**
 * Record arrival events from the board we just fetched (analytics v3,
 * the transport analytics spec (internal)).
 *
 * Flag-gated (`analytics_collect`) and called inside `ctx.waitUntil` from the
 * *fresh-fetch* path only, so it adds **zero** load on the source. Only
 * vehicles that are AT the stop (`stops_remaining = 0`) with a usable vehicle id
 * are written: one row per (5-min slot, stop, vehicle) via INSERT OR IGNORE on a
 * WITHOUT ROWID primary key, so the same arrival seen on several refreshes is
 * written once and an ignored duplicate costs 0 rows. Most refreshes write
 * nothing. The sweep's `stop_last_observed` bookkeeping (1 row per board) is
 * written only while the sweep is on, since only the sweep reads it.
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
  const slot = Math.floor(now / EVENT_SLOT_SECONDS);
  const stmts: D1PreparedStatement[] = [];
  const seen = new Set<string>();
  for (const r of raw) {
    if (r.stopsRemaining !== 0) continue;
    const vehicleId = vehicleIdOf(r.garageNo);
    if (!vehicleId || !r.garageNo || seen.has(vehicleId)) continue;
    seen.add(vehicleId);
    stmts.push(
      env.STIGLA_ANALYTICS_DB.prepare(
        `INSERT OR IGNORE INTO arrival_events
           (slot, stop_id, garage_no, vehicle_id, line, direction_route_id, observed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      ).bind(
        slot,
        stopId,
        r.garageNo,
        vehicleId,
        r.lineNumber,
        (await resolveObservationDirection(env, r)) ?? "",
        now,
      ),
    );
  }
  if (await getFlagMemoized(env, ctx, "analytics_sweep")) {
    stmts.push(
      env.STIGLA_ANALYTICS_DB.prepare(
        `INSERT INTO stop_last_observed (stop_id, observed_at) VALUES (?, ?)
         ON CONFLICT(stop_id) DO UPDATE SET observed_at = excluded.observed_at
         WHERE excluded.observed_at > stop_last_observed.observed_at`,
      ).bind(stopId, now),
    );
  }
  if (stmts.length > 0) await env.STIGLA_ANALYTICS_DB.batch(stmts);
}
