import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import type { Env } from "../src/env";
import { aggregate, getLineAnalytics, logObservations } from "../src/lib/analytics";
import { setFlag } from "../src/lib/featureFlags";
import { computeJams, recordVehicleFixes } from "../src/lib/jamDetector";
import { latestObservationPerStop } from "../src/lib/sweep";
import { degradationMetrics, recordUpstreamEvent, rollingCounts } from "../src/lib/upstreamBudget";
import type { RawArrival } from "../src/lib/transitProvider";
import type { ArrivalDto } from "../src/types";

// D1 write budget guard (docs/reports/2026-10-05-d1-write-budget.md). The account
// is on the D1 free tier for good: 100k rows_written/day, account-wide, and D1
// counts every index entry a write touches. Miniflare's meta.rows_written matches
// prod accounting exactly (verified: a 12-row raw insert was 61 rows in prod and
// in miniflare before the fix), so these numbers are the real per-call cost —
// adding an index or a write path that blows them fails here, not on the bill.

// Wraps a D1Database, summing meta.rows_written of every run()/batch() and
// remembering every SQL text (with its bound args) prepared through it.
function metered(db: D1Database) {
  const tally = { written: 0, calls: [] as { sql: string; args: unknown[] }[] };
  const raw = new WeakMap<object, D1PreparedStatement>();
  const wrap = (st: D1PreparedStatement, sql: string): D1PreparedStatement => {
    const p = new Proxy(st, {
      get(t, prop) {
        if (prop === "bind") {
          return (...a: unknown[]) => {
            tally.calls.push({ sql, args: a });
            return wrap(t.bind(...a), sql);
          };
        }
        if (prop === "run") {
          return async () => {
            const r = await t.run();
            tally.written += r.meta.rows_written ?? 0;
            return r;
          };
        }
        const v = Reflect.get(t, prop, t);
        return typeof v === "function" ? v.bind(t) : v;
      },
    });
    raw.set(p, st);
    return p;
  };
  const proxy = new Proxy(db, {
    get(t, prop) {
      if (prop === "prepare") {
        return (sql: string) => {
          tally.calls.push({ sql, args: [] });
          return wrap(t.prepare(sql), sql);
        };
      }
      if (prop === "batch") {
        return async (stmts: D1PreparedStatement[]) => {
          const rs = await t.batch(stmts.map((s) => raw.get(s) ?? s));
          for (const r of rs) tally.written += r.meta.rows_written ?? 0;
          return rs;
        };
      }
      const v = Reflect.get(t, prop, t);
      return typeof v === "function" ? v.bind(t) : v;
    },
  });
  return { db: proxy as D1Database, tally };
}

function meteredEnv() {
  const m = metered(env.STIGLA_ANALYTICS_DB);
  return { env: { ...env, STIGLA_ANALYTICS_DB: m.db } as Env, tally: m.tally };
}

const ctx = () => ({ waitUntil() {} });

const arrivals = (n: number): RawArrival[] =>
  Array.from({ length: n }, (_, i) => ({
    lineNumber: "79",
    etaSeconds: 60 * i,
    stopsRemaining: i,
    garageNo: `P${90000 + i}`,
    gps: null,
    heading: null,
    trajectory: null,
    routeStations: [],
  }));

const tram = (garage: string, lat: number): ArrivalDto =>
  ({
    line: "7",
    vehicle_type: "tram",
    eta_minutes: 1,
    stops_remaining: 4,
    route_id: "r",
    direction_route_id: "r",
    gps: { lat, lon: 20.46 },
    garage_no: garage,
    heading: null,
  }) as ArrivalDto;

beforeEach(async () => {
  for (const t of ["raw_observations", "arrival_events", "stop_last_observed", "vehicle_fixes", "upstream_meter", "agg_state"]) {
    await env.STIGLA_ANALYTICS_DB.prepare(`DELETE FROM ${t}`).run();
  }
});

