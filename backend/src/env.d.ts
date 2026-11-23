export interface Env {
  STIGLA_KV: KVNamespace;
  /** Tests set "0" so KV writes are visible at once; prod/staging use the default. */
  KV_CACHE_TTL_MS?: string;
  STIGLA_IDEAS_DB: D1Database;
  STIGLA_ANALYTICS_DB: D1Database;
  ASSETS: Fetcher;

  API_VERSION: string;
  // "production" | "staging" — selects per-environment feature-flag defaults.
  ENVIRONMENT: string;

  TRANSIT_SOURCE_BASE_URL: string;
  TRANSIT_SOURCE_FORM_EXTRA_JSON: string;
  SOURCE_USER_AGENT_CONTACT: string;

  ADMIN_TOKEN: string;

  NOMINATIM_USER_AGENT_CONTACT: string;

  ANTHROPIC_API_KEY: string;

  // Feedback triage (Part D). Optional: absent = store-only (D1), no GitHub issue.
  // GITHUB_FEEDBACK_REPO is a non-secret "owner/name" in [vars]; the token is a
  // fine-grained PAT (issues:write on that PRIVATE repo) set via `wrangler secret`.
  GITHUB_FEEDBACK_REPO?: string;
  GITHUB_FEEDBACK_TOKEN?: string;

  // D1 write-budget governor (lib/d1Governor.ts). Both secrets, set via
  // `wrangler secret put`: a Cloudflare API token with ONLY "Account Analytics:
  // Read", and the account id it reads. Absent = the governor logs and does nothing.
  CF_ANALYTICS_API_TOKEN?: string;
  CF_ACCOUNT_ID?: string;

  // Workers Rate Limiting binding for the public write endpoints (/events,
  // /ideas, comments). Optional so tests and older configs without the
  // binding still run: absent = no per-IP limit (the D1 governor still guards).
  WRITE_LIMITER?: RateLimit;
  GEOCODE_LIMITER?: RateLimit;
}

// Workers Rate Limiting API (binding type is not in our workers-types pin).
interface RateLimit {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}
