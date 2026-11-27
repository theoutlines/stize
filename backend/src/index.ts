import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./env";
import type { App } from "./routes/app";
import { adminTokenOk } from "./lib/errors";
import { runScheduled } from "./cron";
import { transitRoutes } from "./routes/transit";
import { writeRoutes } from "./routes/write";
import { cityRoutes } from "./routes/city";
import { adminRoutes } from "./routes/admin";

const app: App = new Hono<{ Bindings: Env }>();

// Public read-only API consumed directly from the Flutter web build running
// on an arbitrary origin (stize.app, localhost during dev, ...).
// Nothing here is per-user or cookie-authenticated, so a permissive origin is fine.
app.use("*", cors({ origin: "*", allowHeaders: ["Content-Type", "X-Admin-Token", "X-Device-Id"] }));

// Every /admin route: one shared check, compared in constant time (audit
// 2026-11-22, S10). Both sides are hashed first so the comparison runs on equal
// lengths and leaks neither the token nor its length through timing.
app.use("/api/v1/admin/*", async (c, next) => {
  if (!(await adminTokenOk(c.req.header("X-Admin-Token"), c.env.ADMIN_TOKEN))) {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
});

// D1-backed community/analytics routes. An unexpected throw there is almost always
// the store being unavailable — e.g. the account's D1 free-tier daily write limit
// (100k rows_written, account-wide) exhausted, which makes EVERY D1 query error
// until 00:00 UTC (2026-10-05 incident). That is a temporary outage, not a bug in
// the request: answer 503 with a clean JSON error the client can show, never a
// bare 500. Expected errors (validation, rate limit) are still mapped in-route.
const D1_BACKED_PATH = /^\/api\/v1\/(feedback|analytics\/lines)(\/|$)/;

app.onError((err, c) => {
  if (D1_BACKED_PATH.test(c.req.path)) {
    console.error(`store unavailable on ${c.req.method} ${c.req.path}`, err);
    c.header("cache-control", "no-store");
    c.header("retry-after", "300");
    return c.json({ error: "temporarily_unavailable" }, 503);
  }
  console.error(`unhandled error on ${c.req.method} ${c.req.path}`, err);
  return c.text("Internal Server Error", 500);
});

transitRoutes(app);
writeRoutes(app);
cityRoutes(app);
adminRoutes(app);

export default {
  fetch: app.fetch,
  scheduled: runScheduled,
};
