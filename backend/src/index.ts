import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import type {
  HealthResponse,
  LinesResponse,
  RouteShapeResponse,
  StopsResponse,
  VehiclesResponse,
} from "./types";
import { isServiceKilled, setServiceKilled } from "./lib/killswitch";
import { getArrivals } from "./lib/arrivals";
import { getNearbyVehicles } from "./lib/vehicles";
import {
  getAllLines,
  getAllStops,
  getLineByNumber,
  getRouteShape,
  nearbyStops,
  searchLines,
  searchStops,
} from "./lib/gtfsData";
import { geocodeSearch } from "./lib/geocode";
import { listAlerts, refreshAlerts } from "./lib/alerts";
import {
  RateLimitedError,
  ValidationError,
  addComment,
  createIdea,
  hideIdea,
  ideaExists,
  listComments,
  listIdeas,
  toggleVote,
} from "./lib/ideas";

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

app.get("/api/v1/ideas", async (c) => {
  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) return c.json({ error: "missing X-Device-Id header" }, 400);
  const ideas = await listIdeas(c.env, deviceId);
  return c.json({ ideas });
});

app.post("/api/v1/ideas", async (c) => {
  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) return c.json({ error: "missing X-Device-Id header" }, 400);
  const body = await c.req.json<{ text?: string }>().catch(() => ({ text: undefined }));
  if (typeof body.text !== "string") return c.json({ error: "body must be { \"text\": string }" }, 400);

  try {
    const idea = await createIdea(c.env, deviceId, body.text);
    return c.json(idea, 201);
  } catch (err) {
    if (err instanceof RateLimitedError) return c.json({ error: err.message }, 429);
    if (err instanceof ValidationError) return c.json({ error: err.message }, 400);
    throw err;
  }
});

app.post("/api/v1/ideas/:id/vote", async (c) => {
  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) return c.json({ error: "missing X-Device-Id header" }, 400);
  const ideaId = Number(c.req.param("id"));
  if (!Number.isInteger(ideaId)) return c.json({ error: "invalid idea id" }, 400);
  if (!(await ideaExists(c.env, ideaId))) return c.json({ error: "unknown idea" }, 404);

  const result = await toggleVote(c.env, ideaId, deviceId);
  return c.json(result);
});

app.get("/api/v1/ideas/:id/comments", async (c) => {
  const ideaId = Number(c.req.param("id"));
  if (!Number.isInteger(ideaId)) return c.json({ error: "invalid idea id" }, 400);
  if (!(await ideaExists(c.env, ideaId))) return c.json({ error: "unknown idea" }, 404);

  const comments = await listComments(c.env, ideaId);
  return c.json({ comments });
});

app.post("/api/v1/ideas/:id/comments", async (c) => {
  const deviceId = c.req.header("X-Device-Id");
  if (!deviceId) return c.json({ error: "missing X-Device-Id header" }, 400);
  const ideaId = Number(c.req.param("id"));
  if (!Number.isInteger(ideaId)) return c.json({ error: "invalid idea id" }, 400);
  if (!(await ideaExists(c.env, ideaId))) return c.json({ error: "unknown idea" }, 404);

  const body = await c.req.json<{ text?: string }>().catch(() => ({ text: undefined }));
  if (typeof body.text !== "string") return c.json({ error: "body must be { \"text\": string }" }, 400);

  try {
    const comment = await addComment(c.env, ideaId, deviceId, body.text);
    return c.json(comment, 201);
  } catch (err) {
    if (err instanceof ValidationError) return c.json({ error: err.message }, 400);
    throw err;
  }
});

app.post("/api/v1/admin/ideas/:id/hide", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const ideaId = Number(c.req.param("id"));
  if (!Number.isInteger(ideaId)) return c.json({ error: "invalid idea id" }, 400);
  if (!(await ideaExists(c.env, ideaId))) return c.json({ error: "unknown idea" }, 404);

  await hideIdea(c.env, ideaId);
  return c.json({ status: "hidden" });
});

// Contextual route-change alerts (experimental). Refreshed by a cron trigger
// (see `scheduled` handler below), not on the request path — this endpoint
// just serves whatever's currently cached in KV.
app.get("/api/v1/alerts", async (c) => {
  const alerts = await listAlerts(c.env);
  return c.json({ alerts });
});

app.post("/api/v1/admin/alerts/refresh", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const result = await refreshAlerts(c.env);
  return c.json(result);
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

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(
      refreshAlerts(env).then(
        (result) => console.log(`alerts refresh: +${result.added}, total ${result.total}`),
        (err) => console.error("alerts refresh failed", err),
      ),
    );
  },
};
