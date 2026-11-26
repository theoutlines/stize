import { toLatin } from "./latin";
import type { Env } from "../env";

const NOMINATIM_BASE_URL = "https://nominatim.openstreetmap.org/search";
const CACHE_TTL_SECONDS = 60 * 60 * 24 * 30; // geocoding results for a street name barely change
// Every stop in the feed (Mladenovac in the south to Borča in the north) plus
// about 2 km. Nominatim is asked to stay inside it (bounded=1, Serbia only),
// and results are filtered against it again: a query like "830" used to bring
// addresses from Taiwan and the US.
export const BELGRADE_BOUNDS = { west: 20.07, south: 44.36, east: 20.75, north: 45.09 };
const BELGRADE_VIEWBOX = `${BELGRADE_BOUNDS.west},${BELGRADE_BOUNDS.north},${BELGRADE_BOUNDS.east},${BELGRADE_BOUNDS.south}`;

export function insideBelgrade(lat: number, lon: number): boolean {
  const b = BELGRADE_BOUNDS;
  return lat >= b.south && lat <= b.north && lon >= b.west && lon <= b.east;
}

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
  const cacheKey = new Request(`https://cache.stigla.internal/geocode/v4/${encodeURIComponent(normalized)}`);
  const cached = await cache.match(cacheKey);
  if (cached) return (await cached.json()) as GeocodeResult[];
  if (!(await allowUpstream())) throw new GeocodeRateLimited(normalized);

  const url = new URL(NOMINATIM_BASE_URL);
  url.searchParams.set("q", query);
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("limit", "10");
  url.searchParams.set("viewbox", BELGRADE_VIEWBOX);
  url.searchParams.set("bounded", "1");
  url.searchParams.set("countrycodes", "rs");
  // Latin-script names and the address parts, so the result reads short:
  // "Knez Mihailova 5, Stari grad" instead of the full nine-part OSM line.
  url.searchParams.set("accept-language", "sr-Latn");
  url.searchParams.set("addressdetails", "1");

  const res = await fetch(url, {
    headers: {
      "user-agent": `StiglaApp/0.1 (+${env.NOMINATIM_USER_AGENT_CONTACT}; personal use, low volume)`,
    },
  });
  if (!res.ok) throw new Error(`Nominatim responded ${res.status}`);

  const body = (await res.json()) as Array<{
    display_name: string;
    name?: string;
    lat: string;
    lon: string;
    address?: Record<string, string>;
  }>;
  // The short form collapses several OSM objects of one street to the same text
  // ("Kneza Mihaila, Stari grad" twice): keep the first of each.
  const seen = new Set<string>();
  const results = body
    .map((r) => ({ display_name: shortAddress(r), lat: parseFloat(r.lat), lon: parseFloat(r.lon) }))
    .filter((r) => insideBelgrade(r.lat, r.lon))
    .filter((r) => !seen.has(r.display_name) && seen.add(r.display_name));

  await cache.put(
    cacheKey,
    new Response(JSON.stringify(results), {
      headers: { "content-type": "application/json", "cache-control": `max-age=${CACHE_TTL_SECONDS}` },
    }),
  );
  return results;
}

/** "Place or street + number, district" in Latin script; falls back to the first two parts of the full line. */
export function shortAddress(r: { display_name: string; name?: string; address?: Record<string, string> }): string {
  const a = r.address ?? {};
  const street = a.road ? [a.road, a.house_number].filter(Boolean).join(" ") : undefined;
  const head = r.name && r.name !== a.road ? r.name : street ?? r.name;
  const area = a.suburb ?? a.neighbourhood ?? a.quarter ?? a.city_district ?? a.city ?? a.town ?? a.village;
  const parts = [head, area].filter((p, i, all): p is string => !!p && all.indexOf(p) === i);
  const text = parts.length > 0 ? parts.join(", ") : r.display_name.split(",").slice(0, 2).join(",").trim();
  return toLatin(text);
}
