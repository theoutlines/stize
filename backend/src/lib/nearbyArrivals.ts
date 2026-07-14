import type { Env } from "../env";
import type {
  ArrivalDto,
  NearbyArrivalGroup,
  NearbyArrivalsResponse,
  StopDto,
} from "../types";
import { getArrivals } from "./arrivals";
import { getFlag } from "./featureFlags";
import { nearbyStops, getLineDtoByRouteId } from "./gtfsData";
import { haversineDistanceMeters } from "./haversine";
import type { WaitUntilCtx } from "./swrCache";

// The "Nearby" list reconstructs "which lines can I catch from here, and when"
// by fanning out to the arrivals of each nearby stop and grouping them by line +
// direction. It reuses the same bounded, cache-rate-limited fan-out as the map
// (nearbyStops + getArrivals), so it never storms the fragile upstream and each
// per-stop board rides the shared 30s stale-while-revalidate cache.
//
// The stop cap is deliberately below the vehicles-in-area fan-out's 18:
// aggregating this many cold per-stop boards (each a large upstream parse) in one
// request already sits near the Worker CPU budget (1102), and for a "what can I
// catch on foot" list the closest 8 stops are plenty. Do not raise these.
const MAX_STOPS_FANOUT = 8;
const MAX_RADIUS_METERS = 1500;

// Schedule (getArrivals includeSchedule:true) is inherited only for the nearest
// N stops of the fan-out — the rest stay live-only. Rationale: getStopSchedule is
// one uncached subrequest per stop (+ a parse), and an 8-wide schedule fan-out is
// the same shape of load that blew the map path's per-invocation CPU/subrequest
// budget (→ 503). The nearest stops are exactly where "never empty" matters (you
// walk to them), so schedule there buys the most for the least. This cap is
// deliberately conservative and *measured* on staging (densest point) before any
// raise — do not bump it on a hunch.
export const NEARBY_SCHEDULE_STOPS = 3;

// How many soonest departures to keep per row.
const MAX_ETAS_PER_GROUP = 2;

// --- Time-to-board sort (behind the nearby_sort_board flag) -----------------
// Ordering the list by bare ETA ignores how far you have to walk: a bus "2 min
// away" at a stop 300 m off is one you'd physically miss, and ranks above a bus
// "5 min away" at the stop under your feet. Time-to-board fixes that: it's the
// moment you'd actually be aboard = walk to the stop, then wait for the soonest
// departure you can still catch.

// Comfortable brisk walking pace, ~4.8 km/h. Distances here are straight-line
// (stop → user), so this is deliberately unhurried to offset real detours.
export const NEARBY_WALK_SPEED_M_PER_MIN = 80;
// A minute of slack: you can jog the last stretch to just catch a departure.
export const NEARBY_BOARD_GRACE_MIN = 1;
// If you can't reach *any* listed departure, you've missed the bus and wait for
// the next one, which we don't have a time for — approximate that wait. (A real
// per-line headway would replace this constant later.)
export const NEARBY_MISSED_DEPARTURE_PENALTY_MIN = 6;

// Minutes until you'd board, given the walk distance and the (ascending) ETAs of
// the listed departures. Returns the earliest departure you can still catch; if
// none is reachable, a walk-plus-penalty estimate that sorts such rows after the
// ones you can actually make.
export function timeToBoardMinutes(distanceMeters: number, etasMinutes: number[]): number {
  const walk = distanceMeters / NEARBY_WALK_SPEED_M_PER_MIN;
  for (const eta of etasMinutes) {
    if (walk <= eta + NEARBY_BOARD_GRACE_MIN) return eta;
  }
  return walk + NEARBY_MISSED_DEPARTURE_PENALTY_MIN;
}

export type NearbySortMode = "eta" | "board";

// One nearby stop with its board and its distance to the user.
export interface StopBoard {
  stop: StopDto;
  distanceMeters: number;
  board: { arrivals: ArrivalDto[]; updated_at: string };
}

// The direction a nearby row groups by: the direction the vehicle is actually
// travelling (`direction_route_id`), falling back to the canonical `route_id`.
// This is main's reliable, backend-resolved direction — it replaces the old
// terminus-name match and fixes the "→ None" rows the branch used to emit.
function directionKey(a: ArrivalDto): string {
  return a.direction_route_id ?? a.route_id;
}

