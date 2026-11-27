import type { Env } from "../../env";
import type { VehicleType } from "../../types";
import { getRouteTrips } from "../gtfsData";
import { kvGetCached } from "../kvCache";

// Thresholds, KV config, downstream stop counts and vehicle types for jam detection.

// Tram-jam ("stalled segment") detection. Two responsibilities, both cheap:
//
//  1. recordVehicleFixes — opportunistic bookkeeping fired from the existing SWR
//     arrivals refresh (no extra upstream calls). One row per `garage_no`,
//     overwritten in place; the only derived state is `moved_at` (when the fix
//     last actually moved). No geometry, no history — just a last-fix table so a
//     freshly-opened client sees an ongoing jam immediately (storage Variant B).
//
//  2. computeJams — reads that table and applies the conservative V1 rules the
//     Phase-0 measurement calibrated (see docs/reports/2026-07-20-jam-detection.md).
//     The heavy geometry (projecting the red segment onto the route shape, the
//     geometry gate, downstream-stop banners) stays on the CLIENT; the worker only
//     does haversine-cheap grouping and hands the client the segment's stops.
//
// ── Thresholds (Phase-0 calibrated; T_JAM is PRELIMINARY — see report §1.3) ──
// The 2026-07-20 window caught a pure feed-starvation baseline, not a live jam:
// natural freeze age p95 = 90s, max = 210s. T_JAM sits well above that so the
// detector cannot fire on the starvation sawtooth or a lone terminal dwell. It is
// validated for "does NOT false-positive"; it has NOT yet been checked against a
// real jam's magnitude, so treat it as a starting value.
export const FROZEN_MOVE_M = 30; // a fix within this of the last one hasn't "moved"
export const TERMINAL_RADIUS_M = 150; // a fix this close to a direction terminus is a legit layover
export const CLUSTER_RADIUS_M = 600; // two frozen vehicles this close = "same segment"
export const SEEN_RECENT_MS = 120_000; // ignore vehicles not observed in the last 2 min
export const FEED_HEALTH_WINDOW_MS = 90_000; // "moved recently" window for the feed-health gate
export const FEED_HEALTHY_MIN_MOVING = 0.35; // below this moving fraction the feed is starving → suppress
export const MIN_FEED_SAMPLE = 6; // don't judge feed health on too few vehicles
// A not-moving vehicle's row is rewritten at most this often, just to keep its
// `seen_at` fresh. Must stay well under SEEN_RECENT_MS so a frozen tram — exactly
// what a jam IS — never drops out of the "recently seen" set between rewrites.
export const FIX_HEARTBEAT_MS = 60_000;

// ── Cascading freeze thresholds — KV config, NOT hardcode (owner, round 2) ──
// The threshold to flag a stalled vehicle scales with signal strength, because a
// real stalled *cluster* is far less likely to be a fluke than a lone dwell:
//   • a lone frozen vehicle never becomes a jam on its own (a jam needs >=2), so
//     `single` is only a documentation anchor for any future lone indicator;
//   • >=2 vehicles of one direction stacked on an adjacent segment → `cluster`
//     (180s): a queue behind a light doesn't stack up two cars this long;
//   • a confirmed substitute bus on the line → halve again (`substitute`).
// T_JAM is PRELIMINARY (no live jam captured yet); these are the calibration
// knobs. Read from KV (`config:jam_*`), default here, clamped to sane bounds.
export const JAM_CONFIG_DEFAULTS = {
  tSingle: 300, // lone vehicle (not currently surfaced; kept for parity/anchor)
  tCluster: 180, // >=2 same-direction on an adjacent segment
  tSubstitute: 90, // a substitute bus corroborates the line → halve the cluster threshold
  clusterMin: 2, // >=2; NEVER 3 (would miss real jams on short/sparse lines)
} as const;

export const JAM_DOWNSTREAM_HORIZON_S_DEFAULT = 600; // ~10 min of travel ahead

export interface JamConfig {
  tSingle: number;
  tCluster: number;
  tSubstitute: number;
  clusterMin: number;
  downstreamHorizonS: number;
}

