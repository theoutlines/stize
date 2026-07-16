// Stale-while-revalidate on top of the Workers Cache API: callers always get
// an immediate response from `caches.default`; a background refresh via
// `ctx.waitUntil()` keeps it from drifting too far behind. Only a genuinely
// cold cache key blocks the caller on a real upstream fetch.
//
// A light backoff rides along in the same cache entry: repeated upstream
// failures push out the next allowed revalidation attempt (capped), so a
// flaky/down source gets polled less often instead of every request.

const MAX_BACKOFF_SECONDS = 600;
const EDGE_CACHE_HEADROOM_SECONDS = 300;

// Hard-staleness limit: a cache entry older than this is NOT handed back as
// stale-while-revalidate — the caller blocks on one fresh fetch and gets the
// fresh board instead. Normal SWR (instant stale + background refresh) still
// applies for entries between the TTL and this limit.
//
// CONTRACT — this MUST stay below the client's playback staleness gate
// (`_stalenessSeconds = 45` in app/lib/core/timed_trajectory.dart). Above that
// gate the marker stops predicting from its plan and freezes at its last fix; a
// single 30s SWR fetch can otherwise return a board up to ~60s old (it triggers
// a revalidation the NEXT fetch sees, not this one), so without this the markers
// freeze half the time. Blocking here to return a board younger than the gate is
// exactly what keeps them moving. **Move the two together — never widen this
// past the client gate.** (Both consumers use the 30s arrivals TTL today.)
const HARD_STALE_SECONDS = 40;

// Per-isolate single-flight: concurrent callers that need the same upstream value
// share ONE in-flight fetch (the rest await the same promise), so N simultaneous
// hard-stale hits do a single upstream request instead of a thundering herd.
// Keyed by cache-key URL; the map lives for the isolate's lifetime and each entry
// is cleared the moment its fetch settles. (Cross-isolate dedup isn't possible in
// Workers, but the TTL + backoff bound that.)
const inFlight = new Map<string, Promise<unknown>>();

function singleFlight<T>(key: string, fn: () => Promise<T>): Promise<T> {
  const existing = inFlight.get(key) as Promise<T> | undefined;
  if (existing) return existing;
  const p = (async () => {
    try {
      return await fn();
    } finally {
      inFlight.delete(key);
    }
  })();
  inFlight.set(key, p);
  return p;
}

interface CachedPayload<T> {
  data: T;
  updatedAt: string; // last successful fetch, ISO
  nextAttemptAt: string; // don't attempt a refresh before this
  consecutiveFailures: number;
}

export interface SwrResult<T> {
  data: T;
  updatedAt: string;
  stale: boolean;
}

// Duck-typed rather than the full `ExecutionContext` so this works with
// whichever flavor a caller has on hand (raw Workers ctx, Hono's `c.executionCtx`, ...).
export interface WaitUntilCtx {
  waitUntil(promise: Promise<unknown>): void;
}

export async function getWithStaleWhileRevalidate<T>(
  cacheKeyUrl: string,
  ttlSeconds: number,
  ctx: WaitUntilCtx,
  fetchFresh: () => Promise<T>,
): Promise<SwrResult<T>> {
  const cache = caches.default;
  const cacheKey = new Request(cacheKeyUrl);

  const cached = await cache.match(cacheKey);
  if (cached) {
    const payload = (await cached.json()) as CachedPayload<T>;
    const now = Date.now();
    const ageMs = now - Date.parse(payload.updatedAt);
    const stale = ageMs >= ttlSeconds * 1000;
    const hardStale = ageMs >= HARD_STALE_SECONDS * 1000;
    const canAttempt = now >= Date.parse(payload.nextAttemptAt);

    // Hard-stale (older than the client's freshness gate) and allowed to refresh:
    // don't hand back a board that would freeze the markers — block on ONE
    // (deduped) fresh fetch and return it. If the upstream is down the fetch
    // throws: arm the backoff and fall back to serving last-known-good, so the
    // markers park honestly rather than the source getting hammered. When the
    // backoff is active (`!canAttempt`) we skip straight to serving stale below —
    // the correct degradation for a source that's down.
    if (hardStale && canAttempt) {
      try {
        const { data, updatedAt } = await singleFlight(cacheKeyUrl, () =>
          fetchAndStore(cache, cacheKey, ttlSeconds, fetchFresh),
        );
        return { data, updatedAt, stale: false };
      } catch {
        await armBackoff(cache, cacheKey, ttlSeconds, payload);
        return { data: payload.data, updatedAt: payload.updatedAt, stale: true };
      }
    }

    // Normal SWR window (TTL ≤ age < hard-stale): serve stale now, refresh in the
    // background (single-flighted so a background refresh and any concurrent
    // hard-stale block share the same upstream fetch).
    if (stale && canAttempt) {
      ctx.waitUntil(
        singleFlight(cacheKeyUrl, () =>
          fetchAndStore(cache, cacheKey, ttlSeconds, fetchFresh),
        )
          .then(() => undefined)
          .catch(() => armBackoff(cache, cacheKey, ttlSeconds, payload)),
      );
    }
    return { data: payload.data, updatedAt: payload.updatedAt, stale };
  }

  // Cold cache key: the caller has to wait for one real fetch (deduped, so a burst
  // of cold requests doesn't fan out N upstream calls).
  const { data, updatedAt } = await singleFlight(cacheKeyUrl, () =>
    fetchAndStore(cache, cacheKey, ttlSeconds, fetchFresh),
  );
  return { data, updatedAt, stale: false };
}

// Fetch fresh, store it, and return it. Throws on upstream failure (the caller
// decides whether to arm the backoff or propagate).
async function fetchAndStore<T>(
  cache: Cache,
  cacheKey: Request,
  ttlSeconds: number,
  fetchFresh: () => Promise<T>,
): Promise<{ data: T; updatedAt: string }> {
  const data = await fetchFresh();
  const updatedAt = new Date().toISOString();
  await storePayload(cache, cacheKey, ttlSeconds, {
    data,
    updatedAt,
    nextAttemptAt: updatedAt,
    consecutiveFailures: 0,
  });
  return { data, updatedAt };
}

// Push out the next allowed refresh after a failure (exponential, capped), so a
// flaky/down source is polled less often instead of on every request.
async function armBackoff<T>(
  cache: Cache,
  cacheKey: Request,
  ttlSeconds: number,
  previous: CachedPayload<T>,
): Promise<void> {
  const consecutiveFailures = previous.consecutiveFailures + 1;
  const backoffSeconds = Math.min(ttlSeconds * 2 ** consecutiveFailures, MAX_BACKOFF_SECONDS);
  await storePayload(cache, cacheKey, ttlSeconds, {
    ...previous,
    nextAttemptAt: new Date(Date.now() + backoffSeconds * 1000).toISOString(),
    consecutiveFailures,
  });
}

async function storePayload<T>(
  cache: Cache,
  cacheKey: Request,
  ttlSeconds: number,
  payload: CachedPayload<T>,
): Promise<void> {
  const response = new Response(JSON.stringify(payload), {
    headers: {
      "content-type": "application/json",
      // Generous outer bound so the edge doesn't evict before our own
      // staleness/backoff logic (which operates on `updatedAt`) gets a say.
      "cache-control": `max-age=${ttlSeconds + EDGE_CACHE_HEADROOM_SECONDS}`,
    },
  });
  await cache.put(cacheKey, response);
}
