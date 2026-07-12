import type { Env } from "../env";
import type {
  ArrivalsResponse,
  NearbyArrivalGroup,
  NearbyArrivalsResponse,
  StopDto,
} from "../types";
import { getArrivals } from "./arrivals";
import { nearbyStops } from "./gtfsData";
import { haversineDistanceMeters } from "./haversine";
import type { WaitUntilCtx } from "./swrCache";

// The "Nearby" list reconstructs "which lines can I catch from here, and when"
// by fanning out to the arrivals of each nearby stop and grouping them by line +
// direction. The same bounds as the vehicles-in-area fan-out apply so a request
// can't storm the fragile upstream: ≤12 stops, ≤1500 m, each per-stop call
// riding the shared 30s stale-while-revalidate cache. Do not raise these.
const MAX_STOPS_FANOUT = 12;
const MAX_RADIUS_METERS = 1500;

// How many soonest departures to keep per row.
const MAX_ETAS_PER_GROUP = 2;

// One nearby stop with its live board and its distance to the user.
export interface StopBoard {
  stop: StopDto;
  distanceMeters: number;
  board: ArrivalsResponse;
}

// Pure aggregation: group arrivals across nearby stops by line + direction, keep
// only the stop closest to the user for each group (dedup), and sort rows by the
// soonest ETA. Kept free of env/fetch so the grouping/dedup/sort rules are
// unit-testable in isolation. [boards] must be ordered nearest-stop-first.
export function groupNearbyArrivals(boards: StopBoard[]): NearbyArrivalGroup[] {
  const groups = new Map<string, NearbyArrivalGroup>();

  for (const { stop, distanceMeters, board } of boards) {
    // Bucket this stop's arrivals by line + direction first, so a group is
    // seeded from *all* of that line+direction's departures at this stop, not
    // just the first one encountered.
    const buckets = new Map<string, NearbyArrivalGroup>();
    for (const a of board.arrivals) {
      const key = `${a.line}|${a.destination ?? a.direction_id ?? ""}`;
      // Since boards come nearest-first, the first stop that serves a group wins
      // it; a farther stop's copy of the same line+direction is dropped (dedup).
      if (groups.has(key)) continue;

      let bucket = buckets.get(key);
      if (!bucket) {
        bucket = {
          line: a.line,
          vehicle_type: a.vehicle_type,
          destination: a.destination,
          direction_id: a.direction_id,
          stop_id: stop.stop_id,
          stop_name: stop.name,
          distance_meters: Math.round(distanceMeters),
          arrivals: [],
        };
        buckets.set(key, bucket);
      }
      bucket.arrivals.push({
        eta_minutes: a.eta_minutes,
        garage_no: a.garage_no,
        stops_remaining: a.stops_remaining,
      });
    }

    for (const [key, bucket] of buckets) {
      bucket.arrivals.sort((x, y) => x.eta_minutes - y.eta_minutes);
      bucket.arrivals = bucket.arrivals.slice(0, MAX_ETAS_PER_GROUP);
      groups.set(key, bucket);
    }
  }

  return [...groups.values()].sort((a, b) => {
    const ea = a.arrivals[0]?.eta_minutes ?? Number.POSITIVE_INFINITY;
    const eb = b.arrivals[0]?.eta_minutes ?? Number.POSITIVE_INFINITY;
    if (ea !== eb) return ea - eb;
    // Tie-break by distance so the closer stop's line sits higher.
    return a.distance_meters - b.distance_meters;
  });
}

export async function getNearbyArrivals(
  env: Env,
  ctx: WaitUntilCtx,
  lat: number,
  lon: number,
  radiusMeters: number,
): Promise<NearbyArrivalsResponse> {
  const radius = Math.min(radiusMeters, MAX_RADIUS_METERS);
  const stops = (await nearbyStops(env, lat, lon, radius)).slice(0, MAX_STOPS_FANOUT);

  const center = { lat, lon };
  const boards = await Promise.all(
    stops.map(async (stop): Promise<StopBoard | null> => {
      const board = await getArrivals(env, ctx, stop.stop_id).catch(() => null);
      if (!board) return null;
      return {
        stop,
        distanceMeters: haversineDistanceMeters(center, { lat: stop.lat, lon: stop.lon }),
        board,
      };
    }),
  );

  // nearbyStops already returns nearest-first; keep that order for the dedup.
  const present = boards.filter((b): b is StopBoard => b !== null);
  const groups = groupNearbyArrivals(present);

  let latest = "";
  for (const b of present) {
    if (b.board.updated_at > latest) latest = b.board.updated_at;
  }

  return {
    groups,
    updated_at: latest || new Date().toISOString(),
    service_status: "ok",
  };
}
