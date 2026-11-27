import { setServiceKilled } from "../lib/killswitch";
import { FEATURE_FLAGS, getAllFlags, isFeatureFlag, setFlag } from "../lib/featureFlags";
import { aggregate } from "../lib/analytics";
import { runSweepTick, sweepStatus } from "../lib/sweep";
import { refreshAlerts } from "../lib/alerts";
import { computeJams } from "../lib/jamDetector";
import { fetchUsageToday, forgetGovernedFlag, readGovernorState, readsConstrained, resolveGovernorConfig, runD1Governor } from "../lib/d1Governor";
import { rebuildConfigBundle } from "../lib/kvCache";
import type { App } from "./app";

// Admin routes; the X-Admin-Token check is in index.ts.

export function adminRoutes(app: App): void {
  // Jams: what the detector sees right now (regardless of the show flag) plus the
  // journal of jams shown in the last 7 days. The calibration view.
  app.get("/api/v1/admin/jams", async (c) => {
    const now = Date.now();
    const live = await computeJams(c.env, now);
    const since = new Date(now - 7 * 86400_000).toISOString().slice(0, 10);
    const { results } = await c.env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT * FROM jam_journal WHERE day >= ? ORDER BY day DESC, first_at DESC",
    )
      .bind(since)
      .all();
    return c.json({ live, journal: results });
  });

  app.post("/api/v1/admin/alerts/refresh", async (c) => {
    const result = await refreshAlerts(c.env);
    return c.json(result);
  });

  app.post("/api/v1/admin/killswitch", async (c) => {
    const body = await c.req.json<{ killed?: boolean }>().catch(() => ({ killed: undefined }));
    if (typeof body.killed !== "boolean") {
      return c.json({ error: "body must be { \"killed\": boolean }" }, 400);
    }
    await setServiceKilled(c.env, body.killed);
    return c.json({ status: body.killed ? "killed" : "ok" });
  });

  // Rebuild the config bundle (lib/kvCache.ts) from the individual KV keys at
  // once, after a key was changed by hand in the dashboard or with `wrangler kv
  // key put` (otherwise the hourly cron picks it up).
  //   curl -X POST .../api/v1/admin/config/rebuild -H "X-Admin-Token: $T"
  app.post("/api/v1/admin/config/rebuild", async (c) => {
    const bundle = await rebuildConfigBundle(c.env);
    return c.json({ keys: Object.keys(bundle).length });
  });

  // Flip a feature flag remotely (no redeploy). Same admin-token auth as above.
  //   curl -X POST .../api/v1/admin/flags -H "X-Admin-Token: $T" \
  //        -d '{"flag":"analytics_collect","value":true}'
  app.post("/api/v1/admin/flags", async (c) => {
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
    // A human decision on a flag the D1 budget governor is holding OFF overrides it:
    // the governor won't restore (or re-trip) that flag for the current day.
    await forgetGovernedFlag(c.env, body.flag);
    return c.json({ flags: await getAllFlags(c.env) });
  });

  // Run the aggregation on demand (same as the daily cron) — for testing.
  app.post("/api/v1/admin/analytics/aggregate", async (c) => {
    if (await readsConstrained(c.env)) {
      return c.json({ error: "deferred: D1 read budget governor tripped; retry after 00:00 UTC" }, 503);
    }
    const result = await aggregate(c.env);
    return c.json(result);
  });

  // Run one sentinel-sweep tick on demand (same as the per-minute cron). Staging
  // has no cron, so this is how the sweep is exercised there while verifying —
  // remember staging ALSO reaches the source, so enable `analytics_sweep` on
  // staging only for the duration of a check.
  app.post("/api/v1/admin/sweep/tick", async (c) => {
    // No jitter on the manual path — a staging check should return promptly, not
    // sleep up to ~2×jitter seconds like the cron tick does.
    const result = await runSweepTick(c.env, c.executionCtx, new Date(), { applyJitter: false });
    return c.json(result);
  });

  // Read-out of the request budget + degradation breaker: current req/hr (live vs
  // sweep), remaining sweep budget, and breaker health — so it can be checked
  // WITHOUT `wrangler tail`. Admin-token gated (metrics are operational, not public).
  // Contains NO secrets/tokens — only counts, config values, and derived metrics.
  // Applied D1 migrations per bound database, to compare with the repo's
  // migrations folders (scripts/check-migrations.mjs). Migrations are applied by
  // hand, so this is the drift check (audit round 2, T2).
  app.get("/api/v1/admin/migrations", async (c) => {
    const read = async (db: D1Database | undefined) => {
      if (!db) return null;
      const { results } = await db.prepare("SELECT name FROM d1_migrations ORDER BY id").all<{ name: string }>();
      return results.map((r) => r.name);
    };
    return c.json({
      ideas: await read(c.env.STIGLA_IDEAS_DB),
      analytics: await read(c.env.STIGLA_ANALYTICS_DB),
    });
  });

  app.get("/api/v1/admin/sweep/status", async (c) => {
    c.header("cache-control", "no-store");
    // Non-essential read: stood down while the D1 read-budget governor is tripped
    // (answers from KV only — use /admin/d1-budget for the budget read-out).
    if (await readsConstrained(c.env)) {
      return c.json({ error: "stood down: D1 read budget governor tripped until 00:00 UTC" }, 503);
    }
    return c.json(await sweepStatus(c.env));
  });

  // D1 budget governor read-out (see lib/d1Governor.ts): config, today's account-wide
  // rows_written + rows_read (GraphQL — costs no D1 rows), and the governor state.
  // Admin-token gated; no secrets in the response.
  app.get("/api/v1/admin/d1-budget", async (c) => {
    c.header("cache-control", "no-store");
    const now = new Date();
    const [config, state] = await Promise.all([resolveGovernorConfig(c.env), readGovernorState(c.env)]);
    let usage: { rowsWritten: number; rowsRead: number } | null = null;
    let usageError: string | null = null;
    try {
      usage = await fetchUsageToday(c.env, now);
    } catch (e) {
      usageError = String(e);
    }
    const pct = (v: number, limit: number) => Math.round((v / limit) * 1000) / 10;
    return c.json({
      now: now.toISOString(),
      config,
      threshold_rows: (config.dailyLimit * config.thresholdPct) / 100,
      threshold_rows_read: (config.dailyReadLimit * config.readThresholdPct) / 100,
      rows_written_today: usage?.rowsWritten ?? null,
      used_pct: usage ? pct(usage.rowsWritten, config.dailyLimit) : null,
      rows_read_today: usage?.rowsRead ?? null,
      read_used_pct: usage ? pct(usage.rowsRead, config.dailyReadLimit) : null,
      usage_error: usageError,
      governor_state: state,
    });
  });

  // Run one governor pass on demand (the cron does this every interval). Staging has
  // no cron, so this is how the governor is exercised there. NOTE: the reading is
  // account-wide; on staging it flips only staging's own KV flags.
  app.post("/api/v1/admin/d1-budget/tick", async (c) => {
    return c.json(await runD1Governor(c.env, new Date()));
  });
}
