import type { Env } from "../env";
import { getFlag, setFlag, type FeatureFlag } from "./featureFlags";

// ---------------------------------------------------------------------------
// D1 write-budget governor.
//
// The account lives on the D1 free tier permanently: 100k rows_written per UTC day,
// ACCOUNT-WIDE (prod + staging, analytics + ideas). Exceeding it makes every D1
// query in the account fail until 00:00 UTC — including the community features
// (ideas, feedback) that must never lose D1 to analytics (2026-10-05 incident:
// one long map session burned the day's budget by early afternoon).
//
// The same holds for READS: 5M rows_read per UTC day, account-wide; past it D1
// refuses reads too (2026-10-05: ad-hoc diagnostics alone reached 93%).
//
// So, periodically (on the minute cron, every `config:d1_governor_interval_min`
// minutes, default 15), read today's account-wide rows_written AND rows_read from
// the Cloudflare GraphQL Analytics API (which itself costs no D1 rows). Each metric
// has its own limit + threshold in KV (writes: 70% of 100k, reads: 70% of 5M).
// When EITHER crosses its threshold, switch the analytics WRITERS off —
// `analytics_collect` (raw observations) and `jam_detection_collect` (last-fix
// table) — until the UTC day rolls over, then switch back on ONLY the flags the
// governor itself turned off. A READS trip additionally stands down the
// non-essential readers for the rest of the day (`readsConstrained`): the
// aggregator run (incl. its catch-up) is deferred and the admin status read-out
// answers without touching D1. With collection off the sweep stands down too.
//
// Human intent wins:
//   • a flag that was already OFF when the governor tripped is not in its list,
//     so it is never turned on by the restore;
//   • a manual flip of a governed flag via /admin/flags removes it from the list
//     (`forgetGovernedFlag`), so a deliberate human OFF survives the reset and a
//     deliberate human ON is not re-tripped the same day.
// Each metric trips at most once per UTC day.
//
// Fail-safe: no token, an API error, or an unparseable answer → log and do
// nothing (never flip flags on missing data). State lives in KV (a handful of
// writes per day), never in D1 — it must keep working when D1 is the thing that's
// out of budget.
//
// Secrets: CF_ANALYTICS_API_TOKEN (Account Analytics: Read — read-only) and
// CF_ACCOUNT_ID. Thresholds are KV config, not hardcoded.
// ---------------------------------------------------------------------------

export const GOVERNED_FLAGS: readonly FeatureFlag[] = ["analytics_collect", "jam_detection_collect"];

const KV_STATE = "d1_governor:state";
const KV_THRESHOLD_PCT = "config:d1_governor_threshold_pct";
const KV_DAILY_LIMIT = "config:d1_daily_rows_written_limit";
const KV_READ_THRESHOLD_PCT = "config:d1_governor_read_threshold_pct";
const KV_DAILY_READ_LIMIT = "config:d1_daily_rows_read_limit";
const KV_INTERVAL_MIN = "config:d1_governor_interval_min";

export const DEFAULT_THRESHOLD_PCT = 70;
export const DEFAULT_DAILY_LIMIT = 100_000;
export const DEFAULT_READ_THRESHOLD_PCT = 70;
export const DEFAULT_DAILY_READ_LIMIT = 5_000_000;
// 15 min: one map session adds ~17k rows/hour, so an hourly check could overshoot
// the threshold by a full session-hour (owner decision 2026-10-05).
export const DEFAULT_INTERVAL_MIN = 15;

const GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql";

export interface GovernorConfig {
  thresholdPct: number; // rows_written
  dailyLimit: number; // rows_written
  readThresholdPct: number;
  dailyReadLimit: number;
  intervalMin: number;
}

export type GovernorMetric = "writes" | "reads";

export interface D1Usage {
  rowsWritten: number;
  rowsRead: number;
}

export interface GovernorState {
  day: string; // UTC date (YYYY-MM-DD) the governor tripped on
  disabled: FeatureFlag[]; // flags the governor itself turned OFF
  tripped_at: string; // ISO time of the first trip that day
  rows_written: number; // reading at the last trip
  rows_read?: number;
  // Which metric(s) tripped today. A state written before reads were governed has
  // neither field and means a writes trip.
  writes_tripped?: boolean;
  reads_tripped?: boolean;
}

export interface GovernorResult {
  action: "skipped" | "restored" | "tripped" | "ok" | "error";
  detail: string;
  rowsWritten?: number;
  rowsRead?: number;
  restored?: FeatureFlag[];
  disabled?: FeatureFlag[];
  tripped?: GovernorMetric[];
}

function parsePositive(raw: string | null, fallback: number, max = Number.MAX_SAFE_INTEGER): number {
  if (raw === null) return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 && n <= max ? n : fallback;
}

