import type { Env } from "../env";

const NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search";
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 30; // geocoding results for a street name barely change
const BELGRADE_VIEWBOX = "20.2,44.95,20.65,44.65"; // lon1,lat1,lon2,lat2 — biases results, doesn't hard-filter

export interface GeocodeResult {
  display_name: string;
  lat: number;
  lon: number;
}

export async function geocodeSearch(env: Env, query: string): Promise<GeocodeResult[]> {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];

  const cacheKey = `geocode:${normalized}`;
  const cached = await env.STIGLA_KV.get(cacheKey);
  if (cached) return JSON.parse(cached) as GeocodeResult[];

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

  await env.STIGLA_KV.put(cacheKey, JSON.stringify(results), { expirationTtl: CACHE_TTL_SECONDS });
  return results;
}
