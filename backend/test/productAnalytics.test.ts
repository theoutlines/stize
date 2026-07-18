import { beforeEach, describe, expect, it } from "vitest";
import { env, SELF } from "cloudflare:test";
import {
  MAX_BATCH,
  logProductEvents,
  sanitizeBatch,
  sanitizeEvent,
} from "../src/lib/productAnalytics";
import { setFlag } from "../src/lib/featureFlags";

// A throwaway waitUntil scope: logProductEvents keys its memoized flag read off
// this object, and the endpoint hands the write to waitUntil in production.
const scope = () => ({ waitUntil() {} });

beforeEach(async () => {
  await env.STIGLA_ANALYTICS_DB.prepare("DELETE FROM product_events").run();
  await setFlag(env, "product_analytics", true);
});

describe("sanitizeEvent", () => {
  it("keeps an allow-listed event with valid enum props", () => {
    expect(sanitizeEvent({ event: "app_open", props: { mode: "on_demand", locale_class: "sr" } })).toEqual({
      event: "app_open",
      props: { mode: "on_demand", locale_class: "sr" },
      session: null,
    });
  });

  it("drops an unknown event name entirely", () => {
    expect(sanitizeEvent({ event: "rage_quit" })).toBeNull();
    expect(sanitizeEvent({ event: 42 })).toBeNull();
    expect(sanitizeEvent(null)).toBeNull();
    expect(sanitizeEvent("stop_open")).toBeNull();
  });

  it("strips unknown property keys and out-of-enum values", () => {
    // `source` is valid; `evil` is not a known key; `mode` isn't allowed on stop_open.
    expect(
      sanitizeEvent({ event: "stop_open", props: { source: "pin", evil: "x", mode: "aquarium" } }),
    ).toEqual({ event: "stop_open", props: { source: "pin" }, session: null });
    // An out-of-enum value for a known key is dropped, leaving no props.
    expect(sanitizeEvent({ event: "stop_open", props: { source: "telepathy" } })).toEqual({
      event: "stop_open",
      props: null,
      session: null,
    });
  });

  it("ignores props on a no-property event", () => {
    expect(sanitizeEvent({ event: "search_used", props: { source: "pin" } })).toEqual({
      event: "search_used",
      props: null,
      session: null,
    });
  });

  it("keeps a well-formed session id but drops a malformed one", () => {
    expect(sanitizeEvent({ event: "search_used", session: "ab12_CD-9" })?.session).toBe("ab12_CD-9");
    // Too long / illegal characters / free text -> dropped to null.
    expect(sanitizeEvent({ event: "search_used", session: "a".repeat(33) })?.session).toBeNull();
    expect(sanitizeEvent({ event: "search_used", session: "hi there!" })?.session).toBeNull();
  });
});

describe("sanitizeBatch", () => {
  it("drops unknowns and caps the batch at MAX_BATCH", () => {
    const raw = [
      { event: "search_used" },
      { event: "nope" },
      { event: "stop_open", props: { source: "nearby" } },
    ];
    expect(sanitizeBatch(raw)).toHaveLength(2);

    const flood = Array.from({ length: MAX_BATCH + 25 }, () => ({ event: "search_used" }));
    expect(sanitizeBatch(flood)).toHaveLength(MAX_BATCH);
    expect(sanitizeBatch("not an array")).toEqual([]);
  });
});

describe("logProductEvents", () => {
  it("writes sanitized rows with an hour-bucketed timestamp and JSON props", async () => {
    const events = sanitizeBatch([
      { event: "app_open", props: { mode: "aquarium", locale_class: "other" }, session: "sess1" },
      { event: "sort_comfort" },
    ]);
    await logProductEvents(env, scope(), events);

    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT event, props, session, hour_bucket FROM product_events ORDER BY event",
    ).all<{ event: string; props: string | null; session: string | null; hour_bucket: number }>();

    expect(results).toHaveLength(2);
    const appOpen = results.find((r) => r.event === "app_open")!;
    expect(JSON.parse(appOpen.props!)).toEqual({ mode: "aquarium", locale_class: "other" });
    expect(appOpen.session).toBe("sess1");
    // Server-stamped, truncated to the hour.
    expect(appOpen.hour_bucket % 3600).toBe(0);
    const sort = results.find((r) => r.event === "sort_comfort")!;
    expect(sort.props).toBeNull();
    expect(sort.session).toBeNull();
  });

  it("writes nothing when the product_analytics flag is off", async () => {
    await setFlag(env, "product_analytics", false);
    await logProductEvents(env, scope(), sanitizeBatch([{ event: "search_used" }]));
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM product_events",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(0);
  });

  it("chunks a batch wider than D1's bound-param cap without error", async () => {
    // 4 columns per row; MAX_BATCH rows = 400 params, well over D1's 100 cap, so
    // chunkedInsert must split it. All rows must land.
    const events = sanitizeBatch(
      Array.from({ length: MAX_BATCH }, () => ({ event: "line_filter" })),
    );
    await logProductEvents(env, scope(), events);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM product_events",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(MAX_BATCH);
  });
});

describe("POST /api/v1/events", () => {
  const post = (payload: unknown) =>
    SELF.fetch("https://stigla-api.test/api/v1/events", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });

  it("returns 204 and writes nothing when the flag is OFF", async () => {
    await setFlag(env, "product_analytics", false);
    const res = await post({ events: [{ event: "search_used" }] });
    expect(res.status).toBe(204);
    const { results } = await env.STIGLA_ANALYTICS_DB.prepare(
      "SELECT COUNT(*) AS n FROM product_events",
    ).all<{ n: number }>();
    expect(results[0].n).toBe(0);
  });

  it("returns 202 with the accepted count when the flag is ON", async () => {
    await setFlag(env, "product_analytics", true);
    // One valid event + one unknown (dropped) -> accepted: 1.
    const res = await post({
      events: [{ event: "stop_open", props: { source: "pin" } }, { event: "junk" }],
    });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ accepted: 1 });
  });
});
