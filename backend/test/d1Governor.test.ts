import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import type { Env } from "../src/env";
import worker from "../src/index";
import {
  fetchUsageToday,
  forgetGovernedFlag,
  governorDue,
  readGovernorState,
  readsConstrained,
  runD1Governor,
} from "../src/lib/d1Governor";
import { getFlag, setFlag } from "../src/lib/featureFlags";
import { loadSentinels } from "../src/lib/sweep";

const DAY1 = new Date(Date.UTC(2026, 9, 5, 13, 0, 0));
const DAY2_MIDNIGHT = new Date(Date.UTC(2026, 9, 6, 0, 0, 0));

const govEnv = { ...env, CF_ANALYTICS_API_TOKEN: "test-token", CF_ACCOUNT_ID: "test-account" } as Env;

// A GraphQL answer reporting `rows` written (and `init.read` rows read) today,
// split over two "databases".
function gql(rows: number | null, init: { status?: number; errors?: string; read?: number } = {}): typeof fetch {
  return (async (_url: RequestInfo | URL, req?: RequestInit) => {
    const body = JSON.parse(String(req?.body));
    expect(body.variables.a).toBe("test-account");
    expect(String((req?.headers as Record<string, string>).Authorization)).toBe("Bearer test-token");
    if (init.errors) return Response.json({ data: null, errors: [{ message: init.errors }] });
    const half = rows === null ? 0 : Math.floor(rows / 2);
    const read = init.read ?? 0;
    const rhalf = Math.floor(read / 2);
    return Response.json(
      {
        data: {
          viewer: {
            accounts: [
              {
                d1AnalyticsAdaptiveGroups:
                  rows === null
                    ? []
                    : [
                        { sum: { rowsWritten: half, rowsRead: rhalf } },
                        { sum: { rowsWritten: rows - half, rowsRead: read - rhalf } },
                      ],
              },
            ],
          },
        },
        errors: null,
      },
      { status: init.status ?? 200 },
    );
  }) as typeof fetch;
}

beforeEach(async () => {
  for (const k of [
    "d1_governor:state",
    "config:d1_governor_threshold_pct",
    "config:d1_daily_rows_written_limit",
    "config:d1_governor_interval_min",
    "config:d1_governor_read_threshold_pct",
    "config:d1_analytics_share_pct",
    "config:d1_daily_rows_read_limit",
  ]) {
    await env.STIGLA_KV.delete(k);
  }
  await setFlag(env, "analytics_collect", true);
  await setFlag(env, "jam_detection_collect", true);
});

describe("governorDue", () => {
  it("fires on the interval boundary of the UTC day (incl. 00:00)", () => {
    expect(governorDue(new Date(Date.UTC(2026, 9, 6, 0, 0)), 60)).toBe(true);
    expect(governorDue(new Date(Date.UTC(2026, 9, 6, 13, 0)), 60)).toBe(true);
    expect(governorDue(new Date(Date.UTC(2026, 9, 6, 13, 1)), 60)).toBe(false);
    expect(governorDue(new Date(Date.UTC(2026, 9, 6, 13, 15)), 15)).toBe(true);
  });
});

describe("fetchUsageToday", () => {
  it("sums every database's rowsWritten and rowsRead for today", async () => {
    expect(await fetchUsageToday(govEnv, DAY1, gql(71_000, { read: 1_234_567 }))).toEqual({
      rowsWritten: 71_000,
      rowsRead: 1_234_567,
    });
  });

  it("throws (fail-safe) without secrets, on HTTP errors and GraphQL errors", async () => {
    await expect(fetchUsageToday(env as Env, DAY1, gql(1))).rejects.toThrow(/not configured/);
    await expect(fetchUsageToday(govEnv, DAY1, gql(1, { status: 500 }))).rejects.toThrow(/HTTP 500/);
    await expect(fetchUsageToday(govEnv, DAY1, gql(1, { errors: "quota" }))).rejects.toThrow(/quota/);
  });
});

