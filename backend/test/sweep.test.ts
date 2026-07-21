import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { env } from "cloudflare:test";
import {
  isNightHour,
  loadSentinels,
  parseInterval,
  runSweepTick,
} from "../src/lib/sweep";
import { setFlag, getFlag } from "../src/lib/featureFlags";

// A test ctx that collects waitUntil promises so the caller can await the
// fire-and-forget state persistence (cursor / breaker, in D1).
function collectingCtx() {
  const tasks: Promise<unknown>[] = [];
  return {
    ctx: { waitUntil: (p: Promise<unknown>) => void tasks.push(p) },
    settle: () => Promise.all(tasks),
  };
}

// A daytime and a night instant (July → Belgrade is UTC+2). 10:00 UTC = 12:00
// local (day); 00:30 UTC = 02:30 local (inside the 01–05 night pause).
const DAY = new Date(Date.UTC(2026, 6, 14, 10, 0, 0));
const NIGHT = new Date(Date.UTC(2026, 6, 14, 0, 30, 0));

async function resetKv() {
  for (const k of [
    "config:sweep_interval_day_seconds",
    "config:sweep_interval_night_seconds",
    "config:sweep_jitter_seconds",
    "config:upstream_budget_hourly",
    "config:upstream_live_reserve_hourly",
    "config:breaker_latency_p95_ms",
    "config:breaker_non_json_fraction",
    "config:breaker_window_seconds",
    "config:breaker_min_samples",
  ]) {
    await env.STIGLA_KV.delete(k);
  }
  await env.STIGLA_KV.delete("flag:analytics_sweep");
  await env.STIGLA_KV.delete("flag:upstream_budget");
}

// Seed one upstream-fetch meter row (used by the budget/breaker guard tests).
async function seedUpstream(
  ts: number,
  kind: "live" | "sweep",
  latencyMs: number,
  outcome: string,
): Promise<void> {
  await env.STIGLA_ANALYTICS_DB.prepare(
    "INSERT INTO upstream_events (ts, kind, latency_ms, outcome) VALUES (?, ?, ?, ?)",
  )
    .bind(ts, kind, latencyMs, outcome)
    .run();
}

// Sweep durable state lives in D1 now (migration 0007), read via this helper.
async function sweepState(key: string): Promise<string | null> {
  const row = await env.STIGLA_ANALYTICS_DB.prepare(
    "SELECT value FROM sweep_state WHERE key = ?",
  )
    .bind(key)
    .first<{ value: string }>();
  return row?.value ?? null;
}

beforeEach(async () => {
  await resetKv();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM raw_observations").run();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM sweep_state").run();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM upstream_events").run();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("parseInterval", () => {
  it("uses the fallback for an unset (null) key", () => {
    expect(parseInterval(null, 20)).toBe(20);
  });
  it("uses the fallback for a non-numeric or negative value", () => {
    expect(parseInterval("abc", 20)).toBe(20);
    expect(parseInterval("-5", 20)).toBe(20);
  });
  it("takes a valid non-negative override, including 0 (paused)", () => {
    expect(parseInterval("11", 20)).toBe(11);
    expect(parseInterval("0", 20)).toBe(0);
  });
});

describe("isNightHour", () => {
  it("is night in [01:00, 05:00) and day otherwise", () => {
    expect(isNightHour(0)).toBe(false);
    expect(isNightHour(1)).toBe(true);
    expect(isNightHour(4)).toBe(true);
    expect(isNightHour(5)).toBe(false);
    expect(isNightHour(12)).toBe(false);
  });
});

describe("loadSentinels", () => {
  it("serves the runtime sentinel artifact (minimal set)", async () => {
    const stops = await loadSentinels(env);
    expect(stops.length).toBeGreaterThan(100);
    expect(stops.every((s) => typeof s === "string")).toBe(true);
  });
});

describe("runSweepTick — gating", () => {
  it("is a no-op while the flag is OFF (prod default)", async () => {
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();
    expect(r.ran).toBe(false);
    expect(r.reason).toBe("disabled");
  });

  it("pauses at night (night interval defaults to 0)", async () => {
    await setFlag(env, "analytics_sweep", true);
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, NIGHT);
    await settle();
    expect(r.ran).toBe(false);
    expect(r.reason).toBe("night-paused");
  });

  it("honours an explicit night interval override", async () => {
    await setFlag(env, "analytics_sweep", true);
    await env.STIGLA_KV.put("config:sweep_interval_night_seconds", "40");
    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, NIGHT);
    await settle();
    expect(r.reason).toBe("night-active");
  });
});

