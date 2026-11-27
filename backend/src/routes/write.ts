import { type Context } from "hono";
import type { Env } from "../env";
import { getFlagMemoized } from "../lib/featureFlags";
import { logProductEvents, sanitizeBatch } from "../lib/productAnalytics";
import { getStopById } from "../lib/gtfsData";
import { RateLimitedError, ValidationError } from "../lib/errors";
import { createFeedback, createFeedbackIssue, stopReportToFeedback } from "../lib/feedback";
import type { App } from "./app";

// Public write routes (product events, stop reports, feedback), each under a per-IP limit.

// Per-IP limit on public write endpoints (WRITE_LIMITER binding). Returns a
// 429 response when over, null otherwise. No binding (tests) = no limit.
async function overWriteLimit(c: Context<{ Bindings: Env }>, scope: string) {
  const limiter = c.env.WRITE_LIMITER;
  if (!limiter) return null;
  const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
  const { success } = await limiter.limit({ key: `${scope}:${ip}` });
  return success ? null : c.json({ error: "too many requests" }, 429);
}

export function writeRoutes(app: App): void {
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
    const limited = await overWriteLimit(c, "events");
    if (limited) return limited;
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

  // Stop data report (a rider flags wrong data at one stop). Same receiver and
  // killswitch as feedback; the stop must exist in our reference data.
  app.post("/api/v1/stops/:id/report", async (c) => {
    c.header("cache-control", "no-store");
    if (!(await getFlagMemoized(c.env, c.executionCtx, "feedback_form"))) {
      return c.json({ error: "feedback form disabled" }, 403);
    }
    const stop = await getStopById(c.env, c.req.param("id"));
    if (!stop) return c.json({ error: "unknown stop" }, 404);
    const body = await c.req
      .json<Record<string, string | undefined>>()
      .catch(() => ({}) as Record<string, string | undefined>);
    const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
    try {
      const { feedback, title } = stopReportToFeedback(stop, {
        stopId: stop.stop_id,
        category: body.category ?? "",
        comment: body.comment,
        honeypot: body.website,
        appVersion: body.app_version,
        platform: body.platform,
        locale: body.locale,
      });
      const row = await createFeedback(c.env, ip, feedback);
      c.executionCtx.waitUntil(
        createFeedbackIssue(c.env, feedback, { title, labels: ["stop-report"] }).catch(
          (err) => console.error("stop report issue create failed", err),
        ),
      );
      return c.json({ id: row.id, created_at: row.created_at }, 201);
    } catch (err) {
      if (err instanceof RateLimitedError) return c.json({ error: err.message }, 429);
      if (err instanceof ValidationError) return c.json({ error: err.message }, 400);
      throw err;
    }
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
}
