import type { Env } from "../env";
import type { VehicleDto, VehiclesResponse } from "../types";
import { getArrivals } from "./arrivals";
import { nearbyStops } from "./gtfsData";
import { haversineDistanceMeters } from "./haversine";
import type { WaitUntilCtx } from "./swrCache";

// The upstream is per-stop only, so "all vehicles in an area" is reconstructed
// by fanning out to the arrivals of each nearby stop and deduplicating the
// vehicles by garage number. These guards keep that fan-out bounded: a
// zoomed-out client can't trigger a request storm against the fragile source,
// and each per-stop call still rides the shared 30s stale-while-revalidate
// cache, so steady-state upstream load stays low.
// Widened 12 -> 18 so a panned viewport has fewer dead patches with no fresh
// fixes (which read as vehicles "standing still"). Each per-stop call still
// rides the shared 30s SWR cache, so steady-state upstream load rises at most
// ~50% worst-case, not per-user; the 30s-per-key cap is untouched. Watch the
// source for pushback at this fan-out.
const MAX_STOPS_FANOUT = 18;
// Only the nearest stops may trigger a real refresh (upstream fetch + cache write,
// 2 subrequests each); the outer ring reads the cache only. 18 refreshing stops
// plus their cache reads exceeded the free plan's 50 subrequests per invocation on
// a cold cache, failing the cache writes (audit 2026-11-22, A4; seen in logs).
const MAX_REFRESHING_STOPS = 12;
const MAX_RADIUS_METERS = 1500;

export async function getNearbyVehicles(
  env: Env,
  ctx: WaitUntilCtx,
  lat: number,
  lon: number,
  radiusMeters: number,
): Promise<VehiclesResponse> {
  const radius = Math.min(radiusMeters, MAX_RADIUS_METERS);
  const stops = (await nearbyStops(env, lat, lon, radius)).slice(0, MAX_STOPS_FANOUT);

  const boards = await Promise.all(
    // Map path: skip the schedule fallback *list* so an 18-stop fan-out doesn't
    // blow Cloudflare's per-invocation subrequest / CPU limits (→ 503). The map's
    // own scheduled objects are added once below, not per stop.
    stops.map((s, i) =>
      getArrivals(env, ctx, s.stop_id, {
        includeSchedule: false,
        cacheOnly: i >= MAX_REFRESHING_STOPS,
      }).catch(() => null),
    ),
  );

  const center = { lat, lon };
  const byVehicle = new Map<string, VehicleDto>();
  let latest = "";
  for (const board of boards) {
    if (!board) continue;
    if (board.updated_at > latest) latest = board.updated_at;
    for (const a of board.arrivals) {
      if (!a.gps) continue;
      // Only vehicles physically inside the requested area — the same bus shows
      // up in several stops' arrivals, often far outside the viewport.
      if (haversineDistanceMeters(center, a.gps) > radius) continue;
      const key = a.garage_no ?? `${a.line}:${a.gps.lat.toFixed(5)}:${a.gps.lon.toFixed(5)}`;
      if (byVehicle.has(key)) continue;
      byVehicle.set(key, {
        line: a.line,
        vehicle_type: a.vehicle_type,
        garage_no: a.garage_no,
        lat: a.gps.lat,
        lon: a.gps.lon,
        heading: a.heading,
        // Direction the vehicle is actually travelling, so the map draws it on
        // that direction's shape (falls back to canonical inside getArrivals).
        route_id: a.direction_route_id,
        // Carry the forward timing plan (timed-trajectory) and the as-of time it
        // is anchored to (this board's last successful upstream refresh). Both
        // are absent when the arrivals layer left `trajectory` off (flag off /
        // no plan), keeping the field additive.
        ...(a.trajectory
          ? { trajectory: a.trajectory, as_of: board.updated_at }
          : {}),
      });
    }
  }

  const asOf = latest || new Date().toISOString();
  const vehicles = [...byVehicle.values()];

  // No scheduled objects on the map (owner decision 2026-11-24): a planned
  // trip "in transit" without a live vehicle is by definition a trip that
  // already left the terminus untracked, i.e. a phantom. The map shows live only.

  return { vehicles, updated_at: asOf };
}

