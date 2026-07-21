import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  aggregate,
  getLineAnalytics,
  logObservations,
  maxRowsPerInsert,
  schedDelaySeconds,
  vehicleIdOf,
} from "../src/lib/analytics";
import { setFlag } from "../src/lib/featureFlags";
import type { RawArrival } from "../src/lib/transitProvider";

// A fixed instant so day-of-week / hour buckets are deterministic (UTC).
const BASE = Math.floor(Date.UTC(2026, 0, 6, 10, 0, 0) / 1000); // Tue 10:00 UTC
const HOUR = 10;
const DOW = new Date(BASE * 1000).getUTCDay();

// Seed one raw observation, normalising vehicle_id exactly as the collector does.
// Optional 5th tuple element sets direction_route_id (else NULL → '' bucket).
async function seed(
  rows: [garage: string | null, stop: string, stopsRemaining: number, at: number, dir?: string][],
) {
  for (const [garage, stop, sr, at, dir] of rows) {
    await env.STIGLA_ANALYTICS_DB.prepare(
      `INSERT INTO raw_observations (line, stop_id, garage_no, vehicle_id, eta_minutes, stops_remaining, observed_at, direction_route_id)
       VALUES (?,?,?,?,?,?,?,?)`,
    )
      .bind("79", stop, garage, vehicleIdOf(garage), sr, sr, at, dir ?? null)
      .run();
  }
}

// Aggregate is now incremental (watermarked by agg_state.last_run) and additive.
// Every test starts from a clean slate — including last_run, so each aggregate()
// begins with a full backfill.
beforeEach(async () => {
  for (const t of [
    "raw_observations",
    "agg_line_dir_time",
    "agg_vehicle_line",
    "agg_vehicle_line_dow",
    "agg_state",
  ]) {
    await env.STIGLA_ANALYTICS_DB.prepare(`DELETE FROM ${t}`).run();
  }
});

