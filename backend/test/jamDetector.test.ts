import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  computeJams,
  garageVehicleType,
  recordVehicleFixes,
  JAM_CONFIG_DEFAULTS,
} from "../src/lib/jamDetector";

const T_CLUSTER = JAM_CONFIG_DEFAULTS.tCluster; // 180s — >=2 same-direction cluster
import { setFlag } from "../src/lib/featureFlags";
import { getAllLines, getLineDirectionEndpoints } from "../src/lib/gtfsData";
import type { ArrivalDto } from "../src/types";

const NOW = Date.UTC(2026, 6, 20, 12, 0, 0); // fixed instant

// Insert a last-fix row directly, for deterministic freeze ages.
async function seedFix(row: {
  garage: string;
  line: string;
  dir?: string | null;
  lat: number;
  lon: number;
  remain?: number | null;
  movedSecsAgo: number;
  seenSecsAgo?: number;
}) {
  await env.STIGLA_ANALYTICS_DB.prepare(
    `INSERT INTO vehicle_fixes
       (garage_no, line, direction_route_id, vehicle_type, lat, lon, stops_remaining, moved_at, seen_at, board_at)
     VALUES (?1,?2,?3,'tram',?4,?5,?6,?7,?8,?7)`,
  )
    .bind(
      row.garage,
      row.line,
      row.dir ?? null,
      row.lat,
      row.lon,
      row.remain ?? 5,
      NOW - row.movedSecsAgo * 1000,
      NOW - (row.seenSecsAgo ?? 0) * 1000,
    )
    .run();
}

// A handful of "healthy" recently-moved vehicles so the feed-health gate passes.
async function seedHealthyBackground(n = 10) {
  for (let i = 0; i < n; i++) {
    await seedFix({
      garage: `MOVE${i}`,
      line: "99",
      lat: 44.8 + i * 0.001,
      lon: 20.45 + i * 0.001,
      movedSecsAgo: 5, // moved just now
    });
  }
}

async function firstTramLine() {
  const lines = await getAllLines(env);
  const tram = lines.find((l) => l.vehicle_type === "tram");
  if (!tram) throw new Error("no tram line in fixture GTFS");
  const dirs = await getLineDirectionEndpoints(env, tram.line);
  return { line: tram.line, routeId: tram.route_id, dirs };
}

beforeEach(async () => {
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM vehicle_fixes").run();
  await setFlag(env, "jam_detection_show", true);
});

describe("garageVehicleType", () => {
  it("classifies tram / trolleybus / bus by garage number range", () => {
    expect(garageVehicleType("P80399")).toBe("tram"); // KT4 range
    expect(garageVehicleType("P81538")).toBe("tram"); // bozankaya range
    expect(garageVehicleType("P82050")).toBe("trolleybus");
    expect(garageVehicleType("P93475")).toBe("bus");
    expect(garageVehicleType("P26624")).toBe("bus");
    expect(garageVehicleType(null)).toBe("unknown");
    expect(garageVehicleType("junk")).toBe("unknown");
  });
});

describe("recordVehicleFixes", () => {
  const arr = (over: Partial<ArrivalDto>): ArrivalDto => ({
    line: "7",
    vehicle_type: "tram",
    eta_minutes: 1,
    stops_remaining: 4,
    route_id: "r",
    direction_route_id: "r",
    gps: { lat: 44.8, lon: 20.46 },
    garage_no: "P80200",
    heading: null,
    ...over,
  });

  it("re-reading the SAME board never bumps moved_at (sawtooth-proof)", async () => {
    const board = NOW - 60_000;
    await recordVehicleFixes(env, board, [arr({})], NOW);
    const before = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT moved_at FROM vehicle_fixes WHERE garage_no='P80200'",
    ).first<{ moved_at: number }>();
    // Same board again, later wall-clock, identical position → WHERE guard no-ops.
    await recordVehicleFixes(env, board, [arr({})], NOW + 30_000);
    const after = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT moved_at, seen_at FROM vehicle_fixes WHERE garage_no='P80200'",
    ).first<{ moved_at: number; seen_at: number }>();
    expect(after!.moved_at).toBe(before!.moved_at);
  });

  it("an unmoved fix on a NEWER board holds moved_at; a moved fix bumps it", async () => {
    await recordVehicleFixes(env, NOW - 120_000, [arr({})], NOW - 120_000);
    const orig = (await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT moved_at FROM vehicle_fixes WHERE garage_no='P80200'",
    ).first<{ moved_at: number }>())!.moved_at;

    // Newer board, same position → moved_at unchanged (freeze accumulates).
    await recordVehicleFixes(env, NOW - 60_000, [arr({})], NOW - 60_000);
    expect(
      (await env.STIGLA_ANALYTICS_DB.prepare(
        "SELECT moved_at FROM vehicle_fixes WHERE garage_no='P80200'",
      ).first<{ moved_at: number }>())!.moved_at,
    ).toBe(orig);

    // Newer board, moved >30m → moved_at jumps to the new sighting.
    await recordVehicleFixes(env, NOW, [arr({ gps: { lat: 44.81, lon: 20.47 } })], NOW);
    expect(
      (await env.STIGLA_ANALYTICS_DB.prepare(
        "SELECT moved_at FROM vehicle_fixes WHERE garage_no='P80200'",
      ).first<{ moved_at: number }>())!.moved_at,
    ).toBe(NOW);
  });

  it("skips scheduled rows and rows without gps/garage", async () => {
    await recordVehicleFixes(
      env,
      NOW,
      [
        arr({ source: "scheduled", garage_no: null, gps: null }),
        arr({ garage_no: null }),
        arr({ gps: null }),
      ],
      NOW,
    );
    const count = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT count(*) c FROM vehicle_fixes",
    ).first<{ c: number }>();
    expect(count!.c).toBe(0);
  });
});

