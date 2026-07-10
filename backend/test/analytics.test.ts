import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { aggregate, getLineAnalytics, logObservations } from "../src/lib/analytics";
import { setFlag } from "../src/lib/featureFlags";
import type { RawArrival } from "../src/lib/transitProvider";

// A fixed instant so day-of-week / hour buckets are deterministic (UTC).
const BASE = Math.floor(Date.UTC(2026, 0, 6, 10, 0, 0) / 1000); // Tue 10:00 UTC
const HOUR = 10;
const DOW = new Date(BASE * 1000).getUTCDay();

async function seed(rows: [garage: string, stop: string, stopsRemaining: number, at: number][]) {
  for (const [garage, stop, sr, at] of rows) {
    await env.STIGLA_ANALYTICS_DB.prepare(
      `INSERT INTO raw_observations (line, stop_id, garage_no, eta_minutes, stops_remaining, observed_at)
       VALUES (?,?,?,?,?,?)`,
    )
      .bind("79", stop, garage, sr, sr, at)
      .run();
  }
}

beforeEach(async () => {
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM raw_observations").run();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM agg_line_time").run();
});

describe("analytics.logObservations", () => {
  const raw: RawArrival[] = [
    { lineNumber: "79", etaSeconds: 120, stopsRemaining: 2, garageNo: "P93001", gps: null, heading: null },
    { lineNumber: "79", etaSeconds: 60, stopsRemaining: 1, garageNo: null, gps: null, heading: null },
  ];

  it("writes nothing while analytics_collect is off", async () => {
    await setFlag(env, "analytics_collect", false);
    await logObservations(env, "S1", raw);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM raw_observations",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(0);
  });

  it("logs only vehicles with a garage number when collection is on", async () => {
    await setFlag(env, "analytics_collect", true);
    await logObservations(env, "S1", raw);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT garage_no FROM raw_observations",
    ).all<{ garage_no: string }>();
    expect(results.map((r) => r.garage_no)).toEqual(["P93001"]);
    await setFlag(env, "analytics_collect", false);
  });
});

describe("analytics.aggregate + getLineAnalytics", () => {
  it("derives activity, real headways and speed from raw observations", async () => {
    await seed([
      // Vehicle V1 approaching stop S1: 3 → 1 → 0 stops remaining.
      ["V1", "S1", 3, BASE],
      ["V1", "S1", 1, BASE + 120], // closed 2 stops in 120s → 1.0 stop/min
      ["V1", "S1", 0, BASE + 180], // closed 1 stop in 60s → 1.0 stop/min (arrival)
      // Vehicle V2 arrives at S1 300s after V1 → headway 300s.
      ["V2", "S1", 0, BASE + 480],
    ]);

    const res = await aggregate(env);
    expect(res.buckets).toBe(1);

    const a = await getLineAnalytics(env, "79");
    expect(a.total_samples).toBe(4);
    expect(a.by_hour).toHaveLength(24);
    expect(a.by_dow).toHaveLength(7);

    const h = a.by_hour[HOUR];
    expect(h.samples).toBe(4);
    expect(h.arrivals).toBe(2);
    expect(h.mean_headway_secs).toBe(300);
    expect(h.mean_speed_stops_per_min).toBeCloseTo(1.0, 3);

    // Empty buckets are present and null-valued (full axis for charts).
    expect(a.by_hour[0].samples).toBe(0);
    expect(a.by_hour[0].mean_headway_secs).toBeNull();

    // Bucketed onto the right day-of-week.
    expect(a.by_dow[DOW].samples).toBe(4);

    // The 2D grid (for heatmap / dot-plot) has the single populated cell.
    expect(a.grid).toHaveLength(1);
    expect(a.grid[0]).toMatchObject({ dow: DOW, hour: HOUR, samples: 4, arrivals: 2 });
    expect(a.grid[0].mean_headway_secs).toBe(300);

    // Punctuality is scaffolded but not yet computed.
    expect(a.punctuality).toBeNull();
    expect(a.updated_at).not.toBeNull();
  });

  it("returns empty, non-crashing analytics for a line with no data", async () => {
    const a = await getLineAnalytics(env, "999");
    expect(a.total_samples).toBe(0);
    expect(a.by_hour.every((b) => b.samples === 0)).toBe(true);
  });
});
