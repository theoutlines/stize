import type { ConfigResponse, HealthResponse, LinesResponse, NearbyArrivalsResponse, RouteShapeResponse, StopsResponse, VehiclesResponse } from "../types";
import { isServiceKilled } from "../lib/killswitch";
import { getAllFlags } from "../lib/featureFlags";
import { getArrivals } from "../lib/arrivals";
import { getNearbyVehicles } from "../lib/vehicles";
import { getNearbyArrivals } from "../lib/nearbyArrivals";
import { getAllLines, getAllStops, getFeedMeta, getLineByNumber, getRouteShape, nearbyStops, searchLines, searchStops } from "../lib/gtfsData";
import { GeocodeRateLimited, geocodeSearch } from "../lib/geocode";
import { kvGetCached } from "../lib/kvCache";
import type { App } from "./app";

// Read-only transit routes: config, stops, lines, arrivals, vehicles, coverage, geocode.

// KV key for the drawer's optional Donate link. Empty/unset ⇒ the client hides
// the Donate item; set it (dashboard/wrangler) to reveal it. See the internal flag registry.
const DONATE_URL_KV_KEY = "config:donate_url";

export function transitRoutes(app: App): void {
  app.get("/api/v1/health", async (c) => {
    const killed = await isServiceKilled(c.env);
    const body: HealthResponse = { status: killed ? "killed" : "ok", version: c.env.API_VERSION };
    return c.json(body);
  });

  // Runtime config + feature flags the app reads at startup. no-store so a remote
  // flag flip (via /admin/flags) reaches clients on their next fetch, no rebuild.
  app.get("/api/v1/config", async (c) => {
    const config: Record<string, string> = {};
    const donateUrl = (await kvGetCached(c.env, DONATE_URL_KV_KEY))?.trim();
    if (donateUrl) config.donate_url = donateUrl;

    const body: ConfigResponse = {
      version: c.env.API_VERSION,
      environment: c.env.ENVIRONMENT ?? "production",
      flags: await getAllFlags(c.env),
      config,
    };
    c.header("cache-control", "no-store");
    return c.json(body);
  });

  // GTFS bundle freshness metadata (feed version + validity dates). An explicit
  // Hono route so it gets CORS headers — the static-asset binding that serves
  // /gtfs/*.json bypasses the cors() middleware. 404 if the bundle predates
  // feed_meta.json (client degrades silently).
  app.get("/api/v1/gtfs-meta", async (c) => {
    const meta = await getFeedMeta(c.env);
    if (!meta) return c.json({ error: "no feed metadata" }, 404);
    return c.json(meta);
  });

  app.get("/api/v1/arrivals", async (c) => {
    // Live board — never cache. Without this the zone's Browser Cache TTL serves
    // the browser a stale board on the client's 30s poll, so it only refreshed on
    // a hard reload. no-store, like /config.
    c.header("cache-control", "no-store");
    const stopId = c.req.query("stop");
    if (!stopId) return c.json({ error: "missing 'stop' query param" }, 400);

    if (await isServiceKilled(c.env)) {
      return c.json({
        stop_id: stopId,
        stop_name: "",
        updated_at: new Date().toISOString(),
        arrivals: [],
        service_status: "unavailable",
      });
    }

    try {
      const result = await getArrivals(c.env, c.executionCtx, stopId);
      if (!result) return c.json({ error: "unknown stop_id" }, 404);
      return c.json(result);
    } catch (err) {
      console.error("arrivals fetch failed", err);
      return c.json({
        stop_id: stopId,
        stop_name: "",
        updated_at: new Date().toISOString(),
        arrivals: [],
        service_status: "unavailable",
      });
    }
  });

  app.get("/api/v1/stops", async (c) => {
    const query = c.req.query("query") ?? "";
    const stops = await searchStops(c.env, query);
    const body: StopsResponse = { stops };
    return c.json(body);
  });

  // Full dumps for the client's on-device offline reference cache (rebuilt
  // on redeploy only, so aggressive caching downstream is safe).
  app.get("/api/v1/stops/all", async (c) => {
    const stops = await getAllStops(c.env);
    c.header("cache-control", "public, max-age=3600");
    const body: StopsResponse = { stops };
    return c.json(body);
  });

  app.get("/api/v1/lines/all", async (c) => {
    const lines = await getAllLines(c.env);
    c.header("cache-control", "public, max-age=3600");
    const body: LinesResponse = { lines };
    return c.json(body);
  });

  app.get("/api/v1/stops/nearby", async (c) => {
    const lat = parseFloat(c.req.query("lat") ?? "");
    const lon = parseFloat(c.req.query("lon") ?? "");
    const radius = parseFloat(c.req.query("radius") ?? "500");
    if (Number.isNaN(lat) || Number.isNaN(lon)) {
      return c.json({ error: "missing/invalid 'lat'/'lon' query params" }, 400);
    }
    const stops = await nearbyStops(c.env, lat, lon, Number.isNaN(radius) ? 500 : radius);
    const body: StopsResponse = { stops };
    return c.json(body);
  });

  // Live vehicles physically inside the given area, for the map's "see transport
  // right away" view. Reconstructed from per-stop arrivals (see getNearbyVehicles)
  // with the fan-out bounded and rate-limited by the shared per-stop cache.
  app.get("/api/v1/vehicles/nearby", async (c) => {
    // Live positions — never cache (same zone Browser Cache TTL gotcha as
    // /arrivals). Otherwise the 30s poll is served stale from the browser
    // HTTP cache and only a hard reload updates the map.
    c.header("cache-control", "no-store");
    const lat = parseFloat(c.req.query("lat") ?? "");
    const lon = parseFloat(c.req.query("lon") ?? "");
    const radius = parseFloat(c.req.query("radius") ?? "800");
    if (Number.isNaN(lat) || Number.isNaN(lon)) {
      return c.json({ error: "missing/invalid 'lat'/'lon' query params" }, 400);
    }
    const empty: VehiclesResponse = { vehicles: [], updated_at: new Date().toISOString() };
    if (await isServiceKilled(c.env)) return c.json(empty);
    try {
      const body = await getNearbyVehicles(
        c.env,
        c.executionCtx,
        lat,
        lon,
        Number.isNaN(radius) ? 800 : radius,
      );
      return c.json(body);
    } catch (err) {
      console.error("vehicles fetch failed", err);
      return c.json(empty);
    }
  });

  // Lines you can catch from around a point, grouped by line + direction with the
  // soonest departures at the nearest serving stop — the "Nearby" list. Same
  // bounded, cache-rate-limited fan-out as /vehicles/nearby (see getNearbyArrivals).
  app.get("/api/v1/arrivals/nearby", async (c) => {
    const lat = parseFloat(c.req.query("lat") ?? "");
    const lon = parseFloat(c.req.query("lon") ?? "");
    const radius = parseFloat(c.req.query("radius") ?? "500");
    if (Number.isNaN(lat) || Number.isNaN(lon)) {
      return c.json({ error: "missing/invalid 'lat'/'lon' query params" }, 400);
    }
    const emptyKilled: NearbyArrivalsResponse = {
      groups: [],
      updated_at: new Date().toISOString(),
      service_status: "unavailable",
    };
    if (await isServiceKilled(c.env)) return c.json(emptyKilled);
    // Staging-only measurement knob: sweep how many nearest stops inherit the
    // schedule fallback to find the per-invocation 503 boundary at a dense point
    // (see NEARBY_SCHEDULE_STOPS). Ignored on prod, which always uses the default.
    let scheduleStops: number | undefined;
    if (c.env.ENVIRONMENT === "staging") {
      const raw = parseInt(c.req.query("schedule_stops") ?? "", 10);
      if (!Number.isNaN(raw)) scheduleStops = Math.max(0, Math.min(8, raw));
    }
    try {
      const body = await getNearbyArrivals(
        c.env,
        c.executionCtx,
        lat,
        lon,
        Number.isNaN(radius) ? 500 : radius,
        scheduleStops,
      );
      return c.json(body);
    } catch (err) {
      console.error("nearby arrivals fetch failed", err);
      return c.json({
        groups: [],
        updated_at: new Date().toISOString(),
        service_status: "unavailable",
      } satisfies NearbyArrivalsResponse);
    }
  });

  app.get("/api/v1/lines", async (c) => {
    const query = c.req.query("query") ?? "";
    const lines = await searchLines(c.env, query);
    const body: LinesResponse = { lines };
    return c.json(body);
  });

  app.get("/api/v1/lines/:routeId/shape", async (c) => {
    const routeId = c.req.param("routeId");
    const shape = await getRouteShape(c.env, routeId);
    if (!shape) return c.json({ error: "unknown route_id" }, 404);
    const body: RouteShapeResponse = shape;
    return c.json(body);
  });

  // Coverage-map *render* layer: the raw route shapes (build-coverage-lines.mjs →
  // public/gtfs/coverage.geojson). Served through an explicit Hono route so it
  // gets the CORS headers the web build needs cross-origin — the raw /gtfs/*
  // static-asset path bypasses the cors() middleware.
  //
  // Cache: a short shared (edge) TTL so a redeploy of the data reflects within a
  // minute, with a longer browser TTL since the file only changes on redeploy.
  // The client also appends a `?rev=` cache-buster it bumps on data-model changes,
  // which sidesteps any longer-lived edge entry from a previous version.
  app.get("/api/v1/coverage", async (c) => {
    const res = await c.env.ASSETS.fetch(new URL("/gtfs/coverage.geojson", "https://assets.internal"));
    if (!res.ok) return c.json({ error: "coverage data unavailable" }, 404);
    return c.newResponse(res.body, 200, {
      "content-type": "application/json",
      "cache-control": "public, max-age=3600, s-maxage=60",
    });
  });

  // Coverage mode's flow lines (build-coverage-flow.mjs → coverage-flow.geojson):
  // per-type corridors carrying weekday `trips`. Same serving rules as
  // /api/v1/coverage above.
  app.get("/api/v1/coverage/flow", async (c) => {
    const res = await c.env.ASSETS.fetch(new URL("/gtfs/coverage-flow.geojson", "https://assets.internal"));
    if (!res.ok) return c.json({ error: "coverage data unavailable" }, 404);
    return c.newResponse(res.body, 200, {
      "content-type": "application/json",
      "cache-control": "public, max-age=3600, s-maxage=60",
    });
  });

  // Convenience alias: look a line up by its number directly (e.g. "79", "7L").
  app.get("/api/v1/lines/by-number/:line/shape", async (c) => {
    const line = c.req.param("line");
    const lineMeta = await getLineByNumber(c.env, line);
    if (!lineMeta) return c.json({ error: "unknown line" }, 404);
    const shape = await getRouteShape(c.env, lineMeta.route_id);
    if (!shape) return c.json({ error: "unknown route_id" }, 404);
    return c.json(shape satisfies RouteShapeResponse);
  });

  app.get("/api/v1/geocode", async (c) => {
    const query = c.req.query("query") ?? "";
    if (!query.trim()) return c.json({ results: [] });
    try {
      // Nominatim's usage policy is about 1 request/second in total; guard it per
      // IP and globally, but only when the answer isn't cached already.
      const results = await geocodeSearch(c.env, query, async () => {
        const lim = c.env.GEOCODE_LIMITER;
        if (!lim) return true;
        const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
        const [mine, all] = await Promise.all([
          lim.limit({ key: `ip:${ip}` }),
          lim.limit({ key: "all" }),
        ]);
        return mine.success && all.success;
      });
      return c.json({ results });
    } catch (err) {
      if (err instanceof GeocodeRateLimited) return c.json({ results: [] }, 429);
      console.error("geocode failed", err);
      return c.json({ results: [] }, 502);
    }
  });
}
