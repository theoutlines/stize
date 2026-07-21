import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import type {
  ConfigResponse,
  HealthResponse,
  LinesResponse,
  NearbyArrivalsResponse,
  RouteShapeResponse,
  StopsResponse,
  VehiclesResponse,
} from "./types";
import { isServiceKilled, setServiceKilled } from "./lib/killswitch";
import { FEATURE_FLAGS, getAllFlags, getFlagMemoized, isFeatureFlag, setFlag } from "./lib/featureFlags";
import { aggregate, getLineAnalytics } from "./lib/analytics";
import { runSweepTick, sweepStatus } from "./lib/sweep";
import { logProductEvents, sanitizeBatch } from "./lib/productAnalytics";
import { getArrivals } from "./lib/arrivals";
import { getNearbyVehicles } from "./lib/vehicles";
import { getNearbyArrivals } from "./lib/nearbyArrivals";
import {
  getAllLines,
  getAllStops,
  getFeedMeta,
  getLineByNumber,
  getRouteShape,
  nearbyStops,
  searchLines,
  searchStops,
} from "./lib/gtfsData";
import { geocodeSearch } from "./lib/geocode";
import { listAlerts, refreshAlerts } from "./lib/alerts";
import { computeJams, pruneVehicleFixes, type JamsResponse } from "./lib/jamDetector";
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
import { createFeedback, createFeedbackIssue } from "./lib/feedback";

// KV key for the drawer's optional Donate link. Empty/unset ⇒ the client hides
// the Donate item; set it (dashboard/wrangler) to reveal it. See feature-flags.md.
const DONATE_URL_KV_KEY = "config:donate_url";

const app = new Hono<{ Bindings: Env }>();

// Public read-only API consumed directly from the Flutter web build running
// on an arbitrary origin (stize.app, legacy stigla.theoutlines.xyz, localhost
// during dev, ...).
// Nothing here is per-user or cookie-authenticated, so a permissive origin is fine.
app.use("*", cors({ origin: "*", allowHeaders: ["Content-Type", "X-Admin-Token", "X-Device-Id"] }));

app.get("/api/v1/health", async (c) => {
  const killed = await isServiceKilled(c.env);
  const body: HealthResponse = { status: killed ? "killed" : "ok", version: c.env.API_VERSION };
  return c.json(body);
});

