import { describe, expect, it } from "vitest";
import { env } from "cloudflare:test";
import { addComment, createIdea, hideIdea, ideaExists, listComments, listIdeas, toggleVote } from "../src/lib/ideas";

describe("ideas", () => {
  it("creates an idea with zero votes and has_voted false", async () => {
    const idea = await createIdea(env, "device-a", "Add dark mode everywhere");
    expect(idea.votes).toBe(0);
    expect(idea.has_voted).toBe(false);
    expect(idea.text).toBe("Add dark mode everywhere");
  });

  it("rejects empty text", async () => {
    await expect(createIdea(env, "device-rate-1", "   ")).rejects.toThrow();
  });

  it("rate-limits a second idea from the same device", async () => {
    await createIdea(env, "device-b", "First idea");
    await expect(createIdea(env, "device-b", "Second idea too soon")).rejects.toThrow();
  });

  it("toggles a vote on and off, and reflects has_voted per device", async () => {
    const idea = await createIdea(env, "device-c", "Show line color on the map");

    const afterVote = await toggleVote(env, idea.id, "voter-1");
    expect(afterVote.votes).toBe(1);
    expect(afterVote.has_voted).toBe(true);

    const listForVoter = await listIdeas(env, "voter-1");
    const found = listForVoter.find((i) => i.id === idea.id);
    expect(found?.has_voted).toBe(true);
    expect(found?.votes).toBe(1);

    const listForOther = await listIdeas(env, "someone-else");
    const foundOther = listForOther.find((i) => i.id === idea.id);
    expect(foundOther?.has_voted).toBe(false);

    const afterUnvote = await toggleVote(env, idea.id, "voter-1");
    expect(afterUnvote.votes).toBe(0);
    expect(afterUnvote.has_voted).toBe(false);
  });

  it("orders ideas by votes descending", async () => {
    const low = await createIdea(env, "device-d", "Low-vote idea");
    const high = await createIdea(env, "device-e", "High-vote idea");
    await toggleVote(env, high.id, "voter-x");
    await toggleVote(env, high.id, "voter-y");
    await toggleVote(env, low.id, "voter-z");

    const list = await listIdeas(env, "voter-observer");
    const highIndex = list.findIndex((i) => i.id === high.id);
    const lowIndex = list.findIndex((i) => i.id === low.id);
    expect(highIndex).toBeLessThan(lowIndex);
  });

  it("hidden ideas are excluded from the list", async () => {
    const idea = await createIdea(env, "device-f", "Spammy idea");
    expect(await ideaExists(env, idea.id)).toBe(true);

    await hideIdea(env, idea.id);
    const list = await listIdeas(env, "voter-observer-2");
    expect(list.find((i) => i.id === idea.id)).toBeUndefined();
  });

  it("adds and lists comments in chronological order", async () => {
    const idea = await createIdea(env, "device-g", "Idea with comments");
    await addComment(env, idea.id, "commenter-1", "First comment");
    await addComment(env, idea.id, "commenter-2", "Second comment");

    const comments = await listComments(env, idea.id);
    expect(comments.map((c) => c.text)).toEqual(["First comment", "Second comment"]);
  });
});
