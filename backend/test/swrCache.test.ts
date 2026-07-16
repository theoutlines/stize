import { describe, expect, it } from "vitest";
import { getWithStaleWhileRevalidate, type WaitUntilCtx } from "../src/lib/swrCache";

function fakeCtx(): WaitUntilCtx & { drain(): Promise<void> } {
  const pending: Promise<unknown>[] = [];
  return {
    waitUntil(p) {
      pending.push(p);
    },
    async drain() {
      await Promise.all(pending);
      pending.length = 0;
    },
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Seed the edge cache directly with an entry of a chosen age (and optional
// backoff), so the hard-stale path can be exercised without waiting real
// seconds. Mirrors the internal CachedPayload shape.
async function seedCache(
  key: string,
  data: unknown,
  ageSeconds: number,
  opts: { nextAttemptAtMsFromNow?: number; consecutiveFailures?: number } = {},
) {
  const updatedAt = new Date(Date.now() - ageSeconds * 1000).toISOString();
  const nextAttemptAt =
    opts.nextAttemptAtMsFromNow !== undefined
      ? new Date(Date.now() + opts.nextAttemptAtMsFromNow).toISOString()
      : updatedAt;
  const payload = {
    data,
    updatedAt,
    nextAttemptAt,
    consecutiveFailures: opts.consecutiveFailures ?? 0,
  };
  await caches.default.put(
    new Request(key),
    new Response(JSON.stringify(payload), {
      headers: { "content-type": "application/json", "cache-control": "max-age=999" },
    }),
  );
}

describe("getWithStaleWhileRevalidate", () => {
  it("fetches fresh on a cold key and serves the same value from cache on the next call", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/cold-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      return { n: calls };
    };

    const first = await getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh);
    expect(first.data).toEqual({ n: 1 });
    expect(first.stale).toBe(false);

    const second = await getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh);
    expect(second.data).toEqual({ n: 1 }); // still cached, no re-fetch
    expect(second.stale).toBe(false);
    expect(calls).toBe(1);
  });

  it("serves stale data immediately and refreshes in the background once past TTL", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/stale-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      return { n: calls };
    };

    await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh); // ttl ~50ms
    await sleep(100);

    const staleRead = await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh);
    expect(staleRead.stale).toBe(true);
    expect(staleRead.data).toEqual({ n: 1 }); // old value returned immediately

    await ctx.drain(); // let the background refresh finish
    expect(calls).toBe(2);

    const freshRead = await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh);
    expect(freshRead.data).toEqual({ n: 2 });
  });

  it("backs off after a failed refresh instead of retrying every request", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/backoff-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      if (calls === 1) return { ok: true };
      throw new Error("upstream down");
    };

    await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh);
    await sleep(100);

    // First stale read triggers a refresh attempt, which fails.
    await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh);
    await ctx.drain();
    expect(calls).toBe(2);

    // Immediately stale again, but backoff should suppress another attempt right away.
    const again = await getWithStaleWhileRevalidate(key, 0.05, ctx, fetchFresh);
    await ctx.drain();
    expect(again.data).toEqual({ ok: true }); // still serving last-known-good data
    expect(calls).toBe(2); // no new attempt yet
  });

  // A board older than the client's playback staleness gate (HARD_STALE = 40s)
  // must NOT be served stale — the caller blocks on a fresh fetch and gets it, so
  // the markers never freeze on it.
  it("blocks and returns fresh for a hard-stale entry (older than 40s)", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/hardstale-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      return { n: calls };
    };
    await seedCache(key, { n: 0 }, 41); // 41s old → past the hard-stale limit

    const res = await getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh);
    expect(res.stale).toBe(false); // did NOT serve the stale board
    expect(res.data).toEqual({ n: 1 }); // returned the freshly-fetched one
    expect(calls).toBe(1); // and actually fetched (blocking)
  });

  it("single-flights concurrent hard-stale hits into ONE upstream fetch", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/singleflight-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      await sleep(50); // slow enough that the three overlap
      return { n: calls };
    };
    await seedCache(key, { n: 0 }, 41);

    const results = await Promise.all([
      getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh),
      getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh),
      getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh),
    ]);

    expect(calls).toBe(1); // deduped — a single upstream fetch, not a herd
    for (const r of results) {
      expect(r.stale).toBe(false);
      expect(r.data).toEqual({ n: 1 });
    }
  });

  it("during backoff, a hard-stale entry is served stale WITHOUT blocking", async () => {
    const ctx = fakeCtx();
    const key = `https://cache.test/hardstale-backoff-${Math.random()}`;
    let calls = 0;
    const fetchFresh = async () => {
      calls++;
      return { n: calls };
    };
    // Hard-stale (41s) but the source is down: backoff is armed 60s out.
    await seedCache(key, { n: 0 }, 41, { nextAttemptAtMsFromNow: 60_000, consecutiveFailures: 2 });

    const res = await getWithStaleWhileRevalidate(key, 30, ctx, fetchFresh);
    await ctx.drain();
    // Correct degradation: last-known-good served, no fetch (source stays unhit,
    // the client marker parks honestly).
    expect(res.stale).toBe(true);
    expect(res.data).toEqual({ n: 0 });
    expect(calls).toBe(0);
  });
});
