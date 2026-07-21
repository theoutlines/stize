-- Upstream request meter — one row per ACTUAL upstream fetch (never a cache hit).
--
-- Powers three things behind the `upstream_budget` flag (see lib/upstreamBudget.ts):
--   1. a shared rolling-hour request budget (live + sweep counted separately) that
--      lets the sentinel sweep back off before the source is overloaded — while the
--      live path is NEVER throttled;
--   2. a degradation breaker that trips on a slow-but-200 source (p95 latency) or a
--      rising share of non-JSON/empty responses, which the old all-failed breaker
--      could not see;
--   3. the /admin/sweep/status observability read-out.
--
-- All isolates write to this ONE table, so the counts/metrics are global to the
-- worker, not per-isolate. Rows are pruned to a short retention (~2h) opportunistically.
-- Kept in D1 (never KV): this is minute-cadence-or-faster machine state and the
-- sweep already writes raw_observations to this same DB (KV vs D1 principle,
-- migration 0007 / feature-flags.md).
CREATE TABLE IF NOT EXISTS upstream_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,          -- unix seconds of the fetch
  kind TEXT NOT NULL,           -- 'live' | 'sweep' — which path issued the fetch
  latency_ms INTEGER NOT NULL,  -- wall-clock of the upstream round-trip
  outcome TEXT NOT NULL         -- 'json' | 'empty' | 'non_json' | 'http_error' | 'network_error'
);

-- Every read filters by a time window, so index the timestamp.
CREATE INDEX IF NOT EXISTS idx_upstream_events_ts ON upstream_events (ts);
