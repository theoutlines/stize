import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  aggregate,
  getLineAnalytics,
  logObservations,
  maxRowsPerInsert,
  vehicleIdOf,
} from "../src/lib/analytics";
import { setFlag } from "../src/lib/featureFlags";
import type { RawArrival } from "../src/lib/transitProvider";

// A fixed instant so day-of-week / hour buckets are deterministic (UTC).
const BASE = Math.floor(Date.UTC(2026, 0, 6, 10, 0, 0) / 1000); // Tue 10:00 UTC
const HOUR = 10;
const DOW = new Date(BASE * 1000).getUTCDay();

// Seed one raw observation, normalising vehicle_id exactly as the collector does.
async function seed(
  rows: [garage: string | null, stop: string, stopsRemaining: number, at: number][],
) {
  for (const [garage, stop, sr, at] of rows) {
    await env.STIGLA_ANALYTICS_DB.prepare(
      `INSERT INTO raw_observations (line, stop_id, garage_no, vehicle_id, eta_minutes, stops_remaining, observed_at)
       VALUES (?,?,?,?,?,?,?)`,
    )
      .bind("79", stop, garage, vehicleIdOf(garage), sr, sr, at)
      .run();
  }
}

beforeEach(async () => {
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM raw_observations").run();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM agg_line_time").run();
});

describe("maxRowsPerInsert", () => {
  it("derives rows-per-statement from the column count and D1's 100-param cap", () => {
    // raw_observations is 7 columns: floor(100/7) = 14 rows → 98 params (< 100).
    expect(maxRowsPerInsert(7)).toBe(14);
    // Boundary — exactly at the cap: 10 columns × 10 rows = 100 params fits.
    expect(maxRowsPerInsert(10)).toBe(10);
    // Boundary — one param over: 11 columns can only take 9 rows (99), not 10 (110).
    expect(maxRowsPerInsert(11)).toBe(9);
    // Never collapses to a zero-row (infinite-loop) chunk, even absurdly wide.
    expect(maxRowsPerInsert(101)).toBe(1);
  });
});

describe("vehicleIdOf", () => {
  it("treats P1..P999 as junk (null) and keeps real ids", () => {
    expect(vehicleIdOf("P5")).toBeNull();
    expect(vehicleIdOf("P999")).toBeNull();
    expect(vehicleIdOf("P1000")).toBe("P1000");
    expect(vehicleIdOf("P93001")).toBe("P93001");
    expect(vehicleIdOf(null)).toBeNull();
  });
});

describe("analytics.logObservations", () => {
  const raw: RawArrival[] = [
    { lineNumber: "79", etaSeconds: 120, stopsRemaining: 2, garageNo: "P93001", gps: null, heading: null, trajectory: null, routeStations: [] },
    { lineNumber: "79", etaSeconds: 60, stopsRemaining: 1, garageNo: null, gps: null, heading: null, trajectory: null, routeStations: [] },
    { lineNumber: "79", etaSeconds: 30, stopsRemaining: 0, garageNo: "P5", gps: null, heading: null, trajectory: null, routeStations: [] },
  ];

  it("writes nothing while analytics_collect is off", async () => {
    await setFlag(env, "analytics_collect", false);
    await logObservations(env, "S1", raw);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM raw_observations",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(0);
  });

  it("logs every arrival (garage optional) and normalises vehicle_id", async () => {
    await setFlag(env, "analytics_collect", true);
    await logObservations(env, "S1", raw);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT garage_no, vehicle_id FROM raw_observations",
    ).all<{ garage_no: string | null; vehicle_id: string | null }>();
    expect(results).toHaveLength(3); // incl. the one without a garage number
    expect(results.find((r) => r.garage_no === "P93001")?.vehicle_id).toBe("P93001");
    expect(results.find((r) => r.garage_no === null)?.vehicle_id).toBeNull();
    expect(results.find((r) => r.garage_no === "P5")?.vehicle_id).toBeNull(); // junk
    await setFlag(env, "analytics_collect", false);
  });

  it("chunks a busy stop past the D1 param cap without 'too many SQL variables'", async () => {
    await setFlag(env, "analytics_collect", true);
    // 200 rows × 7 params = 1400 bind vars — 14× over D1's 100/statement cap and
    // well past the 142-row threshold from the 2026-07-13 regression. The single
    // unchunked statement the old code built here is exactly what threw.
    const many: RawArrival[] = Array.from({ length: 200 }, (_, i) => ({
      lineNumber: "79",
      etaSeconds: 60,
      stopsRemaining: i % 5,
      garageNo: `P${1000 + i}`, // all real ids → also 200 rows in the aggregates
      gps: null,
      heading: null,
      trajectory: null,
      routeStations: [],
    }));
    await logObservations(env, "S1", many);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM raw_observations",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(200);

    // The aggregate write-back (agg_line_time + per-vehicle tables, one row per
    // vehicle) must survive the same wide result set — the second insert path.
    await aggregate(env);
    const agg = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM agg_vehicle_line",
    ).all<{ n: number }>();
    expect(agg.results[0].n).toBe(200);
    await setFlag(env, "analytics_collect", false);
  });
});

