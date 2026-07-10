export type VehicleType = "bus" | "tram" | "trolleybus";
export type ServiceStatus = "ok" | "unavailable";

export interface ArrivalDto {
  line: string;
  vehicle_type: VehicleType;
  eta_minutes: number;
  stops_remaining: number | null;
  route_id: string;
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
  route_id: string;
  origin: string;
  destination: string;
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
  flags: Record<string, boolean>;
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
