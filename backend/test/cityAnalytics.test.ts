import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { CITY_KV_KEY, foldCity, getCitySummary, refreshCitySummary, toLocal } from "../src/lib/cityAnalytics";

const db = () => env.STIGLA_ANALYTICS_DB;

async function put(line: string, dir: string, dow: number, hour: number, v: Partial<Record<string, number>>) {
  await db()
    .prepare(
      `INSERT INTO agg_line_dir_time (line, direction_route_id, dow, hour, samples, arrivals, headway_count, headway_secs_sum,
         sched_delay_count, sched_delay_secs_sum, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
    )
    .bind(line, dir, dow, hour, v.arrivals ?? 0, v.arrivals ?? 0, v.hc ?? 0, v.hs ?? 0, v.dc ?? 0, v.ds ?? 0, 1)
    .run();
}

beforeEach(async () => {
  await db().prepare("DELETE FROM agg_line_dir_time").run();
  await db().prepare("DELETE FROM agg_state").run();
  await env.STIGLA_KV.delete(CITY_KV_KEY);
});

describe("toLocal", () => {
  it("shifts UTC buckets to Belgrade time with the weekday rolling over", () => {
    expect(toLocal(2, 10)).toEqual({ dow: 2, hour: 11 });
    expect(toLocal(6, 23)).toEqual({ dow: 0, hour: 0 });
  });
});

describe("foldCity", () => {
  it("is empty without data", () => {
    const s = foldCity([], 1, null);
    expect(s.totals.arrivals).toBe(0);
    expect(s.totals.mean_delay_secs).toBeNull();
    expect(s.grid).toEqual([]);
    expect(s.lines).toEqual([]);
  });
});

describe("city summary", () => {
  it("folds directions and lines into local cells, lines and totals", async () => {
    // Line 79, two directions, Tue 16:00 UTC → Tue 17:00 local.
    await put("79", "a", 2, 16, { arrivals: 10, hc: 4, hs: 2400, dc: 5, ds: 600 });
    await put("79", "b", 2, 16, { arrivals: 6, hc: 2, hs: 1200, dc: 3, ds: 0 });
    // Line 26 in the evening: 21:00 UTC → 22:00 local.
    await put("26", "a", 3, 21, { arrivals: 4, hc: 2, hs: 2880, dc: 0, ds: 0 });
    await db().prepare("INSERT INTO agg_state (key, value) VALUES ('last_run', '1234')").run();

    const s = await refreshCitySummary(env);
    expect(s.aggregated_to).toBe(1234);
    expect(s.totals).toMatchObject({ arrivals: 20, delay_count: 8, mean_delay_secs: 75, headway_count: 8 });

    const tue17 = s.grid.find((c) => c.dow === 2 && c.hour === 17)!;
    expect(tue17).toMatchObject({ arrivals: 16, delay_count: 8, mean_delay_secs: 75, mean_headway_secs: 600 });

    expect(s.lines.map((l) => l.line)).toEqual(["79", "26"]); // by arrivals
    const l26 = s.lines.find((l) => l.line === "26")!;
    expect(l26.mean_delay_secs).toBeNull(); // no delay samples: unknown, not zero
    expect(l26.evening_mean_headway_secs).toBe(1440);
    expect(s.lines.find((l) => l.line === "79")!.evening_headway_count).toBe(0);
  });

  it("serves the stored summary, computes once on a cold miss, and stays empty when reads are constrained", async () => {
    await put("79", "a", 2, 16, { arrivals: 3 });
    const constrained = await getCitySummary(env, false);
    expect(constrained.totals.arrivals).toBe(0);
    expect(await env.STIGLA_KV.get(CITY_KV_KEY)).toBeNull();

    const cold = await getCitySummary(env, true);
    expect(cold.totals.arrivals).toBe(3);
    expect(await env.STIGLA_KV.get(CITY_KV_KEY)).not.toBeNull();

    await put("79", "b", 2, 16, { arrivals: 5 }); // newer data: not visible until the next refresh
    const again = await getCitySummary(env, true);
    expect(again.totals.arrivals).toBe(3);
  });
});
