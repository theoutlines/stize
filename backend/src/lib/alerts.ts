import type { Env } from "../env";

const NEWS_LIST_URL = "https://www.bgprevoz.rs/vesti";
const KV_KEY = "route_alerts_v1";
const MAX_AGE_DAYS_AFTER_EXPIRY = 30; // prune alerts this long after valid_until passes
const CLAUDE_MODEL = "claude-haiku-4-5-20251001";

export interface RouteAlert {
  id: string; // the URL slug, stable per announcement
  url: string;
  title: string;
  publishedAt: string; // ISO date, from the list page
  lines: string[];
  stops: string[];
  validFrom: string | null; // ISO date
  validUntil: string | null; // ISO date
  confidence: "line" | "stop";
  summary: string;
}

interface NewsListEntry {
  slug: string;
  url: string;
  title: string;
  publishedAt: string;
}

/** Parses the bgprevoz.rs/vesti list page into title/url/date entries via HTMLRewriter. */
async function fetchNewsList(userAgentContact: string): Promise<NewsListEntry[]> {
  const res = await fetch(NEWS_LIST_URL, {
    headers: { "user-agent": `StiglaApp/0.1 (+${userAgentContact}; personal use, low volume)` },
  });
  if (!res.ok) throw new Error(`bgprevoz.rs/vesti responded ${res.status}`);

  const entries: NewsListEntry[] = [];
  let pendingUrl: string | null = null;
  let pendingTitle = "";
  let collectingTitle = false;
  let collectingDate = false;
  let pendingDate = "";

  const rewriter = new HTMLRewriter()
    .on("h2 a", {
      element(el) {
        pendingUrl = el.getAttribute("href");
        pendingTitle = "";
        collectingTitle = true;
      },
      text(chunk) {
        if (collectingTitle) pendingTitle += chunk.text;
        if (chunk.lastInTextNode) collectingTitle = false;
      },
    })
    .on("h3", {
      element() {
        pendingDate = "";
        collectingDate = true;
      },
      text(chunk) {
        if (collectingDate) pendingDate += chunk.text;
        if (chunk.lastInTextNode) {
          collectingDate = false;
          if (pendingUrl) {
            const slug = pendingUrl.split("/").filter(Boolean).pop() ?? pendingUrl;
            entries.push({
              slug,
              url: pendingUrl,
              title: pendingTitle.trim(),
              publishedAt: parseSerbianDate(pendingDate.trim()),
            });
            pendingUrl = null;
          }
        }
      },
    });

  await rewriter.transform(res).text();
  return entries;
}

/** Fetches a detail page and extracts the plain-text article body. */
async function fetchArticleText(url: string, userAgentContact: string): Promise<string> {
  const res = await fetch(url, {
    headers: { "user-agent": `StiglaApp/0.1 (+${userAgentContact}; personal use, low volume)` },
  });
  if (!res.ok) throw new Error(`${url} responded ${res.status}`);

  const parts: string[] = [];
  const rewriter = new HTMLRewriter()
    .on(".editor p", {
      text(chunk) {
        parts.push(chunk.text);
        if (chunk.lastInTextNode) parts.push("\n");
      },
    })
    .on(".editor li", {
      text(chunk) {
        parts.push(chunk.text);
        if (chunk.lastInTextNode) parts.push("\n");
      },
    });

  await rewriter.transform(res).text();
  return parts.join("").replace(/\n{2,}/g, "\n").trim();
}

/** DD-MM-YYYY (as shown on the site) -> ISO date. Falls back to the raw string if unparsed. */
export function parseSerbianDate(text: string): string {
  const m = text.match(/(\d{2})-(\d{2})-(\d{4})/);
  if (!m) return text;
  const [, day, month, year] = m;
  return `${year}-${month}-${day}`;
}

interface ParsedAnnouncement {
  lines: string[];
  stops: string[];
  valid_from: string | null;
  valid_until: string | null;
  confidence: "line" | "stop";
  summary: string;
}

/**
 * Asks Claude to extract structured {lines, stops, validity period} from a
 * free-form Serbian announcement. Per the project's fallback rule: when the
 * model isn't confident about specific stops, it should report line-level
 * attribution only (confidence: "line"), not guess at stops.
 */
