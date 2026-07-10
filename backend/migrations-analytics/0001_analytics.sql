-- Transport-analytics history (separate DB: stigla-analytics).

-- Raw arrival observations: one row per vehicle-approaching-a-stop seen on a
-- real upstream refresh. We only log what we already fetch to serve the user —
-- no extra calls to the source. Pruned to a rolling window by the aggregator.
CREATE TABLE raw_observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  line TEXT NOT NULL,
  stop_id TEXT NOT NULL,
  garage_no TEXT,               -- vehicle id; needed to derive speed & headways
  eta_minutes INTEGER,
  stops_remaining INTEGER,      -- 0 == at the stop (an arrival event)
  observed_at INTEGER NOT NULL  -- unix seconds
);
CREATE INDEX idx_raw_time ON raw_observations(observed_at);
CREATE INDEX idx_raw_veh ON raw_observations(line, garage_no, stop_id, observed_at);
CREATE INDEX idx_raw_stop ON raw_observations(line, stop_id, observed_at);

-- Rolled-up per-line metrics bucketed by day-of-week (0=Sun..6=Sat) and
-- hour-of-day (0..23). Recomputed from raw by the daily cron. Sums+counts are
-- stored so means are cheap and buckets stay mergeable.
CREATE TABLE agg_line_time (
  line TEXT NOT NULL,
  dow INTEGER NOT NULL,
  hour INTEGER NOT NULL,
  samples INTEGER NOT NULL DEFAULT 0,             -- observation rows
  arrivals INTEGER NOT NULL DEFAULT 0,            -- rows at the stop (stops_remaining=0)
  headway_count INTEGER NOT NULL DEFAULT 0,       -- measured gaps between vehicles
  headway_secs_sum INTEGER NOT NULL DEFAULT 0,    -- for mean real interval
  speed_count INTEGER NOT NULL DEFAULT 0,         -- measured speed samples
  speed_stops_per_min_sum REAL NOT NULL DEFAULT 0,-- for mean stops/min
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (line, dow, hour)
);

-- Small bookkeeping (e.g. last aggregation run).
CREATE TABLE agg_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
