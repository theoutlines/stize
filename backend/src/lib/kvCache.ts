import type { Env } from "../env";

// Short in-isolate read cache for KV config/flag keys (incident 2026-11-23:
// the account hit 50% of the free 100k KV reads/day by mid-afternoon, ~40% of
// them "not found" reads of unset flags/config re-read on every request).
//
// Trade-off, accepted: a flag/config flip reaches every isolate within
// KV_CACHE_TTL_MS instead of on the very next request. A write through this
// module (setFlag / setServiceKilled) updates the writing isolate at once, so
// /admin/flags still echoes what it just wrote.
export const KV_CACHE_TTL_MS = 30_000;

function ttlFor(env: Env): number {
  const raw = env.KV_CACHE_TTL_MS;
  const n = raw === undefined ? NaN : Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : KV_CACHE_TTL_MS;
}

type Entry = { value: string | null; expires: number };
const byNamespace = new WeakMap<object, Map<string, Entry>>();

function store(env: Env): Map<string, Entry> {
  let m = byNamespace.get(env.STIGLA_KV);
  if (!m) byNamespace.set(env.STIGLA_KV, (m = new Map()));
  return m;
}

export async function kvGetCached(env: Env, key: string): Promise<string | null> {
  const m = store(env);
  const now = Date.now();
  const ttl = ttlFor(env);
  const hit = m.get(key);
  if (ttl > 0 && hit && hit.expires > now) return hit.value;
  const value = await env.STIGLA_KV.get(key);
  if (ttl > 0) m.set(key, { value, expires: now + ttl });
  return value;
}

/** Record a value this isolate just wrote, so its own reads see it at once. */
export function kvCacheRemember(env: Env, key: string, value: string | null): void {
  store(env).set(key, { value, expires: Date.now() + ttlFor(env) });
}

/** Tests: forget everything cached for this namespace. */
export function kvCacheClear(env: Env): void {
  byNamespace.delete(env.STIGLA_KV);
}