describe("analytics.aggregate + getLineAnalytics", () => {
  it("derives activity, real headways and speed; junk & no-garage count for activity only", async () => {
    await seed([
      ["V1", "S1", 3, BASE],
      ["V1", "S1", 1, BASE + 120], // 2 stops in 120s → 1.0 stop/min
      ["V1", "S1", 0, BASE + 180], // 1 stop in 60s → 1.0 stop/min (arrival)
      ["V2", "S1", 0, BASE + 480], // real arrival 300s after V1
      ["P7", "S1", 0, BASE + 300], // JUNK arrival between them — must be ignored
      [null, "S1", 5, BASE + 60], // no garage — activity only
    ]);

    await aggregate(env);
    const a = await getLineAnalytics(env, "79");

    const h = a.by_hour[HOUR];
    expect(h.samples).toBe(6); // every observation, incl. junk + no-garage
    expect(h.arrivals).toBe(3); // three stops_remaining=0 rows
    // Headway is between the two REAL vehicles only (V1→V2 = 300s); the junk
    // arrival at +300 must not inject a spurious 120s/180s gap.
    expect(h.mean_headway_secs).toBe(300);
    expect(h.mean_speed_stops_per_min).toBeCloseTo(1.0, 3);

    // Bucketed onto the right day-of-week; grid has the single populated cell.
    expect(a.by_dow[DOW].samples).toBe(6);
    expect(a.grid).toHaveLength(1);
    expect(a.grid[0]).toMatchObject({ dow: DOW, hour: HOUR, samples: 6, arrivals: 3 });

    expect(a.punctuality).toBeNull();
    expect(a.updated_at).not.toBeNull();
  });

  it("returns empty, non-crashing analytics for a line with no data", async () => {
    const a = await getLineAnalytics(env, "999");
    expect(a.total_samples).toBe(0);
    expect(a.by_hour.every((b) => b.samples === 0)).toBe(true);
  });

  it("builds per-vehicle × line (+ dow) aggregates, excluding junk & no-garage", async () => {
    await seed([
      ["V1", "S1", 3, BASE],
      ["V1", "S1", 1, BASE + 120],
      ["V1", "S1", 0, BASE + 180],
      ["V2", "S1", 0, BASE + 480],
      ["P7", "S1", 0, BASE + 300], // junk — excluded
      [null, "S1", 5, BASE + 60], // no garage — excluded
    ]);
    await aggregate(env);

    const pairs = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT vehicle_id, samples, arrivals, first_seen, last_seen FROM agg_vehicle_line ORDER BY vehicle_id",
    ).all<{ vehicle_id: string; samples: number; arrivals: number; first_seen: number; last_seen: number }>();
    // Only the real vehicles — never P7 or the no-garage row.
    expect(pairs.results.map((r) => r.vehicle_id)).toEqual(["V1", "V2"]);
    const v1 = pairs.results[0];
    expect(v1).toMatchObject({ samples: 3, arrivals: 1, first_seen: BASE, last_seen: BASE + 180 });

    const dow = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT dow, samples, speed_count FROM agg_vehicle_line_dow WHERE vehicle_id = 'V1'",
    ).all<{ dow: number; samples: number; speed_count: number }>();
    expect(dow.results).toHaveLength(1);
    expect(dow.results[0]).toMatchObject({ dow: DOW, samples: 3, speed_count: 2 });
  });
});
