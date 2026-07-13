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
const MAX_STOPS_FANOUT = 12;
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
    stops.map((s) => getArrivals(env, ctx, s.stop_id).catch(() => null)),
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
      });
    }
  }

  return {
    vehicles: [...byVehicle.values()],
    updated_at: latest || new Date().toISOString(),
  };
}
