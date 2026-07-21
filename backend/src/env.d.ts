export interface Env {
  STIGLA_KV: KVNamespace;
  STIGLA_IDEAS_DB: D1Database;
  STIGLA_ANALYTICS_DB: D1Database;
  ASSETS: Fetcher;

  API_VERSION: string;
  // "production" | "staging" — selects per-environment feature-flag defaults.
  ENVIRONMENT: string;

  TRANSIT_SOURCE_BASE_URL: string;
  TRANSIT_SOURCE_API_KEY?: string;
  TRANSIT_SOURCE_FORM_EXTRA_JSON: string;
  SOURCE_USER_AGENT_CONTACT: string;

  ADMIN_TOKEN: string;

  TURNSTILE_SITE_KEY?: string;
  TURNSTILE_SECRET_KEY?: string;

  NOMINATIM_USER_AGENT_CONTACT: string;

  ANTHROPIC_API_KEY: string;

  // Feedback triage (Part D). Optional: absent = store-only (D1), no GitHub issue.
  // GITHUB_FEEDBACK_REPO is a non-secret "owner/name" in [vars]; the token is a
  // fine-grained PAT (issues:write on that PRIVATE repo) set via `wrangler secret`.
  GITHUB_FEEDBACK_REPO?: string;
  GITHUB_FEEDBACK_TOKEN?: string;
}