describe("runSweepTick — rotation", () => {
  it("advances the cursor by the per-tick batch size", async () => {
    await setFlag(env, "analytics_sweep", true);
    // Pin the interval explicitly (default is now 60s → 1/tick) to exercise the
    // multi-sentinel batch: 20s → round(60/20) = 3 sentinels/tick.
    await env.STIGLA_KV.put("config:sweep_interval_day_seconds", "20");
    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const { ctx, settle } = collectingCtx();
    await runSweepTick(env, ctx, DAY);
    await settle();
    expect(await sweepState("cursor")).toBe("3");

    const c2 = collectingCtx();
    await runSweepTick(env, c2.ctx, DAY);
    await c2.settle();
    expect(await sweepState("cursor")).toBe("6");
  });
});

describe("runSweepTick — adaptive skip", () => {
  it("skips sentinels with a fresh organic observation within the current cycle", async () => {
    await setFlag(env, "analytics_sweep", true);
    await env.STIGLA_KV.put("config:sweep_interval_day_seconds", "20"); // 3/tick
    const stops = await loadSentinels(env);
    const nowSec = Math.floor(DAY.getTime() / 1000);
    const batch = stops.slice(0, 3); // day interval → 3/tick, cursor starts at 0

    // A fresh observation NOW for each batch stop. With 163 sentinels × 20s the
    // cycle is ~3260s, so an age-0 observation is well inside (cycle − margin) →
    // read as organic traffic → skipped. No separate visit-state needed.
    for (const s of batch) {
      await env.STIGLA_ANALYTICS_DB.prepare(
        `INSERT INTO raw_observations (line, stop_id, garage_no, vehicle_id, eta_minutes, stops_remaining, observed_at)
         VALUES ('79', ?, 'P26624', 'P26624', 3, 3, ?)`,
      )
        .bind(s, nowSec)
        .run();
    }

    // fetch would fail if reached; the point is it must NOT be reached.
    vi.stubGlobal("fetch", () => Promise.reject(new Error("should not fetch a skipped stop")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    expect(r.skipped).toBe(3);
    expect(r.swept).toEqual([]);
    // Cursor still advances by the batch size so skipped stops aren't retried.
    expect(await sweepState("cursor")).toBe("3");
  });
});

describe("runSweepTick — circuit breaker", () => {
  it("trips after N consecutive all-failed ticks and flips the flag OFF", async () => {
    await setFlag(env, "analytics_sweep", true);
    vi.stubGlobal("fetch", () => Promise.reject(new Error("upstream challenge/down")));

    for (let i = 0; i < 5; i++) {
      const { ctx, settle } = collectingCtx();
      await runSweepTick(env, ctx, DAY);
      await settle();
    }

    // The breaker flipped its own flag OFF (no redeploy).
    expect(await getFlag(env, "analytics_sweep")).toBe(false);
    const breaker = JSON.parse((await sweepState("breaker"))!);
    expect(breaker.consecutiveFailures).toBeGreaterThanOrEqual(5);
    expect(breaker.trippedAt).not.toBeNull();
  });

  it("resets the failure counter after a successful tick", async () => {
    await setFlag(env, "analytics_sweep", true);
    await env.STIGLA_KV.put("config:sweep_interval_day_seconds", "20"); // 3/tick
    // Seed a couple of failures.
    vi.stubGlobal("fetch", () => Promise.reject(new Error("down")));
    for (let i = 0; i < 2; i++) {
      const { ctx, settle } = collectingCtx();
      await runSweepTick(env, ctx, DAY);
      await settle();
    }
    let breaker = JSON.parse((await sweepState("breaker"))!);
    expect(breaker.consecutiveFailures).toBe(2);

    // Now a tick where every batch stop is skipped (attempted=0) must NOT count
    // as a success OR a failure — the counter is untouched.
    const stops = await loadSentinels(env);
    const nowSec = Math.floor(DAY.getTime() / 1000);
    const cursor = Number(await sweepState("cursor"));
    const batch = [0, 1, 2].map((i) => stops[(cursor + i) % stops.length]);
    for (const s of batch) {
      await env.STIGLA_ANALYTICS_DB.prepare(
        `INSERT INTO raw_observations (line, stop_id, garage_no, vehicle_id, eta_minutes, stops_remaining, observed_at)
         VALUES ('79', ?, 'P1', NULL, 3, 3, ?)`,
      )
        .bind(s, nowSec)
        .run();
    }
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();
    expect(r.skipped).toBe(3);
    breaker = JSON.parse((await sweepState("breaker"))!);
    expect(breaker.consecutiveFailures).toBe(2); // untouched
  });
});

// The DAY instant as unix seconds — used to place meter rows inside the rolling
// windows the guard reads.
const DAY_SEC = Math.floor(DAY.getTime() / 1000);

describe("runSweepTick — request budget gate (upstream_budget on)", () => {
  it("stands the sweep down when the rolling-hour total leaves no room for the reserve", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    // ceiling 5, reserve 2 → sweepCeiling 3. Seed 4 live fetches this hour (> 3),
    // so adding the sweep's 1/tick would cross the sweep ceiling.
    await env.STIGLA_KV.put("config:upstream_budget_hourly", "5");
    await env.STIGLA_KV.put("config:upstream_live_reserve_hourly", "2");
    for (let i = 0; i < 4; i++) await seedUpstream(DAY_SEC - 10 - i, "live", 100, "json");

    // fetch must NOT be reached — the tick should no-op on the budget.
    vi.stubGlobal("fetch", () => Promise.reject(new Error("should not fetch when budget-exhausted")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    expect(r.ran).toBe(false);
    expect(r.reason).toContain("budget-exhausted");
    expect(await sweepState("cursor")).toBeNull(); // cursor did NOT advance
  });

  it("sweeps normally while under the sweep ceiling", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    await env.STIGLA_KV.put("config:upstream_budget_hourly", "1000");
    await env.STIGLA_KV.put("config:upstream_live_reserve_hourly", "300");
    await seedUpstream(DAY_SEC - 10, "live", 100, "json"); // well under 700

    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    // Not blocked by the budget: it attempted the batch (fetch failed, but the
    // cursor advanced by the 1/tick default tempo).
    expect(r.reason).toBe("day-active");
    expect(await sweepState("cursor")).toBe("1");
    expect(r.meter?.liveHr).toBe(1);
  });
});

describe("live path is never blocked by the budget", () => {
  it("getArrivals(kind:'live') still fetches even when the hour is over the ceiling", async () => {
    await setFlag(env, "upstream_budget", true);
    await setFlag(env, "analytics_collect", false); // keep the test focused on the fetch
    await env.STIGLA_KV.put("config:upstream_budget_hourly", "5");
    await env.STIGLA_KV.put("config:upstream_live_reserve_hourly", "2");
    for (let i = 0; i < 50; i++) await seedUpstream(DAY_SEC - 10 - i, "live", 100, "json");

    // Provide the upstream env the provider needs (secrets aren't bound in tests).
    const orig = {
      extra: env.TRANSIT_SOURCE_FORM_EXTRA_JSON,
      url: env.TRANSIT_SOURCE_BASE_URL,
    };
    (env as { TRANSIT_SOURCE_FORM_EXTRA_JSON: string }).TRANSIT_SOURCE_FORM_EXTRA_JSON = "{}";
    (env as { TRANSIT_SOURCE_BASE_URL: string }).TRANSIT_SOURCE_BASE_URL = "https://source.invalid/api";

    // A real upstream response — the live path must reach it regardless of budget.
    let fetched = false;
    vi.stubGlobal("fetch", () => {
      fetched = true;
      return Promise.resolve(
        new Response(JSON.stringify([]), { status: 200, headers: { "content-type": "application/json" } }),
      );
    });

    try {
      const { getArrivals } = await import("../src/lib/arrivals");
      const { ctx, settle } = collectingCtx();
      // A real sentinel id so getStopById resolves.
      const stops = await loadSentinels(env);
      await getArrivals(env, ctx, stops[0], { kind: "live" });
      await settle();
      expect(fetched).toBe(true); // the budget never gated the live fetch
    } finally {
      (env as { TRANSIT_SOURCE_FORM_EXTRA_JSON: string }).TRANSIT_SOURCE_FORM_EXTRA_JSON = orig.extra;
      (env as { TRANSIT_SOURCE_BASE_URL: string }).TRANSIT_SOURCE_BASE_URL = orig.url;
    }
  });
});

describe("runSweepTick — jitter", () => {
  it("applies a randomized pre-fetch delay within [0, 2×jitter] only when asked", async () => {
    await setFlag(env, "analytics_sweep", true);
    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));

    const sleeps: number[] = [];
    const sleep = (ms: number) => {
      sleeps.push(ms);
      return Promise.resolve();
    };
    // jitter default 10s, random 0.5 → delay = round(0.5 × 2 × 10 × 1000) = 10000ms.
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY, { applyJitter: true, sleep, random: () => 0.5 });
    await settle();
    expect(r.jitterMs).toBe(10000);
    expect(r.jitterMs).toBeGreaterThanOrEqual(0);
    expect(r.jitterMs).toBeLessThanOrEqual(2 * 10 * 1000);
    expect(sleeps).toEqual([10000]);
  });

  it("does not delay when jitter is off (admin/manual path)", async () => {
    await setFlag(env, "analytics_sweep", true);
    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const sleeps: number[] = [];
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY, {
      applyJitter: false,
      sleep: (ms) => (sleeps.push(ms), Promise.resolve()),
      random: () => 0.5,
    });
    await settle();
    expect(r.jitterMs).toBe(0);
    expect(sleeps).toEqual([]);
  });
});