describe("runD1Governor", () => {
  it("below the analytics share: nothing changes", async () => {
    const r = await runD1Governor(govEnv, DAY1, { fetchImpl: gql(39_999) });
    expect(r.action).toBe("ok");
    expect(await getFlag(env, "analytics_collect")).toBe(true);
    expect(await readGovernorState(env)).toBeNull();
  });

  it("at >= 70%: turns both collectors OFF and records which ones", async () => {
    const r = await runD1Governor(govEnv, DAY1, { fetchImpl: gql(70_000) });
    expect(r.action).toBe("tripped");
    expect(await getFlag(env, "analytics_collect")).toBe(false);
    expect(await getFlag(env, "jam_detection_collect")).toBe(false);
    expect((await readGovernorState(env))?.disabled).toEqual(["analytics_collect", "jam_detection_collect"]);
  });

  it("at the analytics share (40%): only analytics_collect goes OFF, once a day", async () => {
    const r = await runD1Governor(govEnv, DAY1, { fetchImpl: gql(40_000) });
    expect(r.action).toBe("tripped");
    expect(r.disabled).toEqual(["analytics_collect"]);
    expect(await getFlag(env, "analytics_collect")).toBe(false);
    expect(await getFlag(env, "jam_detection_collect")).toBe(true);
    expect((await readGovernorState(env))?.analytics_capped).toBe(true);
    // A human re-enable the same day is not overridden by the share again...
    await setFlag(env, "analytics_collect", true);
    const again = await runD1Governor(govEnv, new Date(DAY1.getTime() + 3600_000), { fetchImpl: gql(50_000) });
    expect(again.action).not.toBe("tripped");
    expect(await getFlag(env, "analytics_collect")).toBe(true);
    // ...but the general 70% threshold still applies.
    const general = await runD1Governor(govEnv, new Date(DAY1.getTime() + 7200_000), { fetchImpl: gql(70_000) });
    expect(general.action).toBe("tripped");
    expect(await getFlag(env, "jam_detection_collect")).toBe(false);
  });

  it("thresholds come from KV config", async () => {
    await env.STIGLA_KV.put("config:d1_analytics_share_pct", "100");
    await env.STIGLA_KV.put("config:d1_governor_threshold_pct", "50");
    await env.STIGLA_KV.put("config:d1_daily_rows_written_limit", "10000");
    expect((await runD1Governor(govEnv, DAY1, { fetchImpl: gql(4_999) })).action).toBe("ok");
    expect((await runD1Governor(govEnv, DAY1, { fetchImpl: gql(5_000) })).action).toBe("tripped");
  });

  it("trips at most once per day (a human re-enable is not overridden the same day)", async () => {
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(80_000) });
    await setFlag(env, "analytics_collect", true); // human turns it back on
    const r = await runD1Governor(govEnv, new Date(DAY1.getTime() + 3600_000), { fetchImpl: gql(90_000) });
    expect(r.action).toBe("skipped");
    expect(await getFlag(env, "analytics_collect")).toBe(true);
  });

  it("after 00:00 UTC restores ONLY the flags it turned off", async () => {
    await setFlag(env, "jam_detection_collect", false); // a human had it OFF already
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(75_000) });
    expect((await readGovernorState(env))?.disabled).toEqual(["analytics_collect"]);

    const r = await runD1Governor(govEnv, DAY2_MIDNIGHT, { fetchImpl: gql(12) });
    expect(r.action).toBe("restored");
    expect(r.restored).toEqual(["analytics_collect"]);
    expect(await getFlag(env, "analytics_collect")).toBe(true);
    expect(await getFlag(env, "jam_detection_collect")).toBe(false); // human's OFF kept
    expect(await readGovernorState(env)).toBeNull();
  });

  it("restores even when the usage API is down after midnight", async () => {
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(75_000) });
    const r = await runD1Governor(govEnv, DAY2_MIDNIGHT, { fetchImpl: gql(0, { status: 503 }) });
    expect(r.action).toBe("restored");
    expect(await getFlag(env, "analytics_collect")).toBe(true);
  });

  it("a manual /admin/flags decision during the day is never overridden by the restore", async () => {
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(75_000) });
    await setFlag(env, "analytics_collect", false);
    await forgetGovernedFlag(env, "analytics_collect"); // what /admin/flags does
    await runD1Governor(govEnv, DAY2_MIDNIGHT, { fetchImpl: gql(1) });
    expect(await getFlag(env, "analytics_collect")).toBe(false); // human OFF kept
    expect(await getFlag(env, "jam_detection_collect")).toBe(true); // governor's restored
  });

  it("fails safe: a usage-read error changes nothing", async () => {
    const r = await runD1Governor(govEnv, DAY1, { fetchImpl: gql(99_000, { errors: "boom" }) });
    expect(r.action).toBe("error");
    expect(await getFlag(env, "analytics_collect")).toBe(true);
  });
});

