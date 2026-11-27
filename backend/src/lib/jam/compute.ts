import type { Env } from "../../env";
import { haversineDistanceMeters } from "../haversine";
import { getLineDirectionEndpoints, getRouteShape, getAllLines } from "../gtfsData";
import { CLUSTER_RADIUS_M, FEED_HEALTHY_MIN_MOVING, FEED_HEALTH_WINDOW_MS, MIN_FEED_SAMPLE, SEEN_RECENT_MS, TERMINAL_RADIUS_M, downstreamStopCount, garageVehicleType, readJamConfig } from "./config";
import { VehicleFixRow } from "./fixes";
import { JamDto, JamsResponse, LatLon, SubstitutionDto } from "./types";

// computeJams: frozen vehicles grouped into jams, with their geometry.

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
  // Over recently-seen vehicles (tram lines only — that is all recordVehicleFixes
  // keeps since the 2026-10-05 write-budget fix), the fraction that moved within the
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
export async function enrichJamGeometry(
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

export async function isAtTerminal(env: Env, r: VehicleFixRow): Promise<boolean> {
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
export function clusterByProximity<T extends { lat: number; lon: number }>(items: T[]): T[][] {
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
export async function buildSimulatedJam(
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