// Runtime config + feature flags the app reads at startup. no-store so a remote
// flag flip (via /admin/flags) reaches clients on their next fetch, no rebuild.
app.get("/api/v1/config", async (c) => {
  const config: Record<string, string> = {};
  const donateUrl = (await c.env.STIGLA_KV.get(DONATE_URL_KV_KEY))?.trim();
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

// Tram-jam ("stalled segment") detection. Reads the last-fix table the arrivals
// refresh maintains and returns the current jam set + bus substitutions. Inert
// (empty) unless `jam_detection_show` is on — the client gates its polling on the
// same flag, so with it off nothing is computed and nothing is drawn.
//
// Live positions — never cache (same zone Browser-Cache-TTL gotcha as /arrivals).
app.get("/api/v1/jams", async (c) => {
  c.header("cache-control", "no-store");
  const empty: JamsResponse = {
    feed_healthy: true,
    jams: [],
    substitutions: [],
    updated_at: new Date().toISOString(),
  };
  if (!(await getFlagMemoized(c.env, c.executionCtx, "jam_detection_show"))) return c.json(empty);
  if (await isServiceKilled(c.env)) return c.json(empty);
  try {
    const now = Date.now();
    // Staging-only synthetic jam so a stand can be verified without a live jam:
    // ?sim=<line> (or KV `jam:sim`) injects a jam on a real tram line+direction.
    let simLine: string | null = null;
    if (c.env.ENVIRONMENT === "staging") {
      simLine = c.req.query("sim") ?? (await c.env.STIGLA_KV.get("jam:sim"));
    }
    const body = await computeJams(c.env, now, { simLine });
    c.executionCtx.waitUntil(pruneVehicleFixes(c.env, now).catch(() => {}));
    return c.json(body);
  } catch (err) {
    console.error("jams compute failed", err);
    return c.json(empty);
  }
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

// Flip a feature flag remotely (no redeploy). Same admin-token auth as above.
//   curl -X POST .../api/v1/admin/flags -H "X-Admin-Token: $T" \
//        -d '{"flag":"analytics_collect","value":true}'
app.post("/api/v1/admin/flags", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const body = await c.req
    .json<{ flag?: string; value?: boolean }>()
    .catch(() => ({ flag: undefined, value: undefined }));
  if (!body.flag || !isFeatureFlag(body.flag) || typeof body.value !== "boolean") {
    return c.json(
      { error: `body must be { "flag": one of [${FEATURE_FLAGS.join(", ")}], "value": boolean }` },
      400,
    );
  }
  await setFlag(c.env, body.flag, body.value);
  return c.json({ flags: await getAllFlags(c.env) });
});

// Product analytics: anonymous, batched usage events from the client. Own
// contour (no external vendor) — the worker writes them to product_events. This
// is deliberately cheap and fire-and-forget: sanitize the batch synchronously
// (drop unknown events, strip non-enum props, cap the size), hand the write to
// waitUntil, and answer immediately. Nothing here can add latency to, or fail,
// the client. No auth: the payload is anonymous enums, same trust model as the
// other public read/write endpoints.
//
// The endpoint MIRRORS the `product_analytics` flag: with it OFF it collects
// nothing and says so with 204 No Content — no body parse, no write. The client
// already sends nothing when the flag is off (config-gated); this makes the gate
// observable and harmlessly absorbs a stale client that still posts. The flag
// read is memoized on the request ctx, so the ON path's logProductEvents reuses
// it — one KV read per request.
app.post("/api/v1/events", async (c) => {
  c.header("cache-control", "no-store");
  if (!(await getFlagMemoized(c.env, c.executionCtx, "product_analytics"))) {
    return c.body(null, 204);
  }
  const body = await c.req
    .json<{ events?: unknown }>()
    .catch(() => ({ events: undefined }));
  const events = sanitizeBatch(body.events);
  if (events.length > 0) {
    c.executionCtx.waitUntil(
      logProductEvents(c.env, c.executionCtx, events).catch((err) =>
        console.error("product events log failed", err),
      ),
    );
  }
  return c.json({ accepted: events.length }, 202);
});

// In-app feedback (drawer footer). D1 is the durable primary store; a GitHub
// issue is created best-effort on top for triage (see createFeedbackIssue).
// Gated by the `feedback_form` flag — OFF makes it a full killswitch (the client
// hides the form, and a stale client that still posts gets 403). Abuse guards
// live in createFeedback: per-IP rate limit, message length cap, honeypot. The
// contact email is never exposed; replies happen out-of-band via the issue.
app.post("/api/v1/feedback", async (c) => {
  c.header("cache-control", "no-store");
  if (!(await getFlagMemoized(c.env, c.executionCtx, "feedback_form"))) {
    return c.json({ error: "feedback form disabled" }, 403);
  }
  const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
  const body = await c.req
    .json<{
      message?: string;
      contact?: string;
      website?: string; // honeypot
      app_version?: string;
      platform?: string;
      locale?: string;
    }>()
    .catch(() => ({}) as {
      message?: string;
      contact?: string;
      website?: string;
      app_version?: string;
      platform?: string;
      locale?: string;
    });

  const input = {
    message: body.message ?? "",
    contact: body.contact,
    honeypot: body.website,
    appVersion: body.app_version,
    platform: body.platform,
    locale: body.locale,
  };

  try {
    const row = await createFeedback(c.env, ip, input);
    // Store succeeded → best-effort GitHub triage issue. A failure here is
    // logged and swallowed: the durable D1 row already exists, so the caller
    // still got a 201 and nothing is lost.
    c.executionCtx.waitUntil(
      createFeedbackIssue(c.env, input).catch((err) =>
        console.error("feedback issue create failed", err),
      ),
    );
    return c.json({ id: row.id, created_at: row.created_at }, 201);
  } catch (err) {
    if (err instanceof RateLimitedError) return c.json({ error: err.message }, 429);
    if (err instanceof ValidationError) return c.json({ error: err.message }, 400);
    throw err;
  }
});

// Transport analytics: rolled-up metrics for one line, served from the
// pre-aggregated table (fast; no raw scan on the request path). Behind the
// `analytics_show` flag on the client — the endpoint itself is harmless/empty
// until history accumulates.
app.get("/api/v1/analytics/lines/:line", async (c) => {
  const line = c.req.param("line");
  const data = await getLineAnalytics(c.env, line);
  return c.json(data);
});

// Run the aggregation on demand (same as the daily cron) — for testing.
app.post("/api/v1/admin/analytics/aggregate", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  const result = await aggregate(c.env);
  return c.json(result);
});

// Run one sentinel-sweep tick on demand (same as the per-minute cron). Staging
// has no cron, so this is how the sweep is exercised there while verifying —
// remember staging ALSO reaches the source, so enable `analytics_sweep` on
// staging only for the duration of a check.
app.post("/api/v1/admin/sweep/tick", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  // No jitter on the manual path — a staging check should return promptly, not
  // sleep up to ~2×jitter seconds like the cron tick does.
  const result = await runSweepTick(c.env, c.executionCtx, new Date(), { applyJitter: false });
  return c.json(result);
});

// Read-out of the request budget + degradation breaker: current req/hr (live vs
// sweep), remaining sweep budget, and breaker health — so it can be checked
// WITHOUT `wrangler tail`. Admin-token gated (metrics are operational, not public).
// Contains NO secrets/tokens — only counts, config values, and derived metrics.
app.get("/api/v1/admin/sweep/status", async (c) => {
  const token = c.req.header("X-Admin-Token");
  if (!token || token !== c.env.ADMIN_TOKEN) {
    return c.json({ error: "unauthorized" }, 401);
  }
  c.header("cache-control", "no-store");
  return c.json(await sweepStatus(c.env));
});

export default {
  fetch: app.fetch,
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    // Two triggers share this handler (see wrangler.toml). The per-minute one
    // drives the sentinel sweep; the daily one refreshes alerts and rolls up
    // analytics. Branch on which cron fired so a minute tick never runs the
    // heavy daily job (and vice-versa).
    if (event.cron === "* * * * *") {
      // Cron path applies jitter (randomized 0..2×jitter-s pre-fetch delay) so the
      // upstream hit doesn't land on a fixed phase every minute.
      ctx.waitUntil(
        runSweepTick(env, ctx, new Date(), { applyJitter: true }).then(
          (r) => {
            // One greppable line per tick: reason + counts + the budget/breaker
            // numbers behind the decision (no secrets). Logged even on a no-op so a
            // "budget-exhausted" / "degradation-breaker" stand-down is visible.
            const m = r.meter
              ? ` live_hr=${r.meter.liveHr} sweep_hr=${r.meter.sweepHr}` +
                ` sweep_ceiling=${r.meter.sweepCeiling} p95=${r.meter.p95LatencyMs ?? "-"}ms` +
                ` nonjson=${(r.meter.nonJsonFraction * 100).toFixed(0)}% samples=${r.meter.samples}`
              : "";
            console.log(
              `sweep: ${r.reason} swept=${r.swept.length} skipped=${r.skipped}` +
                ` fail=${r.failures} jitter=${r.jitterMs ?? 0}ms${m}`,
            );
          },
          (err) => console.error("sweep tick failed", err),
        ),
      );
      return;
    }

    ctx.waitUntil(
      refreshAlerts(env).then(
        (result) => console.log(`alerts refresh: +${result.added}, total ${result.total}`),
        (err) => console.error("alerts refresh failed", err),
      ),
    );
    // Roll raw observations into per-line metrics and prune old raw.
    ctx.waitUntil(
      aggregate(env).then(
        (r) =>
          console.log(
            `analytics aggregate: ${r.buckets} buckets, window ${r.from}..${r.to}, caughtUp=${r.caughtUp}`,
          ),
        (err) => console.error("analytics aggregate failed", err),
      ),
    );
  },
};
