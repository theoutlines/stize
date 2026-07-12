import type { Env } from "../env";
import type { LineDto, RouteShapeResponse, StopDto } from "../types";
import { haversineDistanceMeters } from "./haversine";

// GTFS bundles are static assets built by scripts/build-gtfs.mjs. They only
// change on redeploy, so cache the parsed arrays for the lifetime of the
// isolate instead of re-fetching/parsing per request.
let stopsCache: StopDto[] | null = null;
let linesCache: LineDto[] | null = null;

async function fetchAsset(env: Env, path: string): Promise<Response> {
  return env.ASSETS.fetch(new URL(path, "https://assets.internal"));
}

async function loadStops(env: Env): Promise<StopDto[]> {
  if (stopsCache) return stopsCache;
  const res = await fetchAsset(env, "/gtfs/stops.json");
  if (!res.ok) throw new Error(`Failed to load stops.json: ${res.status}`);
  const body = (await res.json()) as { stops: StopDto[] };
  stopsCache = body.stops;
  return stopsCache;
}

async function loadLines(env: Env): Promise<LineDto[]> {
  if (linesCache) return linesCache;
  const res = await fetchAsset(env, "/gtfs/lines.json");
  if (!res.ok) throw new Error(`Failed to load lines.json: ${res.status}`);
  const body = (await res.json()) as { lines: LineDto[] };
  linesCache = body.lines;
  return linesCache;
}

// Full dumps, for the client's on-device offline reference cache.
export async function getAllStops(env: Env): Promise<StopDto[]> {
  return loadStops(env);
}

export async function getAllLines(env: Env): Promise<LineDto[]> {
  return loadLines(env);
}

export async function getStopById(env: Env, stopId: string): Promise<StopDto | null> {
  const stops = await loadStops(env);
  return stops.find((s) => s.stop_id === stopId) ?? null;
}

export async function searchStops(env: Env, query: string): Promise<StopDto[]> {
  const stops = await loadStops(env);
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return stops.filter((s) => s.name.toLowerCase().includes(q)).slice(0, 50);
}

export async function nearbyStops(
  env: Env,
  lat: number,
  lon: number,
  radiusMeters: number,
): Promise<StopDto[]> {
  const stops = await loadStops(env);
  return stops
    .map((s) => ({ stop: s, distance: haversineDistanceMeters({ lat, lon }, { lat: s.lat, lon: s.lon }) }))
    .filter((x) => x.distance <= radiusMeters)
    .sort((a, b) => a.distance - b.distance)
    .slice(0, 50)
    .map((x) => x.stop);
}

// The single GTFS stop closest to a coordinate. Used to turn a vehicle's route
// terminus (a bare lat/lon from the live feed) into a human stop name = the
// arrival's travel direction. The stops array is isolate-cached, so this is an
// in-memory scan.
export async function nearestStop(env: Env, gps: { lat: number; lon: number }): Promise<StopDto | null> {
  const stops = await loadStops(env);
  let best: StopDto | null = null;
  let bestDist = Infinity;
  for (const s of stops) {
    const d = haversineDistanceMeters(gps, { lat: s.lat, lon: s.lon });
    if (d < bestDist) {
      bestDist = d;
      best = s;
    }
  }
  return best;
}

// Both GTFS directions of a line number (each direction is its own entry, F8),
// for matching a resolved terminus name back to a direction_id.
export async function getLineDirections(env: Env, line: string): Promise<LineDto[]> {
  const lines = await loadLines(env);
  const q = line.toLowerCase();
  return lines.filter((l) => l.line.toLowerCase() === q);
}

export async function searchLines(env: Env, query: string): Promise<LineDto[]> {
  const lines = await loadLines(env);
  const q = query.trim().toLowerCase();
  if (!q) return [];
  return lines.filter((l) => l.line.toLowerCase().includes(q)).slice(0, 50);
}

export async function getLineByNumber(env: Env, line: string): Promise<LineDto | null> {
  const lines = await loadLines(env);
  return lines.find((l) => l.line.toLowerCase() === line.toLowerCase()) ?? null;
}

export async function getRouteShape(env: Env, routeId: string): Promise<RouteShapeResponse | null> {
  const res = await fetchAsset(env, `/gtfs/shapes/${encodeURIComponent(routeId)}.json`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Failed to load shape for ${routeId}: ${res.status}`);
  return (await res.json()) as RouteShapeResponse;
}
