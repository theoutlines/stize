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
  // Column-wise copy of stops.json (scripts/compact-stops.mjs): ~6x cheaper to
  // parse on a cold isolate, which keeps /arrivals under the 10 ms CPU limit.
  const res = await fetchAsset(env, "/gtfs/stops.compact.json");
  if (!res.ok) throw new Error(`Failed to load stops.compact.json: ${res.status}`);
  const c = (await res.json()) as {
    stop_id: string[]; name: string[]; lat: number[]; lon: number[]; lines: string[]; types: string[];
  };
  const out: StopDto[] = new Array(c.stop_id.length);
  for (let i = 0; i < c.stop_id.length; i++) {
    out[i] = {
      stop_id: c.stop_id[i],
      name: c.name[i],
      lat: c.lat[i],
      lon: c.lon[i],
      lines: c.lines[i] ? c.lines[i].split(",") : [],
      // Absent in the source stays absent (the client falls back to its index).
      types: c.types[i] ? (c.types[i].split(",") as StopDto["types"]) : undefined,
    } as StopDto;
  }
  stopsCache = out;
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

/// The number printed on the stop's sign in Belgrade ("šifra stajališta") is
/// the GTFS stop_id minus 20000 (20830 → "830"). Null for an id outside that
/// scheme, so a future feed with other ids never invents a code.
export function stopCode(stopId: string): string | null {
  if (!/^2\d{4}$/.test(stopId)) return null;
  return String(Number(stopId) - 20000);
}

const CODE_QUERY = /^\d{1,4}$/;
const MAX_CODE_MATCHES = 10;
// Number prefixes start at three digits: shorter numbers are line numbers far
// more often, and 8 or 83 would list dozens of unrelated stops.
const MIN_PREFIX_DIGITS = 3;

/// Name substring search, plus sign-number search for an all-digit query: the
/// exact number first, then (from three digits) numbers that start with it
/// (830 → 8300…8309), then name matches ("Blok 25" for "25"). Shared contract with
/// the client's offline search (app/lib/core/search.dart searchStopsLocal).
export function searchStopsIn(stops: StopDto[], query: string): StopDto[] {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const byCode: StopDto[] = [];
  if (CODE_QUERY.test(q)) {
    const n = String(Number(q));
    const exact: StopDto[] = [];
    const prefix: StopDto[] = [];
    for (const s of stops) {
      const code = stopCode(s.stop_id);
      if (code === null) continue;
      if (code === n) exact.push(s);
      else if (q.length >= MIN_PREFIX_DIGITS && code.startsWith(n)) prefix.push(s);
    }
    prefix.sort((a, b) => Number(a.stop_id) - Number(b.stop_id));
    byCode.push(...exact, ...prefix.slice(0, MAX_CODE_MATCHES));
  }
  const seen = new Set(byCode.map((s) => s.stop_id));
  const byName = stops.filter((s) => !seen.has(s.stop_id) && s.name.toLowerCase().includes(q));
  return [...byCode, ...byName].slice(0, 50);
}

export async function searchStops(env: Env, query: string): Promise<StopDto[]> {
  return searchStopsIn(await loadStops(env), query);
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

// route_id -> LineDto, cached for the isolate. Labels each scheduled map
// object with its line/vehicle_type.
let routeMetaCache: Map<string, LineDto> | null = null;
async function routeMeta(env: Env): Promise<Map<string, LineDto>> {
  if (routeMetaCache) return routeMetaCache;
  const lines = await loadLines(env);
  routeMetaCache = new Map(lines.map((l) => [l.route_id, l] as const));
  return routeMetaCache;
}
export async function getLineDtoByRouteId(env: Env, routeId: string): Promise<LineDto | undefined> {
  return (await routeMeta(env)).get(routeId);
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