describe("runD1Governor — rows_read (2026-10-05: diagnostics hit 93% of 5M)", () => {
  it("reads >= 70% of 5M trips the same flags and constrains non-essential reads", async () => {
    expect((await runD1Governor(govEnv, DAY1, { fetchImpl: gql(1_000, { read: 3_499_999 }) })).action).toBe("ok");
    expect(await readsConstrained(env, DAY1)).toBe(false);

    const r = await runD1Governor(govEnv, DAY1, { fetchImpl: gql(1_000, { read: 3_500_000 }) });
    expect(r.action).toBe("tripped");
    expect(r.tripped).toEqual(["reads"]);
    expect(await getFlag(env, "analytics_collect")).toBe(false);
    expect(await getFlag(env, "jam_detection_collect")).toBe(false);
    expect(await readsConstrained(env, DAY1)).toBe(true);
    expect(await readsConstrained(env, DAY2_MIDNIGHT)).toBe(false); // only for that day
  });

  it("read thresholds come from their own KV keys", async () => {
    await env.STIGLA_KV.put("config:d1_governor_read_threshold_pct", "50");
    await env.STIGLA_KV.put("config:d1_daily_rows_read_limit", "1000000");
    expect((await runD1Governor(govEnv, DAY1, { fetchImpl: gql(0, { read: 499_999 }) })).action).toBe("ok");
    expect((await runD1Governor(govEnv, DAY1, { fetchImpl: gql(0, { read: 500_000 }) })).action).toBe("tripped");
  });

  it("a writes trip does not constrain reads; a later reads trip the same day still fires", async () => {
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(80_000, { read: 10 }) });
    expect(await readsConstrained(env, DAY1)).toBe(false);
    await setFlag(env, "analytics_collect", true); // human re-enabled after the writes trip
    await forgetGovernedFlag(env, "analytics_collect");
    const later = new Date(DAY1.getTime() + 900_000);
    const r = await runD1Governor(govEnv, later, { fetchImpl: gql(81_000, { read: 4_000_000 }) });
    expect(r.tripped).toEqual(["reads"]);
    expect(await getFlag(env, "analytics_collect")).toBe(false); // new emergency → OFF again
    const st = await readGovernorState(env);
    expect(st).toMatchObject({ writes_tripped: true, reads_tripped: true });
    expect(st?.disabled.sort()).toEqual(["analytics_collect", "jam_detection_collect"]);
    // Both tripped → further passes skip without even calling the API.
    expect((await runD1Governor(govEnv, later, { fetchImpl: gql(0, { status: 500 }) })).action).toBe("skipped");
    // Midnight restores both.
    await runD1Governor(govEnv, DAY2_MIDNIGHT, { fetchImpl: gql(1) });
    expect(await getFlag(env, "analytics_collect")).toBe(true);
    expect(await getFlag(env, "jam_detection_collect")).toBe(true);
  });

  it("a state written by the writes-only governor is read as a writes trip", async () => {
    await env.STIGLA_KV.put(
      "d1_governor:state",
      JSON.stringify({ day: "2026-10-05", disabled: ["analytics_collect"], tripped_at: DAY1.toISOString(), rows_written: 70_001 }),
    );
    expect((await readGovernorState(env))?.writes_tripped).toBe(true);
    expect(await readsConstrained(env, DAY1)).toBe(false);
  });

  it("admin status and the manual aggregate stand down (503, no D1) while reads are constrained", async () => {
    await runD1Governor(govEnv, DAY1, { fetchImpl: gql(0, { read: 4_900_000 }) });
    // Pin "today" to the trip day for the route's own readsConstrained(new Date()).
    vi.useFakeTimers({ now: DAY1, toFake: ["Date"] });
    try {
      for (const [method, path] of [
        ["GET", "/api/v1/admin/sweep/status"],
        ["POST", "/api/v1/admin/analytics/aggregate"],
      ] as const) {
        const ctx = createExecutionContext();
        const res = await worker.fetch(
          new Request(`https://stigla-api.test${path}`, { method, headers: { "X-Admin-Token": "adm" } }),
          { ...env, ADMIN_TOKEN: "adm", STIGLA_ANALYTICS_DB: deadDb } as Env, // proves no D1 call is made
          ctx,
        );
        await waitOnExecutionContext(ctx);
        expect(res.status).toBe(503);
      }
    } finally {
      vi.useRealTimers();
    }
  });
});

