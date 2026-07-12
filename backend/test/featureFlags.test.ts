import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { getAllFlags, getFlag, isFeatureFlag, setFlag } from "../src/lib/featureFlags";

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
    expect(Object.keys(flags).sort()).toEqual(["analytics_collect", "analytics_show", "nearby_list"]);
  });

  it("guards against unknown flag names", () => {
    expect(isFeatureFlag("analytics_show")).toBe(true);
    expect(isFeatureFlag("nope")).toBe(false);
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
