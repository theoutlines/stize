import type { Env } from "../env";

const NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search";
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 30; // geocoding results for a street name barely change
const BELGRADE_VIEWBOX = "20.2,44.95,20.65,44.65"; // lon1,lat1,lon2,lat2 — biases results, doesn't hard-filter

export interface GeocodeResult {
  display_name: string;
  lat: number;
  lon: number;
}

export class GeocodeRateLimited extends Error {}

// Results are cached in the edge Cache API, not KV: KV allows only 1,000 writes a
// day on the free plan, account-wide, and every new search term was a write. A
// burst of searches could have used them up and with them the flag writes the
// D1 governor relies on (technical audit 2026-11-22).
//
// `allowUpstream` is asked only on a cache miss, right before calling Nominatim,
// so the per-IP / global rate limit spends nothing on cached answers.
export async function geocodeSearch(
  env: Env,
  query: string,
  allowUpstream: () => Promise<boolean> = async () => true,
): Promise<GeocodeResult[]> {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];

  const cache = caches.default;
  const cacheKey = new Request(`https://cache.stigla.internal/geocode/${encodeURIComponent(normalized)}`);
  const cached = await cache.match(cacheKey);
  if (cached) return (await cached.json()) as GeocodeResult[];
  if (!(await allowUpstream())) throw new GeocodeRateLimited(normalized);

  const url = new URL(NOMINATIM_BASE_URL);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "10");
  url.searchParams.set("viewbox", BELGRADE_VIEWBOX);
  url.searchParams.set("bounded", "0");

  const res = await fetch(url, {
    headers: {
      "user-agent": `StiglaApp/0.1 (+${env.NOMINATIM_USER_AGENT_CONTACT}; personal use, low volume)`,
    },
  });
  if (!res.ok) throw new Error(`Nominatim responded ${res.status}`);

  const body = (await res.json()) as Array<{ display_name: string; lat: string; lon: string }>;
  const results = body.map((r) => ({
    display_name: r.display_name,
    lat: parseFloat(r.lat),
    lon: parseFloat(r.lon),
  }));

  await cache.put(
    cacheKey,
    new Response(JSON.stringify(results), {
      headers: { "content-type": "application/json", "cache-control": `max-age=${CACHE_TTL_SECONDS}` },
    }),
  );
  return results;
}
