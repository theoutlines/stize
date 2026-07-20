-- Analytics model v2 — per-direction line metrics + headway-distribution
-- baseline, recomputed INCREMENTALLY (see aggregate() in src/lib/analytics.ts).
--
-- NOTE ON NUMBERING: 0005_vehicle_fixes belongs to the parallel jam-detection
-- branch (already applied to staging D1). This file takes 0006 so the two merge
-- into a clean 0001..0006 sequence — confirm jam-detection does not also grab
-- 0006 before merging.

-- Which direction of the line a vehicle was on, resolved on the arrivals path
-- (lib/direction.ts) exactly as the map does. Nullable: legacy rows and rows
-- whose direction can't be told stay NULL (bucketed as '' in the aggregate).
ALTER TABLE raw_observations ADD COLUMN direction_route_id TEXT;

-- Superset of agg_line_time: split by direction, and carrying a 12-bucket
-- headway histogram (hb0..hb11) so ANY percentile / "worse-than-usual" baseline
-- is derivable, plus schedule-delay accumulators (columns scaffolded here;
-- populated in a follow-up step). Individual integer histogram columns (not a
-- JSON blob) so the incremental merge is a plain additive UPSERT.
--
-- Headway-bucket upper bounds (seconds), hb0..hb11:
--   <120, <180, <240, <300, <360, <480, <600, <900, <1200, <1800, <3600, >=3600
CREATE TABLE agg_line_dir_time (
  line TEXT NOT NULL,
  direction_route_id TEXT NOT NULL DEFAULT '', -- '' == unknown/unresolved direction
  dow INTEGER NOT NULL,                          -- 0=Sun..6=Sat
  hour INTEGER NOT NULL,                          -- 0..23
  samples INTEGER NOT NULL DEFAULT 0,
  arrivals INTEGER NOT NULL DEFAULT 0,
  headway_count INTEGER NOT NULL DEFAULT 0,
  headway_secs_sum INTEGER NOT NULL DEFAULT 0,
  hb0 INTEGER NOT NULL DEFAULT 0,
  hb1 INTEGER NOT NULL DEFAULT 0,
  hb2 INTEGER NOT NULL DEFAULT 0,
  hb3 INTEGER NOT NULL DEFAULT 0,
  hb4 INTEGER NOT NULL DEFAULT 0,
  hb5 INTEGER NOT NULL DEFAULT 0,
  hb6 INTEGER NOT NULL DEFAULT 0,
  hb7 INTEGER NOT NULL DEFAULT 0,
  hb8 INTEGER NOT NULL DEFAULT 0,
  hb9 INTEGER NOT NULL DEFAULT 0,
  hb10 INTEGER NOT NULL DEFAULT 0,
  hb11 INTEGER NOT NULL DEFAULT 0,
  speed_count INTEGER NOT NULL DEFAULT 0,
  speed_stops_per_min_sum REAL NOT NULL DEFAULT 0,
  sched_delay_count INTEGER NOT NULL DEFAULT 0,      -- populated in the follow-up step
  sched_delay_secs_sum INTEGER NOT NULL DEFAULT 0,   -- populated in the follow-up step
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (line, direction_route_id, dow, hour)
);
CREATE INDEX idx_aldt_line ON agg_line_dir_time(line);

-- Superseded by agg_line_dir_time (folded across directions on the read path).
DROP TABLE agg_line_time;

-- Force the next aggregate run to be a FULL backfill (last_run absent → window
-- starts at 0) so the fresh per-direction table is populated from all retained
-- raw before incremental runs take over.
DELETE FROM agg_state WHERE key = 'last_run';
