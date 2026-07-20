import type { Env } from "../env";
import type { ArrivalDto, VehicleType } from "../types";
import { haversineDistanceMeters } from "./haversine";
import { getLineDirectionEndpoints, getRouteShape, getAllLines, getRouteTrips } from "./gtfsData";

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
const TERMINAL_RADIUS_M = 150; // a fix this close to a direction terminus is a legit layover
const CLUSTER_RADIUS_M = 600; // two frozen vehicles this close = "same segment"
const SEEN_RECENT_MS = 120_000; // ignore vehicles not observed in the last 2 min
const FEED_HEALTH_WINDOW_MS = 90_000; // "moved recently" window for the feed-health gate
const FEED_HEALTHY_MIN_MOVING = 0.35; // below this moving fraction the feed is starving → suppress
const MIN_FEED_SAMPLE = 6; // don't judge feed health on too few vehicles
const PRUNE_AGE_MS = 10 * 60_000; // drop rows older than this

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

async function readJamConfig(env: Env): Promise<JamConfig> {
  const num = async (key: string, def: number, lo: number, hi: number) => {
    const raw = await env.STIGLA_KV.get(`config:${key}`);
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
const DOWNSTREAM_STOP_FALLBACK = 6;
// Never let the horizon paint half the city even on a very fast line.
const DOWNSTREAM_STOP_HARD_CAP = 20;

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
async function avgSegmentSeconds(env: Env, routeId: string): Promise<number | null> {
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

export interface VehicleFixRow {
  garage_no: string;
  line: string;
  direction_route_id: string | null;
  vehicle_type: string | null;
  lat: number;
  lon: number;
  stops_remaining: number | null;
  moved_at: number;
  seen_at: number;
  board_at: number;
}

// Approx metre→degree at Belgrade latitude, for the SQL bounding-box "moved"
// proxy (avoids a haversine in SQL). 30 m ≈ 0.00027° lat, ≈ 0.00038° lon.
const DEG_LAT_30M = FROZEN_MOVE_M / 111_000;
const DEG_LON_30M = FROZEN_MOVE_M / (111_000 * Math.cos((44.8 * Math.PI) / 180));

/**
 * Upsert one board's live vehicles into the last-fix table. `moved_at` is bumped
 * only when the fix actually moved (>=~30 m by bounding box) or `stops_remaining`
 * changed; a re-read of the SAME board (board_at not newer) is a no-op via the
 * WHERE guard, so the feed's re-stamp sawtooth never resets a real freeze clock.
 * Idempotent and batched; safe to fire-and-forget from ctx.waitUntil.
 */
export async function recordVehicleFixes(
  env: Env,
  boardAt: number,
  arrivals: ArrivalDto[],
  now: number,
): Promise<void> {
  const db = env.STIGLA_ANALYTICS_DB;
  const stmt = db.prepare(
    `INSERT INTO vehicle_fixes
       (garage_no, line, direction_route_id, vehicle_type, lat, lon, stops_remaining, moved_at, seen_at, board_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?9)
     ON CONFLICT(garage_no) DO UPDATE SET
       line = excluded.line,
       direction_route_id = excluded.direction_route_id,
       vehicle_type = excluded.vehicle_type,
       moved_at = CASE
         WHEN abs(excluded.lat - vehicle_fixes.lat) > ${DEG_LAT_30M}
           OR abs(excluded.lon - vehicle_fixes.lon) > ${DEG_LON_30M}
           OR excluded.stops_remaining IS NOT vehicle_fixes.stops_remaining
         THEN excluded.seen_at
         ELSE vehicle_fixes.moved_at END,
       lat = excluded.lat,
       lon = excluded.lon,
       stops_remaining = excluded.stops_remaining,
       seen_at = excluded.seen_at,
       board_at = excluded.board_at
     WHERE excluded.board_at > vehicle_fixes.board_at`,
  );

  const batch = [];
  const seen = new Set<string>();
  for (const a of arrivals) {
    if (a.source === "scheduled" || !a.gps || !a.garage_no) continue;
    if (seen.has(a.garage_no)) continue; // one row per garage per board
    seen.add(a.garage_no);
    batch.push(
      stmt.bind(
        a.garage_no,
        a.line,
        a.direction_route_id ?? a.route_id ?? null,
        a.vehicle_type,
        a.gps.lat,
        a.gps.lon,
        a.stops_remaining,
        now,
        boardAt,
      ),
    );
  }
  if (batch.length === 0) return;
  await db.batch(batch);
}

/** Best-effort prune of stale rows (called opportunistically from /jams). */
export async function pruneVehicleFixes(env: Env, now: number): Promise<void> {
  await env.STIGLA_ANALYTICS_DB.prepare(`DELETE FROM vehicle_fixes WHERE seen_at < ?1`)
    .bind(now - PRUNE_AGE_MS)
    .run();
}

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

/**
 * Compute the current jam set from the last-fix table. Pure read + haversine;
 * no shape projection (that's the client's job). `simLine`, when set on staging,
 * injects a synthetic jam so a stand can be verified without a live jam.
 */
export async function computeJams(
  env: Env,
  now: number,
  opts: { simLine?: string | null } = {},
): Promise<JamsResponse> {
  const rows = (
    await env.STIGLA_ANALYTICS_DB.prepare(
      `SELECT garage_no, line, direction_route_id, vehicle_type, lat, lon, stops_remaining, moved_at, seen_at, board_at
         FROM vehicle_fixes WHERE seen_at >= ?1`,
    )
      .bind(now - SEEN_RECENT_MS)
      .all<VehicleFixRow>()
  ).results;

  // ── Feed-health gate (global suppression) ──
  // Over recently-seen vehicles of ALL types, the fraction that moved within the
  // last window. During feed starvation the board re-stamps but no fix moves, so
  // this collapses toward 0 and we suppress everything (better silent than wrong).
  let sample = 0;
  let moving = 0;
  for (const r of rows) {
    sample++;
    if (now - r.moved_at <= FEED_HEALTH_WINDOW_MS) moving++;
  }
  const feedHealthy = sample >= MIN_FEED_SAMPLE ? moving / sample >= FEED_HEALTHY_MIN_MOVING : true;

  const cfg = await readJamConfig(env);
  const tramLines = new Set(
    (await getAllLines(env)).filter((l) => l.vehicle_type === "tram").map((l) => l.line),
  );

  const jams: JamDto[] = [];
  const substitutions: SubstitutionDto[] = [];

  if (feedHealthy) {
    // ── Bus-substitution signal (independent of jams) ──
    const subByKey = new Map<string, SubstitutionDto>();
    for (const r of rows) {
      if (!tramLines.has(r.line)) continue;
      const gt = garageVehicleType(r.garage_no);
      if (gt === "bus") {
        const key = `${r.line}|${r.direction_route_id ?? ""}`;
        const s = subByKey.get(key) ?? {
          line: r.line,
          direction_route_id: r.direction_route_id,
          garage_nos: [],
        };
        s.garage_nos.push(r.garage_no);
        subByKey.set(key, s);
      }
    }
    substitutions.push(...subByKey.values());
    const substituteLines = new Set(substitutions.map((s) => s.line));

    // ── Frozen trams, terminals excluded ──
    // "Frozen" here already means BOTH the GPS is static (<30 m) AND
    // stops_remaining hasn't progressed — because `moved_at` is bumped whenever
    // EITHER changes (see recordVehicleFixes). So a slowly-crawling caravan
    // (bunching: still moving, still crossing stops) never reads as frozen and
    // never forms a jam cluster — bunching is a headway problem, not a stall, and
    // is left to the analytics headway-CV metric (report §7d), not alerted here.
    const frozen: (VehicleFixRow & { frozenSecs: number; isSub: boolean })[] = [];
    for (const r of rows) {
      if (!tramLines.has(r.line)) continue;
      const frozenSecs = Math.floor((now - r.moved_at) / 1000);
      // Cascading threshold: a substitute-bus-corroborated line relaxes furthest,
      // then the plain cluster threshold. (A lone vehicle never becomes a jam, so
      // the stricter single threshold isn't applied to cluster candidates.)
      const threshold = substituteLines.has(r.line) ? cfg.tSubstitute : cfg.tCluster;
      if (frozenSecs < threshold) continue;
      if (await isAtTerminal(env, r)) continue;
      frozen.push({ ...r, frozenSecs, isSub: garageVehicleType(r.garage_no) === "bus" });
    }

    // ── Cluster: >=2 frozen of the same direction within CLUSTER_RADIUS_M ──
    const byDir = new Map<string, typeof frozen>();
    for (const f of frozen) {
      const key = `${f.line}|${f.direction_route_id ?? ""}`;
      (byDir.get(key) ?? byDir.set(key, []).get(key)!).push(f);
    }
    for (const [, group] of byDir) {
      for (const cluster of clusterByProximity(group)) {
        if (cluster.length < cfg.clusterMin) continue;
        const geom = await enrichJamGeometry(env, cluster[0].direction_route_id, cluster, cfg.downstreamHorizonS);
        jams.push({
          line: cluster[0].line,
          direction_route_id: cluster[0].direction_route_id,
          vehicles: cluster.map((c) => ({
            garage_no: c.garage_no,
            lat: c.lat,
            lon: c.lon,
            stops_remaining: c.stops_remaining,
            frozen_secs: c.frozenSecs,
            is_substitute: c.isSub,
          })),
          frozen_secs: Math.max(...cluster.map((c) => c.frozenSecs)),
          has_substitute: cluster.some((c) => c.isSub),
          segment: geom.segment,
          affected_stop_ids: geom.affectedStopIds,
        });
      }
    }
  }

  // ── Staging simulation ──
  if (opts.simLine) {
    const sim = await buildSimulatedJam(env, opts.simLine, cfg.downstreamHorizonS);
    if (sim) {
      jams.push(sim.jam);
      if (sim.substitution) substitutions.push(sim.substitution);
    }
  }

  return {
    feed_healthy: feedHealthy,
    jams,
    substitutions,
    updated_at: new Date(now).toISOString(),
  };
}

/**
 * Cheap (ordering-only, no shape projection) jam geometry: bound the stalled span
 * by the rear vehicle's last stop and the front vehicle's next stop, and list the
 * affected stops — those WITHIN the span (under the red segment) plus the
 * downstream ones ahead of it (capped). Each vehicle is placed by its nearest stop
 * on the direction's ordered stop list (haversine sweep over ~30 stops).
 */
async function enrichJamGeometry(
  env: Env,
  directionRouteId: string | null,
  cluster: { lat: number; lon: number }[],
  downstreamHorizonS: number,
): Promise<{ segment: { rear: LatLon; front: LatLon } | null; affectedStopIds: string[] }> {
  if (!directionRouteId) return { segment: null, affectedStopIds: [] };
  const shape = await getRouteShape(env, directionRouteId);
  if (!shape || shape.stops.length < 2) return { segment: null, affectedStopIds: [] };
  const stops = [...shape.stops].sort((a, b) => a.seq - b.seq);
  const downstreamCap = await downstreamStopCount(env, directionRouteId, downstreamHorizonS);
  const nearestSeqIdx = (p: { lat: number; lon: number }) => {
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < stops.length; i++) {
      const d = haversineDistanceMeters(p, stops[i]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  };
  const idxs = cluster.map(nearestSeqIdx);
  const rearIdx = Math.max(0, Math.min(...idxs) - 1);
  const frontIdx = Math.min(stops.length - 1, Math.max(...idxs) + 1);
  const rearStop = stops[rearIdx];
  const frontStop = stops[frontIdx];
  // Within-span stops (under the red segment) + downstream stops ahead, capped by
  // TRAVEL TIME (downstreamCap = stops within the horizon), not a fixed count.
  const affectedStopIds = stops
    .slice(rearIdx, frontIdx + 1 + downstreamCap)
    .map((s) => s.stop_id);
  return {
    segment: { rear: { lat: rearStop.lat, lon: rearStop.lon }, front: { lat: frontStop.lat, lon: frontStop.lon } },
    affectedStopIds,
  };
}

async function isAtTerminal(env: Env, r: VehicleFixRow): Promise<boolean> {
  const dirs = await getLineDirectionEndpoints(env, r.line);
  const p = { lat: r.lat, lon: r.lon };
  for (const d of dirs) {
    // Match the vehicle's resolved direction when we have it; otherwise any
    // terminal of the line counts (conservative — excludes more, fires less).
    if (r.direction_route_id && d.routeId !== r.direction_route_id) continue;
    if (
      haversineDistanceMeters(p, d.origin) <= TERMINAL_RADIUS_M ||
      haversineDistanceMeters(p, d.destination) <= TERMINAL_RADIUS_M
    )
      return true;
  }
  // No direction match found but the line has terminals near the fix → still a
  // layover (handles the fallback where direction couldn't be resolved).
  if (r.direction_route_id && dirs.every((d) => d.routeId !== r.direction_route_id)) {
    for (const d of dirs) {
      if (
        haversineDistanceMeters(p, d.origin) <= TERMINAL_RADIUS_M ||
        haversineDistanceMeters(p, d.destination) <= TERMINAL_RADIUS_M
      )
        return true;
    }
  }
  return false;
}

// Single-link clustering by proximity: greedily grow clusters where each member
// is within CLUSTER_RADIUS_M of some other member. Small N (frozen trams), so a
// simple O(n^2) sweep is fine.
function clusterByProximity<T extends { lat: number; lon: number }>(items: T[]): T[][] {
  const clusters: T[][] = [];
  const used = new Set<number>();
  for (let i = 0; i < items.length; i++) {
    if (used.has(i)) continue;
    const cluster = [items[i]];
    used.add(i);
    let grew = true;
    while (grew) {
      grew = false;
      for (let j = 0; j < items.length; j++) {
        if (used.has(j)) continue;
        if (cluster.some((c) => haversineDistanceMeters(c, items[j]) <= CLUSTER_RADIUS_M)) {
          cluster.push(items[j]);
          used.add(j);
          grew = true;
        }
      }
    }
    clusters.push(cluster);
  }
  return clusters;
}

// Fabricate a jam on a real tram line+direction with real mid-route stop coords,
// so the client renders the full red segment + banner. `simLine` is a line number
// ("1") to force, or "auto"/"1"-with-empty to pick the first tram line with a
// usable shape. Staging only (the caller gates on ENVIRONMENT).
async function buildSimulatedJam(
  env: Env,
  simLine: string,
  downstreamHorizonS: number,
): Promise<{ jam: JamDto; substitution?: SubstitutionDto } | null> {
  const tramLines = (await getAllLines(env)).filter((l) => l.vehicle_type === "tram");
  const wanted = simLine && simLine !== "auto" && simLine !== "1" ? simLine : null;
  const candidates = wanted ? tramLines.filter((l) => l.line === wanted) : tramLines;
  for (const line of candidates) {
    const shape = await getRouteShape(env, line.route_id);
    if (!shape || shape.stops.length < 6) continue;
    const stops = [...shape.stops].sort((a, b) => a.seq - b.seq);
    const downstreamCap = await downstreamStopCount(env, line.route_id, downstreamHorizonS);
    const mid = Math.floor(stops.length / 2);
    const s1 = stops[mid];
    const s2 = stops[mid + 1];
    const rearIdx = Math.max(0, mid - 1);
    const frontIdx = Math.min(stops.length - 1, mid + 2);
    const rear = stops[rearIdx];
    const front = stops[frontIdx];
    return {
      jam: {
        line: line.line,
        direction_route_id: line.route_id,
        vehicles: [
          { garage_no: "SIM-A", lat: s1.lat, lon: s1.lon, stops_remaining: 5, frozen_secs: 360, is_substitute: false },
          { garage_no: "SIM-B", lat: s2.lat, lon: s2.lon, stops_remaining: 6, frozen_secs: 330, is_substitute: false },
        ],
        frozen_secs: 360,
        has_substitute: false,
        segment: { rear: { lat: rear.lat, lon: rear.lon }, front: { lat: front.lat, lon: front.lon } },
        affected_stop_ids: stops
          .slice(rearIdx, frontIdx + 1 + downstreamCap)
          .map((s) => s.stop_id),
        simulated: true,
      },
    };
  }
  return null;
}