// Pure aggregation: group arrivals across nearby stops by line + direction, keep
// only the stop closest to the user for each group (dedup), and sort the rows —
// by soonest ETA ("eta", default) or by time-to-board ("board"). Kept free of
// env/fetch so the grouping/dedup/sort rules are unit-testable in isolation.
// [boards] must be ordered nearest-stop-first. [destinationByRoute] maps a
// direction route_id to its human terminus name (resolved by the caller from
// GTFS line metadata); missing entries render as a null destination.
export function groupNearbyArrivals(
  boards: StopBoard[],
  destinationByRoute: Map<string, string | null> = new Map(),
  sortMode: NearbySortMode = "eta",
): NearbyArrivalGroup[] {
  const groups = new Map<string, NearbyArrivalGroup>();

  for (const { stop, distanceMeters, board } of boards) {
    // Bucket this stop's arrivals by line + direction first, so a group is
    // seeded from *all* of that line+direction's departures at this stop, not
    // just the first one encountered.
    const buckets = new Map<string, NearbyArrivalGroup>();
    for (const a of board.arrivals) {
      const key = `${a.line}|${directionKey(a)}`;
      // Since boards come nearest-first, the first stop that serves a group wins
      // it; a farther stop's copy of the same line+direction is dropped (dedup).
      if (groups.has(key)) continue;

      let bucket = buckets.get(key);
      if (!bucket) {
        const routeId = directionKey(a);
        bucket = {
          line: a.line,
          vehicle_type: a.vehicle_type,
          route_id: routeId,
          destination: destinationByRoute.get(routeId) ?? null,
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
        source: a.source,
      });
    }

    for (const [key, bucket] of buckets) {
      bucket.arrivals.sort((x, y) => x.eta_minutes - y.eta_minutes);
      bucket.arrivals = bucket.arrivals.slice(0, MAX_ETAS_PER_GROUP);
      groups.set(key, bucket);
    }
  }

  const sortKey = (g: NearbyArrivalGroup): number => {
    if (sortMode === "board") {
      return timeToBoardMinutes(g.distance_meters, g.arrivals.map((a) => a.eta_minutes));
    }
    return g.arrivals[0]?.eta_minutes ?? Number.POSITIVE_INFINITY;
  };

  return [...groups.values()].sort((a, b) => {
    const ka = sortKey(a);
    const kb = sortKey(b);
    if (ka !== kb) return ka - kb;
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
  // Load cap (see NEARBY_SCHEDULE_STOPS): how many of the nearest stops inherit
  // the schedule fallback. Overridable so a staging measurement can sweep it to
  // find the 503 boundary at the densest point; production uses the default.
  scheduleStops: number = NEARBY_SCHEDULE_STOPS,
): Promise<NearbyArrivalsResponse> {
  const radius = Math.min(radiusMeters, MAX_RADIUS_METERS);
  const stops = (await nearbyStops(env, lat, lon, radius)).slice(0, MAX_STOPS_FANOUT);

  const center = { lat, lon };
  const boards = await Promise.all(
    // `stops` is nearest-first, so index < scheduleStops selects the nearest N to
    // carry planned departures (never-empty where you'd walk); farther stops stay
    // live-only to keep the per-invocation schedule cost bounded.
    stops.map(async (stop, i): Promise<StopBoard | null> => {
      const board = await getArrivals(env, ctx, stop.stop_id, {
        includeSchedule: i < scheduleStops,
      }).catch(() => null);
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

  // Resolve each present direction's terminus name once (in-memory GTFS lookup,
  // no subrequests) so the pure grouping can label rows "→ <destination>".
  const destinationByRoute = new Map<string, string | null>();
  for (const b of present) {
    for (const a of b.board.arrivals) {
      const routeId = a.direction_route_id ?? a.route_id;
      if (!destinationByRoute.has(routeId)) {
        const line = await getLineDtoByRouteId(env, routeId);
        destinationByRoute.set(routeId, line?.destination ?? null);
      }
    }
  }

  const sortMode: NearbySortMode = (await getFlag(env, "nearby_sort_board")) ? "board" : "eta";
  const groups = groupNearbyArrivals(present, destinationByRoute, sortMode);

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
