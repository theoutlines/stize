import { beforeEach, describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  DEFAULT_BREAKER_LATENCY_P95_MS,
  DEFAULT_BREAKER_MIN_SAMPLES,
  DEFAULT_BREAKER_NON_JSON_FRACTION,
  DEFAULT_BREAKER_WINDOW_SECONDS,
  DEFAULT_BUDGET_HOURLY,
  DEFAULT_LIVE_RESERVE_HOURLY,
  degradationMetrics,
  evaluateDegradation,
  pruneUpstreamEvents,
  recordUpstreamEvent,
  resolveBudgetConfig,
  rollingCounts,
  sweepBudgetDecision,
  type BreakerConfig,
  type UpstreamOutcome,
} from "../src/lib/upstreamBudget";

const NOW = 1_800_000_000; // fixed unix seconds for deterministic windows

async function seed(
  ts: number,
  kind: "live" | "sweep",
  latencyMs: number,
  outcome: UpstreamOutcome,
): Promise<void> {
  await recordUpstreamEvent(env, { kind, latencyMs, outcome }, ts);
}

const breakerCfg: BreakerConfig = {
  latencyP95Ms: DEFAULT_BREAKER_LATENCY_P95_MS,
  nonJsonFraction: DEFAULT_BREAKER_NON_JSON_FRACTION,
  windowSeconds: DEFAULT_BREAKER_WINDOW_SECONDS,
  minSamples: DEFAULT_BREAKER_MIN_SAMPLES,
};

beforeEach(async () => {
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM upstream_events").run();
  for (const k of ["config:upstream_budget_hourly", "config:upstream_live_reserve_hourly"]) {
    await env.STIGLA_KV.delete(k);
  }
});

describe("sweepBudgetDecision (pure)", () => {
  const budget = { ceiling: 1200, liveReserve: 300 }; // sweepCeiling = 900

  it("allows the sweep while total + batch stays at/under (ceiling − reserve)", () => {
    const d = sweepBudgetDecision({ live: 800, sweep: 99, total: 899 }, 1, budget);
    expect(d.sweepCeiling).toBe(900);
    expect(d.allowed).toBe(true);
  });

  it("blocks the sweep when its batch would cross the sweep ceiling", () => {
    const d = sweepBudgetDecision({ live: 895, sweep: 5, total: 900 }, 1, budget);
    expect(d.allowed).toBe(false); // 900 + 1 > 900
  });

  it("reserves headroom for live: a live-only spike above the sweep ceiling blocks sweep", () => {
    // Live alone is over the sweep ceiling — the sweep must stand down entirely,
    // but this function is never consulted for live traffic (live is never gated).
    const d = sweepBudgetDecision({ live: 1000, sweep: 0, total: 1000 }, 1, budget);
    expect(d.allowed).toBe(false);
  });
});

describe("evaluateDegradation (pure)", () => {
  it("does not trip below the minimum sample count", () => {
    const v = evaluateDegradation(
      { samples: 5, p95LatencyMs: 99999, nonJsonFraction: 1 },
      breakerCfg,
    );
    expect(v.tripped).toBe(false);
  });

  it("trips on p95 latency over threshold", () => {
    const v = evaluateDegradation(
      { samples: 50, p95LatencyMs: 4000, nonJsonFraction: 0 },
      breakerCfg,
    );
    expect(v.tripped).toBe(true);
    expect(v.reason).toContain("p95_latency");
  });

  it("trips on non-JSON share over threshold", () => {
    const v = evaluateDegradation(
      { samples: 50, p95LatencyMs: 100, nonJsonFraction: 0.5 },
      breakerCfg,
    );
    expect(v.tripped).toBe(true);
    expect(v.reason).toContain("non_json_share");
  });

  it("stays closed on a healthy source", () => {
    const v = evaluateDegradation(
      { samples: 50, p95LatencyMs: 400, nonJsonFraction: 0.02 },
      breakerCfg,
    );
    expect(v.tripped).toBe(false);
    expect(v.reason).toBeNull();
  });
});

describe("rollingCounts (D1)", () => {
  it("counts live and sweep separately within the window and ignores older rows", async () => {
    await seed(NOW - 10, "live", 100, "json");
    await seed(NOW - 20, "live", 100, "json");
    await seed(NOW - 30, "sweep", 100, "json");
    await seed(NOW - 4000, "live", 100, "json"); // outside the 1h window

    const counts = await rollingCounts(env, 3600, NOW);
    expect(counts).toEqual({ live: 2, sweep: 1, total: 3 });
  });
});

describe("degradationMetrics (D1)", () => {
  it("computes nearest-rank p95 and the non-JSON share over the window", async () => {
    // 20 samples with latencies 1..20; nearest-rank p95 index = ceil(0.95*20)-1 = 18 → 19.
    for (let i = 1; i <= 20; i++) await seed(NOW - i, "live", i, i <= 5 ? "non_json" : "json");
    const m = await degradationMetrics(env, 300, NOW);
    expect(m.samples).toBe(20);
    expect(m.p95LatencyMs).toBe(19);
    expect(m.nonJsonFraction).toBeCloseTo(5 / 20, 5);
  });

  it("returns null p95 and zero share when there are no samples in the window", async () => {
    const m = await degradationMetrics(env, 300, NOW);
    expect(m).toEqual({ samples: 0, p95LatencyMs: null, nonJsonFraction: 0 });
  });
});

describe("pruneUpstreamEvents (D1)", () => {
  it("drops rows older than the retention window, keeps recent ones", async () => {
    await seed(NOW - 10, "live", 100, "json");
    await seed(NOW - 8000, "live", 100, "json"); // > 2h old
    await pruneUpstreamEvents(env, NOW);
    const counts = await rollingCounts(env, 24 * 3600, NOW);
    expect(counts.total).toBe(1);
  });
});

describe("resolveBudgetConfig (KV defaults + override)", () => {
  it("falls back to the documented defaults for unset keys", async () => {
    const b = await resolveBudgetConfig(env);
    expect(b.ceiling).toBe(DEFAULT_BUDGET_HOURLY);
    expect(b.liveReserve).toBe(DEFAULT_LIVE_RESERVE_HOURLY);
  });

  it("honours explicit KV overrides", async () => {
    await env.STIGLA_KV.put("config:upstream_budget_hourly", "600");
    await env.STIGLA_KV.put("config:upstream_live_reserve_hourly", "150");
    const b = await resolveBudgetConfig(env);
    expect(b).toEqual({ ceiling: 600, liveReserve: 150 });
  });
});
