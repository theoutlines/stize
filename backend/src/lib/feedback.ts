import type { Env } from "../env";
// Reuse the shared error vocabulary so the `/api/v1/feedback` handler maps them
// to the same status codes as the ideas endpoint (400 / 429).
import { RateLimitedError, ValidationError } from "./ideas";

// A feedback message is a free-form paragraph, so a much larger cap than an
// idea's 280-char headline — but still bounded so a single POST can't dump
// unbounded text into D1.
const MAX_MESSAGE_LENGTH = 2000;
const MAX_CONTACT_LENGTH = 200;

// Abuse guard: one accepted submission per client IP per window. Presence of the
// KV key = locked out (same pattern as `idea_rate:`), auto-expiring via TTL.
const RATE_LIMIT_SECONDS = 60;

// A stray-length metadata cap — app_version / platform / locale are attached by
// the client, but the endpoint is public so we clamp them defensively.
const MAX_META_LENGTH = 64;

export interface FeedbackInput {
  message: string;
  contact?: string | null;
  /** Hidden honeypot field — real users never fill it; a bot that does is dropped. */
  honeypot?: string | null;
  appVersion?: string | null;
  platform?: string | null;
  locale?: string | null;
}

export interface FeedbackRow {
  id: number;
  created_at: string;
}

function clampMeta(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, MAX_META_LENGTH);
}

/**
 * Validate + rate-limit + persist one feedback submission to D1. Throws
 * {@link ValidationError} (→ 400) on a bad payload / tripped honeypot and
 * {@link RateLimitedError} (→ 429) when the IP is inside its cooldown. D1 is the
 * durable store; the GitHub issue (see {@link createFeedbackIssue}) is layered
 * on best-effort by the caller AFTER this resolves.
 */
export async function createFeedback(
  env: Env,
  ip: string,
  input: FeedbackInput,
): Promise<FeedbackRow> {
  // Honeypot: a hidden field no human sees. Any content = a bot. Reject before
  // touching the rate-limit key so spam never consumes a real user's window.
  if (typeof input.honeypot === "string" && input.honeypot.trim() !== "") {
    throw new ValidationError("rejected");
  }

  const message = (input.message ?? "").trim();
  if (!message) throw new ValidationError("message must not be empty");
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new ValidationError(`message must be at most ${MAX_MESSAGE_LENGTH} chars`);
  }

  const contact = clampContact(input.contact);

  const rateLimitKey = `feedback_rate:${ip}`;
  if (await env.STIGLA_KV.get(rateLimitKey)) {
    throw new RateLimitedError("please wait a moment before sending more feedback");
  }
  await env.STIGLA_KV.put(rateLimitKey, "1", { expirationTtl: RATE_LIMIT_SECONDS });

  const createdAt = new Date().toISOString();
  const { meta } = await env.STIGLA_IDEAS_DB.prepare(
    `INSERT INTO feedback (message, contact, app_version, platform, locale, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      message,
      contact,
      clampMeta(input.appVersion),
      clampMeta(input.platform),
      clampMeta(input.locale),
      createdAt,
    )
    .run();

  return { id: meta.last_row_id as number, created_at: createdAt };
}

function clampContact(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, MAX_CONTACT_LENGTH);
}

/**
 * Best-effort GitHub triage issue for an accepted submission. Only fires when a
 * `GITHUB_FEEDBACK_TOKEN` secret (fine-grained PAT, issues:write on a PRIVATE
 * repo) AND a `GITHUB_FEEDBACK_REPO` ("owner/name") are configured on the
 * worker; absent either, this is a no-op (store-only, no error). The caller runs
 * it under `waitUntil` and swallows failures — D1 already holds the durable
 * copy, so a GitHub outage never fails or loses the submission.
 */
export async function createFeedbackIssue(env: Env, input: FeedbackInput): Promise<void> {
  const token = env.GITHUB_FEEDBACK_TOKEN;
  const repo = env.GITHUB_FEEDBACK_REPO;
  if (!token || !repo) return; // store-only mode

  const message = (input.message ?? "").trim();
  if (!message) return;

  const firstLine = message.split("\n", 1)[0]!.trim();
  const title = (firstLine || "Feedback").slice(0, 80);
  const contact = clampContact(input.contact);
  const body = [
    message,
    "",
    "---",
    `- app version: ${clampMeta(input.appVersion) ?? "—"}`,
    `- platform: ${clampMeta(input.platform) ?? "—"}`,
    `- locale: ${clampMeta(input.locale) ?? "—"}`,
    `- contact: ${contact ?? "—"}`,
  ].join("\n");

  const res = await fetch(`https://api.github.com/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "stigla-feedback-bot",
      "content-type": "application/json",
    },
    body: JSON.stringify({ title, body, labels: ["feedback"] }),
  });
  if (!res.ok) {
    throw new Error(`github issue create failed: ${res.status}`);
  }
}