export async function resolveGovernorConfig(env: Env): Promise<GovernorConfig> {
  const [pct, limit, rpct, rlimit, interval] = await Promise.all([
    env.STIGLA_KV.get(KV_THRESHOLD_PCT),
    env.STIGLA_KV.get(KV_DAILY_LIMIT),
    env.STIGLA_KV.get(KV_READ_THRESHOLD_PCT),
    env.STIGLA_KV.get(KV_DAILY_READ_LIMIT),
    env.STIGLA_KV.get(KV_INTERVAL_MIN),
  ]);
  return {
    thresholdPct: parsePositive(pct, DEFAULT_THRESHOLD_PCT, 100),
    dailyLimit: parsePositive(limit, DEFAULT_DAILY_LIMIT),
    readThresholdPct: parsePositive(rpct, DEFAULT_READ_THRESHOLD_PCT, 100),
    dailyReadLimit: parsePositive(rlimit, DEFAULT_DAILY_READ_LIMIT),
    intervalMin: Math.round(parsePositive(interval, DEFAULT_INTERVAL_MIN, 1440)),
  };
}

export const utcDay = (d: Date): string => d.toISOString().slice(0, 10);

/** Is this minute-cron tick one the governor should run on? */
export function governorDue(now: Date, intervalMin: number): boolean {
  const minuteOfDay = now.getUTCHours() * 60 + now.getUTCMinutes();
  return minuteOfDay % Math.max(1, intervalMin) === 0;
}

export async function readGovernorState(env: Env): Promise<GovernorState | null> {
  const raw = await env.STIGLA_KV.get(KV_STATE);
  if (!raw) return null;
  try {
    const s = JSON.parse(raw) as GovernorState;
    if (typeof s.day !== "string" || !Array.isArray(s.disabled)) return null;
    if (s.writes_tripped === undefined && s.reads_tripped === undefined) s.writes_tripped = true;
    return s;
  } catch {
    return null;
  }
}

/**
 * True while today's rows_read trip is in force: non-essential D1 readers (the
 * aggregator, admin status) must stand down until 00:00 UTC. One KV read; a KV
 * failure reads as "not constrained" (never blocks on the guard itself).
 */
export async function readsConstrained(env: Env, now: Date = new Date()): Promise<boolean> {
  try {
    const s = await readGovernorState(env);
    return !!s && s.day === utcDay(now) && s.reads_tripped === true;
  } catch {
    return false;
  }
}

/**
 * A human set `flag` via /admin/flags: stop governing it for the current trip, so
 * the reset restore never overrides that decision.
 */
export async function forgetGovernedFlag(env: Env, flag: FeatureFlag): Promise<void> {
  const state = await readGovernorState(env);
  if (!state || !state.disabled.includes(flag)) return;
  state.disabled = state.disabled.filter((f) => f !== flag);
  await env.STIGLA_KV.put(KV_STATE, JSON.stringify(state));
}

/**
 * Today's (UTC) account-wide D1 rows_written and rows_read from the GraphQL
 * Analytics API — every database in the account, which is exactly what the daily
 * limits count, ad-hoc wrangler/REST queries included. Costs no D1 rows. Throws on
 * a missing secret or an unusable answer (the caller fails safe).
 */
export async function fetchUsageToday(
  env: Env,
  now: Date,
  fetchImpl: typeof fetch = fetch,
): Promise<D1Usage> {
  if (!env.CF_ANALYTICS_API_TOKEN || !env.CF_ACCOUNT_ID) {
    throw new Error("CF_ANALYTICS_API_TOKEN / CF_ACCOUNT_ID not configured");
  }
  const day = utcDay(now);
  const query =
    "query($a:String!,$d:Date!){viewer{accounts(filter:{accountTag:$a}){" +
    "d1AnalyticsAdaptiveGroups(limit:1000,filter:{date:$d}){sum{rowsWritten rowsRead}}}}}";
  const res = await fetchImpl(GRAPHQL_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.CF_ANALYTICS_API_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ query, variables: { a: env.CF_ACCOUNT_ID, d: day } }),
  });
  if (!res.ok) throw new Error(`GraphQL HTTP ${res.status}`);
  const body = (await res.json()) as {
    data?: {
      viewer?: {
        accounts?: { d1AnalyticsAdaptiveGroups?: { sum?: { rowsWritten?: number; rowsRead?: number } }[] }[];
      };
    };
    errors?: { message: string }[] | null;
  };
  if (body.errors && body.errors.length > 0) {
    throw new Error(`GraphQL error: ${body.errors.map((e) => e.message).join("; ")}`);
  }
  const groups = body.data?.viewer?.accounts?.[0]?.d1AnalyticsAdaptiveGroups;
  if (!Array.isArray(groups)) throw new Error("GraphQL answer has no d1AnalyticsAdaptiveGroups");
  return groups.reduce<D1Usage>(
    (u, g) => ({
      rowsWritten: u.rowsWritten + (g.sum?.rowsWritten ?? 0),
      rowsRead: u.rowsRead + (g.sum?.rowsRead ?? 0),
    }),
    { rowsWritten: 0, rowsRead: 0 },
  );
}

