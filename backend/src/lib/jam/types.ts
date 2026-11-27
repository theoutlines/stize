
// What /api/v1/jams returns.

export interface JamVehicleDto {
  garage_no: string;
  lat: number;
  lon: number;
  stops_remaining: number | null;
  frozen_secs: number;
  is_substitute: boolean; // a bus-classified garage on this tram line
}

export interface LatLon {
  lat: number;
  lon: number;
}

export interface JamDto {
  line: string;
  direction_route_id: string | null;
  vehicles: JamVehicleDto[]; // >=2 frozen, on the same ~segment
  frozen_secs: number; // max across the cluster
  has_substitute: boolean; // a substitute bus is caught in this jam → highest confidence
  // Stop coords bounding the stalled span (rear vehicle's last stop → front
  // vehicle's next stop). The CLIENT projects these onto the direction shape and
  // draws the red segment — and applies the geometry gate (if the shape doesn't
  // faithfully carry the vehicles, it degrades to marker badges). Null when the
  // direction shape is unavailable (→ client shows badges, no segment).
  segment: { rear: LatLon; front: LatLon } | null;
  // Stops the jam affects: those WITHIN the stalled span (rear.seq..front.seq —
  // the stops sitting under the red segment, which a rider naturally taps) PLUS
  // the downstream stops ahead of it (capped). Both the delay banner and the stop
  // glow key off this union. Ordering only (GTFS seq) — no shape projection on the
  // worker. (Round-2 fix: within-segment stops used to be omitted, so tapping an
  // obviously-affected stop showed nothing.)
  affected_stop_ids: string[];
  simulated?: boolean; // staging-only synthetic jam
}

// A bus running a tram line, independent of any jam (planned track works also do
// this). Its own neutral notice; the client tones it down when a route alert
// already announced it.
export interface SubstitutionDto {
  line: string;
  direction_route_id: string | null;
  garage_nos: string[];
  simulated?: boolean;
}

export interface JamsResponse {
  feed_healthy: boolean; // false = feed starvation; the client shows nothing
  jams: JamDto[];
  substitutions: SubstitutionDto[];
  updated_at: string;
}
