import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { kvCacheClear, kvCacheRemember, kvGetCached } from "../src/lib/kvCache";

describe("kvGetCached", () => {
  it("serves repeat reads from memory within the TTL", async () => {
    const e = { ...env, KV_CACHE_TTL_MS: "60000" } as typeof env;
    kvCacheClear(e);
    await env.STIGLA_KV.put("cfg:x", "1");
    expect(await kvGetCached(e, "cfg:x")).toBe("1");
    await env.STIGLA_KV.put("cfg:x", "2");
    expect(await kvGetCached(e, "cfg:x")).toBe("1"); // cached
    kvCacheRemember(e, "cfg:x", "2");
    expect(await kvGetCached(e, "cfg:x")).toBe("2"); // own write seen at once
  });

  it("caches a missing key too (unset flags were most of the reads)", async () => {
    const e = { ...env, KV_CACHE_TTL_MS: "60000" } as typeof env;
    kvCacheClear(e);
    expect(await kvGetCached(e, "cfg:missing")).toBeNull();
    await env.STIGLA_KV.put("cfg:missing", "1");
    expect(await kvGetCached(e, "cfg:missing")).toBeNull();
  });

  it("TTL 0 reads through every time", async () => {
    await env.STIGLA_KV.put("cfg:y", "a");
    expect(await kvGetCached(env, "cfg:y")).toBe("a");
    await env.STIGLA_KV.put("cfg:y", "b");
    expect(await kvGetCached(env, "cfg:y")).toBe("b");
  });
});
