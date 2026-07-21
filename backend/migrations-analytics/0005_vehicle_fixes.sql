-- Jam detection — last-fix-per-vehicle bookkeeping (feature/jam-detection).
--
-- A DELIBERATELY STANDALONE, tiny table: one row per live vehicle (`garage_no`),
-- overwritten in place as new fixes arrive. It is NOT history — it holds only the
-- latest known fix and the moment that fix last actually *moved*. That single
-- `moved_at` timestamp is all the jam detector needs to compute a freeze age
-- instantly (Variant B — a user who just opened the app sees an ongoing jam
-- without waiting T_jam minutes to accumulate client-side history).
--
-- It shares the analytics DB for operational convenience but is intentionally
-- UNCOUPLED from raw_observations and its aggregates (no FK, no shared columns,
-- no join): raw_observations is being reshaped concurrently by the
-- citywide-analytics work, and an incident-journal linkage is deferred until both
-- land. Keep this table self-contained.
--
-- Written opportunistically from the existing SWR arrivals refresh (no extra
-- upstream calls), only when `jam_detection_show` is on. Rows are pruned by age.
CREATE TABLE vehicle_fixes (
  garage_no TEXT PRIMARY KEY,       -- live fleet id, e.g. "P80399"
  line TEXT NOT NULL,               -- line number as the feed labels it, e.g. "7L"
  direction_route_id TEXT,          -- resolved travel direction (ArrivalDto.direction_route_id)
  vehicle_type TEXT,                -- the LINE's expected type (bus|tram|trolleybus); the
                                    -- garage-number classifier (bus-on-tram) is applied at read time
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  stops_remaining INTEGER,          -- position-in-route signal; frozen when it stops progressing
  moved_at INTEGER NOT NULL,        -- unix ms — last time the fix moved >=30m OR stops_remaining changed
  seen_at INTEGER NOT NULL,         -- unix ms — last time observed on a fresh board
  board_at INTEGER NOT NULL         -- unix ms — the upstream board's updated_at this fix came from;
                                    -- gates writes so a re-read of the SAME board never bumps moved_at
);

-- The detector reads "vehicles seen recently" and filters by line/type in code;
-- an index on seen_at keeps both the read and the age-based prune cheap.
CREATE INDEX idx_vf_seen ON vehicle_fixes(seen_at);
