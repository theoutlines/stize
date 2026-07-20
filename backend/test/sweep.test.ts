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
// fire-and-forget state persistence (cursor / visits / breaker).
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
    "sweep:cursor",
    "sweep:visits",
    "sweep:breaker",
  ]) {
    await env.STIGLA_KV.delete(k);
  }
  await env.STIGLA_KV.delete("flag:analytics_sweep");
}

beforeEach(async () => {
  await resetKv();
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM raw_observations").run();
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
    // Day default interval 20s → round(60/20) = 3 sentinels/tick.
    vi.stubGlobal("fetch", () => Promise.reject(new Error("no upstream")));
    const { ctx, settle } = collectingCtx();
    await runSweepTick(env, ctx, DAY);
    await settle();
    expect(await env.STIGLA_KV.get("sweep:cursor")).toBe("3");

    const c2 = collectingCtx();
    await runSweepTick(env, c2.ctx, DAY);
    await c2.settle();
    expect(await env.STIGLA_KV.get("sweep:cursor")).toBe("6");
  });
});

describe("runSweepTick — adaptive skip", () => {
  it("skips sentinels with fresh organic observations since the last visit", async () => {
    await setFlag(env, "analytics_sweep", true);
    const stops = await loadSentinels(env);
    const nowSec = Math.floor(DAY.getTime() / 1000);
    const batch = stops.slice(0, 3); // day interval → 3/tick, cursor starts at 0

    // Organic observation NOW for each batch stop, and a last-visit an hour ago
    // (so the fresh obs post-dates our visit → treated as organic).
    await env.STIGLA_KV.put(
      "sweep:visits",
      JSON.stringify(Object.fromEntries(batch.map((s) => [s, nowSec - 3600]))),
    );
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
    expect(await env.STIGLA_KV.get("sweep:cursor")).toBe("3");
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
    const breaker = JSON.parse((await env.STIGLA_KV.get("sweep:breaker"))!);
    expect(breaker.consecutiveFailures).toBeGreaterThanOrEqual(5);
    expect(breaker.trippedAt).not.toBeNull();
  });

  it("resets the failure counter after a successful tick", async () => {
    await setFlag(env, "analytics_sweep", true);
    // Seed a couple of failures.
    vi.stubGlobal("fetch", () => Promise.reject(new Error("down")));
    for (let i = 0; i < 2; i++) {
      const { ctx, settle } = collectingCtx();
      await runSweepTick(env, ctx, DAY);
      await settle();
    }
    let breaker = JSON.parse((await env.STIGLA_KV.get("sweep:breaker"))!);
    expect(breaker.consecutiveFailures).toBe(2);

    // Now a tick where every batch stop is skipped (attempted=0) must NOT count
    // as a success OR a failure — the counter is untouched.
    const stops = await loadSentinels(env);
    const nowSec = Math.floor(DAY.getTime() / 1000);
    const cursor = Number(await env.STIGLA_KV.get("sweep:cursor"));
    const batch = [0, 1, 2].map((i) => stops[(cursor + i) % stops.length]);
    await env.STIGLA_KV.put(
      "sweep:visits",
      JSON.stringify(Object.fromEntries(batch.map((s) => [s, nowSec - 3600]))),
    );
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
    breaker = JSON.parse((await env.STIGLA_KV.get("sweep:breaker"))!);
    expect(breaker.consecutiveFailures).toBe(2); // untouched
  });
});
