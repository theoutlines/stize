import { isServiceKilled } from "../lib/killswitch";
import { getFlagMemoized } from "../lib/featureFlags";
import { getLineAnalytics } from "../lib/analytics";
import { getCitySummary } from "../lib/cityAnalytics";
import { listAlerts } from "../lib/alerts";
import { computeJams, type JamsResponse } from "../lib/jamDetector";
import { readsConstrained } from "../lib/d1Governor";
import type { App } from "./app";

// Alerts, jams and the analytics read routes.

export function cityRoutes(app: App): void {
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
      return c.json(body);
    } catch (err) {
      console.error("jams compute failed", err);
      return c.json(empty);
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

  // City section: one precomputed summary for the whole city (grid by local
  // weekday × hour, per-line rollups, totals). Read from KV; recomputed after the
  // daily aggregate, and once on a cold miss unless D1 reads are constrained.
  app.get("/api/v1/analytics/city", async (c) => {
    const data = await getCitySummary(c.env, !(await readsConstrained(c.env)));
    c.header("Cache-Control", "public, max-age=900");
    return c.json(data);
  });
}
