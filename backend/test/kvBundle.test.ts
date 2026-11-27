import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { getFlag, setFlag } from "../src/lib/featureFlags";
import {
  CONFIG_BUNDLE_KEY,
  isBundledKey,
  kvCacheClear,
  kvGetCached,
  rebuildConfigBundle,
} from "../src/lib/kvCache";

type KV = typeof env.STIGLA_KV;

/** The test env with the bundle on, over a KV wrapper that counts reads. */
function counted() {
  const reads: string[] = [];
  const real = env.STIGLA_KV;
  const kv = new Proxy(real, {
    get(target, prop) {
      if (prop === "get") {
        return (key: string, ...rest: unknown[]) => {
          reads.push(key);
          return (target.get as (...a: unknown[]) => unknown).call(target, key, ...rest);
        };
      }
      const v = Reflect.get(target, prop, target);
      return typeof v === "function" ? v.bind(target) : v;
    },
  }) as KV;
  const e = {
    ...env,
    STIGLA_KV: kv,
    KV_CACHE_TTL_MS: "60000",
    KV_CONFIG_BUNDLE: "1",
  } as typeof env;
  return { e, reads };
}

async function clearKv() {
  const all = await env.STIGLA_KV.list();
  await Promise.all(all.keys.map((k) => env.STIGLA_KV.delete(k.name)));
}

describe("config bundle", () => {
  beforeEach(clearKv);

  it("knows which keys belong in it", () => {
    expect(isBundledKey("flag:analytics_collect")).toBe(true);
    expect(isBundledKey("config:sweep_interval_day_seconds")).toBe(true);
    expect(isBundledKey("service_killed")).toBe(true);
    expect(isBundledKey(CONFIG_BUNDLE_KEY)).toBe(false);
    expect(isBundledKey("d1_governor:state")).toBe(false);
  });

  it("is built from the individual keys on the first read", async () => {
    await env.STIGLA_KV.put("flag:analytics_collect", "1");
    await env.STIGLA_KV.put("config:donate_url", "https://example.org/d");
    const { e } = counted();
    kvCacheClear(e);
    expect(await kvGetCached(e, "flag:analytics_collect")).toBe("1");
    expect(await kvGetCached(e, "config:donate_url")).toBe("https://example.org/d");
    expect(await kvGetCached(e, "config:unset")).toBeNull();
    const raw = await env.STIGLA_KV.get(CONFIG_BUNDLE_KEY);
    expect(JSON.parse(raw!)).toEqual({
      "config:donate_url": "https://example.org/d",
      "flag:analytics_collect": "1",
    });
  });

  it("a cold isolate reads one key, not one per setting", async () => {
    await env.STIGLA_KV.put("flag:analytics_collect", "1");
    await env.STIGLA_KV.put("config:d1_governor_interval_min", "15");
    await rebuildConfigBundle({ ...env, KV_CONFIG_BUNDLE: "1" } as typeof env);
    const { e, reads } = counted();
    kvCacheClear(e);
    for (const k of [
      "flag:analytics_collect",
      "flag:analytics_sweep",
      "flag:upstream_budget",
      "config:d1_governor_interval_min",
      "config:d1_governor_threshold_pct",
      "config:sweep_interval_day_seconds",
      "service_killed",
    ]) {
      await kvGetCached(e, k);
    }
    expect(reads).toEqual([CONFIG_BUNDLE_KEY]);
  });

  it("setFlag updates the bundle, so another isolate sees it", async () => {
    const a = counted().e;
    kvCacheClear(a);
    await setFlag(a, "analytics_sweep", true);
    const b = counted().e;
    kvCacheClear(b);
    expect(await getFlag(b, "analytics_sweep")).toBe(true);
    expect(await env.STIGLA_KV.get("flag:analytics_sweep")).toBe("1");
  });

  it("a key changed by hand shows up after a rebuild", async () => {
    await env.STIGLA_KV.put("config:sweep_interval_day_seconds", "20");
    await rebuildConfigBundle({ ...env, KV_CONFIG_BUNDLE: "1" } as typeof env);
    await env.STIGLA_KV.put("config:sweep_interval_day_seconds", "40");
    const { e } = counted();
    kvCacheClear(e);
    expect(await kvGetCached(e, "config:sweep_interval_day_seconds")).toBe("20");
    await rebuildConfigBundle(e);
    kvCacheClear(e);
    expect(await kvGetCached(e, "config:sweep_interval_day_seconds")).toBe("40");
  });

  it("keys outside the bundle are read directly", async () => {
    await env.STIGLA_KV.put("d1_governor:state", "{}");
    const { e, reads } = counted();
    kvCacheClear(e);
    expect(await kvGetCached(e, "d1_governor:state")).toBe("{}");
    expect(reads).toEqual(["d1_governor:state"]);
  });

  it("a rebuild that changes nothing writes nothing", async () => {
    await env.STIGLA_KV.put("flag:analytics_collect", "1");
    const e = { ...env, KV_CONFIG_BUNDLE: "1" } as typeof env;
    await rebuildConfigBundle(e);
    const before = await env.STIGLA_KV.getWithMetadata(CONFIG_BUNDLE_KEY);
    await rebuildConfigBundle(e);
    const after = await env.STIGLA_KV.getWithMetadata(CONFIG_BUNDLE_KEY);
    expect(after.value).toBe(before.value);
  });
});
