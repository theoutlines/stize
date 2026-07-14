import type { Env } from "../env";
import { bearingDegrees, distanceToSegmentMeters } from "./haversine";

// One waypoint of a vehicle's forward timing plan: an absolute route position
// and how many seconds from *now* (the moment upstream produced this response)
// the vehicle is expected to reach it. The plan starts at the vehicle's current
// GPS (etaSeconds 0) and lists each downstream station ahead of it.
export interface TrajectoryPoint {
  lat: number;
  lon: number;
  etaSeconds: number;
}

export interface RawArrival {
  lineNumber: string;
  etaSeconds: number;
  stopsRemaining: number | null;
  garageNo: string | null;
  gps: { lat: number; lon: number } | null;
  // Travel direction in degrees (0 = north, clockwise), derived from the
  // vehicle's own route geometry, or null when it can't be determined.
  heading: number | null;
  // Forward timing plan built from `all_stations` (timed-trajectory feature):
  // where the vehicle will be and when, so the client can animate it smoothly by
  // time instead of easing to the last fix and stopping. Null when the upstream
  // gives no usable per-station timing.
  trajectory: TrajectoryPoint[] | null;
  // The vehicle's own trip, ordered origin→destination (parsed `all_stations`).
  // Used to resolve which direction of the line it's on. Empty when absent.
  routeStations: { lat: number; lon: number }[];
}

// Abstracts the upstream live-arrivals source. The concrete endpoint and its
// request shape live entirely in env vars (see backend/.dev.vars, never
// committed) — nothing about the real provider is hardcoded here or anywhere
// else in source, per the project's data-provider rule.
export interface TransitDataProvider {
  fetchArrivals(stopId: string): Promise<RawArrival[]>;
}

export class BgnaplataTransitProvider implements TransitDataProvider {
  constructor(private readonly env: Env) {}

  async fetchArrivals(stopId: string): Promise<RawArrival[]> {
    const extraFields = JSON.parse(this.env.TRANSIT_SOURCE_FORM_EXTRA_JSON) as Record<string, string>;
    const body = new URLSearchParams({
      r: stopId,
      b: generateClientId(),
      ...extraFields,
    });

    const res = await fetch(this.env.TRANSIT_SOURCE_BASE_URL, {
      method: "POST",
      headers: {
        "content-type": "application/x-www-form-urlencoded",
        accept: "application/json, text/javascript, */*; q=0.01",
        "x-requested-with": "XMLHttpRequest",
        "user-agent": `StiglaApp/0.1 (+${this.env.SOURCE_USER_AGENT_CONTACT}; personal use, low volume)`,
      },
      body: body.toString(),
    });

    if (!res.ok) {
      throw new Error(`Transit source responded ${res.status}`);
    }

    const raw = (await res.json()) as unknown;
    if (!Array.isArray(raw)) return [];

    return raw.map(parseRawArrival);
  }
}

export function parseRawArrival(item: unknown): RawArrival {
  const r = item as Record<string, unknown>;
  const vehicles = Array.isArray(r.vehicles) ? (r.vehicles as Record<string, unknown>[]) : [];
  const firstVehicle = vehicles[0];
  const rawGps =
    firstVehicle && typeof firstVehicle.lat === "string" && typeof firstVehicle.lng === "string"
      ? { lat: parseFloat(firstVehicle.lat), lon: parseFloat(firstVehicle.lng) }
      : null;
  const gps = rawGps && !Number.isNaN(rawGps.lat) && !Number.isNaN(rawGps.lon) ? rawGps : null;

  const routeStations = parseRouteStations(r.all_stations);

  return {
    lineNumber: String(r.line_number ?? ""),
    etaSeconds: typeof r.seconds_left === "number" ? r.seconds_left : 0,
    stopsRemaining: typeof r.stations_between === "number" ? r.stations_between : null,
    garageNo: typeof r.garage_no === "string" ? r.garage_no : null,
    gps,
    heading: gps ? headingFromRoute(gps, routeStations) : null,
    trajectory: gps ? parseTrajectory(gps, r.all_stations) : null,
    routeStations,
  };
}

