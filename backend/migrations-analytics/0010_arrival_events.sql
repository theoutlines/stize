-- Analytics v3 (the transport analytics spec (internal)): record arrival events, not boards.
--
-- One row per (5-minute slot, stop, vehicle) the moment a vehicle reaches a stop.
-- WITHOUT ROWID + primary key only, so an insert writes exactly 1 row and an
-- INSERT OR IGNORE duplicate (the same arrival seen on the next refresh) writes 0.
-- The key starts with `slot`, so the aggregator's time-range scan uses it with no
-- secondary index. Kept indefinitely (a delete costs a written row; storage is
-- not the constraint). `raw_observations` stays as a frozen archive.
CREATE TABLE IF NOT EXISTS arrival_events (
  slot INTEGER NOT NULL,                       -- floor(observed_at / 300)
  stop_id TEXT NOT NULL,
  garage_no TEXT NOT NULL,                     -- raw fleet number
  vehicle_id TEXT NOT NULL,                    -- normalised fleet id
  line TEXT NOT NULL,
  direction_route_id TEXT NOT NULL DEFAULT '', -- '' == unresolved
  observed_at INTEGER NOT NULL,                -- unix seconds
  PRIMARY KEY (slot, stop_id, vehicle_id)
) WITHOUT ROWID;
