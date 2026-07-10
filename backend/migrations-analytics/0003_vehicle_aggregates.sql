-- Per-vehicle history (real vehicles only — rows with a NULL vehicle_id, i.e.
-- junk/placeholder or missing garage numbers, are excluded). Raw seed for the
-- future fleet features: which vehicle runs which line, and its own punctuality.

-- Totals + lifespan for each (vehicle, line) pair.
CREATE TABLE agg_vehicle_line (
  vehicle_id TEXT NOT NULL,
  line TEXT NOT NULL,
  samples INTEGER NOT NULL DEFAULT 0,
  arrivals INTEGER NOT NULL DEFAULT 0,
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (vehicle_id, line)
);

-- The same broken down by day-of-week (0=Sun..6=Sat), plus speed. Compact:
-- ~vehicles × lines-they-run × 7.
CREATE TABLE agg_vehicle_line_dow (
  vehicle_id TEXT NOT NULL,
  line TEXT NOT NULL,
  dow INTEGER NOT NULL,
  samples INTEGER NOT NULL DEFAULT 0,
  arrivals INTEGER NOT NULL DEFAULT 0,
  speed_count INTEGER NOT NULL DEFAULT 0,
  speed_stops_per_min_sum REAL NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (vehicle_id, line, dow)
);

CREATE INDEX idx_avl_line ON agg_vehicle_line(line);
CREATE INDEX idx_avld_line ON agg_vehicle_line_dow(line);
