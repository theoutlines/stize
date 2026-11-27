import type { Env } from "../env";

// Reads of KV config and flag keys, made cheap.
//
// Incident 2026-11-23: the account hit 50% of the free 100k KV reads/day by
// mid-afternoon, ~40% of them "not found" reads of unset flags/config re-read on
// every request. Fix 1 was a short in-isolate cache (below).
//
// Incident 2026-11-26: 50% again, over the whole day. The in-isolate cache only
// helps an isolate that is reused, and the per-minute cron mostly starts in a
// fresh one: each tick read ~15 config/flag keys one by one (≈0.4 reads/s day
// and night). Fix 2 is the CONFIG BUNDLE: every config/flag key also lives in
// one KV value, `config:bundle` (a JSON object key -> value). A cold isolate
// reads that one key instead of fifteen. Bulk `get([...])` would not help: KV
// bills each key of a bulk read as one read.
//
// The individual keys stay the source of truth (admin writes and `wrangler kv
// key put` keep working); the bundle is rebuilt from them every hour by the
// cron, on the first read when it is missing, and right away by setFlag /
// setServiceKilled. A key changed by hand in the dashboard therefore reaches
// the app within an hour, or at once with POST /admin/config/rebuild.
//
// Trade-off, accepted: a flag/config flip reaches every isolate within
// KV_CACHE_TTL_MS instead of on the very next request. A write through this
// module (setFlag / setServiceKilled) updates the writing isolate at once, so
// /admin/flags still echoes what it just wrote.
export const KV_CACHE_TTL_MS = 30_000;

/** The one KV value holding every config/flag key (see above). */
export const CONFIG_BUNDLE_KEY = "config:bundle";

/** Keys that belong in the bundle: flags, `config:*` settings, the kill switch. */
export function isBundledKey(key: string): boolean {
  if (key === CONFIG_BUNDLE_KEY) return false;
  return key.startsWith("flag:") || key.startsWith("config:") || key === "service_killed";
}

type Bundle = Record<string, string>;

function ttlFor(env: Env): number {
  const raw = env.KV_CACHE_TTL_MS;
  const n = raw === undefined ? NaN : Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : KV_CACHE_TTL_MS;
}

function bundleOn(env: Env): boolean {
  return env.KV_CONFIG_BUNDLE !== "0";
}

type Entry = { value: string | null; expires: number };
type BundleEntry = { value: Promise<Bundle>; expires: number };
const byNamespace = new WeakMap<object, Map<string, Entry>>();
const bundles = new WeakMap<object, BundleEntry>();

function store(env: Env): Map<string, Entry> {
  let m = byNamespace.get(env.STIGLA_KV);
  if (!m) byNamespace.set(env.STIGLA_KV, (m = new Map()));
  return m;
}

function parseBundle(raw: string | null): Bundle | null {
  if (raw === null) return null;
  try {
    const v = JSON.parse(raw) as unknown;
    if (v && typeof v === "object" && !Array.isArray(v)) return v as Bundle;
  } catch {
    // A broken bundle is rebuilt from the individual keys below.
  }
  return null;
}

/**
 * Rebuild the bundle from the individual keys (two list operations, one read
 * per existing key) and write it if it changed. Returns the new bundle.
 */
export async function rebuildConfigBundle(env: Env): Promise<Bundle> {
  const names: string[] = [];
  for (const prefix of ["flag:", "config:"]) {
    let cursor: string | undefined;
    do {
      const page = await env.STIGLA_KV.list({ prefix, cursor });
      for (const k of page.keys) if (isBundledKey(k.name)) names.push(k.name);
      cursor = page.list_complete ? undefined : page.cursor;
    } while (cursor);
  }
  names.push("service_killed");
  const values = await Promise.all(names.map((n) => env.STIGLA_KV.get(n)));
  const next: Bundle = {};
  names.forEach((n, i) => {
    const v = values[i];
    if (v !== null) next[n] = v;
  });
  const json = JSON.stringify(sortKeys(next));
  const current = await env.STIGLA_KV.get(CONFIG_BUNDLE_KEY);
  if (current !== json) await env.STIGLA_KV.put(CONFIG_BUNDLE_KEY, json);
  bundles.set(env.STIGLA_KV, { value: Promise.resolve(next), expires: Date.now() + ttlFor(env) });
  return next;
}

function sortKeys(b: Bundle): Bundle {
  return Object.fromEntries(Object.entries(b).sort(([a], [z]) => a.localeCompare(z)));
}

async function loadBundle(env: Env): Promise<Bundle> {
  const raw = await env.STIGLA_KV.get(CONFIG_BUNDLE_KEY);
  return parseBundle(raw) ?? rebuildConfigBundle(env);
}

function bundleFor(env: Env): Promise<Bundle> {
  const now = Date.now();
  const hit = bundles.get(env.STIGLA_KV);
  if (hit && hit.expires > now) return hit.value;
  const value = loadBundle(env);
  // One in-flight load per isolate; a failed load is not cached.
  bundles.set(env.STIGLA_KV, { value, expires: now + ttlFor(env) });
  value.catch(() => bundles.delete(env.STIGLA_KV));
  return value;
}

export async function kvGetCached(env: Env, key: string): Promise<string | null> {
  const m = store(env);
  const now = Date.now();
  const ttl = ttlFor(env);
  const hit = m.get(key);
  if (ttl > 0 && hit && hit.expires > now) return hit.value;
  const value =
    bundleOn(env) && ttl > 0 && isBundledKey(key)
      ? ((await bundleFor(env))[key] ?? null)
      : await env.STIGLA_KV.get(key);
  if (ttl > 0) m.set(key, { value, expires: now + ttl });
  return value;
}

/**
 * Write one config/flag key: the individual key (the source of truth), the
 * bundle, and this isolate's caches, so its own reads see it at once.
 */
export async function kvPutConfig(env: Env, key: string, value: string): Promise<void> {
  await env.STIGLA_KV.put(key, value);
  if (bundleOn(env) && isBundledKey(key)) {
    const current = parseBundle(await env.STIGLA_KV.get(CONFIG_BUNDLE_KEY));
    if (current) {
      current[key] = value;
      await env.STIGLA_KV.put(CONFIG_BUNDLE_KEY, JSON.stringify(sortKeys(current)));
      bundles.set(env.STIGLA_KV, {
        value: Promise.resolve(current),
        expires: Date.now() + ttlFor(env),
      });
    } else {
      await rebuildConfigBundle(env);
    }
  }
  kvCacheRemember(env, key, value);
}

/** Record a value this isolate just wrote, so its own reads see it at once. */
export function kvCacheRemember(env: Env, key: string, value: string | null): void {
  store(env).set(key, { value, expires: Date.now() + ttlFor(env) });
}

/** Tests: forget everything cached for this namespace. */
export function kvCacheClear(env: Env): void {
  byNamespace.delete(env.STIGLA_KV);
  bundles.delete(env.STIGLA_KV);
}
