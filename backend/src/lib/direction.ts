import { haversineDistanceMeters } from "./haversine";

export interface DirectionEndpoints {
  routeId: string;
  origin: { lat: number; lon: number };
  destination: { lat: number; lon: number };
}

// A vehicle's resolved direction is only trusted when the winning direction is
// at least this much (metres, summed over both endpoints) better-matched than
// the runner-up. Otherwise the two directions are too alike to tell apart from
// the endpoints (short loops, near-identical terminals) and we fall back.
const AMBIGUITY_MARGIN_M = 300;

/**
 * Pick which direction of a line a live vehicle is travelling, by matching the
 * vehicle's own route (`all_stations`, ordered origin→destination) to each
 * direction's terminal coordinates. Deterministic: uses the trip's real
 * endpoints, not the vehicle's current position (which is ambiguous where the
 * two directions share a street).
 *
 * Returns the matching `route_id`, or null when it can't be told — a missing/
 * too-short route, a single-direction line handled by the caller, or two
 * directions too alike to distinguish. Callers fall back to the canonical
 * direction on null (never crash).
 */
export function resolveDirectionRouteId(
  routeStations: { lat: number; lon: number }[],
  directions: DirectionEndpoints[],
): string | null {
  if (directions.length <= 1) return null; // 0 or 1 direction: nothing to resolve
  if (routeStations.length < 2) return null; // no usable trip geometry

  const first = routeStations[0];
  const last = routeStations[routeStations.length - 1];

  let best: DirectionEndpoints | null = null;
  let bestScore = Infinity;
  let secondScore = Infinity;
  for (const d of directions) {
    const score =
      haversineDistanceMeters(first, d.origin) +
      haversineDistanceMeters(last, d.destination);
    if (score < bestScore) {
      secondScore = bestScore;
      bestScore = score;
      best = d;
    } else if (score < secondScore) {
      secondScore = score;
    }
  }

  if (best === null) return null;
  // Require a clear winner, else the endpoints don't distinguish the directions.
  if (secondScore - bestScore < AMBIGUITY_MARGIN_M) return null;
  return best.routeId;
}