describe("computeJams", () => {
  it("suppresses everything during feed starvation (nothing moved)", async () => {
    const { line, routeId } = await firstTramLine();
    // Two trams frozen well past T_JAM, but the WHOLE feed is frozen too.
    await seedFix({ garage: "P80201", line, dir: routeId, lat: 44.81, lon: 20.47, movedSecsAgo: 400 });
    await seedFix({ garage: "P80202", line, dir: routeId, lat: 44.8105, lon: 20.4705, movedSecsAgo: 400 });
    for (let i = 0; i < 10; i++)
      await seedFix({ garage: `S${i}`, line: "99", lat: 44.8, lon: 20.45, movedSecsAgo: 400 });
    const res = await computeJams(env, NOW);
    expect(res.feed_healthy).toBe(false);
    expect(res.jams).toHaveLength(0);
  });

  it("reports a jam: >=2 same-direction trams frozen past T_JAM on a healthy feed", async () => {
    const { line, routeId } = await firstTramLine();
    await seedHealthyBackground();
    await seedFix({ garage: "P80201", line, dir: routeId, lat: 44.812, lon: 20.472, movedSecsAgo: T_CLUSTER + 20 });
    await seedFix({ garage: "P80202", line, dir: routeId, lat: 44.8123, lon: 20.4723, movedSecsAgo: T_CLUSTER + 50 });
    const res = await computeJams(env, NOW);
    expect(res.feed_healthy).toBe(true);
    expect(res.jams).toHaveLength(1);
    expect(res.jams[0].line).toBe(line);
    expect(res.jams[0].vehicles).toHaveLength(2);
    expect(res.jams[0].frozen_secs).toBeGreaterThanOrEqual(T_CLUSTER);
  });

  it("a single frozen tram is NOT a jam", async () => {
    const { line, routeId } = await firstTramLine();
    await seedHealthyBackground();
    await seedFix({ garage: "P80201", line, dir: routeId, lat: 44.812, lon: 20.472, movedSecsAgo: T_CLUSTER + 20 });
    const res = await computeJams(env, NOW);
    expect(res.jams).toHaveLength(0);
  });

  it("excludes trams frozen at a direction terminal (legit layover)", async () => {
    const { line, routeId, dirs } = await firstTramLine();
    const term = dirs[0]?.origin;
    if (!term) return; // fixture line lacks terminal coords — skip
    await seedHealthyBackground();
    await seedFix({ garage: "P80201", line, dir: routeId, lat: term.lat, lon: term.lon, movedSecsAgo: T_CLUSTER + 20 });
    await seedFix({ garage: "P80202", line, dir: routeId, lat: term.lat + 0.0002, lon: term.lon, movedSecsAgo: T_CLUSTER + 20 });
    const res = await computeJams(env, NOW);
    expect(res.jams).toHaveLength(0);
  });

  it("flags a bus running a tram line as a substitution", async () => {
    const { line, routeId } = await firstTramLine();
    await seedHealthyBackground();
    await seedFix({ garage: "P93475", line, dir: routeId, lat: 44.8, lon: 20.46, movedSecsAgo: 5 });
    const res = await computeJams(env, NOW);
    expect(res.substitutions.some((s) => s.line === line && s.garage_nos.includes("P93475"))).toBe(true);
  });

  it("injects a synthetic jam when a sim line is given", async () => {
    const { line } = await firstTramLine();
    const res = await computeJams(env, NOW, { simLine: line });
    const sim = res.jams.find((j) => j.simulated);
    expect(sim).toBeTruthy();
    expect(sim!.vehicles.length).toBeGreaterThanOrEqual(2);
  });

  it("affected_stop_ids covers the stalled span, not just downstream (round-2 fix)", async () => {
    const { line } = await firstTramLine();
    const res = await computeJams(env, NOW, { simLine: line });
    const sim = res.jams.find((j) => j.simulated)!;
    // The two sim vehicles sit at mid / mid+1, so the span's stops must be in the
    // affected set — a rider tapping a stop under the segment gets the banner.
    expect(sim.affected_stop_ids.length).toBeGreaterThanOrEqual(3);
  });

  it("cascading threshold: a substitute bus relaxes the cluster to tSubstitute", async () => {
    const { line, routeId } = await firstTramLine();
    await seedHealthyBackground();
    // A substitute bus on the line (corroborates) + two trams frozen only ~100s —
    // below tCluster(180) but above tSubstitute(90) → a jam forms thanks to it.
    await seedFix({ garage: "P93475", line, dir: routeId, lat: 44.8115, lon: 20.4718, movedSecsAgo: 100 });
    await seedFix({ garage: "P80201", line, dir: routeId, lat: 44.812, lon: 20.472, movedSecsAgo: 100 });
    await seedFix({ garage: "P80202", line, dir: routeId, lat: 44.8123, lon: 20.4723, movedSecsAgo: 110 });
    const res = await computeJams(env, NOW);
    expect(res.jams.length).toBe(1);
    expect(res.jams[0].has_substitute).toBe(true);
  });
});