/**
 * One governor pass. Order matters: first the day-rollover restore (independent
 * of the API — it must happen even if analytics is unreachable), then the
 * threshold check.
 */
export async function runD1Governor(
  env: Env,
  now: Date,
  opts: { fetchImpl?: typeof fetch } = {},
): Promise<GovernorResult> {
  const today = utcDay(now);
  let state = await readGovernorState(env);

  // 1. Day rolled over → restore exactly what we turned off.
  if (state && state.day !== today) {
    const restored: FeatureFlag[] = [];
    for (const flag of state.disabled) {
      // Only if it's still OFF (as we left it); never touch a flag a human re-set.
      if (!(await getFlag(env, flag))) {
        await setFlag(env, flag, true);
        restored.push(flag);
      }
    }
    await env.STIGLA_KV.delete(KV_STATE);
    console.log(
      `D1_BUDGET_GOVERNOR: day ${state.day} -> ${today}, restored [${restored.join(",")}]`,
    );
    state = null;
    // Fall through: the new day's reading is checked below (normally ~0).
    const result = await checkThreshold(env, now, today, state, opts);
    return result.action === "tripped" ? result : { ...result, action: "restored", restored };
  }

  return checkThreshold(env, now, today, state, opts);
}

async function checkThreshold(
  env: Env,
  now: Date,
  today: string,
  state: GovernorState | null,
  opts: { fetchImpl?: typeof fetch },
): Promise<GovernorResult> {
  const todays = state && state.day === today ? state : null;
  if (todays?.writes_tripped && todays?.reads_tripped) {
    return { action: "skipped", detail: `writes and reads already tripped today (since ${todays.tripped_at})` };
  }

  const cfg = await resolveGovernorConfig(env);
  let usage: D1Usage;
  try {
    usage = await fetchUsageToday(env, now, opts.fetchImpl);
  } catch (e) {
    console.warn("D1_BUDGET_GOVERNOR: usage read failed; leaving flags untouched", e);
    return { action: "error", detail: String(e) };
  }

  const writeThreshold = (cfg.dailyLimit * cfg.thresholdPct) / 100;
  const readThreshold = (cfg.dailyReadLimit * cfg.readThresholdPct) / 100;
  const tripped: GovernorMetric[] = [];
  if (!todays?.writes_tripped && usage.rowsWritten >= writeThreshold) tripped.push("writes");
  if (!todays?.reads_tripped && usage.rowsRead >= readThreshold) tripped.push("reads");

  const reading =
    `rows_written ${usage.rowsWritten}/${writeThreshold} (${cfg.thresholdPct}% of ${cfg.dailyLimit}), ` +
    `rows_read ${usage.rowsRead}/${readThreshold} (${cfg.readThresholdPct}% of ${cfg.dailyReadLimit})`;
  if (tripped.length === 0) {
    return { action: todays ? "skipped" : "ok", detail: reading, rowsWritten: usage.rowsWritten, rowsRead: usage.rowsRead };
  }

  // Same response for either metric: the analytics writers go OFF. (A second trip
  // the same day re-applies it — a human re-enable after a WRITES trip does not
  // survive a later READS trip, which is a new, separate emergency.)
  const disabled: FeatureFlag[] = [];
  for (const flag of GOVERNED_FLAGS) {
    if (await getFlag(env, flag)) {
      await setFlag(env, flag, false);
      disabled.push(flag);
    }
  }
  const next: GovernorState = {
    day: today,
    disabled: [...new Set([...(todays?.disabled ?? []), ...disabled])],
    tripped_at: todays?.tripped_at ?? now.toISOString(),
    rows_written: usage.rowsWritten,
    rows_read: usage.rowsRead,
    writes_tripped: !!todays?.writes_tripped || tripped.includes("writes"),
    reads_tripped: !!todays?.reads_tripped || tripped.includes("reads"),
  };
  await env.STIGLA_KV.put(KV_STATE, JSON.stringify(next));
  console.error(
    `D1_BUDGET_GOVERNOR: tripped [${tripped.join(",")}] — ${reading}; turned OFF ` +
      `[${disabled.join(",")}] until 00:00 UTC` +
      (tripped.includes("reads") ? "; non-essential D1 reads stood down" : ""),
  );
  return {
    action: "tripped",
    detail: reading,
    rowsWritten: usage.rowsWritten,
    rowsRead: usage.rowsRead,
    disabled,
    tripped,
  };
}
