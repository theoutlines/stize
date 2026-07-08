import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import type {
  HealthResponse,
  LinesResponse,
  RouteShapeResponse,
  StopsResponse,
} from "./types";
import { isServiceKilled, setServiceKilled } from "./lib/killswitch";
import { getArrivals } from "./lib/arrivals";
import { getLineByNumber, getRouteShape, nearbyStops, searchLines, searchStops } from "./lib/gtfsData";
import { geocodeSearch } from "./lib/geocode";

const app = new Hono<{ Bindings: Env }>();

// Public read-only API consumed directly from the Flutter web build running
// on an arbitrary origin (stigla.theoutlines.xyz, localhost during dev, ...).
// Nothing here is per-user or cookie-authenticated, so a permissive origin is fine.
app.use("*", cors({ origin: "*", allowHeaders: ["Content-Type", "X-Admin-Token", "X-Device-Id"] }));

app.get("/api/v1/health", async (c) => {
  const killed = await isServiceKilled(c.env);
  const body: HealthResponse = { status: killed ? "killed" : "ok", version: c.env.API_VERSION };
  return c.json(body);
});

app.get("/api/v1/arrivals", async (c) => {
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
    const results = await geocodeSearch(c.env, query);
    return c.json({ results });
  } catch (err) {
    console.error("geocode failed", err);
    return c.json({ results: [] }, 502);
  }
});

app.post("/api/v1/admin/killswitch", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const body = await c.req.json<{ killed?: boolean }>().catch(() => ({ killed: undefined }));
  if (typeof body.killed !== "boolean") {
    return c.json({ error: "body must be { \"killed\": boolean }" }, 400);
  }
  await setServiceKilled(c.env, body.killed);
  return c.json({ status: body.killed ? "killed" : "ok" });
});

export default app;