describe("maxRowsPerInsert", () => {
  it("derives rows-per-statement from the column count and D1's 100-param cap", () => {
    // e.g. a 7-column row: floor(100/7) = 14 rows → 98 params (< 100).
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

describe("schedDelaySeconds", () => {
  it("returns the signed delay to the nearest scheduled minute", () => {
    // Scheduled at 600 (10:00) and 630 (10:30); arrived at 605 → 5 min late.
    expect(schedDelaySeconds(605, [600, 630])).toBe(300);
    // Arrived at 596 → 4 min early relative to the nearest (600).
    expect(schedDelaySeconds(596, [600, 630])).toBe(-240);
  });
  it("is null when nothing is within tolerance", () => {
    expect(schedDelaySeconds(600, [500], 30)).toBeNull(); // 100 min off
    expect(schedDelaySeconds(600, [])).toBeNull();
  });
  it("matches across the midnight wrap (overnight trips)", () => {
    // Arrived 00:10 (10 min); a scheduled 24:50 overnight trip (1490) → 1490-1440
    // = 50 (00:50). Nearest is 50 → 10-50 = -40 min, outside default tolerance.
    expect(schedDelaySeconds(10, [1490], 30)).toBeNull();
    // But 00:55 arrival vs the same 00:50 scheduled → 5 min late, matched via wrap.
    expect(schedDelaySeconds(55, [1490])).toBe(300);
  });
});

describe("analytics.logObservations", () => {
  const raw: RawArrival[] = [
    { lineNumber: "79", etaSeconds: 120, stopsRemaining: 2, garageNo: "P93001", gps: null, heading: null, trajectory: null, routeStations: [] },
    { lineNumber: "79", etaSeconds: 60, stopsRemaining: 1, garageNo: null, gps: null, heading: null, trajectory: null, routeStations: [] },
    { lineNumber: "79", etaSeconds: 30, stopsRemaining: 0, garageNo: "P5", gps: null, heading: null, trajectory: null, routeStations: [] },
  ];

  // Each call gets its own per-invocation scope (like a fresh request ctx), so
  // the memoized flag read never leaks across tests / flag flips.
  const ctx = () => ({ waitUntil() {} });

  it("writes nothing while analytics_collect is off", async () => {
    await setFlag(env, "analytics_collect", false);
    await logObservations(env, ctx(), "S1", raw);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM raw_observations",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(0);
  });

  it("logs every arrival (garage optional) and normalises vehicle_id", async () => {
    await setFlag(env, "analytics_collect", true);
    await logObservations(env, ctx(), "S1", raw);
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
    await logObservations(env, ctx(), "S1", many);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM raw_observations",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(200);

    // The aggregate write-back (agg_line_dir_time + per-vehicle tables, one row
    // per vehicle) must survive the same wide result set — the second insert path.
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

  it("is incremental: a second run adds new data without double-counting the old", async () => {
    // Batch 1, aggregated with a watermark just after it.
    await seed([
      ["V1", "S1", 3, BASE],
      ["V1", "S1", 0, BASE + 120],
    ]);
    await aggregate(env, BASE + 200);
    let a = await getLineAnalytics(env, "79");
    expect(a.by_hour[HOUR].samples).toBe(2);

    // Re-running immediately (no new rows) must change nothing — idempotent.
    await aggregate(env, BASE + 210);
    a = await getLineAnalytics(env, "79");
    expect(a.by_hour[HOUR].samples).toBe(2);

    // Batch 2 (new rows after the watermark) is ADDED to the existing bucket.
    await seed([
      ["V2", "S1", 2, BASE + 300],
      ["V2", "S1", 0, BASE + 360],
    ]);
    await aggregate(env, BASE + 500);
    a = await getLineAnalytics(env, "79");
    expect(a.by_hour[HOUR].samples).toBe(4); // 2 + 2, not 6
    expect(a.by_hour[HOUR].arrivals).toBe(2);
  });

  it("splits raw by direction but the folded response sums across directions", async () => {
    await seed([
      ["V1", "S1", 0, BASE, "00079"],
      ["V1", "S1", 2, BASE + 60, "00079"],
      ["V2", "S2", 0, BASE, "00079-1"],
    ]);
    await aggregate(env, BASE + 1000);

    // Stored per direction.
    const dirs = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT direction_route_id, SUM(samples) AS s FROM agg_line_dir_time WHERE line='79' GROUP BY direction_route_id ORDER BY direction_route_id",
    ).all<{ direction_route_id: string; s: number }>();
    expect(dirs.results).toEqual([
      { direction_route_id: "00079", s: 2 },
      { direction_route_id: "00079-1", s: 1 },
    ]);

    // Folded on read.
    const a = await getLineAnalytics(env, "79");
    expect(a.by_hour[HOUR].samples).toBe(3);
  });

  it("computes sched_delay against the real GTFS timetable for a matched arrival", async () => {
    // Real bundle fact: stop 20001, line 5, direction 00005-1, service RD has a
    // departure at minute 347 (05:47 Belgrade). 2026-07-14 is a Tuesday (RD
    // active, no calendar exception). An arrival at 05:50 local (03:50 UTC in
    // CEST) is 3 min = 180s late vs that 05:47 trip.
    const observedAt = Math.floor(Date.UTC(2026, 6, 14, 3, 50, 0) / 1000);
    await env.STIGLA_ANALYTICS_DB.prepare(
      `INSERT INTO raw_observations (line, stop_id, garage_no, vehicle_id, eta_minutes, stops_remaining, observed_at, direction_route_id)
       VALUES ('5','20001','P93001','P93001',0,0,?,'00005-1')`,
    )
      .bind(observedAt)
      .run();

    await aggregate(env, observedAt + 100);

    const row = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT sched_delay_count, sched_delay_secs_sum FROM agg_line_dir_time WHERE line='5' AND direction_route_id='00005-1'",
    ).first<{ sched_delay_count: number; sched_delay_secs_sum: number }>();
    expect(row).toMatchObject({ sched_delay_count: 1, sched_delay_secs_sum: 180 });
  });

  it("leaves sched_delay at 0 for an arrival at a stop with no timetable", async () => {
    await seed([["V1", "S1", 0, BASE]]); // "S1" isn't a real GTFS stop → no schedule
    await aggregate(env, BASE + 100);
    const row = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT SUM(sched_delay_count) AS c FROM agg_line_dir_time WHERE line='79'",
    ).first<{ c: number }>();
    expect(row?.c ?? 0).toBe(0);
  });

  it("fills the headway histogram bucket matching the real interval", async () => {
    // Two distinct real vehicles arriving 300s apart → one 300s headway. 300s
    // falls in hb4 (bounds 240..360).
    await seed([
      ["V1", "S1", 0, BASE],
      ["V2", "S1", 0, BASE + 300],
    ]);
    await aggregate(env, BASE + 1000);
    const row = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT headway_count, headway_secs_sum, hb3, hb4, hb5 FROM agg_line_dir_time WHERE line='79'",
    ).first<{ headway_count: number; headway_secs_sum: number; hb3: number; hb4: number; hb5: number }>();
    expect(row).toMatchObject({ headway_count: 1, headway_secs_sum: 300, hb3: 0, hb4: 1, hb5: 0 });
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