// Upper bound on plan points we forward, so a pathological upstream route can't
// bloat the response. Real Belgrade trips have ~20-60 stations; this is well
// clear of that while still bounding the payload.
const MAX_TRAJECTORY_POINTS = 80;

// Build the forward timing plan from the vehicle's `all_stations`. Each entry
// carries `second_left_by_route`: the live estimated seconds from the vehicle's
// *current* position to that station (stations already behind read 0). We keep
// only the stations still ahead, prepend the current GPS at etaSeconds 0, and
// enforce a strictly increasing time axis so the client can invert it. Returns
// null unless there's at least one real step ahead to animate toward.
export function parseTrajectory(
  gps: { lat: number; lon: number },
  allStations: unknown,
): TrajectoryPoint[] | null {
  if (!Array.isArray(allStations)) return null;
  const points: TrajectoryPoint[] = [{ lat: gps.lat, lon: gps.lon, etaSeconds: 0 }];
  let lastEta = 0;
  for (const s of allStations as Record<string, unknown>[]) {
    const c = s?.coordinates as Record<string, unknown> | undefined;
    if (!c) continue;
    const lat = parseFloat(String(c.latitude));
    const lon = parseFloat(String(c.longitude));
    const eta = typeof s.second_left_by_route === "number" ? s.second_left_by_route : NaN;
    if (Number.isNaN(lat) || Number.isNaN(lon) || Number.isNaN(eta)) continue;
    // Only stations genuinely ahead of the vehicle (eta strictly growing). A
    // non-increasing eta is a station it has already passed or a duplicate.
    if (eta <= lastEta) continue;
    points.push({ lat, lon, etaSeconds: eta });
    lastEta = eta;
    if (points.length >= MAX_TRAJECTORY_POINTS) break;
  }
  return points.length >= 2 ? points : null;
}

// `all_stations` is the vehicle's own full trip, ordered origin -> destination,
// each entry `{ coordinates: { latitude, longitude } }`.
function parseRouteStations(value: unknown): { lat: number; lon: number }[] {
  if (!Array.isArray(value)) return [];
  const out: { lat: number; lon: number }[] = [];
  for (const s of value as Record<string, unknown>[]) {
    const c = s?.coordinates as Record<string, unknown> | undefined;
    if (!c) continue;
    const lat = parseFloat(String(c.latitude));
    const lon = parseFloat(String(c.longitude));
    if (!Number.isNaN(lat) && !Number.isNaN(lon)) out.push({ lat, lon });
  }
  return out;
}

// Travel direction at the vehicle's position: the bearing of the route segment
// it currently sits on, oriented origin -> destination (the direction of
// travel). Route-geometry based, so it doesn't jitter like a GPS-delta would.
export function headingFromRoute(
  gps: { lat: number; lon: number },
  routeStations: { lat: number; lon: number }[],
): number | null {
  if (routeStations.length < 2) return null;
  // Pick the route *segment* the vehicle is actually on — the one it sits
  // closest to — and take that segment's forward bearing (origin→destination).
  // Projecting onto segments (not snapping to the nearest station) keeps the
  // arrow pointing along the direction of travel even mid-block, and avoids the
  // failure where the nearest station is the one just passed, which would flip
  // the arrow onto the next segment.
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < routeStations.length - 1; i++) {
    const { distance } = distanceToSegmentMeters(gps, routeStations[i], routeStations[i + 1]);
    if (distance < bestDist) {
      bestDist = distance;
      bestIdx = i;
    }
  }
  return bearingDegrees(routeStations[bestIdx], routeStations[bestIdx + 1]);
}

function generateClientId(): string {
  const digits = Math.floor(Math.random() * 1e8)
    .toString()
    .padStart(8, "0");
  return `ST${digits}`;
}
