import type { Env } from "../env";
import type { IdeaCommentDto, IdeaDto } from "../types";

const MAX_TEXT_LENGTH = 280;
const RATE_LIMIT_SECONDS = 5 * 60; // one new idea per device per 5 minutes

export class RateLimitedError extends Error {}
export class ValidationError extends Error {}

export async function listIdeas(env: Env, deviceId: string): Promise<IdeaDto[]> {
  const { results } = await env.STIGLA_IDEAS_DB.prepare(
    `SELECT i.id, i.text, i.created_at,
            (SELECT COUNT(*) FROM idea_votes v WHERE v.idea_id = i.id) AS votes,
            EXISTS(SELECT 1 FROM idea_votes v WHERE v.idea_id = i.id AND v.device_id = ?) AS has_voted
     FROM ideas i
     WHERE i.hidden = 0
     ORDER BY votes DESC, i.created_at DESC`,
  )
    .bind(deviceId)
    .all<{ id: number; text: string; created_at: string; votes: number; has_voted: number }>();

  return results.map((r) => ({
    id: r.id,
    text: r.text,
    votes: r.votes,
    created_at: r.created_at,
    has_voted: r.has_voted === 1,
  }));
}

export async function createIdea(env: Env, deviceId: string, text: string): Promise<IdeaDto> {
  const trimmed = text.trim();
  if (!trimmed) throw new ValidationError("text must not be empty");
  if (trimmed.length > MAX_TEXT_LENGTH) throw new ValidationError(`text must be at most ${MAX_TEXT_LENGTH} chars`);

  const rateLimitKey = `idea_rate:${deviceId}`;
  if (await env.STIGLA_KV.get(rateLimitKey)) {
    throw new RateLimitedError("only one new idea per device every few minutes");
  }
  await env.STIGLA_KV.put(rateLimitKey, "1", { expirationTtl: RATE_LIMIT_SECONDS });

  const createdAt = new Date().toISOString();
  const { meta } = await env.STIGLA_IDEAS_DB.prepare(
    "INSERT INTO ideas (text, created_at, hidden) VALUES (?, ?, 0)",
  )
    .bind(trimmed, createdAt)
    .run();

  return { id: meta.last_row_id as number, text: trimmed, votes: 0, created_at: createdAt, has_voted: false };
}

/** Toggles the device's vote on an idea. Returns the new vote count and state. */
export async function toggleVote(env: Env, ideaId: number, deviceId: string): Promise<{ votes: number; has_voted: boolean }> {
  const existing = await env.STIGLA_IDEAS_DB.prepare(
    "SELECT 1 FROM idea_votes WHERE idea_id = ? AND device_id = ?",
  )
    .bind(ideaId, deviceId)
    .first();

  if (existing) {
    await env.STIGLA_IDEAS_DB.prepare("DELETE FROM idea_votes WHERE idea_id = ? AND device_id = ?")
      .bind(ideaId, deviceId)
      .run();
  } else {
    await env.STIGLA_IDEAS_DB.prepare("INSERT INTO idea_votes (idea_id, device_id) VALUES (?, ?)")
      .bind(ideaId, deviceId)
      .run();
  }

  const row = await env.STIGLA_IDEAS_DB.prepare("SELECT COUNT(*) AS votes FROM idea_votes WHERE idea_id = ?")
    .bind(ideaId)
    .first<{ votes: number }>();

  return { votes: row?.votes ?? 0, has_voted: !existing };
}

export async function ideaExists(env: Env, ideaId: number): Promise<boolean> {
  const row = await env.STIGLA_IDEAS_DB.prepare("SELECT 1 FROM ideas WHERE id = ?").bind(ideaId).first();
  return row !== null;
}

export async function listComments(env: Env, ideaId: number): Promise<IdeaCommentDto[]> {
  const { results } = await env.STIGLA_IDEAS_DB.prepare(
    "SELECT id, text, created_at FROM idea_comments WHERE idea_id = ? ORDER BY created_at ASC",
  )
    .bind(ideaId)
    .all<IdeaCommentDto>();
  return results;
}

export async function addComment(env: Env, ideaId: number, deviceId: string, text: string): Promise<IdeaCommentDto> {
  const trimmed = text.trim();
  if (!trimmed) throw new ValidationError("text must not be empty");
  if (trimmed.length > MAX_TEXT_LENGTH) throw new ValidationError(`text must be at most ${MAX_TEXT_LENGTH} chars`);

  const createdAt = new Date().toISOString();
  const { meta } = await env.STIGLA_IDEAS_DB.prepare(
    "INSERT INTO idea_comments (idea_id, device_id, text, created_at) VALUES (?, ?, ?, ?)",
  )
    .bind(ideaId, deviceId, trimmed, createdAt)
    .run();

  return { id: meta.last_row_id as number, text: trimmed, created_at: createdAt };
}

export async function hideIdea(env: Env, ideaId: number): Promise<void> {
  await env.STIGLA_IDEAS_DB.prepare("UPDATE ideas SET hidden = 1 WHERE id = ?").bind(ideaId).run();
}