describe("D1 write cost per upstream fetch (rows_written)", () => {
  it("raw_observations keeps only the observed_at index", async () => {
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='raw_observations' AND sql IS NOT NULL",
    ).all<{ name: string }>();
    expect(results.map((r) => r.name)).toEqual(["idx_raw_time"]);
  });

  it("logObservations v3: 1 row per arrival event, 0 for the rest of the board and for a re-sighting (was ~40 per board)", async () => {
    await setFlag(env, "analytics_collect", true);
    await setFlag(env, "analytics_sweep", false);
    try {
      const m = meteredEnv();
      // A 12-vehicle board where exactly one vehicle is at the stop (index 0).
      await logObservations(m.env, ctx(), "S1", arrivals(12));
      expect(m.tally.written).toBe(1);
      // The next refresh sees the same vehicle still at the stop: ignored, 0 rows.
      await logObservations(m.env, ctx(), "S1", arrivals(12));
      expect(m.tally.written).toBe(1);
      // A board with nobody at the stop writes nothing.
      await logObservations(m.env, ctx(), "S2", arrivals(12).slice(1));
      expect(m.tally.written).toBe(1);
    } finally {
      await setFlag(env, "analytics_collect", false);
    }
  });

  it("arrival_events has no secondary index", async () => {
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='arrival_events' AND sql IS NOT NULL",
    ).all<{ name: string }>();
    expect(results).toEqual([]);
  });

  it("upstream meter: exactly 1 row per fetch (was 3)", async () => {
    const m = meteredEnv();
    const now = 1_800_000_000;
    await recordUpstreamEvent(m.env, { kind: "live", latencyMs: 300, outcome: "json" }, now);
    await recordUpstreamEvent(m.env, { kind: "live", latencyMs: 300, outcome: "json" }, now + 1);
    expect(m.tally.written).toBe(2);
  });

  it("vehicle_fixes: 0 rows for a no-change re-sighting, 2 for a real update, 0 for non-tram", async () => {
    const t0 = Date.UTC(2026, 9, 5, 11, 0, 0);
    await recordVehicleFixes(env, t0, [tram("P80101", 44.8), tram("P80102", 44.8)], t0);

    const m = meteredEnv();
    // Another stop's board 20s later, nobody moved → no writes at all.
    await recordVehicleFixes(m.env, t0 + 20_000, [tram("P80101", 44.8), tram("P80102", 44.8)], t0 + 20_000);
    expect(m.tally.written).toBe(0);
    // One tram moved → one update = row + seen_at index.
    await recordVehicleFixes(m.env, t0 + 25_000, [tram("P80101", 44.801), tram("P80102", 44.8)], t0 + 25_000);
    expect(m.tally.written).toBe(2);
    // A bus board writes nothing.
    await recordVehicleFixes(
      m.env,
      t0 + 30_000,
      [{ ...tram("P20001", 44.9), vehicle_type: "bus" } as ArrivalDto],
      t0 + 30_000,
    );
    expect(m.tally.written).toBe(2);
  });
});

describe("read paths use an index (EXPLAIN QUERY PLAN)", () => {
  it("no read on a growing table (arrival_events, stop_last_observed, vehicle_fixes) is a full scan", async () => {
    const m = meteredEnv();
    const now = Math.floor(Date.UTC(2026, 9, 5, 12, 0, 0) / 1000);
    await env.STIGLA_ANALYTICS_DB.prepare(
      `INSERT INTO arrival_events (slot, stop_id, garage_no, vehicle_id, line, direction_route_id, observed_at)
       VALUES (?,'S1','P90001','P90001','79','',?)`,
    )
      .bind(Math.floor((now - 600) / 300), now - 600)
      .run();
    await env.STIGLA_ANALYTICS_DB.prepare(
      "INSERT OR REPLACE INTO agg_state (key, value) VALUES ('last_run', ?)",
    )
      .bind(String(now - 7200))
      .run();

    // Drive every read path once through the metered DB to capture its SQL:
    // the fresh-backfill anchor, the drift-guard backlog count (a 60s window keeps
    // the run "behind"), the windowed rollup, then the request/sweep reads.
    await env.STIGLA_KV.put("config:agg_backfill_window_s", "60");
    try {
      await aggregate(m.env, now);
    } finally {
      await env.STIGLA_KV.delete("config:agg_backfill_window_s");
    }
    await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM agg_state").run();
    await aggregate(m.env, now);
    await computeJams(m.env, Date.UTC(2026, 9, 5, 12, 0, 0));
    await getLineAnalytics(m.env, "79");
    await latestObservationPerStop(m.env, ["S1", "S2"], now - 9000);
    await rollingCounts(m.env, 3600, now);
    await degradationMetrics(m.env, 300, now);

    const tables = ["arrival_events", "stop_last_observed", "upstream_meter", "vehicle_fixes"];
    // Keep the bound form of each read (the unbound prepare() entry has no args).
    const bySql = new Map<string, unknown[]>();
    for (const c of m.tally.calls) {
      if (!/^\s*(SELECT|WITH)/i.test(c.sql) || !tables.some((t) => c.sql.includes(t))) continue;
      if (c.args.length > 0 || !bySql.has(c.sql)) bySql.set(c.sql, c.args);
    }
    expect(bySql.size).toBeGreaterThanOrEqual(12);

    const plans: string[] = [];
    for (const [sql, args] of bySql) {
      const { results } = await env.STIGLA_ANALYTICS_DB.prepare(`EXPLAIN QUERY PLAN ${sql}`)
        .bind(...args)
        .all<{ detail: string }>();
      const detail = results.map((r) => r.detail);
      plans.push(`${sql.replace(/\s+/g, " ").slice(0, 90)}\n    → ${detail.join(" | ")}`);
      // upstream_meter is a fixed-size ring (<= METER_RING_MINUTES × 2 rows): a scan
      // is bounded by construction, and an index on `minute` would cost a written
      // row per fetch. Every other table here grows, so it must be searched.
      for (const t of tables.filter((x) => x !== "upstream_meter")) {
        // A bare "SCAN <table>" (no index) is a full scan of a growing table.
        expect(detail.some((d) => new RegExp(`^SCAN ${t}( |$)`).test(d)), `${sql}\n${detail.join("\n")}`).toBe(false);
      }
    }
    console.log(`QUERY PLANS\n${plans.join("\n")}`);
  });
});
