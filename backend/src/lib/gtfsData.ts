import type { Env } from "../env";
import type { FeedMeta, LineDto, RouteShapeResponse, StopDto } from "../types";
import type { DirectionEndpoints } from "./direction";
import type { ScheduleMeta, StopSchedule, TripTimed } from "./schedule";
import { haversineDistanceMeters } from "./haversine";

// GTFS bundles are static assets built by scripts/build-gtfs.mjs. They only
// change on redeploy, so cache the parsed arrays for the lifetime of the
// isolate instead of re-fetching/parsing per request.
let stopsCache: StopDto[] | null = null;
let linesCache: LineDto[] | null = null;
let feedMetaCache: FeedMeta | null = null;

async function fetchAsset(env: Env, path: string): Promise<Response> {
  return env.ASSETS.fetch(new URL(path, "https://assets.internal"));
}

// Bundle freshness metadata (feed version + validity dates + build time), for
// the "Route data: <date>" line in the app. Written by build-gtfs.mjs. Returns
// null if the asset is missing (older bundle) — callers degrade silently.
export async function getFeedMeta(env: Env): Promise<FeedMeta | null> {
  if (feedMetaCache) return feedMetaCache;
  const res = await fetchAsset(env, "/gtfs/feed_meta.json");
  if (!res.ok) return null;
  feedMetaCache = (await res.json()) as FeedMeta;
  return feedMetaCache;
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

// route_id -> LineDto and line number -> route_ids, both cached for the isolate.
// Used to turn a viewport's stop lines into candidate route ids for scheduled
// map objects, and to label each object with its line/vehicle_type.
let routeMetaCache: { byRoute: Map<string, LineDto>; byLine: Map<string, string[]> } | null = null;
async function routeMaps(env: Env) {
  if (routeMetaCache) return routeMetaCache;
  const lines = await loadLines(env);
  const byRoute = new Map<string, LineDto>();
  const byLine = new Map<string, string[]>();
  for (const l of lines) {
    byRoute.set(l.route_id, l);
    const arr = byLine.get(l.line) ?? [];
    arr.push(l.route_id);
    byLine.set(l.line, arr);
  }
  routeMetaCache = { byRoute, byLine };
  return routeMetaCache;
}
export async function getLineDtoByRouteId(env: Env, routeId: string): Promise<LineDto | undefined> {
  return (await routeMaps(env)).byRoute.get(routeId);
}
export async function getRouteIdsForLines(env: Env, lineNumbers: Iterable<string>): Promise<string[]> {
  const { byLine } = await routeMaps(env);
  const out = new Set<string>();
  for (const ln of lineNumbers) for (const rid of byLine.get(ln) ?? []) out.add(rid);
  return [...out];
}

// Per-line terminal coordinates for each direction, derived once from lines.json
// (already isolate-cached) — no per-request shape loading. Feeds direction
// resolution (lib/direction.ts). Directions missing terminal coords are skipped.
const lineDirectionsCache = new Map<string, DirectionEndpoints[]>();
export async function getLineDirectionEndpoints(
  env: Env,
  line: string,
): Promise<DirectionEndpoints[]> {
  const key = line.toLowerCase();
  const cached = lineDirectionsCache.get(key);
  if (cached) return cached;
  const lines = await loadLines(env);
  const out: DirectionEndpoints[] = [];
  for (const l of lines) {
    if (l.line.toLowerCase() !== key) continue;
    if (
      typeof l.origin_lat === "number" &&
      typeof l.origin_lon === "number" &&
      typeof l.dest_lat === "number" &&
      typeof l.dest_lon === "number"
    ) {
      out.push({
        routeId: l.route_id,
        origin: { lat: l.origin_lat, lon: l.origin_lon },
        destination: { lat: l.dest_lat, lon: l.dest_lon },
      });
    }
  }
  lineDirectionsCache.set(key, out);
  return out;
}

// Schedule fallback (Phase 1): the shared calendar/service metadata (cached for
// the isolate — it's tiny and changes only on rebuild) and one stop's planned
// departures (fetched per stop, like shapes). Both return null when absent so
// callers degrade to live-only.
let scheduleMetaCache: ScheduleMeta | null = null;
export async function getScheduleMeta(env: Env): Promise<ScheduleMeta | null> {
  if (scheduleMetaCache) return scheduleMetaCache;
  const res = await fetchAsset(env, "/gtfs/schedule/_meta.json");
  if (!res.ok) return null;
  scheduleMetaCache = (await res.json()) as ScheduleMeta;
  return scheduleMetaCache;
}

export async function getStopSchedule(env: Env, stopId: string): Promise<StopSchedule | null> {
  const res = await fetchAsset(env, `/gtfs/schedule/${encodeURIComponent(stopId)}.json`);
  if (!res.ok) return null;
  return (await res.json()) as StopSchedule;
}

// A route's timetable trips (Phase 2 — scheduled map objects), fetched per route
// only for lines that lack a live vehicle, so a busy live viewport stays cheap.
// Cached per isolate (immutable per deploy) so repeated map refreshes don't
// re-fetch — the nearby path is subrequest-sensitive.
const routeTripsCache = new Map<string, TripTimed[] | null>();
export async function getRouteTrips(env: Env, routeId: string): Promise<TripTimed[] | null> {
  if (routeTripsCache.has(routeId)) return routeTripsCache.get(routeId)!;
  const res = await fetchAsset(env, `/gtfs/trips/${encodeURIComponent(routeId)}.json`);
  const trips = res.ok ? ((await res.json()) as { trips: TripTimed[] }).trips : null;
  routeTripsCache.set(routeId, trips);
  return trips;
}

const routeShapeCache = new Map<string, RouteShapeResponse | null>();
export async function getRouteShape(env: Env, routeId: string): Promise<RouteShapeResponse | null> {
  if (routeShapeCache.has(routeId)) return routeShapeCache.get(routeId)!;
  const res = await fetchAsset(env, `/gtfs/shapes/${encodeURIComponent(routeId)}.json`);
  if (res.status === 404) {
    routeShapeCache.set(routeId, null);
    return null;
  }
  if (!res.ok) throw new Error(`Failed to load shape for ${routeId}: ${res.status}`);
  const shape = (await res.json()) as RouteShapeResponse;
  routeShapeCache.set(routeId, shape);
  return shape;
}
