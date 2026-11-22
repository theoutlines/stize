-- Jam journal (going live on prod, 2026-11-22). Every 5 minutes the cron
-- records each jam the detector currently shows, one row per day x line x
-- direction (upsert: first/last seen, peak cluster size, peak freeze). It is the
-- calibration record for the preliminary thresholds: what users were actually
-- shown, read via GET /api/v1/admin/jams. WITHOUT ROWID + PK only: 1 written row
-- per active jam per 5 minutes, nothing when the city flows.
CREATE TABLE IF NOT EXISTS jam_journal (
  day TEXT NOT NULL,                -- UTC date
  line TEXT NOT NULL,
  direction_route_id TEXT NOT NULL DEFAULT '',
  first_at INTEGER NOT NULL,        -- unix seconds
  last_at INTEGER NOT NULL,
  max_vehicles INTEGER NOT NULL,
  max_frozen_secs INTEGER NOT NULL,
  has_substitute INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, line, direction_route_id)
) WITHOUT ROWID;