describe("runSweepTick — degradation breaker (upstream_budget on)", () => {
  async function seedWindow(n: number, latencyMs: number, nonJson: number): Promise<void> {
    for (let i = 0; i < n; i++) {
      await seedUpstream(DAY_SEC - 10 - i, "live", latencyMs, i < nonJson ? "non_json" : "json");
    }
  }

  it("trips on high p95 latency (slow-but-200) and flips analytics_sweep OFF", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    await seedWindow(25, 4000, 0); // p95 4000ms > 3000ms default, 25 ≥ min samples

    vi.stubGlobal("fetch", () => Promise.reject(new Error("should not fetch after a trip")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    expect(r.ran).toBe(false);
    expect(r.reason).toContain("degradation-breaker");
    expect(r.reason).toContain("p95_latency");
    expect(await getFlag(env, "analytics_sweep")).toBe(false); // auto-OFF, no redeploy
  });

  it("trips on a high non-JSON/empty share", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    await seedWindow(20, 100, 10); // 50% non-JSON > 30% default, low latency

    vi.stubGlobal("fetch", () => Promise.reject(new Error("should not fetch after a trip")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    expect(r.reason).toContain("non_json_share");
    expect(await getFlag(env, "analytics_sweep")).toBe(false);
  });

  it("does not trip below the minimum sample count", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    await seedWindow(5, 9000, 5); // catastrophic but only 5 samples (< 20)

    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const { ctx, settle } = collectingCtx();
    const r = await runSweepTick(env, ctx, DAY);
    await settle();

    expect(r.reason).toBe("day-active"); // proceeded normally
    expect(await getFlag(env, "analytics_sweep")).toBe(true); // still on
  });

  it("re-enable is MANUAL: after a trip the sweep stays disabled until the flag is set", async () => {
    await setFlag(env, "analytics_sweep", true);
    await setFlag(env, "upstream_budget", true);
    await seedWindow(25, 4000, 0);

    vi.stubGlobal("fetch", () => Promise.reject(new Error("down")));
    const first = collectingCtx();
    await runSweepTick(env, first.ctx, DAY);
    await first.settle();
    expect(await getFlag(env, "analytics_sweep")).toBe(false);

    // A subsequent tick just no-ops as disabled — no auto-recovery.
    const second = collectingCtx();
    const r2 = await runSweepTick(env, second.ctx, DAY);
    await second.settle();
    expect(r2.reason).toBe("disabled");
    expect(await getFlag(env, "analytics_sweep")).toBe(false);

    // Only a manual flip brings it back.
    await setFlag(env, "analytics_sweep", true);
    expect(await getFlag(env, "analytics_sweep")).toBe(true);
  });
});
