import { beforeEach, describe, expect, it } from "vitest";
import { env, SELF } from "cloudflare:test";
import { stopReportToFeedback } from "../src/lib/feedback";
import { ValidationError } from "../src/lib/errors";
import { setFlag } from "../src/lib/featureFlags";

const STOP = { stop_id: "20147", name: "Trg Slavija", lat: 44.80297, lon: 20.46653, lines: ["2", "31"] };

beforeEach(async () => {
  await env.STIGLA_IDEAS_DB.prepare("DELETE FROM feedback").run();
  await setFlag(env, "feedback_form", true);
});

describe("stopReportToFeedback", () => {
  it("writes the stop context into the message and the issue title", () => {
    const { feedback, title } = stopReportToFeedback(STOP, { stopId: "20147", category: "wrong_lines" });
    expect(feedback.message).toContain("[stop 20147] wrong_lines");
    expect(feedback.message).toContain("lines: 2, 31");
    expect(title).toBe("[stop 20147] wrong_lines · Trg Slavija");
  });

  it("rejects an unknown category", () => {
    expect(() => stopReportToFeedback(STOP, { stopId: "20147", category: "spam" })).toThrow(ValidationError);
  });

  it("requires a comment for other, and only keeps it trimmed", () => {
    expect(() => stopReportToFeedback(STOP, { stopId: "20147", category: "other", comment: "  " })).toThrow(
      ValidationError,
    );
    const { feedback } = stopReportToFeedback(STOP, {
      stopId: "20147",
      category: "other",
      comment: "  the pole is gone  ",
    });
    expect(feedback.message).toContain("other: the pole is gone");
  });
});

async function anyStopId(): Promise<string> {
  const res = await SELF.fetch("https://x/api/v1/stops/all");
  const data = (await res.json()) as { stops?: { stop_id: string }[] } | { stop_id: string }[];
  const list = Array.isArray(data) ? data : (data.stops ?? []);
  return list[0]!.stop_id;
}

describe("POST /api/v1/stops/:id/report", () => {
  const post = (id: string, body: unknown, ip: string) =>
    SELF.fetch(`https://x/api/v1/stops/${id}/report`, {
      method: "POST",
      headers: { "content-type": "application/json", "CF-Connecting-IP": ip },
      body: JSON.stringify(body),
    });

  it("stores a report for a known stop", async () => {
    const id = await anyStopId();
    expect(id).toBeTruthy();
    const res = await post(id!, { category: "wrong_name", platform: "web", locale: "en" }, "9.9.9.1");
    expect(res.status).toBe(201);
    const row = await env.STIGLA_IDEAS_DB.prepare("SELECT message FROM feedback").first<{ message: string }>();
    expect(row?.message).toContain(`[stop ${id}] wrong_name`);
  });

  it("404s an unknown stop and 400s a bad category", async () => {
    expect((await post("does-not-exist", { category: "wrong_name" }, "9.9.9.2")).status).toBe(404);
    expect((await post(await anyStopId(), { category: "nope" }, "9.9.9.3")).status).toBe(400);
  });

  it("is off with the feedback killswitch", async () => {
    await setFlag(env, "feedback_form", false);
    expect((await post("20147", { category: "wrong_name" }, "9.9.9.4")).status).toBe(403);
  });
});
