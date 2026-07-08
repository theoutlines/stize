export interface Env {
  STIGLA_KV: KVNamespace;
  STIGLA_IDEAS_DB: D1Database;
  ASSETS: Fetcher;

  API_VERSION: string;

  TRANSIT_SOURCE_BASE_URL: string;
  TRANSIT_SOURCE_API_KEY?: string;
  TRANSIT_SOURCE_FORM_EXTRA_JSON: string;
  SOURCE_USER_AGENT_CONTACT: string;

  ADMIN_TOKEN: string;

  TURNSTILE_SITE_KEY?: string;
  TURNSTILE_SECRET_KEY?: string;

  NOMINATIM_USER_AGENT_CONTACT: string;

  ANTHROPIC_API_KEY: string;
}
