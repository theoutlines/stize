import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import {
  getAllFlags,
  getFlag,
  getFlagMemoized,
  isFeatureFlag,
  setFlag,
} from "../src/lib/featureFlags";

describe("featureFlags", () => {
  it("defaults every flag to off when its KV key is unset", async () => {
    expect(await getFlag(env, "analytics_collect")).toBe(false);
    expect(await getFlag(env, "analytics_show")).toBe(false);
  });

  it("flips a flag on and off independently", async () => {
    await setFlag(env, "analytics_collect", true);
    expect(await getFlag(env, "analytics_collect")).toBe(true);
    // The other flag is unaffected.
    expect(await getFlag(env, "analytics_show")).toBe(false);

    await setFlag(env, "analytics_collect", false);
    expect(await getFlag(env, "analytics_collect")).toBe(false);
  });

  it("getAllFlags returns every known flag", async () => {
    const flags = await getAllFlags(env);
    expect(Object.keys(flags).sort()).toEqual([
      "analytics_collect",
      "analytics_show",
      "analytics_sweep",
      "context_panel",
      "coverage_map_show",
      "coverage_on_main_map",
      "jam_detection_show",
      "nearby_list",
      "nearby_sort_board",
      "product_analytics",
      "vehicles_on_demand",
    ]);
  });

  it("guards against unknown flag names", () => {
    expect(isFeatureFlag("analytics_show")).toBe(true);
    expect(isFeatureFlag("nope")).toBe(false);
  });

  it("getFlagMemoized reads KV once per scope but re-reads across scopes (instant flip)", async () => {
    // Count KV reads without touching the real binding's other methods.
    let reads = 0;
    const counting = new Proxy(env, {
      get(target, prop, recv) {
        if (prop === "STIGLA_KV") {
          return { get: (k: string) => (reads++, target.STIGLA_KV.get(k)) };
        }
        return Reflect.get(target, prop, recv);
      },
    }) as typeof env;

    await setFlag(env, "analytics_collect", true);
    const scopeA = {};
    expect(await getFlagMemoized(counting, scopeA, "analytics_collect")).toBe(true);
    expect(await getFlagMemoized(counting, scopeA, "analytics_collect")).toBe(true);
    expect(reads).toBe(1); // same invocation → a single KV read, not one per call

    // Flip the flag; a NEW scope (next request) must observe it — no TTL/global cache.
    await setFlag(env, "analytics_collect", false);
    const scopeB = {};
    expect(await getFlagMemoized(counting, scopeB, "analytics_collect")).toBe(false);
    expect(reads).toBe(2);
    await setFlag(env, "analytics_collect", false);
  });

  it("defaults unset flags ON on staging, OFF on production, but an explicit value wins", async () => {
    const staging = { ...env, ENVIRONMENT: "staging" };
    const prod = { ...env, ENVIRONMENT: "production" };
    await env.STIGLA_KV.delete("flag:analytics_show");

    expect(await getFlag(staging, "analytics_show")).toBe(true);
    expect(await getFlag(prod, "analytics_show")).toBe(false);

    // An explicit KV value overrides the env default in both.
    await setFlag(env, "analytics_show", false);
    expect(await getFlag(staging, "analytics_show")).toBe(false);
    await env.STIGLA_KV.delete("flag:analytics_show");
  });
});