const deadDb = new Proxy({} as D1Database, {
  get() {
    return () => {
      throw new Error("D1 must not be touched");
    };
  },
});

describe("D1-backed routes answer 503, never 500, when D1 is down", () => {
  const dead = new Proxy({} as D1Database, {
    get() {
      return () => {
        throw new Error("D1_ERROR: daily rows_written limit exceeded");
      };
    },
  });
  const deadEnv = { ...env, STIGLA_IDEAS_DB: dead, STIGLA_ANALYTICS_DB: dead } as Env;

  async function call(path: string, init: RequestInit = {}) {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      new Request(`https://stigla-api.test${path}`, {
        ...init,
        headers: { "X-Device-Id": "dev-1", "content-type": "application/json", Origin: "https://stize.app" },
      }),
      deadEnv,
      ctx,
    );
    await waitOnExecutionContext(ctx);
    return res;
  }

  it.each([
    ["GET", "/api/v1/analytics/lines/79"],
  ])("%s %s → 503 JSON with CORS", async (method, path) => {
    const res = await call(path, { method, body: method === "POST" ? JSON.stringify({ text: "hello there" }) : undefined });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "temporarily_unavailable" });
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
  });

  it("POST /api/v1/feedback → 503", async () => {
    await setFlag(env, "feedback_form", true);
    const res = await call("/api/v1/feedback", { method: "POST", body: JSON.stringify({ message: "A real message here" }) });
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "temporarily_unavailable" });
  });

  afterEach(() => vi.unstubAllGlobals());

  it("/arrivals still serves a live board (all D1 writers on, every D1 call throwing)", async () => {
    // The pre-migration-0009 / over-budget state: every analytics write throws.
    // The live path must neither fail nor wait on them (all in waitUntil + catch).
    for (const f of ["analytics_collect", "jam_detection_collect", "upstream_budget"] as const) {
      await setFlag(env, f, true);
    }
    const e = env as { TRANSIT_SOURCE_FORM_EXTRA_JSON: string; TRANSIT_SOURCE_BASE_URL: string };
    const orig = { extra: e.TRANSIT_SOURCE_FORM_EXTRA_JSON, url: e.TRANSIT_SOURCE_BASE_URL };
    e.TRANSIT_SOURCE_FORM_EXTRA_JSON = "{}";
    e.TRANSIT_SOURCE_BASE_URL = "https://source.invalid/api";
    vi.stubGlobal("fetch", () =>
      Promise.resolve(new Response("[]", { status: 200, headers: { "content-type": "application/json" } })),
    );
    try {
      const stop = (await loadSentinels(env))[0];
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        new Request(`https://stigla-api.test/api/v1/arrivals?stop=${stop}&cb=${Date.now()}`),
        { ...deadEnv, TRANSIT_SOURCE_FORM_EXTRA_JSON: "{}", TRANSIT_SOURCE_BASE_URL: "https://source.invalid/api" } as Env,
        ctx,
      );
      expect(res.status).toBe(200);
      expect(((await res.json()) as { service_status: string }).service_status).toBe("ok");
      await waitOnExecutionContext(ctx); // background writes fail quietly
    } finally {
      e.TRANSIT_SOURCE_FORM_EXTRA_JSON = orig.extra;
      e.TRANSIT_SOURCE_BASE_URL = orig.url;
      for (const f of ["analytics_collect", "jam_detection_collect", "upstream_budget"] as const) {
        await setFlag(env, f, false);
      }
    }
  });

  it("/config still answers (D1 is not on its path)", async () => {
    const res = await call("/api/v1/config");
    expect(res.status).toBe(200);
  });
});
