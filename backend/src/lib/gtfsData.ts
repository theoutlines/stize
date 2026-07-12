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

// Spatial grid over the stops for O(1)-ish nearest-stop lookup. A full linear
// scan per call was cheap once, but the "Nearby" fan-out resolves a terminus for
// *every* arrival across up to a dozen stops, so a few thousand-stop scans per
// call added up and blew the Worker's CPU budget (1102). Bucketing once by a
// ~0.005° grid (~400 m) turns each lookup into a small local search.
const GRID_DEG = 0.005;
let stopGrid: Map<string, StopDto[]> | null = null;

function gridKey(latCell: number, lonCell: number): string {
  return `${latCell}:${lonCell}`;
}

async function ensureStopGrid(env: Env): Promise<Map<string, StopDto[]>> {
  if (stopGrid) return stopGrid;
  const stops = await loadStops(env);
  const grid = new Map<string, StopDto[]>();
  for (const s of stops) {
    const key = gridKey(Math.floor(s.lat / GRID_DEG), Math.floor(s.lon / GRID_DEG));
    const bucket = grid.get(key);
    if (bucket) bucket.push(s);
    else grid.set(key, [s]);
  }
  stopGrid = grid;
  return grid;
}

// The single GTFS stop closest to a coordinate. Used to turn a vehicle's route
// terminus (a bare lat/lon from the live feed) into a human stop name = the
// arrival's travel direction. A terminus IS a stop, so it lands in its own cell;
// we widen the search ring only if nearby cells are empty, and fall back to a
// full scan in the (rare) pathological case.
export async function nearestStop(env: Env, gps: { lat: number; lon: number }): Promise<StopDto | null> {
  const grid = await ensureStopGrid(env);
  const latCell = Math.floor(gps.lat / GRID_DEG);
  const lonCell = Math.floor(gps.lon / GRID_DEG);

  const pick = (candidates: StopDto[]): StopDto | null => {
    let best: StopDto | null = null;
    let bestDist = Infinity;
    for (const s of candidates) {
      const d = haversineDistanceMeters(gps, { lat: s.lat, lon: s.lon });
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best;
  };

  // Grow the search box ring by ring; once any cell in a ring has stops, one
  // extra ring guarantees the true nearest isn't just outside the box.
  for (let ring = 0; ring <= 4; ring++) {
    const candidates: StopDto[] = [];
    for (let dLat = -ring; dLat <= ring; dLat++) {
      for (let dLon = -ring; dLon <= ring; dLon++) {
        // Only the newly-added outer ring (skip the interior we already saw).
        if (ring > 0 && Math.abs(dLat) !== ring && Math.abs(dLon) !== ring) continue;
        const bucket = grid.get(gridKey(latCell + dLat, lonCell + dLon));
        if (bucket) candidates.push(...bucket);
      }
    }
    if (candidates.length > 0) {
      // Search one more ring for correctness, then decide.
      const outer: StopDto[] = [];
      const r2 = ring + 1;
      for (let dLat = -r2; dLat <= r2; dLat++) {
        for (let dLon = -r2; dLon <= r2; dLon++) {
          if (Math.abs(dLat) !== r2 && Math.abs(dLon) !== r2) continue;
          const bucket = grid.get(gridKey(latCell + dLat, lonCell + dLon));
          if (bucket) outer.push(...bucket);
        }
      }
      return pick([...candidates, ...outer]);
    }
  }

  // Nothing within the searched box (extremely sparse): fall back to a scan.
  return pick(await loadStops(env));
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
