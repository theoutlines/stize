import type { Env } from "../env";
import type { FeedMeta, LineDto, RouteShapeResponse, StopDto } from "../types";
import type { DirectionEndpoints } from "./direction";
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

export async function getRouteShape(env: Env, routeId: string): Promise<RouteShapeResponse | null> {
  const res = await fetchAsset(env, `/gtfs/shapes/${encodeURIComponent(routeId)}.json`);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Failed to load shape for ${routeId}: ${res.status}`);
  return (await res.json()) as RouteShapeResponse;
}
