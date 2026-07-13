export type VehicleType = "bus" | "tram" | "trolleybus";
export type ServiceStatus = "ok" | "unavailable";

export interface ArrivalDto {
  line: string;
  vehicle_type: VehicleType;
  eta_minutes: number;
  stops_remaining: number | null;
  route_id: string; // canonical direction (bare route_id), unchanged
  // The route_id of the *direction this vehicle is actually travelling*, resolved
  // from its live route (`all_stations`). Falls back to the canonical route_id
  // when the direction can't be told. Lets the map stitch the vehicle to the
  // correct direction's shape instead of always the canonical one.
  direction_route_id?: string;
  gps: { lat: number; lon: number } | null;
  garage_no: string | null;
  heading: number | null;
}

// A single moving vehicle for the "all transport in the visible area" map view,
// reconstructed from per-stop arrivals and deduplicated by garage number.
export interface VehicleDto {
  line: string;
  vehicle_type: VehicleType;
  garage_no: string | null;
  lat: number;
  lon: number;
  heading: number | null;
  // Direction-resolved route_id (see ArrivalDto.direction_route_id) so the map
  // can draw the vehicle on the shape of the direction it's really going.
  route_id?: string;
}

export interface VehiclesResponse {
  vehicles: VehicleDto[];
  updated_at: string;
}

export interface ArrivalsResponse {
  stop_id: string;
  stop_name: string;
  updated_at: string;
  arrivals: ArrivalDto[];
  service_status: ServiceStatus;
}

export interface StopDto {
  stop_id: string;
  name: string;
  lat: number;
  lon: number;
  lines: string[];
}

export interface StopsResponse {
  stops: StopDto[];
}

export interface LineDto {
  line: string;
  vehicle_type: VehicleType;
  // Per-direction shape key: the canonical direction keeps the bare GTFS
  // route_id; the other direction is "{route_id}-{direction_id}" (F8).
  route_id: string;
  // GTFS direction_id ("0"/"1"). Both directions of a line are separate
  // entries, so a search surfaces the line both ways.
  direction_id?: string;
  origin: string;
  destination: string;
  // Terminal coordinates (origin/destination stop). Used to match a live
  // vehicle's own route to the correct direction (lib/direction.ts).
  origin_lat?: number;
  origin_lon?: number;
  dest_lat?: number;
  dest_lon?: number;
}

export interface LinesResponse {
  lines: LineDto[];
}

export interface RouteShapeStopDto {
  stop_id: string;
  name: string;
  lat: number;
  lon: number;
  seq: number;
}

export interface RouteShapeResponse {
  route_id: string;
  vehicle_type: VehicleType;
  origin: string;
  destination: string;
  polyline: [number, number][];
  stops: RouteShapeStopDto[];
}

export interface HealthResponse {
  status: "ok" | "killed";
  version: string;
}

// Runtime config the app fetches at startup: the API version plus remotely
// togglable feature flags (see lib/featureFlags.ts). Kept tiny and no-store so a
// flag flip reaches clients without a rebuild.
export interface ConfigResponse {
  version: string;
  environment: string; // "production" | "staging"
  flags: Record<string, boolean>;
}

// Bundle freshness metadata, written by scripts/build-gtfs.mjs into
// public/gtfs/feed_meta.json and served at GET /api/v1/gtfs-meta. Dates are ISO
// (YYYY-MM-DD) or null when the source feed omitted them.
export interface FeedMeta {
  feed_version: string | null; // GTFS feed_info.feed_version, e.g. "24"
  feed_start_date: string | null; // start of the feed's declared validity
  feed_end_date: string | null; // end of the feed's declared validity
  calendar_start: string | null; // widest service window across calendar.txt
  calendar_end: string | null;
  built_at: string; // ISO timestamp of the bundle build
  counts: { lines: number; stops: number; shapes: number };
}

// One time-bucket of a line's rolled-up analytics (by hour-of-day or day-of-
// week). Means are null when there weren't enough samples to measure them.
export interface AnalyticsBucket {
  key: number; // hour 0..23, or dow 0..6 (0=Sun)
  samples: number;
  arrivals: number;
  mean_headway_secs: number | null; // real interval between vehicles
  mean_speed_stops_per_min: number | null; // route progress rate
}

// One (day-of-week, hour) cell of the full grid — the 2D shape a heatmap and a
// distribution dot-plot need (the folded by_hour/by_dow lose it).
export interface AnalyticsCell {
  dow: number; // 0=Sun..6=Sat
  hour: number; // 0..23
  samples: number;
  arrivals: number;
  mean_headway_secs: number | null;
  mean_speed_stops_per_min: number | null;
}

export interface LineAnalyticsResponse {
  line: string;
  total_samples: number;
  by_hour: AnalyticsBucket[]; // 24 buckets
  by_dow: AnalyticsBucket[]; // 7 buckets
  grid: AnalyticsCell[]; // sparse: only populated (dow,hour) cells
  updated_at: number | null; // last aggregation run (unix secs)
  // Punctuality (delay vs GTFS schedule) is scaffolded but not yet computed —
  // it needs per-trip scheduled times; null means "not available yet".
  punctuality: null;
}

export interface IdeaDto {
  id: number;
  text: string;
  votes: number;
  created_at: string;
  has_voted: boolean;
}

export interface IdeaCommentDto {
  id: number;
  text: string;
  created_at: string;
}