export async function readJamConfig(env: Env): Promise<JamConfig> {
  const num = async (key: string, def: number, lo: number, hi: number) => {
    const raw = await kvGetCached(env, `config:${key}`);
    const v = raw == null ? def : Number(raw);
    return Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : def;
  };
  const [tSingle, tCluster, tSubstitute, clusterMin, downstreamHorizonS] = await Promise.all([
    num("jam_t_single", JAM_CONFIG_DEFAULTS.tSingle, 60, 1800),
    num("jam_t_cluster", JAM_CONFIG_DEFAULTS.tCluster, 60, 1800),
    num("jam_t_substitute", JAM_CONFIG_DEFAULTS.tSubstitute, 30, 1800),
    num("jam_cluster_min", JAM_CONFIG_DEFAULTS.clusterMin, 2, 5),
    num("jam_downstream_horizon_s", JAM_DOWNSTREAM_HORIZON_S_DEFAULT, 120, 3600),
  ]);
  return { tSingle, tCluster, tSubstitute, clusterMin, downstreamHorizonS };
}

// Fallback downstream count when a line has no usable timetable to derive segment
// times from — a modest stop count so the banner still localizes.
export const DOWNSTREAM_STOP_FALLBACK = 6;
// Never let the horizon paint half the city even on a very fast line.
export const DOWNSTREAM_STOP_HARD_CAP = 20;

/**
 * How many downstream stops fall within [horizonS] seconds of travel past the
 * jam's front — derived from the line's MEAN segment time (a representative trip's
 * total run time / its segment count), NOT a fixed stop count. Beyond this the jam
 * shows up as an absence of live vehicles in the board anyway, so the banner there
 * only duplicates that emptiness and stretches the alert across half the city.
 */
export async function downstreamStopCount(
  env: Env,
  routeId: string,
  horizonS: number,
): Promise<number> {
  const avg = await avgSegmentSeconds(env, routeId);
  if (avg == null || avg <= 0) return DOWNSTREAM_STOP_FALLBACK;
  return Math.min(DOWNSTREAM_STOP_HARD_CAP, Math.max(1, Math.round(horizonS / avg)));
}

// Mean seconds between consecutive timed stops on a route. `TripTimed.times` are
// minutes since midnight, aligned to the shape stops — but the array carries
// quirks (an out-of-order first element; degenerate all-equal trips), so instead
// of trusting positions we take, per trip, (max − min) / (segments) and return the
// MEDIAN across trips. Null when the line carries no usable trip data.
export async function avgSegmentSeconds(env: Env, routeId: string): Promise<number | null> {
  const trips = await getRouteTrips(env, routeId);
  if (!trips || trips.length === 0) return null;
  const perTrip: number[] = [];
  for (const t of trips) {
    const nn = t.times.filter((x): x is number => x != null);
    if (nn.length < 3) continue;
    const spanMin = Math.max(...nn) - Math.min(...nn);
    if (spanMin <= 0) continue; // degenerate (all-equal) trip
    perTrip.push((spanMin * 60) / (nn.length - 1));
  }
  if (perTrip.length === 0) return null;
  perTrip.sort((a, b) => a - b);
  return perTrip[Math.floor(perTrip.length / 2)];
}

// Tram fleet garage-number ranges (mirror app/assets/data/fleet_models.json —
// classes with powertrain tram/trolleybus). Used ONLY for the bus-substitution
// signal: a bus-classified garage running a tram line. The line's own expected
// type comes from GTFS; this classifies the *vehicle*.
export function garageVehicleType(garageNo: string | null): VehicleType | "unknown" {
  if (!garageNo) return "unknown";
  const n = parseInt(garageNo.replace(/\D/g, ""), 10);
  if (Number.isNaN(n)) return "unknown";
  if ((n >= 80101 && n <= 80699) || (n >= 81500 && n <= 81560)) return "tram";
  if (n >= 82001 && n <= 82199) return "trolleybus";
  return "bus";
}
