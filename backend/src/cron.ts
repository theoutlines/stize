import type { Env } from "./env";
import { aggregate } from "./lib/analytics";
import { refreshCitySummary } from "./lib/cityAnalytics";
import { refreshAlerts } from "./lib/alerts";
import { governorDue, readsConstrained, resolveGovernorConfig, runD1Governor } from "./lib/d1Governor";
import { getFlag } from "./lib/featureFlags";
import { journalJams } from "./lib/jamDetector";
import { rebuildConfigBundle } from "./lib/kvCache";
import { runSweepTick } from "./lib/sweep";

// The cron handler (wrangler.toml [triggers]): the per-minute tick (D1 governor,
// config bundle, jam journal, sentinel sweep) and the daily job (alerts,
// analytics roll-up, city summary).
export async function runScheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
  // Two triggers share this handler (see wrangler.toml). The per-minute one
  // drives the sentinel sweep; the daily one refreshes alerts and rolls up
  // analytics. Branch on which cron fired so a minute tick never runs the
  // heavy daily job (and vice-versa).
  if (event.cron === "* * * * *") {
    // D1 write-budget governor: every `config:d1_governor_interval_min` minutes
    // (default every 15 min, incl. 00:00 UTC for the day-rollover restore). KV + one
    // GraphQL read; never touches D1 itself.
    const tickAt = new Date(event.scheduledTime);
    ctx.waitUntil(
      resolveGovernorConfig(env)
        .then((cfg) => (governorDue(tickAt, cfg.intervalMin) ? runD1Governor(env, tickAt) : null))
        .then(
          (r) => r && console.log(`d1 governor: ${r.action} ${r.detail}`),
          (err) => console.error("d1 governor failed", err),
        ),
    );

    // Config bundle: rebuilt from the individual keys once an hour, so a key
    // changed by hand reaches the app within the hour (lib/kvCache.ts).
    if (tickAt.getUTCMinutes() === 0) {
      ctx.waitUntil(
        rebuildConfigBundle(env).then(
          (b) => console.log(`config bundle: ${Object.keys(b).length} keys`),
          (err) => console.error("config bundle rebuild failed", err),
        ),
      );
    }

    // Jam journal: every 5 minutes while jams are shown, record what users see.
    if (tickAt.getUTCMinutes() % 5 === 0) {
      ctx.waitUntil(
        getFlag(env, "jam_detection_show")
          .then((on) => (on ? journalJams(env, tickAt.getTime()) : 0))
          .then(
            (n) => n > 0 && console.log(`jam journal: ${n} active`),
            (err) => console.error("jam journal failed", err),
          ),
      );
    }

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
  // Roll raw observations into per-line metrics (raw is kept; no prune). Deferred
  // (whole run, incl. its catch-up) while the D1 read-budget governor is tripped —
  // the drift guard takes the backlog on the next run.
  ctx.waitUntil(
    readsConstrained(env).then(async (constrained) => {
      if (constrained) {
        console.warn("analytics aggregate deferred: D1 read budget governor tripped");
        return;
      }
      try {
        const r = await aggregate(env);
        console.log(
          `analytics aggregate: ${r.buckets} buckets, window ${r.from}..${r.to}, caughtUp=${r.caughtUp}`,
        );
        // The city page reads one precomputed summary; refresh it right after
        // the aggregate moved (best-effort: the old one stays served).
        await refreshCitySummary(env).catch((err) => console.error("city summary refresh failed", err));
      } catch (err) {
        console.error("analytics aggregate failed", err);
      }
    }),
  );
}