async function parseAnnouncementWithLLM(
  env: Env,
  title: string,
  bodyText: string,
  publishedAt: string,
): Promise<ParsedAnnouncement> {
  const tool = {
    name: "record_route_change",
    description: "Records structured data extracted from a Belgrade public transport route-change announcement.",
    input_schema: {
      type: "object",
      properties: {
        lines: {
          type: "array",
          items: { type: "string" },
          description: "Line numbers affected (e.g. '79', '7L'). Empty if none are clearly named.",
        },
        stops: {
          type: "array",
          items: { type: "string" },
          description:
            "Specific stop names affected, ONLY if you are confident about them. Leave empty if unsure — line-level attribution is safer than a wrong stop.",
        },
        valid_from: {
          type: ["string", "null"],
          description: "ISO date (YYYY-MM-DD) the change takes/took effect, or null if not stated.",
        },
        valid_until: {
          type: ["string", "null"],
          description: "ISO date (YYYY-MM-DD) the change ends, or null if permanent/not stated.",
        },
        confidence: {
          type: "string",
          enum: ["line", "stop"],
          description: "'stop' only if specific stops were confidently extracted; otherwise 'line'.",
        },
        summary: {
          type: "string",
          description: "One short plain-language sentence (in Serbian) summarizing the change for a rider.",
        },
      },
      required: ["lines", "stops", "valid_from", "valid_until", "confidence", "summary"],
    },
  };

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: 1024,
      tools: [tool],
      tool_choice: { type: "tool", name: "record_route_change" },
      messages: [
        {
          role: "user",
          content:
            `Announcement published ${publishedAt} on the Belgrade public transport authority's site.\n\n` +
            `Title: ${title}\n\nBody:\n${bodyText}`,
        },
      ],
    }),
  });

  if (!res.ok) {
    throw new Error(`Claude API responded ${res.status}: ${await res.text()}`);
  }

  const data = (await res.json()) as {
    content: Array<{ type: string; input?: ParsedAnnouncement }>;
  };
  const toolUse = data.content.find((c) => c.type === "tool_use");
  if (!toolUse?.input) throw new Error("Claude did not return a tool_use block");
  return toolUse.input;
}

export async function refreshAlerts(env: Env): Promise<{ added: number; total: number }> {
  const existingRaw = await env.STIGLA_KV.get(KV_KEY);
  const existing: RouteAlert[] = existingRaw ? JSON.parse(existingRaw) : [];
  const existingIds = new Set(existing.map((a) => a.id));

  const list = await fetchNewsList(env.SOURCE_USER_AGENT_CONTACT);
  const newEntries = list.filter((e) => !existingIds.has(e.slug));

  const added: RouteAlert[] = [];
  for (const entry of newEntries) {
    try {
      const bodyText = await fetchArticleText(entry.url, env.SOURCE_USER_AGENT_CONTACT);
      const parsed = await parseAnnouncementWithLLM(env, entry.title, bodyText, entry.publishedAt);
      added.push({
        id: entry.slug,
        url: entry.url,
        title: entry.title,
        publishedAt: entry.publishedAt,
        lines: parsed.lines,
        stops: parsed.stops,
        validFrom: parsed.valid_from,
        validUntil: parsed.valid_until,
        confidence: parsed.confidence,
        summary: parsed.summary,
      });
    } catch (err) {
      console.error(`Failed to process announcement ${entry.url}`, err);
    }
  }

  const cutoff = Date.now() - MAX_AGE_DAYS_AFTER_EXPIRY * 24 * 60 * 60 * 1000;
  const merged = [...added, ...existing].filter((a) => {
    if (!a.validUntil) return true;
    return Date.parse(a.validUntil) >= cutoff;
  });

  await env.STIGLA_KV.put(KV_KEY, JSON.stringify(merged));
  return { added: added.length, total: merged.length };
}

export async function listAlerts(env: Env): Promise<RouteAlert[]> {
  const raw = await env.STIGLA_KV.get(KV_KEY);
  return raw ? JSON.parse(raw) : [];
}
