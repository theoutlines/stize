import { beforeEach, describe, expect, it } from "vitest";
import { env, SELF } from "cloudflare:test";
import { createFeedback, createFeedbackIssue } from "../src/lib/feedback";
import { RateLimitedError, ValidationError } from "../src/lib/ideas";
import { setFlag } from "../src/lib/featureFlags";

// Each case uses a distinct IP: the per-IP rate limit is a real miniflare KV
// key (`feedback_rate:<ip>`), so sharing an IP across cases would cross-lock.
async function countRows(): Promise<number> {
  const row = await env.STIGLA_IDEAS_DB.prepare("SELECT COUNT(*) AS n FROM feedback").first<{ n: number }>();
  return row?.n ?? 0;
}

beforeEach(async () => {
  await env.STIGLA_IDEAS_DB.prepare("DELETE FROM feedback").run();
  await setFlag(env, "feedback_form", true);
});

describe("createFeedback (lib)", () => {
  it("stores a row with message + metadata", async () => {
    const row = await createFeedback(env, "1.1.1.1", {
      message: "  The nearby list froze on line 79.  ",
      contact: "  @ivan_tg  ",
      appVersion: "Stigla 1.0.0 (1)",
      platform: "web",
      locale: "sr",
    });
    expect(row.id).toBeGreaterThan(0);

    const stored = await env.STIGLA_IDEAS_DB.prepare(
      "SELECT message, contact, app_version, platform, locale FROM feedback WHERE id = ?",
    )
      .bind(row.id)
      .first<{ message: string; contact: string; app_version: string; platform: string; locale: string }>();
    expect(stored?.message).toBe("The nearby list froze on line 79."); // trimmed
    expect(stored?.contact).toBe("@ivan_tg");
    expect(stored?.app_version).toBe("Stigla 1.0.0 (1)");
    expect(stored?.platform).toBe("web");
    expect(stored?.locale).toBe("sr");
  });

  it("stores contact as null when omitted", async () => {
    const row = await createFeedback(env, "1.1.1.2", { message: "no contact given" });
    const stored = await env.STIGLA_IDEAS_DB.prepare("SELECT contact FROM feedback WHERE id = ?")
      .bind(row.id)
      .first<{ contact: string | null }>();
    expect(stored?.contact).toBeNull();
  });

  it("rejects an empty message", async () => {
    await expect(createFeedback(env, "1.1.1.3", { message: "   " })).rejects.toBeInstanceOf(ValidationError);
    expect(await countRows()).toBe(0);
  });

  it("rejects an over-length message and stores nothing", async () => {
    const huge = "x".repeat(2001);
    await expect(createFeedback(env, "1.1.1.4", { message: huge })).rejects.toBeInstanceOf(ValidationError);
    expect(await countRows()).toBe(0);
  });

  it("rejects a honeypot-filled submission and stores nothing", async () => {
    await expect(
      createFeedback(env, "1.1.1.5", { message: "real text", honeypot: "http://spam.example" }),
    ).rejects.toBeInstanceOf(ValidationError);
    expect(await countRows()).toBe(0);
  });

  it("rate-limits repeat submissions from the same IP", async () => {
    await createFeedback(env, "1.1.1.6", { message: "first" });
    await expect(createFeedback(env, "1.1.1.6", { message: "second" })).rejects.toBeInstanceOf(
      RateLimitedError,
    );
    expect(await countRows()).toBe(1); // only the first landed
  });
});

describe("createFeedbackIssue (best-effort)", () => {
  it("is a no-op when no GitHub token is configured (store-only)", async () => {
    // Default test env has GITHUB_FEEDBACK_REPO set but no token → must not throw.
    await expect(createFeedbackIssue(env, { message: "hi" })).resolves.toBeUndefined();
  });
});

describe("POST /api/v1/feedback", () => {
  const post = (body: unknown, ip = "2.2.2.1") =>
    SELF.fetch("https://stigla-api.test/api/v1/feedback", {
      method: "POST",
      headers: { "content-type": "application/json", "CF-Connecting-IP": ip },
      body: JSON.stringify(body),
    });

  it("stores a row and returns 201 (GitHub token absent = store-only, no failure)", async () => {
    const res = await post({ message: "map is blank on my phone", app_version: "Stigla 1.0.0 (1)", platform: "web", locale: "en" });
    expect(res.status).toBe(201);
    const json = await res.json<{ id: number }>();
    expect(json.id).toBeGreaterThan(0);
    expect(await countRows()).toBe(1);
  });

  it("rejects an over-length message with 400", async () => {
    const res = await post({ message: "x".repeat(2001) }, "2.2.2.2");
    expect(res.status).toBe(400);
    expect(await countRows()).toBe(0);
  });

  it("rejects a honeypot-filled submission with 400", async () => {
    const res = await post({ message: "real", website: "spam" }, "2.2.2.3");
    expect(res.status).toBe(400);
    expect(await countRows()).toBe(0);
  });

  it("rate-limits repeats from the same IP with 429", async () => {
    const first = await post({ message: "first" }, "2.2.2.4");
    expect(first.status).toBe(201);
    const second = await post({ message: "second" }, "2.2.2.4");
    expect(second.status).toBe(429);
    expect(await countRows()).toBe(1);
  });

  it("returns 403 when feedback_form is off (killswitch)", async () => {
    await setFlag(env, "feedback_form", false);
    const res = await post({ message: "should be refused" }, "2.2.2.5");
    expect(res.status).toBe(403);
    expect(await countRows()).toBe(0);
  });
});
