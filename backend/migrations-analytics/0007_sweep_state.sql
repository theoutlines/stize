-- Sweep durable state (rotation cursor + circuit-breaker) moved OUT of Workers
-- KV into D1.
--
-- Why: the per-minute sentinel sweep (cron `* * * * *`) persisted its state to
-- KV every tick — put(sweep:cursor) + put(sweep:visits) = 2 writes/tick, ~2400
-- writes/day, 2.4× over KV's free 1000-writes/day budget (this triggered the
-- 2026-07-21 "50% daily KV operation limit" alert). D1's write budget is
-- ~100k/day and the sweep ALREADY writes raw_observations to this same DB, so
-- moving its state here makes per-minute persistence trivially cheap.
--
-- `sweep:visits` is dropped entirely (not migrated): adaptive-skip now derives
-- "organic traffic refreshed this sentinel within the current cycle" purely from
-- MAX(observed_at) in raw_observations — less state, one fewer thing to persist.
--
-- KV keeps ONLY the human-flipped knobs: flag:analytics_sweep and
-- config:sweep_interval_{day,night}_seconds. Principle: KV = manual knobs/flags;
-- minute-cadence automation state lives in D1.
CREATE TABLE IF NOT EXISTS sweep_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
