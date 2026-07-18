-- Product analytics — a separate contour that shares the analytics DB.
--
-- Anonymous behavioural events, by design: NO user-id, NO fingerprint, NO IP,
-- NO precise coordinates, NO free text. Each row is an allow-listed event name,
-- enum-only properties, and a timestamp coarsened to the hour. This is our own
-- pipeline (worker -> D1); nothing leaves for an external analytics vendor.
-- The event/property allow-list lives in src/lib/productAnalytics.ts; the public
-- privacy note lives in README.md. Kept in the transport-analytics DB (not a new
-- one) but strictly separate from raw_observations and its aggregates.
CREATE TABLE product_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event TEXT NOT NULL,           -- allow-listed event name (unknown ones are dropped, never stored)
  props TEXT,                    -- JSON object of enum-only props, or NULL when the event carries none
  session TEXT,                  -- ephemeral in-tab id: random, NOT persisted client-side, NOT an identity;
                                 -- only lets us read funnels (e.g. stop_open -> vehicle_follow). NULL allowed.
  hour_bucket INTEGER NOT NULL   -- unix seconds truncated to the hour (server-stamped on receipt)
);

-- Slice by event x time is the common read (DAU-style counts, media-kit
-- aggregates). A second index on time alone covers day-only rollups.
CREATE INDEX idx_pe_event_time ON product_events(event, hour_bucket);
CREATE INDEX idx_pe_time ON product_events(hour_bucket);
