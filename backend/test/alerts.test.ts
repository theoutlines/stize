import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { listAlerts, parseSerbianDate } from "../src/lib/alerts";
import type { RouteAlert } from "../src/lib/alerts";

describe("parseSerbianDate", () => {
  it("converts DD-MM-YYYY to ISO", () => {
    expect(parseSerbianDate("31-05-2026")).toBe("2026-05-31");
  });

  it("falls back to the raw string when it doesn't match the expected format", () => {
    expect(parseSerbianDate("not a date")).toBe("not a date");
  });
});

describe("listAlerts", () => {
  it("returns an empty array when nothing has been cached yet", async () => {
    expect(await listAlerts(env)).toEqual([]);
  });

  it("returns whatever is cached in KV", async () => {
    const sample: RouteAlert[] = [
      {
        id: "test-alert",
        url: "https://www.bgprevoz.rs/vesti/test-alert",
        title: "Test alert",
        publishedAt: "2026-01-01",
        lines: ["79"],
        stops: [],
        validFrom: "2026-01-02",
        validUntil: null,
        confidence: "line",
        summary: "A test alert.",
      },
    ];
    await env.STIGLA_KV.put("route_alerts_v1", JSON.stringify(sample));
    expect(await listAlerts(env)).toEqual(sample);
  });
});
